import Foundation

/// Writes a user-requested copy without changing the pipeline's preserved
/// transcript artifact.
enum TranscriptExport {
    static func writeCopy(_ text: String, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try text.write(to: destination, atomically: true, encoding: .utf8)
        try FileManager.default.restrictToOwner(destination)
    }
}
