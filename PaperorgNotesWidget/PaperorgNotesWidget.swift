import AppIntents
import SwiftUI
import WidgetKit

struct QuickRecordEntry: TimelineEntry {
    let date: Date
}

struct QuickRecordProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickRecordEntry {
        QuickRecordEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickRecordEntry) -> Void) {
        completion(QuickRecordEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickRecordEntry>) -> Void) {
        let entry = QuickRecordEntry(date: .now)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct QuickRecordWidgetView: View {
    var entry: QuickRecordEntry

    var body: some View {
        Button(intent: QuickRecordIntent()) {
            VStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 28, weight: .semibold))
                Text("Record")
                    .font(.headline)
                Text("Paperorg Notes")
                    .font(.caption2)
                    .opacity(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(for: .widget) {
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.42, blue: 0.42),
                        Color(red: 0.14, green: 0.50, blue: 0.48)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

struct PaperorgNotesWidget: Widget {
    let kind = "QuickRecordWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickRecordProvider()) { entry in
            QuickRecordWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Record")
        .description("Start a voice note instantly.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}
