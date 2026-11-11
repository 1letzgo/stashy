#!/usr/bin/env python3
"""Copy English from Android values/strings.xml into stashy/Localizable.xcstrings.

English is maintained in strings.xml; this keeps the iOS catalog in step without a round trip
through Tolgee. Translations in the catalog are left alone; keys that are gone from strings.xml are
removed from it.

Usage: python3 -I tools/l10n/sync_en.py
"""
from __future__ import annotations

import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
XML = ROOT / "android/app/src/main/res/values/strings.xml"
CATALOG = ROOT / "stashy/Localizable.xcstrings"


def android_text(raw: str) -> str:
    """Unescape an Android string resource value."""
    s = raw.strip()
    if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
        s = s[1:-1]
    out, i = "", 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            out += {"n": "\n", "t": "\t"}.get(n, n)
            i += 2
            continue
        out += c
        i += 1
    return out


def apple_value(text: str) -> str:
    """%1$s -> %@ (one value) or %1$@ (several); %% stays."""
    count = len(re.findall(r"%\d+\$s", text))
    return re.sub(r"%(\d+)\$s", (lambda m: "%@") if count == 1 else (lambda m: f"%{m.group(1)}$@"), text)


def main() -> None:
    english = {}
    for el in ET.parse(XML).getroot().iter("string"):
        english[el.get("name")] = android_text("".join(el.itertext()))

    catalog = json.loads(CATALOG.read_text(encoding="utf-8")) if CATALOG.exists() else \
        {"sourceLanguage": "en", "version": "1.0", "strings": {}}
    strings = catalog.setdefault("strings", {})
    added = changed = 0
    for key, text in english.items():
        value = apple_value(text)
        entry = strings.setdefault(key, {"extractionState": "manual", "localizations": {}})
        unit = entry.setdefault("localizations", {}).setdefault("en", {}).setdefault("stringUnit", {})
        if not unit:
            added += 1
        elif unit.get("value") != value:
            changed += 1
        unit.update({"state": "translated", "value": value})
    removed = [k for k in strings if k not in english]
    for k in removed:
        del strings[k]
    catalog["strings"] = dict(sorted(strings.items()))
    # One line, as Tolgee exports it: a pretty-printed catalog would turn every sync into a 200k-line diff.
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"{len(english)} keys: {added} added, {changed} changed, {len(removed)} removed")


if __name__ == "__main__":
    main()
