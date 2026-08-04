//
//  BinaryDiff.swift
//  SwiftBinaryInspect
//
//  Offset-aligned byte comparison of two blobs — the "these two presets differ by one
//  knob, show me where" instrument.
//
//  Created by David Sherlock on 8/4/26.
//

import Foundation

/// Compares two blobs **offset for offset** and reports maximal runs of differing bytes.
///
/// This is deliberately *not* a resyncing diff. A text diff hunts for matching regions so
/// an insertion doesn't cascade; over binary data that heuristic reliably invents
/// alignments that aren't real — a run of `0x00` matches everything. The case this exists
/// for is two same-shaped records that differ in a few fields (two synth presets saved
/// either side of one parameter change), where offset-for-offset *is* the truth and any
/// resync would obscure it.
///
/// Files of unequal length are compared over their common prefix; the tail is reported
/// separately via ``Result/lengthDelta`` rather than being folded into a run, so a caller
/// can never mistake "this file is longer" for "these bytes changed".
public enum BinaryDiff {

    /// A maximal span of consecutive differing bytes within the compared prefix.
    public struct Run: Equatable, Sendable {
        /// Offset of the first differing byte.
        public let offset: Int
        /// How many consecutive bytes differ.
        public let length: Int

        public init(offset: Int, length: Int) {
            self.offset = offset
            self.length = length
        }

        /// One past the last differing byte.
        public var end: Int { offset + length }
        /// The half-open range this run covers.
        public var range: Range<Int> { offset..<end }
    }

    /// The outcome of a comparison.
    public struct Result: Equatable, Sendable {
        /// Maximal differing runs over `0..<comparedLength`, in ascending offset order.
        public let runs: [Run]
        /// Total differing bytes within the compared prefix (sum of the run lengths).
        public let differingBytes: Int
        /// How many bytes were compared — `min(a.count, b.count)`.
        public let comparedLength: Int
        /// `b.count - a.count`. Non-zero means one side has a tail the other lacks; those
        /// trailing bytes are NOT represented in `runs`.
        public let lengthDelta: Int
        /// True when `runs` was truncated by the `maxRuns` cap — there are more differences
        /// past the last reported run. A caller must surface this rather than implying the
        /// list is complete.
        public let truncated: Bool

        /// True when both blobs are byte-for-byte equal, including length.
        public var identical: Bool { runs.isEmpty && lengthDelta == 0 }

        /// Offset of the first differing byte, or `nil` when the compared prefix matches.
        public var firstDifference: Int? { runs.first?.offset }
    }

    /// Compare two blobs offset for offset.
    ///
    /// - Parameters:
    ///   - a: The left/original blob.
    ///   - b: The right/changed blob.
    ///   - maxRuns: Stop after this many runs, setting ``Result/truncated``. `nil` (default)
    ///     reports every run. A cap keeps a pathological pair (two unrelated multi-megabyte
    ///     files, where nearly every byte differs) from building a vast array a UI can't use.
    /// - Returns: The differing runs plus the length relationship.
    public static func compare(_ a: Data, _ b: Data, maxRuns: Int? = nil) -> Result {
        let common = min(a.count, b.count)
        let aBase = a.startIndex, bBase = b.startIndex
        var runs: [Run] = []
        var differing = 0
        var truncated = false

        var i = 0
        while i < common {
            // Skip equal bytes.
            while i < common, a[aBase + i] == b[bBase + i] { i += 1 }
            guard i < common else { break }
            // Consume the differing run.
            let start = i
            while i < common, a[aBase + i] != b[bBase + i] { i += 1 }
            runs.append(Run(offset: start, length: i - start))
            differing += i - start
            if let cap = maxRuns, runs.count >= cap {
                // Only truthfully "truncated" if something actually differs past here.
                truncated = firstDifference(a, b, from: i, upTo: common) != nil
                break
            }
        }

        return Result(runs: runs,
                      differingBytes: differing,
                      comparedLength: common,
                      lengthDelta: b.count - a.count,
                      truncated: truncated)
    }

    /// Offset of the first differing byte at or after `from`, within the common prefix.
    /// Cheaper than a full ``compare(_:_:maxRuns:)`` when a caller only needs "do these
    /// differ, and where first?" — used to answer the truncation question honestly.
    ///
    /// - Returns: The offset, or `nil` when the window is byte-identical.
    public static func firstDifference(_ a: Data, _ b: Data, from: Int = 0, upTo: Int? = nil) -> Int? {
        let common = min(upTo ?? min(a.count, b.count), min(a.count, b.count))
        let aBase = a.startIndex, bBase = b.startIndex
        var i = max(0, from)
        while i < common {
            if a[aBase + i] != b[bBase + i] { return i }
            i += 1
        }
        return nil
    }

    /// True when the byte at `offset` differs between the two blobs. An offset past the end
    /// of one blob but not the other counts as differing; past both, it does not.
    ///
    /// Intended for per-cell tinting in a hex view, where the caller already holds a
    /// ``Result`` for the summary but wants a cheap per-byte answer while drawing.
    public static func differs(_ a: Data, _ b: Data, at offset: Int) -> Bool {
        guard offset >= 0 else { return false }
        let inA = offset < a.count, inB = offset < b.count
        guard inA || inB else { return false }
        guard inA, inB else { return true }
        return a[a.startIndex + offset] != b[b.startIndex + offset]
    }
}
