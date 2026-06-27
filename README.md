# WhatsApp MCP - Installer

A one-command installer that connects your personal WhatsApp to Claude Desktop,
with a simple menu to **install / uninstall / update** and optional automatic
updates. No coding required.

> Built on the proven architecture of
> [claude-desktop-rtl-patch](https://github.com/shraga100/claude-desktop-rtl-patch).

---

## התקנה מהירה (עברית)

1. פתח **PowerShell** והדבק:
   ```powershell
   irm https://raw.githubusercontent.com/eliranpv11/whatsapp-mcp/main/install.ps1 | iex
   ```
2. ייפתח תפריט - בחר **1 (התקנה)**.
3. סרוק את קוד ה-QR מהוואטסאפ בטלפון.
4. פתח מחדש את Claude Desktop. זהו!

להסרה מלאה - הרץ שוב ובחר **2**.

---

## What it does

- Downloads a **pure-Go WhatsApp bridge** (a single static `.exe`, no Python /
  no C compiler / no admin needed) plus a bundled MCP server.
- Registers the connector in `claude_desktop_config.json` so Claude Desktop can
  read and send your WhatsApp messages through MCP tools.
- Always **closes Claude Desktop before editing its config**, so the running app
  cannot re-add the entry (a problem with naive config edits).

## Menu

```
1. Install WhatsApp connector
2. Uninstall completely (connector + local data)
3. Update now
4. Enable automatic updates
5. Disable automatic updates
6. Exit
```

## Security

- All binaries are downloaded over **HTTPS** from this repo's GitHub Releases and
  verified against **SHA-256** (`SHA256SUMS`) before they run. A tampered or
  corrupted download is rejected.
- The config is **backed up** before every change and validated as JSON.
- `run-local.ps1` verifies the manager script's own SHA-256 against a pinned hash.
- Unsigned executables trigger a one-time Windows **SmartScreen** prompt
  (More info -> Run anyway). Code-signing removes it (optional).
- The connector reads your private messages locally and (by design) exposes them
  to Claude. Treat incoming WhatsApp text as untrusted - see "the lethal trifecta".

## For maintainers

- `bridge-src/`  - the Go bridge (pure-Go SQLite via `modernc.org/sqlite`).
- `mcp-server-src/` - the Python MCP server (bundled to `mcp-server.exe`).
- `.github/workflows/build.yml` - on a `v*` tag, builds both binaries, computes
  `SHA256SUMS`, and publishes a Release. Tag a version and CI does the rest.
- Fill `eliranpv11/whatsapp-mcp` (in `install.ps1` and `whatsapp-mcp.ps1`) and
  the pinned hash in `run-local.ps1` before publishing.

## Status (built & verified locally)

- Bridge converted to pure-Go and **compiles statically with no CGO** (verified).
- Timestamp **round-trip Go->Python verified** (`datetime.fromisoformat` parses).
- Manager config-injection / removal **unit-tested in isolation** (verified).
- Not yet run on real GitHub CI or against a live Claude Desktop install -
  those require a published repo + a human QR scan.
