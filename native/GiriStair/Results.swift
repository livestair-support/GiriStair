import SwiftUI

struct GiriResultsView: View {
    @EnvironmentObject private var store: GiriStore
    @State private var kind = "all"
    @State private var resultFilter = "all"
    @State private var year = "all"
    @State private var collapsed = false
    private let accent = AppSectionAccent.ticket
    private var tournaments: [GiriEvent] {
        store.events.filter {
            $0.meetingType == .tournament && $0.isParticipating && $0.status != .canceled &&
            (kind == "all" || $0.kind.rawValue == kind) &&
            (year == "all" || String(Calendar.current.component(.year, from: GiriEventPresentation.date($0) ?? $0.createdAt)) == year)
        }
    }
    private var years: [String] {
        Array(Set(store.events.filter { $0.meetingType == .tournament }.map {
            String(Calendar.current.component(.year, from: GiriEventPresentation.date($0) ?? $0.createdAt))
        })).sorted(by: >)
    }
    private var filtered: [GiriEvent] {
        tournaments.filter {
            resultFilter == "all" || (resultFilter == "recorded" ? $0.hasRecordedResult : !$0.hasRecordedResult)
        }.sorted { (GiriEventPresentation.date($0) ?? $0.createdAt) > (GiriEventPresentation.date($1) ?? $1.createdAt) }
    }
    // Only an explicitly recorded final outcome/rank of one's attended event is
    // counted. A stage's advancement and another player's podium are separate.
    private var completed: [GiriEvent] { tournaments.filter { $0.status == .attended } }
    private var champions: Int { completed.filter { $0.effectivePlacement == 1 }.count }
    private var runnersUp: Int { completed.filter { $0.effectivePlacement == 2 }.count }
    private var placed: Int {
        completed.filter {
            ($0.effectivePlacement ?? 0) > 2 ||
            ($0.tournamentResult?.outcome == .placed && $0.effectivePlacement == nil)
        }.count
    }
    var body: some View {
        VStack(spacing: 0) {
            filterHeader
            ScrollView {
                LazyVStack(spacing: 0) {
                statistics
                    .padding(.horizontal, 18).padding(.vertical, 6)
                HStack {
                    Text("大会の記録").font(.system(size: appFontSize(18), weight: .bold, design: .rounded))
                    Spacer()
                    Text("\(filtered.count)件").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 8)
                if filtered.isEmpty {
                    CenteredEmptyMessage(systemImage: "trophy", title: tournaments.isEmpty ? "大会の記録がありません" : "該当する結果がありません")
                        .frame(maxWidth: .infinity, minHeight: 145)
                        .appTintedCard(accentColor: accent).padding(.horizontal, 18)
                }
                ForEach(filtered) { event in
                    NavigationLink { GiriEventDetail(eventID: event.id) } label: {
                        GiriEventCard(event: event, showsResult: true)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 18).padding(.vertical, 6)
                }
            }
                .padding(.bottom, 104)
            }
        }
        .background(appBackgroundColor)
        .safeAreaInset(edge: .top, spacing: 0) {
            AppPageHeader(title: "戦績", systemImage: "trophy", accentColor: accent)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
    private var filterHeader: some View {
        VStack(spacing: 5) {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: appFontSize(16), weight: .semibold))
                        .foregroundStyle(accent).frame(width: 22)
                    Text("表示・絞り込み").font(.system(size: appFontSize(18), weight: .bold, design: .rounded))
                    Spacer()
                    Text("\(filtered.count)件").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    AppHeaderCollapseButton(isCollapsed: $collapsed, tintColor: accent)
                }
                if !collapsed {
                    Divider().overlay(appSeparatorColor)
                    HStack(spacing: 0) {
                        GiriListFilterMenu(title: "年", selection: $year,
                                           options: [("all", "全期間")] + years.map { ($0, $0) })
                        Divider().overlay(appSeparatorColor).frame(height: 30).padding(.horizontal, 9)
                        GiriListFilterMenu(title: "形式", selection: $kind, options: [
                            ("all", "全形式"), ("live", "生大喜利"), ("online", "ネット大喜利")])
                    }
                    Divider().overlay(appSeparatorColor)
                    GiriListFilterMenu(title: "結果", selection: $resultFilter, options: [
                        ("all", "すべて"), ("recorded", "結果あり"), ("unrecorded", "未入力")])
                }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
        .appTintedCard(accentColor: accent, cornerRadius: 20, railVerticalInset: 14, lightTintOpacity: 0.065)
        .padding(.horizontal, 18).padding(.bottom, 12)
    }
    private var statistics: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppCardSectionTitle(title: "最終成績", systemImage: "trophy", accentColor: accent)
            HStack(spacing: 0) {
                metric("優勝", champions, image: "trophy.fill", color: accent)
                Divider().overlay(appSeparatorColor)
                metric("準優勝", runnersUp, image: "medal.fill", color: .secondary)
                Divider().overlay(appSeparatorColor)
                metric("入賞", placed, image: "rosette", color: AppSectionAccent.artist)
            }
            .frame(height: 72)
            Divider().overlay(appSeparatorColor)
            HStack {
                Text("結果入力済み").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("\(tournaments.filter(\.hasRecordedResult).count)件").font(.body.weight(.medium))
                Text("／ \(tournaments.count)件").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .appTintedCard(accentColor: accent)
    }
    private func metric(_ title: String, _ count: Int, image: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Label(title, systemImage: image).font(.caption.weight(.medium)).foregroundStyle(color)
            Text("\(count)").font(.system(size: appFontSize(26), weight: .bold, design: .rounded)).foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}
