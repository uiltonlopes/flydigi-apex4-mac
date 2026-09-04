// Requests carried from the spacestation:// URL scheme into pages that keep their own state (Screen sources,
// GIPHY query, macro selection). Pages read and clear them.

import Observation

@MainActor @Observable
final class NavHints {
    static let shared = NavHints()
    var screenSource: String?     // "official" | "factory" | "giphy"
    var giphyQuery: String?
    var macroIndex: Int?
}
