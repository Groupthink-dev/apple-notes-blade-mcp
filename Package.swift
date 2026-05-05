// swift-tools-version: 5.9
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
// MCP dependency uses the local swift-sdk path during dev (matches stallari-harness
// posture). Switch to git URL pinned by SHA before tagging v0.1.0 if/when the
// upstream Client EOF spin fix is merged.

let package = Package(
    name: "apple-notes-blade-mcp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "AppleNotesBlade",
            targets: ["AppleNotesBlade"]
        ),
    ],
    dependencies: [
        .package(path: "../swift-sdk"),
        // SQLite.swift without SQLCipher trait — Apple's NoteStore.sqlite is
        // plain SQLite, not encrypted. Matches stallari-vault's SQLite client
        // choice; we just don't pull in SQLCipher.
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.3"),
    ],
    targets: [
        .target(
            name: "AppleNotesBlade",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "SQLite", package: "SQLite.swift"),
            ]
        ),
        .testTarget(
            name: "AppleNotesBladeTests",
            dependencies: ["AppleNotesBlade"]
        ),
    ]
)
