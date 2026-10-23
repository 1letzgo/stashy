#!/usr/bin/env python3
"""
stashy-keygen — offline license keys for the stashy+ unlock of the Android `sideload` build.

How it works
------------
* ECDSA P-256 / SHA-256. The private key stays on this machine
  (default ~/.stashy-license/stashy-license-private.pem, chmod 600) and must NEVER be committed.
  The app only embeds the public key (`LicenseKey.PUBLIC_KEY` in
  android/app/src/main/java/de/letzgo/stashy/data/LicenseKey.kt) and verifies keys offline.
* Key text:  STASHY-XXXXX-XXXXX-...  = Crockford base32 (no padding) of  payload || signature,
  grouped in 5-char blocks. The app ignores case, spaces, dashes and the STASHY- prefix,
  and reads I/L as 1 and O as 0.
* Payload (binary, big endian):
      u8  version (=1)
      u16 issued   (days since 1970-01-01, UTC)
      u16 expires  (days since 1970-01-01, UTC, 0 = never; valid through the end of that day, UTC)
      u8  len + UTF-8 license id   (<= 32 bytes)
      u8  len + UTF-8 holder name  (<= 64 bytes)
  Signature = ECDSA over the payload bytes, as raw r||s (64 bytes).

Usage
-----
  python3 tools/stashy-keygen.py init                     # once: create the key pair, print the public key
  python3 tools/stashy-keygen.py pubkey                   # print the public key again
  python3 tools/stashy-keygen.py issue --name "Jane Doe" [--expires 2027-12-31] [--id ABC123] [--note "Ko-fi"]
  python3 tools/stashy-keygen.py verify STASHY-....       # verify with the local key pair
  python3 tools/stashy-keygen.py verify --public-key <base64 DER> STASHY-....

Every issued key is appended to ~/.stashy-license/issued.csv (id, name, issued, expires, note, key).
Use --dir to work with another key directory (e.g. a throwaway test key pair).

Requires the `cryptography` package (pip3 install cryptography).
"""

import argparse
import base64
import csv
import datetime as dt
import os
import secrets
import struct
import sys
from pathlib import Path

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature, encode_dss_signature

VERSION = 1
PREFIX = "STASHY-"
GROUP = 5
SIG_LEN = 64
ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"  # Crockford base32
DEFAULT_DIR = Path.home() / ".stashy-license"
PRIVATE_NAME = "stashy-license-private.pem"
EPOCH = dt.date(1970, 1, 1)


# MARK: - Crockford base32

def b32encode(data: bytes) -> str:
    bits, value, out = 0, 0, []
    for byte in data:
        value = (value << 8) | byte
        bits += 8
        while bits >= 5:
            bits -= 5
            out.append(ALPHABET[(value >> bits) & 31])
    if bits:
        out.append(ALPHABET[(value << (5 - bits)) & 31])
    return "".join(out)


def b32decode(text: str) -> bytes:
    bits, value, out = 0, 0, bytearray()
    for ch in text:
        idx = ALPHABET.find(ch)
        if idx < 0:
            raise ValueError(f"invalid character {ch!r}")
        value = (value << 5) | idx
        bits += 5
        if bits >= 8:
            bits -= 8
            out.append((value >> bits) & 0xFF)
    return bytes(out)


def normalize(text: str) -> list:
    """Candidate base32 bodies for pasted input (same rules as LicenseKey.kt)."""
    s = "".join(ch for ch in text.upper() if not ch.isspace())
    s = s.replace("I", "1").replace("L", "1").replace("O", "0")
    candidates = []
    if s.startswith("STASHY"):
        candidates.append(s[len("STASHY"):].replace("-", ""))
    candidates.append(s.replace("-", ""))
    return candidates


def format_key(body: str) -> str:
    return PREFIX + "-".join(body[i:i + GROUP] for i in range(0, len(body), GROUP))


# MARK: - Payload

def days(date: dt.date) -> int:
    return (date - EPOCH).days


def encode_payload(license_id: str, name: str, issued: dt.date, expires) -> bytes:
    lid, nm = license_id.encode(), name.encode()
    if not 0 < len(lid) <= 32:
        sys.exit("license id must be 1-32 bytes")
    if not 0 < len(nm) <= 64:
        sys.exit("name must be 1-64 bytes (UTF-8)")
    return (struct.pack(">BHH", VERSION, days(issued), days(expires) if expires else 0)
            + bytes([len(lid)]) + lid + bytes([len(nm)]) + nm)


def decode_payload(blob: bytes):
    """Returns (payload, signature, fields) or raises ValueError."""
    if len(blob) < 5 or blob[0] != VERSION:
        raise ValueError("unknown key version")
    _, issued, expires = struct.unpack(">BHH", blob[:5])
    pos = 5
    fields = []
    for _ in range(2):
        if pos >= len(blob):
            raise ValueError("truncated key")
        n = blob[pos]
        pos += 1
        if pos + n > len(blob):
            raise ValueError("truncated key")
        fields.append(blob[pos:pos + n].decode())
        pos += n
    if len(blob) - pos != SIG_LEN:
        raise ValueError("bad signature length")
    return blob[:pos], blob[pos:], {
        "version": VERSION,
        "id": fields[0],
        "name": fields[1],
        "issued": (EPOCH + dt.timedelta(days=issued)).isoformat(),
        "expires": (EPOCH + dt.timedelta(days=expires)).isoformat() if expires else None,
    }


# MARK: - Keys

def private_path(d: Path) -> Path:
    return d / PRIVATE_NAME


def load_private(d: Path):
    p = private_path(d)
    if not p.exists():
        sys.exit(f"No private key at {p} — run `init` first.")
    return serialization.load_pem_private_key(p.read_bytes(), password=None)


def public_b64(pub) -> str:
    der = pub.public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    return base64.b64encode(der).decode()


def load_public_b64(text: str):
    return serialization.load_der_public_key(base64.b64decode(text))


def sign(priv, payload: bytes) -> bytes:
    r, s = decode_dss_signature(priv.sign(payload, ec.ECDSA(hashes.SHA256())))
    return r.to_bytes(32, "big") + s.to_bytes(32, "big")


def verify_sig(pub, payload: bytes, raw: bytes) -> bool:
    der = encode_dss_signature(int.from_bytes(raw[:32], "big"), int.from_bytes(raw[32:], "big"))
    try:
        pub.verify(der, payload, ec.ECDSA(hashes.SHA256()))
        return True
    except InvalidSignature:
        return False


# MARK: - Commands

def cmd_init(args):
    d = Path(args.dir).expanduser()
    p = private_path(d)
    if p.exists():
        sys.exit(f"Refusing to overwrite existing key {p}.")
    d.mkdir(parents=True, exist_ok=True)
    os.chmod(d, 0o700)
    priv = ec.generate_private_key(ec.SECP256R1())
    pem = priv.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
    fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(pem)
    print(f"Private key written to {p} (chmod 600). Back it up somewhere safe; never commit it.")
    print("Public key (base64 DER SubjectPublicKeyInfo) for LicenseKey.PUBLIC_KEY:")
    print(public_b64(priv.public_key()))


def cmd_pubkey(args):
    print(public_b64(load_private(Path(args.dir).expanduser()).public_key()))


def parse_date(text: str) -> dt.date:
    try:
        return dt.date.fromisoformat(text)
    except ValueError:
        sys.exit(f"invalid date {text!r} (expected YYYY-MM-DD)")


def cmd_issue(args):
    d = Path(args.dir).expanduser()
    priv = load_private(d)
    issued = parse_date(args.issued) if args.issued else dt.datetime.now(dt.timezone.utc).date()
    expires = parse_date(args.expires) if args.expires else None
    if expires and expires < issued and not args.allow_past:
        sys.exit("expiry date is before the issue date (use --allow-past for test keys)")
    license_id = args.id or secrets.token_hex(4).upper()
    payload = encode_payload(license_id, args.name.strip(), issued, expires)
    key = format_key(b32encode(payload + sign(priv, payload)))
    if not args.no_log:
        log = d / "issued.csv"
        new = not log.exists()
        with open(log, "a", newline="") as f:
            w = csv.writer(f)
            if new:
                w.writerow(["id", "name", "issued", "expires", "note", "key"])
            w.writerow([license_id, args.name.strip(), issued.isoformat(), expires.isoformat() if expires else "", args.note or "", key])
        os.chmod(log, 0o600)
    print(key)


def cmd_verify(args):
    pub = load_public_b64(args.public_key) if args.public_key else load_private(Path(args.dir).expanduser()).public_key()
    errors = []
    for body in normalize(args.key):
        try:
            payload, sig, fields = decode_payload(b32decode(body))
        except (ValueError, UnicodeDecodeError) as e:
            errors.append(str(e))
            continue
        if not verify_sig(pub, payload, sig):
            errors.append("signature does not match")
            continue
        today = dt.datetime.now(dt.timezone.utc).date()
        expired = fields["expires"] is not None and today > dt.date.fromisoformat(fields["expires"])
        print("VALID" + (" (EXPIRED)" if expired else ""))
        for k in ("id", "name", "issued", "expires"):
            print(f"  {k:8} {fields[k] or '—'}")
        sys.exit(1 if expired else 0)
    print("INVALID: " + (errors[0] if errors else "empty key"))
    sys.exit(2)


def main():
    ap = argparse.ArgumentParser(description="Offline stashy+ license keys for the Android sideload build (ECDSA P-256).",
                                 formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__.split("Usage")[1] if "Usage" in __doc__ else None)
    ap.add_argument("--dir", default=str(DEFAULT_DIR), help=f"key directory (default {DEFAULT_DIR})")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("init", help="create the key pair (refuses to overwrite) and print the public key").set_defaults(fn=cmd_init)
    sub.add_parser("pubkey", help="print the public key (base64 DER) to embed in the app").set_defaults(fn=cmd_pubkey)

    p = sub.add_parser("issue", help="issue a license key")
    p.add_argument("--name", required=True, help="license holder (name or email), shown in the app")
    p.add_argument("--expires", help="expiry date YYYY-MM-DD (valid through that day, UTC); default: never")
    p.add_argument("--id", help="license id (default: random 8 hex chars)")
    p.add_argument("--note", help="note for issued.csv only (not part of the key)")
    p.add_argument("--issued", help=argparse.SUPPRESS)
    p.add_argument("--allow-past", action="store_true", help=argparse.SUPPRESS)
    p.add_argument("--no-log", action="store_true", help="don't append to issued.csv")
    p.set_defaults(fn=cmd_issue)

    p = sub.add_parser("verify", help="verify a key and print its payload (exit 0 valid, 1 expired, 2 invalid)")
    p.add_argument("key", help="the license key (any case, with or without dashes / STASHY- prefix)")
    p.add_argument("--public-key", help="base64 DER public key (default: derived from the local private key)")
    p.set_defaults(fn=cmd_verify)

    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
