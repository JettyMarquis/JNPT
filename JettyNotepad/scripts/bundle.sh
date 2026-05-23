#!/bin/bash
set -euo pipefail

# bundle.sh — Build JettyNotepad and package it into a signed .app bundle.
# Usage: ./scripts/bundle.sh [--release]
#
# Output: build/JettyNotepad.app
# Run:    open build/JettyNotepad.app
#         (First launch: right-click → Open to bypass Gatekeeper once)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/JettyNotepad.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

CONFIG="debug"
if [[ "${1:-}" == "--release" ]]; then
    CONFIG="release"
fi

echo "=== Building JettyNotepad ($CONFIG) ==="
cd "$PROJECT_DIR"
if [[ "$CONFIG" == "release" ]]; then
    swift build -c release 2>&1
    BINARY="$(swift build -c release --show-bin-path)/JettyNotepad"
else
    swift build 2>&1
    BINARY="$(swift build --show-bin-path)/JettyNotepad"
fi

echo "=== Creating .app bundle ==="
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BINARY" "$MACOS/JettyNotepad"

cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>JettyNotepad</string>
    <key>CFBundleIdentifier</key>
    <string>com.jettymarquis.jettynotepad</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>JettyNotepad</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>JettyNotepad Document</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.jettymarquis.jettynotepad.jnt</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>jnt</string>
            </array>
            <key>NSDocumentClass</key>
            <string>JNTDocument</string>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.data</string>
                <string>public.content</string>
            </array>
            <key>UTTypeDescription</key>
            <string>JettyNotepad Document</string>
            <key>UTTypeIdentifier</key>
            <string>com.jettymarquis.jettynotepad.jnt</string>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>jnt</string>
                </array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo -n "APPL????" > "$CONTENTS/PkgInfo"

echo "=== Ad-hoc signing ==="
codesign --force --deep --sign - "$APP_DIR"

echo ""
echo "=== Done: $APP_DIR ==="
echo ""
echo "  open build/JettyNotepad.app"
echo ""
echo "  First launch: right-click → Open (one-time Gatekeeper bypass)"
