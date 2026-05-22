<#
.SYNOPSIS
Installs aw-watcher-cursor-busy as a bundled ActivityWatch module.

.DESCRIPTION
This installer is for Windows machines that already have ActivityWatch installed
and opened at least once. It copies standalone EXE payloads into ActivityWatch's
installation directory, adds aw-watcher-cursor-busy to aw-qt autostart_modules,
removes old PATH-based launchers, and restarts ActivityWatch.
#>

[CmdletBinding()]
param(
    [switch]$NoRestartActivityWatch
)

$ErrorActionPreference = "Stop"

$WatcherName = "aw-watcher-cursor-busy"
$ReportName = "aw-cursor-busy-report"
$InstallerLogPath = Join-Path $env:LOCALAPPDATA "$WatcherName\installer.log"

function Initialize-InstallerLog {
    $logDir = Split-Path -Parent $InstallerLogPath
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    "[$(Get-Date -Format s)] Installer started" | Set-Content -LiteralPath $InstallerLogPath -Encoding UTF8
}

function Write-InstallerLog {
    param([string]$Message)
    "[$(Get-Date -Format s)] $Message" | Add-Content -LiteralPath $InstallerLogPath -Encoding UTF8
}

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message"
    Write-InstallerLog $Message
}

function Get-AwQtConfigPath {
    $path = Join-Path $env:LOCALAPPDATA "activitywatch\activitywatch\aw-qt\aw-qt.toml"
    if (Test-Path -LiteralPath $path) {
        return $path
    }

    throw "ActivityWatch aw-qt.toml was not found at: $path. Start ActivityWatch once, then run this installer again."
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

function Stop-CursorBusyProcesses {
    Write-Step "Stopping existing cursor-busy processes, if present"
    $currentPid = $PID

    Get-CimInstance Win32_Process |
        Where-Object {
            $_.ProcessId -ne $currentPid -and
            (
                $_.Name -like "*cursor-busy*" -or
                ($_.Name -match "^pythonw?\.exe$" -and $_.CommandLine -like "*cursor-busy*")
            )
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }

    Start-Sleep -Seconds 1
}

function Install-BundledExe {
    param(
        [Parameter(Mandatory = $true)][string]$ModuleName
    )

    $payload = Join-Path $PSScriptRoot "$ModuleName.exe"
    if (-not (Test-Path -LiteralPath $payload)) {
        throw "Payload EXE not found: $payload"
    }

    $awQt = Get-AwQtExePath
    if (-not $awQt) {
        throw "ActivityWatch aw-qt.exe was not found."
    }

    $awRoot = Split-Path -Parent $awQt
    $moduleDir = Join-Path $awRoot $ModuleName
    $target = Join-Path $moduleDir "$ModuleName.exe"

    New-Item -ItemType Directory -Path $moduleDir -Force | Out-Null
    Copy-Item -LiteralPath $payload -Destination $target -Force
    Write-InstallerLog "Copied $payload to $target"
}

function Remove-LegacyLaunchers {
    Write-Step "Removing legacy PATH-based cursor-busy launchers"

    $candidateDirs = New-Object System.Collections.Generic.List[string]
    $candidateDirs.Add((Join-Path $env:USERPROFILE ".local\bin"))

    foreach ($base in @($env:APPDATA, $env:LOCALAPPDATA)) {
        foreach ($version in @("Python311", "Python312", "Python313", "Python314")) {
            $candidateDirs.Add((Join-Path $base "Python\$version\Scripts"))
            $candidateDirs.Add((Join-Path $base "Programs\Python\$version\Scripts"))
        }
    }

    foreach ($dir in ($candidateDirs | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            continue
        }

        foreach ($moduleName in @($WatcherName, $ReportName)) {
            foreach ($name in @("$moduleName.exe", "$moduleName-script.py", "$moduleName-script.pyw")) {
                $path = Join-Path $dir $name
                if (Test-Path -LiteralPath $path) {
                    try {
                        Remove-Item -LiteralPath $path -Force
                        Write-InstallerLog "Removed legacy launcher $path"
                    }
                    catch {
                        Write-Warning "Could not remove legacy launcher $path`: $_"
                        Write-InstallerLog "Could not remove legacy launcher $path`: $_"
                    }
                }
            }
        }
    }
}

function Format-TomlList {
    param([string[]]$Items)
    return "[" + (($Items | ForEach-Object { '"' + $_ + '"' }) -join ", ") + "]"
}

function Set-AwQtAutostartModule {
    Write-Step "Enabling $WatcherName in ActivityWatch autostart_modules"

    $config = Get-AwQtConfigPath
    $backup = "$config.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item -LiteralPath $config -Destination $backup -Force

    $lines = @(Get-Content -LiteralPath $config)
    $sectionStart = -1
    $sectionEnd = $lines.Count

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[aw-qt\]\s*$') {
            $sectionStart = $i
            break
        }
    }

    if ($sectionStart -lt 0) {
        $required = @("aw-server", "aw-watcher-afk", "aw-watcher-window", $WatcherName)
        $lines = @("[aw-qt]", "autostart_modules = $(Format-TomlList $required)", "") + $lines
        Set-Content -LiteralPath $config -Value $lines -Encoding ASCII
        return
    }

    for ($i = $sectionStart + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[.+\]\s*$') {
            $sectionEnd = $i
            break
        }
    }

    $autostartIndex = -1
    $modules = New-Object System.Collections.Generic.List[string]
    for ($i = $sectionStart + 1; $i -lt $sectionEnd; $i++) {
        if ($lines[$i] -match '^\s*#?\s*autostart_modules\s*=') {
            $autostartIndex = $i
            foreach ($match in [regex]::Matches($lines[$i], '"([^"]+)"')) {
                $modules.Add($match.Groups[1].Value)
            }
            break
        }
    }

    if ($modules.Count -eq 0) {
        foreach ($module in @("aw-server", "aw-watcher-afk", "aw-watcher-window", $WatcherName)) {
            $modules.Add($module)
        }
    }
    elseif (-not $modules.Contains($WatcherName)) {
        $modules.Add($WatcherName)
    }

    $newLine = "autostart_modules = $(Format-TomlList ($modules.ToArray()))"
    if ($autostartIndex -ge 0) {
        $lines[$autostartIndex] = $newLine
    }
    else {
        $before = $lines[0..$sectionStart]
        $after = if ($sectionStart + 1 -lt $lines.Count) { $lines[($sectionStart + 1)..($lines.Count - 1)] } else { @() }
        $lines = @($before) + @($newLine) + @($after)
    }

    Set-Content -LiteralPath $config -Value $lines -Encoding ASCII
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
            ($_.Path -like '*ActivityWatch*' -or $_.Path -like '*cursor-busy*')
        } |
        Stop-Process -Force

    Get-CimInstance Win32_Process |
        Where-Object {
            $_.Name -match '^pythonw?\.exe$' -and
            $_.CommandLine -like "*cursor-busy*"
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }

    Start-Sleep -Seconds 2
    Start-Process -FilePath $awQt -WindowStyle Hidden
}

function Assert-Installed {
    Write-Step "Verifying installation"
    Start-Sleep -Seconds 5
    $process = Get-Process -Name $WatcherName -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "$WatcherName is running."
        Write-InstallerLog "$WatcherName is running."
    }
    else {
        Write-Warning "$WatcherName is not running yet. If ActivityWatch is open, check Modules > $WatcherName or restart Windows."
        Write-InstallerLog "$WatcherName is not running after installation."
    }
}

Initialize-InstallerLog
Write-Step "Checking ActivityWatch configuration"
$null = Get-AwQtConfigPath

Stop-CursorBusyProcesses
Write-Step "Installing bundled cursor-busy executables"
Install-BundledExe $WatcherName
Install-BundledExe $ReportName
Remove-LegacyLaunchers
Set-AwQtAutostartModule
Restart-ActivityWatch
Assert-Installed

Write-Host ""
Write-Host "Done. ActivityWatch will start $WatcherName automatically with Windows through aw-qt."
