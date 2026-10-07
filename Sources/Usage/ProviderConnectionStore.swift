import AppKit
import Combine

@MainActor
final class ProviderConnectionStore: ObservableObject {
    static let shared = ProviderConnectionStore()
    @Published private(set) var snapshots: [IslandProvider: ConnectedUsage] = [:]
    @Published private(set) var loading: Set<IslandProvider> = []
    private var tasks: [IslandProvider: Task<Void, Never>] = [:]
    private var generations: [IslandProvider: UUID] = [:]
    private var lastAttempt: [IslandProvider: Date] = [:]
    private var cooldown: [IslandProvider: Date] = [:]
    private var selection: AnyCancellable?
    private var selectedProviders = Set(ProviderVisibilityStore.shared.selected)

    private init() {
        selection = ProviderVisibilityStore.shared.$selected
            .dropFirst().receive(on: RunLoop.main).sink { [weak self] selected in
                guard let self else { return }
                let next = Set(selected)
                guard next != self.selectedProviders else { return }
                for provider in self.selectedProviders.subtracting(next) {
                    self.tasks.removeValue(forKey: provider)?.cancel()
                    self.generations.removeValue(forKey: provider)
                    self.loading.remove(provider)
                    self.lastAttempt.removeValue(forKey: provider)
                }
                self.selectedProviders = next
                UsageStore.shared.refreshForSelectionChange()
            }
    }

    func snapshot(_ provider: IslandProvider) -> ConnectedUsage {
        snapshots[provider] ?? ConnectedUsage(message: provider.connectionHint, needsLogin: true)
    }

    func limits(_ provider: IslandProvider) -> [ConnectedLimit] {
        let usage = snapshot(provider)
        return ProviderQuotaPreferences.resolve(usage,
            selection: ProviderQuotaPreferences.shared.selection(for: usage.storageScope(provider: provider)))
    }

    func primary(_ provider: IslandProvider) -> ConnectedLimit? {
        let usage = snapshot(provider)
        return ProviderQuotaPreferences.primary(limits(provider),
            selection: ProviderQuotaPreferences.shared.selection(for: usage.storageScope(provider: provider)))
    }

    func refreshSelected() {
        for provider in ProviderVisibilityStore.shared.selected where !provider.usesLegacyUsage {
            refresh(provider)
        }
    }

    func refresh(_ provider: IslandProvider, manually: Bool = false) {
        guard !provider.usesLegacyUsage, !loading.contains(provider) else { return }
        if let until = cooldown[provider], until > Date() { return }
        if !manually, let previous = lastAttempt[provider], Date().timeIntervalSince(previous) < 300 { return }
        if AppEnvironment.isDemo {
            snapshots[provider] = ConnectedUsage(limits: [
                ConnectedLimit(id: "demo", label: provider == .grok ? "Credits" : provider == .gemini ? "gemini-3.6-flash" : provider == .glm ? "Requests" : "5h",
                    usedFraction: 0.38, resetAt: Date().addingTimeInterval(7200),
                    groupLabel: provider == .grok ? nil : "Gemini Models",
                    kind: provider == .grok ? .credits : .session)
            ], plan: provider == .grok ? "SuperGrok" : provider == .kimi ? "Kimi Code" : provider == .glm ? "Coding Plan" : "AI Pro", updatedAt: Date())
            if provider == .antigravity {
                snapshots[provider]?.limits.append(ConnectedLimit(id: "weekly", label: "week",
                    usedFraction: 0.62, resetAt: Date().addingTimeInterval(86400),
                    groupLabel: "Gemini Models", kind: .weekly))
                snapshots[provider]?.limits.append(ConnectedLimit(id: "model", label: "Usage",
                    usedFraction: 0.21, resetAt: Date().addingTimeInterval(14400),
                    groupID: "claude", groupLabel: "Claude Models"))
            }
            return
        }
        loading.insert(provider)
        lastAttempt[provider] = Date()
        let generation = UUID()
        generations[provider] = generation
        tasks[provider] = Task {
            defer {
                if generations[provider] == generation {
                    loading.remove(provider)
                    tasks[provider] = nil
                    generations[provider] = nil
                }
            }
            do {
                let fetched: ConnectedUsage
                if provider == .kimi || provider == .gemini || provider == .glm {
                    fetched = try await CodingProviderConnection.fetch(provider)
                } else {
                    fetched = try await ProviderSessionRecovery.fetch {
                        try await (provider == .grok ? GrokConnection.fetch() : AntigravityConnection.fetch())
                    } renew: {
                        try await ProviderSessionRecovery.renew(provider == .grok ? "grok" : "agy")
                    }
                }
                guard !Task.isCancelled else { return }
                snapshots[provider] = fetched
                if fetched.accountID != nil || fetched.account != nil {
                    for limit in fetched.limits {
                        UsageHistoryStore.shared.record(key: fetched.historyKey(provider: provider, limit: limit),
                                                        window: limit.window, at: fetched.updatedAt ?? Date())
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                var message: String
                var needsLogin = false
                switch error {
                case ProviderConnectionError.signIn, ProviderConnectionError.expired,
                     ProviderConnectionError.http(401):
                    needsLogin = true
                    message = provider.connectionHint
                case ProviderConnectionError.http(429):
                    cooldown[provider] = Date().addingTimeInterval(900)
                    message = "Rate limited. Retrying in 15 minutes."
                default:
                    message = "Could not read provider usage. Try refreshing the connection."
                }
                var retained = snapshots[provider] ?? ConnectedUsage()
                retained.message = message
                retained.needsLogin = needsLogin
                snapshots[provider] = retained
            }
        }
    }

    func connect(_ provider: IslandProvider) {
        guard !provider.usesLegacyUsage else { return }
        let command = provider.connectionCommand
        guard !command.isEmpty, let binary = ProviderSessionRecovery.binary(command) else {
            let installURL = provider.installationURL
            if let url = URL(string: installURL) { NSWorkspace.shared.open(url) }
            return
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("CodexIsland-\(command)-\(UUID().uuidString).command")
        let quoted = "'" + binary.replacingOccurrences(of: "'", with: "'\\''") + "'"
        do {
            let arguments = provider == .grok || provider == .kimi ? " login" : ""
            try ("#!/bin/sh\n" + quoted + arguments + "\n").write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            NSWorkspace.shared.open(file)
        } catch {
            snapshots[provider] = ConnectedUsage(message: provider.connectionHint, needsLogin: true)
        }
    }
}
