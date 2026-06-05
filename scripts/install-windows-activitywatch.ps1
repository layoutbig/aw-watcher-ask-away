<#
.SYNOPSIS
Installs aw-watcher-ask-away on Windows and enables ActivityWatch autostart.

.DESCRIPTION
This installer is meant for Windows machines that already have ActivityWatch
installed. It installs Python 3.12 for the current user when needed, installs
aw-watcher-ask-away with pipx, converts the generated launcher to a GUI launcher
so no Python console window opens, and adds aw-watcher-ask-away to aw-qt's
autostart_modules list.

.PARAMETER PackageSpec
Package spec passed to pipx. When omitted, the installer first looks for an
embedded wheel in .\payload and falls back to the PyPI package name. From a
local checkout, you can pass "." to install the local source tree.

.PARAMETER NoPythonInstall
Fail instead of downloading and installing Python 3.12 when no compatible
Python is found.

.PARAMETER NoRestartActivityWatch
Do not restart ActivityWatch after installation.
#>

[CmdletBinding()]
param(
    [string]$PackageSpec = "",
    [switch]$NoPythonInstall,
    [switch]$NoRestartActivityWatch
)

$ErrorActionPreference = "Stop"

$PythonVersion = "3.12.10"
$PythonInstallerUrl = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe"
$WatcherName = "aw-watcher-ask-away"
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

function Resolve-PackageSpec {
    if ($PackageSpec) {
        return $PackageSpec
    }

    $payloadDir = Join-Path $PSScriptRoot "payload"
    if (Test-Path -LiteralPath $payloadDir) {
        $wheel = Get-ChildItem -LiteralPath $payloadDir -Filter "aw_watcher_ask_away-*.whl" |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($wheel) {
            return $wheel.FullName
        }
    }

    $wheel = Get-ChildItem -LiteralPath $PSScriptRoot -Filter "aw_watcher_ask_away-*.whl" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($wheel) {
        return $wheel.FullName
    }

    return $WatcherName
}

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message"
    Write-InstallerLog $Message
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($Arguments -join ' ')"
    }
}

function Invoke-NativeCapture {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $previousErrorActionPreference = $ErrorActionPreference

    try {
        $ErrorActionPreference = "Continue"
        $output = & $FilePath @Arguments 2>$null
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) {
            $exitCode = 0
        }

        return [pscustomobject]@{
            ExitCode = $exitCode
            Stdout = (($output | Where-Object { $_ }) -join [Environment]::NewLine)
        }
    }
    catch {
        return [pscustomobject]@{
            ExitCode = 1
            Stdout = ""
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

function Test-CompatiblePython {
    param([string]$PythonExe)

    if (-not (Test-Path -LiteralPath $PythonExe)) {
        return $false
    }

    $result = Invoke-NativeCapture $PythonExe @(
        "-c",
        "import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)"
    )
    return ($result.ExitCode -eq 0)
}

function Get-PythonExe {
    $candidates = New-Object System.Collections.Generic.List[string]

    foreach ($path in @(
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python314\python.exe"
    )) {
        $candidates.Add($path)
    }

    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        $candidates.Add($python.Source)
    }

    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        foreach ($version in @("3.12", "3.11", "3.13", "3.14")) {
            $result = Invoke-NativeCapture $py.Source @(
                "-$version",
                "-c",
                "import sys; print(sys.executable)"
            )
            if ($result.ExitCode -eq 0 -and $result.Stdout) {
                $pythonPath = ($result.Stdout -split "`r?`n" | Where-Object { $_ } | Select-Object -First 1)
                if ($pythonPath) {
                    $candidates.Add($pythonPath)
                }
            }
        }
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-CompatiblePython $candidate) {
            return $candidate
        }
    }

    return $null
}

function Install-PythonForCurrentUser {
    if ($NoPythonInstall) {
        throw "Python 3.11+ was not found, and -NoPythonInstall was specified."
    }

    Write-Step "Installing Python $PythonVersion for current user"
    $installer = Join-Path $env:TEMP "python-$PythonVersion-amd64.exe"
    Invoke-WebRequest -Uri $PythonInstallerUrl -OutFile $installer

    $args = "/quiet InstallAllUsers=0 PrependPath=1 Include_test=0 Include_launcher=1 Include_pip=1"
    $process = Start-Process -FilePath $installer -ArgumentList $args -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Python installer failed with exit code $($process.ExitCode)."
    }

    $python = Get-PythonExe
    if (-not $python) {
        throw "Python was installed, but no compatible python.exe was found."
    }

    return $python
}

function Install-PipxAndWatcher {
    param([string]$PythonExe)

    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot "$WatcherName.exe")) {
        Write-Step "Standalone watcher payload found; skipping pipx watcher install"
        return
    }

    $resolvedPackageSpec = Resolve-PackageSpec

    Write-Step "Installing pipx"
    Invoke-Checked $PythonExe @("-m", "pip", "install", "--user", "pipx")

    Write-Step "Ensuring pipx PATH entries"
    Invoke-Checked $PythonExe @("-m", "pipx", "ensurepath")

    Write-Step "Installing $WatcherName with pipx from $resolvedPackageSpec"
    Invoke-Checked $PythonExe @("-m", "pipx", "install", $resolvedPackageSpec, "--python", $PythonExe, "--force")
}

function Stop-AskAwayProcesses {
    Write-Step "Stopping existing $WatcherName processes, if present"

    Get-Process -Name $WatcherName -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue

    Get-CimInstance Win32_Process |
        Where-Object {
            $_.Name -match '^pythonw?\.exe$' -and
            $_.CommandLine -like "*$WatcherName*"
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }

    Start-Sleep -Seconds 1
}

function Convert-WatcherLauncherToGui {
    param([string]$PythonExe)

    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot "$WatcherName.exe")) {
        Write-Step "Standalone watcher payload found; skipping pipx launcher conversion"
        return
    }

    Write-Step "Converting $WatcherName launcher to pythonw.exe"

    $userBin = Join-Path $env:USERPROFILE ".local\bin"
    $launcher = Join-Path $userBin "$WatcherName.exe"
    if (-not (Test-Path -LiteralPath $launcher)) {
        throw "Expected launcher was not found: $launcher"
    }

    $backupDir = Join-Path $env:LOCALAPPDATA $WatcherName
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $backup = Join-Path $backupDir "$WatcherName.console.exe"
    if (-not (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $launcher -Destination $backup -Force
    }

    $pipxHome = if ($env:PIPX_HOME) { $env:PIPX_HOME } else { Join-Path $env:USERPROFILE "pipx" }
    $venvPython = Join-Path $pipxHome "venvs\$WatcherName\Scripts\python.exe"
    if (-not (Test-Path -LiteralPath $venvPython)) {
        $venvPython = $PythonExe
    }

    $script = @"
# -*- coding: utf-8 -*-
from pip._vendor.distlib.scripts import ScriptMaker
import os

target = os.path.expanduser(r"$userBin")
maker = ScriptMaker(None, target)
maker.clobber = True
maker.variants = {""}
maker.executable = r"$venvPython"
maker.make("$WatcherName = aw_watcher_ask_away.__main__:main", options={"gui": True})
"@

    $tmp = Join-Path $env:TEMP "$WatcherName-gui-launcher.py"
    Set-Content -LiteralPath $tmp -Value $script -Encoding UTF8
    Invoke-Checked $PythonExe @($tmp)

    $duplicate = Join-Path $userBin "$WatcherName.console.exe"
    if (Test-Path -LiteralPath $duplicate) {
        Remove-Item -LiteralPath $duplicate -Force
    }
}

function Install-ActivityWatchModuleShim {
    Write-Step "Installing $WatcherName inside ActivityWatch modules folder"

    $awQt = Get-AwQtExePath
    if (-not $awQt) {
        Write-Warning "ActivityWatch aw-qt.exe was not found. Falling back to PATH-based module discovery."
        return
    }

    $standaloneLauncher = Join-Path $PSScriptRoot "$WatcherName.exe"
    $sourceLauncher = if (Test-Path -LiteralPath $standaloneLauncher) {
        $standaloneLauncher
    }
    else {
        Join-Path $env:USERPROFILE ".local\bin\$WatcherName.exe"
    }

    if (-not (Test-Path -LiteralPath $sourceLauncher)) {
        Write-Warning "Expected $WatcherName launcher was not found at $sourceLauncher"
        Write-InstallerLog "Expected launcher not found at $sourceLauncher"
        return
    }

    $awRoot = Split-Path -Parent $awQt
    $moduleDir = Join-Path $awRoot $WatcherName
    $targetLauncher = Join-Path $moduleDir "$WatcherName.exe"

    try {
        New-Item -ItemType Directory -Path $moduleDir -Force | Out-Null
        Copy-Item -LiteralPath $sourceLauncher -Destination $targetLauncher -Force
        Write-InstallerLog "Copied $sourceLauncher to $targetLauncher"
    }
    catch {
        Write-Warning "Could not copy $WatcherName into ActivityWatch modules folder: $_"
        Write-InstallerLog "Could not copy launcher into ActivityWatch modules folder: $_"
    }
}

function Remove-LegacySystemLaunchers {
    Write-Step "Removing legacy PATH-based $WatcherName launchers"

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

        foreach ($name in @("$WatcherName.exe", "$WatcherName.console.exe", "$WatcherName-script.py", "$WatcherName-script.pyw")) {
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

function Remove-LegacyPipxInstall {
    Write-Step "Removing legacy pipx $WatcherName install, if present"

    $pipxHome = if ($env:PIPX_HOME) { $env:PIPX_HOME } else { Join-Path $env:USERPROFILE "pipx" }
    $venvDir = Join-Path $pipxHome "venvs\$WatcherName"
    if (Test-Path -LiteralPath $venvDir) {
        try {
            Remove-Item -LiteralPath $venvDir -Recurse -Force
            Write-InstallerLog "Removed legacy pipx venv $venvDir"
        }
        catch {
            Write-Warning "Could not remove legacy pipx venv $venvDir`: $_"
            Write-InstallerLog "Could not remove legacy pipx venv $venvDir`: $_"
        }
    }
}

function Remove-SeparateStartupShortcut {
    Write-Step "Removing separate Windows Startup shortcut, if present"
    $startup = [Environment]::GetFolderPath("Startup")
    $shortcut = Join-Path $startup "$WatcherName.lnk"
    if (Test-Path -LiteralPath $shortcut) {
        Remove-Item -LiteralPath $shortcut -Force
    }
}

function Get-AwQtConfigPath {
    $path = Join-Path $env:LOCALAPPDATA "activitywatch\activitywatch\aw-qt\aw-qt.toml"
    if (Test-Path -LiteralPath $path) {
        return $path
    }

    throw "ActivityWatch aw-qt.toml was not found at: $path. Start ActivityWatch once, then run this installer again."
}

function Format-TomlList {
    param([string[]]$Items)
    return "[" + (($Items | ForEach-Object { '"' + $_ + '"' }) -join ", ") + "]"
}

function Set-AwQtAutostartModules {
    Write-Step "Enabling $WatcherName in ActivityWatch autostart_modules"

    $config = Get-AwQtConfigPath
    $backup = "$config.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item -LiteralPath $config -Destination $backup -Force

    $required = @("aw-server", "aw-watcher-afk", "aw-watcher-window", $WatcherName)
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
        foreach ($module in $required) {
            $modules.Add($module)
        }
    }
    else {
        foreach ($module in $required) {
            if (-not $modules.Contains($module)) {
                $modules.Add($module)
            }
        }
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
            ($_.Path -like '*ActivityWatch*' -or $_.Path -like "*$WatcherName*")
        } |
        Stop-Process -Force

    Get-CimInstance Win32_Process |
        Where-Object {
            $_.Name -match '^pythonw?\.exe$' -and
            $_.CommandLine -like "*$WatcherName*"
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

Stop-AskAwayProcesses

$standalonePayload = Join-Path $PSScriptRoot "$WatcherName.exe"
if (Test-Path -LiteralPath $standalonePayload) {
    Write-Step "Using standalone watcher payload: $standalonePayload"
}
else {
    $python = Get-PythonExe
    if (-not $python) {
        $python = Install-PythonForCurrentUser
    }

    Write-Step "Using Python: $python"
    Install-PipxAndWatcher $python
    Convert-WatcherLauncherToGui $python
}

Install-ActivityWatchModuleShim
Remove-LegacySystemLaunchers
Remove-LegacyPipxInstall
Remove-SeparateStartupShortcut
Set-AwQtAutostartModules
Restart-ActivityWatch
Assert-Installed

Write-Host ""
Write-Host "Done. ActivityWatch will start $WatcherName automatically with Windows through aw-qt."
