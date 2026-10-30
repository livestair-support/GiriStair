// Shared SwiftUI implementation extracted from LiveStair (read-only reference).
// Reference commit: 074206d2d92cefdf6e1a076900ed7af807ae1eb8.
// Original CommonUI.swift blob: 440a8ef5a97e7289bee7366b6e4b903d65c7ee53.
// Source components retain their dimensions, typography, theme colors and row
// backgrounds. AppPageHeader parameterizes the original MainTabTitleHeader icon.
// OptionalDateRow adapts optional GiriStair dates, preserving nil on cancellation.
import SwiftUI
import UIKit
import Foundation

let accentActionColor = Color.pink
let settingsMinimumListRowHeight: CGFloat = 48

enum AppThemeMode: String {
    case system
    case light
    case dark
    case livestair
}

struct AppInfoButton: View {
    let title: String
    let message: String
    let tintColor: Color
    
    @State private var isShowingInfo = false
    
    init(
        title: String,
        message: String,
        tintColor: Color = .secondary
    ) {
        self.title = title
        self.message = message
        self.tintColor = tintColor
    }
    
    var body: some View {
        Button {
            isShowingInfo = true
        } label: {
            Image(systemName: "info.circle")
                .font(
                    .system(
                        size: appFontSize(14),
                        weight: .regular
                    )
                )
                .foregroundColor(
                    tintColor.opacity(0.78)
                )
                .frame(
                    width: 24,
                    height: 28
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(
            "\(title)の説明"
        )
        .alert(
            title,
            isPresented: $isShowingInfo
        ) {
            Button(
                "閉じる",
                role: .cancel
            ) {}
        } message: {
            Text(message)
        }
    }
}

struct AppIndexItemBadge: View {
    let systemImage: String
    let color: Color
    
    @AppStorage("appearanceMode")
    private var appearanceModeRawValue: String =
    AppThemeMode.system.rawValue
    
    @Environment(\.colorScheme)
    private var colorScheme
    
    init(
        systemImage: String,
        color: Color = accentActionColor
    ) {
        self.systemImage = systemImage
        self.color = color
    }
    
    private var isDarkAppearance: Bool {
        resolvedAppAppearanceIsDark(
            appearanceModeRawValue:
                appearanceModeRawValue,
            systemColorScheme:
                colorScheme
        )
    }
    
    var body: some View {
        Image(systemName: systemImage)
            .font(
                .system(
                    size: appFontSize(15),
                    weight: .semibold
                )
            )
            .foregroundColor(color)
            .frame(width: 36, height: 36)
            .background(
                color.opacity(
                    isDarkAppearance
                    ? 0.20
                    : 0.14
                )
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
            )
    }
}

struct AppEditorFormModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environment(
                \.defaultMinListRowHeight,
                 40
            )
            .listSectionSpacing(14)
            .contentMargins(
                .top,
                8,
                for: .scrollContent
            )
            .scrollContentBackground(.hidden)
            .background {
                appBackgroundColor
                    .ignoresSafeArea()
            }
    }
}

func appSearchKey(
    _ text: String
) -> String {
    let trimmed =
    text.trimmingCharacters(
        in: .whitespacesAndNewlines
    )

    let katakana =
    trimmed.applyingTransform(
        .hiraganaToKatakana,
        reverse: false
    ) ?? trimmed

    let halfWidth =
    katakana.applyingTransform(
        .fullwidthToHalfwidth,
        reverse: false
    ) ?? katakana

    return halfWidth
        .lowercased()
        .filter { !$0.isWhitespace }
}

// 検索語（空白で区切った語すべて）が、どれかの文字に含まれるか
func appSearchMatches(
    queryKeys: [String],
    in targetKeys: [String]
) -> Bool {
    queryKeys.allSatisfy { queryKey in
        targetKeys.contains {
            $0.contains(queryKey)
        }
    }
}

// 検索欄に入力された文字を、語ごとの検索用の文字にする
func appSearchQueryKeys(
    _ text: String
) -> [String] {
    text
        .split(whereSeparator: { $0.isWhitespace })
        .map { appSearchKey(String($0)) }
        .filter { !$0.isEmpty }
}

struct AppSearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField(
                placeholder,
                text: $text
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("検索語を消す")
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 36)
        .background(appSubCardColor)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
        )
    }
}

// プルダウン（Menu）の共通部品。
// iOS 26 では、メニューを開くとラベルが Liquid Glass の変形アニメーションで消え、
// 閉じたあとに ⇵ などの画像が遅れて出てくる。ラベルのガラス表示を止めて、そのまま表示されるようにする。
// iOS 26 より前、または iOS 26 の SDK がない環境では、普通の Menu と同じ。
struct AppMenu<MenuContent: View, MenuLabel: View>: View {
    private let content: MenuContent
    private let label: MenuLabel

    init(
        @ViewBuilder content: () -> MenuContent,
        @ViewBuilder label: () -> MenuLabel
    ) {
        self.content = content()
        self.label = label()
    }

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                Menu {
                    content
                } label: {
                    label
                        .glassEffect(.identity)
                }
                .clipped()
            }
        } else {
            Menu {
                content
            } label: {
                label
            }
        }
        #else
        Menu {
            content
        } label: {
            label
        }
        #endif
    }
}

// ヘッダーを畳む／広げるボタン（ヘッダーの右上に置く）
struct AppHeaderCollapseButton: View {
    @Binding var isCollapsed: Bool
    var tintColor: Color = .secondary
    // 読み上げの「〇〇を広げる」の〇〇（設定タブのセクションでは、セクションの名前）
    var subject: String = "条件"

    var body: some View {
        Button {
            withAnimation(
                .easeInOut(duration: 0.2)
            ) {
                isCollapsed.toggle()
            }
        } label: {
            Image(
                systemName:
                    isCollapsed
                ? "chevron.down.circle"
                : "chevron.up.circle"
            )
            .font(
                .system(
                    size: appFontSize(17),
                    weight: .semibold
                )
            )
            .foregroundColor(tintColor)
            .frame(width: 30, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isCollapsed
            ? "\(subject)を広げる"
            : "\(subject)を畳む"
        )
    }
}

// ヘッダーを畳んだときに出す、初期状態と違う条件（なければ何も出さない）
struct AppHeaderConditionSummary: View {
    let conditions: [String]
    // 条件があるときだけ付ける上の余白
    var topPadding: CGFloat = 0

    var body: some View {
        if !conditions.isEmpty {
            Text(
                "条件：" +
                conditions.joined(separator: "・")
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(2)
            .fixedSize(
                horizontal: false,
                vertical: true
            )
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .padding(.top, topPadding)
        }
    }
}

// 検索欄に入力があるときの条件の文字（畳んだヘッダーに出す）
func appSearchConditionText(
    _ searchText: String
) -> String? {
    let trimmed =
    searchText.trimmingCharacters(
        in: .whitespacesAndNewlines
    )

    return trimmed.isEmpty
    ? nil
    : "検索「\(trimmed)」"
}

struct AppIndexHeaderCard<Content: View>: View {
    let accentColor: Color
    
    private let content: Content
    
    @AppStorage("appearanceMode")
    private var appearanceModeRawValue: String =
    AppThemeMode.system.rawValue
    
    @Environment(\.colorScheme)
    private var colorScheme
    
    init(
        accentColor: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.accentColor = accentColor
        self.content = content()
    }
    
    private var appearanceMode: AppThemeMode {
        resolvedAppThemeMode(
            appearanceModeRawValue
        )
    }
    
    private var isDarkAppearance: Bool {
        resolvedAppAppearanceIsDark(
            appearanceModeRawValue:
                appearanceModeRawValue,
            systemColorScheme:
                colorScheme
        )
    }
    
    private var tintOpacity: Double {
        if isDarkAppearance {
            return 0.10
        }
        
        switch appearanceMode {
        case .livestair:
            return 0.065
            
        case .light, .system:
            return 0.080
            
        case .dark:
            return 0.10
        }
    }
    
    private var borderOpacity: Double {
        if isDarkAppearance {
            return 0.28
        }
        
        switch appearanceMode {
        case .livestair:
            return 0.30
            
        case .light, .system:
            return 0.34
            
        case .dark:
            return 0.28
        }
    }
    
    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            content
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            ZStack(alignment: .leading) {
                appCardColor
                
                accentColor
                    .opacity(tintOpacity)
                
                Rectangle()
                    .fill(accentColor)
                    .frame(width: 3)
            }
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .stroke(
                accentColor.opacity(
                    borderOpacity
                ),
                lineWidth: 1
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(appHeaderColor)
    }
}

struct AppIndexListStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .environment(
                \.defaultMinListRowHeight,
                 44
            )
            .listSectionSpacing(14)
            .contentMargins(
                .top,
                8,
                for: .scrollContent
            )
            .contentMargins(
                .bottom,
                24,
                for: .scrollContent
            )
            .scrollContentBackground(.hidden)
            .background {
                appBackgroundColor
                    .ignoresSafeArea()
            }
    }
}


extension View {
    func appIndexListStyle() -> some View {
        modifier(
            AppIndexListStyleModifier()
        )
    }
}

extension View {
    func appEditorFormStyle() -> some View {
        modifier(
            AppEditorFormModifier()
        )
    }
}

enum AppSectionAccent {
    static let live = Color(
        red: 0.94,
        green: 0.27,
        blue: 0.43
    )
    
    static let artist = Color(
        red: 0.41,
        green: 0.50,
        blue: 0.66
    )
    
    static let venue = Color(
        red: 0.25,
        green: 0.60,
        blue: 0.61
    )
    
    // アーティスト（くすんだ青）と見分けやすいよう、少し鮮やかな藍色にしている
    static let song = Color(
        red: 0.40,
        green: 0.40,
        blue: 0.72
    )
    
    static let ticket = Color(
        red: 0.76,
        green: 0.55,
        blue: 0.28
    )
    
    static let memo = Color(
        red: 0.42,
        green: 0.58,
        blue: 0.45
    )
    
    static let scan = Color(
        red: 0.58,
        green: 0.42,
        blue: 0.72    
    )
    
    static let photo = Color(
        red: 0.70,
        green: 0.52,
        blue: 0.61    
    )   
    
    static let favorite = Color(
        red: 0.95,
        green: 0.78,
        blue: 0.24
    )    
}

struct AppCardSectionTitle: View {
    let title: String
    let systemImage: String
    let accentColor: Color
    let infoTitle: String?
    let infoMessage: String?
    
    init(
        title: String,
        systemImage: String,
        accentColor: Color,
        infoTitle: String? = nil,
        infoMessage: String? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accentColor = accentColor
        self.infoTitle = infoTitle
        self.infoMessage = infoMessage
    }
    
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(
                    .system(
                        size: appFontSize(14),
                        weight: .semibold
                    )
                )
                .foregroundColor(accentColor)
                .frame(width: 28, height: 28)
                .background(
                    accentColor.opacity(0.14)
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 8,
                        style: .continuous
                    )
                )
            
            Text(title)
                .font(
                    .system(
                        size: appFontSize(18),
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundColor(.primary)
            
            if let infoTitle,
               let infoMessage {
                AppInfoButton(
                    title: infoTitle,
                    message: infoMessage,
                    tintColor: accentColor
                )
            }
            
            Spacer()
        }
        .padding(.vertical, 1)
        .textCase(nil)
        .accessibilityAddTraits(.isHeader)
    }
}

struct AppSectionCardModifier: ViewModifier {
    let accentColor: Color
    
    func body(content: Content) -> some View {
        content
            .listRowBackground(
                AppTintedListRowBackground(
                    accentColor: accentColor
                )
            )
            .listRowSeparatorTint(
                appSeparatorColor
            )
            .listRowInsets(
                EdgeInsets(
                    top: 6,
                    leading: 16,
                    bottom: 6,
                    trailing: 16
                )
            )
    }
}

extension View {
    func appSectionCardStyle(
        accentColor: Color
    ) -> some View {
        modifier(
            AppSectionCardModifier(
                accentColor: accentColor
            )
        )
    }
}

// EventBasicEditor.swift EventEditorCardSectionModifier and
// LiveDetailView.swift LiveDetailCardSectionModifier. Editor and detail rows
// intentionally have different vertical insets, rather than sharing a guessed
// generic card geometry.
private struct GiriEventSectionCardModifier: ViewModifier {
    let accentColor: Color
    let verticalInset: CGFloat

    func body(content: Content) -> some View {
        content
            .listRowBackground(AppTintedListRowBackground(
                accentColor: accentColor, lightTintOpacity: 0.065))
            .listRowSeparatorTint(appSeparatorColor)
            .listRowInsets(EdgeInsets(top: verticalInset, leading: 16,
                                     bottom: verticalInset, trailing: 16))
    }
}

extension View {
    func appEventEditorCardStyle(accentColor: Color) -> some View {
        modifier(GiriEventSectionCardModifier(accentColor: accentColor, verticalInset: 8))
    }

    func appEventDetailCardStyle(accentColor: Color) -> some View {
        modifier(GiriEventSectionCardModifier(accentColor: accentColor, verticalInset: 6))
    }
}

// EventBasicEditor.swift EventEditorCardTitle. The source editor badge uses
// 0.12 opacity and a nested 4pt heading/info gap; general section titles use 0.14.
struct GiriEventCardSectionTitle: View {
    let title: String
    let systemImage: String
    let accentColor: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: appFontSize(14), weight: .semibold))
                .foregroundColor(accentColor)
                .frame(width: 28, height: 28)
                .background(accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: appFontSize(18), weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .textCase(nil)
        .accessibilityAddTraits(.isHeader)
    }
}

struct AppTintedSurfaceBackground: View {
    let accentColor: Color
    var lightTintOpacity: Double = 0.045
    
    @AppStorage("appearanceMode")
    private var appearanceModeRawValue: String =
    AppThemeMode.system.rawValue
    
    @Environment(\.colorScheme)
    private var colorScheme
    
    private var appearanceMode: AppThemeMode {
        resolvedAppThemeMode(
            appearanceModeRawValue
        )
    }
    
    private var isDarkAppearance: Bool {
        resolvedAppAppearanceIsDark(
            appearanceModeRawValue:
                appearanceModeRawValue,
            systemColorScheme:
                colorScheme
        )
    }
    
    private var tintOpacity: Double {
        if isDarkAppearance {
            return max(
                lightTintOpacity,
                0.080
            )
        }
        
        switch appearanceMode {
        case .livestair:
            return max(
                lightTintOpacity,
                0.065
            )
            
        case .light, .system:
            return max(
                lightTintOpacity,
                0.075
            )
            
        case .dark:
            return max(
                lightTintOpacity,
                0.080
            )
        }
    }
    
    var body: some View {
        ZStack {
            appCardColor
            
            accentColor
                .opacity(tintOpacity)
        }
    }
}

struct AppTintedListRowBackground: View {
    let accentColor: Color
    var lightTintOpacity: Double = 0.045
    
    @AppStorage("appearanceMode")
    private var appearanceModeRawValue: String =
    AppThemeMode.system.rawValue
    
    @Environment(\.colorScheme)
    private var colorScheme
    
    private var isDarkAppearance: Bool {
        resolvedAppAppearanceIsDark(
            appearanceModeRawValue:
                appearanceModeRawValue,
            systemColorScheme:
                colorScheme
        )
    }
    
    private var borderOpacity: Double {
        isDarkAppearance
        ? 0.20
        : 0.28
    }
    
    var body: some View {
        AppTintedSurfaceBackground(
            accentColor: accentColor,
            lightTintOpacity:
                lightTintOpacity
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 3)
        }
        .overlay {
            Rectangle()
                .stroke(
                    accentColor.opacity(
                        borderOpacity
                    ),
                    lineWidth: 0.65
                )
        }
    }
}

struct AppTintedCardModifier: ViewModifier {
    let accentColor: Color
    let cornerRadius: CGFloat
    let railVerticalInset: CGFloat
    let lightTintOpacity: Double
    let clipsContent: Bool
    
    @AppStorage("appearanceMode")
    private var appearanceModeRawValue: String =
    AppThemeMode.system.rawValue
    
    @Environment(\.colorScheme)
    private var colorScheme
    
    private var appearanceMode: AppThemeMode {
        resolvedAppThemeMode(
            appearanceModeRawValue
        )
    }
    
    private var isDarkAppearance: Bool {
        resolvedAppAppearanceIsDark(
            appearanceModeRawValue:
                appearanceModeRawValue,
            systemColorScheme:
                colorScheme
        )
    }
    
    private var borderOpacity: Double {
        if isDarkAppearance {
            return 0.28
        }
        
        switch appearanceMode {
        case .livestair:
            return 0.30
            
        case .light, .system:
            return 0.34
            
        case .dark:
            return 0.28
        }
    }
    
    @ViewBuilder
    private func boundedContent(_ content: Content) -> some View {
        if clipsContent {
            content.clipShape(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content
        }
    }

    func body(content: Content) -> some View {
        boundedContent(content)
            .background {
                AppTintedSurfaceBackground(
                    accentColor: accentColor,
                    lightTintOpacity:
                        lightTintOpacity
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius:
                            cornerRadius,
                        style:
                                .continuous
                    )
                )
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius:
                        cornerRadius,
                    style:
                            .continuous
                )
                .stroke(
                    accentColor.opacity(
                        borderOpacity
                    ),
                    lineWidth: 1
                )
            }
            .overlay(alignment: .leading) {
                RoundedRectangle(
                    cornerRadius: 1.5,
                    style: .continuous
                )
                .fill(accentColor)
                .frame(width: 3)
                .padding(
                    .vertical,
                    railVerticalInset
                )
            }
    }
}

extension View {
    func appTintedCard(
        accentColor: Color,
        cornerRadius: CGFloat = 20,
        railVerticalInset: CGFloat = 14,
        lightTintOpacity: Double = 0.045,
        clipsContent: Bool = false
    ) -> some View {
        modifier(
            AppTintedCardModifier(
                accentColor: accentColor,
                cornerRadius: cornerRadius,
                railVerticalInset:
                    railVerticalInset,
                lightTintOpacity:
                    lightTintOpacity,
                clipsContent: clipsContent
            )
        )
    }
}

struct AppFieldIcon: View {
    let systemImage: String
    let color: Color
    
    var body: some View {
        Image(systemName: systemImage)
            .font(
                .system(
                    size: appFontSize(14),
                    weight: .semibold
                )
            )
            .foregroundColor(color)
            .frame(width: 20)
            .accessibilityHidden(true)
    }
}

struct AppFieldLabel: View {
    let title: String
    let systemImage: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            AppFieldIcon(
                systemImage: systemImage,
                color: color
            )
            
            Text(title)
                .foregroundColor(.primary)
        }
    }
}

private var currentAppThemeMode: AppThemeMode {
    let rawValue =
    UserDefaults.standard.string(
        forKey: "appearanceMode"
    ) ?? AppThemeMode.system.rawValue
    
    return AppThemeMode(
        rawValue: rawValue
    ) ?? .system
}

private let standardLightPageUIColor =
UIColor(
    red: 0.976,
    green: 0.976,
    blue: 0.984,
    alpha: 1
)

private let standardLightCardUIColor =
UIColor(
    red: 1.000,
    green: 1.000,
    blue: 1.000,
    alpha: 1
)

private let standardLightSubCardUIColor =
UIColor(
    red: 0.945,
    green: 0.950,
    blue: 0.965,
    alpha: 1
)

private let standardDarkCardUIColor =
UIColor(
    red: 0.105,
    green: 0.105,
    blue: 0.120,
    alpha: 1
)

private let standardDarkSubCardUIColor =
UIColor(
    red: 0.155,
    green: 0.155,
    blue: 0.175,
    alpha: 1
)

private func appPageBackgroundColor(
    for mode: AppThemeMode
) -> Color {
    switch mode {
    case .livestair:
        return Color(
            red: 0.98,
            green: 0.93,
            blue: 0.84
        )
        
    case .light:
        return Color(
            uiColor:
                standardLightPageUIColor
        )
        
    case .dark:
        return Color.black
        
    case .system:
        return Color(
            uiColor: UIColor { traits in
                if traits.userInterfaceStyle ==
                    .dark {
                    return .black
                } else {
                    return standardLightPageUIColor
                }
            }
        )
    }
}

private func appCardSurfaceColor(
    for mode: AppThemeMode
) -> Color {
    switch mode {
    case .livestair:
        return Color(
            red: 1.000,
            green: 0.995,
            blue: 0.975
        )
        
    case .light:
        return Color(
            uiColor:
                standardLightCardUIColor
        )
        
    case .dark:
        return Color(
            uiColor:
                standardDarkCardUIColor
        )
        
    case .system:
        return Color(
            uiColor: UIColor { traits in
                if traits.userInterfaceStyle ==
                    .dark {
                    return standardDarkCardUIColor
                } else {
                    return standardLightCardUIColor
                }
            }
        )
    }
}

private func appSubCardSurfaceColor(
    for mode: AppThemeMode
) -> Color {
    switch mode {
    case .livestair:
        return Color(
            red: 0.990,
            green: 0.980,
            blue: 0.945
        )
        
    case .light:
        return Color(
            uiColor:
                standardLightSubCardUIColor
        )
        
    case .dark:
        return Color(
            uiColor:
                standardDarkSubCardUIColor
        )
        
    case .system:
        return Color(
            uiColor: UIColor { traits in
                if traits.userInterfaceStyle ==
                    .dark {
                    return standardDarkSubCardUIColor
                } else {
                    return standardLightSubCardUIColor
                }
            }
        )
    }
}

var appBackgroundColor: Color {
    appPageBackgroundColor(
        for: currentAppThemeMode
    )
}

enum AppLargeScreenLayout {
    // iPad のとき true（起動中に変わらない）
    static let isPadDevice: Bool =
    UIDevice.current.userInterfaceIdiom == .pad
    
    // 今のアプリの幅が広いか（horizontalSizeClass が regular か）。
    // Split View などで iPhone くらいの幅にしたときは false になる（アプリ全体に付ける AppLargeScreenTypeSize で入れる）
    static var isRegularWidth = true

    // iPad で、幅が広いとき true（文字を一回り大きくする・中身を最大幅で並べる）
    static var isLargeScreen: Bool {
        isPadDevice && isRegularWidth
    }

    // 大きさを決めて書いている文字（.system(size:appFontSize())）の倍率
    // （幅を変えたときは、それぞれの画面が次に描き直されたときから変わる）
    static var fontScale: CGFloat {
        isLargeScreen ? 1.15 : 1.0
    }

    // 横に広い画面で、画面の中身を並べる最大の幅（左右は背景色）
    static let readableContentMaxWidth: CGFloat = 820
}

// 文字の大きさ。iPad では画面に合わせて少し大きくする
func appFontSize(
    _ size: CGFloat
) -> CGFloat {
    size * AppLargeScreenLayout.fontScale
}

var appHeaderColor: Color {
    appPageBackgroundColor(
        for: currentAppThemeMode
    )
}

var appCardColor: Color {
    appCardSurfaceColor(
        for: currentAppThemeMode
    )
}

var appSubCardColor: Color {
    appSubCardSurfaceColor(
        for: currentAppThemeMode
    )
}

var appSeparatorColor: Color {
    switch currentAppThemeMode {
    case .livestair:
        return Color.black
            .opacity(0.12)
        
    case .light:
        return Color.black
            .opacity(0.12)
        
    case .dark:
        return Color.white
            .opacity(0.14)
        
    case .system:
        return Color(
            uiColor: UIColor { traits in
                if traits.userInterfaceStyle ==
                    .dark {
                    return UIColor.white
                        .withAlphaComponent(0.14)
                } else {
                    return UIColor.black
                        .withAlphaComponent(0.12)
                }
            }
        )
    }
}

var appTagBackgroundColor: Color {
    switch currentAppThemeMode {
    case .livestair:
        return accentActionColor.opacity(0.12)
    default:
        return Color.blue.opacity(0.10)
    }
}

var appTagTextColor: Color {
    switch currentAppThemeMode {
    case .livestair:
        return accentActionColor
    default:
        return .primary
    }
}

private func resolvedAppThemeMode(
    _ rawValue: String
) -> AppThemeMode {
    AppThemeMode(rawValue: rawValue) ?? .system
}

private func resolvedAppAppearanceIsDark(
    appearanceModeRawValue: String,
    systemColorScheme: ColorScheme
) -> Bool {
    switch resolvedAppThemeMode(
        appearanceModeRawValue
    ) {
    case .dark:
        return true
        
    case .light, .livestair:
        return false
        
    case .system:
        return systemColorScheme == .dark
    }
}

@MainActor
func playLiveStairSaveFeedback() {
    UINotificationFeedbackGenerator()
        .notificationOccurred(.success)
}

@MainActor
func playLiveStairDeleteFeedback() {
    UIImpactFeedbackGenerator(style: .medium)
        .impactOccurred()
}

// The root header is MainTabTitleHeader / MainTabTitleLabel from LiveStair,
// parameterized by GiriStair's five screen names rather than live-specific names.
struct AppPageHeader: View {
    let title: String
    let systemImage: String
    let accentColor: Color
    var trailingReserve: CGFloat = 90
    @AppStorage("appearanceMode") private var appearanceModeRawValue = AppThemeMode.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: appFontSize(19), weight: .bold))
                    .foregroundColor(accentColor)
                    .frame(width: 38, height: 38)
                    .background(accentColor.opacity(resolvedAppAppearanceIsDark(
                        appearanceModeRawValue: appearanceModeRawValue,
                        systemColorScheme: colorScheme) ? 0.20 : 0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: appFontSize(34), weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            Spacer(minLength: trailingReserve + 12)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appHeaderColor)
    }
}

// Original CenteredEmptyMessage, with an additional labeled initializer to match
// the GiriStair screen API. It remains a centered empty message, not a card.
struct CenteredEmptyMessage: View {
    let text: String
    var systemImage: String? = nil

    init(text: String, systemImage: String? = nil) {
        self.text = text
        self.systemImage = systemImage
    }

    init(systemImage: String, title: String, message: String = "") {
        self.text = message.isEmpty ? title : title + "\n" + message
        self.systemImage = systemImage
    }

    var body: some View {
        VStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: appFontSize(28), weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.55))
            }
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }
}

func japaneseHolidayName(for date: Date) -> String? {
    JapaneseHolidayCalendar.holidayName(for: date)
}

func liveDateWeekdayColor(_ date: Date) -> Color {
    if japaneseHolidayName(for: date) != nil {
        return .red
    }
    
    let weekday = Calendar(identifier: .gregorian).component(.weekday, from: date)
    
    switch weekday {
    case 1:
        return .red
    case 7:
        return .blue
    default:
        return .primary
    }
}

func liveListDateColor(_ date: Date) -> Color {
    if japaneseHolidayName(for: date) != nil {
        return .red
    }
    
    let weekday = Calendar(identifier: .gregorian).component(.weekday, from: date)
    
    switch weekday {
    case 1:
        return .red
    case 7:
        return .blue
    default:
        return .secondary
    }
}

// An optional native date/time input. Opening and cancelling either picker
// never writes a guessed value. UIDatePicker owns the time menu and popover.
struct OptionalDateRow: View {
    let title: String
    @Binding var selection: Date?
    var components: DatePickerComponents = [.date, .hourAndMinute]
    @State private var showingCalendar = false

    private var dateTitle: String {
        selection.map { GiriDateText.day($0) } ?? "未定"
    }

    private var calendarSelection: Binding<Date> {
        Binding(get: { selection ?? Date() }, set: { date in
            if components.contains(.hourAndMinute), let previous = selection {
                let calendar = Calendar.current
                let time = calendar.dateComponents([.hour, .minute], from: previous)
                selection = calendar.date(bySettingHour: time.hour ?? 0,
                    minute: time.minute ?? 0, second: 0, of: date) ?? date
            } else {
                selection = date
            }
        })
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            if components.contains(.date) {
                Button {
                    showingCalendar = true
                } label: {
                    HStack(spacing: 10) {
                        Text(dateTitle)
                            .font(.body.weight(.semibold))
                            .foregroundColor(selection.map(liveDateWeekdayColor) ?? .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        if !components.contains(.hourAndMinute) {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingCalendar, arrowEdge: .bottom) {
                    EventDateCalendarPickerView(selectedDate: calendarSelection,
                        maxWidth: 345, onClose: { showingCalendar = false })
                        .frame(width: 345, height: 372)
                        .padding(.top, 12)
                        .presentationCompactAdaptation(.popover)
                }
            }
            if components.contains(.hourAndMinute) {
                OptionalCompactTimePicker(selection: $selection)
                    .frame(width: 70, height: 32)
                    .accessibilityLabel(title)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if components == .date { showingCalendar = true }
        }
        .contextMenu {
            if selection != nil {
                Button("未定に戻す", systemImage: "arrow.counterclockwise") {
                    selection = nil
                }
            }
        }
    }
}

// EventBasicEditor.swift EventEditorTimeRow / EventEditorTimePair, with the
// GiriStair start/end labels and the existing five-minute optional picker.
struct GiriEventTimeRow: View {
    @Binding var startsAt: Date?
    @Binding var endsAt: Date?

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            timePair("開始", selection: $startsAt)
                .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 4)
            timePair("終了", selection: $endsAt)
                .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 4)
            Divider()
                .overlay(appSeparatorColor)
                .frame(height: 34)
                .padding(.horizontal, 6)
            Button {
                startsAt = nil
                endsAt = nil
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "arrow.counterclockwise").font(.footnote)
                    Text("未定").font(.caption)
                }
                .foregroundColor(accentActionColor)
                .frame(width: 36)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func timePair(_ title: String, selection: Binding<Date?>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
                .fixedSize()
            OptionalCompactTimePicker(selection: selection)
                .frame(width: 70, height: 32)
                .accessibilityLabel(title)
        }
    }
}

private struct OptionalCompactTimePicker: UIViewRepresentable {
    @Binding var selection: Date?

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .compact
        picker.minuteInterval = 5
        picker.locale = Locale(identifier: "ja_JP")
        picker.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        let cover = context.coordinator.emptyCover
        cover.frame = picker.bounds
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        picker.addSubview(cover)
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        context.coordinator.selection = $selection
        if let selection {
            if abs(picker.date.timeIntervalSince(selection)) > 0.5 {
                picker.setDate(selection, animated: false)
            }
        } else {
            let calendar = Calendar.current
            var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
            parts.minute = (parts.minute ?? 0) / 5 * 5
            picker.setDate(calendar.date(from: parts) ?? Date(), animated: false)
        }
        context.coordinator.emptyCover.isHidden = selection != nil
        picker.bringSubviewToFront(context.coordinator.emptyCover)
    }

    final class Coordinator: NSObject {
        var selection: Binding<Date?>
        let emptyCover: UILabel = {
            let label = UILabel()
            label.text = "--:--"
            label.textAlignment = .center
            label.font = .monospacedDigitSystemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
                weight: .regular)
            label.textColor = .label
            // The optional placeholder must fully cover the compact picker's
            // provisional date, which has not been committed to the document.
            label.backgroundColor = .systemGray5
            label.layer.cornerRadius = 16
            label.clipsToBounds = true
            label.isUserInteractionEnabled = false
            label.isAccessibilityElement = false
            return label
        }()
        init(selection: Binding<Date?>) { self.selection = selection }
        @objc func changed(_ picker: UIDatePicker) {
            selection.wrappedValue = picker.date
        }
    }
}

// EventBasicEditor.swift EventDateCalendarPickerView, direct source.
struct EventDateCalendarPickerView: View {
    @Binding var selectedDate: Date
    let maxWidth: CGFloat
    let onClose: () -> Void
    
    @State private var displayedMonth: Date
    @State private var showingMonthPicker = false
    @State private var pickerYear: Int
    @State private var pickerMonth: Int
    @State private var displayedDates: [Date] = []
    
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    
    private var isSmallWidth: Bool {
        maxWidth <= 340
    }
    
    private var calendarContentHorizontalPadding: CGFloat {
        isSmallWidth ? 14 : 18
    }
    
    private var calendarHeaderHorizontalPadding: CGFloat {
        isSmallWidth ? 16 : 20
    }
    
    init(selectedDate: Binding<Date>, maxWidth: CGFloat, onClose: @escaping () -> Void) {
        self._selectedDate = selectedDate
        self.maxWidth = maxWidth
        self.onClose = onClose
        
        let initialDate = selectedDate.wrappedValue
        self._displayedMonth = State(initialValue: initialDate)
        self._pickerYear = State(initialValue: Calendar.current.component(.year, from: initialDate))
        self._pickerMonth = State(initialValue: Calendar.current.component(.month, from: initialDate))
    }
    
    private var yearOptions: [Int] {
        let currentYear = calendar.component(.year, from: Date())
        return Array((currentYear - 5)...(currentYear + 5))
    }
    
    var body: some View {
        calendarCard
            .overlay(alignment: .topTrailing) {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: appFontSize(16), weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .background(appCardColor)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .offset(x: isSmallWidth ? 0 : 6, y: -10)
                .zIndex(10)
            }
            .padding(.horizontal, 0)
            .padding(.top, 0)
            .onAppear {
                rebuildDisplayedDates()
            }
    }
    
    private func rebuildDisplayedDates() {
        displayedDates = daysInDisplayedMonth()
    }
    
    private var calendarCard: some View {
        VStack(spacing: 0) {
            header
            
            if showingMonthPicker {
                monthPickerArea
            } else {
                weekdayHeader
                
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(displayedDates, id: \.self) { date in
                        dayCell(date)
                    }
                }
                .padding(.horizontal, calendarContentHorizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.top, 18)
        .background(appBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.primary.opacity(0.28), lineWidth: 1)
        }
    }    
    
    private var header: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if showingMonthPicker {
                        showingMonthPicker = false
                    } else {
                        syncPickerWithDisplayedMonth()
                        showingMonthPicker = true
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(monthTitle(displayedMonth))
                        .font(.system(size: appFontSize(22), weight: .bold))
                        .foregroundColor(.primary)
                    
                    Image(systemName: showingMonthPicker ? "chevron.up" : "chevron.down")
                        .font(.system(size: appFontSize(15), weight: .bold))
                        .foregroundColor(accentActionColor)
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Button {
                moveMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: appFontSize(21), weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(showingMonthPicker)
            .opacity(showingMonthPicker ? 0.35 : 1)
            
            Button {
                moveMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: appFontSize(21), weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(showingMonthPicker)
            .opacity(showingMonthPicker ? 0.35 : 1)
            
        }
        .padding(.horizontal, calendarHeaderHorizontalPadding)
        .padding(.bottom, 14)
    }
    
    private var monthPickerArea: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Picker("年", selection: $pickerYear) {
                    ForEach(yearOptions, id: \.self) { year in
                        Text(verbatim: "\(year)年")
                            .tag(year)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()
                
                Picker("月", selection: $pickerMonth) {
                    ForEach(1...12, id: \.self) { month in
                        Text(verbatim: "\(month)月")
                            .tag(month)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            .frame(height: 170)
            .clipped()
            
            Button {
                applyPickerMonth()
                withAnimation(.easeInOut(duration: 0.18)) {
                    showingMonthPicker = false
                }
            } label: {
                Text("この年月を表示")
                    .font(.headline.bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(accentActionColor)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 12)
        }
    }
    
    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(["日", "月", "火", "水", "木", "金", "土"], id: \.self) { weekday in
                Text(weekday)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(weekdayHeaderColor(weekday))
                    .frame(height: 22)
            }
        }
        .padding(.horizontal, calendarContentHorizontalPadding)
    }
    
    private func dayCell(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let isCurrentMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
        
        return Button {
            selectedDate = date
            onClose()
        } label: {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(accentActionColor)
                        .frame(width: 38, height: 38)
                } else if isToday {
                    Circle()
                        .fill(accentActionColor.opacity(0.16))
                        .frame(width: 38, height: 38)
                }
                
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: appFontSize(17), weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .white : calendarDayTextColor(date))
                    .opacity(isCurrentMonth ? 1.0 : 0.28)
            }
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func calendarDayTextColor(_ date: Date) -> Color {
        if japaneseHolidayName(for: date) != nil {
            return .red
        }
        
        let weekday = calendar.component(.weekday, from: date)
        
        switch weekday {
        case 1:
            return .red
        case 7:
            return .blue
        default:
            return .primary
        }
    }
    
    private func weekdayHeaderColor(_ weekday: String) -> Color {
        switch weekday {
        case "日":
            return .red
        case "土":
            return .blue
        default:
            return .secondary
        }
    }
    
    private func monthTitle(_ date: Date) -> String {
        GiriDateText.month(date)
    }
    
    private func moveMonth(_ value: Int) {
        displayedMonth = calendar.date(
            byAdding: .month,
            value: value,
            to: displayedMonth
        ) ?? displayedMonth
        
        syncPickerWithDisplayedMonth()
        displayedDates = daysInDisplayedMonth()
    }
    
    private func syncPickerWithDisplayedMonth() {
        pickerYear = calendar.component(.year, from: displayedMonth)
        pickerMonth = calendar.component(.month, from: displayedMonth)
    }
    
    private func applyPickerMonth() {
        displayedMonth = calendar.date(
            from: DateComponents(year: pickerYear, month: pickerMonth, day: 1)
        ) ?? displayedMonth
        
        displayedDates = daysInDisplayedMonth()
    }
    
    private func daysInDisplayedMonth() -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1)) else {
            return []
        }
        
        var dates: [Date] = []
        var date = firstWeek.start
        
        while date < lastWeek.end {
            dates.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86400)
        }
        
        return dates
    }
}

