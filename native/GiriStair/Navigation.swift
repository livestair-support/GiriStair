import SwiftUI

enum GiriThoughtDestination: Hashable, Identifiable {
    case event(String)
    case site(String)
    case note(String)
    case round(eventID: String, roundID: String)

    var id: String {
        switch self {
        case .event(let id): return "event:\(id)"
        case .site(let id): return "site:\(id)"
        case .note(let id): return "note:\(id)"
        case .round(let eventID, let roundID): return "round:\(eventID):\(roundID)"
        }
    }
}

/// Detail pages select the existing thought tab and route to the linked draft.
@MainActor
final class GiriNavigation: ObservableObject {
    @Published var selectedTab = 1
    @Published var thoughtDestination: GiriThoughtDestination?

    func openThoughts(eventID: String) { open(.event(eventID)) }
    func openThoughts(siteID: String) { open(.site(siteID)) }
    func openThoughts(eventID: String, roundID: String) { open(.round(eventID: eventID, roundID: roundID)) }
    func openThought(noteID: String) { open(.note(noteID)) }

    private func open(_ destination: GiriThoughtDestination) {
        selectedTab = 3
        thoughtDestination = destination
    }
}
