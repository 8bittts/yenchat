import Foundation

/// Runs a short-lived helper (the Tailscale CLI, the bundled `yen`) off the main
/// thread with a deadline, for remote session discovery.
///
/// The blocking work runs on a global dispatch queue, so awaiting `run` never
/// blocks the caller's actor, even when the caller is the main actor.
enum SessionsProcess {
    struct Outcome: Equatable, Sendable {
        /// The exit status, or nil when the process did not start or was stopped
        /// at the deadline.
        let status: Int32?
        let stdout: Data
        let timedOut: Bool
    }

    /// Variables a helper must not inherit. An app launched from a persistent
    /// pane carries that pane's zmx session, and a zmx client would treat its
    /// own work as nested in it.
    nonisolated static func helperEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        adding extra: [String: String] = [:]
    ) -> [String: String] {
        environment
            .filter { !$0.key.hasPrefix("ZMX_") }
            .merging(extra) { _, new in new }
    }

    nonisolated static func run(
        _ path: String,
        _ arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async -> Outcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: runBlocking(path, arguments, environment: environment, timeout: timeout))
            }
        }
    }

    nonisolated private final class Buffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func set(_ value: Data) {
            lock.lock()
            data = value
            lock.unlock()
        }

        func get() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    nonisolated private static func runBlocking(
        _ path: String,
        _ arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return Outcome(status: nil, stdout: Data(), timedOut: false)
        }

        let buffer = Buffer()
        let drained = DispatchSemaphore(value: 0)
        let reader = pipe.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            buffer.set(reader.readDataToEndOfFile())
            drained.signal()
        }

        let seconds = PersistentSessions.seconds(timeout)
        if exited.wait(timeout: .now() + seconds) == .timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                exited.wait()
            }
            // A grandchild (ssh under the CLI) can hold the pipe open past its
            // parent; do not wait for it.
            _ = drained.wait(timeout: .now() + 0.5)
            return Outcome(status: nil, stdout: buffer.get(), timedOut: true)
        }
        // The helper exited; give a lingering grandchild a moment, then stop reading.
        _ = drained.wait(timeout: .now() + 2)
        let status = process.terminationReason == .exit ? process.terminationStatus : nil
        return Outcome(status: status, stdout: buffer.get(), timedOut: false)
    }
}
