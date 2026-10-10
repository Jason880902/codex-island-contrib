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
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["acp"]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        let stop = DispatchWorkItem { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: stop)
        defer {
            stop.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        var buffer = Data()
        func request(_ id: Int, method: String, params: [String: Any]) throws {
            let payload: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
            var data = try JSONSerialization.data(withJSONObject: payload)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
            while Date() < deadline {
                if let newline = buffer.firstIndex(of: 10) {
                    let line = Data(buffer[..<newline])
                    buffer.removeSubrange(...newline)
                    guard let response = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                          response["id"] as? Int == id else { continue }
                    if response["error"] != nil { throw ProviderConnectionError.expired }
                    guard response["result"] != nil else { throw ProviderConnectionError.invalidResponse }
                    return
                }
                let chunk = output.fileHandleForReading.availableData
                guard !chunk.isEmpty else { throw ProviderConnectionError.unavailable }
                buffer.append(chunk)
                guard buffer.count < 1_048_576 else { throw ProviderConnectionError.invalidResponse }
            }
            throw ProviderConnectionError.unavailable
        }
        // ACP checks CLI-owned auth without starting a session, model turn, or browser login.
        try request(1, method: "initialize", params: ["protocolVersion": 1, "clientCapabilities": [:]])
        try request(2, method: "authenticate", params: ["methodId": "login"])
    }
}
