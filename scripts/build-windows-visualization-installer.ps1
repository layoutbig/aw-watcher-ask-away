<#
.SYNOPSIS
Builds a one-file Windows installer EXE for the aw-watcher-ask-away visualization.

.DESCRIPTION
The generated EXE is a PyInstaller one-file launcher. It includes:
- install-windows-visualization.ps1
- visualization\dist\index.html

It does not install Python, pipx, or aw-watcher-ask-away. It assumes the user
already has ActivityWatch and aw-watcher-ask-away installed.

The resulting installer is written to:
dist\AskAwayVisualizationInstaller.exe
#>

[CmdletBinding()]
param(
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$DistDir = Join-Path $RepoRoot "dist"
$BuildDir = Join-Path $RepoRoot "build\windows-visualization-installer"
$InstallerScript = Join-Path $PSScriptRoot "install-windows-visualization.ps1"
$LauncherScript = Join-Path $PSScriptRoot "visualization-installer-launcher.py"
$VisualizationSource = Join-Path $RepoRoot "visualization\dist\index.html"

if (-not $OutputPath) {
    $OutputPath = Join-Path $DistDir "AskAwayVisualizationInstaller.exe"
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

function Get-PythonExe {
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        foreach ($version in @("3.12", "3.11", "3.13", "3.14", "3")) {
            $result = Invoke-NativeCapture $py.Source @("-$version", "-c", "import sys; print(sys.executable)")
            if ($result.ExitCode -eq 0 -and $result.Stdout) {
                return ($result.Stdout -split "`r?`n" | Select-Object -First 1)
            }
        }
    }

    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        return $python.Source
    }

    foreach ($path in @(
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python314\python.exe",
        "C:\Python312\python.exe",
        "C:\Python311\python.exe",
        "C:\Python313\python.exe",
        "C:\Python314\python.exe"
    )) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            return $path
        }
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
New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null

if (-not (Test-Path -LiteralPath $VisualizationSource)) {
    throw "Custom visualization was not found: $VisualizationSource"
}

Copy-Item -LiteralPath $InstallerScript -Destination (Join-Path $BuildDir "install-windows-visualization.ps1") -Force
$visualizationBuildDir = Join-Path $BuildDir "visualization\dist"
New-Item -ItemType Directory -Path $visualizationBuildDir -Force | Out-Null
Copy-Item -LiteralPath $VisualizationSource -Destination (Join-Path $visualizationBuildDir "index.html") -Force

$python = Get-PythonExe
Write-Host "==> Ensuring PyInstaller is available with $python"
$check = Start-Process -FilePath $python -ArgumentList @("-m", "PyInstaller", "--version") -Wait -PassThru -WindowStyle Hidden
if ($check.ExitCode -ne 0) {
    Invoke-Checked $python @("-m", "pip", "install", "--user", "pyinstaller")
}

$icon = Get-ActivityWatchIcon
$pyinstallerArgs = @(
    "-m", "PyInstaller",
    "--noconfirm",
    "--clean",
    "--onefile",
    "--console",
    "--name", "AskAwayVisualizationInstaller",
    "--distpath", $DistDir,
    "--workpath", (Join-Path $RepoRoot "build\pyinstaller-visualization"),
    "--specpath", (Join-Path $RepoRoot "build\pyinstaller-visualization"),
    "--add-data", "$(Join-Path $BuildDir 'install-windows-visualization.ps1');.",
    "--add-data", "$(Join-Path $BuildDir 'visualization');visualization",
    $LauncherScript
)

if ($icon) {
    Write-Host "==> Using icon $icon"
    $pyinstallerArgs = @(
        "-m", "PyInstaller",
        "--noconfirm",
        "--clean",
        "--onefile",
        "--console",
        "--name", "AskAwayVisualizationInstaller",
        "--icon", $icon,
        "--distpath", $DistDir,
        "--workpath", (Join-Path $RepoRoot "build\pyinstaller-visualization"),
        "--specpath", (Join-Path $RepoRoot "build\pyinstaller-visualization"),
        "--add-data", "$(Join-Path $BuildDir 'install-windows-visualization.ps1');.",
        "--add-data", "$(Join-Path $BuildDir 'visualization');visualization",
        $LauncherScript
    )
}

Write-Host "==> Building $OutputPath"
Invoke-Checked $python $pyinstallerArgs

if (-not (Test-Path -LiteralPath $OutputPath)) {
    throw "Installer EXE was not created: $OutputPath"
}

Write-Host "==> Created $OutputPath"
