//
//  KeychainManager.swift
//  GoveeBar
//
//  Created by Rohit Manivel on 10/28/25.
//

import Foundation
import Security
import os.log

struct KeychainHelper {

    private static let service = "com.rohitmanivel.GoveeBar"
    private static let logger = Logger(subsystem: service, category: "Keychain")

    enum KeychainError: Error {
        case dataConversionFailed
        case unhandledStatus(OSStatus)
    }

    @discardableResult
    static func save(_ value: String, for key: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            logger.error("Failed to convert value to data")
            return false
        }

        let query: [String: Any] = baseQuery(for: key)

        let updateData = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, updateData as CFDictionary)

        if status == errSecItemNotFound {
            // Add if missing
            var newItem = query
            newItem[kSecValueData as String] = data
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            if addStatus != errSecSuccess {
                logger.error("Failed to add item: \(addStatus)")
                return false
            }
            logger.debug("Key saved successfully")
            return true
        } else if status != errSecSuccess {
            logger.error("Failed to update item: \(status)")
            return false
        }

        logger.debug("Key updated successfully")
        return true
    }

    static func get(_ key: String) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess,
           let data = result as? Data,
           let string = String(data: data, encoding: .utf8) {
            logger.debug("Key retrieved successfully")
            return string
        }

        if status != errSecItemNotFound {
            logger.error("Get failed: \(status)")
        }
        return nil
    }

    @discardableResult
    static func delete(_ key: String) -> Bool {
        let query = baseQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Delete failed: \(status)")
            return false
        }

        logger.debug("Key deleted successfully")
        return true
    }

    private static func baseQuery(for key: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
    }
}
