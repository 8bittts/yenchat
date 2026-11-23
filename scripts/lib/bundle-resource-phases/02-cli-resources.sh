#!/bin/bash
# Sourced by bundle-yen-resources.sh in the shared bundling shell.

# Bundle commands directory
echo "  Bundling commands..."
rm -rf "$APP_PATH/Contents/Resources/commands"
cp -Rp "$YEN_CLI_DIR/commands" "$APP_PATH/Contents/Resources/"

# Bundle lib directory
echo "  Bundling lib..."
rm -rf "$APP_PATH/Contents/Resources/lib"
cp -Rp "$YEN_CLI_DIR/lib" "$APP_PATH/Contents/Resources/"

# Bundle fixture resources used by shipped IDE benchmark harness
echo "  Bundling fixtures..."
rm -rf "$APP_PATH/Contents/Resources/fixtures"
if [ -d "$YEN_CLI_DIR/fixtures" ]; then
    cp -Rp "$YEN_CLI_DIR/fixtures" "$APP_PATH/Contents/Resources/"
fi

# NOTE: shell/ directory removed (was legacy yen.zsh with unused analytics/learning)
# Shell integration is now only in shell-integration/ (handled below)

# Update version and commit in Info.plist (Sparkle keys are set during vendor rebrand)
echo "  Updating Info.plist..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION_INT" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :YENBuild $VERSION" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :YENCommit $COMMIT" "$APP_PATH/Contents/Info.plist"

: # Keep optional final checks from becoming a failed source command.

cp "$CUSTOMIZATIONS_DIR/icons/YENMenuMark.svg" "$APP_PATH/Contents/Resources/"
rm -rf "$APP_PATH/Contents/Resources/Notices"
mkdir -p "$APP_PATH/Contents/Resources/Notices"
cp "$CUSTOMIZATIONS_DIR/notices/"*.txt "$APP_PATH/Contents/Resources/Notices/"
