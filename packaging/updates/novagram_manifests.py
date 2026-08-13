#!/usr/bin/env python3
"""Rewrites the NovaGram update manifests from the latest GitHub release.

Lives in confeden/nova_updates as .github/scripts/novagram_manifests.py and is
run by .github/workflows/publish-novagram-manifests.yml.

The manifests keep the shape of the existing version.json so that everything in
that repository looks the same:

    {"version": ..., "url": ..., "sha256": ..., "release_url": ...}

One release covers both platforms, so its tag carries both base versions:

    v<desktop base>/<android base>      for example v7.0.9/12.9.2

Each manifest gets only its own half, and each client compares only its own
half against the version it was built from. That is what makes an Android-only
release invisible to the desktop: if the desktop base did not move, the number
in Novagram_PC.json does not move either, and every desktop client correctly
reports that there is nothing to install.

The digest is the one the clients check the downloaded file against, so it is
computed here from the asset itself rather than trusted from anywhere. A
release without a matching asset leaves that platform's manifest untouched:
publishing an empty one would tell every client that it is up to date with
nothing.
"""

import hashlib
import json
import os
import sys
import urllib.error
import urllib.request

OWNER = "confeden"
REPO = "Novagram"
API = f"https://api.github.com/repos/{OWNER}/{REPO}/releases/latest"

# One manifest per platform: the file, how to recognise its asset among the
# rest, and which half of the tag belongs to it.
TARGETS = (
    ("Novagram_PC.json", lambda name: name.lower().endswith(".exe"), 0),
    ("Novagram_android.json", lambda name: name.lower().endswith(".apk"), 1),
)


def versions(tag):
    """Splits "v7.0.9/12.9.2" into ("7.0.9", "12.9.2").

    A tag with one number in it gives that number to both platforms, so an
    older single-platform tag still works.
    """
    parts = (tag[1:] if tag.startswith("v") else tag).split("/")
    parts = [part.strip() for part in parts if part.strip()]
    if not parts:
        return []
    return parts if len(parts) > 1 else [parts[0], parts[0]]


def request(url, token, binary=False):
    headers = {
        "Accept": "application/octet-stream" if binary else "application/vnd.github+json",
        "User-Agent": "novagram-manifests",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    with urllib.request.urlopen(
        urllib.request.Request(url, headers=headers)
    ) as response:
        return response.read()


def digest(url, token):
    hash = hashlib.sha256()
    hash.update(request(url, token, binary=True))
    return hash.hexdigest()


def main():
    token = os.environ.get("RELEASES_TOKEN") or ""
    try:
        release = json.loads(request(API, token))
    except urllib.error.HTTPError as error:
        if error.code == 404:
            print("No published release yet, nothing to do.")
            return 0
        raise

    tag = release.get("tag_name") or ""
    parts = versions(tag)
    if not parts:
        print("The latest release has no tag, nothing to do.")
        return 0
    if release.get("draft") or release.get("prerelease"):
        print(f"Latest release {tag} is a draft or a prerelease, skipping.")
        return 0

    assets = release.get("assets") or []
    for name, matches, index in TARGETS:
        asset = next((a for a in assets if matches(a.get("name", ""))), None)
        if asset is None:
            print(f"{name}: release {tag} carries no matching asset, left as is.")
            continue
        if index >= len(parts):
            print(f"{name}: tag {tag} has no version for this platform, left as is.")
            continue
        manifest = {
            "version": parts[index],
            "url": asset["browser_download_url"],
            "sha256": digest(asset["url"], token),
            "release_url": release["html_url"],
            # Only so the update bar can say how much it is about to download.
            # Clients treat a missing "size" as unknown and show nothing, so
            # manifests written before this field are still valid.
            "size": asset.get("size", 0),
        }
        with open(name, "w", encoding="utf-8") as file:
            json.dump(manifest, file, indent=2, ensure_ascii=False)
            file.write("\n")
        print(f"{name}: {manifest['version']} -> {manifest['url']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
