import SwiftUI
import WatchKit

@main
struct PaperorgNotesWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchLifecycle.self) private var lifecycle
    @Environment(\.scenePhase) private var scenePhase
    private var recorder: WatchRecorder { .shared }

    var body: some Scene {
        WindowGroup {
            WatchRecordView(recorder: recorder)
                .onAppear { recorder.activate() }
                .onOpenURL { url in
                    guard url.host == "record" else { return }
                    recorder.startFromWatchFace()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        recorder.stopBecauseAppLeftForeground()
                    }
                }
        }
    }
}

final class WatchLifecycle: NSObject, WKApplicationDelegate {
    func applicationDidEnterBackground() {
        Task { @MainActor in
            WatchRecorder.shared.stopBecauseAppLeftForeground()
        }
    }
}

struct WatchRecordView: View {
    @Bindable var recorder: WatchRecorder

    var body: some View {
        VStack(spacing: 8) {
            Text(recorder.isRecording ? recorder.elapsedText : "Paperorg")
                .font(recorder.isRecording ? .title2.monospacedDigit() : .headline)
            Button {
                recorder.toggle()
            } label: {
                Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.title2)
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(.borderedProminent)
            .tint(recorder.isRecording ? .red : .accentColor)
            Text(recorder.status)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !recorder.isRecording {
                Text(recorder.setupLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 4)
    }
}
