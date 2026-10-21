import AppKit
import ArgumentParser
import AVFoundation
import Foundation
import IOKit.pwr_mgt

@main
struct MeetingSimulator: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "meeting-simulator",
        abstract: "Synthetic meeting trigger for the dev app's auto-detect path.",
        discussion: """
        Pops a window with a MeetingDetector-matching title and creates the same
        IOKit power assertion a real Teams / Zoom call would. Plays the fixture
        WAV through the system output so the CATapDescription tap captures real
        audio. With --silent, the fixture is played at volume=0 so the audio
        device stays active but the tap captures only zero-content buffers —
        used by scripts/e2e-silent-recording.sh to exercise the
        SilentRecordingMonitor path end-to-end.
        """,
    )

    @Argument(help: "Path to fixture WAV. Defaults to the repo's two_speakers_de.wav.")
    var audioPath: String?

    @Option(name: .long, help: """
    Window title the simulated meeting window shows. Detection fires off the
    power assertion regardless; this title is what the app's title lookup sees,
    so it drives the resulting meeting title / output filename. Default matches
    the MeetingSimulator meeting pattern. Set to "MeetingSimulator" (the app
    name) to exercise the no-usable-title placeholder path.
    """)
    var title: String = "Simulator Meeting | MeetingSimulator"

    @Flag(help: """
    Play the fixture at volume=0 so the audio device stays active but produces
    zero-content buffers. Without this the CATapDescription tap has no producer
    and gets no IOProc callbacks, so the recording file ends up zero bytes.
    """)
    var silent = false

    @Option(name: .long, help: """
    Auto-terminate after N seconds. Defaults: audio duration + 2 s (without
    --silent) or 60 s (with --silent, where there's no
    audioPlayerDidFinishPlaying callback to drive the natural exit).
    """)
    var duration: Double?

    @Option(name: .long, help: """
    Wait N seconds after showing the meeting window and starting its power
    assertion before playing the fixture. Useful for verifying that capture
    has attached before the first spoken audio begins. Defaults to 0.
    """)
    var playbackDelay: Double = 0

    @Flag(help: """
    Keep replaying the fixture instead of exiting when it ends. Audible mode
    normally exits through `audioPlayerDidFinishPlaying`, which caps a meeting
    at the fixture's length; a lane that has to outlast a detection threshold
    plus two assertion phases needs more than that. Implies the silent mode's
    default --duration, since the finish callback no longer fires.
    """)
    var loop = false

    func validate() throws {
        if let duration, duration <= 0 {
            throw ValidationError("--duration must be a positive number of seconds, got \(duration).")
        }
        if !playbackDelay.isFinite || playbackDelay < 0 {
            throw ValidationError("--playback-delay must be a finite non-negative number, got \(playbackDelay).")
        }
        if let duration, duration <= playbackDelay {
            throw ValidationError("--duration must exceed --playback-delay so playback can start before the simulator closes.")
        }
    }

    func run() {
        let fixturePath = audioPath ?? Self.findFixture()
        let windowTitle = title
        let silentMode = silent
        let dur = duration
        let looping = loop
        let delay = playbackDelay
        MainActor.assumeIsolated {
            runSimulator(
                fixturePath: fixturePath, windowTitle: windowTitle,
                playback: SimulatorPlaybackOptions(
                    silent: silentMode, loop: looping, duration: dur, playbackDelay: delay,
                ),
            )
        }
    }

    /// Locate the repo's bundled fixture WAV.
    ///
    /// `#filePath` resolves to the absolute path of this source file at
    /// compile time, so walking up from it lands at the repo root regardless
    /// of where the binary is later executed — works for both `swift run`
    /// in the package dir and a built binary copied elsewhere, as long as
    /// the source was compiled from the repo checkout.
    private static let fixtureRepoRelativePath = "app/MeetingTranscriber/Tests/Fixtures/two_speakers_de.wav"

    private static func findFixture() -> String {
        // Walk Sources/ → meeting-simulator/ → tools/ → repo root. The
        // fourth deletion is the one that actually lands at the repo
        // root; without it we'd end up at `tools/` and append a path
        // that has never existed.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fromSource = repoRoot.appendingPathComponent(fixtureRepoRelativePath)
        if FileManager.default.fileExists(atPath: fromSource.path) {
            return fromSource.path
        }
        // Fallback for binaries run from the repo root.
        if FileManager.default.fileExists(atPath: fixtureRepoRelativePath) {
            return fixtureRepoRelativePath
        }
        FileHandle.standardError.write(Data(
            "ERROR: Fixture not found at \(fromSource.path) or \(fixtureRepoRelativePath)\n".utf8,
        ))
        FileHandle.standardError.write(Data(
            "Pass the audio path as the first positional argument, or `--help` for usage.\n".utf8,
        ))
        Self.exit(withError: ExitCode.failure)
    }
}

// MARK: - Simulator runtime

/// Default --duration when --silent is set, since silent mode has no
/// `audioPlayerDidFinishPlaying` to drive a natural exit.
private let defaultSilentDuration: Double = 60

private struct SimulatorPlaybackOptions {
    let silent: Bool
    let loop: Bool
    let duration: Double?
    let playbackDelay: Double
}

/// AppKit lifecycle isn't reentrant — `NSApplication.shared.run()` blocks
/// forever once started. This runs the whole window + audio + assertion
/// dance from inside ArgumentParser's `run()` and never returns.
@MainActor
private func runSimulator(fixturePath: String, windowTitle: String, playback: SimulatorPlaybackOptions) {
    // Fail fast before any AppKit / IOKit state is created.
    guard FileManager.default.fileExists(atPath: fixturePath) else {
        FileHandle.standardError.write(Data("ERROR: Audio file not found: \(fixturePath)\n".utf8))
        exit(1)
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let (window, label) = buildMeetingWindow(title: windowTitle)
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)

    let assertionID = createPowerAssertion()
    print("Window: \"\(windowTitle)\"")
    print("PID: \(ProcessInfo.processInfo.processIdentifier)")
    print(playback.silent ? "Audio: <silent mode — zero-volume playback>" : "Audio: \(fixturePath)")
    if playback.playbackDelay > 0 {
        print("Playback starts after \(String(format: "%.1f", playback.playbackDelay))s.")
    }
    print("Leave button visible for AX verification")

    let delegate = AppDelegate(assertionID: assertionID)
    app.delegate = delegate
    window.delegate = delegate

    // Non-silent mode without an explicit --duration exits via the audio
    // player's finish callback, so its effective duration is nil. Looping
    // removes that callback, so it needs the timed exit silent mode uses.
    let effectiveDuration = playback.duration ?? ((playback.silent || playback.loop) ? defaultSilentDuration + playback.playbackDelay : nil)
    let playbackMode = PlaybackMode(
        silent: playback.silent, loop: playback.loop, timedDuration: effectiveDuration ?? defaultSilentDuration,
    )
    if playback.playbackDelay > 0 {
        // Open CoreAudio before advertising the simulated meeting. Sawti's
        // process tap must translate the simulator PID to an AudioObjectID
        // when the meeting is detected. If AVAudioPlayer is created only
        // after the delay, recording can fail with "Failed to translate any
        // PIDs to audio objects". A near-silent tone activates the process
        // audio stream without playing fixture speech before the start time.
        prepareWarmupPlayback(delegate: delegate)
        label.stringValue = "Waiting to play audio\n(\(String(format: "%.0f", playback.playbackDelay))s)"
        DispatchQueue.main.asyncAfter(deadline: .now() + playback.playbackDelay) {
            MainActor.assumeIsolated {
                print("Playback delay elapsed — starting fixture audio.")
                startPlayback(fixturePath: fixturePath, mode: playbackMode, label: label, delegate: delegate)
                delegate.stopWarmupPlayback()
            }
        }
    } else {
        startPlayback(fixturePath: fixturePath, mode: playbackMode, label: label, delegate: delegate)
    }

    if let effectiveDuration {
        DispatchQueue.main.asyncAfter(deadline: .now() + effectiveDuration) {
            MainActor.assumeIsolated {
                print("Duration elapsed — closing.")
                NSApplication.shared.terminate(nil)
            }
        }
    }

    app.run()
}

/// Builds the window + content view + Teams-style toolbar. Returns the
/// window and the status label so callers can update it during playback.
@MainActor
private func buildMeetingWindow(title: String) -> (NSWindow, NSTextField) {
    let window = NSWindow(
        contentRect: NSRect(x: 200, y: 200, width: 800, height: 600),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false,
    )
    window.title = title
    window.isReleasedWhenClosed = false

    let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

    let label = NSTextField(labelWithString: "Loading audio...")
    label.font = .systemFont(ofSize: 24)
    label.alignment = .center
    label.frame = NSRect(x: 50, y: 300, width: 700, height: 100)
    contentView.addSubview(label)

    let toolbar = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 60))
    toolbar.wantsLayer = true
    toolbar.layer?.backgroundColor = NSColor.darkGray.cgColor

    let muteBtn = NSButton(title: "Mute", target: nil, action: nil)
    muteBtn.frame = NSRect(x: 200, y: 15, width: 80, height: 30)
    muteBtn.setAccessibilityLabel("Mute")
    toolbar.addSubview(muteBtn)

    let cameraBtn = NSButton(title: "Camera", target: nil, action: nil)
    cameraBtn.frame = NSRect(x: 300, y: 15, width: 80, height: 30)
    toolbar.addSubview(cameraBtn)

    let shareBtn = NSButton(title: "Share", target: nil, action: nil)
    shareBtn.frame = NSRect(x: 400, y: 15, width: 80, height: 30)
    toolbar.addSubview(shareBtn)

    let leaveBtn = NSButton(title: "Leave", target: nil, action: #selector(AppDelegate.leaveClicked))
    leaveBtn.frame = NSRect(x: 520, y: 15, width: 80, height: 30)
    leaveBtn.bezelColor = .systemRed
    leaveBtn.setAccessibilityLabel("Leave")
    leaveBtn.setAccessibilityIdentifier("leave-call")
    toolbar.addSubview(leaveBtn)

    contentView.addSubview(toolbar)
    window.contentView = contentView
    return (window, label)
}

/// Creates the same IOKit "prevent display sleep" assertion a real Teams /
/// Zoom call creates; `PowerAssertionDetector` picks it up via
/// `IOPMCopyAssertionsByProcess`. Returns the assertion ID so `AppDelegate`
/// can release it on termination.
private func createPowerAssertion() -> IOPMAssertionID {
    var assertionID: IOPMAssertionID = 0
    let result = IOPMAssertionCreateWithName(
        "PreventUserIdleDisplaySleep" as CFString,
        IOPMAssertionLevel(kIOPMAssertionLevelOn),
        "Simulator Meeting Call in progress" as CFString,
        &assertionID,
    )
    if result == kIOReturnSuccess {
        print("Power assertion created (ID: \(assertionID))")
    } else {
        print("WARNING: Could not create power assertion (status: \(result))")
    }
    return assertionID
}

/// How the fixture is played. One value rather than three arguments because
/// the three answer one question, and two of them only mean anything together:
/// looping and silent playback both remove the finish callback, which is what
/// makes the timed exit the only way out.
private struct PlaybackMode {
    let silent: Bool
    let loop: Bool
    /// Only consulted when there is no finish callback to exit on.
    let timedDuration: Double
}

@MainActor
private func prepareWarmupPlayback(delegate: AppDelegate) {
    do {
        let warmupURL = try writeWarmupTone()
        let player = try AVAudioPlayer(contentsOf: warmupURL)
        player.delegate = delegate
        // -86 dB relative to the full-scale tone: enough to keep CoreAudio's
        // output stream active, while inaudible in normal use.
        player.volume = 0.0001
        player.numberOfLoops = -1
        player.prepareToPlay()
        player.play()
        delegate.warmupPlayer = player
        delegate.warmupURL = warmupURL
        print("Near-silent CoreAudio warm-up started for delayed fixture mode.")
    } catch {
        print("ERROR: Could not prepare CoreAudio warm-up: \(error)")
    }
}

private func writeWarmupTone() throws -> URL {
    let sampleRate: UInt32 = 48000
    let frameCount = Int(sampleRate)
    let bytesPerSample: UInt16 = 2
    let dataSize = UInt32(frameCount) * UInt32(bytesPerSample)
    var wave = Data()
    wave.append(contentsOf: "RIFF".utf8)
    wave.appendLittleEndian(36 + dataSize)
    wave.append(contentsOf: "WAVEfmt ".utf8)
    wave.appendLittleEndian(UInt32(16))
    wave.appendLittleEndian(UInt16(1))
    wave.appendLittleEndian(UInt16(1))
    wave.appendLittleEndian(sampleRate)
    wave.appendLittleEndian(sampleRate * UInt32(bytesPerSample))
    wave.appendLittleEndian(bytesPerSample)
    wave.appendLittleEndian(UInt16(16))
    wave.append(contentsOf: "data".utf8)
    wave.appendLittleEndian(dataSize)
    for frame in 0 ..< frameCount {
        let phase = 2 * Double.pi * 440 * Double(frame) / Double(sampleRate)
        let sample = Int16(sin(phase) * 16384)
        wave.appendLittleEndian(sample)
    }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sawti-meeting-simulator-warmup-\(UUID().uuidString).wav")
    try wave.write(to: url, options: .atomic)
    return url
}

private extension Data {
    mutating func appendLittleEndian(_ value: some FixedWidthInteger) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

@MainActor
private func startPlayback(
    fixturePath: String,
    mode: PlaybackMode,
    label: NSTextField,
    delegate: AppDelegate,
) {
    let audioURL = URL(fileURLWithPath: fixturePath)
    do {
        let player = try AVAudioPlayer(contentsOf: audioURL)
        player.delegate = delegate
        if mode.silent {
            // Volume=0 + loop forever keeps the audio device active so the
            // CATapDescription tap fires its IOProc and captures
            // zero-content buffers. Skipping playback entirely (no
            // `AVAudioPlayer` at all) leaves the device with no producer —
            // the tap stays subscribed but gets no callbacks, and the
            // recording file ends up zero bytes.
            player.volume = 0
            player.numberOfLoops = -1
            let seconds = Int(mode.timedDuration)
            label.stringValue = "SILENT MODE\n(zero-volume playback, \(seconds)s)"
            print("Silent mode: playing fixture at volume=0 for \(seconds)s.")
        } else {
            player.volume = 1
            player.numberOfLoops = mode.loop ? -1 : 0
            label.stringValue = "Playing \(audioURL.lastPathComponent)\n"
                + "(\(String(format: "%.0f", player.duration))s\(mode.loop ? ", looping" : ""))"
            print("Playing audio (\(String(format: "%.1f", player.duration))s)...")
            print(mode.loop ? "Looping until --duration elapses." : "Window closes automatically after playback.")
        }
        player.prepareToPlay()
        player.play()
        delegate.audioPlayer = player
    } catch {
        print("ERROR: Could not play audio: \(error)")
        label.stringValue = "Audio error: \(error.localizedDescription)"
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, AVAudioPlayerDelegate {
    let assertionID: IOPMAssertionID
    var audioPlayer: AVAudioPlayer?
    var warmupPlayer: AVAudioPlayer?
    var warmupURL: URL?

    init(assertionID: IOPMAssertionID) {
        self.assertionID = assertionID
    }

    func applicationWillTerminate(_: Notification) {
        stopWarmupPlayback()
        IOPMAssertionRelease(assertionID)
    }

    func stopWarmupPlayback() {
        warmupPlayer?.stop()
        warmupPlayer = nil
        if let warmupURL {
            try? FileManager.default.removeItem(at: warmupURL)
            self.warmupURL = nil
        }
    }

    func windowWillClose(_: Notification) {
        print("Window closed — exiting.")
        NSApplication.shared.terminate(nil)
    }

    nonisolated func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully _: Bool) {
        print("Audio finished — closing in 2s.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            MainActor.assumeIsolated {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    @objc
    func leaveClicked() {
        print("Leave clicked — closing.")
        NSApplication.shared.terminate(nil)
    }
}
