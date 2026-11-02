import SwiftUI

enum GiriThoughtDestination: Hashable, Identifiable {
    case event(String)
    case site(String)
    case note(String)
    case round(eventID: String, roundID: String)
    /// プレイヤー詳細から開く、その人の回答（ツボ上げ・好きな回答）。
    case answerer(String)
    /// プレイヤー詳細から開く、その人が作ったお題。
    case author(String)

    var id: String {
        switch self {
        case .event(let id): return "event:\(id)"
        case .site(let id): return "site:\(id)"
        case .note(let id): return "note:\(id)"
        case .round(let eventID, let roundID): return "round:\(eventID):\(roundID)"
        case .answerer(let name): return "answerer:\(name)"
        case .author(let name): return "author:\(name)"
        }
    }
}

/// プレイヤー・会場詳細のショートカットから一覧タブを開くときの条件
/// （LiveStair の openArtistsLiveList / openVenueLiveList）。
struct GiriListRequest: Equatable {
    var players: [String] = []
    var venue: String? = nil
    let id = UUID()
}

/// Detail pages select the existing thought tab and route to the linked draft.
@MainActor
final class GiriNavigation: ObservableObject {
    @Published var selectedTab = 1
    @Published var thoughtDestination: GiriThoughtDestination?
    @Published var listRequest: GiriListRequest?

    func openList(players: [String] = [], venue: String? = nil) {
        listRequest = GiriListRequest(players: players, venue: venue)
        selectedTab = 1
    }

    func openThoughts(eventID: String) { open(.event(eventID)) }
    func openThoughts(siteID: String) { open(.site(siteID)) }
    func openThoughts(eventID: String, roundID: String) { open(.round(eventID: eventID, roundID: roundID)) }
    func openThought(noteID: String) { open(.note(noteID)) }
    func openThoughts(answerer: String) { open(.answerer(answerer)) }
    func openThoughts(author: String) { open(.author(author)) }

    private func open(_ destination: GiriThoughtDestination) {
        selectedTab = 3
        thoughtDestination = destination
    }
}
