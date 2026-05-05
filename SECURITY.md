# Security

## Scope

`apple-notes-blade-mcp` is a Stallari-internal Swift library, consumed only by `StallariKit` via SPM dependency. It is **not exposed externally** — the 5 Notes tools are registered with StallariKit's internal tool catalog only and never appear on the daemon's public `:9847/mcp` HTTP MCP surface. A regression test in `stallari-harness` (`AppleNotesBladeWiringTests.testNotesNotAdvertisedExternally`) guards this boundary.

## In scope

- Bugs in the Apple Notes data path that could leak content, bypass read-only invariants, or escalate the blade's access beyond its declared sandbox.
- Parser hardening issues: protobuf decoder unbounded recursion / large-message handling, zlib bomb resistance, SQLite query injection.
- Path validation gaps in `Config.storePath` (only `/private/tmp/*` and the canonical Apple Notes Group Container path are accepted).

## Out of scope

- Any vulnerability requiring a non-Stallari MCP client to be wired up to the library — by design, this library is not exposed externally and there is no remote attack surface.
- macOS Full Disk Access policy. The blade requires FDA on the consuming Stallari binary; granting FDA to a malicious binary is outside this project's scope.
- `swift-sdk` / `SwiftProtobuf` upstream supply-chain compromise. Reported to the upstream maintainers.

## Reporting

Please report security issues via the Stallari security channel. Do not file public GitHub issues for security-sensitive matters.

Disclosure window: 90 days from triage.

## Cryptography & secrets

- The library reads `NoteStore.sqlite` read-only. No keys, no tokens, no credentials are touched.
- The blade does not open network sockets. App Sandbox network entitlement is irrelevant because Stallari runs unsandboxed (FDA prerequisite).

## Supply chain

- Dependencies pinned by SHA in Stallari's release cadence (not in this repo's `Package.swift`, which uses a local-path dep during dev).
- SBOM emitted by Stallari's release pipeline, not this repo's.
