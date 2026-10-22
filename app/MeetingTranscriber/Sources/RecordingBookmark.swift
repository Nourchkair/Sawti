import Foundation

/// A named moment on a recording's elapsed-time timeline.
struct RecordingBookmark: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let offset: TimeInterval
    let title: String

    init(id: UUID = UUID(), offset: TimeInterval, title: String = "Bookmark") {
        self.id = id
        self.offset = max(0, offset)
        self.title = title
    }
}

/// Bookmarks are private metadata stored next to the recording, never embedded
/// into an audio or transcript artifact.
enum RecordingBookmarksStore {
    static let filenameSuffix = "_bookmarks.json"

    static func read(from directory: URL, basename: String) -> [RecordingBookmark] {
        let url = directory.appendingPathComponent("\(basename)\(filenameSuffix)")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([RecordingBookmark].self, from: data)) ?? []
    }

    static func write(_ bookmarks: [RecordingBookmark], to directory: URL, basename: String) throws {
        guard !bookmarks.isEmpty else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(bookmarks.sorted { $0.offset < $1.offset })
        let url = directory.appendingPathComponent("\(basename)\(filenameSuffix)")
        try data.write(to: url, options: .atomic)
        try FileManager.default.restrictToOwner(url)
    }
}
