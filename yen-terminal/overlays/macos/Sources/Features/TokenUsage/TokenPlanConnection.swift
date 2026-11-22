import Foundation
import Security
import SwiftUI

/// Uses only a user API key supplied to YEN and the two usage reads from Cursor's dashboard.
struct TokenPlanClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    var transport: Transport = { try await TokenPlanHTTP.session.data(for: $0) }

    enum Failure: Error { case signIn, response }
    struct Pools: Sendable {
        let meters: [TokenPlanMeter]
        let partial: Bool
    }

    func read(key: String) async throws -> Pools {
        struct Login: Decodable { let accessToken: String }
        let exchange = try await request("auth/exchange_user_api_key", token: key)
        let token = try JSONDecoder().decode(Login.self, from: exchange).accessToken
        guard !token.isEmpty else { throw Failure.signIn }
        async let monthly = fetchPool("GetCurrentPeriodUsage", token: token)
        async let weekly = fetchPool("GetSandUsageStatus", token: token)
        let (period, bot) = await (monthly, weekly)
        guard period != nil || bot != nil else { throw Failure.response }
        return Pools(meters: (period ?? []) + (bot ?? []), partial: period == nil || bot == nil)
    }

    private func fetchPool(_ method: String, token: String) async -> [TokenPlanMeter]? {
        guard let data = try? await request("aiserver.v1.DashboardService/" + method, token: token),
              let object = try? JSONSerialization.jsonObject(with: data) as? TokenRecord.Object else { return nil }
        if method == "GetSandUsageStatus" {
            guard let entitled = object["hasNonZeroIncludedLimit"] as? Bool else { return nil }
            if !entitled { return [] }
            guard let meter = TokenPlanMeter("Grok Bot weekly", percent: object["usagePercent"],
                                             reset: TokenRecord.date(object["nextResetTimestampUtc"])) else { return nil }
            return [meter]
        }
        guard let usage = object["planUsage"] as? TokenRecord.Object else { return [] }
        let epoch = (object["billingCycleEnd"] as? String).flatMap(Double.init) ?? object["billingCycleEnd"] as? Double
        let end = epoch.map { Date(timeIntervalSince1970: $0 / 1000) }
        let models = TokenPlanMeter("Cursor models", percent: usage["autoPercentUsed"], reset: end)
        let other = TokenPlanMeter("Cursor other models", percent: usage["apiPercentUsed"], reset: end)
        if let models, let other, models.percent == other.percent {
            return [TokenPlanMeter("Cursor all models", percent: models.percent, reset: end)!]
        }
        let separate = [models, other].compactMap { $0 }
        if !separate.isEmpty { return separate }
        return [TokenPlanMeter("Cursor included", percent: usage["totalPercentUsed"], reset: end)].compactMap { $0 }
    }

    private func request(_ path: String, token: String) async throws -> Data {
        try Task.checkCancellation()
        let base = URL(string: "https://api2.cursor.sh")!
        var request = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: 15)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport(request)
        let status = (response as? HTTPURLResponse)?.statusCode
        if status == 401 || status == 403 { throw Failure.signIn }
        guard status == 200 else { throw Failure.response }
        return data
    }
}

private final class TokenPlanHTTP: NSObject, URLSessionTaskDelegate {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        return URLSession(configuration: config, delegate: TokenPlanHTTP(), delegateQueue: nil)
    }()

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private enum TokenPlanKey {
    static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "com.yenchat.yen") + ".token-usage",
         kSecAttrAccount as String: "cursor-plan"]
    }

    static func save(_ key: String) -> Bool {
        var item = query
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let result = SecItemAdd(item as CFDictionary, nil)
        if result == errSecDuplicateItem {
            return SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data(key.utf8)] as CFDictionary) == errSecSuccess
        }
        return result == errSecSuccess
    }

    static func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        var data: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &data) == errSecSuccess, let bytes = data as? Data else { return nil }
        return String(data: bytes, encoding: .utf8)
    }

    static func remove() -> Bool {
        let result = SecItemDelete(query as CFDictionary)
        return result == errSecSuccess || result == errSecItemNotFound
    }
}

@MainActor
final class TokenPlanConnection: ObservableObject {
    private static let enabledKey = "com.yenchat.yen.tokenUsage.cursorPlan"
    @Published private(set) var connected: Bool
    @Published private(set) var meters: [TokenPlanMeter] = []
    @Published private(set) var message: String?
    @Published private(set) var loading = false
    private var task: Task<Void, Never>?
    private var lastAttempt = Date.distantPast
    private let client: TokenPlanClient
    private let savedKey: () -> String?

    /// A test supplies the client, the saved key and the connection state, so it never touches the Keychain.
    init(client: TokenPlanClient = TokenPlanClient(), savedKey: @escaping () -> String? = TokenPlanKey.read,
         connected: Bool = UserDefaults.standard.bool(forKey: TokenPlanConnection.enabledKey)) {
        self.client = client
        self.savedKey = savedKey
        self.connected = connected
    }

    /// Reset All Settings removes the saved key and the menu's display choices.
    @discardableResult
    static func reset(defaults: UserDefaults = .standard, removeKey: () -> Bool = TokenPlanKey.remove) -> Bool {
        for key in [enabledKey, TokenMenuDisplay.key, TokenMenuDisplay.columnsKey] { defaults.removeObject(forKey: key) }
        return removeKey()
    }

    func connect(_ key: String) {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        load(key: key, save: true)
    }

    func refresh(force: Bool = false) {
        guard connected, task == nil, force || Date().timeIntervalSince(lastAttempt) >= 300 else { return }
        lastAttempt = Date()
        guard let key = savedKey() else { message = "Unlock the Keychain or reconnect to Cursor."; return }
        load(key: key, save: false)
    }

    private func load(key: String, save: Bool) {
        stop()
        loading = true
        message = nil
        lastAttempt = Date()
        task = Task {
            do {
                let pools = try await client.read(key: key)
                try Task.checkCancellation()
                if save {
                    guard TokenPlanKey.save(key) else {
                        throw CocoaError(.fileWriteNoPermission)
                    }
                    UserDefaults.standard.set(true, forKey: Self.enabledKey)
                    connected = true
                }
                meters = pools.meters
                if pools.partial { message = "Some Cursor plan readings are unavailable." }
                else if meters.isEmpty { message = "No included plan pools reported." }
            } catch {
                guard !Task.isCancelled else { return }
                meters = []
                if case TokenPlanClient.Failure.signIn = error { message = "Cursor rejected the key. Check it and reconnect." }
                else if error is CocoaError { message = "Couldn’t save the key in Keychain." }
                else { message = "Couldn’t read the Cursor plan. Try again." }
            }
            loading = false
            task = nil
        }
    }

    func disconnect() {
        stop()
        guard TokenPlanKey.remove() else { message = "Unlock the Keychain and try disconnecting again."; return }
        UserDefaults.standard.removeObject(forKey: Self.enabledKey)
        connected = false
        meters = []
        message = nil
    }

    func stop() {
        task?.cancel()
        task = nil
        loading = false
    }
}
