import Foundation
import Testing
@testable import YEN

struct IDEBlockingProcessRunnerTests {
    private enum RunnerError: Error, Equatable {
        case unavailable
        case failed(String)
    }

    @Test func capsOutputWhileContinuingToDrainBothPipes() async throws {
        let output = try await IDEBlockingProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "head -c 4194304 /dev/zero; head -c 4194304 /dev/zero >&2"],
            currentDirectory: "/", stdoutLimit: 4096, stderrLimit: 2048,
            toolUnavailable: RunnerError.unavailable, commandFailed: RunnerError.failed)
        #expect(output.terminationStatus == 0)
        #expect(output.stdoutBytes.count == 4096)
        #expect(output.stderrBytes.count == 2048)
        let truncated = output.wasTruncated
        #expect(truncated)
    }

    @Test func exactAndZeroByteLimitsPreserveTruncationMeaning() async throws {
        for limit in [0, 3, 4] {
            let output = try await IDEBlockingProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf abc"], currentDirectory: "/",
                stdoutLimit: limit, stderrLimit: 0,
                toolUnavailable: RunnerError.unavailable, commandFailed: RunnerError.failed)
            #expect(output.stdoutBytes == Data("abc".utf8.prefix(limit)))
            #expect(output.stderrBytes.isEmpty)
            #expect(output.wasTruncated == (limit < 3))
        }
    }

    @Test func launchFailureResumesWithUnavailableError() async {
        do {
            _ = try await IDEBlockingProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/nonexistent/yen-test-executable"),
                arguments: [], currentDirectory: "/", standardInput: Data("input".utf8),
                toolUnavailable: RunnerError.unavailable, commandFailed: RunnerError.failed)
            Issue.record("Expected launch failure.")
        } catch let error as RunnerError {
            #expect(error == .unavailable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func simultaneousChildrenDrainOutputBeforeCompleting() async throws {
        try await withThrowingTaskGroup(of: IDEBlockingProcessOutput.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    try await IDEBlockingProcessRunner.run(
                        executableURL: URL(fileURLWithPath: "/bin/cat"), arguments: [],
                        currentDirectory: "/", standardInput: Data(repeating: 120, count: 128 * 1024),
                        toolUnavailable: RunnerError.unavailable, commandFailed: RunnerError.failed)
                }
            }
            var completed = 0
            for try await output in group {
                #expect(output.stdoutBytes == Data(repeating: 120, count: 128 * 1024))
                #expect(!output.wasTruncated)
                completed += 1
            }
            #expect(completed == 16)
        }
    }

    @Test func cancellationEscalatesWhenChildIgnoresTermination() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ready = directory.appendingPathComponent("ready")
        let task = Task {
            try await IDEBlockingProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "trap '' TERM; printf ready > ready; while :; do :; done"],
                currentDirectory: directory.path,
                allowAnyExitCode: true,
                terminationGracePeriod: 0.2,
                toolUnavailable: RunnerError.unavailable,
                commandFailed: RunnerError.failed
            )
        }
        defer { task.cancel() }
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: ready.path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(FileManager.default.fileExists(atPath: ready.path))
        task.cancel()
        let output = try await task.value
        #expect(output.terminationStatus == SIGKILL)
    }

    @Test func capturesStdoutAndStderrSeparately() async throws {
        let output = try await IDEBlockingProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'out'; printf 'err' >&2"],
            currentDirectory: "/",
            toolUnavailable: RunnerError.unavailable,
            commandFailed: RunnerError.failed
        )

        #expect(output.stdout == "out")
        #expect(output.stderr == "err")
    }

    @Test func preservesProcessOutputWhitespaceForDiffBodies() async throws {
        let output = try await IDEBlockingProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'line with trailing spaces   \\n\\n'"],
            currentDirectory: "/",
            toolUnavailable: RunnerError.unavailable,
            commandFailed: RunnerError.failed
        )

        #expect(output.stdout == "line with trailing spaces   \n\n")
    }

    @Test func preservesRawOutputBytesForByteSensitiveCallers() async throws {
        let output = try await IDEBlockingProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'good.txt\\0bad\\377.txt\\0'"],
            currentDirectory: "/",
            toolUnavailable: RunnerError.unavailable,
            commandFailed: RunnerError.failed
        )

        #expect(
            output.stdoutBytes
                == Data([
                    0x67, 0x6F, 0x6F, 0x64, 0x2E, 0x74, 0x78, 0x74, 0x00,
                    0x62, 0x61, 0x64, 0xFF, 0x2E, 0x74, 0x78, 0x74, 0x00,
                ])
        )
        #expect(output.stdout.contains("bad\u{FFFD}.txt"))
    }

    @Test func passesExplicitEnvironmentValues() async throws {
        let output = try await IDEBlockingProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf \"$YEN_TEST_PROCESS_ENV\""],
            currentDirectory: "/",
            environment: ["YEN_TEST_PROCESS_ENV": "present"],
            toolUnavailable: RunnerError.unavailable,
            commandFailed: RunnerError.failed
        )

        #expect(output.stdout == "present")
    }

    @Test func surfacesFailureDetailFromCommandOutput() async {
        do {
            _ = try await IDEBlockingProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf 'boom' >&2; exit 9"],
                currentDirectory: "/",
                toolUnavailable: RunnerError.unavailable,
                commandFailed: RunnerError.failed
            )
            Issue.record("Expected command failure.")
        } catch let error as RunnerError {
            #expect(error == .failed("boom"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func writesStandardInputToTheProcess() async throws {
        let output = try await IDEBlockingProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/cat"),
            arguments: [],
            currentDirectory: "/",
            standardInput: Data("hello".utf8),
            toolUnavailable: RunnerError.unavailable,
            commandFailed: RunnerError.failed
        )

        #expect(output.stdout == "hello")
    }

    @Test func writesLargeStandardInputWithoutDeadlocking() async throws {
        // A payload past the ~64KB pipe buffer deadlocks if stdin is written before
        // stdout is drained; the concurrent stdin arm keeps both pipes flowing.
        let payload = String(repeating: "x", count: 512 * 1024)
        let output = try await IDEBlockingProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/cat"),
            arguments: [],
            currentDirectory: "/",
            standardInput: Data(payload.utf8),
            toolUnavailable: RunnerError.unavailable,
            commandFailed: RunnerError.failed
        )

        #expect(output.stdout == payload)
    }

    @Test func toleratesReaderExitingBeforeStandardInputIsFullyWritten() async throws {
        // The reader consumes a few bytes then exits, closing its stdin read end
        // while a large payload is still in flight -> EPIPE on our write. The write
        // must fail gracefully (throwing write + try?) rather than raise an
        // uncatchable NSFileHandleOperationException (Ghostty ignores SIGPIPE
        // process-wide, so that would abort the whole app), and the run must still
        // complete with the reader's partial output. Mirrors the cancel->terminate
        // race the merge-conflict preview can hit during rapid hunk navigation.
        let payload = String(repeating: "x", count: 512 * 1024)
        let output = try await IDEBlockingProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "head -c 8; exit 0"],
            currentDirectory: "/",
            allowAnyExitCode: true,
            standardInput: Data(payload.utf8),
            toolUnavailable: RunnerError.unavailable,
            commandFailed: RunnerError.failed
        )

        #expect(output.stdout == "xxxxxxxx")
    }

    @Test func cancellationBeforeRunnerEntryDoesNotLaunchTheProcess() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("yen-cancelled-process-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let launchSentinel = directory.appendingPathComponent("launched")
        let task = Task { () throws -> IDEBlockingProcessOutput in
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            return try await IDEBlockingProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/touch"),
                arguments: [launchSentinel.path],
                currentDirectory: "/",
                toolUnavailable: RunnerError.unavailable,
                commandFailed: RunnerError.failed
            )
        }

        do {
            _ = try await task.value
            Issue.record("Expected cancellation before subprocess launch.")
        } catch is CancellationError {
            // Expected: the cancellation latch prevents Process.run().
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }

        #expect(!FileManager.default.fileExists(atPath: launchSentinel.path))
    }
}
