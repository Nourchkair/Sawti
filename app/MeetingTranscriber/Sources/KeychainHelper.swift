import Foundation
import os.log
import Security

/// macOS Keychain-based secret storage using Security.framework.
/// Same API surface as the previous file-based implementation.
enum KeychainHelper {
    private static let service = AppPaths.logSubsystem
    private static let logger = Logger(subsystem: AppPaths.logSubsystem, category: "KeychainHelper")
    private static let testStore = InMemoryTestStore()

    private static func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    /// Store or update a value in the Keychain.
    static func save(key: String, value: String) {
        if AppPaths.isRunningTests {
            testStore.save(key: key, value: value)
            return
        }

        guard let data = value.data(using: .utf8) else { return }
        var query = baseQuery(for: key)
        query[kSecValueData as String] = data

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let update = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery(for: key) as CFDictionary, update as CFDictionary)
            if updateStatus != errSecSuccess {
                logger.error("Failed to update \(key): \(updateStatus)")
            }
        } else if addStatus != errSecSuccess {
            logger.error("Failed to save \(key): \(addStatus)")
        }
    }

    /// Read a value from the Keychain. Returns `nil` if not found.
    static func read(key: String) -> String? {
        if AppPaths.isRunningTests {
            return testStore.read(key: key)
        }

        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Delete a value from the Keychain.
    static func delete(key: String) {
        if AppPaths.isRunningTests {
            testStore.delete(key: key)
            return
        }

        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    /// Check whether a value exists in the Keychain.
    static func exists(key: String) -> Bool {
        if AppPaths.isRunningTests {
            return testStore.read(key: key) != nil
        }

        var query = baseQuery(for: key)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// XCTest workers must not read, create, update or delete items in the
    /// developer's login Keychain. A process-local store keeps the same
    /// save/read/exists/delete contract without calling Security.framework.
    private final class InMemoryTestStore: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: String] = [:]

        func save(key: String, value: String) {
            lock.lock()
            defer { lock.unlock() }
            values[key] = value
        }

        func read(key: String) -> String? {
            lock.lock()
            defer { lock.unlock() }
            return values[key]
        }

        func delete(key: String) {
            lock.lock()
            defer { lock.unlock() }
            values.removeValue(forKey: key)
        }
    }
}
