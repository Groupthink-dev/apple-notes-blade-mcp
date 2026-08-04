// swift-tools-version: 6.1
import PackageDescription

// apple-notes-blade-mcp
//
// Stallari-internal Swift library blade for read-only access to Apple Notes
// (NoteStore.sqlite + zlib/protobuf bodies). Defined by DD-240; first concrete
// blade in the local-corpus class.
//
// Consumed only via StallariKit's internal tool registry. Never exposed on the
// daemon's public :9847/mcp HTTP MCP surface. See README §"No external exposure".
//
// MCP dependency tracks upstream modelcontextprotocol/swift-sdk. It was formerly
// URL-pinned to the piersdd fork (DD-295 Phase C), but that fork's 0.12.1 tag
// carried no local patches — it was a strict ancestor of upstream 0.12.1 — so the
// pin bought nothing while colliding with upstream's own 0.12.1 and freezing us
// off the upgrade path. The fork's one real patch (stallari/client-loop-no-repeat)
// is consumed only by stallari-harness.

let package = Package(
    name: "apple-notes-blade-mcp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AppleNotesBlade",
            targets: ["AppleNotesBlade"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
        // SQLite.swift with SQLCipher trait — matches stallari-harness'
        // SPM trait declaration so the merged graph resolves cleanly when
        // this library is embedded as an SPM dep. We don't *use* SQLCipher
        // (Apple's NoteStore.sqlite is plain SQLite); enabling the trait is
        // purely for resolution compatibility. The runtime SQLite client
        // exposed by the package is API-compatible across traits.
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.3", traits: ["SQLCipher"]),
        // Canonical _meta: envelope helpers (DD-338 Phase E.swift). Replaces
        // the previously hand-rolled Sources/AppleNotesBlade/MetaEnvelope.swift
        // (deleted in DD-338 Phase C Wave 5).
        .package(url: "https://github.com/Groupthink-dev/stallari-mcp-helpers-swift", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "AppleNotesBlade",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "MCPHelpers", package: "stallari-mcp-helpers-swift"),
            ]
        ),
        .testTarget(
            name: "AppleNotesBladeTests",
            dependencies: ["AppleNotesBlade"]
        ),
    ]
)
