import Foundation

/// Pure I/O helpers for persisting `PipelineQueue`'s `[PipelineJob]` array
/// to disk and reading it back. Extracted from `PipelineQueue` so the
/// serialization + atomic-rename mechanics can be exercised without
/// constructing a full queue + speaker DB + engine wiring, and so the
/// save side can later run off the main actor without touching the rest
/// of `PipelineQueue`'s `@MainActor` surface.
///
/// File names mirror what `PipelineQueue` used inline before the
/// extraction (`pipeline_queue.json` final, `pipeline_queue.tmp` staging)
/// so existing on-disk snapshots load unchanged after upgrade.
enum PipelineSnapshot {
    static let snapshotFilename = "pipeline_queue.json"
    static let stagingFilename = "pipeline_queue.tmp"
    private static let ownerOnlyPermissions = 0o600

    /// JSON-encode `jobs` and atomically replace any existing snapshot at
    /// `logDir/pipeline_queue.json`. The staging write goes to
    /// `pipeline_queue.tmp` first; `replaceItemAt` (which lowers to
    /// `renamex_np` on macOS) swaps it in.
    ///
    /// - Throws: `EncodingError` from JSONEncoder, or any `FileManager` I/O error.
    static func save(_ jobs: [PipelineJob], to logDir: URL) throws {
        let data = try JSONEncoder().encode(jobs)
        let fileManager = FileManager.default
        let stagingPath = logDir.appendingPathComponent(stagingFilename)
        if fileManager.fileExists(atPath: stagingPath.path) {
            try fileManager.removeItem(at: stagingPath)
        }
        guard fileManager.createFile(
            atPath: stagingPath.path,
            contents: data,
            attributes: [.posixPermissions: ownerOnlyPermissions],
        ) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: stagingPath.path])
        }
        let snapshotPath = logDir.appendingPathComponent(snapshotFilename)
        _ = try fileManager.replaceItemAt(snapshotPath, withItemAt: stagingPath)
        try fileManager.setAttributes(
            [.posixPermissions: ownerOnlyPermissions],
            ofItemAtPath: snapshotPath.path,
        )
    }

    // swiftlint:disable discouraged_optional_collection
    /// Read + JSON-decode the snapshot at `logDir/pipeline_queue.json`.
    ///
    /// - Returns: the decoded jobs, or `nil` if no snapshot file exists.
    ///   `nil` vs an empty array is load-bearing: the caller logs a
    ///   different message ("No pipeline snapshot to restore" vs
    ///   "Snapshot loaded but no recoverable jobs") so flattening into
    ///   `[]` on missing-file would lose that distinction.
    /// - Throws: any read or `DecodingError` failure. Caller decides how
    ///   to recover (PipelineQueue logs + drops the load).
    static func load(from logDir: URL) throws -> [PipelineJob]? {
        let snapshotPath = logDir.appendingPathComponent(snapshotFilename)
        guard FileManager.default.fileExists(atPath: snapshotPath.path) else {
            return nil
        }
        // Existing snapshots predate the owner-only writer. Tighten them on
        // the first launch that reads them, before any job metadata is loaded.
        try FileManager.default.setAttributes(
            [.posixPermissions: ownerOnlyPermissions],
            ofItemAtPath: snapshotPath.path,
        )
        let data = try Data(contentsOf: snapshotPath)
        return try JSONDecoder().decode([PipelineJob].self, from: data)
    }
    // swiftlint:enable discouraged_optional_collection
}
