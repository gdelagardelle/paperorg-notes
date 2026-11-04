import XCTest
@testable import PaperorgNotes

final class WatchRecordingTransferTests: XCTestCase {
    func testPayloadReadsWatchMetadata() {
        let payload = WatchRecordingTransfer.payload(metadata: [
            "recordingID": "abc",
            "duration": 12.5,
            "createdAt": 1_700_000_000.0
        ])
        XCTAssertEqual(payload.recordingID, "abc")
        XCTAssertEqual(payload.duration, 12.5)
        XCTAssertEqual(payload.createdAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testSetupSaysWhenEmailWillNotSend() {
        let off = WatchPhoneSetup.context(language: "Lëtzebuergesch", sendsEmail: false, recipients: ["a@b.c"])
        XCTAssertEqual(off["emailState"], "off")

        let missing = WatchPhoneSetup.context(language: "Lëtzebuergesch", sendsEmail: true, recipients: ["  "])
        XCTAssertEqual(missing["emailState"], "missing")

        let ready = WatchPhoneSetup.context(language: "Lëtzebuergesch", sendsEmail: true, recipients: ["a@b.c", "d@e.f"])
        XCTAssertEqual(ready["emailState"], "ready")
        XCTAssertEqual(ready["recipient"], "2 people")
        XCTAssertEqual(ready["language"], "Lëtzebuergesch")
    }

    func testBlankIdentifierIsReplaced() {
        let payload = WatchRecordingTransfer.payload(metadata: ["recordingID": "  "])
        XCTAssertFalse(payload.recordingID.isEmpty)
        XCTAssertNotEqual(payload.recordingID, "  ")
        XCTAssertEqual(payload.duration, 0)
        XCTAssertNil(payload.createdAt)
    }
}
