import Foundation

@main
struct KimiSessionRecoveryTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("bin"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let binary = root.appendingPathComponent("bin/kimi")
        let script = """
        #!/bin/sh
        test "$1" = acp || exit 8
        IFS= read -r init
        printf '%s\\n' "$init" | /usr/bin/grep -q 'initialize' || exit 9
        printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1}}'
        IFS= read -r auth
        printf '%s\\n' "$auth" | /usr/bin/grep -q 'authenticate' || exit 10
        /usr/bin/touch "$KIMI_CODE_HOME/renewed"
        printf '%s\\n' '{"jsonrpc":"2.0","id":2,"result":null}'
        """
        try script.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        let previous = ProcessInfo.processInfo.environment["KIMI_CODE_HOME"]
        setenv("KIMI_CODE_HOME", root.path, 1)
        defer {
            if let previous { setenv("KIMI_CODE_HOME", previous, 1) } else { unsetenv("KIMI_CODE_HOME") }
        }
        try await KimiSessionRecovery.renew()
        precondition(FileManager.default.fileExists(atPath: root.appendingPathComponent("renewed").path), "Kimi CLI renewal must run automatically")
        var attempts = 0
        var renewals = 0
        let restored = try await KimiSessionRecovery.fetch {
            attempts += 1
            if attempts == 1 { throw ProviderConnectionError.expired }
            return ConnectedUsage(plan: "Kimi Code")
        } renew: {
            renewals += 1
            try await KimiSessionRecovery.renew()
        }
        precondition(attempts == 2 && renewals == 1 && restored.plan == "Kimi Code")
        print("PASS Kimi discovers CLI and renews using initialize/authenticate without login or agent prompts")
        let rejection = script.replacingOccurrences(of: "\"result\":null", with: "\"error\":{\"code\":-32000}")
        try rejection.write(to: binary, atomically: true, encoding: .utf8)
        do { try await KimiSessionRecovery.renew(); fatalError("Expected rejected session") }
        catch ProviderConnectionError.expired { }
        print("PASS Kimi rejected session needs login instead of retrying indefinitely")
        let hanging = "#!/bin/sh\nwhile :; do :; done\n"
        try hanging.write(to: binary, atomically: true, encoding: .utf8)
        let began = Date()
        do { try await KimiSessionRecovery.renew(timeout: 0.2); fatalError("Expected timeout") }
        catch ProviderConnectionError.unavailable { }
        precondition(Date().timeIntervalSince(began) < 3)
        print("PASS Kimi renewal process has a bounded timeout")
        let cancelled = Task { try await KimiSessionRecovery.renew(timeout: 5) }
        try await Task.sleep(nanoseconds: 100_000_000)
        cancelled.cancel()
        do { try await cancelled.value; fatalError("Expected cancellation") }
        catch is CancellationError { }
        print("PASS deselecting Kimi cancels CLI recovery")
    }
}
