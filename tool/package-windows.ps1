param(
    [string]$ReleaseDirectory = 'build/windows/x64/runner/Release',
    [string]$Destination = 'dist/Lan-Clip-Windows-x64.zip'
)
$ErrorActionPreference = 'Stop'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (!(Test-Path $vswhere)) { throw 'Visual Studio installer tools were not found.' }
$installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$installation) { throw 'Visual Studio C++ tools were not found.' }
$redistRoot = Join-Path $installation 'VC/Redist/MSVC'
$redist = Get-ChildItem $redistRoot -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Name } -Descending |
    Select-Object -First 1
if (!$redist) { throw 'The Visual C++ redistributable directory was not found.' }
$runtime = @(Get-ChildItem (Join-Path $redist.FullName 'x64/Microsoft.VC*.CRT/*.dll'))
if (!$runtime.Count) { throw 'No x64 Visual C++ runtime DLLs were found.' }
Copy-Item $runtime.FullName -Destination $ReleaseDirectory -Force
foreach ($name in @('lan_clip.exe', 'flutter_windows.dll', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    if (!(Test-Path (Join-Path $ReleaseDirectory $name))) { throw "Missing runtime file: $name" }
}
$parent = Split-Path -Parent $Destination
if ($parent) { New-Item -ItemType Directory -Force $parent | Out-Null }
Compress-Archive -Path (Join-Path $ReleaseDirectory '*') -DestinationPath $Destination -Force
Write-Output "Packaged Windows x64 app and $($runtime.Count) Visual C++ runtime DLLs: $Destination"
