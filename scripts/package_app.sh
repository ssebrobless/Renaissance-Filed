#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Renaissance Filed"
EXECUTABLE_NAME="RenaissanceLedger"
HELPER_APP_NAME="Renaissance Harness"
HELPER_EXECUTABLE_NAME="RenaissanceHarness"
APP_VERSION="1.0"
APP_BUILD="1"
ICON_SOURCE="branding/RenaissanceFiled.png"
ICON_NAME="RenaissanceFiled"
BUILD_DIR=".build/release"
DIST_DIR="dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
HELPER_APP_DIR="$DIST_DIR/$HELPER_APP_NAME.app"
SIGNING_ENV_FILE="${HOME}/.renaissance_ledger_codesign_env"

if [ -f "$SIGNING_ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$SIGNING_ENV_FILE"
fi

SIGN_IDENTITY="${RENAISSANCE_CODESIGN_IDENTITY:-}"
SIGN_KEYCHAIN="${RENAISSANCE_CODESIGN_KEYCHAIN:-}"
SIGN_IDENTITY_SHA=""

if [ -n "$SIGN_IDENTITY" ]; then
  FIND_IDENTITY_ARGS=(-v -p codesigning)
  if [ -n "$SIGN_KEYCHAIN" ]; then
    FIND_IDENTITY_ARGS+=( "$SIGN_KEYCHAIN" )
  fi
  IDENTITY_LINE="$(security find-identity "${FIND_IDENTITY_ARGS[@]}" 2>/dev/null | grep -F "$SIGN_IDENTITY" | head -n 1 || true)"
  if [ -z "$IDENTITY_LINE" ]; then
    if [ -n "$SIGN_KEYCHAIN" ] \
      && security find-certificate -c "$SIGN_IDENTITY" "$SIGN_KEYCHAIN" >/dev/null 2>&1 \
      && security find-key -s -t private "$SIGN_KEYCHAIN" >/dev/null 2>&1; then
      echo "Configured signing identity '$SIGN_IDENTITY' exists in '$SIGN_KEYCHAIN' but is not trusted yet; run the local trust helper on the Mac, then rebuild. Falling back to ad-hoc signing." >&2
    else
      echo "Configured signing identity '$SIGN_IDENTITY' was not found; falling back to ad-hoc signing." >&2
    fi
    SIGN_IDENTITY=""
    SIGN_KEYCHAIN=""
  else
    SIGN_IDENTITY_SHA="$(echo "$IDENTITY_LINE" | awk '{ print $2 }')"
  fi
fi

rm -rf "$DIST_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
mkdir -p "$HELPER_APP_DIR/Contents/MacOS" "$HELPER_APP_DIR/Contents/Resources"

swift package clean
swift build -c release

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

if [ -f "$ICON_SOURCE" ]; then
  bash scripts/build_icns.sh "$ICON_SOURCE" "$APP_DIR/Contents/Resources/$ICON_NAME.icns"
fi

cp "$BUILD_DIR/$HELPER_EXECUTABLE_NAME" "$HELPER_APP_DIR/Contents/MacOS/$HELPER_APP_NAME"
chmod +x "$HELPER_APP_DIR/Contents/MacOS/$HELPER_APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>Renaissance Filed</string>
  <key>CFBundleExecutable</key>
  <string>Renaissance Filed</string>
  <key>CFBundleIdentifier</key>
  <string>com.ssebrobless.renaissanceledger</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>RenaissanceFiled</string>
  <key>CFBundleName</key>
  <string>Renaissance Filed</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${APP_BUILD}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

cat > "$HELPER_APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>Renaissance Harness</string>
  <key>CFBundleExecutable</key>
  <string>Renaissance Harness</string>
  <key>CFBundleIdentifier</key>
  <string>com.ssebrobless.renaissanceharness</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Renaissance Harness</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${APP_BUILD}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

codesign_app() {
  local app_path="$1"
  local -a args=(--force --deep --sign -)
  if [ -n "$SIGN_IDENTITY_SHA" ]; then
    if [ -n "$SIGN_KEYCHAIN" ]; then
      security unlock-keychain -p '' "$SIGN_KEYCHAIN" >/dev/null
      security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k '' "$SIGN_KEYCHAIN" >/dev/null
      security list-keychains -d user -s "$HOME/Library/Keychains/login.keychain-db" "$SIGN_KEYCHAIN" >/dev/null
      security default-keychain -d user -s "$HOME/Library/Keychains/login.keychain-db" >/dev/null
      args=(--force --deep --sign "$SIGN_IDENTITY_SHA" --keychain "$SIGN_KEYCHAIN")
    else
      args=(--force --deep --sign "$SIGN_IDENTITY_SHA")
    fi
  fi
  codesign "${args[@]}" "$app_path"
}

codesign_app "$APP_DIR"
codesign_app "$HELPER_APP_DIR"

cd "$DIST_DIR"
zip -r "RenaissanceFiled-macos.zip" "$APP_NAME.app" "$HELPER_APP_NAME.app"
shasum -a 256 "RenaissanceFiled-macos.zip" > "RenaissanceFiled-macos.sha256"

echo "Created artifacts in $DIST_DIR"
