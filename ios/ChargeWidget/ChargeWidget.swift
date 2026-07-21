import WidgetKit
import SwiftUI
#if canImport(AppIntents)
import AppIntents
#endif

// ============================================================
// 전기차 기름차 — 홈위젯 (안드로이드 위젯 디자인 미러)
//  · GasWidget      즐겨찾기 주유소  (small/medium/large)
//  · EvWidget       즐겨찾기 충전소  (small/medium/large)
//  · CombinedWidget 주유 + 충전     (medium/large)
// 데이터: App Group(group.com.dksw.charge) UserDefaults
//  · widget_gas_list / widget_ev_list (JSON), widget_*_updated, widget_bg_opacity
// ============================================================

private let appGroupId = "group.com.dksw.charge"

// ─── 새로고침 인텐트 (iOS 17+) — 순수 Swift 로 서버 조회 후 위젯 데이터 갱신 ───
// Flutter/home_widget 를 익스텐션에 링크하면 위젯 프로세스 메모리 한도(30MB)·프리뷰
// 워치독에 걸려 갤러리가 뻗음 → 앱과 동일한 공개 API 를 URLSession 으로 직접 호출.
#if canImport(AppIntents)
private let apiBase = "https://charge.dksw4.com/api"

@available(iOS 17.0, *)
struct RefreshWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "새로고침"
    static var isDiscoverable = false

    @Parameter(title: "kind", default: "all") var kind: String

    init() {}
    init(kind: String) { self.kind = kind }

    func perform() async throws -> some IntentResult {
        if kind == "gas" || kind == "all" { await Self.refreshGas() }
        if kind == "ev" || kind == "all" { await Self.refreshEv() }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }

    private static func nowHHmm() -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: Date())
    }

    private static func fetchData(_ path: String) async -> [String: Any]? {
        guard let url = URL(string: apiBase + path) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return root["data"] as? [String: Any]
    }

    // 유종 라벨 → 오피넷 코드 (widget item 은 라벨만 보유)
    private static func fuelCode(_ label: String) -> String {
        switch label {
        case "고급휘발유": return "B034"
        case "경유": return "D047"
        case "LPG": return "K015"
        default: return "B027" // 휘발유
        }
    }

    static func refreshGas() async {
        guard let ud = UserDefaults(suiteName: appGroupId),
              let raw = ud.string(forKey: "widget_gas_list"),
              let d = raw.data(using: .utf8),
              var items = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]]
        else { return }
        for i in items.indices.prefix(4) {
            guard let id = items[i]["id"] as? String, !id.isEmpty else { continue }
            guard let data = await fetchData("/stations/gas/\(id)") else { continue }
            if let price = data["PRICE"] as? NSNumber { items[i]["price"] = price.intValue }
            let code = fuelCode(items[i]["fuelLabel"] as? String ?? "휘발유")
            if let delta = (data["price_delta_vs_yesterday"] as? [String: Any])?[code] as? NSNumber {
                items[i]["change"] = delta.intValue
            }
        }
        // 저렴한 순 (0=미상은 뒤로) — 앱 로직 미러
        items.sort {
            let a = ($0["price"] as? NSNumber)?.intValue ?? 0
            let b = ($1["price"] as? NSNumber)?.intValue ?? 0
            if a == 0 { return false }
            if b == 0 { return true }
            return a < b
        }
        if let out = try? JSONSerialization.data(withJSONObject: items),
           let str = String(data: out, encoding: .utf8) {
            ud.set(str, forKey: "widget_gas_list")
            ud.set(nowHHmm(), forKey: "widget_gas_updated")
        }
    }

    static func refreshEv() async {
        guard let ud = UserDefaults(suiteName: appGroupId),
              let raw = ud.string(forKey: "widget_ev_list"),
              let d = raw.data(using: .utf8),
              var items = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]]
        else { return }
        for i in items.indices.prefix(4) {
            guard let id = items[i]["id"] as? String, !id.isEmpty else { continue }
            guard let data = await fetchData("/stations/ev/\(id)"),
                  let chargers = data["chargers"] as? [[String: Any]] else { continue }
            let stats = chargers.map { ($0["stat"] as? NSNumber)?.intValue ?? 9 }
            let outputs = chargers.map { ($0["output"] as? NSNumber)?.intValue ?? 7 }
            let total = chargers.count
            let avail = stats.filter { $0 == 2 }.count
            let broken = stats.filter { $0 == 1 || $0 == 4 || $0 == 5 || $0 == 9 }.count
            items[i]["available"] = avail
            items[i]["total"] = total
            items[i]["broken"] = broken
            items[i]["hasFast"] = outputs.contains { $0 >= 50 }
            items[i]["maxKw"] = outputs.max() ?? 0
            items[i]["statusCode"] = (broken >= total && total > 0) ? 2 : (avail == 0 ? 1 : 0)
        }
        items.sort {
            (($0["available"] as? NSNumber)?.intValue ?? 0) >
            (($1["available"] as? NSNumber)?.intValue ?? 0)
        }
        if let out = try? JSONSerialization.data(withJSONObject: items),
           let str = String(data: out, encoding: .utf8) {
            ud.set(str, forKey: "widget_ev_list")
            ud.set(nowHHmm(), forKey: "widget_ev_updated")
        }
    }
}
#endif
// ─── 안드로이드 위젯 팔레트 (colors.xml 미러) ───
private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
    static let wInk       = Color(hex: 0x0F172A)
    static let wInk2      = Color(hex: 0x334155)
    static let wMuted     = Color(hex: 0x64748B)
    static let wMute2     = Color(hex: 0x94A3B8)
    static let wLine      = Color(hex: 0xE2E8F0)
    static let wLineSoft  = Color(hex: 0xF1F5F9)
    static let wBlue      = Color(hex: 0x2563EB)
    static let wBlueSoft  = Color(hex: 0xEFF6FF)
    static let wBlueText  = Color(hex: 0x1E40AF)
    static let wGreen     = Color(hex: 0x10B981)
    static let wGreen2    = Color(hex: 0x059669)
    static let wGreenSoft = Color(hex: 0xECFDF5)
    static let wGreenText = Color(hex: 0x047857)
    static let wAmberSoft = Color(hex: 0xFEF3C7)
    static let wAmberText = Color(hex: 0x92400E)
    static let wRed       = Color(hex: 0xEF4444)
    static let wRedSoft   = Color(hex: 0xFEE2E2)
    static let wRedText   = Color(hex: 0xB91C1C)
}

// ─── 데이터 모델 ───
struct GasItem: Identifiable {
    let id: String, name: String, brand: String
    let price: Int, isSelf: Bool, fuelLabel: String, change: Int
}
struct EvItem: Identifiable {
    let id: String, name: String
    let available: Int, total: Int, broken: Int
    let hasFast: Bool, maxKw: Int, statusCode: Int
}

struct ChargeEntry: TimelineEntry {
    let date: Date
    let gas: [GasItem]
    let ev: [EvItem]
    let gasUpdated: String
    let evUpdated: String
    let bgOpacity: Double
}

// ─── Provider ───
struct ChargeProvider: TimelineProvider {
    func placeholder(in context: Context) -> ChargeEntry { Self.load() }
    func getSnapshot(in context: Context, completion: @escaping (ChargeEntry) -> Void) {
        completion(Self.load())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ChargeEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [Self.load()], policy: .after(next)))
    }

    static func load() -> ChargeEntry {
        let ud = UserDefaults(suiteName: appGroupId)
        func arr(_ key: String) -> [[String: Any]] {
            guard let s = ud?.string(forKey: key), let d = s.data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]]
            else { return [] }
            return j
        }
        let gas = arr("widget_gas_list").map { m in
            GasItem(id: m["id"] as? String ?? "",
                    name: m["name"] as? String ?? "",
                    brand: m["brand"] as? String ?? "",
                    price: (m["price"] as? NSNumber)?.intValue ?? 0,
                    isSelf: (m["isSelf"] as? NSNumber)?.boolValue ?? false,
                    fuelLabel: m["fuelLabel"] as? String ?? "휘발유",
                    change: (m["change"] as? NSNumber)?.intValue ?? 0)
        }
        let ev = arr("widget_ev_list").map { m in
            EvItem(id: m["id"] as? String ?? "",
                   name: m["name"] as? String ?? "",
                   available: (m["available"] as? NSNumber)?.intValue ?? 0,
                   total: (m["total"] as? NSNumber)?.intValue ?? 0,
                   broken: (m["broken"] as? NSNumber)?.intValue ?? 0,
                   hasFast: (m["hasFast"] as? NSNumber)?.boolValue ?? false,
                   maxKw: (m["maxKw"] as? NSNumber)?.intValue ?? 0,
                   statusCode: (m["statusCode"] as? NSNumber)?.intValue ?? 0)
        }
        let opacity = Double(Int(ud?.string(forKey: "widget_bg_opacity") ?? "100") ?? 100) / 100.0
        return ChargeEntry(date: Date(), gas: gas, ev: ev,
                           gasUpdated: ud?.string(forKey: "widget_gas_updated") ?? "",
                           evUpdated: ud?.string(forKey: "widget_ev_updated") ?? "",
                           bgOpacity: opacity)
    }
}

// ─── 공용: 카드 배경 ───
private struct CardBackground: ViewModifier {
    let opacity: Double
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                Color.white.opacity(max(0.05, 0.98 * opacity))
            }
        } else {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(max(0.05, 0.98 * opacity)))
        }
    }
}

// ─── 공용: 헤더 (마크 + 타이틀 + 갱신시각) ───
private struct WidgetHeader: View {
    let title: String
    let updated: String
    var refreshKind: String = "all"
    var body: some View {
        HStack(spacing: 6) {
            if let pin = UIImage(named: "app_pin") ??
                UIImage(contentsOfFile: Bundle.main.path(forResource: "app_pin", ofType: "png") ?? "") {
                Image(uiImage: pin).resizable().scaledToFit()
                    .frame(width: 20, height: 20)
            }
            Text(title)
                .font(.system(size: 13, weight: .heavy))
                .foregroundColor(.wInk)
            Spacer(minLength: 0)
            #if canImport(AppIntents)
            if #available(iOS 17.0, *) {
                Button(intent: RefreshWidgetIntent(kind: refreshKind)) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.wMute2)
                }
                .buttonStyle(.plain)
            }
            #endif
            if !updated.isEmpty {
                HStack(spacing: 3) {
                    Circle().fill(Color.wGreen).frame(width: 5, height: 5)
                    Text(updated)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.wMute2)
                }
            }
        }
    }
}

// ─── 섹션 라벨 (● 주유 · 즐겨찾기 / ● 충전 · 잔여 자리) ───
private struct SectionLabel: View {
    let dot: Color
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(dot).frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.wMuted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4).padding(.top, 2)
    }
}

// ─── 공용: 강조행 배경 (그라데이션 + 좌측 액센트바) ───
private struct BestRowBackground: View {
    let accent: Color
    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: [accent.opacity(0.14), .clear],
                startPoint: .leading, endPoint: .trailing)
            Rectangle().fill(accent).frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// ─── 브랜드 로고 (번들 PNG) ───
private struct BrandLogo: View {
    let brand: String
    private var asset: String {
        switch brand {
        case "GSC": return "oil_gs"
        case "SKE": return "oil_sk"
        case "HDO": return "oil_hd"
        case "SOL": return "oil_soil"
        case "NHO": return "oil_nh"
        case "EX":  return "oil_ex"
        default:    return "brand_etc"
        }
    }
    var body: some View {
        Group {
            if let ui = bundleImage(asset) {
                Image(uiImage: ui).resizable().scaledToFit().padding(5)
            } else {
                Image(systemName: "fuelpump.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.wBlue)
            }
        }
        .frame(width: 32, height: 32)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.wLine, lineWidth: 1)))
    }
    private func bundleImage(_ name: String) -> UIImage? {
        if let p = Bundle.main.path(forResource: name, ofType: "png"),
           let img = UIImage(contentsOfFile: p) { return img }
        if let p = Bundle.main.path(forResource: "BrandLogos/\(name)", ofType: "png"),
           let img = UIImage(contentsOfFile: p) { return img }
        return nil
    }
}

// ─── 필(pill) ───
private struct Pill: View {
    let text: String
    let fg: Color
    let bg: Color
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(fg)
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .background(Capsule().fill(bg))
    }
}

// ─── 주유 행 ───
private struct GasRow: View {
    let item: GasItem
    let isBest: Bool
    var body: some View {
        HStack(spacing: 8) {
            BrandLogo(brand: item.brand)
            Text(item.name)
                .font(.system(size: 13, weight: .heavy))
                .foregroundColor(.wInk)
                .lineLimit(1)
            Spacer(minLength: 4)
            Pill(text: item.isSelf ? "셀프" : "일반", fg: .wInk2, bg: .wLineSoft)
            Text(item.fuelLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.wMuted)
            VStack(alignment: .trailing, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(item.price > 0 ? priceString(item.price) : "—")
                        .font(.system(size: 19, weight: .heavy))
                        .tracking(-0.6)
                        .foregroundColor(.wInk)
                    if item.price > 0 {
                        Text("원")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.wMuted)
                    }
                }
                if item.change != 0 {
                    Text(item.change > 0 ? "▲ \(item.change)" : "▼ \(-item.change)")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(item.change > 0 ? .wRed : .wGreen2)
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(isBest ? AnyView(BestRowBackground(accent: .wBlue)) : AnyView(Color.clear))
    }
    private func priceString(_ p: Int) -> String {
        p >= 1000 ? "\(p / 1000),\(String(format: "%03d", p % 1000))" : "\(p)"
    }
}

// ─── 충전 행 ───
private struct EvRow: View {
    let item: EvItem
    let isBest: Bool
    private var isFull: Bool {
        (item.broken > 0 && item.broken >= item.total && item.total > 0) || item.statusCode == 2
    }
    private var isBusy: Bool { !isFull && item.available == 0 }
    var body: some View {
        HStack(spacing: 8) {
            // EV 배지 (안드 미러: 초록 그라데이션 + EV)
            Text("EV")
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [.wGreen, .wGreen2],
                                             startPoint: .top, endPoint: .bottom)))
            Text(item.name)
                .font(.system(size: 13, weight: .heavy))
                .foregroundColor(.wInk)
                .lineLimit(1)
            Spacer(minLength: 4)
            Pill(text: item.hasFast ? "급속" : "완속",
                 fg: item.hasFast ? .wGreenText : .wBlueText,
                 bg: item.hasFast ? .wGreenSoft : .wBlueSoft)
            if item.maxKw > 0 {
                Text("\(item.maxKw)kW")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.wMuted)
            }
            VStack(alignment: .trailing, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(item.available)")
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundColor(isFull || isBusy ? .wRed : .wGreen)
                    Text("/\(item.total)")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(.wInk2)
                }
                Text(isFull ? "점검 중" : (isBusy ? "만차" : "여유 가용"))
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(isFull ? .wRedText : (isBusy ? .wAmberText : .wGreenText))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(isBest ? AnyView(BestRowBackground(accent: .wGreen)) : AnyView(Color.clear))
    }
}

// ─── 빈 상태 ───
private struct EmptyRows: View {
    let message: String
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "star")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.wMute2)
            Text(message)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.wMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private func rowCount(for family: WidgetFamily) -> Int {
    switch family {
    case .systemSmall: return 2
    case .systemMedium: return 2
    default: return 4
    }
}

// ─── 주유 위젯 ───
struct GasWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: ChargeEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(title: "전기차 기름차", updated: entry.gasUpdated, refreshKind: "gas")
            SectionLabel(dot: .wBlue, text: "주유 · 즐겨찾기")
            if entry.gas.isEmpty {
                EmptyRows(message: "앱에서 주유소를\n즐겨찾기 해보세요")
            } else {
                let items = Array(entry.gas.prefix(rowCount(for: family)))
                VStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                        Link(destination: URL(string: "chargehelper:///widget?type=gas&id=\(it.id)")!) {
                            GasRow(item: it, isBest: i == 0)
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(12)
        .modifier(CardBackground(opacity: entry.bgOpacity))
        .widgetURL(URL(string: "chargehelper:///widget?type=gas"))
    }
}

// ─── 충전 위젯 ───
struct EvWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: ChargeEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(title: "전기차 기름차", updated: entry.evUpdated, refreshKind: "ev")
            SectionLabel(dot: .wGreen, text: "충전 · 잔여 자리")
            if entry.ev.isEmpty {
                EmptyRows(message: "앱에서 충전소를\n즐겨찾기 해보세요")
            } else {
                let items = Array(entry.ev.prefix(rowCount(for: family)))
                VStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                        Link(destination: URL(string: "chargehelper:///widget?type=ev&id=\(it.id)")!) {
                            EvRow(item: it, isBest: i == 0)
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(12)
        .modifier(CardBackground(opacity: entry.bgOpacity))
        .widgetURL(URL(string: "chargehelper:///widget?type=ev"))
    }
}

// ─── 통합 위젯 (주유 + 충전) ───
struct CombinedWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: ChargeEntry
    var body: some View {
        let per = family == .systemLarge ? 2 : 1
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(title: "전기차 기름차", updated: entry.gasUpdated)
            if entry.gas.isEmpty && entry.ev.isEmpty {
                EmptyRows(message: "앱에서 주유소·충전소를\n즐겨찾기 해보세요")
            } else {
                VStack(spacing: 2) {
                    if !entry.gas.isEmpty {
                        SectionLabel(dot: .wBlue, text: "주유 · 즐겨찾기")
                    }
                    ForEach(Array(entry.gas.prefix(per).enumerated()), id: \.element.id) { i, it in
                        Link(destination: URL(string: "chargehelper:///widget?type=gas&id=\(it.id)")!) {
                            GasRow(item: it, isBest: i == 0)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    if !entry.ev.isEmpty {
                        SectionLabel(dot: .wGreen, text: "충전 · 잔여 자리")
                    }
                    ForEach(Array(entry.ev.prefix(per).enumerated()), id: \.element.id) { i, it in
                        Link(destination: URL(string: "chargehelper:///widget?type=ev&id=\(it.id)")!) {
                            EvRow(item: it, isBest: i == 0)
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(12)
        .modifier(CardBackground(opacity: entry.bgOpacity))
        .widgetURL(URL(string: "chargehelper:///widget?type=combined"))
    }
}

// ─── 위젯 정의 ───
struct GasWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GasWidget", provider: ChargeProvider()) { entry in
            GasWidgetView(entry: entry)
        }
        .configurationDisplayName("즐겨찾기 주유소")
        .description("즐겨찾기한 주유소의 실시간 최저가를 보여줍니다.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct EvWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EvWidget", provider: ChargeProvider()) { entry in
            EvWidgetView(entry: entry)
        }
        .configurationDisplayName("즐겨찾기 충전소")
        .description("즐겨찾기한 충전소의 빈자리를 실시간으로 보여줍니다.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CombinedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CombinedWidget", provider: ChargeProvider()) { entry in
            CombinedWidgetView(entry: entry)
        }
        .configurationDisplayName("주유 + 충전")
        .description("즐겨찾기 주유소와 충전소를 한 번에 보여줍니다.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct ChargeWidgetBundle: WidgetBundle {
    var body: some Widget {
        GasWidget()
        EvWidget()
        CombinedWidget()
    }
}
