#!/usr/bin/env zsh
set -euo pipefail

APP_NAME="Engify"
BUNDLE_ID="dev.lupmit.engify"
VERSION="1.0.0"
MIN_MACOS="13.0"
OUTPUT_DIR="dist"
SIGN_IDENTITY=""
NOTARY_PROFILE=""
BINARY_NAME=""

usage() {
  cat <<'EOF'
Usage:
  zsh scripts/release.sh [options]

Options:
  --version <value>          Set CFBundleShortVersionString (default: 1.0.0)
  --bundle-id <value>        Set CFBundleIdentifier (default: dev.lupmit.engify)
  --app-name <value>         Set app name and DMG volume name (default: Engify)
  --binary-name <value>      Force binary name inside .build release output
  --output-dir <path>        Output directory (default: dist)
  --sign-identity <value>    codesign identity. If omitted, ad-hoc signing is used
  --notary-profile <value>   notarytool keychain profile (requires --sign-identity)
  --help                     Show this help

Examples:
  zsh scripts/release.sh
  zsh scripts/release.sh --version 1.2.0 --sign-identity "Developer ID Application: YOUR NAME (TEAMID)"
  zsh scripts/release.sh --sign-identity "Developer ID Application: YOUR NAME (TEAMID)" --notary-profile "MY_NOTARY_PROFILE"
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --bundle-id)
      BUNDLE_ID="$2"
      shift 2
      ;;
    --app-name)
      APP_NAME="$2"
      shift 2
      ;;
    --binary-name)
      BINARY_NAME="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --sign-identity)
      SIGN_IDENTITY="$2"
      shift 2
      ;;
    --notary-profile)
      NOTARY_PROFILE="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -n "$NOTARY_PROFILE" && -z "$SIGN_IDENTITY" ]]; then
  echo "--notary-profile requires --sign-identity" >&2
  exit 1
fi

echo "[release] Building release binary..."
swift build -c release

if [[ -z "$BINARY_NAME" ]]; then
  if [[ -f ".build/arm64-apple-macosx/release/Engify" ]]; then
    BINARY_NAME="Engify"
  elif [[ -f ".build/arm64-apple-macosx/release/EngifyApp" ]]; then
    BINARY_NAME="EngifyApp"
  else
    CANDIDATE="$(find .build -type f -path "*/release/*" | head -n 1 || true)"
    if [[ -z "$CANDIDATE" ]]; then
      echo "[release] Could not find release binary in .build" >&2
      exit 1
    fi
    BINARY_NAME="$(basename "$CANDIDATE")"
  fi
fi

BINARY_PATH=".build/arm64-apple-macosx/release/$BINARY_NAME"
if [[ ! -f "$BINARY_PATH" ]]; then
  ALT_PATH="$(find .build -type f -path "*/release/$BINARY_NAME" | head -n 1 || true)"
  if [[ -n "$ALT_PATH" ]]; then
    BINARY_PATH="$ALT_PATH"
  else
    echo "[release] Binary not found: $BINARY_PATH" >&2
    exit 1
  fi
fi

APP_BUNDLE="$OUTPUT_DIR/${APP_NAME}.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST_PATH="$CONTENTS_DIR/Info.plist"
DMG_PATH="$OUTPUT_DIR/${APP_NAME}.dmg"
DMG_STAGING_DIR="$OUTPUT_DIR/.dmg-staging"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BINARY_PATH" "$MACOS_DIR/$BINARY_NAME"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key>
  <string>$BINARY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_MACOS</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
EOF

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "[release] Signing app with identity: $SIGN_IDENTITY"
  codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
  echo "[release] Signing app with ad-hoc identity"
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

mkdir -p "$DMG_STAGING_DIR"
ditto "$APP_BUNDLE" "$DMG_STAGING_DIR/${APP_NAME}.app"
ln -sfn /Applications "$DMG_STAGING_DIR/Applications"

echo "[release] Creating DMG: $DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING_DIR" -ov -format UDZO "$DMG_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
  echo "[release] Notarizing DMG with profile: $NOTARY_PROFILE"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "[release] Stapling notarization ticket"
  xcrun stapler staple "$DMG_PATH"
fi

echo "[release] Done"
echo "  App: $APP_BUNDLE"
echo "  DMG: $DMG_PATH"
