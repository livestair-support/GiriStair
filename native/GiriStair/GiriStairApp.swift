import SwiftUI

/// The shipping iPhone entry point. No Flutter engine or emulated controls.
@main
@MainActor
struct GiriStairApp: App {
    @StateObject private var store: GiriStore
    @StateObject private var navigation = GiriNavigation()

    init() {
        #if DEBUG
        let store = ProcessInfo.processInfo.arguments.contains("--uitest-tab-navigation")
            ? GiriNavigationTestSeed.makeStore() : GiriStore()
        #else
        let store = GiriStore()
        #endif
        _store = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        WindowGroup {
            GiriRootView()
                .environmentObject(store)
                .environmentObject(navigation)
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .preferredColorScheme(preferredAppearance)
        }
    }

    private var preferredAppearance: ColorScheme? {
        switch store.preferences.theme {
        case "dark": return .dark
        case "light", "stair": return .light
        default: return nil
        }
    }
}

@MainActor
private struct GiriRootView: View {
    @EnvironmentObject private var store: GiriStore
    @EnvironmentObject private var navigation: GiriNavigation
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingResult: GiriEvent?
    @State private var resultEditor: GiriEvent?

    var body: some View {
        Group {
            if store.loaded {
                tabs
            } else {
                NavigationStack {
                    Form {
                        Section {
                            AppCardSectionTitle(title: "保存データの確認", systemImage: "externaldrive.badge.exclamationmark", accentColor: AppSectionAccent.ticket)
                            Text("保存データを読み込めませんでした。元のデータを保持したまま、バックアップから復元できます。")
                            Button("読み込みをやり直す") { store.reload() }
                            NavigationLink("バックアップから復元") { GiriSettingsView() }
                        }.appSectionCardStyle(accentColor: AppSectionAccent.ticket)
                    }.appEditorFormStyle().navigationTitle("GiriStair")
                }
            }
        }
        .tint(accentActionColor)
        .alert("保存データの確認", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("閉じる", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .sheet(isPresented: Binding(get: { store.loaded && !store.preferences.onboardingCompleted }, set: { _ in })) {
            GiriFirstProfileView().interactiveDismissDisabled()
        }
        .alert("大会の結果を残しますか？", isPresented: Binding(get: { pendingResult != nil }, set: { if !$0 { pendingResult = nil } })) {
            Button("後で", role: .cancel) { pendingResult = nil }
            Button("入力する") { resultEditor = pendingResult; pendingResult = nil }
        } message: { Text(pendingResult?.title ?? "") }
        .sheet(item: $resultEditor) { event in
            NavigationStack { GiriResultEntry(eventID: event.id) }
        }
        .task {
            synchronizeTheme()
            if store.loaded { store.run { try store.ensureCurrentSiteCycles() } }
            await NotificationsCoordinator.sync(store: store)
            promptForResult()
        }
        .onChange(of: store.document) { _, _ in
            synchronizeTheme()
            Task { await NotificationsCoordinator.sync(store: store) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if store.loaded { store.run { try store.ensureCurrentSiteCycles() } }
                Task { await NotificationsCoordinator.sync(store: store) }
                promptForResult()
            }
        }
    }

    private var tabs: some View {
        TabView(selection: $navigation.selectedTab) {
            NavigationStack { GiriEventEditor(onSaved: { navigation.selectedTab = 1 }) }
                .tabItem { Label("登録", systemImage: "plus.circle.fill") }.tag(0)
            NavigationStack { GiriListView() }
                .tabItem { Label("一覧", systemImage: "clock.fill") }.tag(1)
            NavigationStack { GiriResultsView() }
                .tabItem { Label("戦績", systemImage: "trophy.fill") }.tag(2)
            GiriThinkingView()
                .tabItem { Label("お題/回答", systemImage: "checklist") }.tag(3)
            NavigationStack { GiriSettingsView() }
                .tabItem { Label("設定", systemImage: "gearshape.fill") }.tag(4)
        }
    }

    private func synchronizeTheme() {
        let mode = store.preferences.theme == "stair" ? "livestair" : store.preferences.theme
        if UserDefaults.standard.string(forKey: "appearanceMode") != mode {
            UserDefaults.standard.set(mode, forKey: "appearanceMode")
        }
    }

    private func promptForResult() {
        guard store.loaded, store.preferences.onboardingCompleted,
              !store.preferences.hasShownInitialResultPrompt,
              pendingResult == nil, resultEditor == nil else { return }
        let now = Date()
        let candidate = store.events.filter { event in
            event.eventFormat == .live && event.meetingType == .tournament &&
            event.isActualParticipant && !event.hasFinalResult && event.hasEnded(now: now)
        }.sorted { ($0.eventDate ?? $0.startsAt ?? $0.createdAt) > ($1.eventDate ?? $1.startsAt ?? $1.createdAt) }.first
        if let candidate {
            var preferences = store.preferences
            preferences.hasShownInitialResultPrompt = true
            store.run {
                try store.savePreferences(preferences)
                pendingResult = candidate
            }
        }
    }
}

private struct GiriFirstProfileView: View {
    @EnvironmentObject private var store: GiriStore
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AppCardSectionTitle(title: "自分のプロフィール", systemImage: "person.crop.circle", accentColor: AppSectionAccent.artist)
                    TextField("自分の名前", text: $name).textContentType(.nickname)
                    Button("はじめる") {
                        var preferences = store.preferences
                        preferences.selfName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        preferences.onboardingCompleted = true
                        store.run { try store.savePreferences(preferences); playLiveStairSaveFeedback() }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.appSectionCardStyle(accentColor: AppSectionAccent.artist)
            }
            .appEditorFormStyle()
            .navigationTitle("GiriStair")
            .onAppear { name = store.preferences.selfName }
        }
    }
}

struct BrandWordmark: View {
    var body: some View {
        Image("BrandWordmark").resizable().scaledToFit()
            .accessibilityLabel("GiriStair")
    }
}
