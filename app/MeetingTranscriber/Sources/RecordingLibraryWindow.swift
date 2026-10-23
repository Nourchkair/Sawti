/// Local recordings dashboard: search saved sessions, review transcripts, and
/// play the audio associated with a library entry.
import AVFoundation
import Combine
import SwiftUI

struct RecordingLibraryWindow: View {
    let outputDirectory: URL
    let jobs: [PipelineJob]
    let onOpenTranscript: (URL) -> Void
    let onImportMedia: () -> Void
    let onTranscribe: ([URL]) -> Void

    @State private var recordings: [RecordingLibraryItem] = []
    @State private var selectedID: String?
    @State private var searchText = ""
    @State private var categoryFilter = RecordingCategoryFilter.all
    @State private var sourceFilter = RecordingSourceFilter.all
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var activeReloadID: UUID?
    @State private var transcriptSearchIndex: [String: String] = [:]

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
        return entries.filter { item in
            let categoryMatches: Bool
            switch categoryFilter {
            case .all: categoryMatches = true
            case .unassigned: categoryMatches = item.category?.isEmpty != false
            case let .named(category): categoryMatches = item.category == category
            }
            guard categoryMatches, sourceFilter.matches(item.recordingSource) else { return false }
            guard !query.isEmpty else { return true }
            let metadata = [item.title, item.appName ?? "", item.participants.joined(separator: " "),
                            item.category ?? "", item.statusLabel]
                .joined(separator: " ").lowercased()
            return metadata.contains(query) || (transcriptSearchIndex[item.id] ?? "").contains(query)
        }
    }

    private var availableCategories: [String] {
        Array(Set(entries.compactMap(\.category).filter { !$0.isEmpty })).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
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

    private func isTranscribing(_ item: RecordingLibraryItem) -> Bool {
        let sourcePaths = Set(item.transcriptionURLs(outputDirectory: outputDirectory).map {
            $0.standardizedFileURL.path
        })
        return jobs.contains { job in
            guard !job.state.isTerminal else { return false }
            return [job.mixPath, job.appPath, job.micPath].compactMap(\.self).contains {
                sourcePaths.contains($0.standardizedFileURL.path)
            } || job.namingSlug == item.id
        }
    }

    var body: some View {
        NavigationSplitView {
            libraryList
                .navigationTitle("Library")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Import Media…", systemImage: "tray.and.arrow.down") {
                            onImportMedia()
                        }
                    }
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
                    onTranscribe: onTranscribe,
                    isTranscribing: isTranscribing(selectedEntry),
                    onCategoryChanged: { category in updateCategory(for: selectedEntry, to: category) },
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
        .onChange(of: categoryFilter) { _, _ in
            if !filteredEntries.contains(where: { $0.id == selectedID }) {
                selectedID = filteredEntries.first?.id
            }
        }
        .onChange(of: sourceFilter) { _, _ in
            if !filteredEntries.contains(where: { $0.id == selectedID }) {
                selectedID = filteredEntries.first?.id
            }
        }
    }

    private var libraryList: some View {
        VStack(spacing: 0) {
            TextField("Search recordings and transcripts", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(12)

            Picker("Type", selection: $sourceFilter) {
                ForEach(RecordingSourceFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .padding([.horizontal, .bottom], 8)

            Picker("Category", selection: $categoryFilter) {
                Text("All Categories").tag(RecordingCategoryFilter.all)
                Text("Unassigned").tag(RecordingCategoryFilter.unassigned)
                ForEach(availableCategories, id: \.self) { category in
                    Text(category).tag(RecordingCategoryFilter.named(category))
                }
            }
            .padding([.horizontal, .bottom], 10)

            if isLoading, entries.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredEntries.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "Library Is Empty" : "No Matches",
                    systemImage: searchText.isEmpty ? "waveform" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                        ? "Saved meetings, microphone and app recordings, and imported media will appear here. Use Import Media to add a file."
                        : "Try another title, participant, category, or phrase from a transcript."),
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
            transcriptSearchIndex = await Task.detached(priority: .utility) {
                let openedScope = directory.startAccessingSecurityScopedResource()
                defer { if openedScope { directory.stopAccessingSecurityScopedResource() } }
                return Dictionary(uniqueKeysWithValues: loaded.map { item in
                    let urls = [item.transcriptURL, item.originalTranscriptURL].compactMap { $0 }
                    let text = urls.compactMap { url -> String? in
                        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                        let corrected = TranscriptEditorDocumentStore.correctedTranscript(for: url)
                        return [corrected ?? source, source].joined(separator: "\n")
                    }.joined(separator: "\n")
                    return (item.id, text.lowercased())
                })
            }.value
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

    private func updateCategory(for item: RecordingLibraryItem, to category: String) {
        do {
            try RecordingLibraryIndex.updateCategory(for: item, category: category, outputDirectory: outputDirectory)
            let normalized = category.trimmingCharacters(in: .whitespacesAndNewlines)
            if let index = recordings.firstIndex(where: { $0.id == item.id }) {
                let old = recordings[index]
                recordings[index] = RecordingLibraryItem(
                    id: old.id, title: old.title, recordedAt: old.recordedAt, appName: old.appName,
                    participants: old.participants, category: normalized.isEmpty ? nil : normalized,
                    recordingSource: old.recordingSource,
                    bookmarks: old.bookmarks, transcriptURL: old.transcriptURL,
                    originalTranscriptURL: old.originalTranscriptURL, protocolURL: old.protocolURL,
                    audioURL: old.audioURL, pipelineStatus: old.pipelineStatus, error: old.error,
                )
            }
        } catch {
            loadError = "Sawti could not save this category. Check access to the output folder."
        }
    }
}

private enum RecordingCategoryFilter: Hashable {
    case all
    case unassigned
    case named(String)
}

private enum RecordingSourceFilter: String, CaseIterable, Identifiable {
    case all
    case meeting
    case microphone
    case app
    case imported

    var id: Self { self }

    var label: String {
        switch self {
        case .all: "All Types"
        case .meeting: "Meetings"
        case .microphone: "Microphone"
        case .app: "App Recordings"
        case .imported: "Imported Files"
        }
    }

    func matches(_ source: RecordingSourceKind) -> Bool {
        self == .all || rawValue == source.rawValue
    }
}

private struct RecordingLibraryRow: View {
    let item: RecordingLibraryItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.transcriptURL == nil ? item.recordingSource.symbolName : "doc.text")
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
                Text(item.recordingSource.label)
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                Text(item.statusLabel)
                    .font(.caption2)
                    .foregroundStyle(item.error == nil ? Color.secondary : Color.red)
                if let category = item.category, !category.isEmpty {
                    Text(category)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
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
    let onTranscribe: ([URL]) -> Void
    let isTranscribing: Bool
    let onCategoryChanged: (String) -> Void

    @StateObject private var playback = RecordingAudioPlayback()
    @State private var transcriptText: String?
    @State private var transcriptLoadFailed = false
    @State private var category = ""

    private var transcriptionButtonTitle: String {
        if isTranscribing { return "Processing…" }
        return item.transcriptURL == nil ? "Transcribe" : "Transcribe Again"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            transcriptBody
        }
        .task(id: item.id) {
            category = item.category ?? ""
            await loadTranscript()
        }
        .onDisappear { playback.stop() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
            HStack(spacing: 12) {
                Label(item.recordingSource.label, systemImage: item.recordingSource.symbolName)
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
                TextField("Category (optional)", text: $category)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .disabled(!canSaveCategory)
                Button("Save Category") { onCategoryChanged(category) }
                    .disabled(!canSaveCategory || category.trimmingCharacters(in: .whitespacesAndNewlines) == (item.category ?? ""))
                Text(canSaveCategory ? "Saved locally with this recording" : "Available after processing finishes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if item.audioURL != nil {
                    Button {
                        let urls = item.transcriptionURLs(outputDirectory: outputDirectory)
                        if !urls.isEmpty { onTranscribe(urls) }
                    } label: {
                        Label(
                            transcriptionButtonTitle,
                            systemImage: "waveform",
                        )
                    }
                    .disabled(isTranscribing)
                }
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

            if playback.duration > 0 {
                HStack(spacing: 10) {
                    Text(playback.currentTime.formatted(.number.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit())
                    Slider(
                        value: Binding(get: { playback.currentTime }, set: { playback.seek(to: $0) }),
                        in: 0...max(1, playback.duration),
                    )
                    Text(playback.duration.formatted(.number.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit())
                }
                .frame(maxWidth: 440)
            }

            if !item.bookmarks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bookmarks").font(.headline)
                    ForEach(item.bookmarks.sorted { $0.offset < $1.offset }) { bookmark in
                        Button {
                            guard let audioURL = item.audioURL else { return }
                            playback.play(audioURL, outputDirectory: outputDirectory, at: bookmark.offset)
                        } label: {
                            Label("\(bookmark.offset.formatted(.number.precision(.fractionLength(0))))s · \(bookmark.title)", systemImage: "bookmark.fill")
                        }
                        .buttonStyle(.link)
                    }
                }
            }

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

    private var canSaveCategory: Bool {
        !item.id.hasPrefix("job-")
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
            guard let source = try? String(contentsOf: transcriptURL, encoding: .utf8) else { return nil }
            return TranscriptEditorDocumentStore.correctedTranscript(for: transcriptURL) ?? source
        }.value
        transcriptText = content
        transcriptLoadFailed = content == nil
    }
}

@MainActor
final class RecordingAudioPlayback: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var error: String?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var scopedURL: URL?
    private var finishTask: Task<Void, Never>?

    func play(_ audioURL: URL, outputDirectory: URL, at offset: TimeInterval = 0) {
        stop()
        error = nil
        let accessRoot = Self.isInside(audioURL, directory: outputDirectory) ? outputDirectory : audioURL
        let openedScope = accessRoot.startAccessingSecurityScopedResource()
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: audioURL)
            newPlayer.currentTime = min(max(0, offset), newPlayer.duration)
            guard newPlayer.play() else {
                if openedScope { accessRoot.stopAccessingSecurityScopedResource() }
                error = "Sawti could not start audio playback."
                return
            }
            player = newPlayer
            duration = newPlayer.duration
            currentTime = newPlayer.currentTime
            scopedURL = openedScope ? accessRoot : nil
            isPlaying = true
            finishTask = Task { [weak self] in
                while !Task.isCancelled, newPlayer.isPlaying {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    self?.currentTime = newPlayer.currentTime
                }
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
        currentTime = 0
        duration = 0
        if let scopedURL {
            scopedURL.stopAccessingSecurityScopedResource()
            self.scopedURL = nil
        }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(0, time), player.duration)
        currentTime = player.currentTime
    }

    private static func isInside(_ file: URL, directory: URL) -> Bool {
        let filePath = file.standardizedFileURL.path
        let directoryPath = directory.standardizedFileURL.path
        let directoryPrefix = directoryPath.hasSuffix("/") ? directoryPath : directoryPath + "/"
        return filePath == directoryPath || filePath.hasPrefix(directoryPrefix)
    }
}
