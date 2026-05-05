import Foundation

// MARK: - Public model types
//
// These shapes are what the tool handlers return. They serialise to JSON via
// Codable; field naming uses camelCase on the wire because consumers are
// internal Stallari skills which already speak camelCase. If we ever add an
// external surface, a separate adapter layer can re-key these to snake_case.

public struct Account: Codable, Sendable, Equatable {
    public let id: Int64
    public let name: String
    public let identifier: String?  // Apple Notes account identifier (usually iCloud / On-My-Mac)
}

public struct Folder: Codable, Sendable, Equatable {
    public let id: Int64
    public let accountID: Int64?
    public let name: String
    public let isDefault: Bool
    public let noteCount: Int
}

public struct NoteSummary: Codable, Sendable, Equatable {
    public let id: Int64
    public let folderID: Int64?
    public let title: String
    public let snippet: String?  // From ZSNIPPET — no body decode
    public let modifiedAt: Date?
    public let createdAt: Date?
    public let hasAttachments: Bool
    public let isPinned: Bool
}

public struct NoteHead: Codable, Sendable, Equatable {
    public let id: Int64
    public let folderID: Int64?
    public let title: String
    public let modifiedAt: Date?
    public let createdAt: Date?
    public let hasAttachments: Bool
    public let attachmentCount: Int
    public let bodyByteLength: Int?  // ZICNOTEDATA.ZDATA length; nil if no body row
    public let isPinned: Bool
}

public struct AttachmentMeta: Codable, Sendable, Equatable {
    public let id: Int64
    public let filename: String?
    public let typeUTI: String?
    public let byteLength: Int?
}

public struct Note: Codable, Sendable, Equatable {
    public let id: Int64
    public let folderID: Int64?
    public let title: String
    public let bodyText: String?
    public let bodyHTML: String?  // Always nil in v0.1.0 (deferred — see plan)
    public let modifiedAt: Date?
    public let createdAt: Date?
    public let attachments: [AttachmentMeta]
    /// Set to `true` when `include_html: true` was requested but HTML rendering
    /// is not yet implemented. Consumers should treat this as a soft signal,
    /// not an error.
    public let htmlNotImplemented: Bool
}
