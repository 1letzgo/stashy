#!/bin/bash

echo "🚀 Incrementing Build Number..."

# Path to Info.plist passed by Xcode environment
plist="$PRODUCT_SETTINGS_PATH" 

# Standard Xcode setup:
plistPath="${PROJECT_DIR}/${INFOPLIST_FILE}"

# Only bump version if we are in Release configuration (standard for App Store builds)
if [ "$CONFIGURATION" != "Release" ]; then
    echo "ℹ️  Skipping build number increment for $CONFIGURATION configuration"
    exit 0
fi

if [ -f "$plistPath" ]; then
    # Get current version
    buildNum=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$plistPath")
    
    # Check if it's a number
    if [[ "$buildNum" =~ ^[0-9]+$ ]]; then
        newBuildNum=$(($buildNum + 1))
        
        # Update the source plist
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $newBuildNum" "$plistPath"
        
        echo "✅ Build number bumped to $newBuildNum"
    else
        echo "⚠️  Build number ($buildNum) is not a simple integer. Skipping auto-increment."
    fi
else
    echo "❌ Could not find Info.plist at $plistPath"
    exit 1
fi
