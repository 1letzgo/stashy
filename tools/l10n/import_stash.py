#!/usr/bin/env python3
"""Seed Tolgee with Stash's own translations of the terms stashy shares with Stash's web UI.

For every key whose English text is exactly a Stash term (at most 4 words, no values), the
translation from stashapp/stash's locale files is pushed to Tolgee for each target language.
Existing translations in Tolgee are kept (force mode KEEP), so this never overwrites work done
there. The keys get the Tolgee tag "stash" so they can be reviewed as a group.

Stash's translations are AGPL-3.0 (Weblate); only single terms are taken, and the
acknowledgements name Stash as the source.

Usage: TOLGEE_API_KEY=… python3 -I tools/l10n/import_stash.py [--dry-run]
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glossary  # noqa: E402  (fetch_locales, flatten, TARGETS, STASH_COMMIT)
import migrate_literals  # noqa: E402  (android_escape)
import sync_en  # noqa: E402  (android_text)

ROOT = Path(__file__).resolve().parents[2]
XML = ROOT / "android/app/src/main/res/values/strings.xml"
MAX_WORDS = 4


def matches() -> dict[str, dict[str, str]]:
    """key -> {language: Stash translation}"""
    locales = glossary.fetch_locales(glossary.STASH_COMMIT)
    gb, us = glossary.flatten(locales["en-GB"]), glossary.flatten(locales["en-US"])
    english = {**gb, **us}
    by_text: dict[str, list[str]] = {}
    for k, v in english.items():
        by_text.setdefault(v, []).append(k)
    targets = {lang: glossary.flatten(locales[name]) for lang, name in glossary.TARGETS.items()}

    out: dict[str, dict[str, str]] = {}
    for el in ET.parse(XML).getroot().iter("string"):
        key, text = el.get("name"), sync_en.android_text("".join(el.itertext()))
        if "%" in text or "{" in text or len(text.split()) > MAX_WORDS:
            continue
        stash_keys = sorted(by_text.get(text, []), key=lambda k: (k.count("."), len(k)))
        if not stash_keys:
            continue
        per_lang = {}
        for lang, flat in targets.items():
            value = next((flat[k] for k in stash_keys if flat.get(k)), None)
            if value and "{" not in value:
                per_lang[lang] = value
        if per_lang:
            out[key] = per_lang
    return out


def main() -> None:
    found = matches()
    langs = sorted({lang for v in found.values() for lang in v})
    print(f"{len(found)} keys with Stash translations; per language:",
          {lang: sum(lang in v for v in found.values()) for lang in langs})
    if "--dry-run" in sys.argv:
        for key, v in list(found.items())[:10]:
            print(f"  {key}: de={v.get('de')!r} fr={v.get('fr')!r} ja={v.get('ja')!r}")
        return
    if not os.environ.get("TOLGEE_API_KEY"):
        sys.exit("Set TOLGEE_API_KEY to a project API key of the Tolgee project stashy")

    with tempfile.TemporaryDirectory() as tmp:
        files = []
        for lang in langs:
            lines = ['<?xml version="1.0" encoding="utf-8"?>', "<resources>"]
            for key in sorted(found):
                if lang in found[key]:
                    value = migrate_literals.android_escape(found[key][lang].replace("%", "%%"))
                    lines.append(f'    <string name="{key}">{value}</string>')
            lines.append("</resources>")
            path = Path(tmp) / f"{lang}.xml"
            path.write_text("\n".join(lines) + "\n", encoding="utf-8")
            files.append({"path": str(path), "language": lang})
        config = {
            "apiUrl": "https://tolgee.shelf.am",
            "projectId": 2,
            "format": "ANDROID_XML",
            "push": {"files": files, "languages": langs, "forceMode": "KEEP"},
        }
        cfg = Path(tmp) / "tolgeerc.json"
        cfg.write_text(json.dumps(config), encoding="utf-8")
        subprocess.run(["npx", "--yes", "@tolgee/cli@2.21.0", "--config", str(cfg), "push"], check=True)
    keys_file = ROOT / "localization" / "stash-seeded-keys.txt"
    keys_file.write_text("\n".join(sorted(found)) + "\n", encoding="utf-8")
    print(f"pushed; keys listed in {keys_file.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
