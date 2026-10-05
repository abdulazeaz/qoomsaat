import AppIntents
import SwiftUI
import WidgetKit

extension Period: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Период"
    static var caseDisplayRepresentations: [Period: DisplayRepresentation] = [
        .currentMonth: "Текущий месяц",
        .currentHalf: "Текущий полумесяц",
        .previousHalf: "Прошлый полумесяц",
        .previousMonth: "Прошлый месяц",
    ]
}

struct PeriodIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Период"
    @Parameter(title: "Период", default: .currentMonth) var period: Period
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
        context.isPreview ? Entry(period: config.period, result: Cache.load(config.period)) : await entry(config.period)
    }

    func timeline(for config: PeriodIntent, in context: Context) async -> Timeline<Entry> {
        Timeline(entries: [await entry(config.period)], policy: .after(.now.addingTimeInterval(15 * 60)))
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
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Отработано · \(entry.period.label)")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            if entry.notConfigured {
                Text("Не настроено").font(.headline)
                Text("Откройте приложение Jira Worklog").font(.caption2).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(entry.result?.hoursText ?? "—")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text("ч").font(.title3).foregroundStyle(.secondary)
                }
                if family == .systemMedium, let r = entry.result {
                    Text("Задач с ворклогами: \(r.issues)").font(.callout)
                }
            }
            Spacer(minLength: 0)
            if let error = entry.error {
                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(1)
            }
            if let r = entry.result {
                Text("Обновлено \(r.updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct WorklogWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WorklogWidget", intent: PeriodIntent.self, provider: Provider()) {
            WorklogView(entry: $0)
        }
        .configurationDisplayName("Jira Worklog")
        .description("Часы, списанные в Jira за выбранный период.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
