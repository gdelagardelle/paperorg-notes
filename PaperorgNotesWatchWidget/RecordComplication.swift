import SwiftUI
import WidgetKit

struct RecordEntry: TimelineEntry {
    let date: Date
}

struct RecordProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecordEntry {
        RecordEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecordEntry) -> Void) {
        completion(RecordEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecordEntry>) -> Void) {
        completion(Timeline(entries: [RecordEntry(date: .now)], policy: .never))
    }
}

struct RecordComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Record", systemImage: "mic.fill")
        case .accessoryRectangular:
            HStack {
                Image(systemName: "mic.fill")
                Text("Record")
            }
        case .accessoryCorner:
            Image(systemName: "mic.fill")
                .widgetLabel("Record")
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "mic.fill")
            }
        }
    }
}

struct RecordComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.paperorg.voicenotes.watch.record", provider: RecordProvider()) { _ in
            RecordComplicationView()
                .widgetURL(URL(string: "paperorg-watch://record"))
        }
        .configurationDisplayName("Record")
        .description("Start a Paperorg note.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular
        ])
    }
}

@main
struct PaperorgNotesWatchWidgets: WidgetBundle {
    var body: some Widget {
        RecordComplication()
    }
}
