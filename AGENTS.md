# Swift Binary Inspector

A dependency-free toolkit for inspecting binary files: hex/ASCII dumping, magic-byte file-type identification, printable-string extraction, Shannon entropy, byte-pattern search, per-offset scalar decoding, offset-aligned byte diffing, and structural header parsing for the common executable formats (Mach-O, ELF, PE/COFF, Java class, WebAssembly) — plus a piece-table buffer for editing. Pure Foundation, zero dependencies.

- Module `BinaryInspector` in `Sources/BinaryInspector`; tests in `Tests`; `swift test` is the whole check.
- Swift 6 language mode, tools 6.2, macOS 14+, no dependencies unless the README says so.
- Part of the Sidewatch package family; every package follows the same layout and PR rules.

## Module map

- `Core/` — the engine: BinaryDiff, BinaryDiff+Summary, BinaryFormat, BinaryStrings, BinaryValues, ByteReader, ByteSearch, Entropy, HexDump, MagicBytes, MachOParser (Mach-O structure: `parse` reads headers and load commands only; `symbols(in:image:limit:)` reads nlist entries on demand, capped at 200,000 by default), MachOImage+Addresses (address <-> absolute file offset over a segment's FILE-BACKED part only, `min(fileSize, vmSize)`; segment/section lookups)
- `Edit/` — the engine: edit: BinaryBuffer
- `Models/` — Mach-O value types: MachOFile, MachOSlice, MachOImage, MachOLoadCommand, MachOSegment, MachOSection, MachODylib, MachOVersion, MachOBuildVersion, MachOBuildTool, MachOEntryPoint, MachOCodeSignature, MachOEncryptionInfo, MachOSymbolTableLocation, MachOSymbol, MachOSymbolTable
- `Enums/` — MachODylibKind, MachOSymbolKind, MachOIssue (what a damaged file had skipped; raw values, the app words them)
- `Support/` — ByteOffset (`parse`: a Go to Offset entry, always hexadecimal; only a LEADING `0x` is a prefix, so `10x0` is refused, never read as `0x10`), MachOArchitecture (lipo-style names, subtype feature bits masked), MachOLoadCommandName (otool-style names; unknown numbers stay hex)
- `Internal/` — BoundedBytes (the Mach-O reader's bounds-checked raw-buffer reads), MachOFatReader, MachOImageReader, MachOCommandDecoder, MachOSymbolReader
- `Tools/MachODump` — `macho-dump`, a development executable (no product) that prints the parser's view as JSON
- `scripts/validate_macho.py` — compares the parser with lipo/otool/nm over every Mach-O file in the system and app folders (macOS with developer tools only; never part of `swift test`)
- `Tests/BinaryInspectorTests/Fixtures` — Mach-O fixtures in `MachO/`, rebuilt by `make_fixtures.sh` from `src/`; the tests assert values read from those exact files with otool/nm

## Mach-O rules

- Every file offset in the Mach-O models is ABSOLUTE in the file: a universal slice's offset is already added, so it indexes the original `Data`. Fields are raw numbers and names; the app formats them.
- A damaged file never traps, hangs or allocates wildly: counts are capped by the bytes that could hold them, a `cmdsize` below 8 or past the command area ends the walk, sums near `UInt64.max` saturate. What was skipped is listed in `issues`.
- After changing the parser, run `scripts/validate_macho.py` and keep its mismatch count at zero (see `AUDIT.md` for the last run and the known tool differences).

## Rules

Read `CONTRIBUTING.md` for the folder layout and the pull-request rules.

@CONTRIBUTING.md

- **Auditing? Read `AUDIT.md` first** — what the last full audit checked and fixed, and the known non-issues to skip; extend it, do not redo it.
