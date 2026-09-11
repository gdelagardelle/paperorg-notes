import Foundation

// Standalone harness compiles the real SubscriptionPlan.swift. This unrelated
// localization dependency is not exercised by the protocol tests.
enum L10n { enum Import { static let errorServerTooLong = "Audio too long" } }

@main
struct SegmentProtocolTests {
    static func main() throws {
        for detail in ["segment_pending", "segment_conflict"] {
            let error = ProBackendHTTPMapping.error(
                statusCode: 409, message: detail, treats413AsAudioTooLong: true
            )
            guard error.stopsProviderFallback else {
                fputs("FAIL: ambiguous segment must not fall through to another provider\n", stderr)
                exit(1)
            }
        }
        print("PASS: ambiguous segment errors stop fallback")
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let identity = RecordingSegmentIdentity(sessionID: id, index: 2, startSeconds: 240)
        let restored = try JSONDecoder().decode(RecordingSegmentIdentity.self, from: JSONEncoder().encode(identity))
        let fields = Dictionary(uniqueKeysWithValues: try restored.multipartFields())
        precondition(fields["recording_session_id"] == id.uuidString.lowercased())
        precondition(fields["segment_index"] == "2")
        precondition(Double(fields["segment_start_seconds"]!) == 240)
        for start in [-1.0, Double.infinity, Double.nan] {
            do {
                _ = try RecordingSegmentIdentity(sessionID: id, index: 0, startSeconds: start).multipartFields()
                fatalError("Invalid offset accepted")
            } catch {}
        }
        do {
            _ = try RecordingSegmentIdentity(sessionID: id, index: -1, startSeconds: 0).multipartFields()
            fatalError("Negative index accepted")
        } catch {}
        let enabled = try RecordingCapabilities.decode(Data("{\"segmented_transcription\":true,\"segment_seconds\":120}".utf8))
        let missing = try RecordingCapabilities.decode(Data("{}".utf8))
        precondition(enabled.supported)
        precondition(!missing.supported)
        print("PASS: stable identities, invalid offsets, fail-closed capability")
        precondition(RecordingTranscriptPolicy.accepts(text: "  ", isSegment: true))
        precondition(!RecordingTranscriptPolicy.accepts(text: "  ", isSegment: false))
        precondition(RecordingTranscriptPolicy.accepts(text: "Speech", isSegment: false))
        print("PASS: silent segments are retained as completed, empty legacy recordings rejected")
    }
}
