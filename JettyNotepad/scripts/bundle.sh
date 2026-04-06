#!/bin/bash
set -euo pipefail

# bundle.sh — Package JettyNotepad into a .app bundle
# Usage: ./scripts/bundle.sh [--release]
#
# Output: build/JettyNotepad.app

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

# Copy binary
cp "$BINARY" "$MACOS/JettyNotepad"

# Info.plist
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>JettyNotepad</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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
            <key>LSTypeIsPackage</key>
            <false/>
            <key>NSDocumentClass</key>
            <string>JNTDocument</string>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Plain Text</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.plain-text</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>txt</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Markdown</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>md</string>
                <string>markdown</string>
            </array>
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

# PkgInfo
echo -n "APPL????" > "$CONTENTS/PkgInfo"

# Generate a simple app icon (blue circle with J)
# Using a minimal .icns isn't trivial without iconutil, so we skip it for now
# The app will use the default icon

echo "=== Done ==="
echo ""
echo "  $APP_DIR"
echo ""
echo "Run with:"
echo "  open $APP_DIR"
echo ""
echo "Or from terminal:"
echo "  $MACOS/JettyNotepad"
