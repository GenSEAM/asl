# AgentScript Universal Installer for Windows (PowerShell)
# Usage: irm https://aslang.dev/install.ps1 | iex
$ErrorActionPreference = "Stop"

$Version = "0.1.0"
$InstallDir = "$env:LOCALAPPDATA\asl\bin"
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

Write-Host "🚀 Installing AgentScript (ASL) for Windows..." -ForegroundColor Cyan

$AslCmdPath = Join-Path $InstallDir "asl.cmd"

@"
@echo off
setlocal enableextensions
set "SCRIPT_DIR=%~dp0"

:: Locate asl.wasm and run-wasm.js
if exist "%SCRIPT_DIR%asl.wasm" (
  set "WASM_BIN=%SCRIPT_DIR%asl.wasm"
  set "RUN_JS=%SCRIPT_DIR%run-wasm.js"
) else if exist "%SCRIPT_DIR%..\asl.wasm" (
  set "WASM_BIN=%SCRIPT_DIR%..\asl.wasm"
  set "RUN_JS=%SCRIPT_DIR%..\run-wasm.js"
) else (
  set "WASM_BIN=%SCRIPT_DIR%asl.wasm"
  set "RUN_JS=%SCRIPT_DIR%run-wasm.js"
)

if "%~1"=="--version" goto :show_version
if "%~1"=="-v" goto :show_version
if "%~1"=="" goto :show_help
if "%~1"=="--help" goto :show_help
if "%~1"=="-h" goto :show_help

:: If native zero-dependency asl.exe exists, run it
if exist "%SCRIPT_DIR%asl.exe" (
  "%SCRIPT_DIR%asl.exe" %*
  exit /b %ERRORLEVEL%
)

where node >nul 2>&1
if %ERRORLEVEL% equ 0 (
  node "%RUN_JS%" %*
  exit /b %ERRORLEVEL%
)

where bun >nul 2>&1
if %ERRORLEVEL% equ 0 (
  bun run "%RUN_JS%" %*
  exit /b %ERRORLEVEL%
)

where wasmtime >nul 2>&1
if %ERRORLEVEL% equ 0 (
  wasmtime run --dir=. "%WASM_BIN%" %*
  exit /b %ERRORLEVEL%
)

echo Error: ASL on Windows requires a WebAssembly/WASI runtime (wasmtime, node, bun, or wasmer). >&2
exit /b 1

:show_version
echo asl 0.1.0 (wasm-wasi windows-x64 substrate)
exit /b 0

:show_help
echo AgentScript Native CLI (WASM/WASI substrate for Windows)
echo Usage: asl ^<command^> [args...]
exit /b 0
"@ | Set-Content -Path $AslCmdPath -Encoding ASCII

$UserPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::User)
if ($UserPath -notlike "*$InstallDir*") {
    [System.Environment]::SetEnvironmentVariable("Path", "$UserPath;$InstallDir", [System.EnvironmentVariableTarget]::User)
    $env:Path = "$env:Path;$InstallDir"
    Write-Host "✓ Added $InstallDir to User PATH" -ForegroundColor Green
}

Write-Host "✓ ASL successfully installed to $InstallDir\asl.cmd" -ForegroundColor Green
Write-Host "⚡ Run: asl --version" -ForegroundColor Yellow
