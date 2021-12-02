//
//  FileManager+TempDirectory.swift
//  FYVideoCompressor
//
//  Created by xiaoyang on 2021/1/20.
//

import Foundation

extension FileManager {
    public enum CreateTempDirectoryError: Error, LocalizedError {
        case fileExsisted

        public var errorDescription: String? {
            switch self {
            case .fileExsisted:
                return "File exsisted"
            }
        }
    }
    /// Get temp directory. If it exsists, return it, else create it.
    /// - Parameter pathComponent: path to append to temp directory.
    /// - Throws: error when create temp directory.
    /// - Returns: temp directory location.
    /// - Warning: Every time you call this function will return a different directory or throw an error.
    public static func tempDirectory(with pathComponent: String = ProcessInfo.processInfo.globallyUniqueString) throws -> URL {
        var tempURL: URL

        // Only the volume(卷) of cache url is used.
        let cacheURL = FileManager.default.temporaryDirectory
        if let url = try? FileManager.default.url(for: .itemReplacementDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: cacheURL,
                                                     create: true) {
            tempURL = url
        } else {
            tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
        }

        tempURL.appendPathComponent(pathComponent)

        if !FileManager.default.fileExists(atPath: tempURL.absoluteString) {
            do {
                try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true, attributes: nil)
                #if DEBUG
                print("temp directory path\(tempURL)")
                #endif
                return tempURL
            } catch {
                throw error
            }
        } else {
            #if DEBUG
            print("temp directory path\(tempURL)")
            #endif
            return tempURL
        }
    }
}
