import Foundation
@testable import MeetingTranscriber
import XCTest

final class OriginalTranscriptStoreTests: XCTestCase {
    func testSavingIdenticalTextReusesOriginalArtifact() throws {
        let directory = try makeTempDirectory(prefix: "OriginalTranscript")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try OriginalTranscriptStore.save("[00:00] raw words", basename: "class", directory: directory)
        let second = try OriginalTranscriptStore.save("[00:00] raw words", basename: "class", directory: directory)

        XCTAssertEqual(first, second)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "[00:00] raw words")
        let mode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: first.path)[.posixPermissions] as? Int,
        )
        XCTAssertEqual(mode & 0o777, 0o600)
    }

    func testChangedTextGetsVersionedWithoutOverwritingPriorOriginal() throws {
        let directory = try makeTempDirectory(prefix: "OriginalTranscript")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try OriginalTranscriptStore.save("first run", basename: "class", directory: directory)
        let second = try OriginalTranscriptStore.save("retry output", basename: "class", directory: directory)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "first run")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "retry output")
    }

    func testRemoveAllDeletesEveryVersionForJob() throws {
        let directory = try makeTempDirectory(prefix: "OriginalTranscript")
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try OriginalTranscriptStore.save("one", basename: "class", directory: directory)
        _ = try OriginalTranscriptStore.save("two", basename: "class", directory: directory)
        _ = try OriginalTranscriptStore.save("other meeting", basename: "other", directory: directory)

        try OriginalTranscriptStore.removeAll(basename: "class", directory: directory)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(Set(remaining), Set(["other_original.txt"]))
    }
}
