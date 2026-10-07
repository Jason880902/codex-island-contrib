import Foundation

enum IslandProvider: String, CaseIterable, Identifiable, Codable {
    case claude, codex, grok, antigravity, kimi, gemini, glm

    var id: String { rawValue }
    var name: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .grok: return "Grok"
        case .antigravity: return "Antigravity"
        case .kimi: return "Kimi"
        case .gemini: return "Gemini"
        case .glm: return "GLM"
        }
    }
    var usesLegacyUsage: Bool { self == .claude || self == .codex }
}
