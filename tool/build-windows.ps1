$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter build windows --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Compress-Archive -Path 'build/windows/x64/runner/Release/*' -DestinationPath 'build/Lan-Clip-Windows.zip' -Force
Write-Output '完成：build/Lan-Clip-Windows.zip。请解压整个目录后运行 lan_clip.exe。'
