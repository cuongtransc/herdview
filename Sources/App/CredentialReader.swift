import Foundation
import HerdviewCore

enum CredentialLookup {
    case found(QuotaCredential)
    case notSignedIn
    case failed(String)
}

/// Reads the credential each CLI stores on this Mac. Read-only (ADR 0005).
///
/// Nothing read here is ever logged. That is also why Claude's Keychain item is
/// not read through `ProcessRunner`: it folds a failed command's output into
/// its error, and callers log errors — here that output is a token.
enum CredentialReader {
    /// `security` exits with this when the item does not exist.
    private static let itemNotFound: Int32 = 44

    static func read(_ provider: QuotaProvider, from source: QuotaSource) async -> CredentialLookup {
        if let path = QuotaCredentials.filePath(for: source, home: NSHomeDirectory()) {
            guard let data = FileManager.default.contents(atPath: path),
                  let credential = QuotaCredentials.parse(provider, from: source, data) else { return .notSignedIn }
            return .found(credential)
        }
        return await readClaudeKeychain()
    }

    /// Claude Code writes this item with `/usr/bin/security` itself, so reading
    /// it with the same binary is not expected to raise an access prompt. If
    /// macOS asks anyway, "Always Allow" answers it for good; "Deny" lands in
    /// `.failed`.
    ///
    /// The executable and timeout are parameters only so the lifecycle harness
    /// can use a harmless local process. Production always takes the defaults.
    static func readClaudeKeychain(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/security"),
        timeout: TimeInterval = 30
    ) async -> CredentialLookup {
        let cancellation = ProcessCancellation()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    let process = Process()
                    process.executableURL = executableURL
                    process.arguments = ["find-generic-password", "-s", QuotaCredentials.claudeKeychainService, "-w"]
                    let stdout = Pipe()
                    process.standardOutput = stdout
                    process.standardError = FileHandle.nullDevice
                    process.standardInput = FileHandle.nullDevice
                    do {
                        guard try cancellation.launch(process) else {
                            continuation.resume(returning: .failed("Keychain access denied"))
                            return
                        }
                    } catch {
                        continuation.resume(returning: .failed("Keychain unavailable"))
                        return
                    }
                    // A prompt left unanswered must not hold a fetch forever.
                    let killer = DispatchWorkItem { cancellation.terminateCurrent() }
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                    let data = stdout.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    killer.cancel()
                    cancellation.clear(process)

                    switch process.terminationStatus {
                    case 0:
                        if let credential = QuotaCredentials.parse(.claude, data) {
                            continuation.resume(returning: .found(credential))
                        } else {
                            continuation.resume(returning: .notSignedIn)
                        }
                    case itemNotFound:
                        continuation.resume(returning: .notSignedIn)
                    default:
                        continuation.resume(returning: .failed("Keychain access denied"))
                    }
                }
            }
        }, onCancel: {
            cancellation.cancel()
        })
    }

    /// Coordinates the race between Task cancellation and `Process.run()`. The
    /// lock is held across launch, so cancellation either marks the read before
    /// launch or sees a running process it can terminate; there is no gap where
    /// `/usr/bin/security` can escape cancellation.
    private final class ProcessCancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var isCancelled = false

        func launch(_ process: Process) throws -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !isCancelled else { return false }
            self.process = process
            try process.run()
            return true
        }

        func cancel() {
            lock.lock()
            isCancelled = true
            let running = process
            lock.unlock()
            if running?.isRunning == true { running?.terminate() }
        }

        func terminateCurrent() {
            lock.lock()
            let running = process
            lock.unlock()
            if running?.isRunning == true { running?.terminate() }
        }

        func clear(_ process: Process) {
            lock.lock()
            if self.process === process { self.process = nil }
            lock.unlock()
        }
    }
}
