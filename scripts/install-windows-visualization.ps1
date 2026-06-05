<#
.SYNOPSIS
Installs the aw-watcher-ask-away ActivityWatch custom visualization on Windows.

.DESCRIPTION
This installer assumes ActivityWatch is already installed and that
aw-watcher-ask-away is already available/running. It creates the visualization
HTML inside the user's ActivityWatch data directory, registers it in
aw-server.toml, and optionally restarts ActivityWatch so the custom page is
served immediately.

.PARAMETER NoRestartActivityWatch
Do not restart ActivityWatch after installation.
#>

[CmdletBinding()]
param(
    [switch]$NoRestartActivityWatch
)

$ErrorActionPreference = "Stop"

$WatcherName = "aw-watcher-ask-away"
$InstallerLogPath = Join-Path $env:LOCALAPPDATA "$WatcherName\visualization-installer.log"

function Initialize-InstallerLog {
    $logDir = Split-Path -Parent $InstallerLogPath
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    "[$(Get-Date -Format s)] Visualization installer started" | Set-Content -LiteralPath $InstallerLogPath -Encoding ASCII
}

function Write-InstallerLog {
    param([string]$Message)
    "[$(Get-Date -Format s)] $Message" | Add-Content -LiteralPath $InstallerLogPath -Encoding ASCII
}

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message"
    Write-InstallerLog $Message
}

function Get-AwServerConfigPath {
    $path = Join-Path $env:LOCALAPPDATA "activitywatch\activitywatch\aw-server\aw-server.toml"
    if (Test-Path -LiteralPath $path) {
        return $path
    }

    throw "ActivityWatch aw-server.toml was not found at: $path. Start ActivityWatch once, then run this installer again."
}

function Get-VisualizationSourcePath {
    $candidates = New-Object System.Collections.Generic.List[string]
    $candidates.Add((Join-Path $PSScriptRoot "visualization\dist\index.html"))
    $candidates.Add((Join-Path $PSScriptRoot "payload\visualization\dist\index.html"))

    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..") -ErrorAction SilentlyContinue
    if ($repoRoot) {
        $candidates.Add((Join-Path $repoRoot "visualization\dist\index.html"))
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    throw "Custom visualization index.html was not found beside the installer."
}

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Set-TomlSectionKey {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $content = $Content.TrimStart([char]0xFEFF)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($content -split "`r?`n", -1)) {
        $lines.Add($line)
    }

    $sectionHeader = "[$Section]"
    $sectionStart = -1
    $sectionEnd = $lines.Count

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq $sectionHeader) {
            $sectionStart = $i
            break
        }
    }

    if ($sectionStart -lt 0) {
        while ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq "") {
            $lines.RemoveAt($lines.Count - 1)
        }
        if ($lines.Count -gt 0) {
            $lines.Add("")
        }
        $lines.Add($sectionHeader)
        $lines.Add("$Key = `"$Value`"")
        return ($lines -join "`r`n") + "`r`n"
    }

    for ($i = $sectionStart + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[.+\]\s*$') {
            $sectionEnd = $i
            break
        }
    }

    $keyIndex = -1
    for ($i = $sectionStart + 1; $i -lt $sectionEnd; $i++) {
        if ($lines[$i] -match "^\s*$([regex]::Escape($Key))\s*=") {
            $keyIndex = $i
            break
        }
    }

    if ($keyIndex -ge 0) {
        $lines[$keyIndex] = "$Key = `"$Value`""
    }
    else {
        $lines.Insert($sectionStart + 1, "$Key = `"$Value`"")
    }

    return ($lines -join "`r`n")
}

function Get-AwQtExePath {
    $paths = @(
        "$env:LOCALAPPDATA\Programs\ActivityWatch\aw-qt.exe",
        "$env:ProgramFiles\ActivityWatch\aw-qt.exe",
        "${env:ProgramFiles(x86)}\ActivityWatch\aw-qt.exe"
    )

    foreach ($path in $paths) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            return $path
        }
    }

    return $null
}

function Install-CustomVisualization {
    Write-Step "Installing visualization HTML"

    $source = Get-VisualizationSourcePath
    $targetDir = Join-Path $env:LOCALAPPDATA "activitywatch\activitywatch\$WatcherName\visualization\dist"
    $target = Join-Path $targetDir "index.html"
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force

    Write-Step "Registering custom_static in aw-server.toml"
    $config = Get-AwServerConfigPath
    $backup = "$config.bak-$WatcherName-visualization-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item -LiteralPath $config -Destination $backup -Force

    $content = [System.IO.File]::ReadAllText($config)
    $staticPath = $targetDir.Replace("\", "/")
    $content = Set-TomlSectionKey -Content $content -Section "server.custom_static" -Key $WatcherName -Value $staticPath
    Write-Utf8NoBomFile -Path $config -Content $content

    Write-InstallerLog "Copied $source to $target"
    Write-InstallerLog "Backed up $config to $backup"
    Write-InstallerLog "Registered $WatcherName = $staticPath"
}

function Restart-ActivityWatch {
    if ($NoRestartActivityWatch) {
        return
    }

    $awQt = Get-AwQtExePath
    if (-not $awQt) {
        Write-Warning "ActivityWatch aw-qt.exe was not found. Restart ActivityWatch manually."
        return
    }

    Write-Step "Restarting ActivityWatch"
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessName -match '^aw-' -and
            $_.Path -like '*ActivityWatch*'
        } |
        Stop-Process -Force

    Start-Sleep -Seconds 2
    Start-Process -FilePath $awQt -WindowStyle Hidden
}

Initialize-InstallerLog
Install-CustomVisualization
Restart-ActivityWatch

Write-Host ""
Write-Host "Done. In ActivityWatch, add a Custom Visualization named:"
Write-Host $WatcherName
