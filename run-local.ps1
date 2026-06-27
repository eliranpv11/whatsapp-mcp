# Runs the LOCAL whatsapp-mcp.ps1 after verifying its SHA-256 against a pinned
# hash, so a tampered local copy cannot run silently. After auditing the manager
# script, put its SHA-256 in $PinnedHash below (Get-FileHash whatsapp-mcp.ps1).

$ErrorActionPreference = 'Stop'

$ScriptPath = Join-Path $PSScriptRoot 'whatsapp-mcp.ps1'
$PinnedHash = 'F52C9CE809E3037884CC525320CECA37E50AF0BCEB050A4B533CE5EE69219725'

if (-not (Test-Path $ScriptPath)) {
    Write-Host "whatsapp-mcp.ps1 not found next to this launcher." -ForegroundColor Red
    [void](Read-Host "Press Enter to exit"); exit 1
}

$actual = (Get-FileHash $ScriptPath -Algorithm SHA256).Hash
if ($actual -ne $PinnedHash) {
    Write-Host "[!] HASH MISMATCH - refusing to run." -ForegroundColor Red
    Write-Host "    expected: $PinnedHash"
    Write-Host "    actual:   $actual"
    Write-Host "Re-audit whatsapp-mcp.ps1, then update the pinned hash."
    [void](Read-Host "Press Enter to exit"); exit 1
}

Write-Host "[+] Hash verified. Launching the manager..." -ForegroundColor Green
Start-Process powershell.exe -ArgumentList '-NoProfile','-NoExit','-ExecutionPolicy','Bypass','-File',"`"$ScriptPath`""
