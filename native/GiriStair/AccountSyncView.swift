import SwiftUI

struct GiriAccountSyncRow: View {
    @EnvironmentObject private var accountSync: AccountSyncCoordinator
    @EnvironmentObject private var store: GiriStore
    @State private var showingSignIn = false

    var body: some View {
        if accountSync.isAvailable && store.loaded {
            AccountSyncControls(onSignIn: { showingSignIn = true })
                .sheet(isPresented: $showingSignIn, onDismiss: accountSync.cancelSignIn) {
                    NavigationStack {
                        AccountSyncSignInView(onDismiss: { showingSignIn = false })
                            .giriNavigationBarStyle()
                    }
                }
        }
    }
}

struct AccountSyncControls: View {
    @EnvironmentObject private var accountSync: AccountSyncCoordinator
    let onSignIn: () -> Void

    var body: some View {
        if accountSync.isAvailable {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    if accountSync.isLoggedIn {
                        accountSync.signOut()
                    } else {
                        onSignIn()
                    }
                } label: {
                    Label(
                        accountSync.isLoggedIn ? "ログアウト" : "iCloudでログイン",
                        systemImage: accountSync.isLoggedIn ? "rectangle.portrait.and.arrow.right" : "icloud"
                    )
                }
                .disabled(accountSync.isBusy || accountSync.isApplying)
                if accountSync.isLoggedIn {
                    Text(accountSync.status ?? "同じApple Accountの端末と同期しています。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if let status = accountSync.status {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct AccountSyncSignInView: View {
    @EnvironmentObject private var accountSync: AccountSyncCoordinator
    let onDismiss: () -> Void

    private var showsConflict: Binding<Bool> {
        Binding(
            get: { accountSync.pendingConflict != nil },
            set: { _ in }
        )
    }

    var body: some View {
        List {
            Section {
                AppCardSectionTitle(title: "iCloudで同期", systemImage: "icloud", accentColor: AppSectionAccent.artist)
                    .listRowSeparator(.hidden)
                Text("iPhone・iPadの設定で使っているApple Accountでログインします。同じアカウントでログインした端末に、このアプリの変更が反映されます。ログアウト後の変更は、この端末に保存されます。")
                    .foregroundStyle(.secondary)
                if let status = accountSync.status {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await accountSync.beginSignIn() }
                } label: {
                    if accountSync.isBusy {
                        ProgressView()
                            .accessibilityLabel("iCloudを確認中")
                    } else {
                        Label("iCloudでログイン", systemImage: "icloud")
                    }
                }
                .disabled(accountSync.isBusy || !accountSync.isAvailable)
            }
            .appSectionCardStyle(accentColor: AppSectionAccent.artist)
        }
        .appIndexListStyle()
        .navigationTitle("アカウントと同期")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") {
                    accountSync.cancelSignIn()
                    onDismiss()
                }
                .disabled(accountSync.isBusy)
            }
        }
        .interactiveDismissDisabled(accountSync.isBusy)
        .onChange(of: accountSync.isLoggedIn) { _, isLoggedIn in
            if isLoggedIn { onDismiss() }
        }
        .alert("データを上書きしますか？", isPresented: showsConflict, presenting: accountSync.pendingConflict) { _ in
            Button("キャンセル", role: .cancel) { accountSync.cancelSignIn() }
            Button("上書きしてログイン", role: .destructive) {
                Task { await accountSync.confirmSignIn() }
            }
        } message: { conflict in
            Text(conflict.message)
        }
    }
}
