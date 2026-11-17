#if os(macOS)
import Foundation

struct IDEBlockingProcessOutput: Sendable {
    let stdout: String
    let stderr: String
    let stdoutBytes: Data
    let stderrBytes: Data
    let terminationStatus: Int32
    var wasTruncated = false
}

enum IDEBlockingProcessRunner {
    static func run<Failure: Error>(
        executableURL: URL,
        arguments: [String],
        currentDirectory: String,
        environment: [String: String]? = nil,
        allowedExitCodes: Set<Int32> = [0],
        allowAnyExitCode: Bool = false,
        standardInput: Data? = nil,
        terminationGracePeriod: TimeInterval? = nil,
        stdoutLimit: Int? = nil,
        stderrLimit: Int? = nil,
        toolUnavailable: @autoclosure @escaping @Sendable () -> Failure,
        commandFailed: @escaping @Sendable (String) -> Failure
    ) async throws -> IDEBlockingProcessOutput {
        let processBox = IDEProcessBox(terminationGracePeriod: terminationGracePeriod)
        let output = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                process.executableURL = executableURL
                process.arguments = arguments
                process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
                if let environment { process.environment = environment }
                let capture = IDEProcessCapture(
                    process: process, processBox: processBox,
                    standardInput: standardInput, stdoutLimit: stdoutLimit,
                    stderrLimit: stderrLimit, continuation: continuation)
                capture.installHandlers()
                do {
                    try processBox.launch(process)
                    capture.writeInput(standardInput)
                } catch is CancellationError {
                    capture.fail(CancellationError())
                } catch {
                    capture.fail(toolUnavailable())
                }
            }
        } onCancel: {
            processBox.terminate()
        }
        guard allowAnyExitCode || allowedExitCodes.contains(output.terminationStatus) else {
            let stderr = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            throw commandFailed(stderr.isEmpty ? stdout : stderr)
        }
        return output
    }

    /// Use the throwing API: an early reader exit must not raise an Objective-C
    /// exception when a large input write encounters EPIPE.
    static func writeStandardInput(_ data: Data, to handle: FileHandle) {
        try? handle.write(contentsOf: data)
        try? handle.close()
    }
}

private struct IDECapturedBytes {
    var data = Data()
    var truncated = false
    let limit: Int?

    mutating func append(_ chunk: Data) {
        let available = limit.map { max(0, $0 - data.count) } ?? chunk.count
        data.append(chunk.prefix(available))
        truncated = truncated || chunk.count > available
    }
}

/// Completion waits for process termination AND both EOFs (and any stdin write).
/// A termination callback can arrive before the last output callback.
private final class IDEProcessCapture: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private let processBox: IDEProcessBox
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stdinPipe: Pipe?
    private var stdout: IDECapturedBytes
    private var stderr: IDECapturedBytes
    private var pendingIO: Int
    private var status: Int32?
    private var continuation: CheckedContinuation<IDEBlockingProcessOutput, Error>?

    init(process: Process, processBox: IDEProcessBox, standardInput: Data?,
         stdoutLimit: Int?, stderrLimit: Int?,
         continuation: CheckedContinuation<IDEBlockingProcessOutput, Error>) {
        self.process = process
        self.processBox = processBox
        self.continuation = continuation
        stdout = IDECapturedBytes(limit: stdoutLimit)
        stderr = IDECapturedBytes(limit: stderrLimit)
        stdinPipe = standardInput == nil ? nil : Pipe()
        pendingIO = stdinPipe == nil ? 2 : 3
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        if let stdinPipe { process.standardInput = stdinPipe }
    }

    func installHandlers() {
        stdoutPipe.fileHandleForReading.readabilityHandler = { [self] in read($0, isStdout: true) }
        stderrPipe.fileHandleForReading.readabilityHandler = { [self] in read($0, isStdout: false) }
        process.terminationHandler = { [self] process in
            lock.lock()
            status = process.terminationStatus
            lock.unlock()
            finishIfReady()
        }
    }

    func writeInput(_ data: Data?) {
        guard let data, let stdinPipe else { return }
        // Only optional stdin uses a blocking I/O queue; neither the cooperative
        // executor nor output-drain workers wait for a child to finish.
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            IDEBlockingProcessRunner.writeStandardInput(data, to: stdinPipe.fileHandleForWriting)
            finishedIO()
        }
    }

    private func read(_ handle: FileHandle, isStdout: Bool) {
        do {
            let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                try? handle.close()
                finishedIO()
            } else {
                lock.lock()
                if isStdout { stdout.append(chunk) } else { stderr.append(chunk) }
                lock.unlock()
            }
        } catch {
            processBox.terminate()
            fail(error)
        }
    }

    private func finishedIO() {
        lock.lock()
        pendingIO -= 1
        lock.unlock()
        finishIfReady()
    }

    private func finishIfReady() {
        lock.lock()
        guard pendingIO == 0, let status, let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        let stdout = self.stdout
        let stderr = self.stderr
        lock.unlock()
        cleanup()
        continuation.resume(returning: IDEBlockingProcessOutput(
            stdout: String(decoding: stdout.data, as: UTF8.self),
            stderr: String(decoding: stderr.data, as: UTF8.self),
            stdoutBytes: stdout.data, stderrBytes: stderr.data,
            terminationStatus: status, wasTruncated: stdout.truncated || stderr.truncated))
    }

    func fail(_ error: Error) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        guard let continuation else { return }
        cleanup()
        continuation.resume(throwing: error)
    }

    private func cleanup() {
        process.terminationHandler = nil
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        try? stdoutPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()
        if let stdinPipe {
            try? stdinPipe.fileHandleForReading.close()
            try? stdinPipe.fileHandleForWriting.close()
        }
        // Preserve any scheduled termination escalation after an I/O failure.
        if !process.isRunning { processBox.clear(process) }
    }
}

private final class IDEProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancellationRequested = false
    private let terminationGracePeriod: TimeInterval?

    init(terminationGracePeriod: TimeInterval?) {
        self.terminationGracePeriod = terminationGracePeriod
    }

    /// Atomically checks the cancellation latch and launches the process while
    /// holding the same lock used by `terminate()`. Cancellation therefore either
    /// wins before spawn, or waits for `run()` to return and immediately terminates
    /// the now-running process; there is no store-before-run race window.
    func launch(_ process: Process) throws {
        lock.lock()
        defer { lock.unlock() }

        guard !cancellationRequested else {
            throw CancellationError()
        }

        try process.run()
        self.process = process
    }

    func clear(_ process: Process) {
        lock.lock()
        if self.process === process {
            self.process = nil
        }
        lock.unlock()
    }

    func terminate() {
        lock.lock()
        cancellationRequested = true
        let process = self.process
        lock.unlock()

        guard let process, process.isRunning else { return }
        process.terminate()
        if let terminationGracePeriod {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + terminationGracePeriod) {
                self.killIfStillRunning(process)
            }
        }
    }

    private func killIfStillRunning(_ candidate: Process) {
        lock.lock()
        defer { lock.unlock() }
        guard process === candidate, candidate.isRunning else { return }
        kill(candidate.processIdentifier, SIGKILL)
    }
}
#endif
