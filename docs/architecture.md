# Architecture — apple-notes-blade-mcp

A short companion to the README. Captures the design choices and where they
came from in DD-240.

## Where this library sits

```
┌─────────────────────────────────────────────────────────┐
│  Stallari skill / dispatcher (consuming caller)         │
│                                                         │
│           ┌──────────────────────────────────┐          │
│           │  StallariKit (in-process)        │          │
│           │                                  │          │
│           │   Blades/AppleNotesBladeWiring   │   ← internal accessor
│           │            │                     │          │
│           │            ▼                     │          │
│           │   AppleNotesBlade (this lib)     │          │
│           │   ┌──────────────────────────┐   │          │
│           │   │  AppleNotesToolRegistry  │   │          │
│           │   │  (5 MCP-shaped tools)    │   │          │
│           │   │                          │   │          │
│           │   │  NoteStore (actor)       │   │          │
│           │   │  ProtobufNotesDecoder    │   │          │
│           │   └──────────────────────────┘   │          │
│           │                                  │          │
│           └──────────────────────────────────┘          │
│                          │                              │
│                          ▼                              │
│        ~/Library/Group Containers/group.com.apple.notes/│
│              NoteStore.sqlite (read-only)               │
│                                                         │
└─────────────────────────────────────────────────────────┘

  ✗ Public DaemonMCPServer (:9847/mcp) — Notes tools NOT advertised.
```

The blade is a **library**, not a process. It compiles into Stallari's main
binary. There is no IPC boundary between the consumer and the reader; calls
go through the actor isolation of `NoteStore` and that's the only
synchronisation primitive in play.

## Why a library, not a subprocess

[DD-240 form-factor decision](../../master-ai/atlas/utilities/agent-harness/decisions/DD-240-phase-A-implementation-plan.md):

- **TCC zero-touch.** FDA grant on Stallari covers Notes by virtue of shared
  CDHash. No second prompt, no second grant.
- **Single signing pipeline.** Stallari's existing `make dist` Makefile is
  the only signing event.
- **No subprocess lifecycle ceremony.** No spawn/restart/IPC.

Trade-off: a crash in the protobuf parser brings down the whole harness.
Mitigation lives at three layers:

1. **Defensive parser.** Bounded recursion, bounded message size, bounded
   varint length. All explicit caps with explicit errors.
2. **Actor isolation.** `NoteStore` is an actor; the whole call chain
   from `read_note` down to SQLite is async-isolated.
3. **Failure escape valve.** If real-world crashes surface in soak, escalate
   to Option B (subprocess inside `.app`) in a v0.2.0 DD. The library form
   factor doesn't preclude that — wrapping the library in a stdio MCP
   subprocess is a small additional executable target.

## Why heuristic protobuf, not strict schema

Apple's Notes proto layout has shifted across macOS releases. A strict
codegen'd decoder breaks on the first schema bump. The heuristic walker:

- Walks every length-delimited field as either UTF-8 string or embedded
  message. Bounded recursion.
- Collects candidate strings filtered by `looksLikeReadableText` — rejects
  wire-format envelope bytes that happen to be ASCII-low-value by requiring
  the first scalar to be printable.
- Picks the longest candidate as the body. UUID-shaped strings go to
  attachment metadata instead.

False positives possible: occasionally extracts a metadata field that isn't
quite the body. Soak time will tell us how much that matters in practice.
The test suite locks current behaviour — regressions get caught.

## Why SQLite.swift, not raw SQLite3

Matches `stallari-vault`'s posture. The package is mature, type-safe, and
already vetted in our dependency graph. SQLCipher trait is enabled for
SPM-graph compatibility with the harness; we don't actually open
encrypted databases.

## Why no schema change for v0.1.0

Three "deferred" calls:

- **HTML body rendering** (`include_html: true` returns null + soft signal).
  Reconstructing HTML from the inner `Note` proto's `AttributeRun` fields
  is non-trivial. Tackle in v0.2.0+ when a consumer demands it.
- **FTS attach** (search uses `LIKE`). Apple's `NoteStoreFTS.sqlite`
  companion file has an opaque, version-dependent schema. Defer until
  benchmarks justify.
- **Attachment body bytes** (`read_attachment` doesn't exist yet). For
  v0.1.0, attachment metadata only. A `read_attachment` tool would walk the
  `Attachments/` subtree and return raw bytes — different threat surface,
  different size budget.

Each is gated on a concrete consumer + soak experience.

## Class lineage

This is the **first** concrete blade under the local-corpus class. The
class invariants codified in `directives/local-corpus-blades.md` were
written before this library existed; this implementation is the
corresponding proof of concept. If something here surprises you that
isn't in the directive, the directive is probably wrong — file a DD.

The next blade in the class is `apple-mail-blade-mcp` (DD-241, Phase B).
It will mirror the structure here:

- Swift library compiled into StallariKit
- Hardcoded read paths (`~/Library/Mail/V10/`)
- Read-only v1
- Heuristic decoder for `.emlx` MIME edge cases
- Internal-only registry, regression test against external advertisement

The reusable substrate from this repo (the `AppleNotesToolRegistry` shape,
the wire-format walker pattern, the strict path-validation in `Config`)
should generalise to mail with low ceremony.
