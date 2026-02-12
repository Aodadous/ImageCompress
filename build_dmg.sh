#!/bin/bash

# Configuration
APP_NAME="Tinify"
SCHEME_NAME="Tinify"
PROJECT_PATH="Tinify.xcodeproj"
ARCHIVE_PATH="./build/Tinify.xcarchive"
EXPORT_PATH="./build/Export"
DMG_NAME="Tinify_Installer.dmg"

# Clean build folder
echo "🧹 Cleaning build folder..."
rm -rf "./build"

# 1. Archive the app
echo "📦 Archiving app..."
xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_NAME" \
  -archivePath "$ARCHIVE_PATH" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_ENTITLEMENTS="" \
  CODE_SIGNING_ALLOWED=NO

if [ $? -ne 0 ]; then
    echo "❌ Archive failed"
    exit 1
fi

# 2. Export the app (copy from archive)
echo "📂 Exporting app..."
mkdir -p "$EXPORT_PATH"
# Direct copy is simpler for unsigned apps than using -exportArchive
cp -r "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$EXPORT_PATH/"

if [ $? -ne 0 ]; then
    echo "❌ Export failed"
    exit 1
fi

# 3. Create DMG
echo "💿 Creating DMG..."

# Create a temporary folder for DMG content
DMG_SOURCE="./build/dmg_source"
mkdir -p "$DMG_SOURCE"

# Copy App to source
cp -r "$EXPORT_PATH/$APP_NAME.app" "$DMG_SOURCE/"

# Create Applications shortcut
ln -s /Applications "$DMG_SOURCE/Applications"

# Create DMG using hdiutil
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_SOURCE" \
  -ov \
  -format UDZO \
  "$DMG_NAME"

if [ $? -ne 0 ]; then
    echo "❌ DMG creation failed"
    exit 1
fi

# Clean up
rm -rf "./build"

echo "✅ Done! DMG created at: $(pwd)/$DMG_NAME"
