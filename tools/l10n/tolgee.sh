#!/usr/bin/env bash
# Sync UI strings with Tolgee (https://tolgee.shelf.am, project "stashy").
#
#   tools/l10n/tolgee.sh push   English from Android strings.xml -> Tolgee (new keys, changed English)
#   tools/l10n/tolgee.sh pull   all languages -> stashy/Localizable.xcstrings + android res/values-*/strings.xml
#
# Needs TOLGEE_API_KEY (a project API key of "stashy"). Never commit it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLI=(npx --yes @tolgee/cli@2.21.0 --config "$ROOT/tools/l10n/tolgeerc.json")
RES="$ROOT/android/app/src/main/res"

: "${TOLGEE_API_KEY:?Set TOLGEE_API_KEY to a project API key of the Tolgee project stashy}"
export TOLGEE_API_KEY

# Tolgee language tag -> Android resource folder
android_dir() {
  case "$1" in
    en) echo values ;;
    pt-BR) echo values-pt-rBR ;;
    zh-Hans) echo values-b+zh+Hans ;;
    zh-Hant) echo values-b+zh+Hant ;;
    *) echo "values-$1" ;;
  esac
}

case "${1:-}" in
  push)
    # push.files in tolgeerc.json are relative to that file (tools/l10n)
    "${CLI[@]}" push
    ;;
  pull)
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    "${CLI[@]}" pull --format ANDROID_XML --path "$tmp/android" \
      --file-structure-template "{languageTag}/strings.{extension}"
    for dir in "$tmp"/android/*/; do
      tag="$(basename "$dir")"
      [ "$tag" = en ] && continue   # English stays the hand-maintained source in values/
      mkdir -p "$RES/$(android_dir "$tag")"
      cp "$dir/strings.xml" "$RES/$(android_dir "$tag")/strings.xml"
    done
    # Tolgee writes a value with a leading or trailing space unquoted, and aapt drops that space:
    # " This cannot be undone." would glue onto the sentence before it. Quote such values.
    python3 -I - "$RES" <<'PY'
import re, sys
from pathlib import Path
for f in Path(sys.argv[1]).glob("values-*/strings.xml"):
    s = f.read_text(encoding="utf-8")
    t = re.sub(r'(<string name="[^"]+">)((?: [^<"]*)|(?:[^<"]* ))(</string>)', r'\1"\2"\3', s)
    if t != s:
        f.write_text(t, encoding="utf-8")
PY
    "${CLI[@]}" pull --format APPLE_XCSTRINGS --path "$tmp/apple" \
      --file-structure-template "Localizable.{extension}"
    cp "$tmp/apple/Localizable.xcstrings" "$ROOT/stashy/Localizable.xcstrings"
    ;;
  *)
    sed -n '2,8p' "$0"; exit 1 ;;
esac
