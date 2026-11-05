#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
swift build --disable-sandbox --cache-path "$PWD/.build/cache" -debug-info-format none -c "$configuration" --product VoiceDeck
binary_dir="$(swift build --disable-sandbox --cache-path "$PWD/.build/cache" -debug-info-format none -c "$configuration" --show-bin-path)"
app="$PWD/build/VoiceDeck.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/VoiceDeck" "$app/Contents/MacOS/VoiceDeck"
for bundle in "$binary_dir/"*.bundle; do
  if [[ -d "$bundle" ]]; then ditto "$bundle" "$app/Contents/Resources/$(basename "$bundle")"; fi
done
swift scripts/generate-icon.swift "$PWD/build/AppIcon.iconset" "$app/Contents/Resources/AppIcon.icns" "$PWD/Sources/VoiceDeck/Resources/AppIcon.png"
app_version="$(cat VERSION)"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>VoiceDeck</string>
<key>CFBundleIdentifier</key><string>io.github.tommasinigiovanni.VoiceDeck</string>
<key>CFBundleName</key><string>VoiceDeck</string>
<key>CFBundleDisplayName</key><string>VoiceDeck</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>$app_version</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSMicrophoneUsageDescription</key><string>VoiceDeck registra dal microfono quando lo avvii, per trascrivere la tua voce nella modalità che hai scelto.</string>
<key>NSHumanReadableCopyright</key><string>VoiceDeck · Giovanni Tommasini</string>
</dict></plist>
PLIST
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
dependency_source="${VOICEDECK_FLUIDAUDIO_PATH:-$PWD/.build/checkouts/FluidAudio}"
if [[ -f "$dependency_source/LICENSE" ]]; then
  mkdir -p "$app/Contents/Resources/Licenses/FluidAudio"
  cp "$dependency_source/LICENSE" "$app/Contents/Resources/Licenses/FluidAudio/LICENSE"
  ditto "$dependency_source/ThirdPartyLicenses" "$app/Contents/Resources/Licenses/FluidAudio/ThirdPartyLicenses"
fi
codesign --force --deep --sign - "$app"
printf 'App pronta: %s\n' "$app"
