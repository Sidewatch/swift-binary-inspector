//
//  BinaryBuffer.swift
//  SwiftBinaryInspect
//
//  A piece-table byte buffer: insert, delete and overwrite at arbitrary offsets without
//  copying the file, with undo/redo. The one MUTABLE type in this package.
//
//  Created by David Sherlock on 8/4/26.
//

import Foundation

/// An editable view over a blob, backed by a piece table.
///
/// Everything else in `BinaryInspect` is read-only and never touches its input. This type
/// is the deliberate exception, and it still never mutates the `Data` it was handed: the
/// original stays immutable, inserted bytes accumulate in a separate append-only buffer,
/// and the document is described by an ordered list of pieces pointing into one or the
/// other. Editing rearranges that small list, so an insert near the start of a 500 MB file
/// costs a couple of array operations rather than a 500 MB memmove.
///
/// **The invariant that makes undo cheap:** `added` is append-only — bytes are never
/// removed from it, even when the edit that introduced them is undone. A snapshot of the
/// piece list is therefore sufficient to restore any prior state exactly, with no byte
/// copying. The cost is that `added` grows with edit history rather than with live content;
/// ``compacted()`` rebuilds a fresh buffer when that matters.
public struct BinaryBuffer: Sendable {

    /// Which backing store a piece points into.
    enum Source: Equatable, Sendable { case original, added }

    /// A contiguous span of one backing store.
    struct Piece: Equatable, Sendable {
        let source: Source
        /// Start offset within the backing store (NOT within the document).
        let start: Int
        let length: Int
    }

    /// Enough to restore a prior document state. Cheap because `added` is append-only.
    private struct Snapshot: Sendable {
        let pieces: [Piece]
        let count: Int
    }

    private let original: Data
    private var added: [UInt8] = []
    private var pieces: [Piece]
    /// The state ``isModified`` compares against — the bytes as last written to disk.
    /// Starts as the initial content and moves forward on ``markSaved()``.
    private var savedPieces: [Piece]

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    /// Maximum retained undo steps. Older steps are dropped from the bottom.
    public var undoLimit: Int = 500

    /// Current document length in bytes.
    public private(set) var count: Int

    /// Wrap `data` for editing. The `Data` is retained but never modified.
    public init(_ data: Data) {
        self.original = data
        let initial = data.isEmpty ? [] : [Piece(source: .original, start: 0, length: data.count)]
        self.pieces = initial
        self.savedPieces = initial
        self.count = data.count
    }

    // MARK: - State

    /// True when the document differs from the last saved bytes. Undoing back to that state
    /// clears it — a comparison, not a one-way flag, so edit-then-undo is not "dirty".
    public var isModified: Bool { pieces != savedPieces }

    /// Adopt the current content as the saved baseline, clearing ``isModified``.
    ///
    /// Deliberately keeps undo history: a save is a checkpoint, not a barrier, and losing
    /// the ability to undo past one is a worse surprise than carrying the history.
    public mutating func markSaved() { savedPieces = pieces }

    public var isEmpty: Bool { count == 0 }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Number of pieces currently describing the document. Diagnostic — a proxy for how
    /// fragmented editing has made the table.
    public var pieceCount: Int { pieces.count }

    // MARK: - Reading

    /// The byte at `offset`, or `nil` when out of range.
    public func byte(at offset: Int) -> UInt8? {
        guard offset >= 0, offset < count else { return nil }
        var pos = 0
        for p in pieces {
            let end = pos + p.length
            if offset < end {
                let inner = p.start + (offset - pos)
                switch p.source {
                case .original: return original[original.startIndex + inner]
                case .added:    return added[inner]
                }
            }
            pos = end
        }
        return nil
    }

    /// The bytes over `range`, clamped to the document. Walks the piece table once.
    public func bytes(in range: Range<Int>) -> [UInt8] {
        let lower = min(max(0, range.lowerBound), count)
        let upper = min(max(lower, range.upperBound), count)
        guard upper > lower else { return [] }

        var out: [UInt8] = []
        out.reserveCapacity(upper - lower)
        var pos = 0
        for p in pieces {
            let end = pos + p.length
            if end <= lower { pos = end; continue }
            if pos >= upper { break }
            let from = max(lower, pos) - pos
            let to = min(upper, end) - pos
            switch p.source {
            case .original:
                let s = original.startIndex + p.start
                out.append(contentsOf: original[(s + from)..<(s + to)])
            case .added:
                out.append(contentsOf: added[(p.start + from)..<(p.start + to)])
            }
            pos = end
        }
        return out
    }

    /// Materialize the whole document. This is the save path — allocates `count` bytes.
    public func data() -> Data {
        var out = Data()
        out.reserveCapacity(count)
        for p in pieces {
            switch p.source {
            case .original:
                let s = original.startIndex + p.start
                out.append(original[s..<(s + p.length)])
            case .added:
                added[p.start..<(p.start + p.length)].withUnsafeBufferPointer { out.append(contentsOf: $0) }
            }
        }
        return out
    }

    /// Hex rows over a window, without materializing the whole document — so a virtualized
    /// hex view keeps costing only what it draws after an edit, exactly as it did before one.
    ///
    /// - Parameters:
    ///   - bytesPerRow: Bytes per row (clamped to at least 1).
    ///   - from: Start offset (clamped into range).
    ///   - length: Bytes to cover (default: to the end).
    public func hexRows(bytesPerRow: Int = 16, from: Int = 0, length: Int? = nil) -> [HexDump.Row] {
        let width = max(1, bytesPerRow)
        let start = min(max(0, from), count)
        let end = min(count, length.map { start + max(0, $0) } ?? count)
        guard start < end else { return [] }

        let window = bytes(in: start..<end)
        var rows: [HexDump.Row] = []
        rows.reserveCapacity((end - start + width - 1) / width)
        var i = 0
        while i < window.count {
            let rowEnd = min(i + width, window.count)
            rows.append(HexDump.Row(offset: UInt64(start + i), bytes: Array(window[i..<rowEnd])))
            i = rowEnd
        }
        return rows
    }

    // MARK: - Editing

    /// Insert bytes at `offset` (clamped to `0...count`), growing the document.
    public mutating func insert(_ newBytes: [UInt8], at offset: Int) {
        guard !newBytes.isEmpty else { return }
        pushUndo()
        _insert(newBytes, at: min(max(0, offset), count))
    }

    /// Delete `range` (clamped), shrinking the document.
    public mutating func remove(_ range: Range<Int>) {
        let lower = min(max(0, range.lowerBound), count)
        let upper = min(max(lower, range.upperBound), count)
        guard upper > lower else { return }
        pushUndo()
        _remove(lower..<upper)
    }

    /// Replace `range` with `newBytes` as ONE undo step. Either side may be empty, so this
    /// is also the general form of insert and delete.
    public mutating func replace(_ range: Range<Int>, with newBytes: [UInt8]) {
        let lower = min(max(0, range.lowerBound), count)
        let upper = min(max(lower, range.upperBound), count)
        guard upper > lower || !newBytes.isEmpty else { return }
        pushUndo()
        if upper > lower { _remove(lower..<upper) }
        if !newBytes.isEmpty { _insert(newBytes, at: lower) }
    }

    /// Overwrite in place at `offset`, replacing the bytes already there. Writing past the
    /// end appends rather than failing, so typing into the final row extends the file the
    /// way a hex editor is expected to.
    public mutating func overwrite(_ newBytes: [UInt8], at offset: Int) {
        guard !newBytes.isEmpty else { return }
        let start = min(max(0, offset), count)
        replace(start..<min(start + newBytes.count, count), with: newBytes)
    }

    // MARK: - Undo / redo

    @discardableResult
    public mutating func undo() -> Bool {
        guard let snapshot = undoStack.popLast() else { return false }
        redoStack.append(Snapshot(pieces: pieces, count: count))
        pieces = snapshot.pieces
        count = snapshot.count
        return true
    }

    @discardableResult
    public mutating func redo() -> Bool {
        guard let snapshot = redoStack.popLast() else { return false }
        undoStack.append(Snapshot(pieces: pieces, count: count))
        pieces = snapshot.pieces
        count = snapshot.count
        return true
    }

    /// Drop all history, keeping the current content. Use after a save, when the prior
    /// states are no longer reachable anyway.
    public mutating func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    /// A fresh buffer over the current content, with no history and a single piece —
    /// releasing the original blob and the accumulated add-buffer. Worth doing after a save
    /// of a heavily-edited large file.
    public func compacted() -> BinaryBuffer { BinaryBuffer(data()) }

    // MARK: - Internals

    private mutating func pushUndo() {
        undoStack.append(Snapshot(pieces: pieces, count: count))
        if undoStack.count > undoLimit { undoStack.removeFirst(undoStack.count - undoLimit) }
        redoStack.removeAll()   // a new edit invalidates the redo branch
    }

    /// Insert without touching the undo stack — the shared body of the public mutators.
    private mutating func _insert(_ newBytes: [UInt8], at offset: Int) {
        let index = splitBoundary(at: offset)
        let start = added.count
        added.append(contentsOf: newBytes)
        pieces.insert(Piece(source: .added, start: start, length: newBytes.count), at: index)
        count += newBytes.count
    }

    /// Delete without touching the undo stack. `range` must already be clamped and non-empty.
    private mutating func _remove(_ range: Range<Int>) {
        // Split the low edge first; `splitBoundary` re-walks from the start, so the second
        // call still returns an index valid for the array as it stands after the first.
        let startIndex = splitBoundary(at: range.lowerBound)
        let endIndex = splitBoundary(at: range.upperBound)
        pieces.removeSubrange(startIndex..<endIndex)
        count -= range.count
    }

    /// Ensure `offset` falls on a piece boundary, splitting the straddling piece if needed.
    ///
    /// - Returns: Index of the piece that now STARTS at `offset` (`pieces.count` when
    ///   `offset == count`), so it can be used directly as an insertion point.
    private mutating func splitBoundary(at offset: Int) -> Int {
        if offset <= 0 { return 0 }
        if offset >= count { return pieces.count }

        var remaining = offset
        for (i, p) in pieces.enumerated() {
            if remaining == 0 { return i }
            if remaining < p.length {
                let left = Piece(source: p.source, start: p.start, length: remaining)
                let right = Piece(source: p.source, start: p.start + remaining, length: p.length - remaining)
                pieces[i] = left
                pieces.insert(right, at: i + 1)
                return i + 1
            }
            remaining -= p.length
        }
        return pieces.count
    }
}
