import SwiftUI
import UIKit

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
            Button("入力する") {
                // 結果入力は戦績タブで開く。
                if let event = pendingResult { navigation.openResultEntry(event.id) }
                pendingResult = nil
            }
        } message: { Text(pendingResult?.title ?? "") }
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
        .background {
            TabBarDoubleTapObserver(targetTabIndex: 0) {
                navigation.registrationClearToken += 1
            }
            .frame(width: 0, height: 0)
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
              pendingResult == nil else { return }
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
