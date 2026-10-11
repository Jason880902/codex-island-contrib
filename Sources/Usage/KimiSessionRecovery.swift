import Foundation
import Darwin

enum KimiSessionRecovery {
    static func fetch(operation: () async throws -> ConnectedUsage,
                      renew: () async throws -> Void = { try await KimiSessionRecovery.renew() }) async throws -> ConnectedUsage {
        try await ProviderSessionRecovery.fetch(operation: operation, renew: renew)
    }

    static func renew(timeout: TimeInterval = 25) async throws {
        guard let executable = ProviderSessionRecovery.binary("kimi") else { throw ProviderConnectionError.expired }
        try Task.checkCancellation()
        let process = Process()
        do {
            try await withTaskCancellationHandler {
                try await Task.detached(priority: .utility) {
                    try checkSession(executable: executable, process: process, timeout: timeout)
                }.value
                try Task.checkCancellation()
            } onCancel: {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        } catch {
            try Task.checkCancellation()
            throw error
        }
    }

    private static func checkSession(executable: String, process: Process, timeout: TimeInterval) throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("CodexIsland-kimi-renew-\(UUID().uuidString)")
        let path = scratch.appendingPathComponent("empty-path")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: scratch) }
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["login"]
        process.currentDirectoryURL = scratch
        var environment = ProcessInfo.processInfo.environment
        // The bundled CLI is self-contained. An empty child PATH prevents its browser opener from running.
        environment["PATH"] = path.path
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        let stop = DispatchWorkItem { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: stop)
        defer {
            stop.cancel()
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? errors.fileHandleForReading.close()
        }
        var tail = ""
        while true {
            let data = errors.fileHandleForReading.availableData
            if data.isEmpty { break }
            tail = String((tail + String(decoding: data, as: UTF8.self)).suffix(4096))
            if tail.contains("Opening browser for Kimi device login:") || tail.contains("Waiting for authorization") {
                throw ProviderConnectionError.expired
            }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ProviderConnectionError.unavailable }
    }
}
