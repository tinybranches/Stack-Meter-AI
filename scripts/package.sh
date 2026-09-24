#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(python3 - <<'PY'
import re
text = open("project.yml").read()
m = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', text)
print(m.group(1) if m else "0.0.0")
PY
)"
BUILD="$(python3 - <<'PY'
import re
text = open("project.yml").read()
m = re.search(r'CURRENT_PROJECT_VERSION:\s*(\d+)', text)
print(m.group(1) if m else "0")
PY
)"

DERIVED="$ROOT/build/PackageDerivedData"
STAGING="$ROOT/build/dmg-staging"
DIST="$ROOT/dist"
DMG_NAME="Stack-Meter-AI-${VERSION}.dmg"
VOLUME_NAME="Stack Meter AI ${VERSION}"
VOLUME_ICON="$ROOT/Design/icons/VolumeIcon.icns"
APP_ICON_ICNS="$ROOT/Branding/AppIcon.icns"

echo "==> Generating icons"
python3 "$ROOT/scripts/generate_icons.py"

echo "==> Generating Xcode project"
command -v xcodegen >/dev/null || { echo "Install xcodegen: brew install xcodegen"; exit 1; }
xcodegen generate

echo "==> Building Stack Meter AI (Release)"
rm -rf "$DERIVED"
xcodebuild \
  -project AIBar.xcodeproj \
  -scheme Package \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  build

PRODUCTS="$DERIVED/Build/Products/Release"
APP="$PRODUCTS/Stack Meter AI.app"

[[ -d "$APP" ]] || { echo "Missing: $APP"; exit 1; }
[[ -f "$APP_ICON_ICNS" ]] || { echo "Missing app icon: $APP_ICON_ICNS"; exit 1; }
[[ -f "$VOLUME_ICON" ]] || { echo "Missing volume icon: $VOLUME_ICON"; exit 1; }

if [[ ! -f "$APP/Contents/Resources/AppIcon.icns" ]]; then
  echo "==> Copying AppIcon.icns into app bundle"
  mkdir -p "$APP/Contents/Resources"
  cp "$APP_ICON_ICNS" "$APP/Contents/Resources/AppIcon.icns"
fi

if [[ ! -f "$APP/Contents/Resources/Assets.car" ]]; then
  echo "ERROR: Assets.car missing from app bundle (Notifications needs it)"
  exit 1
fi

echo "==> Applying Finder/LaunchServices icon on .app"
APP="$APP" ICON="$APP_ICON_ICNS" swift -e '
import AppKit
let app = ProcessInfo.processInfo.environment["APP"]!
let icon = ProcessInfo.processInfo.environment["ICON"]!
guard let image = NSImage(contentsOfFile: icon) else {
    fputs("Could not load AppIcon.icns\n", stderr)
    exit(1)
}
let ok = NSWorkspace.shared.setIcon(image, forFile: app, options: [])
print("App bundle Finder icon set:", ok)
'
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted "$APP" >/dev/null || true

echo "==> Staging DMG contents"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
# Create Applications link ONLY after the app copy, and never dereference it during staging.
ln -s /Applications "$STAGING/Applications"
if [[ ! -L "$STAGING/Applications" ]]; then
  echo "ERROR: staging Applications must be a symlink"
  exit 1
fi
# Staging root must contain only the app + Applications link (no nested project copies).
staging_entries=()
while IFS= read -r entry; do
  staging_entries+=("$entry")
done < <(find "$STAGING" -mindepth 1 -maxdepth 1 | sort)
if [[ ${#staging_entries[@]} -ne 2 ]]; then
  echo "ERROR: unexpected staging contents:"
  printf '  %s\n' "${staging_entries[@]}"
  exit 1
fi

mkdir -p "$DIST"
DMG_PATH="$DIST/$DMG_NAME"
RW_DMG="$DIST/.${DMG_NAME}.rw.dmg"
rm -f "$DMG_PATH" "$RW_DMG"

echo "==> Creating read-write DMG (for volume icon)"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDRW \
  "$RW_DMG"

echo "==> Mounting and applying volume icon"
MOUNT_DIR="$(mktemp -d /tmp/stackmeter-dmg.XXXXXX)"
hdiutil attach -readwrite -noverify -noautoopen -mountroot "$MOUNT_DIR" "$RW_DMG" >/dev/null
VOLUME_PATH="$(find "$MOUNT_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)"
[[ -d "$VOLUME_PATH" ]] || { echo "Failed to locate mounted volume"; exit 1; }

cp "$VOLUME_ICON" "$VOLUME_PATH/.VolumeIcon.icns"

if command -v SetFile >/dev/null 2>&1; then
  SetFile -a C "$VOLUME_PATH" || true
else
  VOLUME_PATH="$VOLUME_PATH" python3 - <<'PY'
import os
import xattr

path = os.environ["VOLUME_PATH"]
info = bytearray(32)
try:
    existing = xattr.getxattr(path, "com.apple.FinderInfo")
    info = bytearray(existing.ljust(32, b"\0")[:32])
except Exception:
    pass
info[8] = info[8] | 0x04
xattr.setxattr(path, "com.apple.FinderInfo", bytes(info))
print("set FinderInfo custom-icon bit on", path)
PY
fi

sync
hdiutil detach "$VOLUME_PATH" -quiet || hdiutil detach "$VOLUME_PATH" -force
rmdir "$MOUNT_DIR" 2>/dev/null || true

echo "==> Converting to compressed DMG"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
rm -f "$RW_DMG"

echo "==> Setting Finder icon on the .dmg file"
swift -e "
import AppKit
let dmg = \"${DMG_PATH}\"
let icon = \"${VOLUME_ICON}\"
guard let image = NSImage(contentsOfFile: icon) else {
    fputs(\"Could not load volume icon\\n\", stderr)
    exit(1)
}
let ok = NSWorkspace.shared.setIcon(image, forFile: dmg, options: [])
print(\"DMG file icon set:\", ok)
" 

echo ""
echo "Done."
echo "  Version: $VERSION ($BUILD)"
echo "  DMG:     $DMG_PATH"
echo ""
echo "Open the DMG and drag “Stack Meter AI” into Applications."
echo "To update later, drag the new app over the old one and replace."
