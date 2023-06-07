//
//  URL+FileSize.swift
//  FYVideoCompressor
//
//  Created by xiaoyang on 2021/12/02.
//

import Foundation

extension URL {
    /// File url video memory footprint.
    /// Remote url will return 0.
    /// - Returns: memory size
    func sizePerMB() -> Double {
        guard isFileURL else { return 0 }
        do {
            let attribute = try FileManager.default.attributesOfItem(atPath: path)
            if let size = attribute[FileAttributeKey.size] as? NSNumber {
                return size.doubleValue / (1024 * 1024)
            }
        } catch {
            print("Error: \(error)")
        }
        return 0.0
    }
}
