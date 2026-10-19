@testable import MeetingTranscriber
import XCTest

final class SawtiHelperMicCaptureTests: XCTestCase {
    func testReaderFramesEventsAcrossPartialPipeWrites() {
        let reader = SawtiCaptureHelperEventReader()
        reader.ingest(Data("{\"type\":\"rea".utf8))
        XCTAssertEqual(reader.waitForReady(timeout: 0), "helper_start_timeout")

        reader.ingest(Data("dy\"}\n{\"type\":\"health\",\"levelDBFS\":-24.5,\"secondsSinceLastBuffer\":0.1,\"secondsSinceLastEnergy\":0.2}\n".utf8))
        XCTAssertNil(reader.waitForReady(timeout: 0))
        XCTAssertEqual(reader.health.levelDBFS, -24.5)
        XCTAssertEqual(reader.health.ages.secondsSinceLastBuffer, 0.1)
        XCTAssertEqual(reader.health.ages.secondsSinceLastEnergy, 0.2)
    }

    func testReaderReportsHelperFailureAndCleanStop() {
        let failedReader = SawtiCaptureHelperEventReader()
        failedReader.ingest(Data("{\"type\":\"error\",\"code\":\"microphone_permission_not_granted\"}\n".utf8))
        XCTAssertEqual(failedReader.waitForReady(timeout: 0), "microphone_permission_not_granted")

        let stoppedReader = SawtiCaptureHelperEventReader()
        stoppedReader.ingest(Data("{\"type\":\"ready\"}\n{\"type\":\"stopped\"}\n".utf8))
        XCTAssertNil(stoppedReader.waitForReady(timeout: 0))
        XCTAssertTrue(stoppedReader.waitForStopped(timeout: 0))
    }

    func testReaderFlagsAnUnexpectedHelperExitButNotARequestedStop() {
        let failedReader = SawtiCaptureHelperEventReader()
        failedReader.ingestProcessTermination()
        XCTAssertTrue(failedReader.health.gaveUp)

        let stoppedReader = SawtiCaptureHelperEventReader()
        stoppedReader.requestStop()
        stoppedReader.ingest(Data("{\"type\":\"stopped\"}\n".utf8))
        stoppedReader.ingestProcessTermination()
        XCTAssertFalse(stoppedReader.health.gaveUp)
    }
}
