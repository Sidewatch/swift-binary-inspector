//
//  BinaryDiff+Summary.swift
//  BinaryInspector
//
//  The words for a diff result — a status line and a per-run hex preview — kept out of
//  the views that show them.
//
//  Created by David Sherlock on 9/5/26.
//

import Foundation
import DataConverter

extension BinaryDiff.Result {
    /// One status line: `b.bin: identical.`, or the parts that apply joined by ` · ` —
    /// `3 runs, 17 bytes differ`, `b.bin is 2.0 KB longer` (naming whichever file is
    /// longer), `list capped — more differences follow`.
    public func summary(filename: String, compareName: String) -> String {
        if identical { return "\(compareName): identical." }
        var parts: [String] = []
        if !runs.isEmpty {
            parts.append("\(runs.count.grouped) run\(runs.count == 1 ? "" : "s"), "
                         + "\(differingBytes.grouped) byte\(differingBytes == 1 ? "" : "s") differ")
        }
        if lengthDelta != 0 {
            let longer = lengthDelta > 0 ? compareName : filename
            parts.append("\(longer) is \(abs(lengthDelta).byteSizeLabel) longer")
        }
        if truncated { parts.append("list capped — more differences follow") }
        return "\(compareName): " + parts.joined(separator: " · ")
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
