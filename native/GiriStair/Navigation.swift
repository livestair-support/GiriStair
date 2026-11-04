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
    /// 主催した会（主催・共催、団体を含む）。
    var organizer: String? = nil
    let id = UUID()
}

/// 大会の詳細は一覧タブ、結果入力は戦績タブで開く。タブを切り替えると両方を見られる。
struct GiriDetailRequest: Equatable {
    var eventID: String
    let id = UUID()
}
struct GiriResultRequest: Hashable, Identifiable {
    var eventID: String
    var roundID: String? = nil
    var stageID: String? = nil
    let id = UUID()
}

/// Detail pages select the existing thought tab and route to the linked draft.
@MainActor
final class GiriNavigation: ObservableObject {
    @Published var selectedTab = 1
    @Published var thoughtDestination: GiriThoughtDestination?
    @Published var listRequest: GiriListRequest?
    /// 登録タブを続けて2回押した回数（LiveStair の registrationClearRequestToken）。
    @Published var registrationClearToken = 0
    @Published var detailRequest: GiriDetailRequest?
    @Published var resultRequest: GiriResultRequest?
    /// 保存していない入力がある結果入力・編集画面の記録。別の記録へ切り替えて入力を黙って消さない。
    @Published var unsavedResultEventID: String?
    @Published var unsavedEditorEventID: String?

    /// 一覧タブで大会・会の詳細を開く。
    func openEventDetail(_ eventID: String) {
        detailRequest = GiriDetailRequest(eventID: eventID)
        selectedTab = 1
    }
    /// 戦績タブで結果入力を開く（段階・回を指定すると、その入力をそのまま開く）。
    func openResultEntry(_ eventID: String, roundID: String? = nil, stageID: String? = nil) {
        resultRequest = GiriResultRequest(eventID: eventID, roundID: roundID, stageID: stageID)
        selectedTab = 2
    }
    func markResultEntry(_ eventID: String, unsaved: Bool) {
        if unsaved { unsavedResultEventID = eventID }
        else if unsavedResultEventID == eventID { unsavedResultEventID = nil }
    }
    func markEditor(_ eventID: String, unsaved: Bool) {
        if unsaved { unsavedEditorEventID = eventID }
        else if unsavedEditorEventID == eventID { unsavedEditorEventID = nil }
    }

    func openList(players: [String] = [], venue: String? = nil, organizer: String? = nil) {
        listRequest = GiriListRequest(players: players, venue: venue, organizer: organizer)
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
