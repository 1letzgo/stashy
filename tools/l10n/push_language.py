#!/usr/bin/env python3
"""Push one language's translations (a JSON object key -> text) to Tolgee.

Checks every text against English first: the key must exist in values/strings.xml and carry the
same placeholders (%1$s, %2$s …). Texts that fail are listed and left out.

Usage: TOLGEE_API_KEY=… python3 -I tools/l10n/push_language.py de translations.json [--keep]
  --keep   keep translations that already exist in Tolgee (default: overwrite them)
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
import migrate_literals  # noqa: E402  (android_escape)
import sync_en  # noqa: E402  (android_text)

ROOT = Path(__file__).resolve().parents[2]
XML = ROOT / "android/app/src/main/res/values/strings.xml"
PLACEHOLDER = re.compile(r"%\d+\$s")


def check(english: dict[str, str], texts: dict[str, str]) -> tuple[dict[str, str], list[str]]:
    good, problems = {}, []
    for key, text in texts.items():
        if key not in english:
            problems.append(f"{key}: unknown key")
        elif sorted(PLACEHOLDER.findall(text)) != sorted(PLACEHOLDER.findall(english[key])):
            problems.append(f"{key}: placeholders {PLACEHOLDER.findall(text)} vs {PLACEHOLDER.findall(english[key])}")
        elif not text.strip():
            problems.append(f"{key}: empty")
        else:
            good[key] = text
    return good, problems


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    lang, source = sys.argv[1], Path(sys.argv[2])
    english = {el.get("name"): sync_en.android_text("".join(el.itertext()))
               for el in ET.parse(XML).getroot().iter("string")}
    good, problems = check(english, json.loads(source.read_text(encoding="utf-8")))
    missing = sorted(set(english) - set(good))
    print(f"{lang}: {len(good)} texts ok, {len(problems)} rejected, {len(missing)} keys without text")
    for p in problems[:30]:
        print("  ", p)
    if not os.environ.get("TOLGEE_API_KEY"):
        sys.exit("Set TOLGEE_API_KEY to a project API key of the Tolgee project stashy")

    with tempfile.TemporaryDirectory() as tmp:
        lines = ['<?xml version="1.0" encoding="utf-8"?>', "<resources>"]
        for key in sorted(good):
            text = good[key]
            if not PLACEHOLDER.search(text):
                text = text.replace("%%", "%").replace("%", "%%")
            lines.append(f'    <string name="{key}">{migrate_literals.android_escape(text)}</string>')
        lines.append("</resources>")
        path = Path(tmp) / f"{lang}.xml"
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        config = {
            "apiUrl": "https://tolgee.shelf.am", "projectId": 2, "format": "ANDROID_XML",
            "push": {"files": [{"path": str(path), "language": lang}], "languages": [lang],
                     "forceMode": "KEEP" if "--keep" in sys.argv else "OVERRIDE"},
        }
        cfg = Path(tmp) / "tolgeerc.json"
        cfg.write_text(json.dumps(config), encoding="utf-8")
        subprocess.run(["npx", "--yes", "@tolgee/cli@2.21.0", "--config", str(cfg), "push"], check=True)


if __name__ == "__main__":
    main()
