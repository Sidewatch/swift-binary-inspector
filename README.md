# Swift Binary Inspect

A dependency-free, read-only toolkit for inspecting binary files: hex/ASCII dumping, magic-byte file-type identification, printable-string extraction, Shannon entropy, byte-pattern search, and structural header parsing for the common executable formats (Mach-O, ELF, PE/COFF, Java class, WebAssembly). Pure Foundation, zero dependencies, never mutates its input — built to back a "what is this file?" inspector panel.

## Features

- 🔟 **Hex dump** — `HexDump.rows(of:)` yields structured rows (offset + raw bytes + ASCII gutter) so a view can colorize each byte cell, or `HexDump.render(_:)` for a classic `xxd`-style string
- 🔮 **Magic-byte identification** — `MagicBytes.identify(_:)` names ~30 formats (images, archives, executables, audio/video, fonts, SQLite…) with extension, MIME, and a coarse category; handles the `0xCAFEBABE` Mach-O-universal vs Java-class ambiguity
- 🔤 **String extraction** — `BinaryStrings.extract(from:minLength:encoding:)` recovers printable ASCII and UTF-16 (LE/BE) runs, each tagged with its byte offset
- 📊 **Entropy** — `Entropy.shannon(_:)` (whole-file, 0–8 bits/byte) and `Entropy.blocks(_:blockSize:)` (per-block profile) to spot compressed/encrypted regions
- 🔎 **Byte search** — `ByteSearch.findString(_:in:)` / `findHex(_:in:)` return every match offset; `parseHex(_:)` distinguishes a bad pattern (`nil`) from no matches (`[]`)
- 🧬 **Executable headers** — `BinaryFormat.parse(_:)` reports format, word size, byte order, CPU architecture, and object type for Mach-O (thin + universal), ELF, PE/COFF, Java class, and WASM
- 🛡 **Bounds-checked** — every multi-byte read returns `nil` past the end, so truncated/garbage files are "unrecognized", never a crash
- 🪶 **Zero dependencies** — Foundation only
- 🍎 **Cross-platform** — iOS, macOS, tvOS, watchOS, visionOS

## Requirements

- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+ / visionOS 1.0+
- Swift 5.9+

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/arraypress/swift-binary-inspect.git", from: "1.0.0")
]
```

## Usage

```swift
import BinaryInspect
import Foundation

let data = try Data(contentsOf: url)

// What is it?
if let type = MagicBytes.identify(data) {
    print(type.name, type.mime ?? "")          // "PNG image" "image/png"
}

// Structural header (executables)
if let info = BinaryFormat.parse(data) {
    print(info.kind.rawValue, info.arch ?? "", info.type ?? "")  // "Mach-O" "ARM64" "executable"
}

// Hex view
for row in HexDump.rows(of: data, bytesPerRow: 16) {
    print(row.offsetColumn, row.hexBytes.joined(separator: " "), row.asciiColumn)
}

// Strings, entropy, search
let strings = BinaryStrings.extract(from: data, minLength: 5)      // [(offset, value)]
let entropy = Entropy.shannon(data)                                // 0.0 ... 8.0
let hits = ByteSearch.findHex("ff d8 ff", in: data)               // [Int]? (nil = bad pattern)
```

## License

MIT © 2026 David Sherlock (ArrayPress)
