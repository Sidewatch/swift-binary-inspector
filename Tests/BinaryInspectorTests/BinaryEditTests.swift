//
//  BinaryEditTests.swift
//  Tests for SwiftBinaryInspect — BinaryValues, BinaryDiff, BinaryBuffer
//
//  Created by David Sherlock on 8/4/26.
//

import XCTest
@testable import BinaryInspector

final class BinaryEditTests: XCTestCase {

    // MARK: - BinaryValues

    func testValuesLittleEndianIntegers() {
        // 0x01 0x02 0x03 0x04 → LE UInt32 0x04030201
        let d = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        XCTAssertEqual(BinaryValues.uint8(d, 0), 0x01)
        XCTAssertEqual(BinaryValues.uint16(d, 0, false), 0x0201)
        XCTAssertEqual(BinaryValues.uint32(d, 0, false), 0x04030201)
        XCTAssertEqual(BinaryValues.uint64(d, 0, false), 0x0807060504030201)
    }

    func testValuesBigEndianIntegers() {
        let d = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        XCTAssertEqual(BinaryValues.uint16(d, 0, true), 0x0102)
        XCTAssertEqual(BinaryValues.uint32(d, 0, true), 0x01020304)
        XCTAssertEqual(BinaryValues.uint64(d, 0, true), 0x0102030405060708)
    }

    func testValuesSignedInterpretation() {
        let d = Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertEqual(BinaryValues.int8(d, 0), -1)
        XCTAssertEqual(BinaryValues.int16(d, 0, false), -1)
        XCTAssertEqual(BinaryValues.int32(d, 0, false), -1)
        XCTAssertEqual(BinaryValues.int64(d, 0, false), -1)
        XCTAssertEqual(BinaryValues.uint8(d, 0), 255)
    }

    /// Every float the panel shows must be exactly what Swift would decode from those
    /// bytes — the panel is only useful if it is bit-accurate.
    func testValuesFloatsRoundTripAgainstBitPattern() {
        for sample: Float in [0, 1, -1, 0.5, -0.7071068, .pi, 3.4e38, 1.2e-38] {
            var le = sample.bitPattern.littleEndian
            let d = Data(bytes: &le, count: 4)
            XCTAssertEqual(BinaryValues.float32(d, 0, false), sample, "float32 \(sample)")
        }
        for sample: Double in [0, 1, -1, 0.5, .pi, 1.7e308, 2.2e-308] {
            var le = sample.bitPattern.littleEndian
            let d = Data(bytes: &le, count: 8)
            XCTAssertEqual(BinaryValues.float64(d, 0, false), sample, "float64 \(sample)")
        }
    }

    func testValuesOutOfRangeKeepsRowSetStable() {
        let d = Data([0x41, 0x42])                       // only 2 bytes
        let rows = BinaryValues.decode(d, at: 0)
        // Row set is fixed regardless of how little data is left.
        XCTAssertEqual(rows.count, 11)
        XCTAssertEqual(rows.first { $0.type == "UInt8" }?.text, "65")
        XCTAssertEqual(rows.first { $0.type == "UInt16" }?.inRange, true)
        // 4- and 8-byte types cannot fit in 2 bytes.
        XCTAssertEqual(rows.first { $0.type == "UInt32" }?.inRange, false)
        XCTAssertEqual(rows.first { $0.type == "UInt32" }?.text, BinaryValues.outOfRange)
        XCTAssertEqual(rows.first { $0.type == "Float64" }?.inRange, false)
    }

    func testValuesOffsetPastEndIsAllPlaceholder() {
        let d = Data([0x41, 0x42])
        let rows = BinaryValues.decode(d, at: 99)
        XCTAssertTrue(rows.allSatisfy { !$0.inRange && $0.text == BinaryValues.outOfRange })
    }

    func testValuesNaNAndInfinityAreNamed() {
        XCTAssertEqual(BinaryValues.floatText(.nan), "NaN")
        XCTAssertEqual(BinaryValues.doubleText(.nan), "NaN")
        XCTAssertEqual(BinaryValues.floatText(.infinity), "Infinity")
        XCTAssertEqual(BinaryValues.floatText(-.infinity), "-Infinity")
        XCTAssertEqual(BinaryValues.doubleText(.infinity), "Infinity")
    }

    /// Regression: round numbers were rendered in scientific notation, and Float32 values
    /// were widened to Double before formatting so they printed conversion noise.
    func testValuesFloatFormattingIsReadable() {
        XCTAssertEqual(BinaryValues.doubleText(100), "100.0", "round numbers must not go scientific")
        XCTAssertEqual(BinaryValues.doubleText(0.5), "0.5")
        XCTAssertEqual(BinaryValues.doubleText(-1), "-1.0")

        // 0.1 as a Float is not 0.1 as a Double. Formatting at Float precision must show
        // "0.1", not the nine-digit Double view of the same bits.
        XCTAssertEqual(BinaryValues.floatText(0.1), "0.1")
        XCTAssertEqual(BinaryValues.floatText(100), "100.0")
        XCTAssertFalse(BinaryValues.floatText(0.1).contains("0000"), "no double-precision noise")

        // Every rendering must still round-trip to the same value.
        for sample: Float in [0, 1, -1, 0.1, 0.5, 100, 1e-8, 3.4e38] {
            XCTAssertEqual(Float(BinaryValues.floatText(sample)), sample, "round-trip \(sample)")
        }
        for sample: Double in [0, 1, -1, 0.1, 100, 1e-300, 1.7e308] {
            XCTAssertEqual(Double(BinaryValues.doubleText(sample)), sample, "round-trip \(sample)")
        }
    }

    func testValuesASCIIRow() {
        XCTAssertEqual(BinaryValues.decode(Data([0x41]), at: 0).first { $0.type == "ASCII" }?.text, "A")
        // Control byte renders as the dump's placeholder, not as a raw control character.
        XCTAssertEqual(BinaryValues.decode(Data([0x01]), at: 0).first { $0.type == "ASCII" }?.text, ".")
    }

    // MARK: - BinaryDiff

    func testDiffIdentical() {
        let d = Data((0..<64).map { UInt8($0) })
        let r = BinaryDiff.compare(d, d)
        XCTAssertTrue(r.identical)
        XCTAssertTrue(r.runs.isEmpty)
        XCTAssertEqual(r.differingBytes, 0)
        XCTAssertNil(r.firstDifference)
    }

    func testDiffSingleByte() {
        var a = Data(repeating: 0, count: 32)
        var b = a
        b[10] = 0xFF
        let r = BinaryDiff.compare(a, b)
        XCTAssertEqual(r.runs, [BinaryDiff.Run(offset: 10, length: 1)])
        XCTAssertEqual(r.differingBytes, 1)
        XCTAssertEqual(r.firstDifference, 10)
        XCTAssertFalse(r.identical)
        a[10] = 0xFF                                     // converge → identical
        XCTAssertTrue(BinaryDiff.compare(a, b).identical)
    }

    func testDiffMergesConsecutiveIntoOneRun() {
        var a = Data(repeating: 0, count: 32)
        var b = a
        for i in 5..<9 { b[i] = 0xAA }
        a[20] = 1; b[20] = 2                             // a second, separate run
        let r = BinaryDiff.compare(a, b)
        XCTAssertEqual(r.runs, [BinaryDiff.Run(offset: 5, length: 4),
                                BinaryDiff.Run(offset: 20, length: 1)])
        XCTAssertEqual(r.differingBytes, 5)
        XCTAssertEqual(r.runs[0].end, 9)
        XCTAssertEqual(r.runs[0].range, 5..<9)
    }

    /// A longer file must not report its tail as "changed bytes" — that is a different
    /// fact, and conflating them is exactly what makes binary diffs untrustworthy.
    func testDiffUnequalLengthsReportTailSeparately() {
        let a = Data(repeating: 0x11, count: 16)
        let b = Data(repeating: 0x11, count: 24)
        let r = BinaryDiff.compare(a, b)
        XCTAssertTrue(r.runs.isEmpty)                    // common prefix matches
        XCTAssertEqual(r.comparedLength, 16)
        XCTAssertEqual(r.lengthDelta, 8)
        XCTAssertFalse(r.identical)                      // still not the same file
    }

    func testDiffTruncationIsHonest() {
        var a = Data(repeating: 0, count: 100)
        var b = a
        for i in stride(from: 0, to: 100, by: 10) { b[i] = 0xFF }   // 10 separate runs
        let capped = BinaryDiff.compare(a, b, maxRuns: 3)
        XCTAssertEqual(capped.runs.count, 3)
        XCTAssertTrue(capped.truncated)

        // A cap that happens to equal the real run count must NOT claim truncation.
        a = Data(repeating: 0, count: 10)
        b = a
        b[0] = 1
        let exact = BinaryDiff.compare(a, b, maxRuns: 1)
        XCTAssertEqual(exact.runs.count, 1)
        XCTAssertFalse(exact.truncated, "cap met exactly, nothing beyond — must not report truncated")
    }

    func testDiffPerByteHelper() {
        let a = Data([1, 2, 3])
        let b = Data([1, 9, 3, 4])
        XCTAssertFalse(BinaryDiff.differs(a, b, at: 0))
        XCTAssertTrue(BinaryDiff.differs(a, b, at: 1))
        XCTAssertTrue(BinaryDiff.differs(a, b, at: 3), "past a's end but inside b → differs")
        XCTAssertFalse(BinaryDiff.differs(a, b, at: 99), "past both ends → not a difference")
    }

    func testDiffEmptyInputs() {
        XCTAssertTrue(BinaryDiff.compare(Data(), Data()).identical)
        let r = BinaryDiff.compare(Data(), Data([1, 2]))
        XCTAssertTrue(r.runs.isEmpty)
        XCTAssertEqual(r.lengthDelta, 2)
        XCTAssertFalse(r.identical)
    }

    // MARK: - BinaryBuffer basics

    func testBufferStartsUnmodified() {
        let b = BinaryBuffer(Data([1, 2, 3]))
        XCTAssertEqual(b.count, 3)
        XCTAssertFalse(b.isModified)
        XCTAssertFalse(b.canUndo)
        XCTAssertEqual(b.data(), Data([1, 2, 3]))
    }

    func testBufferInsertMiddleStartEnd() {
        var b = BinaryBuffer(Data([1, 2, 3]))
        b.insert([9], at: 1)
        XCTAssertEqual(b.data(), Data([1, 9, 2, 3]))
        b.insert([0], at: 0)
        XCTAssertEqual(b.data(), Data([0, 1, 9, 2, 3]))
        b.insert([7], at: b.count)                       // append
        XCTAssertEqual(b.data(), Data([0, 1, 9, 2, 3, 7]))
        XCTAssertTrue(b.isModified)
    }

    func testBufferRemove() {
        var b = BinaryBuffer(Data([0, 1, 2, 3, 4, 5]))
        b.remove(2..<4)
        XCTAssertEqual(b.data(), Data([0, 1, 4, 5]))
        XCTAssertEqual(b.count, 4)
    }

    func testBufferOverwriteInPlaceAndPastEnd() {
        var b = BinaryBuffer(Data([1, 2, 3, 4]))
        b.overwrite([0xAA, 0xBB], at: 1)
        XCTAssertEqual(b.data(), Data([1, 0xAA, 0xBB, 4]))
        XCTAssertEqual(b.count, 4, "in-place overwrite must not change length")

        // Overwriting across the end extends, rather than failing or truncating.
        b.overwrite([0xCC, 0xDD], at: 3)
        XCTAssertEqual(b.data(), Data([1, 0xAA, 0xBB, 0xCC, 0xDD]))
        XCTAssertEqual(b.count, 5)
    }

    func testBufferReplaceIsOneUndoStep() {
        var b = BinaryBuffer(Data([1, 2, 3, 4]))
        b.replace(1..<3, with: [9, 9, 9])
        XCTAssertEqual(b.data(), Data([1, 9, 9, 9, 4]))
        XCTAssertTrue(b.undo())
        XCTAssertEqual(b.data(), Data([1, 2, 3, 4]), "replace must undo in a single step")
        XCTAssertFalse(b.canUndo)
    }

    func testBufferUndoRedoAndModifiedFlag() {
        var b = BinaryBuffer(Data([1, 2, 3]))
        b.insert([4], at: 3)
        XCTAssertTrue(b.isModified)
        XCTAssertTrue(b.undo())
        XCTAssertFalse(b.isModified, "undo back to the original must clear isModified")
        XCTAssertEqual(b.data(), Data([1, 2, 3]))
        XCTAssertTrue(b.canRedo)
        XCTAssertTrue(b.redo())
        XCTAssertEqual(b.data(), Data([1, 2, 3, 4]))
        XCTAssertTrue(b.isModified)
    }

    func testBufferMarkSavedRebaselinesButKeepsHistory() {
        var b = BinaryBuffer(Data([1, 2, 3]))
        b.insert([4], at: 3)
        XCTAssertTrue(b.isModified)

        b.markSaved()
        XCTAssertFalse(b.isModified, "saving must clear the dirty flag")
        XCTAssertTrue(b.canUndo, "a save is a checkpoint, not an undo barrier")

        // Undoing back PAST the save makes it dirty again — the content no longer matches disk.
        XCTAssertTrue(b.undo())
        XCTAssertEqual(b.data(), Data([1, 2, 3]))
        XCTAssertTrue(b.isModified, "undoing past a save differs from the saved bytes")

        // Redoing back to the saved state is clean again.
        XCTAssertTrue(b.redo())
        XCTAssertFalse(b.isModified)
    }

    func testBufferNewEditClearsRedoBranch() {
        var b = BinaryBuffer(Data([1, 2, 3]))
        b.insert([4], at: 3)
        b.undo()
        XCTAssertTrue(b.canRedo)
        b.insert([5], at: 0)
        XCTAssertFalse(b.canRedo, "a fresh edit must invalidate the redo branch")
    }

    func testBufferNoOpEditsDoNotPushUndo() {
        var b = BinaryBuffer(Data([1, 2, 3]))
        b.insert([], at: 0)
        b.remove(2..<2)
        b.overwrite([], at: 0)
        XCTAssertFalse(b.canUndo, "empty edits must not create undo steps")
        XCTAssertFalse(b.isModified)
    }

    func testBufferClampsOutOfRangeOffsets() {
        var b = BinaryBuffer(Data([1, 2, 3]))
        b.insert([9], at: 999)                           // clamps to end
        XCTAssertEqual(b.data(), Data([1, 2, 3, 9]))
        b.remove(-5..<1)                                 // clamps to 0..<1
        XCTAssertEqual(b.data(), Data([2, 3, 9]))
        b.remove(100..<200)                              // entirely past end → no-op
        XCTAssertEqual(b.data(), Data([2, 3, 9]))
    }

    func testBufferByteAndBytesAccessors() {
        var b = BinaryBuffer(Data((0..<10).map { UInt8($0) }))
        b.insert([0xFF], at: 5)
        XCTAssertEqual(b.byte(at: 5), 0xFF)
        XCTAssertEqual(b.byte(at: 6), 5)
        XCTAssertNil(b.byte(at: b.count))
        XCTAssertNil(b.byte(at: -1))
        XCTAssertEqual(b.bytes(in: 4..<8), [4, 0xFF, 5, 6])
        XCTAssertEqual(b.bytes(in: 0..<b.count), Array(b.data()))
        XCTAssertEqual(b.bytes(in: 5..<5), [])
    }

    /// The virtualized hex view reads windows, so windowed reads must agree with the whole
    /// document after editing has fragmented the piece table.
    func testBufferHexRowsMatchFullDataAfterEdits() {
        var b = BinaryBuffer(Data((0..<100).map { UInt8($0) }))
        b.insert([0xAA, 0xBB], at: 33)
        b.remove(10..<12)
        b.overwrite([0xCC], at: 50)

        let full = Array(b.data())
        let rows = b.hexRows(bytesPerRow: 16)
        XCTAssertEqual(rows.flatMap(\.bytes), full)
        XCTAssertEqual(rows.first?.offset, 0)

        let window = b.hexRows(bytesPerRow: 8, from: 24, length: 16)
        XCTAssertEqual(window.count, 2)
        XCTAssertEqual(window[0].offset, 24)
        XCTAssertEqual(window.flatMap(\.bytes), Array(full[24..<40]))
    }

    func testBufferCompactedPreservesContentAndDropsHistory() {
        var b = BinaryBuffer(Data([1, 2, 3]))
        b.insert([9], at: 1)
        let c = b.compacted()
        XCTAssertEqual(c.data(), b.data())
        XCTAssertFalse(c.canUndo)
        XCTAssertFalse(c.isModified, "a compacted buffer's content IS its new baseline")
        XCTAssertEqual(c.pieceCount, 1)
    }

    // MARK: - Differential fuzz against a naive reference

    /// The real test: drive the piece table and a plain `[UInt8]` through the SAME random
    /// edit sequence and require byte-identical agreement at every step, then undo the whole
    /// history and require an exact return to the original bytes.
    ///
    /// A piece table's failure mode is a wrong split index, which only shows up on a
    /// particular overlap of edits — the kind of case hand-written examples miss. Seeded so
    /// a failure is reproducible.
    func testBufferDifferentialFuzzAgainstReference() {
        for seed in UInt64(1)...40 {
            var rng = SeededRNG(seed: seed)
            let originalBytes = (0..<200).map { _ in UInt8.random(in: 0...255, using: &rng) }
            let original = Data(originalBytes)

            var buffer = BinaryBuffer(original)
            var reference = originalBytes
            var states: [[UInt8]] = [reference]

            for step in 0..<60 {
                // An empty reference can only be grown, so force an insert in that case.
                let op = reference.isEmpty ? 0 : Int.random(in: 0..<3, using: &rng)
                if op == 0 {
                    let at = Int.random(in: 0...reference.count, using: &rng)
                    let n = Int.random(in: 1...6, using: &rng)
                    let new = (0..<n).map { _ in UInt8.random(in: 0...255, using: &rng) }
                    buffer.insert(new, at: at)
                    reference.insert(contentsOf: new, at: at)
                } else if op == 1 {
                    let lo = Int.random(in: 0..<reference.count, using: &rng)
                    let hi = min(reference.count, lo + Int.random(in: 1...8, using: &rng))
                    buffer.remove(lo..<hi)
                    reference.removeSubrange(lo..<hi)
                } else {
                    let lo = Int.random(in: 0..<reference.count, using: &rng)
                    let hi = min(reference.count, lo + Int.random(in: 0...5, using: &rng))
                    let n = Int.random(in: 0...5, using: &rng)
                    let new = (0..<n).map { _ in UInt8.random(in: 0...255, using: &rng) }
                    guard hi > lo || n > 0 else { continue }
                    buffer.replace(lo..<hi, with: new)
                    reference.replaceSubrange(lo..<hi, with: new)
                }

                XCTAssertEqual(Array(buffer.data()), reference,
                               "seed \(seed) step \(step): content diverged")
                XCTAssertEqual(buffer.count, reference.count,
                               "seed \(seed) step \(step): count diverged")
                if !reference.isEmpty {
                    let probe = Int.random(in: 0..<reference.count, using: &rng)
                    XCTAssertEqual(buffer.byte(at: probe), reference[probe],
                                   "seed \(seed) step \(step): byte(at:) diverged at \(probe)")
                    let lo = Int.random(in: 0..<reference.count, using: &rng)
                    let hi = Int.random(in: lo...reference.count, using: &rng)
                    XCTAssertEqual(buffer.bytes(in: lo..<hi), Array(reference[lo..<hi]),
                                   "seed \(seed) step \(step): bytes(in:) diverged over \(lo)..<\(hi)")
                }
                states.append(reference)
            }

            // Rewind the entire history, checking each intermediate state on the way back.
            for expected in states.dropLast().reversed() {
                XCTAssertTrue(buffer.undo(), "seed \(seed): ran out of undo history early")
                XCTAssertEqual(Array(buffer.data()), expected, "seed \(seed): undo diverged")
            }
            XCTAssertEqual(buffer.data(), original, "seed \(seed): full undo must restore the original bytes")
            XCTAssertFalse(buffer.isModified, "seed \(seed): fully undone buffer must not read as modified")
        }
    }
}

/// Reproducible RNG so a fuzz failure can be re-run. `SystemRandomNumberGenerator` would
/// make a failing seed unrecoverable, which is worse than no fuzzing at all.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
