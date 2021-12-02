//
//  AVFileType.swift
//  
//
//  Created by xiaoyang on 2021/11/11.
//

import Foundation
import AVFoundation
#if !os(macOS)
import MobileCoreServices
#endif

extension AVFileType {
    /// Fetch and extension for a file from UTI string
    var fileExtension: String {
        if #available(iOS 14.0, macOS 11.0, *) {
            if let utType = UTType(self.rawValue) {
                print("utType.preferredMIMEType: \(String(describing: utType.preferredMIMEType))")
                return utType.preferredFilenameExtension ?? "None"
            }
            return "None"
        } else {
            if let ext = UTTypeCopyPreferredTagWithClass(self as CFString,
                                                         kUTTagClassFilenameExtension)?.takeRetainedValue() {
                return ext as String
            }
            return "None"
        }
    }
}
