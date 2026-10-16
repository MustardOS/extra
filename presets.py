#!/usr/bin/env python3
"""Rebuild filters.json and shaders.json from the preset files in this repo.

Name and version are read out of each preset rather than kept in a second place,
so the manifest cannot drift from what it describes.

    ./presets.py                     # regenerate both manifests
    ./presets.py --import <muos>     # also copy the presets muOS ships
"""

import argparse
import hashlib
import json
import os
import re
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
RAW_BASE = "https://raw.githubusercontent.com/MustardOS/extra/refs/heads/main"

RESERVED = {"none"}

KINDS = {
    "filter": {"ext": ".ini", "manifest": "filters.json"},
    "shader": {"ext": ".frag", "manifest": "shaders.json"},
}


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(65536), b""):
            digest.update(block)
    return digest.hexdigest()


def read_metadata(path, kind):
    """Pull the display name, author and version out of a preset."""
    name = author = version = None

    with open(path, "r", errors="replace") as handle:
        for line in handle:
            if kind == "filter":
                match = re.match(r"\s*(name|author|version)\s*=\s*(.+?)\s*$", line)
            else:
                match = re.match(r"\s*//\s*(Name|Author|Version)\s*:\s*(.+?)\s*$", line)

            if match:
                key, value = match.group(1).lower(), match.group(2)
                if key == "name" and not name:
                    name = value
                elif key == "author" and not author:
                    author = value
                elif key == "version" and not version:
                    version = value

            if name and author and version:
                break

    return name, author or "MustardOS", version or "1"


def import_shipped(muos_share):
    """Copy the presets muOS ships so they can be downloaded by older builds too."""
    for kind, spec in KINDS.items():
        source = os.path.join(muos_share, kind)
        target = os.path.join(HERE, kind)

        if not os.path.isdir(source):
            print(f"  {source}: not found, skipped")
            continue

        os.makedirs(target, exist_ok=True)
        copied = 0

        for entry in sorted(os.listdir(source)):
            if not entry.endswith(spec["ext"]):
                continue
            if os.path.splitext(entry)[0].lower() in RESERVED:
                continue

            shutil.copy2(os.path.join(source, entry), os.path.join(target, entry))
            copied += 1

        print(f"  {kind}: imported {copied}")


def build(kind):
    spec = KINDS[kind]
    directory = os.path.join(HERE, kind)
    entries = []

    for entry in sorted(os.listdir(directory)):
        if not entry.endswith(spec["ext"]):
            continue

        stem = os.path.splitext(entry)[0]
        if stem.lower() in RESERVED:
            continue

        path = os.path.join(directory, entry)
        name, author, version = read_metadata(path, kind)

        if not name:
            print(f"  [WARN] {entry}: no name declared, skipping")
            continue

        entries.append({
            "name": name,
            "author": author,
            "url": f"{RAW_BASE}/{kind}/{entry}",
            "version": version,
            "sha256": sha256(path),
        })

    # Keep presets hosted elsewhere, they have no local file to rebuild from
    output = os.path.join(HERE, "data", spec["manifest"])
    if os.path.isfile(output):
        with open(output, "r") as handle:
            for item in json.load(handle):
                if not item.get("url", "").startswith(f"{RAW_BASE}/"):
                    entries.append(item)

    entries.sort(key=lambda item: item["name"].casefold())

    seen = {}
    for item in entries:
        seen.setdefault(item["name"].casefold(), []).append(item["url"])
    for name, urls in seen.items():
        if len(urls) > 1:
            print(f"  [WARN] duplicate name '{name}': {', '.join(urls)}")

    with open(output, "w") as handle:
        json.dump(entries, handle, indent=2)
        handle.write("\n")

    print(f"  {spec['manifest']}: {len(entries)} entries")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--import", dest="muos_share", help="path to the muOS internal share directory")
    arguments = parser.parse_args()

    if arguments.muos_share:
        print("importing:")
        import_shipped(arguments.muos_share)

    print("building:")
    for kind in KINDS:
        build(kind)
