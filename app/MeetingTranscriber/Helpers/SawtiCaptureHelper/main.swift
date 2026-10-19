import AudioTapLib
@preconcurrency import AVFoundation
import Darwin
import Dispatch
import Foundation

private struct CaptureHelperOptions {
    let outputURL: URL
    let deviceUID: String?

    static func parse(_ arguments: [String]) -> CaptureHelperOptions? {
        var outputPath: String?
        var deviceUID: String?
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--output":
                index += 1
                guard index < arguments.count, outputPath == nil else { return nil }
                outputPath = arguments[index]
            case "--device-uid":
                index += 1
                guard index < arguments.count, deviceUID == nil else { return nil }
                deviceUID = arguments[index]
            default:
                return nil
            }
            index += 1
        }
        guard let outputPath, !outputPath.isEmpty else { return nil }
        return CaptureHelperOptions(
            outputURL: URL(fileURLWithPath: outputPath),
            deviceUID: deviceUID,
        )
    }
}

private struct CaptureHelperEvent: Encodable {
    let type: String
    var code: String?
    var levelDBFS: Double?
    var secondsSinceLastBuffer: Double?
    var secondsSinceLastEnergy: Double?
}

@MainActor
private final class CaptureHelperRuntime {
    private let capture: MicCaptureHandler
    private let outputLock = NSLock()
    private var finished = false

    init(capture: MicCaptureHandler) {
        self.capture = capture
    }

    func send(_ event: CaptureHelperEvent) {
        guard let data = try? JSONEncoder().encode(event) else { return }
        outputLock.lock()
        defer { outputLock.unlock() }
        do {
            try FileHandle.standardOutput.write(contentsOf: data + Data([0x0A]))
        } catch {
            // The parent may have exited. Keep capture alive until stdin closes
            // so the audio file still gets a chance to finalize cleanly.
        }
    }

    func reportHealth() {
        let ages = capture.currentSignalAges
        send(CaptureHelperEvent(
            type: "health",
            levelDBFS: capture.currentLevelDBFS,
            secondsSinceLastBuffer: ages.secondsSinceLastBuffer,
            secondsSinceLastEnergy: ages.secondsSinceLastEnergy,
        ))
    }

    func finish() {
        guard !finished else { return }
        finished = true
        capture.stop()
        send(CaptureHelperEvent(type: "stopped"))
        exit(0)
    }
}

@main
private struct SawtiCaptureHelper {
    @MainActor
    static func main() {
        signal(SIGPIPE, SIG_IGN)
        guard let options = CaptureHelperOptions.parse(Array(CommandLine.arguments)) else {
            emitEarlyError("invalid_arguments")
            exit(64)
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            emitEarlyError("microphone_permission_not_granted")
            exit(77)
        }
        do {
            try FileManager.default.createDirectory(
                at: options.outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            guard !FileManager.default.fileExists(atPath: options.outputURL.path) else {
                emitEarlyError("output_already_exists")
                exit(73)
            }
            let capture = MicCaptureHandler(outputURL: options.outputURL)
            try capture.start(deviceUID: options.deviceUID)
            let runtime = CaptureHelperRuntime(capture: capture)
            capture.onGiveUp = {
                DispatchQueue.main.async {
                    runtime.send(CaptureHelperEvent(type: "gave_up"))
                }
            }
            runtime.send(CaptureHelperEvent(type: "ready"))

            let input = DispatchSource.makeReadSource(
                fileDescriptor: STDIN_FILENO,
                queue: DispatchQueue.global(qos: .userInitiated),
            )
            input.setEventHandler {
                var bytes = [UInt8](repeating: 0, count: 64)
                let count = Darwin.read(STDIN_FILENO, &bytes, bytes.count)
                let command = String(decoding: bytes.prefix(max(count, 0)), as: UTF8.self)
                if count <= 0 || command.contains("STOP") {
                    DispatchQueue.main.async { runtime.finish() }
                }
            }
            input.resume()

            let healthTimer = DispatchSource.makeTimerSource(queue: .main)
            healthTimer.schedule(deadline: .now() + 1, repeating: 1)
            healthTimer.setEventHandler { runtime.reportHealth() }
            healthTimer.resume()

            dispatchMain()
        } catch {
            emitEarlyError("microphone_capture_start_failed")
            exit(70)
        }
    }

    private static func emitEarlyError(_ code: String) {
        guard let data = try? JSONEncoder().encode(CaptureHelperEvent(type: "error", code: code)) else { return }
        try? FileHandle.standardOutput.write(contentsOf: data + Data([0x0A]))
    }
}
