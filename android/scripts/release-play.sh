#!/bin/zsh
# Signed Play release of stashy for Android → Google Play (default track: internal).
#   scripts/release-play.sh [track] [release notes]
# Track: internal | alpha (closed test) | beta | production. versionCode = commit count of HEAD.
set -e
cd "$(dirname "$0")/.."
TRACK=${1:-internal}
NOTES=${2:-}
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
./gradlew bundlePlayRelease -q --max-workers=2 -Dorg.gradle.jvmargs=-Xmx2g -Pkotlin.compiler.execution.strategy=in-process
AAB=$(ls -t ~/Library/Caches/stashy-android/*/app/outputs/bundle/playRelease/app-play-release.aab | head -1)
echo "built $AAB (versionCode $(git -C .. rev-list --count HEAD))"
python3 scripts/play_publish.py upload "$AAB" --track "$TRACK" ${NOTES:+--notes "$NOTES"}
