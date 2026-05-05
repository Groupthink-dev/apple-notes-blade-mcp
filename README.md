# apple-notes-blade-mcp

Stallari-internal Swift library blade for read-only access to Apple Notes (`NoteStore.sqlite` + zlib-compressed protobuf bodies). Consumed by `StallariKit` via SPM dependency; never exposed externally.

**Audience:** future me + future architect sessions debugging a Notes parser regression. This is **not** a third-party MCP server. There is no notarised installer, no Claude Desktop snippet, no PyPI/Homebrew distribution.

---

## Class context

First concrete blade under the local-corpus class defined in [DD-240](../master-ai/atlas/utilities/agent-harness/decisions/DD-240.md). Sibling: `apple-mail-blade-mcp` (DD-241, Phase B). Existing kin: `apple-reminders-blade-mcp` (Python — EventKit-via-pyobjc carve-out per DD-240 invariant #6).

The class invariants this blade conforms to live at `directives/local-corpus-blades.md`. The most load-bearing ones for this repo:

- **No probabilistic inference.** Heuristic protobuf walker is deterministic; no ML.
- **Read-only.** SQLite opened with `SQLITE_OPEN_READONLY`. Write surfaces would need a per-feature DD.
- **No network.** The library doesn't link a network framework.
- **Hardcoded read paths.** `Config.storePath` validates against the canonical Apple Notes Group Container path.

## Why a separate repo

Clean module boundary, mirrors the planned `apple-mail-blade-mcp` shape (also Swift, also raw-disk reads), shippable independently if external exposure is ever wanted later. The repo costs ~zero ongoing maintenance — code volume is small, dependency surface is two packages, no external release cadence.

## No external exposure

The 5 Notes tools are wired into the Stallari daemon's *internal* tool routing only. They never appear on the public `:9847/mcp` HTTP MCP surface. Enforcement:

- `AppleNotesBladeWiring` in `stallari-harness/Sources/StallariKit/Blades/` exposes the registry via an internal accessor.
- `DaemonMCPServer`'s composite router is **not** wired up to consult this registry.
- `AppleNotesBladeWiringTests.testNotesNotAdvertisedExternally` verifies that no `apple_notes_*` tool is registered with the public `ToolCatalog`. This test is a load-bearing regression guard — do not weaken or skip it.

If an external MCP client (Claude Desktop, third-party) connects to `:9847/mcp` and runs `tools/list`, no Notes tools are returned.

## Tools

Five tools, all read-only:

| Tool | Purpose | Signature |
|---|---|---|
| `apple_notes_list_folders` | Enumerate folders. Optional account filter. | `(account_id?: int) -> [{id, account_id, name, is_default, note_count}]` |
| `apple_notes_list_notes` | List notes in a folder. Index-only — never opens body bytes. | `(folder_id: int, since?: ISO8601, limit?: int = 100, offset?: int = 0) -> [{id, title, snippet, modified_at, ...}]` |
| `apple_notes_read_note` | Inflate + decode a single note body. | `(id: int, include_html?: bool = false) -> {id, title, body_text, attachments, ...}` |
| `apple_notes_search_notes` | LIKE-based substring search over title + snippet. | `(query: string, account_id?: int, folder_id?: int, since?: ISO8601, limit?: int = 50) -> [...]` |
| `apple_notes_head` | Cheap metadata lookup; never inflates body. | `(id: int) -> {id, title, body_byte_length, attachment_count, ...}` |

Hard cap on every `limit` argument: `Config.maxResultsHardCap` (default 1000). Caps clamp silently — exceeding values do not error.

## Schema notes

### NoteStore.sqlite (V10, macOS 14+)

Apple's schema is a single master table — `ZICCLOUDSYNCINGOBJECT` — with `ZTYPEUTI` discriminating between accounts, folders, notes, and attachments. Body bytes live in `ZICNOTEDATA` joined via `ZNOTEDATA`. Relevant columns documented in `Sources/AppleNotesBlade/Schema.swift` and queried in `NoteStore.swift`.

Z-fields we read: `Z_PK`, `ZTYPEUTI`, `ZNAME`, `ZIDENTIFIER`, `ZTITLE1`, `ZTITLE2`, `ZSNIPPET`, `ZACCOUNT3`, `ZFOLDER`, `ZNOTEDATA`, `ZMODIFICATIONDATE1`, `ZCREATIONDATE1`, `ZATTACHMENTSCOUNT`, `ZISPINNED`, `ZMARKEDFORDELETION`.

Date fields are **Apple Core Data NSDate timestamps** — seconds since 2001-01-01 00:00:00 UTC. `Schema.date(fromCoreData:)` does the conversion.

Older schema versions (V9, V8) are unsupported in v0.1.0. If you hit a Mac with an older schema, the queries error out cleanly via `sqliteError`.

### Body protobuf

`ZICNOTEDATA.ZDATA` is a **gzip-wrapped protobuf** blob. The protobuf shape varies across macOS releases — there is no stable schema. The decoder in `ProtobufDecoder.swift` walks the wire format heuristically:

1. Strip the gzip envelope (10-byte header + 8-byte trailer; FEXTRA/FNAME/FCOMMENT/FHCRC handled).
2. Decompress raw deflate via `Compression` framework's `compression_decode_buffer`.
3. Recursively walk every length-delimited field as either UTF-8 string or embedded message.
4. Collect candidate strings filtered by `looksLikeReadableText` (rejects wire-format byte soup that happens to be ASCII-low-value by requiring the first scalar to be printable).
5. Pick the longest candidate as the body. Drop UUID-shaped strings (those go to attachment metadata).

Hardening: bounded recursion (`maxDepth=32`), bounded inflated payload (`maxMessageBytes=16MB`), bounded varint length (`maxVarintBytes=10`).

### What HTML rendering looks like (deferred)

`include_html: true` returns `body_html: null` and `html_not_implemented: true` (a soft signal, not an error). HTML-faithful rendering would require interpreting `AttributeRun` formatting attributes from the inner `Note` proto. Tracked for v0.2.0+ if a consumer demands it.

### What FTS looks like (deferred)

Apple maintains `NoteStoreFTS.sqlite` alongside `NoteStore.sqlite` for Spotlight-equivalent search, but the schema is opaque + version-dependent. `apple_notes_search_notes` v0.1.0 uses `LIKE` over `ZTITLE1` + `ZSNIPPET` — cheap, predictable, "good enough" for the corpus volumes typical in personal Notes. Real FTS attach is a v0.2.0+ open question.

## Updating

```sh
# In this repo:
make test                  # 52 tests, all fixture-based
git tag -a v0.1.x -m "..."
git push origin v0.1.x

# In stallari-harness:
# Update the SPM ref (path or URL). Pin by SHA before the next Stallari tag.
```

## Troubleshooting

### `permission_denied`
The consuming binary (Stallari) does not have Full Disk Access. Open System Settings → Privacy & Security → Full Disk Access and enable Stallari. The error response always carries the System Settings pointer.

### `store_missing`
`NoteStore.sqlite` does not exist at the configured path. Either Notes.app has never been launched on this Mac, or Apple has shipped a new path schema. Check `~/Library/Group Containers/group.com.apple.notes/`.

### `store_locked`
SQLite returned `SQLITE_BUSY` past the 200ms busy-timeout. Notes.app is in the middle of a sync write. Retry with backoff. Persistent lockups (>30s) are unusual and worth investigating.

### `decode_failure`
The protobuf decoder hit one of its hard caps (max depth, max size, truncated stream) or the gzip envelope was malformed. Carries the note ID for correlation but never the body. If reproducible, capture the ZDATA bytes into a fixture and add a regression test.

### `invalid_store_path`
`Config.storePath` was set to a path outside the allowed prefixes (the canonical Apple Notes Group Container or `/private/tmp/`). This is intentional — only fixture tests should override the path.

## Development

```sh
make build           # swift build (debug)
make test            # swift test --enable-code-coverage
make lint            # swift-format lint
make format          # swift-format auto-format
make clean           # remove .build / .swiftpm
```

CI runs lint + build + test on macOS 14 and macOS 15. **No signing in CI**, no Apple developer credentials, no notarisation. The signing event happens locally in `stallari-harness/Makefile`'s `make dist`, which signs the entire `.app` (including this library compiled into StallariKit).

## Security

See [SECURITY.md](./SECURITY.md). Report internal Stallari security issues via the Stallari security channel. Out of scope: any vulnerability requiring a non-Stallari MCP client to be wired up to this library — by design, that path doesn't exist.

## License

MIT — see [LICENSE](./LICENSE).
