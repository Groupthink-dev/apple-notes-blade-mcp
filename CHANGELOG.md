# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-05-24

### Changed

- **DD-338 Phase C Wave 5:** consolidate `_meta:` envelope emission onto the
  canonical `stallari-mcp-helpers-swift` SPM dep (`MCPHelpers` module v0.1.0).
  Local `Sources/AppleNotesBlade/MetaEnvelope.swift` (160 LOC) deleted; functionally
  equivalent but wire-shape now matches the cross-language canonical:
  - `redactions` and `next_cursor` are ALWAYS emitted (defaults to `[]` and JSON
    `null` respectively). Hand-rolled v1 omitted these when empty/nil.
  - `filtered_by` is alphabetically sorted by the formatter (caller pre-sort is
    no longer load-bearing; existing pre-sorts remain harmless).
  - `formatMetaLine` now throws (encoding-failure surface).
- Catalog declarations flipped `audit_surface: minimal → structured` for the 3
  tools emitting `_meta` envelopes (`apple_notes_list_folders`,
  `apple_notes_list_notes`, `apple_notes_search_notes`). Reconciles drift
  between code shipped 2026-05-23 PR #2 and catalog declaration.
- Platform bump `.macOS(.v13) → .macOS(.v14)` to satisfy the
  `stallari-mcp-helpers-swift` minimum platform.
- Retained `metaQueryDigest(_:)` and `Duration.toMilliseconds()` as blade-local
  helpers in a new `Sources/AppleNotesBlade/MetaHelpers.swift` — these are NOT
  part of the canonical surface.

### Removed

- `Sources/AppleNotesBlade/MetaEnvelope.swift` (replaced by the canonical
  `MCPHelpers` SPM dep).

## [0.2.0] - 2026-05-23

### Added

- First Swift-blade `_meta:` envelope emission across 3 tools
  (`apple_notes_list_folders`, `apple_notes_list_notes`,
  `apple_notes_search_notes`). DD-338 Phase C Wave 5 audit_surface promotion.
