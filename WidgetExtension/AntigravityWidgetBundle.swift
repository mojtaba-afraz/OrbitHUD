import WidgetKit
import SwiftUI
#if canImport(AntigravityUsageCore)
import AntigravityUsageCore
#endif

struct AntigravityWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: AntigravityUsageSnapshot
}

struct AntigravityTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> AntigravityWidgetEntry {
        AntigravityWidgetEntry(date: Date(), snapshot: AntigravityUsageSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (AntigravityWidgetEntry) -> Void) {
        let snapshot = SharedSnapshotStorage.load() ?? AntigravityUsageSnapshot()
        completion(AntigravityWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AntigravityWidgetEntry>) -> Void) {
        let snapshot = SharedSnapshotStorage.load() ?? AntigravityUsageSnapshot()
        let entry = AntigravityWidgetEntry(date: Date(), snapshot: snapshot)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct AntigravityNativeWidgetEntryView: View {
    var entry: AntigravityTimelineProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Usage")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            ForEach(entry.snapshot.quotaGroups.prefix(3)) { group in
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.displayName)
                        .font(.system(size: 11, weight: .bold))
                    ForEach(group.buckets) { bucket in
                        HStack {
                            Text(bucket.windowLabel)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(bucket.remainingPercentage)% left")
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                }
            }
        }
        .padding()
    }
}

struct AntigravityNativeDesktopWidget: Widget {
    let kind: String = "AntigravityNativeDesktopWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AntigravityTimelineProvider()) { entry in
            AntigravityNativeWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Antigravity Usage")
        .description("Track your Antigravity model quotas (Weekly & 5h limits).")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
