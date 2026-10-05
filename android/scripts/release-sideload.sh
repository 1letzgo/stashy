#!/bin/zsh
# Signed sideload release of stashy for Android → GitHub Release of 1letzgo/stashy
# (asset stashy.apk, marked latest — the in-app self-update downloads it from there).
# NAS=1 additionally copies the APK to the Tower (old update path, kept for the transition).
set -e
cd "$(dirname "$0")/.."
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
./gradlew assembleSideloadRelease -q --max-workers=2 -Dorg.gradle.jvmargs=-Xmx2g -Pkotlin.compiler.execution.strategy=in-process
APK=$(ls -t ~/Library/Caches/stashy-android/*/app/outputs/apk/sideload/release/app-sideload-release.apk | head -1)
CODE=$(git -C .. rev-list --count HEAD)
NAME=$(grep -m1 'versionName = ' app/build.gradle.kts | sed 's/.*"\(.*\)".*/\1/')
TMP=$(mktemp -d); cp "$APK" "$TMP/stashy.apk"
TAG="android-v$NAME-$CODE"
gh release create "$TAG" "$TMP/stashy.apk" -R 1letzgo/stashy --target "$(git -C .. rev-parse HEAD)" --latest \
  --title "stashy for Android $NAME ($CODE)" \
  --notes "Android beta build $NAME ($CODE). Install stashy.apk on Android phones and Android TV; the app updates itself from the latest release. Beta builds expire 30 days after their build."
echo "released $TAG"
if [ "$NAS" = "1" ]; then
  mount | grep -q " on /Volumes/appdata " || osascript -e 'mount volume "smb://Tower._smb._tcp.local/appdata"' >/dev/null
  DEST=/Volumes/appdata/party_server/app
  cp "$APK" "$DEST/.stashy.apk.part" && mv -f "$DEST/.stashy.apk.part" "$DEST/stashy.apk"
  [ "$(shasum -a 256 < "$APK")" = "$(shasum -a 256 < "$DEST/stashy.apk")" ] && echo "NAS hash OK"
fi
