//
//  MagicBytes.swift
//  SwiftBinaryInspect
//
//  Best-effort file-type identification from leading magic bytes.
//
//  Created by David Sherlock on 7/18/26.
//

import Foundation

/// Best-effort file-type identification from a file's leading bytes (and a couple of
/// fixed-offset signatures). Deliberately shallow — for a structural breakdown of an
/// executable use ``BinaryFormat``; this just answers "what kind of file is this?".
public enum MagicBytes {

    /// A broad grouping, so a UI can pick an icon/tint without string-matching names.
    public enum Category: String, Sendable {
        case image, archive, executable, document, audio, video, database, font, other
    }

    /// An identified type: a human name, the conventional extension/MIME when there is
    /// one, and a coarse category.
    public struct FileType: Equatable, Sendable {
        public let name: String
        public let ext: String?
        public let mime: String?
        public let category: Category

        public init(name: String, ext: String?, mime: String?, category: Category) {
            self.name = name; self.ext = ext; self.mime = mime; self.category = category
        }
    }

    /// Identify `data` from its magic bytes, or `nil` when nothing matches.
    ///
    /// Note the `0xCAFEBABE` ambiguity: it is both a Mach-O universal ("fat") binary and a
    /// Java `.class` file. They are disambiguated by the big-endian word at offset 4 — a
    /// small architecture count (≤ 30) reads as Mach-O, otherwise as a class-file version.
    public static func identify(_ data: Data) -> FileType? {
        guard !data.isEmpty else { return nil }

        // Fixed-offset signatures first (they'd be shadowed by a shorter prefix match).
        if ByteReader.matches(data, at: 257, [0x75, 0x73, 0x74, 0x61, 0x72]) {   // "ustar"
            return FileType(name: "TAR archive", ext: "tar", mime: "application/x-tar", category: .archive)
        }
        if ByteReader.matches(data, at: 4, [0x66, 0x74, 0x79, 0x70]) {           // "ftyp"
            return FileType(name: "MP4 / ISO media", ext: "mp4", mime: "video/mp4", category: .video)
        }
        if ByteReader.hasPrefix(data, [0x52, 0x49, 0x46, 0x46]) {                // "RIFF"
            if ByteReader.matches(data, at: 8, [0x57, 0x41, 0x56, 0x45]) {       // "WAVE"
                return FileType(name: "WAV audio", ext: "wav", mime: "audio/wav", category: .audio)
            }
            if ByteReader.matches(data, at: 8, [0x41, 0x56, 0x49, 0x20]) {       // "AVI "
                return FileType(name: "AVI video", ext: "avi", mime: "video/x-msvideo", category: .video)
            }
            if ByteReader.matches(data, at: 8, [0x57, 0x45, 0x42, 0x50]) {       // "WEBP"
                return FileType(name: "WebP image", ext: "webp", mime: "image/webp", category: .image)
            }
            return FileType(name: "RIFF container", ext: nil, mime: nil, category: .other)
        }

        // 0xCAFEBABE: Mach-O universal vs Java class (see doc comment).
        if ByteReader.hasPrefix(data, [0xCA, 0xFE, 0xBA, 0xBE]) {
            let count = ByteReader.u32(data, 4, bigEndian: true) ?? 0xFFFF
            return count <= 30
                ? FileType(name: "Mach-O universal binary", ext: nil, mime: "application/x-mach-binary", category: .executable)
                : FileType(name: "Java class", ext: "class", mime: "application/java-vm", category: .executable)
        }

        for (prefix, type) in prefixTable where ByteReader.hasPrefix(data, prefix) {
            return type
        }
        return nil
    }

    /// Ordered prefix table (longer / more-specific prefixes first where they'd collide).
    private static let prefixTable: [([UInt8], FileType)] = [
        ([0x89, 0x50, 0x4E, 0x47],             .init(name: "PNG image", ext: "png", mime: "image/png", category: .image)),
        ([0xFF, 0xD8, 0xFF],                   .init(name: "JPEG image", ext: "jpg", mime: "image/jpeg", category: .image)),
        ([0x47, 0x49, 0x46, 0x38],             .init(name: "GIF image", ext: "gif", mime: "image/gif", category: .image)),
        ([0x42, 0x4D],                         .init(name: "BMP image", ext: "bmp", mime: "image/bmp", category: .image)),
        ([0x00, 0x00, 0x01, 0x00],             .init(name: "ICO icon", ext: "ico", mime: "image/x-icon", category: .image)),
        ([0x25, 0x50, 0x44, 0x46],             .init(name: "PDF document", ext: "pdf", mime: "application/pdf", category: .document)),
        ([0x50, 0x4B, 0x03, 0x04],             .init(name: "ZIP archive", ext: "zip", mime: "application/zip", category: .archive)),
        ([0x50, 0x4B, 0x05, 0x06],             .init(name: "ZIP archive (empty)", ext: "zip", mime: "application/zip", category: .archive)),
        ([0x1F, 0x8B],                         .init(name: "gzip archive", ext: "gz", mime: "application/gzip", category: .archive)),
        ([0x42, 0x5A, 0x68],                   .init(name: "bzip2 archive", ext: "bz2", mime: "application/x-bzip2", category: .archive)),
        ([0xFD, 0x37, 0x7A, 0x58, 0x5A],       .init(name: "XZ archive", ext: "xz", mime: "application/x-xz", category: .archive)),
        ([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C], .init(name: "7-Zip archive", ext: "7z", mime: "application/x-7z-compressed", category: .archive)),
        ([0x52, 0x61, 0x72, 0x21],             .init(name: "RAR archive", ext: "rar", mime: "application/x-rar-compressed", category: .archive)),
        ([0x7F, 0x45, 0x4C, 0x46],             .init(name: "ELF executable", ext: nil, mime: "application/x-elf", category: .executable)),
        ([0xFE, 0xED, 0xFA, 0xCE],             .init(name: "Mach-O (32-bit)", ext: nil, mime: "application/x-mach-binary", category: .executable)),
        ([0xFE, 0xED, 0xFA, 0xCF],             .init(name: "Mach-O (64-bit)", ext: nil, mime: "application/x-mach-binary", category: .executable)),
        ([0xCE, 0xFA, 0xED, 0xFE],             .init(name: "Mach-O (32-bit, LE)", ext: nil, mime: "application/x-mach-binary", category: .executable)),
        ([0xCF, 0xFA, 0xED, 0xFE],             .init(name: "Mach-O (64-bit, LE)", ext: nil, mime: "application/x-mach-binary", category: .executable)),
        ([0x4D, 0x5A],                         .init(name: "PE / DOS executable", ext: "exe", mime: "application/x-msdownload", category: .executable)),
        ([0x00, 0x61, 0x73, 0x6D],             .init(name: "WebAssembly module", ext: "wasm", mime: "application/wasm", category: .executable)),
        ([0x53, 0x51, 0x4C, 0x69, 0x74, 0x65], .init(name: "SQLite database", ext: "sqlite", mime: "application/vnd.sqlite3", category: .database)),
        ([0x4F, 0x67, 0x67, 0x53],             .init(name: "Ogg media", ext: "ogg", mime: "application/ogg", category: .audio)),
        ([0x66, 0x4C, 0x61, 0x43],             .init(name: "FLAC audio", ext: "flac", mime: "audio/flac", category: .audio)),
        ([0x49, 0x44, 0x33],                   .init(name: "MP3 audio (ID3)", ext: "mp3", mime: "audio/mpeg", category: .audio)),
        ([0x77, 0x4F, 0x46, 0x46],             .init(name: "WOFF font", ext: "woff", mime: "font/woff", category: .font)),
        ([0x77, 0x4F, 0x46, 0x32],             .init(name: "WOFF2 font", ext: "woff2", mime: "font/woff2", category: .font)),
        ([0x4F, 0x54, 0x54, 0x4F],             .init(name: "OpenType font", ext: "otf", mime: "font/otf", category: .font)),
        ([0x00, 0x01, 0x00, 0x00, 0x00],       .init(name: "TrueType font", ext: "ttf", mime: "font/ttf", category: .font)),
    ]
}
