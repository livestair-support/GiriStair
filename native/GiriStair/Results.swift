import SwiftUI

struct GiriResultsView: View {
    @EnvironmentObject private var store: GiriStore
    @State private var selectedFormat: EventFormat = .live
    @State private var didInitializeFormat = false
    @State private var showsUnentered = false
    @State private var year = "all"
    @State private var collapsed = false
    private var accent: Color { GiriEventPresentation.accent(selectedFormat) }
    private var tournaments: [GiriEvent] {
        store.events.filter {
            $0.meetingType == .tournament && $0.isActualParticipant && $0.eventFormat == selectedFormat &&
            (year == "all" || String(Calendar(identifier: .gregorian).component(.year, from: GiriEventPresentation.date($0) ?? $0.createdAt)) == year)
        }
    }
    private var years: [String] {
        Array(Set(store.events.filter { $0.meetingType == .tournament && $0.eventFormat == selectedFormat }.map {
            String(Calendar(identifier: .gregorian).component(.year, from: GiriEventPresentation.date($0) ?? $0.createdAt))
        })).sorted(by: >)
    }
    private var filtered: [GiriEvent] {
        let now = Date()
        return tournaments.filter {
            showsUnentered ? ($0.hasEnded(now: now) && !$0.hasFinalResult) : $0.hasFinalResult
        }.sorted { (GiriEventPresentation.date($0) ?? $0.createdAt) > (GiriEventPresentation.date($1) ?? $1.createdAt) }
    }
    // Intermediate advancement, upcoming events, and other players' podiums
    // never become one's own completed participation or final placement.
    private var completed: [GiriEvent] { tournaments.filter { $0.isCountableParticipation() } }
    private var champions: Int { completed.filter { $0.effectivePlacement == 1 }.count }
    private var runnersUp: Int { completed.filter { $0.effectivePlacement == 2 }.count }
    private var placed: Int {
        completed.filter { ($0.effectivePlacement ?? 0) > 2 || ($0.tournamentResult?.outcome == .placed && $0.effectivePlacement == nil) }.count
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            VStack(spacing: 0) {
                filterHeader
                ScrollView {
                    LazyVStack(spacing: 0) {
                        statistics.padding(.horizontal, 18).padding(.vertical, 6)
                        HStack {
                            Text(showsUnentered ? "結果未入力の大会" : "結果記入済の大会")
                                .font(.system(size: appFontSize(18), weight: .bold, design: .rounded))
                            Spacer()
                            Text("\(filtered.count)件").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 8)
                        if filtered.isEmpty {
                            CenteredEmptyMessage(systemImage: "trophy", title: showsUnentered ? "結果未入力の大会はありません" : "結果を記入した大会がありません")
                                .frame(maxWidth: .infinity, minHeight: 145)
                                .appTintedCard(accentColor: accent).padding(.horizontal, 18)
                        }
                        ForEach(filtered) { event in
                            resultRow(event)
                                .buttonStyle(.plain)
                                .padding(.horizontal, 18).padding(.vertical, 6)
                        }
                    }.padding(.bottom, 104)
                }
            }
        }
        .background(appBackgroundColor)
        .safeAreaInset(edge: .top, spacing: 0) { AppPageHeader(title: "戦績", systemImage: "trophy", accentColor: accent) }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard !didInitializeFormat else { return }
            selectedFormat = store.preferences.effectiveFormatOrder.first ?? .live
            didInitializeFormat = true
        }
        .onChange(of: store.preferences.effectiveFormatOrder) { previous, next in
            if selectedFormat == previous.first { selectedFormat = next.first ?? .live }
        }
        .onChange(of: selectedFormat) { _, _ in year = "all" }
    }
    @ViewBuilder private func resultRow(_ event: GiriEvent) -> some View {
        if showsUnentered {
            NavigationLink { GiriResultEntry(eventID: event.id) } label: {
                GiriEventCard(event: event, showsResult: true, resultActionTitle: "結果を入力する")
            }
        } else {
            NavigationLink { GiriEventDetail(eventID: event.id) } label: { GiriEventCard(event: event, showsResult: true) }
        }
    }
    private var filterHeader: some View {
        VStack(spacing: 5) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3").font(.system(size: appFontSize(16), weight: .semibold)).foregroundStyle(accent).frame(width: 22)
                Text("表示・絞り込み").font(.system(size: appFontSize(18), weight: .bold, design: .rounded))
                Spacer()
                Text("\(filtered.count)件").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                AppHeaderCollapseButton(isCollapsed: $collapsed, tintColor: accent)
            }
            GiriFormatPicker(selection: $selectedFormat, formats: store.preferences.effectiveFormatOrder)
            Picker("大会の記録", selection: $showsUnentered) {
                Text("結果記入済").tag(false)
                Text("結果未入力").tag(true)
            }.pickerStyle(.segmented).tint(accent)
            if !collapsed {
                Divider().overlay(appSeparatorColor)
                GiriListFilterMenu(title: "年", selection: $year,
                    options: [("all", "全期間")] + years.map { ($0, $0 + "年") })
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
            }.frame(height: 72)
            Divider().overlay(appSeparatorColor)
            HStack {
                Text("終了した大会").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("\(completed.count)件").font(.body.weight(.medium))
            }
        }.padding(14).appTintedCard(accentColor: accent)
    }
    private func metric(_ title: String, _ count: Int, image: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Label(title, systemImage: image).font(.caption.weight(.medium)).foregroundStyle(color)
            Text("\(count)").font(.system(size: appFontSize(26), weight: .bold, design: .rounded)).foregroundStyle(.primary)
        }.frame(maxWidth: .infinity)
    }
}
