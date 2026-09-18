# Audit log

Last full audit: **17 Sep 2026** — every source file covered by the MECHANICAL checks below (build warnings, tests,
dead-code and risk-pattern scans, docs drift); line-by-line logic review was targeted at the areas changed since
5 Sep 2026, not the whole tree. Nothing needs re-scanning unless it changed after that date. Add a dated line under *History* when you audit again, and keep the
*Known non-issues* list current so the next pass skips them.

## What a full audit checks

1. `swift build` warnings (none allowed except those listed under known non-issues) and `swift test` green.
2. Dead code: every `func`/type/property declared once and referenced nowhere in the app or the family
   (`grep -w` across `*.swift` AND non-Swift files — selectors and MCP names live in strings). Protocol
   requirements, `override`s, `@objc` actions and public API are NOT dead because Sidewatch does not call them.
3. Risky patterns: `Timer` without `invalidate`, `addObserver(forName:)` without `removeObserver`, `as!`, `try!`
   outside literal regexes, `fatalError` outside `init?(coder:)`, `print(` outside harnesses, TODO/FIXME left behind.
4. Docs drift: every name in CLAUDE.md's module map exists; AGENTS.md mirrors CLAUDE.md; README Usage matches the API.

## Result on 17 Sep 2026

- Build: clean. Tests: green.
- Nothing to fix in this package.

## Logic review — 18 Sep 2026 (every source and test file, line by line)

Nothing to fix. Checked: `BinaryBuffer`'s piece table (`splitBoundary` re-walks for the second edge
of a removal, so its index is valid after the first split; `added` is append-only, so a snapshot of
the piece list restores any state exactly; `isModified` is a comparison against `savedPieces`, not a
flag; the differential fuzz against a plain array), `BinaryDiff.compare`'s honest `truncated`,
every `ByteReader` read bounds-checked (PE's `e_lfanew` may be any 32-bit value and cannot overflow
a 64-bit offset), the 0xCAFEBABE disambiguation, `ByteSearch`'s overlapping matches, `Entropy`,
`HexDump` over a slice with a non-zero `startIndex`.

## Known non-issues (do not "fix" these again)

- `BinaryBuffer.clearHistory()` has no caller in Sidewatch — public API, kept on purpose.
- `BinaryStrings` scans UTF-16 at even offsets from byte 0 only; a wide string starting at an odd
  offset is not found. Scanning both parities would double the cost for a case that has not come up.

## History

- 17 Sep 2026 — full audit (app + all 20 libraries), Claude with David.
- 18 Sep 2026 — logic review (every source and test file, line by line), Claude with David.
