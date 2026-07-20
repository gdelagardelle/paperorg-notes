import SwiftUI
import WidgetKit

private enum WidgetBrand {
    static let background = Color.white
    static let textPrimary = Color(red: 0.078, green: 0.137, blue: 0.239)
    static let recordURL = URL(string: "paperorgnotes://record")!
}

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
    @Environment(\.widgetFamily) private var family
    var entry: QuickRecordEntry

    var body: some View {
        Link(destination: WidgetBrand.recordURL) {
            Group {
                switch family {
                case .accessoryCircular:
                    accessoryContent
                default:
                    standardContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .containerBackground(for: .widget) {
            WidgetBrand.background
        }
    }

    private var standardContent: some View {
        VStack(spacing: 10) {
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)

            Text("Record")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WidgetBrand.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var accessoryContent: some View {
        ZStack {
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .padding(6)
        }
    }
}

struct PaperorgNotesWidget: Widget {
    let kind = "QuickRecordWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickRecordProvider()) { entry in
            QuickRecordWidgetView(entry: entry)
                .widgetURL(WidgetBrand.recordURL)
        }
        .configurationDisplayName("Quick Record")
        .description("Start a voice note instantly.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}
