<#
.SYNOPSIS
Builds a one-file Windows installer EXE for aw-watcher-cursor-busy.
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
$InstallerLauncher = Join-Path $PSScriptRoot "installer-launcher.py"
$WatcherLauncher = Join-Path $PSScriptRoot "watcher-standalone.py"
$ReportLauncher = Join-Path $PSScriptRoot "report-standalone.py"

if (-not $OutputPath) {
    $OutputPath = Join-Path $DistDir "CursorBusyActivityWatchInstaller.exe"
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
        foreach ($version in @("3.12", "3.11", "3.13", "3.14")) {
            $result = & py "-$version" -c "import sys; print(sys.executable)" 2>$null
            if ($LASTEXITCODE -eq 0 -and $result) {
                return ($result | Select-Object -First 1)
            }
        }
    }

    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        return $python.Source
    }

    throw "Python 3.11+ was not found. Install Python to build the installer."
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
Write-Host "==> Ensuring build dependencies"
Invoke-Checked $python @("-m", "pip", "install", "--user", "pyinstaller", "aw-client")

$icon = Get-ActivityWatchIcon
if ($icon) {
    Write-Host "==> Using icon $icon"
}

function Build-PayloadExe {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Launcher,
        [switch]$Windowed
    )

    $dist = Join-Path $BuildDir "$Name-dist"
    $work = Join-Path $RepoRoot "build\pyinstaller-$Name"
    $args = @(
        "-m", "PyInstaller",
        "--noconfirm",
        "--clean",
        "--onefile",
        "--name", $Name,
        "--distpath", $dist,
        "--workpath", $work,
        "--specpath", $work,
        "--paths", (Join-Path $RepoRoot "src")
    )

    if ($Windowed) {
        $args += "--windowed"
    }
    else {
        $args += "--console"
    }

    if ($icon) {
        $args += @("--icon", $icon)
    }

    $args += $Launcher

    Write-Host "==> Building $Name"
    Invoke-Checked $python $args

    $exe = Join-Path $dist "$Name.exe"
    if (-not (Test-Path -LiteralPath $exe)) {
        throw "Payload EXE was not created: $exe"
    }

    Copy-Item -LiteralPath $exe -Destination (Join-Path $BuildDir "$Name.exe") -Force
}

Build-PayloadExe -Name "aw-watcher-cursor-busy" -Launcher $WatcherLauncher -Windowed
Build-PayloadExe -Name "aw-cursor-busy-report" -Launcher $ReportLauncher

Copy-Item -LiteralPath $InstallerScript -Destination (Join-Path $BuildDir "install-windows-activitywatch.ps1") -Force

$installerArgs = @(
    "-m", "PyInstaller",
    "--noconfirm",
    "--clean",
    "--onefile",
    "--console",
    "--name", "CursorBusyActivityWatchInstaller",
    "--distpath", $DistDir,
    "--workpath", (Join-Path $RepoRoot "build\pyinstaller-installer"),
    "--specpath", (Join-Path $RepoRoot "build\pyinstaller-installer"),
    "--add-data", "$(Join-Path $BuildDir 'install-windows-activitywatch.ps1');.",
    "--add-data", "$(Join-Path $BuildDir 'aw-watcher-cursor-busy.exe');.",
    "--add-data", "$(Join-Path $BuildDir 'aw-cursor-busy-report.exe');."
)

if ($icon) {
    $installerArgs += @("--icon", $icon)
}

$installerArgs += $InstallerLauncher

Write-Host "==> Building $OutputPath"
Invoke-Checked $python $installerArgs

if (-not (Test-Path -LiteralPath $OutputPath)) {
    throw "Installer EXE was not created: $OutputPath"
}

Write-Host "==> Created $OutputPath"
