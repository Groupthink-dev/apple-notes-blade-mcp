# Contributing

This is a Stallari-internal repo. Contribution patterns assume you're a future
me, an architect session, or an authorised collaborator working on the
Stallari platform — not an external open-source contributor.

## Coding standards

- **Format with `swift-format`.** `make format-check` must pass before commit.
  The repo's `.swift-format` is the source of truth.
- **No external dependencies beyond what `Package.swift` declares.** Today
  that's `MCP` (via local-path `swift-sdk`) and `SQLite.swift` (with the
  SQLCipher trait, for SPM-graph compatibility with the harness — the trait
  is not used at runtime).
- **No probabilistic inference.** This is a class invariant from
  [DD-240](../master-ai/atlas/utilities/agent-harness/decisions/DD-240.md)
  invariant #3. PRs that add LLM calls or user-loaded CoreML get rejected.
- **No network egress.** The library doesn't link a network framework. PRs
  that change this need to come with a DD justifying the change.
- **Errors carry IDs only, never bodies/titles.** This is privacy hygiene —
  errors propagate through Stallari traces and external logs.

## Tests

- **Fixtures only in CI.** `Tests/AppleNotesBladeTests/Fixtures/` builds a
  synthetic `NoteStore.sqlite` under `/private/tmp/` — never the user's real
  Notes data.
- **Never commit real NoteStore data.** The `.gitignore` has explicit guards
  (`*.sqlite`, `NoteStore*`, `fixtures/real/`); double-check before adding
  test fixtures.
- **Add a regression test for every bug fix.** Decoder edge cases especially —
  Apple ships proto schema bumps without warning.

## Local Stallari testing

To test changes against the real Stallari harness without tagging the blade:

1. Confirm `~/src/apple-notes-blade-mcp/` and `~/src/stallari-harness/` are
   sibling directories on disk.
2. The harness's `Package.swift` already references this repo via
   `.package(path: "../apple-notes-blade-mcp")` — no further wiring needed.
3. From `~/src/stallari-harness/` run `make install-dev`. Stallari rebuilds
   with your local changes compiled in.
4. Tests: `swift test --filter AppleNotesBladeWiringTests` runs the harness-
   side tests. They include the regression guard
   `testNotesNotAdvertisedExternally` — keep that test green.

## No online CI signing

We don't sign anything in this repo's CI. No Apple developer credentials in
GitHub Secrets. No notarised pkg release. The signing event happens locally
in `stallari-harness/Makefile`'s `make dist`, which signs the entire `.app`
including this library compiled into StallariKit.

If a future need surfaces for an external surface (e.g. a Notes triage CLI
that ships standalone), that change comes via a separate DD that revisits
the distribution model — it is not a casual addition.

## Versioning

SemVer. Pre-release suffixes (`v0.1.0-rc1`) are allowed and indicate the
library is feature-complete locally but hasn't been wired into a Stallari
release yet. Consumers should pin by commit SHA while the suffix is
non-empty. `Sources/AppleNotesBlade/Version.swift` is the canonical
SemVer string; bump it together with the git tag.

## License

MIT — see [LICENSE](./LICENSE). All contributions are accepted under the same.
