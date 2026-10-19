import Foundation

/// Stores the transcription engine's original output independently from the
/// normalized, diarized transcript used by the rest of the pipeline.
enum OriginalTranscriptStore {
    static func save(_ text: String, basename: String, directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stem = "\(basename)_original"
        var version = 1

        while true {
            let name = version == 1 ? "\(stem).txt" : "\(stem)-\(version).txt"
            let destination = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: destination.path) {
                if let existing = try? String(contentsOf: destination, encoding: .utf8), existing == text {
                    return destination
                }
                version += 1
                continue
            }

            try text.write(to: destination, atomically: true, encoding: .utf8)
            try FileManager.default.restrictToOwner(destination)
            return destination
        }
    }

    /// Remove every version created for a job only after the user opted out of
    /// retaining the original transcript and a protocol was saved.
    static func removeAll(basename: String, directory: URL) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
        )

        let stem = "\(basename)_original"
        for file in files where file.pathExtension == "txt" {
            let filenameStem = file.deletingPathExtension().lastPathComponent
            let isOriginal = filenameStem == stem
                || (filenameStem.hasPrefix("\(stem)-")
                    && Int(filenameStem.dropFirst(stem.count + 1)).map { $0 >= 2 } == true)
            if isOriginal { try FileManager.default.removeItem(at: file) }
        }
    }
}
