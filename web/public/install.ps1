# ==============================================================================
# AgentScript (ASL) Universal Windows PowerShell Installer
# Canonical URL: https://aslang.dev/install.ps1
# Usage: irm https://aslang.dev/install.ps1 | iex
# ==============================================================================
$ErrorActionPreference = 'Stop'

$Version = '0.1.0'
$InstallDir = "$env:LOCALAPPDATA\asl\bin"
$RepoDir = "$env:LOCALAPPDATA\asl\repo"
$BaseReleaseUrl = "https://github.com/GenSEAM/asl/releases/download/v$Version"

# 1. Detect Architecture
$Arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'arm64' } else { 'x64' }

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "         AgentScript (ASL) Windows CLI Installer (v$Version - windows-$Arch)       " -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# 2. Prepare Installation Directory
if (!(Test-Path -Path $InstallDir)) {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
}

$BinaryInstalled = $false

# 3. Attempt Pre-built Binary Download
$ZipCandidates = @(
    "$BaseReleaseUrl/asl-$Version-windows-$Arch.zip",
    "$BaseReleaseUrl/asl-$Version-windows-x64.zip"
)

foreach ($ZipUrl in $ZipCandidates) {
    $ZipFile = "$env:TEMP\asl-$Version-windows.zip"
    Write-Host "--> Checking pre-built binary: $ZipUrl..." -ForegroundColor Gray
    try {
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            & curl.exe -fsSL "$ZipUrl" -o "$ZipFile" 2>$null
        } else {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipFile -UseBasicParsing -TimeoutSec 15
        }

        if ((Test-Path $ZipFile) -and ((Get-Item $ZipFile).Length -gt 1024)) {
            Write-Host "✓ Downloaded binary archive. Extracting to $InstallDir..." -ForegroundColor Green
            Expand-Archive -Path $ZipFile -DestinationPath $InstallDir -Force
            Remove-Item -Force $ZipFile -ErrorAction SilentlyContinue
            $BinaryInstalled = $true
            break
        }
    } catch {
        # Try next candidate
    } finally {
        if (Test-Path $ZipFile) { Remove-Item -Force $ZipFile -ErrorAction SilentlyContinue }
    }
}

# 4. Fallback: Source Clone & Node Daemon Setup
if (-not $BinaryInstalled) {
    Write-Host "--> Pre-built binary not available yet for this release. Building from git source..." -ForegroundColor Yellow
    if (Test-Path "$RepoDir\.git") {
        Write-Host "  Updating existing clone in $RepoDir..." -ForegroundColor Gray
        git -C "$RepoDir" pull --ff-only 2>$null
    } else {
        Write-Host "  Cloning repository into $RepoDir..." -ForegroundColor Gray
        git clone --depth 1 https://github.com/GenSEAM/asl.git "$RepoDir"
    }

    # Verify Node.js prerequisite for source execution
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Host "⚠ Warning: Node.js >= 20 is recommended for local ASL memory daemon." -ForegroundColor Yellow
    }
}

# 5. Create Windows Shims (asl.cmd and asl.ps1)
$CmdShimPath = "$InstallDir\asl.cmd"
$CmdContent = @"
@echo off
setlocal
set "ASL_DIR=%~dp0"
if exist "%ASL_DIR%asl.exe" (
    "%ASL_DIR%asl.exe" %*
    exit /b %ERRORLEVEL%
)
if exist "%LOCALAPPDATA%\asl\repo\asl" (
    if "%1"=="upgrade" goto do_upgrade
    if "%1"=="update" goto do_upgrade
    if exist "%LOCALAPPDATA%\asl\repo\bin\asl-daemon.exe" (
        "%LOCALAPPDATA%\asl\repo\bin\asl-daemon.exe" %*
        exit /b %ERRORLEVEL%
    )
    if exist "%LOCALAPPDATA%\asl\bin\asl-daemon.exe" (
        "%LOCALAPPDATA%\asl\bin\asl-daemon.exe" %*
        exit /b %ERRORLEVEL%
    )
    where bash >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        bash "%LOCALAPPDATA%\asl\repo\asl" %*
        exit /b %ERRORLEVEL%
    )
)
:do_upgrade
if "%1"=="upgrade" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://aslang.dev/install.ps1 | iex"
    exit /b %ERRORLEVEL%
)
if "%1"=="update" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://aslang.dev/install.ps1 | iex"
    exit /b %ERRORLEVEL%
)
echo asl: executable runner not found in %ASL_DIR%
exit /b 1
"@
Set-Content -Path $CmdShimPath -Value $CmdContent -Encoding ASCII

$Ps1ShimPath = "$InstallDir\asl.ps1"
$Ps1Content = @"
`$ErrorActionPreference = 'Stop'
`$ScriptDir = `$PSScriptRoot
if (`$args.Count -gt 0 -and (`$args[0] -eq 'upgrade' -or `$args[0] -eq 'update')) {
    Write-Host "🚀 Checking for AgentScript updates..." -ForegroundColor Cyan
    Invoke-Expression (Invoke-RestMethod -Uri "https://aslang.dev/install.ps1")
    return
}
if (Test-Path "`$ScriptDir\asl.exe") {
    & "`$ScriptDir\asl.exe" @args
    return
}
if (Test-Path "`$ScriptDir\asl-daemon.exe") {
    & "`$ScriptDir\asl-daemon.exe" @args
    return
}
`$DaemonBin = "`$env:LOCALAPPDATA\asl\repo\bin\asl-daemon.exe"
if (Test-Path `$DaemonBin) {
    & `$DaemonBin @args
    return
}
`$BashBin = Get-Command bash -ErrorAction SilentlyContinue
if (`$BashBin -and (Test-Path "`$env:LOCALAPPDATA\asl\repo\asl")) {
    & bash "`$env:LOCALAPPDATA\asl\repo\asl" @args
    return
}
Write-Error "asl: binary or runtime runner not found in `$ScriptDir"
"@
Set-Content -Path $Ps1ShimPath -Value $Ps1Content -Encoding UTF8

# 6. Persistent User PATH Configuration
$UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($UserPath -notlike "*$InstallDir*") {
    [Environment]::SetEnvironmentVariable('Path', "$InstallDir;$UserPath", 'User')
    Write-Host "✓ Added $InstallDir to persistent User PATH" -ForegroundColor Green
}
# Update current process PATH immediately
if ($env:Path -notlike "*$InstallDir*") {
    $env:Path = "$InstallDir;$env:Path"
}

# 7. Verification & Summary
Write-Host ""
Write-Host "================================================================================" -ForegroundColor Green
Write-Host "✓ AgentScript (ASL) successfully installed on Windows!" -ForegroundColor Green
Write-Host "  Location: $InstallDir\asl.cmd" -ForegroundColor Gray
Write-Host "  PowerShell Shim: $InstallDir\asl.ps1" -ForegroundColor Gray
Write-Host "================================================================================" -ForegroundColor Green
Write-Host "⚡ Try running in any terminal: asl --help" -ForegroundColor Cyan
Write-Host "⚡ Self-update anytime with:     asl upgrade" -ForegroundColor Cyan
