import Foundation

enum CodingLogReader {
    static func scan(_ provider: TokenEvent.Provider, root: URL? = nil, now: Date = Date()) -> LocalCostScan {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let environment = ProcessInfo.processInfo.environment
        let base = provider == .kimi
            ? environment["KIMI_CODE_HOME"] ?? home.appendingPathComponent(".kimi-code").path
            : environment["GEMINI_CLI_HOME"] ?? home.path
        let directory = root ?? (provider == .kimi
            ? URL(fileURLWithPath: base).appendingPathComponent("sessions")
            : URL(fileURLWithPath: base).appendingPathComponent(".gemini/tmp"))
        var result = LocalCostScan()
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return result }
        var events: [String: TokenEvent] = [:]
        for case let file as URL in files {
            let isJSONL = file.pathExtension == "jsonl"
            guard provider == .kimi ? file.lastPathComponent == "wire.jsonl"
                : isJSONL || (file.pathExtension == "json" && file.lastPathComponent.hasPrefix("session-")) else { continue }
            guard FileManager.default.isReadableFile(atPath: file.path) else { result.unreadableFiles += 1; continue }
            let accept: (Data) -> Void = { data in
                for event in parse(data, provider: provider) where event.timestamp <= now {
                    guard let id = event.recordID else { continue }
                    if let old = events[id], old.timestamp > event.timestamp { continue }
                    events[id] = event
                }
            }
            if isJSONL { LogParseCache.streamLines(at: file, maxLineBytes: 2_097_152, onLine: accept) }
            else if let data = try? Data(contentsOf: file) { accept(data) }
            else { result.unreadableFiles += 1 }
        }
        result.events = events.values.sorted { $0.timestamp < $1.timestamp }
        return result
    }

    static func parse(_ data: Data, provider: TokenEvent.Provider) -> [TokenEvent] {
        guard provider != .kimi || data.range(of: Data("\"usage.record\"".utf8)) != nil else { return [] }
        guard let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let session = row["sessionId"] as? String ?? ""
        let rows = row["messages"] as? [[String: Any]] ?? [row]
        return rows.compactMap { message in
            let kimi = provider == .kimi
            guard message["type"] as? String == (kimi ? "usage.record" : "gemini"),
                  !kimi || message["usageScope"] as? String == "turn",
                  let usage = message[kimi ? "usage" : "tokens"] as? [String: Any],
                  let model = message["model"] as? String, !model.isEmpty else { return nil }
            let timestamp: Date?
            if kimi, let ms = message["time"] as? Double, ms.isFinite, ms > 0 {
                timestamp = Date(timeIntervalSince1970: ms / 1000)
            } else { timestamp = date(message["timestamp"] as? String) }
            guard let timestamp else { return nil }
            func count(_ key: String) -> Int { usage[key] as? Int ?? 0 }
            let fullInput = count(kimi ? "inputOther" : "input")
            let cached = count(kimi ? "inputCacheRead" : "cached")
            let write = kimi ? count("inputCacheCreation") : 0
            let output = count("output") + (kimi ? 0 : count("thoughts"))
            guard [fullInput, cached, write, output].allSatisfy({ (0...1_000_000_000).contains($0) }),
                  kimi || fullInput >= cached, fullInput + cached + write + output > 0 else { return nil }
            let input = kimi ? fullInput : fullInput - cached
            let fingerprint = "\(Int64(timestamp.timeIntervalSince1970 * 1000)):\(model):\(input):\(output):\(write):\(cached)"
            let id = message["id"] as? String
            return TokenEvent(provider: provider, timestamp: timestamp, model: model,
                inputTokens: input, outputTokens: output, cacheCreationTokens: write, cacheReadTokens: cached,
                recordID: id.map { "\(session):\($0)" } ?? fingerprint)
        }
    }

    private static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
