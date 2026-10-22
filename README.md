# Swift Binary Inspector

A toolkit for inspecting binary files: hex/ASCII dumping, magic-byte file-type identification, printable-string extraction, Shannon entropy, byte-pattern search, per-offset scalar decoding, offset-aligned byte diffing, and structural header parsing for the common executable formats (Mach-O, ELF, PE/COFF, Java class, WebAssembly) — plus a piece-table buffer for editing. Pure Foundation, zero dependencies.

### Read-only, except one type

Every inspection type is read-only and never mutates the `Data` it is handed. The single exception is `BinaryBuffer`, the editing buffer, and it is explicit about it: even there the original `Data` stays immutable — edits accumulate in a separate append-only store and are described by a piece list. If you only ever construct the inspection types, nothing in this package can modify your bytes.

## Features

- 🔟 **Hex dump** — `HexDump.rows(of:)` yields structured rows (offset + raw bytes + ASCII gutter) so a view can colorize each byte cell, or `HexDump.render(_:)` for a classic `xxd`-style string
- 🔮 **Magic-byte identification** — `MagicBytes.identify(_:)` names ~30 formats (images, archives, executables, audio/video, fonts, SQLite…) with extension, MIME, and a coarse category; handles the `0xCAFEBABE` Mach-O-universal vs Java-class ambiguity
- 🔤 **String extraction** — `BinaryStrings.extract(from:minLength:encoding:)` recovers printable ASCII and UTF-16 (LE/BE) runs, each tagged with its byte offset
- 📊 **Entropy** — `Entropy.shannon(_:)` (whole-file, 0–8 bits/byte) and `Entropy.blocks(_:blockSize:)` (per-block profile) to spot compressed/encrypted regions
- 🔎 **Byte search** — `ByteSearch.findString(_:in:)` / `findHex(_:in:)` return every match offset; `parseHex(_:)` distinguishes a bad pattern (`nil`) from no matches (`[]`)
- 🧬 **Executable headers** — `BinaryFormat.parse(_:)` reports format, word size, byte order, CPU architecture, and object type for Mach-O (thin + universal), ELF, PE/COFF, Java class, and WASM
- **Mach-O structure** — `MachOParser.parse(_:)` reads a thin or universal (`fat_arch` and `fat_arch_64`) Mach-O file: slices, header, every load command, segments and sections, linked dylibs with their versions and kinds, install name, rpaths, UUID, build/minimum-OS versions, `LC_MAIN`, code-signature and encryption ranges. `MachOParser.symbols(in:image:limit:)` reads the symbol table on demand. `MachOImage` maps addresses to file offsets and back. Every offset is absolute in the file, and a damaged file yields what could be read plus a list of `issues`, never a crash. Validated against `lipo`, `otool` and `nm` over every Mach-O file in the system and application folders (see `AUDIT.md`)
- 🔢 **Scalar decoding** — `BinaryValues.decode(_:at:endianness:)` reads the bytes at one offset back as Int/UInt 8·16·32·64, Float32/64 and ASCII, for a data-inspector panel beside a hex caret. The row set is fixed regardless of remaining length — spans that overrun report `inRange == false` rather than vanishing, so rows never shift under the caret
- 🔀 **Byte diff** — `BinaryDiff.compare(_:_:)` compares two blobs **offset for offset** and returns maximal differing runs. Deliberately not a resyncing diff: over binary data that heuristic invents alignments (a run of `0x00` matches anything). Unequal lengths are compared over the common prefix, with the tail reported as `lengthDelta` so "this file is longer" is never confused with "these bytes changed"
- ✏️ **Editing** — `BinaryBuffer` is a piece table: `insert`/`remove`/`replace`/`overwrite` at any offset, with undo/redo. An insert near the start of a large file rearranges a small piece list instead of moving the bytes. `hexRows(bytesPerRow:from:)` reads a window without materializing the document, so a virtualized hex view stays cheap after edits
- 🛡 **Bounds-checked** — every multi-byte read returns `nil` past the end, so truncated/garbage files are "unrecognized", never a crash
- 🪶 **Small** — Foundation plus swift-foundation-extensions
- 🍎 **Cross-platform** — iOS, macOS, tvOS, watchOS, visionOS

## Requirements

- macOS 14+ (Foundation only; other Apple platforms at SwiftPM's default minimums)
- Swift 6.2+ (Swift 6 language mode)

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Sidewatch/swift-binary-inspector.git", from: "0.1.0")
]
```

## Usage

```swift
import BinaryInspector
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

// Mach-O structure (map big files: only headers and load commands are read)
let mapped = try Data(contentsOf: url, options: .alwaysMapped)
if let file = MachOParser.parse(mapped) {
    for slice in file.slices {
        guard let image = slice.image else { continue }
        print(slice.architectureName ?? "?", image.loadCommands.count, image.isSigned)  // "arm64" 18 true
        for segment in image.segments { print(segment.name, segment.vmAddress, segment.fileOffset) }
        for dylib in image.dylibs { print(dylib.kind, dylib.path, dylib.currentVersion) }  // load /usr/lib/libSystem.B.dylib 1359.0.0
        let symbols = MachOParser.symbols(in: mapped, image: image, limit: 10_000)
        print(symbols.symbols.count, symbols.truncated)
        if let main = image.entryPoint, let offset = Int(exactly: main.fileOffset), let address = image.address(forFileOffset: offset) {
            print(image.section(containingAddress: address)?.name ?? "")  // "__text"
        }
        _ = image.fileOffset(forAddress: 0x1_0000_0548)  // nil in zero-fill or outside every segment
    }
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

## For agents

Read `CONTRIBUTING.md` first: the folder layout and the PR rules. `swift test` is the whole
check, and a new test must fail before the change it covers. `AGENTS.md` carries a
module map (`CLAUDE.md` imports it).

## License

MIT — see [LICENSE](LICENSE).
