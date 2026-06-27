# WhatsApp MCP - one-command installer (bootstrap).
#
# Usage (paste into PowerShell):
#   irm https://raw.githubusercontent.com/eliranpv11/whatsapp-mcp/main/install.ps1 | iex
#
# Downloads the manager script and opens its menu. No admin required.

$ErrorActionPreference = 'Stop'

$RepoSlug = 'eliranpv11/whatsapp-mcp'
$Url = "https://raw.githubusercontent.com/$RepoSlug/main/whatsapp-mcp.ps1"
$Tmp = Join-Path $env:TEMP 'whatsapp-mcp.ps1'

Write-Host "Downloading the WhatsApp MCP manager..." -ForegroundColor Cyan
$content = Invoke-RestMethod -Uri $Url

# Strip a leading BOM (Invoke-RestMethod keeps it) and re-save with a real
# UTF-8 BOM so Windows PowerShell 5.1 parses it correctly even if it ever
# contains non-ASCII text.
if ($content.Length -gt 0 -and $content[0] -eq [char]0xFEFF) { $content = $content.Substring(1) }
[System.IO.File]::WriteAllText($Tmp, $content, (New-Object System.Text.UTF8Encoding($true)))

Write-Host "Launching the manager (in this window)..." -ForegroundColor Green
# Run the manager INLINE in this same window instead of spawning a new one, so
# the whole flow (menu -> install -> bridge/QR) lives in a single window.
try { Set-ExecutionPolicy -Scope Process Bypass -Force -ErrorAction SilentlyContinue } catch {}
& $Tmp
