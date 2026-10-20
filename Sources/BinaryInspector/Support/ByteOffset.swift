//
//  ByteOffset.swift
//  BinaryInspector
//
//  A byte offset typed by a person: hex with or without a leading 0x.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A byte offset typed into a Go to Offset field.
public enum ByteOffset {
    /// The offset `text` names, read as hexadecimal: `1f40`, `0x1F40` or `0X1f40`, spaces around it
    /// ignored. Only a LEADING `0x` is a prefix — `10x0` is not hex and gives nil, never 0x10. Nil for
    /// empty, negative, non-hex or overflowing input.
    public static func parse(_ text: String) -> Int? {
        var digits = Substring(text.trimmingCharacters(in: .whitespaces))
        if digits.lowercased().hasPrefix("0x") { digits = digits.dropFirst(2) }
        guard !digits.isEmpty, digits.allSatisfy(\.isHexDigit) else { return nil }
        return Int(digits, radix: 16)
    }
}
