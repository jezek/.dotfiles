#!/usr/bin/env python3
"""Stage the latest stable Source Code Pro; return 2 if current, 3 for an upgrade.

The shell installer owns confirmation and installation. This helper only writes
to its temporary directory, so a declined update or failed download cannot
replace existing fonts. No Python packages beyond the standard library are used.
"""

import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from urllib.error import URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


API = "https://api.github.com/repos/adobe-fonts/source-code-pro"
RAW = "https://raw.githubusercontent.com/adobe-fonts/source-code-pro"
FACES = (
    ("Regular", "SourceCodePro-Regular"),
    ("Bold", "SourceCodePro-Bold"),
    ("Italic", "SourceCodePro-It"),
    ("Bold Italic", "SourceCodePro-BoldIt"),
)


def fetch(url):
    request = Request(url, headers={"User-Agent": "jezek-dotfiles-kitty"})
    with urlopen(request, timeout=30) as response:
        return response.read()


def api(path):
    return json.loads(fetch(f"{API}/{path}"))


def font_info(command, argument, expected_name):
    output = subprocess.check_output(
        [command, "-f", "%{postscriptname}\n%{fontversion}\n%{file}\n", argument],
        text=True,
    ).splitlines()
    if len(output) != 3 or output[0] != expected_name:
        return None
    return int(output[1]), Path(output[2])


def blob_hash(data):
    # Each release has different checksums. Verify against its Git tree;
    # Git blob hashes include the object type and length before the file data.
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


def download(commit, entry, destination):
    if entry["type"] != "blob" or entry["mode"] != "100644":
        raise ValueError(f"Unexpected upstream file: {entry['path']}")
    data = fetch(f"{RAW}/{commit}/{entry['path']}")
    if blob_hash(data) != entry["sha"]:
        raise ValueError(f"Checksum verification failed: {entry['path']}")
    destination.write_bytes(data)


def prepare(stage):
    installed = {
        name: font_info("fc-match", f"Source Code Pro:style={style}", name)
        for style, name in FACES
    }
    try:
        release = api("releases/latest")
        if release["draft"] or release["prerelease"]:
            raise ValueError("Adobe did not return a stable font release")
        tag = release["tag_name"]
        commit = api(f"commits/{quote(tag, safe='')}")["sha"]
        if not re.fullmatch(r"[0-9a-f]{40}", commit):
            raise ValueError("Invalid upstream commit ID")
        tree = api(f"git/trees/{commit}?recursive=1")
        if tree["truncated"]:
            raise ValueError("Incomplete upstream font file listing")
        entries = {entry["path"]: entry for entry in tree["tree"]}
    except (URLError, TimeoutError) as error:
        if all(installed.values()):
            print(f"Could not check Source Code Pro updates: {error}. Keeping installed fonts.", file=sys.stderr)
            return 2
        raise

    print(f"Latest stable Source Code Pro: {tag}", flush=True)
    changed = False
    upgrade = False
    for style, name in FACES:
        entry = entries[f"OTF/{name}.otf"]
        current = installed[name]
        if current and blob_hash(current[1].read_bytes()) == entry["sha"]:
            continue

        target = stage / f"{name}.otf"
        download(commit, entry, target)
        offered = font_info("fc-query", str(target), name)
        if offered is None:
            raise ValueError(f"Downloaded font is not the expected {name}")
        # Roman and italic faces have independent version numbers. Compare
        # their actual 16.16 OpenType revisions, including system-installed
        # fonts; a changed release tag alone must never trigger a downgrade.
        version = offered[0]
        if current and version <= current[0]:
            target.unlink()
            continue
        previous = f"{current[0] / 65536:.3f}" if current else "missing"
        print(f"  {style}: {previous} -> {version / 65536:.3f}", flush=True)
        changed = True
        upgrade = upgrade or current is not None

    if not changed:
        print("Source Code Pro is already current or newer; no font changes needed.")
        return 2
    download(commit, entries["LICENSE.md"], stage / "LICENSE.md")
    return 3 if upgrade else 0


if __name__ == "__main__":
    try:
        result = prepare(Path(sys.argv[1]))
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print(f"Preparing Source Code Pro failed: {error}", file=sys.stderr)
        result = 1
    sys.exit(result)
