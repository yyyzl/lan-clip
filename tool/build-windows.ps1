$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter build windows --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& ./tool/package-windows.ps1 -Destination 'build/Lan-Clip-Windows.zip'
Write-Output '完成：build/Lan-Clip-Windows.zip。请解压整个目录后运行 lan_clip.exe。'
