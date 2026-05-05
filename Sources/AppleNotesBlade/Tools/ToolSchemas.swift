import Foundation
import MCP

/// MCP tool schema definitions for the 5 Notes tools (list_accounts elided —
/// it surfaces under list_folders' `account_id` filter rather than a top-level
/// tool).
///
/// Tool naming uses the `apple_notes_*` prefix so a future broader tool
/// catalog stays unambiguous when sibling blades (mail, etc.) join the same
/// internal registry.
public enum NotesToolSchemas {

    public static let listFolders = Tool(
        name: "apple_notes_list_folders",
        description: "List Apple Notes folders. Optional account_id filter.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "account_id": .object([
                    "type": .string("integer"),
                    "description": .string("Optional. Limit folders to this account."),
                ]),
            ]),
            "additionalProperties": .bool(false),
        ])
    )

    public static let listNotes = Tool(
        name: "apple_notes_list_notes",
        description:
            "List notes within a folder. Index-only — does NOT decode bodies. "
            + "Returns title, snippet, dates, attachment-presence flag.",
        inputSchema: .object([
            "type": .string("object"),
            "required": .array([.string("folder_id")]),
            "properties": .object([
                "folder_id": .object([
                    "type": .string("integer"),
                    "description": .string("Folder primary key (Z_PK from list_folders)."),
                ]),
                "since": .object([
                    "type": .string("string"),
                    "format": .string("date-time"),
                    "description": .string("Optional. ISO-8601 lower bound on modification date."),
                ]),
                "limit": .object([
                    "type": .string("integer"),
                    "minimum": .int(1),
                    "maximum": .int(1000),
                    "default": .int(100),
                ]),
                "offset": .object([
                    "type": .string("integer"),
                    "minimum": .int(0),
                    "default": .int(0),
                ]),
            ]),
            "additionalProperties": .bool(false),
        ])
    )

    public static let readNote = Tool(
        name: "apple_notes_read_note",
        description:
            "Read a single note's body. Inflates the gzip-compressed protobuf "
            + "and extracts plain text + attachment metadata. HTML rendering "
            + "is deferred — passing include_html: true returns a soft signal "
            + "(htmlNotImplemented: true) rather than an error.",
        inputSchema: .object([
            "type": .string("object"),
            "required": .array([.string("id")]),
            "properties": .object([
                "id": .object([
                    "type": .string("integer"),
                    "description": .string("Note primary key (Z_PK from list_notes)."),
                ]),
                "include_html": .object([
                    "type": .string("boolean"),
                    "default": .bool(false),
                    "description": .string("Reserved. Always returns null in v0.1.0."),
                ]),
            ]),
            "additionalProperties": .bool(false),
        ])
    )

    /// All schemas in registration order. Phase A.1+A.2 ships three; A.3 adds
    /// `search_notes` + `head`.
    public static func all() -> [Tool] {
        [listFolders, listNotes, readNote]
    }
}
