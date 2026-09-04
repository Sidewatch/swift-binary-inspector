# Swift Binary Inspector

A dependency-free toolkit for inspecting binary files: hex/ASCII dumping, magic-byte file-type identification, printable-string extraction, Shannon entropy, byte-pattern search, per-offset scalar decoding, offset-aligned byte diffing, and structural header parsing for the common executable formats (Mach-O, ELF, PE/COFF, Java class, WebAssembly) — plus a piece-table buffer for editing. Pure Foundation, zero dependencies.

- Module `BinaryInspector` in `Sources/BinaryInspector`; tests in `Tests`; `swift test` is the whole check.
- Swift 6 language mode, tools 6.2, macOS 14+, no dependencies unless the README says so.
- Part of the Sidewatch package family; every package follows the same layout and PR rules.

## Module map

- `Core/` — the engine: BinaryDiff, BinaryFormat, BinaryStrings, BinaryValues, ByteReader, ByteSearch, Entropy, HexDump, MagicBytes
- `Edit/` — the engine: edit: BinaryBuffer

## Rules

@CONTRIBUTING.md
