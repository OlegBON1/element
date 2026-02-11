#!/bin/bash
set -euo pipefail

# Build Element as a proper macOS .app bundle
# This is needed for Accessibility API permissions (AXUIElement)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
APP_NAME="Element"
BUNDLE_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Building $APP_NAME..."
cd "$SCRIPT_DIR"
swift build -c debug 2>&1

EXECUTABLE="$BUILD_DIR/debug/$APP_NAME"

if [ ! -f "$EXECUTABLE" ]; then
    echo "ERROR: Executable not found at $EXECUTABLE"
    exit 1
fi

echo "==> Creating .app bundle..."

# Clean previous bundle
rm -rf "$BUNDLE_DIR"

# Create bundle directory structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp "$EXECUTABLE" "$MACOS_DIR/$APP_NAME"

# Copy Info.plist
cp "$SCRIPT_DIR/Element/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

# Copy resources (element-sdk.js and any SPM-bundled resources)
if [ -d "$BUILD_DIR/debug/Element_Element.bundle" ]; then
    cp -R "$BUILD_DIR/debug/Element_Element.bundle/"* "$RESOURCES_DIR/" 2>/dev/null || true
fi

# Copy element-sdk.js directly as fallback
if [ -f "$SCRIPT_DIR/Element/Resources/element-sdk.js" ]; then
    cp "$SCRIPT_DIR/Element/Resources/element-sdk.js" "$RESOURCES_DIR/"
fi

# Copy app icon
if [ -f "$SCRIPT_DIR/Element/Resources/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/Element/Resources/AppIcon.icns" "$RESOURCES_DIR/"
fi

# Sign with entitlements (ad-hoc signing for local development)
ENTITLEMENTS="$SCRIPT_DIR/Element.entitlements"
if [ -f "$ENTITLEMENTS" ]; then
    echo "==> Signing with entitlements..."
    codesign --force --sign - --entitlements "$ENTITLEMENTS" "$BUNDLE_DIR"
else
    echo "==> Ad-hoc signing..."
    codesign --force --sign - "$BUNDLE_DIR"
fi

# Copy to /Applications for easy Accessibility permission granting
echo "==> Installing to /Applications..."
rm -rf "/Applications/$APP_NAME.app"
cp -R "$BUNDLE_DIR" "/Applications/$APP_NAME.app"

echo ""
echo "==> Build complete: /Applications/$APP_NAME.app"
echo ""
echo "To run:"
echo "  open /Applications/$APP_NAME.app"
echo ""
echo "IMPORTANT: After first launch, go to:"
echo "  System Settings -> Privacy & Security -> Accessibility"
echo "  and grant access to Element."
