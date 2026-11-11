#!/usr/bin/env python3
"""Move hard-coded UI strings of the iOS/tvOS/macOS and Android apps onto shared keys.

One key per English text, shared by both platforms (Tolgee project "stashy"):
  Swift   "Play Count"            -> tr("play_count")
          "\(n) scenes"           -> tr("arg_scenes", n)
  Kotlin  "Play Count"            -> tr(R.string.play_count)
          "$n scenes"             -> tr(R.string.arg_scenes, n)

Writes
  stashy/Localizable.xcstrings                     English values (others come from Tolgee)
  android/app/src/main/res/values/strings.xml      English values
  localization/keys.csv                            key, English, uses per platform

Usage: python3 -I tools/l10n/migrate_literals.py [--report] [--apply]
  --report  only print what would change (default)
  --apply   rewrite the sources and write the files above
"""
from __future__ import annotations

import argparse
import csv
import json
import re
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from xml.sax.saxutils import escape as xml_escape

ROOT = Path(__file__).resolve().parents[2]
STASH_EN = Path(__file__).resolve().parent / ".cache" / "a115a2f957"

SWIFT_DIRS = ["stashy", "stashyTV", "stashyMac"]
KOTLIN_DIRS = ["android/app/src/main/java"]
SKIP_FILES = {"MacCompat.swift", "Localization.swift", "Localization.kt", "GraphQLQueries.swift"}


# --------------------------------------------------------------------------- scanning

@dataclass
class Literal:
    path: Path
    lang: str            # "swift" | "kotlin"
    start: int           # offset of opening quote
    end: int             # offset after closing quote
    parts: list          # ("text", str) | ("expr", source)
    text: str = ""       # English with {0}, {1}
    key: str = ""
    reason: str = ""     # why it was skipped, empty = converted

    @property
    def args(self) -> list[str]:
        return [p[1] for p in self.parts if p[0] == "expr"]


class ParseError(Exception):
    pass


def _swift_unescape(src: str, j: int) -> tuple[str, int]:
    n = src[j + 1]
    simple = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "'": "'", "\\": "\\", "0": "\0"}
    if n in simple:
        return simple[n], j + 2
    if n == "u" and src[j + 2] == "{":
        close = src.index("}", j)
        return chr(int(src[j + 3:close], 16)), close + 1
    raise ParseError(f"escape \\{n}")


def parse_swift_string(src: str, i: int) -> tuple[list, int]:
    """src[i] is '"' (not '\"\"\"'). Returns (parts, end)."""
    j, parts, buf = i + 1, [], ""
    while True:
        if j >= len(src) or src[j] == "\n":
            raise ParseError("unterminated")
        c = src[j]
        if c == '"':
            if buf:
                parts.append(("text", buf))
            return parts, j + 1
        if c == "\\":
            if src[j + 1] == "(":
                if buf:
                    parts.append(("text", buf))
                    buf = ""
                k, depth = j + 2, 1
                while depth:
                    ch = src[k]
                    if ch == '"':
                        if src.startswith('"""', k):
                            raise ParseError("multiline in interpolation")
                        _, k = parse_swift_string(src, k)
                        continue
                    if ch == "(":
                        depth += 1
                    elif ch == ")":
                        depth -= 1
                    elif ch == "\n":
                        raise ParseError("newline in interpolation")
                    k += 1
                parts.append(("expr", src[j + 2:k - 1]))
                j = k
                continue
            ch, j = _swift_unescape(src, j)
            buf += ch
            continue
        buf += c
        j += 1


def parse_kotlin_string(src: str, i: int) -> tuple[list, int]:
    j, parts, buf = i + 1, [], ""
    while True:
        if j >= len(src) or src[j] == "\n":
            raise ParseError("unterminated")
        c = src[j]
        if c == '"':
            if buf:
                parts.append(("text", buf))
            return parts, j + 1
        if c == "\\":
            n = src[j + 1]
            simple = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "'": "'", "\\": "\\", "$": "$", "b": "\b"}
            if n in simple:
                buf += simple[n]
                j += 2
                continue
            if n == "u":
                buf += chr(int(src[j + 2:j + 6], 16))
                j += 6
                continue
            raise ParseError(f"escape \\{n}")
        if c == "$" and j + 1 < len(src) and (src[j + 1] == "{" or src[j + 1].isalpha() or src[j + 1] == "_"):
            if buf:
                parts.append(("text", buf))
                buf = ""
            if src[j + 1] == "{":
                k, depth = j + 2, 1
                while depth:
                    ch = src[k]
                    if ch == '"':
                        if src.startswith('"""', k):
                            raise ParseError("raw in template")
                        _, k = parse_kotlin_string(src, k)
                        continue
                    if ch == "'":
                        k = skip_kotlin_char(src, k)
                        continue
                    if ch == "{":
                        depth += 1
                    elif ch == "}":
                        depth -= 1
                    elif ch == "\n":
                        raise ParseError("newline in template")
                    k += 1
                parts.append(("expr", src[j + 2:k - 1]))
                j = k
            else:
                m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", src[j + 1:])
                parts.append(("expr", m.group(0)))
                j += 1 + len(m.group(0))
            continue
        buf += c
        j += 1


def skip_kotlin_char(src: str, k: int) -> int:
    m = re.match(r"'(\\u[0-9a-fA-F]{4}|\\.|[^'\\])'", src[k:])
    if not m:
        raise ParseError("char literal")
    return k + len(m.group(0))


def scan(src: str, lang: str) -> list[tuple[int, int, list]]:
    """Top-level string literals: (start, end, parts). Comments, multi-line and raw strings skipped."""
    out, i, n = [], 0, len(src)
    parse = parse_swift_string if lang == "swift" else parse_kotlin_string
    while i < n:
        c = src[i]
        if src.startswith("//", i):
            i = src.find("\n", i)
            i = n if i < 0 else i
        elif src.startswith("/*", i):
            depth, i = 1, i + 2
            while depth and i < n:
                if src.startswith("/*", i):
                    depth, i = depth + 1, i + 2
                elif src.startswith("*/", i):
                    depth, i = depth - 1, i + 2
                else:
                    i += 1
        elif src.startswith('"""', i):
            close = src.find('"""', i + 3)
            i = n if close < 0 else close + 3
        elif lang == "swift" and src.startswith('#"', i):
            close = src.find('"#', i + 2)
            i = n if close < 0 else close + 2
        elif lang == "kotlin" and c == "'":
            try:
                i = skip_kotlin_char(src, i)
            except ParseError:
                i += 1
        elif c == '"':
            try:
                parts, end = parse(src, i)
                out.append((i, end, parts))
                i = end
            except ParseError:
                i = src.find("\n", i)
                i = n if i < 0 else i
        else:
            i += 1
    return out


# --------------------------------------------------------------------------- classification

IDENT_RE = re.compile(
    r"^[a-z0-9_.\-/:+#@*]*$"         # keys, SF symbols, fields, paths
    r"|^[a-z][A-Za-z0-9_]*$"         # camelCase
    r"|^[A-Z][A-Za-z0-9]*[A-Z][A-Za-z0-9]*$"  # CamelCase / ALLCAPS identifiers (AppIconPreview, AND)
    r"|^[A-Z0-9_]+$"
    r"|^[A-Za-z]+(-[A-Z][a-z]+)+$"   # HTTP headers (Content-Type)
)
DATE_FMT_RE = re.compile(r"^[yMdHhmsSaEzZLGQwWuk\s,.:/'\-]+$")
UI_OK = {"OK"}

# Enclosing calls whose string arguments are not UI text
DENY_CALLS = re.compile(
    r"(AppLog\.\w+|\bprint|\bdebugPrint|\bNSLog|\bos_log|\blogger\.\w+|Logger\.\w+|\bLog\.[a-z]|\bprintln|"
    r"\bfatalError|\bprecondition\w*|\bassert\w*|\brequire|\bcheck|\berror|"
    r"\bImage|\bUIImage|\bNSImage|\bnamed|\bColor|\bFont\.custom|\.custom|"
    r"Notification\.Name|NSNotification\.Name|\bURL|\bURLQueryItem|\bURLComponents|\bUri\.parse|"
    r"\bNSPredicate|\bRegex|\bNSRegularExpression|\btoRegex|Pattern\.compile|\bSimpleDateFormat|ofPattern|"
    r"forHTTPHeaderField|\bsetValue|\baddValue|\bheader|\baddHeader|\bput|\bputString|\bgetString|\boptString|"
    r"\bgetJSON\w*|\boptJSON\w*|\bhas|\bopt\w*|\bjsonObject|\bJSONObject|\bput\w+|\bgetStringExtra|\bputExtra|"
    r"loadQuery|queryWithFragments|\bstring\(forKey|\bobject\(forKey|\bset|\bremoveObject|\bbool|\binteger|\bdouble|"
    r"accessibilityIdentifier|testTag|\bsemanticsTestTag|\bKeychainManager\.\w+|\bwithName|"
    r"\bDateFormatter|\bNumberFormatter|\bString\(format|\bcomponents|\bsplit|\breplacingOccurrences|\breplace|"
    r"\bcontains|\bhasPrefix|\bhasSuffix|\bstartsWith|\bendsWith|\brange|\bfirstIndex|\bindexOf|\bsubstringAfter\w*|"
    r"\bsubstringBefore\w*|\bremovePrefix|\bremoveSuffix|\btrimStart|\btrimEnd|\btrim|\bjoined|\bjoinToString|"
    r"\bmatches|\bfirstMatch|\bwholeMatch|\btoMediaType|\btoMediaTypeOrNull|\bMediaType|\bmimeType|"
    r"\bPreview|\bavailable|\bSerialName|\bJsonNames|\bEncodeDefault|\bSuppress\w*|\bDeprecated|\bOptIn|"
    r"\bpreview_start|\bnavigate|\bAppStorage|\bSceneStorage|\bfetchRequest|\bperformMutation|\bexecute\w*|"
    r"\bpostNotification|\bpost|\bNotificationCenter|\bkey|\bvalueForKey|\bdecode|\bencode|\bCodingKeys|"
    r"\blog\w*|\w*Log\w*|\binvoke|\bescalate\w*|appendingPathComponent|\bFile|\bappend(?=$)|\bdebug\w*|\btrace\w*)\s*$"
)
DENY_LINE = re.compile(
    r"AppLog\.|\bprint\(|\bLog\.[a-z]\(|forKey:|UserDefaults|@AppStorage|@SceneStorage|NotificationCenter|"
    r"Notification\.Name|accessibilityIdentifier|testTag|#Preview|@available|forHTTPHeaderField|httpMethod|"
    r"dateFormat\s*=|\.dateFormat|@Json|const val \w+_KEY|Key\s*=\s*\"|KEY\s*=\s*\"|"
    r"static let \w*[Kk]ey\w*\s*=|let \w*[Kk]ey\s*=|val \w*[Kk]ey\s*=|\bprefs\.|SharedPreferences|"
    r"\.graphql|operationName|\"query\"|mutation\s|GraphQL\w*\.\w+\(|case \.\w+:\s*return \"[a-z_]+\"$"
)


def enclosing_call(src: str, pos: int) -> tuple[str, int]:
    """Name before the '(' that encloses pos (e.g. 'AppLog.debug') and that paren's offset."""
    depth, k = 0, pos - 1
    while k >= 0 and pos - k < 4000:
        ch = src[k]
        if ch in ")]}":
            depth += 1
        elif ch in "([{":
            if depth == 0:
                if ch != "(":
                    return "", -1
                m = re.search(r"([A-Za-z_][\w.]*)\s*$", src[max(0, k - 120):k])
                return (m.group(1) if m else ""), k
            depth -= 1
        k -= 1
    return "", -1


DATA_NAME = re.compile(
    r"^(raw\w*|\w*RawValue|\w*Raw|storage\w*|\w*StorageKey|\w*Key|key\w*|id|ids|identifier|serial\w*|json\w*|"
    r"persist\w*|sortField|field|fieldName|code|apiValue|graphQL\w*|query\w*|ascensionMode|aliasName|stashValue|"
    r"value|values|webValue|savedValue|legacy\w*|route|path|scope)$", re.I)

DATA_DECL = re.compile(r"^(raw\w*|\w*RawValue|\w*Raw|storage\w*|serial\w*|json\w*|persist\w*|apiValue|stashValue|"
                       r"webValue|savedValue)$", re.I)

KOTLIN_SIGS: dict[str, list[str]] = {}
KOTLIN_FILE_SIGS: dict[Path, dict[str, list[str]]] = {}


def load_kotlin_signatures(sources: dict) -> None:
    """Parameter names of every Kotlin class constructor and function, by name."""
    for path, src in sources.items():
        if path.suffix != ".kt":
            continue
        for m in re.finditer(r"\b(?:class|fun)\s+(?:<[^>]*>\s*)?(?:[\w.]+\.)?([A-Za-z_]\w*)\s*(?:<[^>]*>)?\s*"
                             r"(?:(?:private|internal|public|protected)\s+)?(?:constructor\s*)?\(", src):
            depth, k = 1, m.end()
            while depth and k < len(src):
                depth += {"(": 1, ")": -1}.get(src[k], 0)
                k += 1
            params, buf, d = [], "", 0
            for ch in src[m.end():k - 1]:
                if ch in "(<[{":
                    d += 1
                elif ch in ")>]}":
                    d -= 1
                if ch == "," and d == 0:
                    params.append(buf)
                    buf = ""
                else:
                    buf += ch
            params.append(buf)
            names = []
            for piece in params:
                piece = re.sub(r"@\w+(\([^)]*\))?", "", piece)
                pm = re.search(r"(?:\bva[lr]\s+)?([A-Za-z_]\w*)\s*:", piece)
                names.append(pm.group(1) if pm else "")
            KOTLIN_SIGS.setdefault(m.group(1), names)
            KOTLIN_FILE_SIGS.setdefault(path, {}).setdefault(m.group(1), names)


def kotlin_param_name(path: Path, src: str, call: str, open_pos: int, lit_start: int) -> str:
    """Name of the parameter the literal is passed to, '' when unknown."""
    inside = src[open_pos + 1:lit_start]
    named = re.search(r"([A-Za-z_]\w*)\s*=\s*$", inside)
    if named:
        return named.group(1)
    depth, index = 0, 0
    for ch in inside:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == "," and depth == 0:
            index += 1
    name = call.split(".")[-1]
    local = KOTLIN_FILE_SIGS.get(path, {})
    line_start = src.rfind("\n", 0, open_pos) + 1
    is_entry = re.match(r"\s*(@[\w.]+(\([^)]*\))?\s*)*[A-Z]\w*\s*$", src[line_start:open_pos]) or \
        re.search(r"[;,]\s*[A-Z]\w*\s*$", src[line_start:open_pos])
    enum_before = list(re.finditer(r"\benum class (\w+)", src[:open_pos]))
    params = None if (is_entry and enum_before) else (local.get(name) or KOTLIN_SIGS.get(name))
    if params is None:
        # An enum entry ("Dark(\"Dark\")" on its own line): the parameters of the enclosing enum class
        line_start = src.rfind("\n", 0, open_pos) + 1
        if not re.match(r"\s*(@[\w.]+(\([^)]*\))?\s*)*[A-Z]\w*\s*$", src[line_start:open_pos]) and \
                not re.search(r"[;,]\s*[A-Z]\w*\s*$", src[line_start:open_pos]):
            return ""
        enum = None
        for m in re.finditer(r"\benum class (\w+)", src[:open_pos]):
            enum = m.group(1)
        params = local.get(enum or "") or []
    return params[index] if index < len(params) else ""


def enclosing_decl(src: str, pos: int) -> str:
    """Name of the nearest declaration above pos (var/let/val/func/fun)."""
    names = re.findall(r"\b(?:var|let|val|func|fun)\s+(?:<[^>]*>\s*)?(?:[\w.]+\.)?([A-Za-z_]\w*)", src[max(0, pos - 3000):pos])
    return names[-1] if names else ""


def classify(lit: Literal, src: str) -> str:
    """'' when the literal is UI text, else the reason it is skipped."""
    plain = "".join(p[1] if p[0] == "text" else "\x00" for p in lit.parts)
    letters = plain.replace("\x00", " ")
    if not re.search(r"[A-Za-z]{2}", letters) and letters.strip() not in UI_OK:
        if not re.search(r"[^\x00-\x7f]", letters.replace("\x00", "")) or not re.search(r"\w", letters):
            return "no-text"
    if not lit.parts or all(p[0] == "expr" for p in lit.parts):
        return "no-text"
    stripped = letters.strip()
    core = plain.replace("\x00", "").strip()          # text without the values
    words = re.findall(r"[A-Za-z][A-Za-z'’-]*", core)
    sentence = len(words) >= 4 and re.match(r"[\"“(]?[A-Z0-9]", core) is not None
    first = re.search(r"[A-Za-z]", core)
    if first and first.group(0).islower() and len(words) < 4:
        return "lowercase"                            # css values, log lines, body checks
    if re.search(r"[=|_;{}\\]|\r|\":|\(\?|\[\^", core) and not sentence:
        return "code"
    if re.search(r"\.(json|mp4|m4v|mov|jpg|jpeg|png|gif|webp|srt|vtt|funscript|txt|csv|zip|html?)\b", core):
        return "filename"
    if DATE_FMT_RE.match(core) and re.search(r"yy|MM|dd|HH|mm|ss", core):
        return "format"
    if " " not in core and core not in UI_OK and \
            not re.fullmatch(r"[A-Z]?[a-z]+(-[A-Z]?[a-z]+)*[:.…!?]*|[A-Z][a-z]+[A-Z][a-z]+", core):
        return "identifier"
    if " " not in stripped and stripped not in UI_OK:
        if IDENT_RE.match(stripped) or "." in stripped or "_" in stripped or "/" in stripped:
            return "identifier"
        if not re.search(r"[a-z]", stripped):
            return "identifier"
    if "://" in stripped or stripped.startswith(("http", "/", ".", "#", "{", "[", "<", "%")):
        return "identifier"
    if DATE_FMT_RE.match(stripped) and not re.search(r"[a-z]{3}", stripped):
        return "format"
    if re.search(r"%(\d+\$)?[-+ #0]*\d*(\.\d+)?(l|ll|h)?[dfsu@xXeEgG]", plain):
        return "format"
    if re.search(r"\b(query|mutation|fragment)\b.*[{(]", stripped) or re.search(r"\b[a-z]+_[a-z_]+\b\s*[:{(]", stripped):
        return "graphql"

    line_start = src.rfind("\n", 0, lit.start) + 1
    line_end = src.find("\n", lit.end)
    line = src[line_start:line_end if line_end >= 0 else len(src)]
    before = src[line_start:lit.start]
    after = src[lit.end:line_end if line_end >= 0 else len(src)]
    if DENY_LINE.search(line):
        return "line"
    if re.search(r"(==|!=|===|!==)\s*$", before) or re.match(r"\s*(==|!=|===|!==|\?\?=)", after):
        return "compare"
    if re.match(r"\s+in\b|\.(data|toByteArray|utf8|encodeToByteArray)\b", after):
        return "bytes-or-contains"
    if re.search(r"\bcase\s+$", before) or re.search(r"\bcase\s+[^:]*,\s*$", before) and ":" in after:
        return "pattern"
    if re.match(r"\s*->", after) or re.match(r'\s*,\s*"[^"]*"\s*->', after):
        return "pattern"
    if re.match(r":", after) and lit.lang == "swift" and re.search(r"[\[,]\s*$", before):
        return "dict-key"
    if re.search(r"\b(id|tag|key|rawValue|named|field|identifier|systemImage|systemName|icon|image|value|forKey|suiteName|"
                 r"name|route|path|sortKey|sortField|fieldName|criterion|modifier|queryName|endpoint|notificationName|reason|"
                 r"fallbackReason|storageKey|defaultsKey|cacheKey|fileName|filename|extension|mimeType)\s*[:=]\s*$",
                 before):
        return "id-arg"
    if re.search(r"\.tag\($", before):
        return "id-arg"
    if lit.lang == "swift" and re.match(r"\s*case \w+(\([^)]*\))?\s*=\s*$", before):
        return "raw-value"
    if lit.lang == "kotlin" and re.search(r"\bconst val\b", before) and re.search(r"(KEY|_ID|ROUTE|PREF|TAG)\b", before):
        return "const-key"
    call, open_pos = enclosing_call(src, lit.start)
    if call and DENY_CALLS.search(call):
        return f"call:{call}"
    # (label, VALUE) pairs map a display name to stored data (Stash's saved filters keep the label)
    if re.match(r'\s*\bto\b\s*"[A-Za-z0-9_\-]*"', after) or (
            call in ("", "Pair") and re.search(r"\(\s*$", before)
            and re.match(r'\s*,\s*"[A-Za-z0-9_\-]*"\s*\)', after)):
        return "data-pair"
    if lit.lang == "kotlin" and call and open_pos >= 0:
        param = kotlin_param_name(lit.path, src, call, open_pos, lit.start)
        if param and DATA_NAME.match(param):
            return f"data-param:{param}"
    if lit.lang == "swift":
        label = re.search(r"([A-Za-z_]\w*)\s*:\s*$", before)
        if label and DATA_NAME.match(label.group(1)) and label.group(1) not in ("nameKey", "NSLocalizedDescriptionKey"):
            return f"data-param:{label.group(1)}"
    if re.search(r"\breturn\s+$|->\s*$|:\s*return\s+$|\?\?\s*$|\?:\s*$|=\s*$", before):
        decl = enclosing_decl(src, lit.start)
        if decl and DATA_DECL.match(decl):
            return f"data-decl:{decl}"
    if lit.lang == "swift":
        for expr in lit.args:
            if re.search(r",\s*(specifier|format|style)\s*:", expr):
                return "swiftui-format"
            if re.search(r"\b(Image|Text)\(", expr):
                return "swiftui-interp"
    return ""


# --------------------------------------------------------------------------- keys

def load_stash_terms() -> dict[str, str]:
    """English (US) Stash term -> top-level Stash key (o_count, play_count, ...)."""
    terms: dict[str, str] = {}
    try:
        gb = json.loads((STASH_EN / "en-GB.json").read_text(encoding="utf-8"))
        us = json.loads((STASH_EN / "en-US.json").read_text(encoding="utf-8"))
    except FileNotFoundError:
        return terms
    merged = {**gb, **{k: v for k, v in us.items() if isinstance(v, str)}}
    for k, v in merged.items():
        if isinstance(v, str) and "{" not in v and re.fullmatch(r"[a-z0-9_]+", k):
            terms.setdefault(v, k)
    return terms


RESERVED = set("""abstract assert boolean break byte case catch char class const continue default do double else
enum extends final finally float for goto if implements import instanceof int interface long native new package
private protected public return short static strictfp super switch synchronized this throw throws transient try
void volatile while true false null var as fun in is object typealias typeof val when""".split())


def slug(text: str) -> str:
    t = re.sub(r"\{\d+\}", " arg ", text)
    t = t.replace("&", " and ").replace("+", " plus ").replace("%", " percent ")
    t = re.sub(r"[’']", "", t)
    words = re.findall(r"[A-Za-z0-9]+", t.lower())
    words = [w for w in words if w not in {"the", "a", "an"}] or words
    out = "_".join(words[:6]) or "text"
    if out in RESERVED:  # not a valid Android resource name
        out += "_label"
    if out[0].isdigit():
        out = "n" + out
    return out[:48].rstrip("_")


def assign_keys(literals: list[Literal]) -> dict[str, str]:
    """English text -> key, identical text = identical key on both platforms."""
    stash = load_stash_terms()
    # Stash's own terms first, so they get Stash's key ("O Count" -> o_count, not "O COUNT")
    texts = sorted({l.text for l in literals}, key=lambda t: (t not in stash, len(t), t))
    used: dict[str, str] = {}
    text_key: dict[str, str] = {}
    for t in texts:
        base = stash.get(t) or slug(t)
        if base in RESERVED:
            base += "_label"
        k, n = base, 2
        while k in used and used[k] != t:
            k, n = f"{base}_{n}", n + 1
        used[k] = t
        text_key[t] = k
    return text_key


# --------------------------------------------------------------------------- output

def to_icu(parts: list) -> str:
    out, n = "", 0
    for kind, v in parts:
        if kind == "text":
            out += v
        else:
            out += "{" + str(n) + "}"
            n += 1
    return out


def placeholder_value(text: str, style: str) -> str:
    """English for a native file: {i} -> %@ / %1$s, % -> %%."""
    count = len(re.findall(r"\{\d+\}", text))
    out = text.replace("%", "%%")
    def rep(m):
        i = int(m.group(1))
        if style == "apple":
            return "%@" if count == 1 else f"%{i + 1}$@"
        return f"%{i + 1}$s"
    return re.sub(r"\{(\d+)\}", rep, out)


def android_escape(s: str) -> str:
    s = s.replace("\\", "\\\\").replace("\n", "\\n").replace("\t", "\\t")
    s = s.replace("'", "\\'").replace('"', '\\"')
    s = xml_escape(s)
    if s.startswith(("@", "?")):
        s = "\\" + s
    if s != s.strip():  # aapt drops leading/trailing spaces outside quotes
        s = f'"{s}"'
    return s


def swift_code(lit: Literal) -> str:
    args = "".join(f", {a.strip()}" for a in lit.args)
    return f'tr("{lit.key}"{args})'


def kotlin_code(lit: Literal) -> str:
    args = "".join(f", {a.strip()}" for a in lit.args)
    return f"tr(R.string.{lit.key}{args})"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--samples", type=int, default=0)
    args = ap.parse_args()

    files: list[tuple[Path, str]] = []
    for d in SWIFT_DIRS:
        files += [(p, "swift") for p in sorted((ROOT / d).rglob("*.swift")) if p.name not in SKIP_FILES]
    for d in KOTLIN_DIRS:
        files += [(p, "kotlin") for p in sorted((ROOT / d).rglob("*.kt")) if p.name not in SKIP_FILES]

    sources: dict[Path, str] = {path: path.read_text(encoding="utf-8") for path, _ in files}
    load_kotlin_signatures(sources)
    all_lits: list[Literal] = []
    for path, lang in files:
        src = sources[path]
        for start, end, parts in scan(src, lang):
            lit = Literal(path, lang, start, end, parts)
            lit.reason = classify(lit, src)
            lit.text = to_icu(parts)
            all_lits.append(lit)

    # A text that a file also uses as data (compared, matched, a key, a raw value …) stays a
    # literal everywhere in that file, so both sides keep matching in every language.
    data_kinds = ("compare", "pattern", "dict-key", "raw-value", "id-arg", "call", "line", "bytes-or-contains", "const-key",
                  "data-pair", "data-param", "data-decl")
    tainted = {(l.path, l.text) for l in all_lits if l.reason.split(":")[0] in data_kinds}
    for l in all_lits:
        if not l.reason and (l.path, l.text) in tainted:
            l.reason = "tainted"
    convert = [l for l in all_lits if not l.reason]
    text_key = assign_keys(convert)
    for l in convert:
        l.key = text_key[l.text]

    reasons = Counter(l.reason.split(":")[0] if l.reason else "convert" for l in all_lits)
    print("literals:", len(all_lits), dict(reasons.most_common()))
    print("keys:", len(text_key), "| swift uses:", sum(l.lang == "swift" for l in convert),
          "| kotlin uses:", sum(l.lang == "kotlin" for l in convert))
    by_text = defaultdict(set)
    for l in convert:
        by_text[l.text].add(l.lang)
    print("keys used on both platforms:", sum(len(v) == 2 for v in by_text.values()),
          "| swift only:", sum(v == {"swift"} for v in by_text.values()),
          "| kotlin only:", sum(v == {"kotlin"} for v in by_text.values()))

    if args.samples:
        import random
        random.seed(1)
        for l in random.sample(convert, min(args.samples, len(convert))):
            ln = sources[l.path].count("\n", 0, l.start) + 1
            print(f"  {l.path.relative_to(ROOT)}:{ln}  {l.key}  <- {l.text!r}")
        skipped = [l for l in all_lits if l.reason and l.reason not in ("no-text", "identifier")]
        print("--- skipped samples")
        for l in random.sample(skipped, min(args.samples, len(skipped))):
            ln = sources[l.path].count("\n", 0, l.start) + 1
            print(f"  [{l.reason}] {l.path.relative_to(ROOT)}:{ln}  {l.text!r}")

    if not args.apply:
        return

    # rewrite sources back to front
    per_file = defaultdict(list)
    for l in convert:
        per_file[l.path].append(l)
    for path, lits in per_file.items():
        src = sources[path]
        for l in sorted(lits, key=lambda x: x.start, reverse=True):
            code = swift_code(l) if l.lang == "swift" else kotlin_code(l)
            src = src[:l.start] + code + src[l.end:]
        if any(l.lang == "kotlin" for l in lits):
            # tr() cannot initialise a compile-time constant
            src = re.sub(r"\bconst val (\w+)(\s*(?::\s*String)?\s*=\s*tr\()", r"val \1\2", src)
            pkg = re.search(r"^package ([\w.]+)[ \t]*$", src, re.M)
            if pkg and pkg.group(1) != "de.letzgo.stashy":
                missing = [imp for imp in ("import de.letzgo.stashy.R", "import de.letzgo.stashy.tr")
                           if not re.search("^" + re.escape(imp) + "$", src, re.M)]
                if missing:
                    at = pkg.end()
                    src = src[:at] + "\n\n" + "\n".join(missing) + "\n" + src[at:].lstrip("\n")
        path.write_text(src, encoding="utf-8")

    # catalogs
    entries = {text_key[t]: t for t in text_key}
    xc = {"sourceLanguage": "en", "version": "1.0", "strings": {}}
    for k in sorted(entries):
        xc["strings"][k] = {
            "extractionState": "manual",
            "localizations": {"en": {"stringUnit": {"state": "translated", "value": placeholder_value(entries[k], "apple")}}},
        }
    (ROOT / "stashy/Localizable.xcstrings").write_text(json.dumps(xc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    res = ROOT / "android/app/src/main/res/values"
    res.mkdir(parents=True, exist_ok=True)
    lines = ['<?xml version="1.0" encoding="utf-8"?>', "<!-- Generated from Tolgee (project stashy). English is the source. -->",
             '<resources xmlns:tools="http://schemas.android.com/tools" tools:ignore="MissingTranslation">']
    for k in sorted(entries):
        lines.append(f'    <string name="{k}">{android_escape(placeholder_value(entries[k], "android"))}</string>')
    lines.append("</resources>")
    (res / "strings.xml").write_text("\n".join(lines) + "\n", encoding="utf-8")

    uses = defaultdict(Counter)
    for l in convert:
        uses[l.key][l.lang] += 1
    with (ROOT / "localization/keys.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["key", "en", "swift_uses", "kotlin_uses"])
        for k in sorted(entries):
            w.writerow([k, entries[k], uses[k]["swift"], uses[k]["kotlin"]])
    print("applied:", len(per_file), "files")


if __name__ == "__main__":
    main()
