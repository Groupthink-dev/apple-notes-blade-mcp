import Foundation

/// apple-notes-blade-mcp — Stallari-internal blade for Apple Notes.
///
/// Read-only access to `NoteStore.sqlite` + zlib/protobuf-encoded bodies under
/// `~/Library/Group Containers/group.com.apple.notes/`. Consumed only via
/// StallariKit's internal tool registry; never exposed externally.
///
/// See `DD-240` and `directives/local-corpus-blades.md` for the class invariants
/// this blade conforms to: no probabilistic inference (NLTagger carve-out OK,
/// not in v0.1.0); read-only; hardcoded read paths; framework-deterministic
/// feature extraction allowed; no network egress.
public enum AppleNotesBlade {
    /// Library version. Bump together with the git tag.
    public static let version = "0.0.1"
}
