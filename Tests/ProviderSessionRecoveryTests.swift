import Foundation

@main
struct ProviderSessionRecoveryTests {
    static func main() async throws {
        for error in [ProviderConnectionError.expired, .http(401)] {
            var attempts = 0
            var renewals = 0
            let usage = try await ProviderSessionRecovery.fetch {
                attempts += 1
                if attempts == 1 { throw error }
                return ConnectedUsage(plan: "recovered")
            } renew: { renewals += 1 }
            precondition(attempts == 2 && renewals == 1 && usage.plan == "recovered")
        }
        for error in [ProviderConnectionError.signIn, .http(403), .http(429), .unavailable] {
            var renewals = 0
            do {
                _ = try await ProviderSessionRecovery.fetch { throw error } renew: { renewals += 1 }
                fatalError("Expected failure")
            } catch { precondition(renewals == 0) }
        }
        var attempts = 0
        var renewals = 0
        do {
            _ = try await ProviderSessionRecovery.fetch {
                attempts += 1
                throw ProviderConnectionError.expired
            } renew: { renewals += 1 }
            fatalError("Expected failure after one retry")
        } catch { precondition(attempts == 2 && renewals == 1) }
        do {
            _ = try await ProviderSessionRecovery.fetch {
                throw ProviderConnectionError.expired
            } renew: { throw CancellationError() }
            fatalError("Expected cancellation")
        } catch is CancellationError { }
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: fixture.appendingPathComponent("bin"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let kimi = fixture.appendingPathComponent("bin/kimi")
        try "#!/bin/sh\nexit 0\n".write(to: kimi, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: kimi.path)
        let previousHome = ProcessInfo.processInfo.environment["KIMI_CODE_HOME"]
        setenv("KIMI_CODE_HOME", fixture.path, 1)
        defer {
            if let previousHome { setenv("KIMI_CODE_HOME", previousHome, 1) }
            else { unsetenv("KIMI_CODE_HOME") }
        }
        precondition(ProviderSessionRecovery.binary("kimi") == kimi.path, "Kimi CLI must be discovered in KIMI_CODE_HOME/bin")
        let credential = try GrokConnection.credential(from: Data(#"{"https://auth.x.ai::a":{"key":"old","expires_at":"2000-01-01T00:00:00Z"},"https://auth.x.ai::b":{"key":"current","expires_at":"2099-01-01T00:00:00Z"}}"#.utf8))
        precondition(credential.key == "current")
        print("PASS session renewal, bounded retry, error classification, cancellation, and valid Grok credential selection")
    }
}
