import Foundation

enum L10n {
    static let locale = Locale(identifier: "en_US")
    static func tr(_ text: String, _ args: CVarArg...) -> String { String(format: text, arguments: args) }
}

@main
struct CodingProviderTests {
    static func expect(_ value: Bool, _ label: String) {
        guard value else { print("FAIL \(label)"); exit(1) }
        print("PASS \(label)")
    }
    static func json(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    @MainActor static func main() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let message: [String: Any] = ["id": "turn-1", "type": "gemini", "model": "gemini-2.5-flash",
            "timestamp": "2026-07-15T12:00:00Z", "tokens": ["input": 1000, "output": 200, "cached": 400, "thoughts": 50]]
        let events = CodingLogReader.parse(try json(["sessionId": "session-1", "messages": [message]]), provider: .gemini)
        expect(events.count == 1 && events[0].inputTokens == 600 && events[0].cacheReadTokens == 400,
               "Gemini cached input stays disjoint")
        expect(events[0].outputTokens == 250, "Gemini thoughts billed once as output")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let row = try json(message)
        try (row + Data([10]) + row + Data([10])).write(to: root.appendingPathComponent("session-test.jsonl"))
        let scan = CodingLogReader.scan(.gemini, root: root, now: now)
        expect(scan.events.count == 1, "Repeated streamed Gemini turn counted once")
        var kimi: [String: Any] = ["type": "usage.record", "usageScope": "turn", "model": "kimi-code/k3",
            "time": 1_780_000_000_000.0, "usage": ["inputOther": 100, "output": 25, "inputCacheCreation": 30, "inputCacheRead": 80]]
        let k = CodingLogReader.parse(try json(kimi), provider: .kimi)
        expect(k.count == 1 && k[0].inputTokens == 100 && k[0].cacheCreationTokens == 30 && k[0].cacheReadTokens == 80,
               "Kimi separate buckets preserved")
        kimi["usageScope"] = "session"
        expect(CodingLogReader.parse(try json(kimi), provider: .kimi).isEmpty, "Kimi cumulative session usage rejected")
        kimi["usageScope"] = "turn"
        kimi["usage"] = ["inputOther": -10]
        expect(CodingLogReader.parse(try json(kimi), provider: .kimi).isEmpty, "Negative tokens rejected")
        let q = try CodingProviderConnection.parseKimi(json(["usage": ["limit": "100", "used": "20"]]))
        expect(q.limits.count == 1 && q.limits[0].kind == .weekly && q.limits[0].usedFraction == 0.2,
               "Weekly-only Kimi has no synthetic five-hour quota")
        let unknown = try CodingProviderConnection.parseKimi(json(["usage": ["limit": 0, "used": 0]]))
        expect(unknown.limits.isEmpty, "Missing Kimi quota is not zero usage")
        let google = try CodingProviderConnection.parseGemini(json(["buckets": [
            ["modelId": "gemini-pro", "remainingFraction": 0.0, "resetTime": "2026-07-16T12:00:00Z"],
            ["modelId": "gemini-flash"], ["modelId": "invalid", "remainingFraction": 1.5]]]))
        expect(google.limits.count == 1 && google.limits[0].usedFraction == 1 && google.limits[0].kind == .other,
               "Gemini uses actual model quotas and omits unknown fractions")
        expect(google.plan == nil && google.limits[0].resetAt != nil, "No invented Gemini Pro subscription")
        let glm = try CodingProviderConnection.parseGLM(json(["code": 200, "data": ["limits": [
            ["type": "TOKENS_LIMIT", "percentage": "25", "resetTime": 1_780_000_000_000.0]]]]))
        expect(glm.limits.first?.usedFraction == 0.25 && glm.limits.first?.kind == .other,
               "GLM percentages do not invent quota windows")
        expect(glm.limits.first?.resetAt?.timeIntervalSince1970 == 1_780_000_000, "GLM millisecond reset timestamp")
        let defaults = UserDefaults(suiteName: "CodingProviderTests.\(UUID().uuidString)")!
        defaults.set("kimi", forKey: "MacIsland.slotLeft")
        defaults.set("glm", forKey: "MacIsland.slotRight")
        let preferences = ProviderVisibilityStore(defaults: defaults)
        expect(preferences.selected == [.kimi, .glm], "Previous multi-agent slots migrate")
        preferences.set(.gemini, at: 0)
        preferences.set(.gemini, at: 1)
        expect(preferences.selected == [.glm, .gemini], "New provider selection swaps without duplicates")
        PricingCatalog.install(models: [:], fetchedAt: now)
        expect(Pricing.canonicalModelName("google/gemini-2.5-pro") == "gemini-2.5-pro", "Provider prefix canonicalized")
        expect(Pricing.isKnown("GLM-4.7"), "GLM offline pricing available")
        expect(abs(Pricing.cost(for: events[0]) - 0.000817) < 0.00000001, "Gemini text and thinking API-equivalent pricing")
        let pro = TokenEvent(provider: .gemini, timestamp: now, model: "gemini-2.5-pro", inputTokens: 200_001,
            outputTokens: 1000, cacheCreationTokens: 0, cacheReadTokens: 0)
        expect(abs(Pricing.cost(for: pro) - 0.5150025) < 0.00000001, "Gemini Pro long-context price tier")
        let ledger = UsageLedger(url: root.appendingPathComponent("history.sqlite3"))
        _ = ledger.retain(scan.events, source: .gemini, now: now)
        let retained = ledger.retain([], source: .gemini, now: now)
        expect(retained.events.count == 1 && retained.events[0].provider == .gemini,
               "Gemini durable history survives deleted source logs")
        _ = ledger.retain(k, source: .kimi, now: now)
        expect(ledger.retain([], source: .kimi, now: now).events.count == 1, "Kimi durable history isolated")
    }
}
