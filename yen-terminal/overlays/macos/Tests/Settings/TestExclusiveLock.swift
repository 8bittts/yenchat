import Darwin
import Foundation

enum TestExclusiveLock {
    private static let inProcessSemaphore = DispatchSemaphore(value: 1)
    private static let asyncGate = AsyncGate()

    static func withLock<Result>(
        named name: String,
        _ operation: () throws -> Result
    ) rethrows -> Result {
        inProcessSemaphore.wait()
        let handle = LockHandle(name: name)
        defer {
            withExtendedLifetime(handle) {}
            inProcessSemaphore.signal()
        }
        return try operation()
    }

    static func withLock<Result>(
        named name: String,
        _ operation: () async throws -> Result
    ) async rethrows -> Result {
        await asyncGate.acquire()
        let handle = LockHandle(name: name)
        defer {
            withExtendedLifetime(handle) {}
            Task {
                await asyncGate.release()
            }
        }
        return try await operation()
    }

    private actor AsyncGate {
        private var isLocked = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func acquire() async {
            guard isLocked else {
                isLocked = true
                return
            }

            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        func release() {
            if let waiter = waiters.first {
                waiters.removeFirst()
                waiter.resume()
            } else {
                isLocked = false
            }
        }
    }

    private final class LockHandle {
        private let fileDescriptor: Int32

        init(name: String) {
            let filename = "yen-tests-\(name).lock"
            let path = (NSTemporaryDirectory() as NSString).appendingPathComponent(filename)
            let fd = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            precondition(fd >= 0, "Failed to open test lock file at \(path).")
            guard flock(fd, LOCK_EX) == 0 else {
                let openDescriptor = fd
                close(openDescriptor)
                preconditionFailure("Failed to acquire test lock file at \(path).")
            }
            fileDescriptor = fd
        }

        deinit {
            _ = flock(fileDescriptor, LOCK_UN)
            close(fileDescriptor)
        }
    }
}
