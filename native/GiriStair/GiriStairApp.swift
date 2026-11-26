import SwiftUI
import UIKit

/// The shipping iPhone entry point. No Flutter engine or emulated controls.
@main
@MainActor
struct GiriStairApp: App {
    @StateObject private var store: GiriStore
    @StateObject private var accountSync: AccountSyncCoordinator
    @StateObject private var navigation: GiriNavigation

    init() {
        #if DEBUG
        let store = ProcessInfo.processInfo.arguments.contains("--uitest-tab-navigation")
            ? GiriNavigationTestSeed.makeStore() : GiriStore()
        #else
        let store = GiriStore()
        #endif
        let accountSync = AccountSyncCoordinator(app: "giristair")
        let navigation = GiriNavigation()
        let deviceName: @MainActor () -> String = { [weak store] in
            let model = UIDevice.current.model
            let name = store?.preferences.selfName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? model : "\(name)の\(model)"
        }
        store.onAccountDataChanged = { [weak accountSync] in accountSync?.localDidChange() }
        accountSync.connect(snapshot: { [weak store] in
            guard let store else { throw GiriDataError.notLoaded }
            let snapshot = try store.accountSnapshot()
            return AccountSyncLocalSnapshot(
                data: snapshot.data, lastModified: snapshot.lastModified, isPristine: snapshot.isPristine,
                deviceName: deviceName()
            )
        }, apply: { [weak store, weak navigation, weak accountSync] data in
            guard let store else { throw GiriDataError.notLoaded }
            if let data {
                try store.applyAccountSnapshot(data)
            } else {
                try store.deleteAllData(notifyAccount: false, removing: GiriAutoBackup.deviceFiles().map(\.url))
                navigation?.resetAfterDataDeletion(includingSettings: accountSync?.isBusy == false)
            }
        }, deviceName: deviceName)
        _store = StateObject(wrappedValue: store)
        _accountSync = StateObject(wrappedValue: accountSync)
        _navigation = StateObject(wrappedValue: navigation)
        // 時刻の入力（SwiftUI の DatePicker）は5分刻み。
        UIDatePicker.appearance().minuteInterval = 5
    }

    var body: some Scene {
        WindowGroup {
            GiriRootView()
                .environmentObject(store)
                .environmentObject(accountSync)
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
    @EnvironmentObject private var accountSync: AccountSyncCoordinator
    @EnvironmentObject private var navigation: GiriNavigation
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingResult: GiriEvent?
    /// 0.36：ページの参加者を確かめていた会が終わった後の、参加者の確定。
    @State private var participantReview: GiriParticipantReviewItem?
    @State private var checkingParticipants = false

    var body: some View {
        Group {
            if store.loaded {
                // 0.27：GiriStair テーマとほかのテーマを切り替えた時は、色を読み直すため全体を描き直す
                // （ライト／ダーク／端末に合わせるは外観で色が決まるので、描き直さなくても変わる）。
                tabs.id(store.preferences.theme == "stair")
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
            Button("入力する") {
                // 結果入力は戦績タブで開く。
                if let event = pendingResult { navigation.openResultEntry(event.id) }
                pendingResult = nil
            }
        } message: { Text(pendingResult?.title ?? "") }
        .sheet(item: $participantReview, onDismiss: {
            // 確定（または「後で」）の後に、ほかの終わった会と結果の入力の案内を続ける。
            Task {
                await promptForParticipantConfirmation()
                promptForResult()
            }
        }) { item in
            NavigationStack {
                GiriParticipantChangesView(eventID: item.eventID, confirming: true, readFailed: item.readFailed)
            }
        }
        .task {
            accountSync.setActive(scenePhase == .active)
            synchronizeTheme()
            if store.loaded { store.run { try store.ensureCurrentSiteCycles() } }
            // 0.19：1日1回、最初に開いた時に自動バックアップを作る（LiveStair と同じ）。
            GiriAutoBackup.runIfNeeded(store: store)
            // 0.34.1：同じ回（「2回戦」と「予選2回戦」）をまとめる（バックアップの後）。
            if store.loaded { store.run { try store.mergeDuplicateTournamentRounds() } }
            await NotificationsCoordinator.sync(store: store)
            await promptForParticipantConfirmation()
            promptForResult()
        }
        .onChange(of: store.document) { _, _ in
            synchronizeTheme()
            Task { await NotificationsCoordinator.sync(store: store) }
        }
        .onChange(of: navigation.dataDeletionToken) { _, _ in pendingResult = nil }
        .onChange(of: scenePhase) { _, phase in
            accountSync.setActive(phase == .active)
            if phase == .active {
                if store.loaded { store.run { try store.ensureCurrentSiteCycles() } }
                GiriAutoBackup.runIfNeeded(store: store)
                if store.loaded { store.run { try store.mergeDuplicateTournamentRounds() } }
                Task { await NotificationsCoordinator.sync(store: store) }
                Task {
                    await promptForParticipantConfirmation()
                    promptForResult()
                }
            }
        }
    }

    private var tabs: some View {
        TabView(selection: $navigation.selectedTab) {
            NavigationStack { GiriEventEditor(onSaved: { navigation.selectedTab = 1 }) }
                .id(navigation.dataDeletionToken)
                .tabItem { Label("登録", systemImage: "plus.circle.fill") }.tag(0)
            NavigationStack { GiriListView() }
                .id(navigation.dataDeletionToken)
                .tabItem { Label("一覧", systemImage: "clock.fill") }.tag(1)
            NavigationStack { GiriResultsView() }
                .id(navigation.dataDeletionToken)
                .tabItem { Label("戦績", systemImage: "trophy.fill") }.tag(2)
            GiriThinkingView()
                .id(navigation.dataDeletionToken)
                .tabItem { Label("お題/回答", systemImage: "checklist") }.tag(3)
            NavigationStack { GiriSettingsView() }
                .id(navigation.settingsDeletionToken)
                .tabItem { Label("設定", systemImage: "gearshape.fill") }.tag(4)
        }
        .background {
            TabBarDoubleTapObserver(targetTabIndex: 0) {
                navigation.registrationClearToken += 1
            }
            .frame(width: 0, height: 0)
        }
    }

    private func synchronizeTheme() {
        giriSynchronizeAppearanceMode(store.preferences.theme)
    }

    /// 0.36：ページの参加者を確かめていた会が終わったら、次の起動で1度だけ最後にページを読み、参加者を確定してもらう。
    /// 自分が行かなかった会（興味あり・キャンセルなど）は、聞かずに確かめるのをやめる。
    private func promptForParticipantConfirmation() async {
        guard store.loaded, store.preferences.onboardingCompleted, participantReview == nil, pendingResult == nil, !checkingParticipants else { return }
        let now = Date()
        let ended = store.events.filter { $0.participantSync?.state == .watching && $0.hasEnded(now: now) }
        guard !ended.isEmpty else { return }
        let skipped = ended.filter { !$0.asksParticipantConfirmation }.map(\.id)
        if !skipped.isEmpty { store.run { try store.setParticipantWatchState(.stopped, eventIDs: skipped) } }
        guard let event = ended.filter(\.asksParticipantConfirmation).sorted(by: {
            ($0.participationEndDate ?? $0.eventDate ?? $0.createdAt) < ($1.participationEndDate ?? $1.eventDate ?? $1.createdAt)
        }).first else { return }
        checkingParticipants = true
        let page = try? await giriFetchParticipantPage(for: event, store: store)
        store.run { try store.recordParticipantPage(eventID: event.id, page: page, at: Date(), state: .confirming) }
        checkingParticipants = false
        guard store.events.first(where: { $0.id == event.id })?.participantSync?.state == .confirming else { return }
        participantReview = GiriParticipantReviewItem(eventID: event.id, confirming: true, readFailed: page == nil)
    }

    private func promptForResult() {
        guard store.loaded, store.preferences.onboardingCompleted,
              !store.preferences.hasShownInitialResultPrompt,
              pendingResult == nil, participantReview == nil, !checkingParticipants else { return }
        let now = Date()
        let candidate = store.events.filter { event in
            event.eventFormat == .live && event.meetingType == .tournament &&
            event.isActualParticipant && event.isSelfPlayer && !event.hasFinalResult && event.hasEnded(now: now)
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
                    GiriAccountSyncRow()
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
            .onChange(of: store.preferences.selfName) { _, newName in name = newName }
        }
    }
}

struct BrandWordmark: View {
    var body: some View {
        Image("BrandWordmark").resizable().scaledToFit()
            .accessibilityLabel("GiriStair")
    }
}

// LiveStair ContentView.swift TabBarDoubleTapObserver（登録タブを続けて2回押すと、入力内容を空にする確認を出す）。
struct TabBarDoubleTapObserver:
    UIViewControllerRepresentable {
    
    let targetTabIndex: Int
    let onDoubleTap: () -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            targetTabIndex:
                targetTabIndex,
            onDoubleTap:
                onDoubleTap
        )
    }
    
    func makeUIViewController(
        context: Context
    ) -> ObserverViewController {
        let controller =
        ObserverViewController()
        
        controller.coordinator =
        context.coordinator
        
        return controller
    }
    
    func updateUIViewController(
        _ uiViewController:
        ObserverViewController,
        context: Context
    ) {
        context.coordinator
            .targetTabIndex =
        targetTabIndex
        
        context.coordinator
            .onDoubleTap =
        onDoubleTap
        
        uiViewController.coordinator =
        context.coordinator
        
        uiViewController
            .attachToTabBarController()
    }
    
    static func dismantleUIViewController(
        _ uiViewController:
        ObserverViewController,
        coordinator: Coordinator
    ) {
        coordinator.uninstall()
    }
    
    final class ObserverViewController:
        UIViewController {
        
        weak var coordinator:
        Coordinator?
        
        override func loadView() {
            let transparentView =
            UIView(frame: .zero)
            
            transparentView.backgroundColor =
                .clear
            
            transparentView.isUserInteractionEnabled =
            false
            
            view = transparentView
        }
        
        override func viewDidAppear(
            _ animated: Bool
        ) {
            super.viewDidAppear(animated)
            
            attachToTabBarController()
        }
        
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            
            attachToTabBarController()
        }
        
        func attachToTabBarController() {
            DispatchQueue.main.async {
                [weak self] in
                
                guard
                    let self,
                    let coordinator
                else {
                    return
                }
                
                coordinator.installIfNeeded(
                    from: self
                )
            }
        }
    }
    
    final class Coordinator:
        NSObject,
        UIGestureRecognizerDelegate {
        
        var targetTabIndex: Int
        var onDoubleTap: () -> Void
        
        private weak var installedTabBar:
        UITabBar?
        
        private var tapRecognizer:
        UITapGestureRecognizer?
        
        private var lastTargetTapTime:
        TimeInterval?
        
        private let maximumDoubleTapInterval:
        TimeInterval = 0.55
        
        init(
            targetTabIndex: Int,
            onDoubleTap:
            @escaping () -> Void
        ) {
            self.targetTabIndex =
            targetTabIndex
            
            self.onDoubleTap =
            onDoubleTap
        }
        
        func installIfNeeded(
            from controller:
            UIViewController
        ) {
            guard let tabBarController =
                    findTabBarController(
                        from: controller
                    )
            else {
                return
            }
            
            let tabBar =
            tabBarController.tabBar
            
            if installedTabBar === tabBar,
               tapRecognizer != nil {
                return
            }
            
            uninstall()
            
            let recognizer =
            UITapGestureRecognizer(
                target: self,
                action:
                    #selector(
                        handleTabBarTap(
                            _:
                        )
                    )
            )
            
            recognizer.numberOfTapsRequired =
            1
            
            recognizer.numberOfTouchesRequired =
            1
            
            recognizer.cancelsTouchesInView =
            false
            
            recognizer.delaysTouchesBegan =
            false
            
            recognizer.delaysTouchesEnded =
            false
            
            recognizer.delegate =
            self
            
            tabBar.addGestureRecognizer(
                recognizer
            )
            
            installedTabBar =
            tabBar
            
            tapRecognizer =
            recognizer
        }
        
        func uninstall() {
            if let recognizer =
                tapRecognizer {
                
                installedTabBar?
                    .removeGestureRecognizer(
                        recognizer
                    )
            }
            
            tapRecognizer =
            nil
            
            installedTabBar =
            nil
            
            lastTargetTapTime =
            nil
        }
        
        @objc
        private func handleTabBarTap(
            _ recognizer:
            UITapGestureRecognizer
        ) {
            guard recognizer.state ==
                .ended
            else {
                return
            }
            
            DispatchQueue.main.async {
                [weak self] in
                
                guard
                    let self,
                    let tabBar =
                        self.installedTabBar,
                    let items =
                        tabBar.items,
                    items.indices.contains(
                        self.targetTabIndex
                    )
                else {
                    return
                }
                
                let targetItem =
                items[
                    self.targetTabIndex
                ]
                
                guard tabBar.selectedItem ===
                        targetItem
                else {
                    self.lastTargetTapTime =
                    nil
                    
                    return
                }
                
                let currentTime =
                ProcessInfo
                    .processInfo
                    .systemUptime
                
                if let previousTime =
                    self.lastTargetTapTime,
                   currentTime -
                    previousTime <=
                    self.maximumDoubleTapInterval {
                    
                    self.lastTargetTapTime =
                    nil
                    
                    self.onDoubleTap()
                    
                } else {
                    self.lastTargetTapTime =
                    currentTime
                }
            }
        }
        
        func gestureRecognizer(
            _ gestureRecognizer:
            UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith
            otherGestureRecognizer:
            UIGestureRecognizer
        ) -> Bool {
            true
        }
        
        private func findTabBarController(
            from controller:
            UIViewController
        ) -> UITabBarController? {
            var current:
            UIViewController? =
            controller
            
            while let currentController =
                    current {
                
                if let tabBarController =
                    currentController
                    as? UITabBarController {
                    
                    return tabBarController
                }
                
                if let tabBarController =
                    currentController
                    .tabBarController {
                    
                    return tabBarController
                }
                
                current =
                currentController.parent
            }
            
            guard let rootController =
                    controller
                .viewIfLoaded?
                .window?
                .rootViewController
            else {
                return nil
            }
            
            return findTabBarControllerInHierarchy(
                rootController
            )
        }
        
        private func findTabBarControllerInHierarchy(
            _ controller:
            UIViewController
        ) -> UITabBarController? {
            if let tabBarController =
                controller
                as? UITabBarController {
                
                return tabBarController
            }
            
            for child in
                    controller.children {
                
                if let found =
                    findTabBarControllerInHierarchy(
                        child
                    ) {
                    
                    return found
                }
            }
            
            if let presentedController =
                controller
                .presentedViewController,
               let found =
                findTabBarControllerInHierarchy(
                    presentedController
                ) {
                
                return found
            }
            
            return nil
        }
        
        deinit {
            uninstall()
        }
    }
}
