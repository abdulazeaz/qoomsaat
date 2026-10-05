import AppIntents
import SwiftUI
import WidgetKit

/// Periods offered in Edit Widget (the app's report window offers all of `Period`).
enum WidgetPeriod: String, AppEnum {
    case currentMonth, currentHalf

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Period"
    static var caseDisplayRepresentations: [WidgetPeriod: DisplayRepresentation] = [
        .currentMonth: "Current month",
        .currentHalf: "Current semi-month",
    ]

    var period: Period { Period(rawValue: rawValue)! }
}

struct PeriodIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Period"
    @Parameter(title: "Period", default: .currentMonth) var period: WidgetPeriod
}

/// Refresh button: after perform() WidgetKit reloads the timeline right away.
struct RefreshIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh"
    func perform() async throws -> some IntentResult { .result() }
}

struct Entry: TimelineEntry {
    var date = Date.now
    var period = Period.currentMonth
    var result: WorklogResult?
    var error: String?
    var notConfigured = false
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry() }

    func snapshot(for config: PeriodIntent, in context: Context) async -> Entry {
        let p = config.period.period
        return context.isPreview ? Entry(period: p, result: Cache.load(p)) : await entry(p)
    }

    func timeline(for config: PeriodIntent, in context: Context) async -> Timeline<Entry> {
        Timeline(entries: [await entry(config.period.period)], policy: .after(.now.addingTimeInterval(15 * 60)))
    }

    private func entry(_ period: Period) async -> Entry {
        do {
            let r = try await JiraClient.fromStorage().summary(for: period.interval())
            Cache.save(r, for: period)
            return Entry(period: period, result: r)
        } catch JiraError.notConfigured {
            return Entry(period: period, notConfigured: true)
        } catch {
            return Entry(period: period, result: Cache.load(period), error: error.localizedDescription)
        }
    }
}

struct WorklogView: View {
    let entry: Entry

    // Fixed palette in both light and dark mode.
    private let background = Color(red: 0xD8 / 255, green: 0x5A / 255, blue: 0x30 / 255)
    private let header = Color(red: 0xFA / 255, green: 0xEC / 255, blue: 0xE7 / 255)
    private let footer = Color(red: 0xF5 / 255, green: 0xC4 / 255, blue: 0xB3 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.period.label.uppercased()).lineLimit(1)
                Spacer(minLength: 4)
                Button(intent: RefreshIntent()) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh")
            }
            .font(.custom("DINAlternate-Bold", size: 13))
            .foregroundStyle(header)

            Spacer(minLength: 0)
            if entry.notConfigured {
                Text("Not set up").font(.custom("DINCondensed-Bold", size: 30)).foregroundStyle(.white)
                Text("Open Jira Worklog to sign in").font(.custom("DINAlternate-Bold", size: 11)).foregroundStyle(footer)
            } else {
                Text(entry.result?.hoursText ?? "—")
                    .font(.custom("DINCondensed-Bold", size: 54))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5).lineLimit(1)
            }
            Spacer(minLength: 0)

            Group {
                if let error = entry.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(header)
                } else if let r = entry.result {
                    Text("Updated \(r.updated.formatted(date: .omitted, time: .shortened))")
                }
            }
            .font(.custom("DINAlternate-Bold", size: 11))
            .foregroundStyle(footer)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(background, for: .widget)
    }
}

@main
struct WorklogWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WorklogWidget", intent: PeriodIntent.self, provider: Provider()) {
            WorklogView(entry: $0)
        }
        .configurationDisplayName("Jira Worklog")
        .description("Hours logged in Jira for the current month or semi-month.")
        .supportedFamilies([.systemSmall])
    }
}
