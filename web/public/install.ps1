# AgentScript (ASL) Windows PowerShell Installer
# Auto-generated from pure AgentScript module: pack/src/dist.asl
$ErrorActionPreference = 'Stop'
$Version = '0.1.0'
$InstallDir = "$env:LOCALAPPDATA\asl\bin"
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

Write-Host "🚀 Installing AgentScript (ASL) v$Version for Windows..." -ForegroundColor Cyan
$ZipUrl = "https://github.com/GenSEAM/asl/releases/download/v$Version/asl-$Version-windows-x64.zip"
$ZipFile = "$env:TEMP\asl-$Version.zip"

try {
    Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipFile
    Expand-Archive -Path $ZipFile -DestinationPath $InstallDir -Force
    Remove-Item -Force $ZipFile
} catch {
    Write-Host "Falling back to git clone source build..." -ForegroundColor Yellow
    git clone https://github.com/GenSEAM/asl.git "$env:LOCALAPPDATA\asl\repo"
    Copy-Item "$env:LOCALAPPDATA\asl\repo\asl" "$InstallDir\asl.cmd"
}

$UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($UserPath -notlike "*$InstallDir*") {
    [Environment]::SetEnvironmentVariable('Path', "$InstallDir;$UserPath", 'User')
    Write-Host "✓ Added $InstallDir to User PATH" -ForegroundColor Green
}
Write-Host "✓ AgentScript successfully installed! Restart your shell and run: asl --version" -ForegroundColor Green
