import Foundation
import Security

/// Cloud sync service for syncing terminal settings to YEN cloud
/// Uses existing /api/auth/me PATCH endpoint (no new API needed)
/// File location: settings-gui/CloudSyncService.swift (flat, not in Services/)
class CloudSyncService {
    static let shared = CloudSyncService()

    private let keychainService = "com.yenchat.yen"  // Matches yen-cli/lib/keychain.sh
    private let apiBaseURL = "https://yen.chat"

    // MARK: - Keychain Access

    /// Build keychain account name matching CLI format: com.yenchat.yen.{key}
    /// Must match yen-cli/lib/keychain.sh account format exactly
    private func keychainAccount(_ key: String) -> String {
        return "\(keychainService).\(key)"
    }

    /// Check if user is logged in by checking for access_token in Keychain
    func isLoggedIn() -> Bool {
        return getAccessToken() != nil
    }

    /// Retrieve access token from macOS Keychain
    /// Matches the storage pattern in yen-cli/lib/keychain.sh
    func getAccessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount("access_token"),
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    /// Retrieve user email from Keychain (cached during login)
    func getUserEmail() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount("user_email"),
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let email = String(data: data, encoding: .utf8) else {
            return nil
        }
        return email
    }

    // MARK: - Sync Settings

    /// Sync terminal settings to cloud using existing /api/auth/me PATCH
    /// This is non-blocking and called after successful local save
    func syncSettings(_ settings: [String: String], completion: @escaping (Bool, String?) -> Void) {
        guard let token = getAccessToken() else {
            completion(false, "Not logged in")
            return
        }

        // Use existing /api/auth/me PATCH endpoint
        guard let url = URL(string: "\(apiBaseURL)/api/auth/me") else {
            completion(false, "Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"  // PATCH, not POST — matches existing API
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Structure matches existing API: { "settings": { "terminal": { ... } } }
        // The API merges this with existing settings, preserving other keys
        let payload: [String: Any] = [
            "settings": [
                "terminal": settings,
                "sync_preferences": [
                    "last_sync": ISO8601DateFormatter().string(from: Date())
                ]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(false, "Failed to serialize settings")
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, error.localizedDescription)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    completion(false, "Invalid response")
                    return
                }

                switch httpResponse.statusCode {
                case 200:
                    completion(true, nil)
                case 401:
                    completion(false, "Session expired. Please sign in again.")
                case 403:
                    completion(false, "Access denied")
                default:
                    completion(false, "Server error: \(httpResponse.statusCode)")
                }
            }
        }.resume()
    }

    /// Fetch current settings from cloud
    /// Used to check if cloud has settings before showing sync prompt
    func fetchSettings(completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let token = getAccessToken() else {
            completion(.failure(CloudSyncError.notLoggedIn))
            return
        }

        guard let url = URL(string: "\(apiBaseURL)/api/auth/me") else {
            completion(.failure(CloudSyncError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      let data = data else {
                    completion(.failure(CloudSyncError.serverError))
                    return
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let dataWrapper = json["data"] as? [String: Any],
                       let profile = dataWrapper["profile"] as? [String: Any],
                       let settings = profile["settings"] as? [String: Any] {
                        completion(.success(settings))
                    } else {
                        completion(.success([:]))
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
}

// MARK: - Error Types

enum CloudSyncError: LocalizedError {
    case notLoggedIn
    case invalidURL
    case serverError
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "Not logged in"
        case .invalidURL:
            return "Invalid URL"
        case .serverError:
            return "Server error"
        case .sessionExpired:
            return "Session expired"
        }
    }
}
