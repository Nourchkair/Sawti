import XCTest

/// Guards the test-only defaults boundary. Tests need isolated named domains,
/// while production defaults must stay outside this factory and no test may
/// construct a disk-backed suite directly.
final class ScratchDefaultsHygieneTests: XCTestCase {
    func testNamedDomainsAreSharedByNameAndIsolatedFromEachOther() throws {
        let firstName = "app.meetingtranscriber.test.defaults.first.\(UUID().uuidString)"
        let secondName = "app.meetingtranscriber.test.defaults.second.\(UUID().uuidString)"
        defer {
            DefaultsSuite.remove(firstName)
            DefaultsSuite.remove(secondName)
        }

        let first = try XCTUnwrap(DefaultsSuite.make(firstName))
        let sameDomain = try XCTUnwrap(DefaultsSuite.make(firstName))
        let second = try XCTUnwrap(DefaultsSuite.make(secondName))

        first.set("de", forKey: "language")
        first.set(true, forKey: "autoWatch")

        XCTAssertEqual(sameDomain.string(forKey: "language"), "de")
        XCTAssertTrue(sameDomain.bool(forKey: "autoWatch"))
        XCTAssertNil(second.object(forKey: "language"))

        DefaultsSuite.remove(firstName)
        XCTAssertNil(sameDomain.object(forKey: "language"))
    }

    func testEveryNamedDomainUsesTheMemoryFactoryAndHasCleanup() throws {
        var offenders: [String] = []

        for (name, source) in try testSources() {
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            let code = lines.joined(separator: "\n")

            let suites = code.ranges(of: Self.memoryFactory).count
            let cleanups = code.ranges(of: Self.cleanupHelper).count
            if suites > cleanups {
                offenders.append("\(name): makes \(suites) suite(s), cleans up \(cleanups)")
            }
            if code.contains(Self.directSuiteFactory) {
                offenders.append("\(name): constructs a disk-backed UserDefaults suite directly")
            }
        }

        XCTAssertEqual(
            offenders, [],
            "Named test defaults must use the in-memory factory and be cleared during teardown. "
                + "\(offenders.count) place(s) do not:\n"
                + offenders.joined(separator: "\n"),
        )
    }

    // MARK: - Needles

    /// Built from pieces so this file does not match its own scan.
    private static let directSuiteFactory = "UserDefaults(suiteName" + ":"
    private static let memoryFactory = "DefaultsSuite" + ".make("
    private static let cleanupHelper = "DefaultsSuite" + ".remove("

    // MARK: - Sources

    /// Every `.swift` file beside this one, keyed by file name. Reads the test
    /// target's own directory, derived from this file's path, so it cannot drift
    /// to some other checkout.
    private func testSources(file: StaticString = #filePath) throws -> [(String, String)] {
        let ownPath = URL(fileURLWithPath: "\(file)")
        let dir = ownPath.deletingLastPathComponent()
        let all = try FileManager.default.subpathsOfDirectory(atPath: dir.path)

        // The factory is the one place that calls UserDefaults(suiteName:),
        // and this file names the needles in its own text, so neither scan can
        // match itself.
        let exempt = [ownPath.lastPathComponent, "DefaultsSuite.swift"]
        let sources = all.filter { path in
            path.hasSuffix(".swift") && !exempt.contains(URL(fileURLWithPath: path).lastPathComponent)
        }
        XCTAssertGreaterThan(
            sources.count, 100,
            "Expected to scan the whole test target; found \(sources.count) files under \(dir.path)",
        )

        return try sources.map { relative in
            let text = try String(contentsOf: dir.appendingPathComponent(relative), encoding: .utf8)
            return (relative, text)
        }
    }
}
