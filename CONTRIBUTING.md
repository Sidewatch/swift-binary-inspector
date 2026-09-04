# Contributing

These packages back [Sidewatch](https://github.com/Sidewatch) and are meant to be used by other
projects too. Pull requests are welcome. The rules below keep every package in the family
looking like one codebase, so a reader who knows one knows them all.

## Layout

```
Sources/<Module>/
  Models/       value types — the shape of a thing, nothing else
  Enums/        enums with no behaviour beyond their cases and labels
  Errors/       every Error type, one per file
  Protocols/    protocols the module exposes
  Extensions/   extensions on Foundation / stdlib / other modules' types
  Support/      pure helpers: parsing, escaping, validation, thresholds
  Internal/     non-public machinery
  <Domain>/     the engine, named for what it does (Operations, TreeSitter, Ignore, …)
```

`Core/` is allowed only when the folder IS the engine. A package with one or two files may stay
flat. Tests mirror the module: `Tests/<Module>Tests/<Type>Tests.swift`.

## Rules

- **No repeated code.** A helper needed twice becomes one `Support/` function or an
  `Extensions/` member. Never copy a helper between packages; promote it to a shared package.
- **Models are only models.** Parsing, assembly and validation live in `Support/`, reached
  through thin `Extensions/` where that reads better.
- **Swift 6 language mode, tools 6.0, macOS 14+.** No `unsafeFlags` in `Package.swift`: they make
  the package unusable as a URL dependency.
- **Public API is documented** with `///`. Anything not needed outside the module is `internal`.
- **Tests are mutation-verified.** A new test must FAIL against the code before your change,
  then pass with it. Name the mutant you checked in the PR.
- **Measure before claiming.** A performance change comes with the numbers, before and after.
- **No dependencies without a reason** that the README states. Most packages here have none.

## Pull requests

- One change per PR, with tests, and `swift test` green.
- Say what changed, why, and which test failed before the change.
- Update the README's Usage section when public API changes.
- No version bumps or CHANGELOG edits in feature PRs; releases are tagged separately.
- Licence is MIT. By contributing you agree your contribution is MIT too.
