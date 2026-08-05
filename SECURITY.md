# Security Policy

## Reporting a vulnerability

**Please do not open a public issue.** Use GitHub's private vulnerability reporting:

> **Security** tab → **Report a vulnerability**

That gives us a private thread with no email round-trip. If it is unavailable, email
**davidmichaelsherlock@icloud.com** with `[security]` in the subject.

Include what an attacker gains, the steps to reproduce, and the version or commit. A rough
report of a real issue beats a polished report of a non-issue — send it even if you are unsure.

**What to expect:** an acknowledgement within 5 working days and an assessment within 14. This
package is maintained by one person, so a fix may take longer than triage; you will be told
where it stands rather than left waiting. Credit in the release notes if you would like it, and
no objection to you publishing once a fix ships.

## Supported versions

The latest tagged release. There are no maintained release branches — fixes land on `main` and
are tagged.

## Scope

This is a library, so the boundary is what it does with input it is handed. The cases worth
reporting:

- **Untrusted input causing memory unsafety or a crash** — a malformed file, diff, token,
  archive, database, or byte stream that corrupts memory or reliably crashes a caller.
- **Path traversal** — a crafted path, filename, or header that causes a read or write outside
  the directory an operation implies.
- **Command or argument injection** — anything that lets input reach a shell or alter the
  argument list of a spawned process.
- **Unbounded resource use on small input** — an input whose size does not explain the memory
  or CPU it consumes, where a caller could be stalled by a hostile file.
- **Leaking secrets** — credentials or token material appearing in output, errors, or logs.
- **Data races** — every package here builds under `-strict-concurrency=complete`, so a
  reachable race is a bug, not a design limit.

**Not vulnerabilities:**

- A caller passing a deliberately dangerous argument. These are thin wrappers; they do what
  they are told.
- Wrapping a command-line tool (`git`, and similar) at all. Executing it is the purpose.
- A crash on input the API documents as unsupported, unless it is memory-unsafe.

If the issue is in the Sidewatch application rather than this package, report it at
<https://github.com/Sidewatch/sidewatch>.
