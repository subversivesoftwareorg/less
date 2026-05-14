#!/bin/sh
set -e

# Build and package Less as a signed, notarized DMG for distribution.
#
# Prerequisites:
#   brew install create-dmg
#
# Environment variables (optional — prompted if missing):
#   APPLE_ID        — your Apple ID email for notarization
#   TEAM_ID         — your Apple Developer team ID (default: 84CC987JU3)
#   APP_PASSWORD    — app-specific password for notarytool
#
# Usage:
#   ./Scripts/create-dmg.sh                   # full build + sign + notarize
#   ./Scripts/create-dmg.sh --skip-notarize   # build + sign only

APP_NAME="Less"
BUNDLE_ID="com.subversivesoftware.less"
VERSION="1.0.0"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
RELEASE_DIR="$PROJECT_DIR/.build/apple/Products/Release"
STAGING_DIR="$BUILD_DIR/dmg-staging"
NOTARIZE_TIMEOUT="15m"

SKIP_NOTARIZE=false
if [ "${1:-}" = "--skip-notarize" ]; then
    SKIP_NOTARIZE=true
fi

# ── Auto-increment build number ──────────────────────────────────
PLIST="$PROJECT_DIR/Info.plist"
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
NEW_BUILD=$((CURRENT_BUILD + 1))
echo "==> Incrementing build number: $CURRENT_BUILD → $NEW_BUILD"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$PLIST"

DMG_NAME="Less-${VERSION}-b${NEW_BUILD}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

# ── Find Developer ID certificate ────────────────────────────────
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')
if [ -z "$IDENTITY" ]; then
    echo "Error: No 'Developer ID Application' certificate found in keychain."
    if [ "$SKIP_NOTARIZE" = true ]; then
        echo "Continuing with ad-hoc signing..."
        IDENTITY=""
    else
        exit 1
    fi
fi

# ── Notarization credentials ─────────────────────────────────────
if [ "$SKIP_NOTARIZE" = false ] && [ -n "$IDENTITY" ]; then
    TEAM_ID="${TEAM_ID:-84CC987JU3}"

    if [ -z "${APPLE_ID:-}" ]; then
        printf "Apple ID (email) for notarization: "
        read -r APPLE_ID
    fi
    if [ -z "${APP_PASSWORD:-}" ]; then
        printf "App-specific password: "
        stty -echo
        read -r APP_PASSWORD
        stty echo
        echo ""
    fi
fi

# ── Build (Universal) ────────────────────────────────────────────
echo "==> Building $APP_NAME v$VERSION build $NEW_BUILD (Release, Universal: arm64 + x86_64)..."
cd "$PROJECT_DIR"
swift build -c release --arch arm64 --arch x86_64

# ── Create app bundle ────────────────────────────────────────────
echo "==> Creating app bundle..."
APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"
rm -rf "$STAGING_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

# Copy binary
cp "$RELEASE_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Add @rpath so the binary finds frameworks in Contents/Frameworks
install_name_tool -add_rpath @executable_path/../Frameworks "$APP_BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true

# Copy SQLCipher framework
if [ -d "$RELEASE_DIR/SQLCipher.framework" ]; then
    cp -R "$RELEASE_DIR/SQLCipher.framework" "$APP_BUNDLE/Contents/Frameworks/"
fi

# Copy icon
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
fi

# Copy resource bundles
for bundle in "$RELEASE_DIR"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP_BUNDLE/Contents/Resources/"
done

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>Less is More</string>
    <key>CFBundleDisplayName</key>
    <string>Less is More</string>
    <key>CFBundleVersion</key>
    <string>$NEW_BUILD</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>Less uses the camera to capture photos of physical receipts for expense tracking.</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>PDF Document</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>pdf</string>
            </array>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
        </dict>
    </array>
</dict>
</plist>
EOF

# Verify the binary exists
if [ ! -f "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ]; then
    echo "Error: Build produced an app bundle but the binary is missing!"
    exit 1
fi

# ── Code signing ──────────────────────────────────────────────────
if [ -n "$IDENTITY" ]; then
    echo "==> Signing with: $IDENTITY"
    # Sign frameworks first
    if [ -d "$APP_BUNDLE/Contents/Frameworks" ]; then
        find "$APP_BUNDLE/Contents/Frameworks" -type d -name "*.framework" | while read -r fw; do
            codesign --force --options runtime --sign "$IDENTITY" --timestamp "$fw"
        done
    fi
    # Sign the app
    codesign --force --options runtime \
        --sign "$IDENTITY" \
        --timestamp \
        --entitlements "$PROJECT_DIR/Resources/Less.entitlements" \
        "$APP_BUNDLE"
    echo "==> Verifying signature..."
    codesign --verify --verbose=2 "$APP_BUNDLE"
    echo "    Signature OK"
else
    echo "==> Ad-hoc signing..."
    codesign --force --deep --sign - --entitlements "$PROJECT_DIR/Resources/Less.entitlements" "$APP_BUNDLE"
fi

# ── Verify universal binary ──────────────────────────────────────
ARCHS=$(lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || echo "unknown")
echo "    Architectures: $ARCHS"

# ── Create DMG ───────────────────────────────────────────────────
echo "==> Creating DMG..."
mkdir -p "$BUILD_DIR"
rm -f "$DMG_PATH"

if command -v create-dmg >/dev/null 2>&1; then
    ICON_PATH="$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    VOL_ICON_FLAG=""
    if [ -f "$ICON_PATH" ]; then
        VOL_ICON_FLAG="--volicon $ICON_PATH"
    fi

    create-dmg \
        --volname "$APP_NAME" \
        $VOL_ICON_FLAG \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 175 190 \
        --app-drop-link 425 190 \
        --hide-extension "$APP_NAME.app" \
        "$DMG_PATH" \
        "$STAGING_DIR" \
        || true
    if [ ! -f "$DMG_PATH" ]; then
        echo "Error: create-dmg failed to produce $DMG_NAME"
        exit 1
    fi
else
    ln -sf /Applications "$STAGING_DIR/Applications"
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$STAGING_DIR" \
        -ov -format UDZO \
        "$DMG_PATH"
fi

# Sign the DMG
if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" --timestamp "$DMG_PATH"
fi

# ── Notarize ─────────────────────────────────────────────────────
if [ "$SKIP_NOTARIZE" = false ] && [ -n "$IDENTITY" ]; then
    echo "==> Submitting for notarization (timeout: ${NOTARIZE_TIMEOUT})..."
    if xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_PASSWORD" \
        --wait \
        --timeout "$NOTARIZE_TIMEOUT"; then

        echo "==> Stapling..."
        xcrun stapler staple "$DMG_PATH"
    else
        echo ""
        echo "WARNING: Notarization did not complete within ${NOTARIZE_TIMEOUT}."
        echo "Check status: xcrun notarytool history --apple-id $APPLE_ID --team-id $TEAM_ID --password YOUR_PASSWORD"
        echo "Then staple:  xcrun stapler staple $DMG_PATH"
    fi
fi

# ── Cleanup ──────────────────────────────────────────────────────
rm -rf "$STAGING_DIR"

echo ""
echo "Done! DMG created at:"
echo "  $DMG_PATH"
echo "  Version: $VERSION (build $NEW_BUILD)"
echo "  Size: $(ls -lh "$DMG_PATH" | awk '{print $5}')"
echo "  Architectures: $ARCHS"
if [ -n "$IDENTITY" ]; then
    echo "  Signed with: $IDENTITY"
fi

echo ""
echo "Build number $NEW_BUILD has been written to Info.plist."

# ── Git tag ──────────────────────────────────────────────────────
TAG="v${VERSION}-b${NEW_BUILD}"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git add "$PLIST"
    git commit -m "Build $NEW_BUILD for v$VERSION distribution" 2>/dev/null || true
    git tag -a "$TAG" -m "$APP_NAME $VERSION build $NEW_BUILD"
    echo "  Tagged: $TAG"
    echo ""
    echo "Push with: git push && git push --tags"
else
    echo "Not in a git repo — skipping tag."
fi
