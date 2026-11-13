# AgentSlang (ASL): Windows is not supported yet.
# This script installs nothing. It exists so that https://aslang.dev/install.ps1 answers honestly.
$ErrorActionPreference = "Stop"
Write-Host "AgentSlang (ASL) is not released, and Windows is not supported yet." -ForegroundColor Yellow
Write-Host "Nothing was installed. On macOS or Linux, or under WSL, build from source: https://aslang.dev/docs#install"
throw "ASL install failed: Windows is not supported yet"
