param([string]$Installer = 'dist/Lan-Clip-Windows-x64-Setup.exe')
$ErrorActionPreference = 'Stop'
$installerPath = (Resolve-Path $Installer).Path
$installDir = Join-Path $env:RUNNER_TEMP 'Lan Clip Installer Test'
$dataDir = Join-Path $env:LOCALAPPDATA 'LanClip/lan-clip'
$registryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{B0919F84-CA67-47DD-89F4-B0326B803C54}_is1'
$desktopShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) '轻贴.lnk'
$startShortcut = Join-Path ([Environment]::GetFolderPath('Programs')) '轻贴/轻贴.lnk'
if (Test-Path $dataDir) { throw 'Smoke test requires a clean CI user profile.' }

function Install-App {
    $process = Start-Process $installerPath -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER', '/LANG=chinesesimp', '/TASKS=desktopicon', "/DIR=`"$installDir`"") -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Installer failed: $($process.ExitCode)" }
}

Install-App
foreach ($file in @('lan_clip.exe', 'flutter_windows.dll', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'data/flutter_assets/AssetManifest.bin', 'unins000.exe')) {
    if (!(Test-Path (Join-Path $installDir $file))) { throw "Installed file is missing: $file" }
}
foreach ($item in @($registryPath, $desktopShortcut, $startShortcut)) {
    if (!(Test-Path $item)) { throw "Installation registration is missing: $item" }
}
$app = Start-Process (Join-Path $installDir 'lan_clip.exe') -WorkingDirectory $installDir -PassThru
try {
    $responded = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        $app.Refresh()
        if ($app.HasExited) { throw "Installed app exited: $($app.ExitCode)" }
        try {
            $response = Invoke-WebRequest 'https://127.0.0.1:45877/v1/ping' -SkipCertificateCheck -SkipHttpErrorCheck -TimeoutSec 2
            if ($response.StatusCode -eq 401) { $responded = $true; break }
        } catch { }
    }
    if (!$responded) { throw 'Installed receiver did not become ready.' }
} finally {
    if (!$app.HasExited) { Stop-Process -Id $app.Id; $app.WaitForExit() }
}
$settings = Join-Path $dataDir 'settings.json'
if (!(Test-Path $settings)) { throw 'Installed app did not create its user settings.' }
$saved = Get-Content $settings -Raw | ConvertFrom-Json
$saved.phones = @(@{ id = 'installer-smoke-phone'; name = 'Test phone'; token = 'test-only-pairing-token' })
$saved | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 $settings
$settingsHash = (Get-FileHash $settings).Hash
$keyHash = (Get-FileHash (Join-Path $dataDir 'identity-key.pem')).Hash
Install-App
if ((Get-FileHash $settings).Hash -ne $settingsHash -or (Get-FileHash (Join-Path $dataDir 'identity-key.pem')).Hash -ne $keyHash) {
    throw 'Upgrade changed existing pairing or identity data.'
}
$uninstall = Start-Process (Join-Path $installDir 'unins000.exe') -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -Wait -PassThru
if ($uninstall.ExitCode -ne 0) { throw "Uninstall failed: $($uninstall.ExitCode)" }
foreach ($item in @((Join-Path $installDir 'lan_clip.exe'), $registryPath, $desktopShortcut, $startShortcut)) {
    if (Test-Path $item) { throw "Uninstall left application registration or binary: $item" }
}
if ((Get-FileHash $settings).Hash -ne $settingsHash) { throw 'Uninstall removed user pairing data.' }
Write-Output 'PASS: install, shortcuts, native receiver launch, upgrade preserves pairing, uninstall removes app and keeps user data.'
