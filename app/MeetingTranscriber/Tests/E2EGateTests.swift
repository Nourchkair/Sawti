@testable import MeetingTranscriber
import XCTest

final class E2EGateTests: XCTestCase {
    func testLocalRunNeverSkips() {
        XCTAssertFalse(shouldSkipForE2EGate(env: [:]))
    }

    func testCIWithoutOptInSkips() {
        XCTAssertTrue(shouldSkipForE2EGate(env: ["CI": "true"]))
    }

    func testCIWithOptInRuns() {
        XCTAssertFalse(shouldSkipForE2EGate(env: ["CI": "true", "E2E_ENABLED": "1"]))
    }

    func testCIWithOptInWrongValueSkips() {
        XCTAssertTrue(shouldSkipForE2EGate(env: ["CI": "true", "E2E_ENABLED": "true"]))
    }

    func testOptInWithoutCIRuns() {
        XCTAssertFalse(shouldSkipForE2EGate(env: ["E2E_ENABLED": "1"]))
    }

    func testCIEmptyStringSkips() {
        // Some systems set `CI=""` instead of `CI=true`; gate is presence, not value.
        XCTAssertTrue(shouldSkipForE2EGate(env: ["CI": ""]))
    }

    func testIsolatedLocalRunWithoutOptInSkips() {
        XCTAssertTrue(shouldSkipForE2EGate(env: ["SAWTI_TEST_HOME": "/tmp/sawti-test-home"]))
    }

    func testIsolatedLocalRunWithOptInRuns() {
        XCTAssertFalse(shouldSkipForE2EGate(env: [
            "SAWTI_TEST_HOME": "/tmp/sawti-test-home",
            "E2E_ENABLED": "1",
        ]))
    }

    func testIsolatedModelRunWithoutOptInSkipsButCIModelRunDoesNot() {
        XCTAssertTrue(shouldSkipForIsolatedModelRun(env: ["SAWTI_TEST_HOME": "/tmp/sawti-test-home"]))
        XCTAssertFalse(shouldSkipForIsolatedModelRun(env: ["CI": "true"]))
    }

    func testIsolatedModelRunWithOptInRuns() {
        XCTAssertFalse(shouldSkipForIsolatedModelRun(env: [
            "SAWTI_TEST_HOME": "/tmp/sawti-test-home",
            "E2E_ENABLED": "1",
        ]))
    }
}
