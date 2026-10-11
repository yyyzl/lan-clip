#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
arch_name="$(uname -m)"
mode="${1:-release}"
if [[ "$mode" != release && "$mode" != debug ]]; then echo 'Usage: build-macos-local.sh [release|debug]' >&2; exit 2; fi
assets="build/manual-macos-$mode"
./tool/flutterw assemble --output="$assets" \
  -dTargetPlatform=darwin -dDarwinArchs="$arch_name" -dBuildMode="$mode" \
  "${mode}_macos_bundle_flutter_assets"
bundle="build/local-$mode/Lan Clip.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Frameworks" "$bundle/Contents/Resources"
ditto "$assets/App.framework" "$bundle/Contents/Frameworks/App.framework"
ditto "$assets/FlutterMacOS.framework" "$bundle/Contents/Frameworks/FlutterMacOS.framework"
xcrun swiftc -D LAN_CLIP_STANDALONE -target "$arch_name-apple-macos12.0" \
  -F "$assets" -framework Cocoa -framework FlutterMacOS \
  -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' \
  macos/Runner/MainFlutterWindow.swift macos/Runner/AppDelegate.swift tool/StandaloneMain.swift \
  -o "$bundle/Contents/MacOS/LanClip"
python3 - "$bundle" <<'PY'
import plistlib, sys
from pathlib import Path
bundle = Path(sys.argv[1])
info = {
    'CFBundleExecutable': 'LanClip', 'CFBundleIdentifier': 'dev.lanclip.lanClip',
    'CFBundleName': '轻贴', 'CFBundleDisplayName': '轻贴', 'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '1',
    'LSMinimumSystemVersion': '12.0', 'NSPrincipalClass': 'NSApplication',
    'NSHighResolutionCapable': True,
    'NSLocalNetworkUsageDescription': '接收同一 Wi-Fi 下手机发送的文字和图片。',
    'CFBundleIconFile': 'AppIcon.icns',
}
(bundle/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
if [[ -f design/AppIcon.icns ]]; then cp design/AppIcon.icns "$bundle/Contents/Resources/"; fi
cp design/StatusIcon.png "$bundle/Contents/Resources/"
codesign --force --deep --sign - "$bundle"
echo "Local app: $bundle"
