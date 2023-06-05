//
//  File.swift
//  
//
//  Created by xiaoyang on 2023/6/5.
//

import Foundation

extension FourCharCode {
    internal func toString() -> String {
        let result = String(format: "%c%c%c%c",
                            (self >> 24) & 0xff,
                            (self >> 16) & 0xff,
                            (self >> 8) & 0xff,
                            self & 0xff)
        let characterSet = CharacterSet.whitespaces
        return result.trimmingCharacters(in: characterSet)
    }
}

