import Foundation
@testable import MeetingTranscriber
import XCTest

final class TranscriptExportTests: XCTestCase {
    func testWritesExactTranscriptCopyWithOwnerOnlyPermissions() throws {
        let root = try makeTempDirectory(prefix: "TranscriptExport")
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("copies/class notes.txt")
        let original = "[00:00:01] Speaker A: First line.\nArabic: مرحبًا\n"

        try TranscriptExport.writeCopy(original, to: destination)

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), original)
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
}
