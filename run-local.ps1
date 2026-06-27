# Runs the LOCAL whatsapp-mcp.ps1 after verifying its SHA-256 against a pinned
# hash, so a tampered local copy cannot run silently. After auditing the manager
# script, put its SHA-256 in $PinnedHash below (Get-FileHash whatsapp-mcp.ps1).

$ErrorActionPreference = 'Stop'

$ScriptPath = Join-Path $PSScriptRoot 'whatsapp-mcp.ps1'
$PinnedHash = '1A44194A590DF999FD249DBCA1EA526FD83CBA3B8E243343CF6DCDE35B2F1872'

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
