/// Scans Sawti's output folders and preserves the display metadata needed for
/// a searchable recording history after the short-lived processing job expires.
import Foundation

/// Private descriptive metadata kept beside Sawti's processed audio. The
/// recording library can still rebuild its index from the files if a sidecar
/// is missing or unreadable.
struct RecordingLibraryMetadata: Codable, Sendable {
    static let filenameSuffix = "_library.json"
    static let currentVersion = 1

    let version: Int
    let title: String
    let appName: String
    let recordedAt: Date
    let participants: [String]
    let course: String?

    init(title: String, appName: String, recordedAt: Date, participants: [String], course: String? = nil) {
        version = Self.currentVersion
        self.title = title
        self.appName = appName
        self.recordedAt = recordedAt
        self.participants = participants
        self.course = course
    }

    func write(toDirectory directory: URL, basename: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        let url = directory.appendingPathComponent("\(basename)\(Self.filenameSuffix)")
        try data.write(to: url, options: .atomic)
        try FileManager.default.restrictToOwner(url)
    }

    static func read(fromDirectory directory: URL, basename: String) -> Self? {
        let url = directory.appendingPathComponent("\(basename)\(filenameSuffix)")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let metadata = try? decoder.decode(Self.self, from: data),
              metadata.version == currentVersion,
              !metadata.title.isEmpty else { return nil }
        return metadata
    }
}

struct RecordingLibraryItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let recordedAt: Date
    let appName: String?
    let participants: [String]
    let course: String?
    let bookmarks: [RecordingBookmark]
    let transcriptURL: URL?
    let originalTranscriptURL: URL?
    let protocolURL: URL?
    let audioURL: URL?
    let pipelineStatus: String?
    let error: String?

    var statusLabel: String {
        if let pipelineStatus { return pipelineStatus }
        if protocolURL != nil { return "Transcript and protocol ready" }
        if transcriptURL != nil { return "Transcript ready" }
        if originalTranscriptURL != nil { return "Original transcript saved" }
        return "Recording only"
    }

    func reflecting(_ job: PipelineJob) -> Self {
        Self(
            id: id,
            title: title,
            recordedAt: recordedAt,
            appName: appName,
            participants: participants,
            course: course,
            bookmarks: bookmarks,
            transcriptURL: job.transcriptPath ?? transcriptURL,
            originalTranscriptURL: originalTranscriptURL,
            protocolURL: job.protocolPath ?? protocolURL,
            audioURL: audioURL ?? job.mixPath,
            pipelineStatus: job.state.label,
            error: job.error,
        )
    }

    static func inFlight(_ job: PipelineJob) -> Self {
        Self(
            id: job.namingSlug ?? "job-\(job.id.uuidString)",
            title: job.meetingTitle,
            recordedAt: job.artifactStartTime,
            appName: job.appName,
            participants: job.participants,
            course: nil,
            bookmarks: job.bookmarks ?? [],
            transcriptURL: job.transcriptPath,
            originalTranscriptURL: job.rawTranscriptPath,
            protocolURL: job.protocolPath,
            audioURL: job.mixPath,
            pipelineStatus: job.state.label,
            error: job.error,
        )
    }
}

/// Reads the durable output tree. The user-picked output root is the security
/// scoped URL; child URLs are accessed only while that root is open.
enum RecordingLibraryIndex {
    private struct Builder {
        let id: String
        var title: String
        var recordedAt: Date
        var appName: String?
        var participants: [String] = []
        var course: String?
        var bookmarks: [RecordingBookmark] = []
        var transcriptURL: URL?
        var originalTranscriptURL: URL?
        var protocolURL: URL?
        var audioURL: URL?

        func item() -> RecordingLibraryItem {
            RecordingLibraryItem(
                id: id,
                title: title,
                recordedAt: recordedAt,
                appName: appName,
                participants: participants,
                course: course,
                bookmarks: bookmarks,
                transcriptURL: transcriptURL,
                originalTranscriptURL: originalTranscriptURL,
                protocolURL: protocolURL,
                audioURL: audioURL,
                pipelineStatus: nil,
                error: nil,
            )
        }
    }

    static func load(outputDirectory: URL) throws -> [RecordingLibraryItem] {
        let openedScope = outputDirectory.startAccessingSecurityScopedResource()
        defer {
            if openedScope { outputDirectory.stopAccessingSecurityScopedResource() }
        }

        let fileManager = FileManager.default
        let protocolsDirectory = outputDirectory.appendingPathComponent("protocols", isDirectory: true)
        let recordingsDirectory = outputDirectory.appendingPathComponent("recordings", isDirectory: true)
        let transcriptFiles = try files(in: protocolsDirectory, fileManager: fileManager)
        let recordingFiles = try files(in: recordingsDirectory, fileManager: fileManager)
        var builders: [String: Builder] = [:]

        func builder(for id: String, source: URL?) -> Builder {
            if let existing = builders[id] { return existing }
            let sourceDate = (try? source?.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            let parsed = dateFromFilename(id)
            return Builder(
                id: id,
                title: fallbackTitle(for: id),
                recordedAt: parsed ?? sourceDate ?? .distantPast,
            )
        }

        for file in transcriptFiles {
            let stem = file.deletingPathExtension().lastPathComponent
            if file.pathExtension.lowercased() == "txt" {
                if let originalBase = originalTranscriptBase(stem) {
                    var entry = builder(for: originalBase, source: file)
                    entry.originalTranscriptURL = file
                    builders[originalBase] = entry
                } else {
                    var entry = builder(for: stem, source: file)
                    entry.transcriptURL = file
                    builders[stem] = entry
                }
            } else if file.pathExtension.lowercased() == "md" {
                var entry = builder(for: stem, source: file)
                entry.protocolURL = file
                builders[stem] = entry
            }
        }

        for file in recordingFiles {
            let name = file.lastPathComponent
            if name.hasSuffix(RecordingLibraryMetadata.filenameSuffix) {
                let id = String(name.dropLast(RecordingLibraryMetadata.filenameSuffix.count))
                guard let metadata = RecordingLibraryMetadata.read(fromDirectory: recordingsDirectory, basename: id)
                else { continue }
                var entry = builder(for: id, source: file)
                entry.title = metadata.title
                entry.appName = metadata.appName
                entry.recordedAt = metadata.recordedAt
                entry.participants = metadata.participants
                entry.course = metadata.course
                builders[id] = entry
            } else if name.hasSuffix(RecordingBookmarksStore.filenameSuffix) {
                let id = String(name.dropLast(RecordingBookmarksStore.filenameSuffix.count))
                var entry = builder(for: id, source: file)
                entry.bookmarks = RecordingBookmarksStore.read(from: recordingsDirectory, basename: id)
                builders[id] = entry
            } else if name.hasSuffix(RecordingSidecar.filenameSuffix) {
                let id = String(name.dropLast(RecordingSidecar.filenameSuffix.count))
                guard let metadata = RecordingSidecar.read(fromDirectory: recordingsDirectory, basename: id)
                else { continue }
                var entry = builder(for: id, source: file)
                entry.title = metadata.title
                entry.appName = metadata.appName
                entry.recordedAt = metadata.startedAt
                entry.participants = metadata.participants
                entry.audioURL = recordingsDirectory.appendingPathComponent(metadata.files.mix)
                builders[id] = entry
            } else if let (id, audioURL) = audioFile(file) {
                var entry = builder(for: id, source: file)
                if entry.audioURL == nil || audioURL.lastPathComponent.hasSuffix("_mix.wav") {
                    entry.audioURL = audioURL
                }
                builders[id] = entry
            }
        }

        return builders.values
            .map { $0.item() }
            .filter {
                $0.transcriptURL != nil || $0.originalTranscriptURL != nil
                    || $0.protocolURL != nil || $0.audioURL != nil
            }
            .sorted {
                if $0.recordedAt == $1.recordedAt { return $0.id > $1.id }
                return $0.recordedAt > $1.recordedAt
            }
    }

    static func updateCourse(for item: RecordingLibraryItem, course: String, outputDirectory: URL) throws {
        let openedScope = outputDirectory.startAccessingSecurityScopedResource()
        defer { if openedScope { outputDirectory.stopAccessingSecurityScopedResource() } }
        let recordingsDirectory = outputDirectory.appendingPathComponent("recordings", isDirectory: true)
        let trimmedCourse = course.trimmingCharacters(in: .whitespacesAndNewlines)
        try RecordingLibraryMetadata(
            title: item.title,
            appName: item.appName ?? "Unknown",
            recordedAt: item.recordedAt,
            participants: item.participants,
            course: trimmedCourse.isEmpty ? nil : trimmedCourse,
        ).write(toDirectory: recordingsDirectory, basename: item.id)
    }

    private static func files(in directory: URL, fileManager: FileManager) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles],
        )
    }

    private static func originalTranscriptBase(_ stem: String) -> String? {
        guard let range = stem.range(of: "_original", options: .backwards) else { return nil }
        let version = stem[range.upperBound...]
        guard version.isEmpty || (version.first == "-" && Int(version.dropFirst()) != nil) else { return nil }
        return String(stem[..<range.lowerBound])
    }

    private static func audioFile(_ file: URL) -> (String, URL)? {
        guard file.pathExtension.lowercased() == "wav" else { return nil }
        let stem = file.deletingPathExtension().lastPathComponent
        for suffix in ["_app_16k", "_mic_16k", "_mix", "_16k", "_app", "_mic"] where stem.hasSuffix(suffix) {
            return (String(stem.dropLast(suffix.count)), file)
        }
        return nil
    }

    private static func dateFromFilename(_ id: String) -> Date? {
        let patterns = [#"^(\d{8}_\d{6})_"#, #"^(\d{8}_\d{4})_"#]
        for pattern in patterns {
            guard let range = id.range(of: pattern, options: .regularExpression) else { continue }
            let stamp = String(id[range]).dropLast()
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .autoupdatingCurrent
            formatter.dateFormat = stamp.count == 15 ? "yyyyMMdd_HHmmss" : "yyyyMMdd_HHmm"
            if let date = formatter.date(from: String(stamp)) { return date }
        }
        return nil
    }

    private static func fallbackTitle(for id: String) -> String {
        var title = id
        for pattern in [#"^\d{8}_\d{6}_"#, #"^\d{8}_\d{4}_"#] {
            title = title.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        title = title.replacingOccurrences(of: #"_[0-9a-fA-F]{8}$"#, with: "", options: .regularExpression)
        return title.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
