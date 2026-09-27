//
//  BinaryDiff+Summary.swift
//  BinaryInspector
//
//  The words for a diff result — a status line and a per-run hex preview — kept out of
//  the views that show them.
//
//  Created by David Sherlock on 9/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

extension BinaryDiff.Result {
    /// One status line: `b.bin: identical.`, or the parts that apply joined by ` · ` —
    /// `3 runs, 17 bytes differ`, `b.bin is 2.0 KB longer` (naming whichever file is
    /// longer), `list capped — more differences follow`.
    public func summary(filename: String, compareName: String) -> String {
        if identical {
            return String(localized: "\(compareName): identical.", bundle: .module,
                          comment: "Binary compare status: the named comparison file has the same bytes.")
        }
        var parts: [String] = []
        if !runs.isEmpty {
            parts.append(String(localized: "\(runs.count) runs, \(differingBytes) bytes differ", bundle: .module,
                                comment: "Binary compare status: how many stretches of bytes differ, and how many bytes in total."))
        }
        if lengthDelta != 0 {
            let longer = lengthDelta > 0 ? compareName : filename
            parts.append(String(localized: "\(longer) is \(abs(lengthDelta).byteSizeLabel) longer", bundle: .module,
                                comment: "Binary compare status: file name, then a size such as 2.0 KB."))
        }
        if truncated {
            parts.append(String(localized: "list capped — more differences follow", bundle: .module,
                                comment: "Binary compare status: the list of differences stopped at its limit."))
        }
        return String(localized: "\(compareName): \(parts.joined(separator: " · "))", bundle: .module,
                      comment: "Binary compare status: the comparison file name, then its findings joined by ·.")
    }
}

extension BinaryDiff.Run {
    /// `"a1 b2  →  c3 d4"`: this file's bytes at the run and the comparison's, at most
    /// `showing` of each with an ellipsis when the run is longer, `—` for a side that has
    /// no bytes there, and empty when there is nothing to compare against.
    public func preview(in data: Data, against other: Data?, showing: Int = 8) -> String {
        guard let other else { return "" }
        let shown = min(length, showing)
        func hex(_ d: Data) -> String {
            let start = d.startIndex + offset
            let end = min(d.startIndex + offset + shown, d.endIndex)
            guard start < end else { return "—" }
            return d[start..<end].map { String(format: "%02x", $0) }.joined(separator: " ")
        }
        let ellipsis = length > shown ? "…" : ""
        return "\(hex(data))\(ellipsis)  →  \(hex(other))\(ellipsis)"
    }
}
