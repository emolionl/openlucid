"""Build the two files desktop_updater needs for a release.

1. hashes.json, next to a copy of the built app's files: SHA-512/Base64
   hashes of every file, same format desktop_updater's own Dart client
   computes locally and diffs against. (Same approach as Emolio's
   generate_archive_hashes.py — `dart run desktop_updater:archive` was
   found unreliable there, so this is plain Python instead.)
2. manifest.json (an "app archive"): one entry per platform, each
   pointing at that version's folder. desktop_updater fetches this,
   picks the entry for the running platform, and compares its
   shortVersion (the build number after '+' in the app version) against
   the installed app's own embedded version.

No backend involved: .github/workflows/release.yml publishes the dest
folder and manifest.json to GitHub Pages, so both are just static files.

Usage:
    python tools/generate_release_manifest.py \
        --src build/windows/x64/runner/Release \
        --dest publish/releases/windows/0.4.0+47 \
        --manifest publish/releases/manifest.json \
        --version 0.4.0+47 --platform windows \
        --url https://emolionl.github.io/openlucid/releases/windows/0.4.0+47 \
        --changelog "What changed" [--mandatory]
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import shutil
import sys
from datetime import datetime, timezone


def generate_hashes(src: str, dest: str) -> int:
    if not os.path.isdir(src):
        print(f"ERROR: source folder not found: {src}", file=sys.stderr)
        return 0
    os.makedirs(dest, exist_ok=True)

    if os.path.abspath(src) != os.path.abspath(dest):
        for root, _dirs, files in os.walk(src):
            rel = os.path.relpath(root, src)
            target_root = dest if rel == "." else os.path.join(dest, rel)
            os.makedirs(target_root, exist_ok=True)
            for f in files:
                shutil.copy2(os.path.join(root, f), os.path.join(target_root, f))

    entries: list[dict] = []
    for root, _dirs, files in os.walk(dest):
        for f in sorted(files):
            if f == "hashes.json":
                continue
            full_path = os.path.join(root, f)
            rel_path = os.path.relpath(full_path, dest).replace("/", "\\")
            with open(full_path, "rb") as fh:
                data = fh.read()
            digest = hashlib.sha512(data).digest()
            entries.append(
                {
                    "path": rel_path,
                    "calculatedHash": base64.b64encode(digest).decode(),
                    "length": len(data),
                }
            )

    hashes_path = os.path.join(dest, "hashes.json")
    with open(hashes_path, "w") as fh:
        json.dump(entries, fh, separators=(",", ":"))
    print(f"Wrote {hashes_path} with {len(entries)} entries")
    return len(entries)


def update_app_archive(
    manifest_path: str,
    *,
    app_name: str,
    version: str,
    platform: str,
    url: str,
    changelog: str,
    mandatory: bool,
) -> None:
    if "+" not in version:
        raise ValueError(f"version must include a build number, e.g. 0.4.0+47 (got {version!r})")
    build_number = int(version.split("+")[-1])

    if os.path.exists(manifest_path):
        with open(manifest_path) as fh:
            archive = json.load(fh)
    else:
        archive = {"appName": app_name, "description": f"{app_name} desktop releases", "items": []}

    # One current entry per platform: older ones for the same platform are
    # superseded, not kept, since the client only ever wants the latest.
    archive["items"] = [item for item in archive["items"] if item.get("platform") != platform]
    archive["items"].append(
        {
            "version": version,
            "shortVersion": build_number,
            "changes": [{"type": "release", "message": changelog}] if changelog else [],
            "date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
            "mandatory": mandatory,
            "url": url,
            "platform": platform,
        }
    )

    os.makedirs(os.path.dirname(manifest_path) or ".", exist_ok=True)
    with open(manifest_path, "w") as fh:
        json.dump(archive, fh, indent=2)
    print(f"Updated {manifest_path}: {platform} -> {version}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--src", required=True, help="Flutter build output folder")
    parser.add_argument("--dest", required=True, help="Folder to copy files + hashes.json into")
    parser.add_argument("--manifest", required=True, help="Path to manifest.json to create/update")
    parser.add_argument("--version", required=True, help="App version, e.g. 0.4.0+47")
    parser.add_argument("--platform", required=True, choices=["windows", "macos", "linux"])
    parser.add_argument("--url", required=True, help="Public URL --dest will be served at")
    parser.add_argument("--app-name", default="OpenLucid")
    parser.add_argument("--changelog", default="")
    parser.add_argument("--mandatory", action="store_true")
    args = parser.parse_args()

    if generate_hashes(args.src, args.dest) == 0:
        return 1

    update_app_archive(
        args.manifest,
        app_name=args.app_name,
        version=args.version,
        platform=args.platform,
        url=args.url,
        changelog=args.changelog,
        mandatory=args.mandatory,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
