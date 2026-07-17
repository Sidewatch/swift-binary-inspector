//
//  Entropy.swift
//  SwiftBinaryInspect
//
//  Shannon entropy — whole-file and per-block — for spotting compressed/encrypted regions.
//
//  Created by David Sherlock on 7/18/26.
//

import Foundation

/// Shannon byte entropy, in bits per byte (`0.0` = perfectly uniform data, up to `8.0`
/// = maximally random). High, flat entropy across a region is the usual fingerprint of
/// compression or encryption; a per-block profile makes packed/encrypted sections stand
/// out against low-entropy headers and code.
public enum Entropy {

    /// Whole-buffer Shannon entropy in bits/byte (`0...8`). Empty data is `0`.
    public static func shannon(_ data: Data) -> Double {
        guard !data.isEmpty else { return 0 }
        var counts = [Int](repeating: 0, count: 256)
        let base = data.startIndex
        for i in 0..<data.count { counts[Int(data[base + i])] += 1 }
        let n = Double(data.count)
        var h = 0.0
        for c in counts where c > 0 {
            let p = Double(c) / n
            h -= p * log2(p)
        }
        return h
    }

    /// One block's entropy plus where it sits.
    public struct Block: Equatable {
        public let offset: Int
        public let length: Int
        public let entropy: Double
        public init(offset: Int, length: Int, entropy: Double) {
            self.offset = offset; self.length = length; self.entropy = entropy
        }
    }

    /// A per-block entropy profile: `data` split into `blockSize` chunks (the last may be
    /// short), each scored independently. Useful for driving an entropy sparkline/heatmap.
    ///
    /// - Parameters:
    ///   - data: The bytes to profile.
    ///   - blockSize: Chunk size (clamped to ≥ 1; default 256).
    /// - Returns: One ``Block`` per chunk, in offset order.
    public static func blocks(_ data: Data, blockSize: Int = 256) -> [Block] {
        let size = max(1, blockSize)
        guard !data.isEmpty else { return [] }
        var out: [Block] = []
        out.reserveCapacity((data.count + size - 1) / size)
        var i = 0
        while i < data.count {
            let end = min(i + size, data.count)
            out.append(Block(offset: i, length: end - i, entropy: shannon(data.subdata(in: (data.startIndex + i)..<(data.startIndex + end)))))
            i = end
        }
        return out
    }
}
