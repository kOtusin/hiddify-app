//
//  FilePath.swift
//  SingBoxPacketTunnel
//
//  Created by GFWFighter on 7/25/1402 AP.
//

import Foundation

public enum FilePath {
    public static let packageName = {
        Bundle.main.infoDictionary?["BASE_BUNDLE_IDENTIFIER"] as? String ?? "unknown"
    }()
}

public extension FilePath {
    static let groupName = "group.\(packageName)"

    private static let defaultSharedDirectory: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: FilePath.groupName)

    static let sharedDirectory: URL = {
        if let defaultSharedDirectory {
            return defaultSharedDirectory
        }
        // Keep the app usable (and able to show an error) even when the
        // application-group entitlement is not available.
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }()

    static let cacheDirectory = sharedDirectory
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Caches", isDirectory: true)

    static let workingDirectory = cacheDirectory.appendingPathComponent("Working", isDirectory: true)
}

public extension URL {
    var fileName: String {
        var path = relativePath
        if let index = path.lastIndex(of: "/") {
            path = String(path[path.index(index, offsetBy: 1)...])
        }
        return path
    }
}
