#!/usr/bin/env python3
"""Upload an AAB to Google Play via the Android Publisher API (v3).

Auth: service account key at ~/Library/Application Support/stashy-signing/play-publisher.json
(override with PLAY_KEY). Only needs PyJWT + cryptography, no Google client libraries.

  play_publish.py tracks                               list tracks and their releases
  play_publish.py upload <aab> [--track internal] [--notes "…"] [--draft] [--no-review]
"""
import argparse, glob, json, os, sys, time, urllib.error, urllib.parse, urllib.request

import jwt

PACKAGE = "de.letzgo.stashy"
SIGNING_DIR = os.path.expanduser("~/Library/Application Support/stashy-signing")
SERVICE_ACCOUNT = "play-publisher@stashy-play.iam.gserviceaccount.com"


def find_key():
    """PLAY_KEY, else play-publisher.json, else the downloaded key file of the play-publisher account."""
    if os.environ.get("PLAY_KEY"):
        return os.environ["PLAY_KEY"]
    named = os.path.join(SIGNING_DIR, "play-publisher.json")
    if os.path.exists(named):
        return named
    for path in sorted(glob.glob(os.path.join(SIGNING_DIR, "*.json"))):
        try:
            with open(path) as f:
                if json.load(f).get("client_email") == SERVICE_ACCOUNT:
                    return path
        except (OSError, ValueError):
            pass
    sys.exit(f"No key for {SERVICE_ACCOUNT} in {SIGNING_DIR}")


KEY = find_key()
API = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}"
UPLOAD = f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PACKAGE}"


def token():
    with open(KEY) as f:
        sa = json.load(f)
    now = int(time.time())
    assertion = jwt.encode({
        "iss": sa["client_email"], "scope": "https://www.googleapis.com/auth/androidpublisher",
        "aud": sa["token_uri"], "iat": now, "exp": now + 3600,
    }, sa["private_key"], algorithm="RS256")
    body = urllib.parse.urlencode({
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": assertion}).encode()
    with urllib.request.urlopen(urllib.request.Request(sa["token_uri"], data=body)) as r:
        return json.load(r)["access_token"]


TOKEN = None


def call(method, url, body=None, data=None, ctype="application/json"):
    payload = data if data is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url, method=method, data=payload,
                                 headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": ctype})
    try:
        with urllib.request.urlopen(req, timeout=900) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code} {method} {url.split('?')[0]}\n{e.read().decode()[:1500]}")


def tracks(edit):
    for t in call("GET", f"{API}/edits/{edit}/tracks").get("tracks", []):
        print(t["track"])
        for r in t.get("releases", []):
            print("   ", r.get("status"), r.get("name", ""), r.get("versionCodes", []))


def upload(edit, args):
    size = os.path.getsize(args.aab) / 1e6
    print(f"uploading {args.aab} ({size:.1f} MB)…", flush=True)
    with open(args.aab, "rb") as f:
        bundle = call("POST", f"{UPLOAD}/edits/{edit}/bundles?uploadType=media",
                      data=f.read(), ctype="application/octet-stream")
    code = str(bundle["versionCode"])
    print("versionCode", code)
    release = {"versionCodes": [code], "status": "draft" if args.draft else "completed"}
    if args.notes:
        release["releaseNotes"] = [{"language": "en-US", "text": args.notes}]
    call("PUT", f"{API}/edits/{edit}/tracks/{args.track}",
         {"track": args.track, "releases": [release]})
    q = "?changesNotSentForReview=true" if args.no_review else ""
    call("POST", f"{API}/edits/{edit}:commit{q}")
    print(f"committed {code} → {args.track} ({release['status']})")


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("tracks")
    u = sub.add_parser("upload")
    u.add_argument("aab")
    u.add_argument("--track", default="internal")
    u.add_argument("--notes")
    u.add_argument("--draft", action="store_true", help="create the release as draft (no rollout)")
    u.add_argument("--no-review", action="store_true",
                   help="commit without sending to review (needed when Play asks for it)")
    args = p.parse_args()

    global TOKEN
    TOKEN = token()
    edit = call("POST", f"{API}/edits", {})["id"]
    if args.cmd == "tracks":
        tracks(edit)
        call("DELETE", f"{API}/edits/{edit}")
    else:
        upload(edit, args)


if __name__ == "__main__":
    main()
