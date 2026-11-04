import SwiftUI

/// LiveStair CommonUI.swift SuggestionTextField (074206d2, lines 3019–3115).
/// Keep the source's focus, prefix/readings search, five-row card and selection
/// behaviour; ordering is supplied by the GiriStair directory adapters below.
struct GiriSuggestionTextField: View {
    let placeholder: String
    @Binding var text: String
    let suggestions: [String]
    var limit = 5
    var textAlignment: TextAlignment = .leading
    var suggestionSearchTexts: [String: [String]] = [:]
    var showsAllSuggestionsWhenEmpty = false
    @FocusState private var isInputFocused: Bool

    private func normalizedSuggestionText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.applyingTransform(.hiraganaToKatakana, reverse: false) ?? trimmed).lowercased()
    }
    private var filteredSuggestions: [String] {
        let rawInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawInput.isEmpty else {
            return showsAllSuggestionsWhenEmpty ? Array(suggestions.prefix(limit)) : []
        }
        let input = normalizedSuggestionText(rawInput)
        return suggestions.filter { suggestion in
            if normalizedSuggestionText(suggestion) == input { return false }
            let targets = ([suggestion] + (suggestionSearchTexts[suggestion] ?? []))
                .map(normalizedSuggestionText).filter { !$0.isEmpty }
            return targets.contains { $0.hasPrefix(input) }
        }.prefix(limit).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(placeholder, text: $text)
                .focused($isInputFocused)
                .multilineTextAlignment(textAlignment)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if isInputFocused && !filteredSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredSuggestions, id: \.self) { suggestion in
                        Button {
                            text = suggestion
                            isInputFocused = false
                        } label: {
                            HStack(spacing: 0) {
                                Text(suggestion).foregroundStyle(.primary).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 9).padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        if suggestion != filteredSuggestions.last { Divider() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(appCardColor)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GiriPlayerSuggestionField: View {
    @EnvironmentObject private var store: GiriStore
    let title: String
    @Binding var text: String
    var organizer = false
    var showsLabel = false
    var textAlignment: TextAlignment = .leading
    /// この会で入力済みの名前（参加者・チームのメンバーなど）。先頭に出し、空欄でも選べる。
    var priorityNames: [String] = []
    @State private var cachedNames: [String] = []
    @State private var cachedReadings: [String: [String]] = [:]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if showsLabel {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    .fixedSize().padding(.top, 2)
            }
            GiriSuggestionTextField(placeholder: title, text: $text,
                suggestions: cachedNames, textAlignment: textAlignment,
                suggestionSearchTexts: cachedReadings,
                showsAllSuggestionsWhenEmpty: !priorityNames.isEmpty)
        }
        .onAppear(perform: rebuild)
        .onChange(of: priorityNames) { _, _ in rebuild() }
        .onReceive(store.objectWillChange) { _ in
            // objectWillChange precedes the durable document assignment.
            DispatchQueue.main.async { rebuild() }
        }
    }

    private func rebuild() {
        let profiles = store.playerDirectory
        if organizer {
            // GiriStair's requested exception: frequent hosts come first.
            cachedNames = store.suggestPlayers("", organizer: true).map(\.name)
        } else {
            // EventBasicEditor.sortedArtistSuggestionsByLatestSeen: recent
            // appearances first, then reading order for equally recent names.
            var latest: [String: Date] = [:]
            for event in store.events where event.status != .canceled {
                let seen = event.eventDate ?? event.startsAt ?? event.effectiveRounds.compactMap(\.submissionStart).max() ?? event.createdAt
                for name in event.participants + event.teams.flatMap(\.members) {
                    let key = playerSearchKey(name)
                    if latest[key].map({ $0 < seen }) ?? true { latest[key] = seen }
                }
            }
            cachedNames = profiles.sorted { first, second in
                let firstDate = latest[playerSearchKey(first.name)]
                let secondDate = latest[playerSearchKey(second.name)]
                if firstDate != secondDate {
                    if let firstDate, let secondDate { return firstDate > secondDate }
                    return firstDate != nil
                }
                return playerSearchKey(first.furigana.isEmpty ? first.name : first.furigana) < playerSearchKey(second.furigana.isEmpty ? second.name : second.furigana)
            }.map(\.name)
        }
        if !priorityNames.isEmpty {
            var seen = Set<String>()
            let first = priorityNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && seen.insert(playerSearchKey($0)).inserted }
            cachedNames = first + cachedNames.filter { !seen.contains(playerSearchKey($0)) }
        }
        cachedReadings = Dictionary(profiles.map { ($0.name, $0.furigana.isEmpty ? [] : [$0.furigana]) }, uniquingKeysWith: { first, _ in first })
    }
}

/// 団体の主催者。団体名はプレイヤー一覧に入れないので、これまで団体として入れた名前から候補を出す。
struct GiriGroupOrganizerField: View {
    @EnvironmentObject private var store: GiriStore
    @Binding var text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("主催者").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .fixedSize().padding(.top, 2)
            GiriSuggestionTextField(placeholder: "団体名", text: $text,
                suggestions: groupNames, textAlignment: .trailing)
        }
    }
    private var groupNames: [String] {
        var seen = Set<String>()
        return store.events.filter(\.organizerIsGroup).sorted { $0.createdAt > $1.createdAt }
            .map { $0.organizer.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(playerSearchKey($0)).inserted }
    }
}

/// 大会の審査方法（段階ごとの審査方法が空の時に使う）。候補は段階の入力と同じ。
struct GiriJudgingField: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 8) {
            GiriEditorLabel("審査方法")
            TextField("挙手・加点など", text: $text).multilineTextAlignment(.trailing)
            Menu {
                ForEach(GiriStageEditor.judgings, id: \.self) { value in Button(value) { text = value } }
            } label: {
                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.medium))
            }
            .tint(.primary)
            .accessibilityLabel("審査方法の候補")
        }
    }
}

/// チーム名の入力。左に項目名、右に入力（ライブ登録の会場名と同じ形）。
/// この大会で登録したチームを先に出し、空欄のままでも選べる。
struct GiriTeamNameField: View {
    @Binding var text: String
    let suggestions: [String]
    var showsSuggestionsWhenEmpty = false
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("チーム名").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .fixedSize().padding(.top, 2)
            GiriSuggestionTextField(placeholder: "チーム名", text: $text,
                suggestions: suggestions, textAlignment: .trailing,
                showsAllSuggestionsWhenEmpty: showsSuggestionsWhenEmpty)
        }
    }
}

struct GiriVenueSuggestionField: View {
    @EnvironmentObject private var store: GiriStore
    @Binding var text: String
    @State private var cachedNames: [String] = []

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("会場名").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .fixedSize().padding(.top, 2)
            GiriSuggestionTextField(placeholder: "会場名", text: $text,
                suggestions: cachedNames, textAlignment: .trailing)
        }
        .onAppear(perform: rebuild)
        .onReceive(store.objectWillChange) { _ in DispatchQueue.main.async { rebuild() } }
    }
    private func rebuild() {
        var latest: [String: Date] = [:]
        for event in store.events where !event.venue.isEmpty {
            let key = playerSearchKey(event.venue)
            let seen = event.eventDate ?? event.startsAt ?? event.createdAt
            if latest[key].map({ $0 < seen }) ?? true { latest[key] = seen }
        }
        cachedNames = store.venueDirectory.sorted { first, second in
            let firstDate = latest[playerSearchKey(first.name)], secondDate = latest[playerSearchKey(second.name)]
            if firstDate != secondDate {
                if let firstDate, let secondDate { return firstDate > secondDate }
                return firstDate != nil
            }
            return playerSearchKey(first.name) < playerSearchKey(second.name)
        }.map(\.name)
    }
}
