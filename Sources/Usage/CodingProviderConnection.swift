import Foundation
import CryptoKit

enum CodingProviderConnection {
    static func fetch(_ provider: IslandProvider) async throws -> ConnectedUsage {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let env = ProcessInfo.processInfo.environment
        if provider == .glm {
            let key = env["ZAI_API_KEY"] ?? env["GLM_API_KEY"] ?? GLMKeyStore.read() ?? UserDefaults.standard.string(forKey: "MacIsland.glmAPIKey") ?? ""
            guard !key.isEmpty else { throw ProviderConnectionError.signIn }
            let base = env["GLM_BASE_URL"] ?? UserDefaults.standard.string(forKey: "MacIsland.glmBaseURL") ?? "https://open.bigmodel.cn"
            let data = try await send(base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/monitor/usage/quota/limit", token: key, bearer: false)
            var value = try parseGLM(data)
            value.accountID = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
            return value
        }
        let file: URL
        if provider == .kimi {
            let base = env["KIMI_CODE_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".kimi-code")
            file = base.appendingPathComponent("credentials/kimi-code.json")
        } else {
            let base = env["GEMINI_CLI_HOME"].map { URL(fileURLWithPath: $0) } ?? home
            file = base.appendingPathComponent(".gemini/oauth_creds.json")
        }
        guard let data = try? Data(contentsOf: file),
              let creds = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = creds["access_token"] as? String, !token.isEmpty else { throw ProviderConnectionError.signIn }
        let expiry = number(creds[provider == .kimi ? "expires_at" : "expiry_date"])
        if let expiry, expiry / (provider == .kimi ? 1 : 1000) <= Date().timeIntervalSince1970 { throw ProviderConnectionError.expired }
        if provider == .kimi {
            let base = env["KIMI_CODE_BASE_URL"] ?? "https://api.kimi.com"
            return try parseKimi(await send(base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/coding/v1/usages", token: token))
        }
        let base = "https://cloudcode-pa.googleapis.com/v1internal:"
        let loaded = try await send(base + "loadCodeAssist", token: token,
            body: ["metadata": ["ideType": "GEMINI_CLI", "platform": "DARWIN", "pluginType": "GEMINI"]])
        guard let load = try JSONSerialization.jsonObject(with: loaded) as? [String: Any],
              let project = load["cloudaicompanionProject"] as? String, !project.isEmpty else { throw ProviderConnectionError.invalidResponse }
        var value = try parseGemini(await send(base + "retrieveUserQuota", token: token, body: ["project": project]))
        value.accountID = project
        let tier = load["paidTier"] as? [String: Any] ?? load["currentTier"] as? [String: Any]
        value.plan = tier?["name"] as? String
        return value
    }

    static func parseKimi(_ data: Data) throws -> ConnectedUsage {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProviderConnectionError.invalidResponse }
        var limits: [ConnectedLimit] = []
        func limit(_ value: Any?, id: String, label: String, kind: ConnectedLimitKind) -> ConnectedLimit? {
            guard let value = value as? [String: Any], let total = number(value["limit"]), total > 0,
                  let used = number(value["used"]), used >= 0 else { return nil }
            return ConnectedLimit(id: id, label: label, usedFraction: min(1, used / total),
                resetAt: ProviderPayload.date(value["resetTime"] as? String), kind: kind)
        }
        for item in obj["limits"] as? [[String: Any]] ?? [] {
            guard let window = item["window"] as? [String: Any], number(window["duration"]) == 300,
                  window["timeUnit"] as? String == "TIME_UNIT_MINUTE" else { continue }
            if let value = limit(item["detail"], id: "fiveHour", label: "5h", kind: .session) { limits.append(value); break }
        }
        if let value = limit(obj["usage"], id: "weekly", label: "week", kind: .weekly) { limits.append(value) }
        let user = obj["user"] as? [String: Any]
        let membership = user?["membership"] as? [String: Any]
        let plan = (membership?["level"] as? String).map { $0.replacingOccurrences(of: "LEVEL_", with: "").capitalized }
        return ConnectedUsage(limits: limits, accountID: user?["id"] as? String, plan: plan, updatedAt: Date())
    }

    static func parseGemini(_ data: Data) throws -> ConnectedUsage {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buckets = obj["buckets"] as? [[String: Any]] else { throw ProviderConnectionError.invalidResponse }
        var seen = Set<String>()
        let limits = buckets.compactMap { bucket -> ConnectedLimit? in
            guard let model = bucket["modelId"] as? String, !model.isEmpty,
                  let remaining = ProviderPayload.fraction(number(bucket["remainingFraction"])) else { return nil }
            let type = bucket["tokenType"] as? String ?? "Usage"
            let id = "\(model):\(type)"
            guard seen.insert(id).inserted else { return nil }
            return ConnectedLimit(id: id, label: model, usedFraction: 1 - remaining,
                resetAt: ProviderPayload.date(bucket["resetTime"] as? String), groupLabel: "Gemini")
        }.sorted { $0.id < $1.id }
        return ConnectedUsage(limits: limits, updatedAt: Date())
    }

    static func parseGLM(_ data: Data) throws -> ConnectedUsage {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              number(obj["code"]) == nil || number(obj["code"]) == 200,
              let body = obj["data"] as? [String: Any],
              let rows = body["limits"] as? [[String: Any]] else { throw ProviderConnectionError.invalidResponse }
        let limits = rows.compactMap { item -> ConnectedLimit? in
            guard let type = item["type"] as? String, let pct = number(item["percentage"]), (0...100).contains(pct) else { return nil }
            let reset = ProviderPayload.date(item["resetTime"] as? String)
                ?? number(item["resetTime"]).map { Date(timeIntervalSince1970: $0 > 100_000_000_000 ? $0 / 1000 : $0) }
            // GLM meter names do not establish five-hour or weekly durations.
            return ConnectedLimit(id: type, label: type == "TIME_LIMIT" ? "Requests" : type == "TOKENS_LIMIT" ? "Tokens" : type,
                usedFraction: pct / 100, resetAt: reset)
        }
        return ConnectedUsage(limits: limits, updatedAt: Date())
    }

    private static func number(_ value: Any?) -> Double? {
        let number = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
        guard let number, number.isFinite else { return nil }
        return number
    }

    private static func send(_ endpoint: String, token: String, bearer: Bool = true, body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: endpoint), url.scheme == "https" else { throw ProviderConnectionError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(bearer ? "Bearer \(token)" : token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ProviderConnectionError.invalidResponse }
        guard response.statusCode == 200 else { throw ProviderConnectionError.http(response.statusCode) }
        return data
    }
}

extension IslandProvider {
    var connectionCommand: String {
        switch self {
        case .kimi: return "kimi"
        case .gemini: return "gemini"
        case .glm: return ""
        case .grok: return "grok"
        default: return "agy"
        }
    }
    var connectionAction: String {
        switch self {
        case .kimi: return "Sign in with Kimi CLI"
        case .gemini: return "Open Gemini CLI"
        case .glm: return "Configure GLM API key"
        case .grok: return "Sign in with Grok CLI"
        default: return "Open agy CLI"
        }
    }
    var connectionHint: String {
        switch self {
        case .kimi: return "Run kimi login, then refresh the connection."
        case .gemini: return "Open Gemini CLI and sign in with Google, then refresh the connection."
        case .glm: return "Enter your Coding Plan API key in provider settings, then refresh."
        case .grok: return "Run grok login, then refresh the connection."
        default: return "Open agy CLI to restore your session, then refresh the connection."
        }
    }
    var installationURL: String {
        switch self {
        case .kimi: return "https://kimi.com/code"
        case .gemini: return "https://github.com/google-gemini/gemini-cli"
        case .glm: return "https://docs.z.ai/devpack/overview"
        case .grok: return "https://grok.com/build"
        default: return "https://antigravity.google/docs/cli/install/"
        }
    }
}
