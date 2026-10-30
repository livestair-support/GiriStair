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
                suggestionSearchTexts: cachedReadings)
        }
        .onAppear(perform: rebuild)
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
        cachedReadings = Dictionary(profiles.map { ($0.name, $0.furigana.isEmpty ? [] : [$0.furigana]) }, uniquingKeysWith: { first, _ in first })
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
