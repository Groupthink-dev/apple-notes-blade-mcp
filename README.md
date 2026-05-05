# apple-notes-blade-mcp

**Status:** Phase A scaffold — see [DD-240](https://github.com/Groupthink-dev/) and `DD-240-phase-A-implementation-plan` in the Stallari vault. Full README ships in A.4.

Stallari-internal Swift library blade for read-only access to Apple Notes (`NoteStore.sqlite` + zlib/protobuf bodies). Consumed only via StallariKit's internal tool registry; never exposed on the daemon's public `:9847/mcp` HTTP MCP surface.

## Audience

Future me + future architect sessions. **This is not a third-party MCP server.** There is no notarised installer, no Claude Desktop config snippet, no PyPI/Homebrew distribution.

## Class

First concrete blade under DD-240's local-corpus class. Sibling: `apple-mail-blade-mcp` (DD-241, Phase B). Existing kin: `apple-reminders-blade-mcp` (Python, EventKit-via-pyobjc carve-out).

## Build

```sh
make build       # swift build
make test        # swift test --enable-code-coverage
make lint        # swift-format lint
make format      # swift-format auto-format
```

## License

MIT.
