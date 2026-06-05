<#
.SYNOPSIS
Builds a one-file Windows installer EXE for aw-watcher-ask-away.

.DESCRIPTION
The generated EXE is a PyInstaller one-file launcher with the ActivityWatch
icon. It includes:
- install-windows-activitywatch.ps1
- a local aw-watcher-ask-away wheel

The resulting installer is written to:
dist\AskAwayActivityWatchInstaller.exe
#>

[CmdletBinding()]
param(
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$DistDir = Join-Path $RepoRoot "dist"
$BuildDir = Join-Path $RepoRoot "build\windows-installer"
$PayloadDir = Join-Path $BuildDir "payload"
$InstallerScript = Join-Path $PSScriptRoot "install-windows-activitywatch.ps1"
$LauncherScript = Join-Path $PSScriptRoot "installer-launcher.py"
$WatcherLauncherScript = Join-Path $PSScriptRoot "watcher-standalone.py"

if (-not $OutputPath) {
    $OutputPath = Join-Path $DistDir "AskAwayActivityWatchInstaller.exe"
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

function Get-PythonExe {
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        foreach ($version in @("3.12", "3.11", "3.13", "3.14", "3")) {
            try {
                $result = & $py.Source "-$version" -c "import sys; assert sys.version_info >= (3, 11); print(sys.executable)" 2>$null
                if ($LASTEXITCODE -eq 0 -and $result) {
                    return ($result | Select-Object -First 1)
                }
            }
            catch {
                continue
            }
        }
    }

    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        return $python.Source
    }

    throw "Python was not found. Install Python 3.11+ to build the installer."
}

function Get-ActivityWatchIcon {
    $paths = @(
        "$env:LOCALAPPDATA\Programs\ActivityWatch\media\logo\logo.ico",
        "$env:ProgramFiles\ActivityWatch\media\logo\logo.ico",
        "${env:ProgramFiles(x86)}\ActivityWatch\media\logo\logo.ico"
    )

    foreach ($path in $paths) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            return $path
        }
    }

    return ""
}

New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
if (Test-Path -LiteralPath $OutputPath) {
    Remove-Item -LiteralPath $OutputPath -Force
}
if (Test-Path -LiteralPath $BuildDir) {
    Remove-Item -LiteralPath $BuildDir -Recurse -Force
}
New-Item -ItemType Directory -Path $PayloadDir -Force | Out-Null

$python = Get-PythonExe
Write-Host "==> Building wheel with $python"
Invoke-Checked $python @("-m", "pip", "wheel", ".", "--no-deps", "-w", $PayloadDir)

$wheel = Get-ChildItem -LiteralPath $PayloadDir -Filter "aw_watcher_ask_away-*.whl" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if (-not $wheel) {
    throw "Wheel was not created."
}

Copy-Item -LiteralPath $InstallerScript -Destination (Join-Path $BuildDir "install-windows-activitywatch.ps1") -Force
Copy-Item -LiteralPath $wheel.FullName -Destination (Join-Path $BuildDir $wheel.Name) -Force

Write-Host "==> Preparing PyInstaller build environment"
$BuildVenvDir = Join-Path $BuildDir "pyinstaller-venv"
Invoke-Checked $python @("-m", "venv", $BuildVenvDir)
$buildPython = Join-Path $BuildVenvDir "Scripts\python.exe"
Invoke-Checked $buildPython @("-m", "pip", "install", "--no-cache-dir", "--upgrade", "pip")
Invoke-Checked $buildPython @("-m", "pip", "install", "--no-cache-dir", "pyinstaller")
Invoke-Checked $buildPython @("-m", "pip", "install", "--no-cache-dir", $wheel.FullName)

$icon = Get-ActivityWatchIcon
$pyinstallerArgs = @(
    "-m", "PyInstaller",
    "--noconfirm",
    "--clean",
    "--onefile",
    "--console",
    "--name", "AskAwayActivityWatchInstaller",
    "--distpath", $DistDir,
    "--workpath", (Join-Path $RepoRoot "build\pyinstaller"),
    "--specpath", (Join-Path $RepoRoot "build\pyinstaller"),
    "--add-data", "$(Join-Path $BuildDir 'install-windows-activitywatch.ps1');.",
    "--add-data", "$(Join-Path $BuildDir $wheel.Name);.",
    $LauncherScript
)

if ($icon) {
    Write-Host "==> Using icon $icon"
}

Write-Host "==> Building standalone watcher payload"
$watcherBuildDist = Join-Path $BuildDir "watcher-dist"
$watcherArgs = @(
    "-m", "PyInstaller",
    "--noconfirm",
    "--clean",
    "--onefile",
    "--windowed",
    "--name", "aw-watcher-ask-away",
    "--distpath", $watcherBuildDist,
    "--workpath", (Join-Path $RepoRoot "build\pyinstaller-watcher"),
    "--specpath", (Join-Path $RepoRoot "build\pyinstaller-watcher"),
    "--paths", (Join-Path $RepoRoot "src"),
    $WatcherLauncherScript
)
if ($icon) {
    $watcherArgs = @(
        "-m", "PyInstaller",
        "--noconfirm",
        "--clean",
        "--onefile",
        "--windowed",
        "--name", "aw-watcher-ask-away",
        "--icon", $icon,
        "--distpath", $watcherBuildDist,
        "--workpath", (Join-Path $RepoRoot "build\pyinstaller-watcher"),
        "--specpath", (Join-Path $RepoRoot "build\pyinstaller-watcher"),
        "--paths", (Join-Path $RepoRoot "src"),
        $WatcherLauncherScript
    )
}
Invoke-Checked $buildPython $watcherArgs

$watcherExe = Join-Path $watcherBuildDist "aw-watcher-ask-away.exe"
if (-not (Test-Path -LiteralPath $watcherExe)) {
    throw "Standalone watcher EXE was not created: $watcherExe"
}
Copy-Item -LiteralPath $watcherExe -Destination (Join-Path $BuildDir "aw-watcher-ask-away.exe") -Force

$pyinstallerArgs = @(
    "-m", "PyInstaller",
    "--noconfirm",
    "--clean",
    "--onefile",
    "--console",
    "--name", "AskAwayActivityWatchInstaller",
    "--distpath", $DistDir,
    "--workpath", (Join-Path $RepoRoot "build\pyinstaller"),
    "--specpath", (Join-Path $RepoRoot "build\pyinstaller"),
    "--add-data", "$(Join-Path $BuildDir 'install-windows-activitywatch.ps1');.",
    "--add-data", "$(Join-Path $BuildDir $wheel.Name);.",
    "--add-data", "$(Join-Path $BuildDir 'aw-watcher-ask-away.exe');.",
    $LauncherScript
)
if ($icon) {
    $pyinstallerArgs = @(
        "-m", "PyInstaller",
        "--noconfirm",
        "--clean",
        "--onefile",
        "--console",
        "--name", "AskAwayActivityWatchInstaller",
        "--icon", $icon,
        "--distpath", $DistDir,
        "--workpath", (Join-Path $RepoRoot "build\pyinstaller"),
        "--specpath", (Join-Path $RepoRoot "build\pyinstaller"),
        "--add-data", "$(Join-Path $BuildDir 'install-windows-activitywatch.ps1');.",
        "--add-data", "$(Join-Path $BuildDir $wheel.Name);.",
        "--add-data", "$(Join-Path $BuildDir 'aw-watcher-ask-away.exe');.",
        $LauncherScript
    )
}

Write-Host "==> Building $OutputPath"
Invoke-Checked $buildPython $pyinstallerArgs

if (-not (Test-Path -LiteralPath $OutputPath)) {
    throw "Installer EXE was not created: $OutputPath"
}

Write-Host "==> Created $OutputPath"
