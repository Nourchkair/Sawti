/// Non-destructive audio trimming and splitting for a Library recording.
import AVFoundation
import SwiftUI

struct RecordingAudioEditorSheet: View {
    let item: RecordingLibraryItem
    let sourceURL: URL
    let outputDirectory: URL
    let onSave: ([RecordingEditedAudio]) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var duration: TimeInterval = 0
    @State private var startOffset: TimeInterval = 0
    @State private var endOffset: TimeInterval = 0
    @State private var splitOffset: TimeInterval = 0
    @State private var isPreparing = true
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var validTrim: Bool {
        startOffset >= 0 && endOffset <= duration && endOffset - startOffset >= 0.25
    }

    private var validSplit: Bool {
        validTrim && splitOffset > startOffset + 0.1 && splitOffset < endOffset - 0.1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Edit Recording Audio")
                    .font(.title2.weight(.semibold))
                Text("Sawti keeps the original audio unchanged and saves edited copies with this recording.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if isPreparing {
                ProgressView("Reading audio duration…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Original length: \(duration.formatted(.number.precision(.fractionLength(1)))) seconds")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                timeControl(title: "Start", value: $startOffset)
                timeControl(title: "End", value: $endOffset)
                Divider()
                timeControl(title: "Split at", value: $splitOffset)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                if isWorking {
                    ProgressView("Creating edited audio…")
                }

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(isWorking)
                    Button("Save Trimmed Copy") {
                        Task { await saveTrimmedCopy() }
                    }
                    .disabled(isWorking || !validTrim)
                    Button("Split into Two Clips") {
                        Task { await splitIntoClips() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking || !validSplit)
                }
            }
        }
        .padding(22)
        .frame(minWidth: 620, minHeight: 360)
        .task { await loadDuration() }
    }

    private func timeControl(title: String, value: Binding<TimeInterval>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 70, alignment: .leading)
            Slider(value: value, in: 0...max(duration, 0.1))
            TextField("Seconds", value: value, format: .number.precision(.fractionLength(1)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 86)
        }
    }

    private func loadDuration() async {
        let openedScope = outputDirectory.startAccessingSecurityScopedResource()
        defer { if openedScope { outputDirectory.stopAccessingSecurityScopedResource() } }
        do {
            let asset = AVURLAsset(url: sourceURL)
            let time = try await asset.load(.duration)
            let loadedDuration = time.seconds
            guard loadedDuration.isFinite, loadedDuration > 0 else {
                throw RecordingAudioEditorError.invalidDuration
            }
            duration = loadedDuration
            endOffset = loadedDuration
            splitOffset = loadedDuration / 2
        } catch {
            errorMessage = "Sawti could not read this recording’s duration."
        }
        isPreparing = false
    }

    private func saveTrimmedCopy() async {
        isWorking = true
        errorMessage = nil
        let editID = UUID()
        let filename = "\(item.id)_edit_\(editID.uuidString).m4a"
        let outputURL = outputDirectory
            .appendingPathComponent("recordings", isDirectory: true)
            .appendingPathComponent(filename)
        let asset = RecordingEditedAudio(
            id: editID,
            title: "Trimmed Copy",
            filename: filename,
            kind: .trimmed,
            startOffset: startOffset,
            endOffset: endOffset,
        )

        do {
            try await export(start: startOffset, end: endOffset, to: outputURL)
            guard onSave(item.editedAudio + [asset]) else {
                try? FileManager.default.removeItem(at: outputURL)
                throw RecordingAudioEditorError.couldNotSave
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func splitIntoClips() async {
        isWorking = true
        errorMessage = nil
        let firstID = UUID()
        let secondID = UUID()
        let firstName = "\(item.id)_edit_\(firstID.uuidString).m4a"
        let secondName = "\(item.id)_edit_\(secondID.uuidString).m4a"
        let recordingsDirectory = outputDirectory.appendingPathComponent("recordings", isDirectory: true)
        let firstURL = recordingsDirectory.appendingPathComponent(firstName)
        let secondURL = recordingsDirectory.appendingPathComponent(secondName)
        let first = RecordingEditedAudio(
            id: firstID,
            title: "Part 1",
            filename: firstName,
            kind: .splitPart,
            startOffset: startOffset,
            endOffset: splitOffset,
        )
        let second = RecordingEditedAudio(
            id: secondID,
            title: "Part 2",
            filename: secondName,
            kind: .splitPart,
            startOffset: splitOffset,
            endOffset: endOffset,
        )

        do {
            try await export(start: first.startOffset, end: first.endOffset, to: firstURL)
            try await export(start: second.startOffset, end: second.endOffset, to: secondURL)
            guard onSave(item.editedAudio + [first, second]) else {
                throw RecordingAudioEditorError.couldNotSave
            }
            dismiss()
        } catch {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func export(start: TimeInterval, end: TimeInterval, to outputURL: URL) async throws {
        guard end > start else { throw RecordingAudioEditorError.invalidRange }
        let openedScope = outputDirectory.startAccessingSecurityScopedResource()
        defer { if openedScope { outputDirectory.stopAccessingSecurityScopedResource() } }
        let directory = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let asset = AVURLAsset(url: sourceURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw RecordingAudioEditorError.exportUnavailable
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600),
        )

        let session = RecordingExportSessionBox(exporter)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.value.exportAsynchronously {
                switch session.value.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: RecordingAudioEditorError.cancelled)
                case .failed:
                    continuation.resume(throwing: session.value.error ?? RecordingAudioEditorError.exportFailed)
                default:
                    continuation.resume(throwing: RecordingAudioEditorError.exportFailed)
                }
            }
        }
        try FileManager.default.restrictToOwner(outputURL)
    }
}

/// AVFoundation calls the completion on its export queue. The session is only
/// read after that callback signals completion, so the box safely crosses the
/// callback's Sendable boundary without exposing the session elsewhere.
private final class RecordingExportSessionBox: @unchecked Sendable {
    let value: AVAssetExportSession

    init(_ value: AVAssetExportSession) {
        self.value = value
    }
}

private enum RecordingAudioEditorError: LocalizedError {
    case invalidDuration
    case invalidRange
    case exportUnavailable
    case exportFailed
    case cancelled
    case couldNotSave

    var errorDescription: String? {
        switch self {
        case .invalidDuration: "This recording has no usable audio duration."
        case .invalidRange: "Choose a valid audio range."
        case .exportUnavailable: "Sawti could not prepare an audio editor for this file."
        case .exportFailed: "Sawti could not export this audio copy."
        case .cancelled: "The audio export was cancelled."
        case .couldNotSave: "The edited copy was created, but Sawti could not attach it to the recording."
        }
    }
}
