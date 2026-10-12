$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter build windows --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& ./tool/package-windows.ps1 -Destination 'build/Lan-Clip-Windows.zip'
Write-Output '完成：build/Lan-Clip-Windows-x64-Setup.exe（安装向导）和 build/Lan-Clip-Windows.zip（便携包）。'
