import WidgetKit
import SwiftUI

// MARK: - 공유 데이터 (Flutter home_widget ↔ App Group)
// Flutter 의 HomeWidget.saveWidgetData(key, value) 는
// UserDefaults(suiteName: appGroupId) 에 저장된다. 앱과 동일한 그룹으로 읽는다.
private let kAppGroup = "group.com.dksw.charge"

private func sharedDefaults() -> UserDefaults? {
    UserDefaults(suiteName: kAppGroup)
}

// MARK: - 색상 (앱과 통일: 주유 파랑 / 충전 초록)
private extension Color {
    static let gasBlue = Color(red: 0.231, green: 0.510, blue: 0.965)   // #3B82F6
    static let evGreen = Color(red: 0.133, green: 0.773, blue: 0.369)   // #22C55E
    static let evFull = Color(red: 0.94, green: 0.27, blue: 0.27)       // 만차 빨강
    static let mutedText = Color.secondary
}

// MARK: - 모델
private struct GasItem: Decodable {
    let name: String
    let brand: String?
    let price: Int
    let isSelf: Bool?
    let fuelLabel: String?
    let change: Int?
}

private struct EvItem: Decodable {
    let name: String
    let available: Int
    let total: Int
    let broken: Int?
    let hasFast: Bool?
    let maxKw: Int?
    let statusCode: Int?   // 0 정상 / 1 만차 / 2 고장
}

private func decodeList<T: Decodable>(_ key: String, as type: T.Type) -> [T] {
    guard let raw = sharedDefaults()?.string(forKey: key),
          let data = raw.data(using: .utf8) else { return [] }
    return (try? JSONDecoder().decode([T].self, from: data)) ?? []
}

private func updatedText(_ key: String) -> String {
    sharedDefaults()?.string(forKey: key) ?? "-"
}

private func bgOpacity() -> Double {
    let v = Int(sharedDefaults()?.string(forKey: "widget_bg_opacity") ?? "100") ?? 100
    return Double(max(0, min(100, v))) / 100.0
}

// row 수: 위젯 크기별
private func rowCount(_ family: WidgetFamily) -> Int {
    switch family {
    case .systemSmall: return 2
    case .systemMedium: return 3
    default: return 4
    }
}

// MARK: - Timeline Entry
private struct ChargeEntry: TimelineEntry {
    let date: Date
    let gas: [GasItem]
    let ev: [EvItem]
    let gasUpdated: String
    let evUpdated: String
    let opacity: Double
}

private struct ChargeProvider: TimelineProvider {
    func placeholder(in context: Context) -> ChargeEntry {
        ChargeEntry(date: Date(), gas: [], ev: [], gasUpdated: "-", evUpdated: "-", opacity: 1)
    }
    func getSnapshot(in context: Context, completion: @escaping (ChargeEntry) -> Void) {
        completion(currentEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ChargeEntry>) -> Void) {
        // 앱이 saveWidgetData + reloadTimelines 로 갱신하므로, 여기선 30분 후 안전 리프레시만.
        let entry = currentEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
    private func currentEntry() -> ChargeEntry {
        ChargeEntry(
            date: Date(),
            gas: decodeList("widget_gas_list", as: GasItem.self),
            ev: decodeList("widget_ev_list", as: EvItem.self),
            gasUpdated: updatedText("widget_gas_updated"),
            evUpdated: updatedText("widget_ev_updated"),
            opacity: bgOpacity()
        )
    }
}

// MARK: - 공통 UI 조각
private struct WidgetHeader: View {
    let icon: String
    let title: String
    let accent: Color
    let updated: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundColor(accent)
            Text(title).font(.system(size: 13, weight: .bold)).foregroundColor(.primary)
            Spacer()
            Text(updated).font(.system(size: 10)).foregroundColor(.mutedText)
        }
    }
}

private struct EmptyState: View {
    let text: String
    var body: some View {
        VStack {
            Spacer()
            Text(text).font(.system(size: 12)).foregroundColor(.mutedText).multilineTextAlignment(.center)
            Spacer()
        }.frame(maxWidth: .infinity)
    }
}

// 전일 대비 변동 화살표
private struct ChangeBadge: View {
    let change: Int
    var body: some View {
        if change == 0 { EmptyView() }
        else {
            let up = change > 0
            HStack(spacing: 1) {
                Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 7))
                Text("\(abs(change))").font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(up ? .evFull : .gasBlue)
        }
    }
}

// MARK: - 주유 행
private struct GasRow: View {
    let item: GasItem
    let best: Bool
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(best ? Color.gasBlue : Color.gasBlue.opacity(0.35))
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 12, weight: best ? .bold : .medium))
                    .lineLimit(1).foregroundColor(.primary)
                Text([item.brand, item.fuelLabel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 9)).foregroundColor(.mutedText).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(item.price > 0 ? "\(item.price)원" : "-")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(best ? .gasBlue : .primary)
                if let c = item.change { ChangeBadge(change: c) }
            }
        }
    }
}

// MARK: - 충전 행
private struct EvRow: View {
    let item: EvItem
    let best: Bool
    private var statusColor: Color {
        switch item.statusCode ?? 0 {
        case 1: return .evFull
        case 2: return .orange
        default: return .evGreen
        }
    }
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 12, weight: best ? .bold : .medium))
                    .lineLimit(1).foregroundColor(.primary)
                HStack(spacing: 4) {
                    if (item.maxKw ?? 0) > 0 {
                        Text("\(item.maxKw!)kW").font(.system(size: 9, weight: .semibold))
                            .foregroundColor((item.hasFast ?? false) ? .evGreen : .mutedText)
                    }
                    if (item.broken ?? 0) > 0 {
                        Text("고장 \(item.broken!)").font(.system(size: 9)).foregroundColor(.orange)
                    }
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                if item.total > 0 {
                    Text("\(item.available)/\(item.total)")
                        .font(.system(size: 13, weight: .bold)).foregroundColor(statusColor)
                    Text("가능").font(.system(size: 8)).foregroundColor(.mutedText)
                } else {
                    Text("-").font(.system(size: 13, weight: .bold)).foregroundColor(.mutedText)
                }
            }
        }
    }
}

// MARK: - 위젯 본문
private struct GasWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: ChargeEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(icon: "fuelpump.fill", title: "즐겨찾기 주유소", accent: .gasBlue, updated: entry.gasUpdated)
            if entry.gas.isEmpty {
                EmptyState(text: "즐겨찾기한 주유소가\n여기에 표시돼요")
            } else {
                ForEach(Array(entry.gas.prefix(rowCount(family)).enumerated()), id: \.offset) { i, item in
                    GasRow(item: item, best: i == 0)
                }
                Spacer(minLength: 0)
            }
        }
        .containerPadding()
    }
}

private struct EvWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: ChargeEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(icon: "bolt.fill", title: "즐겨찾기 충전소", accent: .evGreen, updated: entry.evUpdated)
            if entry.ev.isEmpty {
                EmptyState(text: "즐겨찾기한 충전소가\n여기에 표시돼요")
            } else {
                ForEach(Array(entry.ev.prefix(rowCount(family)).enumerated()), id: \.offset) { i, item in
                    EvRow(item: item, best: i == 0)
                }
                Spacer(minLength: 0)
            }
        }
        .containerPadding()
    }
}

private struct CombinedWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: ChargeEntry
    var body: some View {
        let rows = family == .systemLarge ? 2 : 1
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                WidgetHeader(icon: "fuelpump.fill", title: "주유", accent: .gasBlue, updated: entry.gasUpdated)
                if entry.gas.isEmpty {
                    Text("즐겨찾기 주유소 없음").font(.system(size: 10)).foregroundColor(.mutedText)
                } else {
                    ForEach(Array(entry.gas.prefix(rows).enumerated()), id: \.offset) { i, item in
                        GasRow(item: item, best: i == 0)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 5) {
                WidgetHeader(icon: "bolt.fill", title: "충전", accent: .evGreen, updated: entry.evUpdated)
                if entry.ev.isEmpty {
                    Text("즐겨찾기 충전소 없음").font(.system(size: 10)).foregroundColor(.mutedText)
                } else {
                    ForEach(Array(entry.ev.prefix(rows).enumerated()), id: \.offset) { i, item in
                        EvRow(item: item, best: i == 0)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .containerPadding()
    }
}

// containerBackground(iOS17+) — 배경 투명도 반영. 구버전은 padding 만.
private extension View {
    @ViewBuilder
    func containerPadding() -> some View {
        if #available(iOS 17.0, *) {
            self.padding(12)
        } else {
            self.padding(12)
        }
    }
}

private struct ChargeBackground: View {
    let opacity: Double
    var body: some View {
        Color(.systemBackground).opacity(max(0.15, opacity))
    }
}

// MARK: - Widget 정의
struct GasWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GasWidget", provider: ChargeProvider()) { entry in
            widgetContainer(entry) { GasWidgetView(entry: entry) }
        }
        .configurationDisplayName("즐겨찾기 주유소")
        .description("즐겨찾기한 주유소의 최저가를 홈 화면에서 확인해요.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct EvWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EvWidget", provider: ChargeProvider()) { entry in
            widgetContainer(entry) { EvWidgetView(entry: entry) }
        }
        .configurationDisplayName("즐겨찾기 충전소")
        .description("즐겨찾기한 충전소의 빈자리를 홈 화면에서 확인해요.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CombinedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CombinedWidget", provider: ChargeProvider()) { entry in
            widgetContainer(entry) { CombinedWidgetView(entry: entry) }
        }
        .configurationDisplayName("주유 + 충전")
        .description("즐겨찾기 주유소와 충전소를 한 위젯에서 확인해요.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// iOS17+ 는 containerBackground 필수, 구버전은 ZStack 배경.
@ViewBuilder
private func widgetContainer<Content: View>(_ entry: ChargeEntry, @ViewBuilder _ content: () -> Content) -> some View {
    if #available(iOS 17.0, *) {
        content().containerBackground(for: .widget) { ChargeBackground(opacity: entry.opacity) }
    } else {
        ZStack { ChargeBackground(opacity: entry.opacity); content() }
    }
}

// MARK: - Bundle
@main
struct ChargeWidgetBundle: WidgetBundle {
    var body: some Widget {
        GasWidget()
        EvWidget()
        CombinedWidget()
    }
}
