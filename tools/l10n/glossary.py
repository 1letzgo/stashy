#!/usr/bin/env python3
"""Compare stashy's UI wording with Stash's web UI (stashapp/stash locales).

Writes
  localization/glossary.csv         one row per Stash term the apps use, with the
                                    forms found in Swift / Kotlin and Stash's own
                                    translation of the term per target language
  localization/glossary-review.md   the rows that need a decision, plus frequent
                                    stashy labels Stash has no term for

Stash's locale files are fetched at a pinned commit into tools/l10n/.cache
(not committed: Stash is AGPL, only single terms end up in the glossary).

Usage: python3 -I tools/l10n/glossary.py [--commit <sha>]
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import urllib.request
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CACHE = Path(__file__).resolve().parent / ".cache"
OUT = ROOT / "localization"

STASH_COMMIT = "a115a2f957"  # stashapp/stash develop, 2026-10-27
LOCALE_URL = "https://raw.githubusercontent.com/stashapp/stash/{sha}/ui/v2.5/src/locales/{name}.json"

# Target languages: column name -> Stash locale file
TARGETS = {
    "de": "de-DE", "fr": "fr-FR", "nl": "nl-NL", "sv": "sv-SE", "da": "da-DK",
    "nb": "nb-NO", "pl": "pl-PL", "ja": "ja-JP", "pt-BR": "pt-BR",
    "zh-Hans": "zh-CN", "zh-Hant": "zh-TW", "ar": "ar",
}

SOURCES = [
    (ROOT / "stashy", "*.swift", "ios"),
    (ROOT / "stashyTV", "*.swift", "tv"),
    (ROOT / "stashyMac", "*.swift", "mac"),
    (ROOT / "android/app/src/main/java", "*.kt", "android"),
]

# Names stashy (or older Stash versions) used for a Stash term. Key = Stash en value.
ALIASES = {
    "O Count": ["O-Counter", "O Counter", "OCounter", "O-Counts", "O's"],
    "Groups": ["Movies"],
    "Group": ["Movie"],
    "Markers": ["Scene Markers"],
    "Marker": ["Scene Marker"],
    "Favorite": ["Favourite", "Favorited"],
    "Organized": ["Organised"],
    "Play Count": ["Plays", "View Count", "Views"],
    "Resume Time": ["Resume Point", "Resume Position"],
    "Last Played At": ["Last Played", "Last Watched"],
    "Studios": ["Channels"],
    "Rating": ["Stars"],
    "Details": ["Description"],
}

STRING_RE = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
SWIFT_INTERP = re.compile(r"\\\((?:[^()]|\([^()]*\))*\)")
KOTLIN_INTERP = re.compile(r"\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*")
IDENTIFIER = re.compile(
    r"^[a-z0-9_.\-/:]*$"          # keys, SF symbols, fields
    r"|^[a-z][A-Za-z0-9_]*$"       # camelCase identifiers
    r"|^[A-Z][A-Z0-9_]*$"          # GraphQL enums (RATING, AND)
)
NON_UI_LINE = re.compile(
    r"AppLog\.|print\(|Log\.[dewi]\(|forKey:|UserDefaults|getString\(|putString\(|"
    r"NotificationCenter|Notification\.Name|\.post\(name|setValue\(|accessibilityIdentifier|"
    r"#Preview|@available|fatalError|precondition"
)


def fetch_locales(sha: str) -> dict[str, dict]:
    folder = CACHE / sha
    folder.mkdir(parents=True, exist_ok=True)
    out = {}
    for name in ["en-GB", "en-US", *TARGETS.values()]:
        path = folder / f"{name}.json"
        if not path.exists():
            with urllib.request.urlopen(LOCALE_URL.format(sha=sha, name=name), timeout=30) as r:
                path.write_bytes(r.read())
        out[name] = json.loads(path.read_text(encoding="utf-8"))
    return out


def flatten(obj: dict, prefix: str = "") -> dict[str, str]:
    flat = {}
    for k, v in obj.items():
        key = f"{prefix}{k}"
        if isinstance(v, dict):
            flat.update(flatten(v, key + "."))
        elif isinstance(v, str):
            flat[key] = v
    return flat


def is_term(text: str) -> bool:
    if not text or "{" in text or "<" in text or len(text) > 40:
        return False
    if text.endswith((".", "?", "!", ":")):
        return False
    if text.islower() and " " not in text:  # function words: and, or, of
        return False
    return 1 <= len(text.split()) <= 4 and re.search(r"[A-Za-z]", text) is not None


def collect_literals() -> list[tuple[str, str]]:
    """(literal, 'platform:path:line') for every UI-looking string literal."""
    found = []
    for base, pattern, platform in SOURCES:
        if not base.exists():
            continue
        for path in sorted(base.rglob(pattern)):
            rel = path.relative_to(ROOT)
            for n, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
                stripped = line.strip()
                if stripped.startswith(("//", "*", "/*")) or NON_UI_LINE.search(line):
                    continue
                for m in STRING_RE.finditer(line):
                    raw = m.group(1)
                    text = SWIFT_INTERP.sub("…", raw) if platform != "android" else KOTLIN_INTERP.sub("…", raw)
                    text = text.replace("\\n", " ").strip()
                    if not re.search(r"[A-Za-z]{2}", text) or IDENTIFIER.match(text):
                        continue
                    if "://" in text or text.startswith(("query ", "mutation ", "fragment ")):
                        continue
                    found.append((text, f"{platform}:{rel}:{n}"))
    return found


def form_regex(term: str) -> re.Pattern:
    """Matches the term with spaces/hyphens interchangeable, any case, as whole words."""
    parts = [re.escape(p) for p in re.split(r"[\s\-]+", term)]
    return re.compile(r"(?<![A-Za-z0-9])" + r"[\s\-]?".join(parts) + r"(?![A-Za-z0-9])", re.I)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--commit", default=STASH_COMMIT)
    args = ap.parse_args()

    locales = fetch_locales(args.commit)
    gb, us = flatten(locales["en-GB"]), flatten(locales["en-US"])
    en = {**gb, **us}  # Stash's en-US = en-GB plus US spellings
    targets = {col: flatten(locales[name]) for col, name in TARGETS.items()}

    # One row per English term; keep all keys, the shortest one leads.
    keys_by_term: dict[str, list[str]] = defaultdict(list)
    for key, value in en.items():
        if is_term(value):
            keys_by_term[value].append(key)
    # Case variants in Stash itself ("Play Count" / "Play count"): prefer the title-case one.
    by_folded: dict[str, list[str]] = defaultdict(list)
    for term in keys_by_term:
        by_folded[re.sub(r"[\s\-]+", " ", term.lower())].append(term)

    literals = collect_literals()
    labels = Counter(t for t, _ in literals)

    rows = []
    covered_literals: set[str] = set()
    for folded, terms in sorted(by_folded.items()):
        terms.sort(key=lambda t: (-sum(w[:1].isupper() for w in t.split()), -len(keys_by_term[t])))
        term = terms[0]
        keys = sorted({k for t in terms for k in keys_by_term[t]}, key=lambda k: (k.count("."), len(k)))
        patterns = [(term, form_regex(term))] + [(a, form_regex(a)) for a in ALIASES.get(term, [])]
        gb_value = gb.get(keys[0])
        if gb_value and gb_value != term:
            patterns.append((gb_value, form_regex(gb_value)))

        forms: Counter = Counter()       # every surface form found
        label_forms: Counter = Counter() # forms of literals that are just the term
        label_uses = text_uses = 0
        places: Counter = Counter()
        alias_forms: set[str] = set()
        for text, where in literals:
            for name, rx in patterns:
                hits = rx.findall(text)
                if not hits:
                    continue
                for h in hits:
                    forms[h] += 1
                    if name != term:
                        alias_forms.add(h)
                if rx.fullmatch(text.strip(" :…")):
                    label_uses += 1
                    label_forms[hits[0]] += 1
                    covered_literals.add(text)
                else:
                    text_uses += 1
                places[where.rsplit(":", 1)[0]] += 1
                break
        if not forms:
            continue

        exact = forms.get(term, 0)
        term_rx = form_regex(term)
        spelling_forms = {f for f in forms if f not in alias_forms and f.lower() != term.lower()}
        case_forms = {f for f in label_forms if f != term and f.lower() == term.lower()}
        if alias_forms:
            status = "alias"
        elif spelling_forms:
            status = "spelling"
        elif case_forms:
            status = "case"
        elif label_uses == 0:
            status = "in-text"
        else:
            status = "ok"

        row = {
            "stash_en": term,
            "stash_keys": " ".join(keys[:4]) + (" …" if len(keys) > 4 else ""),
            "status": status,
            "proposal": term,
            "app_forms": "; ".join(f"{f} ×{c}" for f, c in forms.most_common()),
            "label_forms": "; ".join(f"{f} ×{c}" for f, c in label_forms.most_common()),
            "exact_uses": exact,
            "label_uses": label_uses,
            "text_uses": text_uses,
            "files": "; ".join(p for p, _ in places.most_common(5)),
        }
        for col in TARGETS:
            row[col] = next((targets[col][k] for k in keys if targets[col].get(k)), "")
        rows.append(row)

    order = {"alias": 0, "spelling": 1, "case": 2, "in-text": 3, "ok": 4}
    rows.sort(key=lambda r: (order[r["status"]], -(r["label_uses"] + r["text_uses"])))

    OUT.mkdir(exist_ok=True)
    fields = list(rows[0].keys()) if rows else []
    with (OUT / "glossary.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)

    # stashy labels without a Stash term (product words to translate consistently)
    stash_terms_folded = set(by_folded)
    own = [
        (t, c) for t, c in labels.most_common()
        if c >= 2 and is_term(t) and t not in covered_literals
        and re.sub(r"[\s\-]+", " ", t.lower()) not in stash_terms_folded
        and not t.startswith("…")
    ][:150]

    counts = Counter(r["status"] for r in rows)
    md = [
        "# Glossary review: stashy vs. Stash",
        "",
        f"Stash locales at `stashapp/stash@{args.commit}`, English base = Stash `en-GB` + `en-US` overrides "
        "(US spelling, Stash terms). Generated by `tools/l10n/glossary.py`; the full table is `glossary.csv`.",
        "",
        f"{len(literals)} UI string literals scanned; {len(rows)} Stash terms found in the apps: "
        + ", ".join(f"{counts[s]} {s}" for s in order if counts[s]) + ".",
        "",
        "Status: **alias** = stashy uses another word for a Stash term · **spelling** = hyphen/space/GB form differs · "
        "**case** = a standalone label differs only in capitalisation (Stash itself mixes Title Case and Sentence case) · "
        "**in-text** = only inside longer sentences · **ok** = identical.",
        "",
    ]
    for status in ["alias", "spelling", "case"]:
        sel = [r for r in rows if r["status"] == status]
        if not sel:
            continue
        md += [f"## {status} ({len(sel)})", "", "| Stash term | stashy forms | labels / in text | de | files |", "|---|---|---|---|---|"]
        for r in sel:
            files = "<br>".join(f.split(":", 1)[1] for f in r["files"].split("; ")[:3])
            forms = r["label_forms"] if status == "case" else r["app_forms"]
            md.append(f"| **{r['stash_en']}** | {forms} | {r['label_uses']} / {r['text_uses']} | {r['de']} | {files} |")
        md.append("")
    md += [
        f"## stashy terms without a Stash equivalent (top {len(own)})",
        "",
        "Labels used at least twice that Stash has no term for. These need their own glossary entries before translating.",
        "",
        "| Label | uses |", "|---|---|",
    ]
    md += [f"| {t} | {c} |" for t, c in own]
    (OUT / "glossary-review.md").write_text("\n".join(md) + "\n", encoding="utf-8")

    print(f"{len(literals)} literals, {len(rows)} terms:", dict(counts))
    print("wrote", (OUT / "glossary.csv").relative_to(ROOT), "and", (OUT / "glossary-review.md").relative_to(ROOT))


if __name__ == "__main__":
    main()
