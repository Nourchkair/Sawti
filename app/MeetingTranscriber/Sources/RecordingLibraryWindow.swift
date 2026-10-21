/// Local recordings dashboard: search saved sessions, review transcripts, and
/// play the audio associated with a library entry.
import AVFoundation
import Combine
import SwiftUI

struct RecordingLibraryWindow: View {
    let outputDirectory: URL
    let jobs: [PipelineJob]
    let onOpenTranscript: (URL) -> Void

    @State private var recordings: [RecordingLibraryItem] = []
    @State private var selectedID: String?
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var activeReloadID: UUID?

    private var entries: [RecordingLibraryItem] {
        var combined = recordings
        for job in jobs {
            if let index = combined.firstIndex(where: { $0.id == job.namingSlug }) {
                combined[index] = combined[index].reflecting(job)
            } else {
                combined.append(.inFlight(job))
            }
        }
        return combined.sorted { $0.recordedAt > $1.recordedAt }
    }

    private var filteredEntries: [RecordingLibraryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter { item in
            [item.title, item.appName ?? "", item.participants.joined(separator: " "), item.statusLabel]
                .joined(separator: " ")
                .lowercased()
                .contains(query)
        }
    }

    private var selectedEntry: RecordingLibraryItem? {
        guard let selectedID else { return nil }
        return filteredEntries.first { $0.id == selectedID }
    }

    private var reloadKey: String {
        let jobKey = jobs.map { job in
            [job.id.uuidString, job.state.rawValue, job.namingSlug ?? "", job.transcriptPath?.path ?? ""]
                .joined(separator: ":")
        }.joined(separator: "|")
        return "\(outputDirectory.path)|\(jobKey)"
    }

    var body: some View {
        NavigationSplitView {
            libraryList
                .navigationTitle("Recordings")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Refresh", systemImage: "arrow.clockwise") {
                            Task { await reload() }
                        }
                        .disabled(isLoading)
                    }
                }
        } detail: {
            if let selectedEntry {
                RecordingLibraryDetail(
                    item: selectedEntry,
                    outputDirectory: outputDirectory,
                    onOpenTranscript: onOpenTranscript,
                )
                .id(selectedEntry.id)
            } else if isLoading {
                ProgressView("Loading recordings…")
            } else if let loadError {
                ContentUnavailableView(
                    "Library Unavailable",
                    systemImage: "externaldrive",
                    description: Text(loadError),
                )
            } else {
                ContentUnavailableView(
                    "Select a Recording",
                    systemImage: "waveform",
                    description: Text("Choose a recording to view its transcript and audio."),
                )
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .task(id: reloadKey) { await reload() }
        .onChange(of: searchText) { _, _ in
            if !filteredEntries.contains(where: { $0.id == selectedID }) {
                selectedID = filteredEntries.first?.id
            }
        }
    }

    private var libraryList: some View {
        VStack(spacing: 0) {
            TextField("Search recordings", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(12)

            if isLoading, entries.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredEntries.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Recordings Yet" : "No Matches",
                    systemImage: searchText.isEmpty ? "waveform" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                        ? "Completed transcripts and saved recordings will appear here."
                        : "Try another title, app, or participant name."),
                )
            } else {
                List(selection: $selectedID) {
                    ForEach(filteredEntries) { item in
                        RecordingLibraryRow(item: item)
                            .tag(Optional(item.id))
                    }
                }
                .listStyle(.sidebar)
            }

            if let loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding([.horizontal, .bottom], 12)
            }
        }
        .frame(minWidth: 250, idealWidth: 300)
    }

    private func reload() async {
        let reloadID = UUID()
        activeReloadID = reloadID
        isLoading = true
        loadError = nil
        do {
            let directory = outputDirectory
            let loaded = try await Task.detached(priority: .utility) {
                try RecordingLibraryIndex.load(outputDirectory: directory)
            }.value
            guard activeReloadID == reloadID else { return }
            recordings = loaded
            if selectedID == nil || !entries.contains(where: { $0.id == selectedID }) {
                selectedID = entries.first?.id
            }
        } catch {
            guard activeReloadID == reloadID else { return }
            loadError = "Sawti could not read the selected output folder. Check its access in Settings → Output."
        }
        guard activeReloadID == reloadID else { return }
        activeReloadID = nil
        isLoading = false
    }
}

private struct RecordingLibraryRow: View {
    let item: RecordingLibraryItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.transcriptURL == nil ? "waveform" : "doc.text")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.recordedAt.formatted(date: .abbreviated, time: .shortened))
                    if let appName = item.appName, !appName.isEmpty {
                        Text("·")
                        Text(appName).lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(item.statusLabel)
                    .font(.caption2)
                    .foregroundStyle(item.error == nil ? Color.secondary : Color.red)
            }
        }
        .padding(.vertical, 3)
        .help(item.title)
    }
}

private struct RecordingLibraryDetail: View {
    let item: RecordingLibraryItem
    let outputDirectory: URL
    let onOpenTranscript: (URL) -> Void

    @StateObject private var playback = RecordingAudioPlayback()
    @State private var transcriptText: String?
    @State private var transcriptLoadFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            transcriptBody
        }
        .task(id: item.transcriptURL) { await loadTranscript() }
        .onDisappear { playback.stop() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
            HStack(spacing: 12) {
                Label(item.recordedAt.formatted(date: .complete, time: .shortened), systemImage: "calendar")
                if let appName = item.appName, !appName.isEmpty {
                    Label(appName, systemImage: "app")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !item.participants.isEmpty {
                Text("Participants: \(item.participants.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                if let audioURL = item.audioURL {
                    Button {
                        if playback.isPlaying {
                            playback.stop()
                        } else {
                            playback.play(audioURL, outputDirectory: outputDirectory)
                        }
                    } label: {
                        Label(
                            playback.isPlaying ? "Stop Audio" : "Play Recording",
                            systemImage: playback.isPlaying ? "stop.fill" : "play.fill",
                        )
                    }
                }
                if let transcriptURL = item.transcriptURL {
                    Button("Open Transcript", systemImage: "arrow.up.right.square") {
                        onOpenTranscript(transcriptURL)
                    }
                }
                if let protocolURL = item.protocolURL {
                    Button("Open Protocol", systemImage: "doc.text") {
                        onOpenTranscript(protocolURL)
                    }
                }
                if let originalURL = item.originalTranscriptURL {
                    Button("Original ASR", systemImage: "text.alignleft") {
                        onOpenTranscript(originalURL)
                    }
                }
            }
            .buttonStyle(.bordered)

            HStack(spacing: 8) {
                Circle()
                    .fill(item.error == nil ? Color.accentColor : Color.red)
                    .frame(width: 7, height: 7)
                Text(item.statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = item.error, !error.isEmpty {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
                }
                if let error = playback.error {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
                }
            }
        }
        .padding(20)
    }

    @ViewBuilder private var transcriptBody: some View {
        if transcriptLoadFailed {
            ContentUnavailableView(
                "Transcript Unavailable",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Sawti could not read this transcript file."),
            )
        } else if let transcriptText {
            ScrollView {
                Text(transcriptText)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(20)
            }
        } else if item.transcriptURL == nil {
            ContentUnavailableView(
                "No Transcript",
                systemImage: "waveform",
                description: Text("This recording was saved without transcription."),
            )
        } else {
            ProgressView("Loading transcript…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loadTranscript() async {
        guard let transcriptURL = item.transcriptURL else {
            transcriptText = nil
            transcriptLoadFailed = false
            return
        }
        let directory = outputDirectory
        let content = await Task.detached(priority: .utility) { () -> String? in
            let openedScope = directory.startAccessingSecurityScopedResource()
            defer {
                if openedScope { directory.stopAccessingSecurityScopedResource() }
            }
            return try? String(contentsOf: transcriptURL, encoding: .utf8)
        }.value
        transcriptText = content
        transcriptLoadFailed = content == nil
    }
}

@MainActor
private final class RecordingAudioPlayback: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var error: String?

    private var player: AVAudioPlayer?
    private var scopedURL: URL?
    private var finishTask: Task<Void, Never>?

    func play(_ audioURL: URL, outputDirectory: URL) {
        stop()
        error = nil
        let accessRoot = Self.isInside(audioURL, directory: outputDirectory) ? outputDirectory : audioURL
        let openedScope = accessRoot.startAccessingSecurityScopedResource()
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: audioURL)
            guard newPlayer.play() else {
                if openedScope { accessRoot.stopAccessingSecurityScopedResource() }
                error = "Sawti could not start audio playback."
                return
            }
            player = newPlayer
            scopedURL = openedScope ? accessRoot : nil
            isPlaying = true
            finishTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(1, newPlayer.duration)))
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        } catch {
            if openedScope { accessRoot.stopAccessingSecurityScopedResource() }
            self.error = "Sawti could not open this audio file."
        }
    }

    func stop() {
        finishTask?.cancel()
        finishTask = nil
        player?.stop()
        player = nil
        isPlaying = false
        if let scopedURL {
            scopedURL.stopAccessingSecurityScopedResource()
            self.scopedURL = nil
        }
    }

    private static func isInside(_ file: URL, directory: URL) -> Bool {
        let filePath = file.standardizedFileURL.path
        let directoryPath = directory.standardizedFileURL.path
        let directoryPrefix = directoryPath.hasSuffix("/") ? directoryPath : directoryPath + "/"
        return filePath == directoryPath || filePath.hasPrefix(directoryPrefix)
    }
}
