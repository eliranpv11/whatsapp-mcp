<#
.SYNOPSIS
    WhatsApp MCP -Connector Manager for Claude Desktop.
.DESCRIPTION
    Installs / uninstalls / updates the WhatsApp MCP connector with a menu.
    No admin required. Always closes Claude Desktop before editing its config
    so the running app cannot re-add ("clobber") the entry.

    Modeled on the architecture of shraga100/claude-desktop-rtl-patch.
#>
param([switch]$Auto, [string]$Action)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# CONFIGURATION  (the maintainer fills RepoSlug before publishing)
# ---------------------------------------------------------------------------
$RepoSlug     = 'eliranpv11/whatsapp-mcp'                 # GitHub owner/repo
$InstallDir   = Join-Path $env:LOCALAPPDATA 'whatsapp-mcp'
$StateFile    = Join-Path $InstallDir 'state.json'
$BridgeExe    = Join-Path $InstallDir 'whatsapp-bridge.exe'
$McpExe       = Join-Path $InstallDir 'mcp-server.exe'
$TaskName     = 'WhatsAppMcpUpdater'
$ClaudeCfg    = Join-Path $env:APPDATA 'Claude\claude_desktop_config.json'
$ConnectorKey = 'whatsapp'

function Write-Log  ($m) { Write-Host "  [*] $m" -ForegroundColor Cyan }
function Write-Ok   ($m) { Write-Host "  [+] $m" -ForegroundColor Green }
function Write-Warn ($m) { Write-Host "  [!] $m" -ForegroundColor Yellow }
function Write-Step ($m) { Write-Host "`n> $m" -ForegroundColor Magenta }

# ---------------------------------------------------------------------------
# CLAUDE DESKTOP -find config, close app (prevents config clobbering)
# ---------------------------------------------------------------------------
function Find-ClaudeConfig {
    if (-not (Test-Path $ClaudeCfg)) {
        throw "Claude Desktop config not found at $ClaudeCfg. Is Claude Desktop installed?"
    }
    return $ClaudeCfg
}

function Stop-ClaudeDesktop {
    $procs = Get-Process -Name 'Claude' -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Log "Closing Claude Desktop (so it can't re-add the connector)..."
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    } else {
        Write-Log "Claude Desktop is not running."
    }
}

function Start-ClaudeDesktop {
    try {
        $pkg = Get-AppxPackage | Where-Object { $_.Name -like '*Claude*' } | Select-Object -First 1
        if ($pkg) { Start-Process "shell:AppsFolder\$($pkg.PackageFamilyName)!Claude" -ErrorAction Stop; Write-Ok "Claude Desktop launched." }
    } catch { Write-Warn "Could not auto-launch Claude Desktop; start it from the Start Menu." }
}

# ---------------------------------------------------------------------------
# CONFIG EDITING  (JSON-aware; testable -takes an explicit path)
# Always make a timestamped backup, validate JSON, write UTF-8 without BOM.
# ---------------------------------------------------------------------------
function Backup-Config([string]$Path) {
    $bak = "$Path.bak-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
    Copy-Item -LiteralPath $Path -Destination $bak -Force
    return $bak
}

function Write-JsonFile([string]$Path, $Object) {
    $json = $Object | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Add-Connector {
    param([Parameter(Mandatory)][string]$ConfigPath,
          [Parameter(Mandatory)][string]$Command,
          [string[]]$Args = @())
    $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    if ($null -eq $cfg.mcpServers) {
        $cfg | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    $entry = [PSCustomObject]@{ command = $Command; args = $Args }
    $cfg.mcpServers | Add-Member -NotePropertyName $ConnectorKey -NotePropertyValue $entry -Force
    Write-JsonFile $ConfigPath $cfg
}

function Remove-Connector {
    param([Parameter(Mandatory)][string]$ConfigPath)
    $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    if ($cfg.PSObject.Properties.Name -contains 'mcpServers' -and $cfg.mcpServers) {
        if ($cfg.mcpServers.PSObject.Properties.Name -contains $ConnectorKey) {
            $cfg.mcpServers.PSObject.Properties.Remove($ConnectorKey)
        }
        # If mcpServers is now empty, drop it entirely to keep the file clean.
        if (-not $cfg.mcpServers.PSObject.Properties.Name) {
            $cfg.PSObject.Properties.Remove('mcpServers')
        }
    }
    Write-JsonFile $ConfigPath $cfg
}

# ---------------------------------------------------------------------------
# VERIFIED DOWNLOAD  (HTTPS + SHA-256 against SHA256SUMS in the Release)
# ---------------------------------------------------------------------------
function Get-VerifiedFile {
    param([Parameter(Mandatory)][string]$Url,
          [Parameter(Mandatory)][string]$OutFile,
          [Parameter(Mandatory)][string]$ExpectedSha256)
    Write-Log "Downloading $(Split-Path $OutFile -Leaf)..."
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
    $actual = (Get-FileHash $OutFile -Algorithm SHA256).Hash
    if ($actual -ne $ExpectedSha256.ToUpper()) {
        Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
        throw "SHA-256 MISMATCH for $(Split-Path $OutFile -Leaf).`n  expected: $ExpectedSha256`n  actual:   $actual`nRefusing to use a tampered/corrupt download."
    }
    Write-Ok "Verified SHA-256: $(Split-Path $OutFile -Leaf)"
}

function Get-LatestRelease {
    $api = "https://api.github.com/repos/$RepoSlug/releases/latest"
    return Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'whatsapp-mcp-installer' }
}

# ---------------------------------------------------------------------------
# STATE
# ---------------------------------------------------------------------------
function Save-State([string]$Version) {
    if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null }
    @{ version = $Version; installedAt = (Get-Date).ToUniversalTime().ToString('o') } |
        ConvertTo-Json | Set-Content -Path $StateFile -Encoding UTF8
}
function Get-StateVersion {
    if (-not (Test-Path $StateFile)) { return $null }
    try { return (Get-Content $StateFile -Raw | ConvertFrom-Json).version } catch { return $null }
}

# ---------------------------------------------------------------------------
# INSTALL / UNINSTALL / UPDATE
# ---------------------------------------------------------------------------
function Install-Connector {
    Write-Step "Installing WhatsApp MCP connector"
    $cfg = Find-ClaudeConfig
    Stop-ClaudeDesktop

    if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null }

    $rel = Get-LatestRelease
    $ver = $rel.tag_name
    Write-Log "Latest release: $ver"
    foreach ($name in @('whatsapp-bridge.exe','mcp-server.exe')) {
        $asset = $rel.assets | Where-Object { $_.name -eq $name } | Select-Object -First 1
        $sha   = ($rel.assets | Where-Object { $_.name -eq 'SHA256SUMS' } | Select-Object -First 1)
        if (-not $asset) { throw "Release asset '$name' not found in $ver." }
        $sums = (Invoke-WebRequest -Uri $sha.browser_download_url -UseBasicParsing).Content
        $expected = ($sums -split "`n" | Where-Object { $_ -match [regex]::Escape($name) } | Select-Object -First 1).Split(' ')[0]
        Get-VerifiedFile -Url $asset.browser_download_url -OutFile (Join-Path $InstallDir $name) -ExpectedSha256 $expected
    }

    Write-Step "Registering connector in Claude Desktop config"
    $bak = Backup-Config $cfg
    Write-Log "Backup: $bak"
    Add-Connector -ConfigPath $cfg -Command $McpExe -Args @()
    Write-Ok "Connector registered (points to $McpExe)."

    Save-State $ver
    Write-Step "Starting the bridge -scan the QR with your phone"
    Start-Process -FilePath $BridgeExe -WorkingDirectory $InstallDir
    Write-Ok "Bridge started. After you scan the QR, reopen Claude Desktop."

    if (-not $Auto) {
        $a = Read-Host "Enable automatic updates? (Y/n)"
        if ($a -ne 'n' -and $a -ne 'N') { Install-AutoUpdate }
    }
    Write-Ok "Install complete."
}

function Uninstall-Connector {
    Write-Step "Removing WhatsApp MCP connector completely"
    $cfg = Find-ClaudeConfig
    Stop-ClaudeDesktop

    Get-Process -Name 'whatsapp-bridge' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Remove-AutoUpdate

    $bak = Backup-Config $cfg
    Write-Log "Backup: $bak"
    Remove-Connector -ConfigPath $cfg
    Write-Ok "Connector removed from config."

    if (Test-Path $InstallDir) {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Ok "Removed $InstallDir (exes + local message DB)."
    }
    Write-Warn "Final step (privacy): on your phone, WhatsApp -> Linked Devices -> remove the linked device."
    Write-Ok "Uninstall complete."
}

function Update-Connector {
    Write-Step "Updating to the latest bridge"
    Stop-ClaudeDesktop
    Get-Process -Name 'whatsapp-bridge' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $rel = Get-LatestRelease
    $ver = $rel.tag_name
    if ($ver -eq (Get-StateVersion)) { Write-Ok "Already on the latest version ($ver)."; return }
    foreach ($name in @('whatsapp-bridge.exe','mcp-server.exe')) {
        $asset = $rel.assets | Where-Object { $_.name -eq $name } | Select-Object -First 1
        $sha   = ($rel.assets | Where-Object { $_.name -eq 'SHA256SUMS' } | Select-Object -First 1)
        $sums  = (Invoke-WebRequest -Uri $sha.browser_download_url -UseBasicParsing).Content
        $expected = ($sums -split "`n" | Where-Object { $_ -match [regex]::Escape($name) } | Select-Object -First 1).Split(' ')[0]
        Get-VerifiedFile -Url $asset.browser_download_url -OutFile (Join-Path $InstallDir $name) -ExpectedSha256 $expected
    }
    Save-State $ver
    Write-Ok "Updated to $ver. Restart the bridge to apply."
}

# ---------------------------------------------------------------------------
# AUTO-UPDATE  (Scheduled Task at logon, checks GitHub releases)
# ---------------------------------------------------------------------------
function Install-AutoUpdate {
    Write-Step "Enabling automatic updates (Scheduled Task)"
    $cmd = "& '$PSCommandPath' -Auto -Action update"
    $action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"$cmd`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $set     = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $set -Force | Out-Null
    Write-Ok "Auto-update task '$TaskName' installed (runs at logon)."
}

function Remove-AutoUpdate {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Ok "Auto-update task removed."
    }
}

# ---------------------------------------------------------------------------
# MENU
# ---------------------------------------------------------------------------
function Show-Menu {
    Clear-Host
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "       WhatsApp MCP  -  Connector Manager"          -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. Install WhatsApp connector"
    Write-Host "  2. Uninstall completely (connector + local data)"
    Write-Host "  3. Update now"
    Write-Host "  4. Enable automatic updates"
    Write-Host "  5. Disable automatic updates"
    Write-Host "  6. Exit"
    $c = Read-Host "`nChoose (1-6)"
    try {
        switch ($c) {
            '1' { Install-Connector }
            '2' { Uninstall-Connector }
            '3' { Update-Connector }
            '4' { Install-AutoUpdate }
            '5' { Remove-AutoUpdate }
            '6' { return }
            default { Show-Menu; return }
        }
    } catch {
        Write-Host "`n[X] $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host "`nPress Enter to return to the menu..."; [void](Read-Host)
    Show-Menu
}

# ---------------------------------------------------------------------------
# ENTRY
# ---------------------------------------------------------------------------
# Only run when executed directly. Dot-sourcing (for tests) loads functions only.
if ($MyInvocation.InvocationName -ne '.') {
    if ($Action) {
        switch ($Action) {
            'install'   { Install-Connector }
            'uninstall' { Uninstall-Connector }
            'update'    { Update-Connector }
            default     { Write-Warn "Unknown action: $Action" }
        }
    } else {
        Show-Menu
    }
}
