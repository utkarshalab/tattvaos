#!/usr/bin/env python3
"""Build the icon packs listed in icons/sources.json.

    build_icons.py <sources.json> <out-dir> [--cache DIR] [--only ID[,ID]]

For every set: a sparse, blob-filtered clone of the repository at the
pinned commit (kept in the cache, default <out-dir>/src), then every
folder in "packs" converted with svg2uic into <out-dir>/<pack>.uic. The
set's licence file is copied to <out-dir>/LICENSES/<id>.txt, and
<out-dir>/NOTICE lists every set, its licence, attribution, commit and
packs. A set whose fetch or conversion fails is reported; the others are
still built (exit status 1 then).

Development-machine tooling only; not part of any OS image.
"""
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import svg2uic  # noqa: E402
from uic import pack  # noqa: E402


def git(args, cwd=None):
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError(f"git {' '.join(args)}: {r.stderr.strip()}")
    return r.stdout.strip()


def fetch(s, cache):
    """The set's sources at its pinned commit -> directory."""
    path = os.path.join(cache, s["id"])
    folders = sorted(set(s["packs"].values()))
    if not os.path.isdir(os.path.join(path, ".git")):
        os.makedirs(cache, exist_ok=True)
        git(["clone", "-q", "--filter=blob:none", "--no-checkout", s["repo"], path])
    git(["sparse-checkout", "set", *folders], path)
    try:
        git(["checkout", "-q", s["commit"]], path)
    except RuntimeError:
        git(["fetch", "-q", "--filter=blob:none", "origin", s["commit"]], path)
        git(["checkout", "-q", s["commit"]], path)
    return path


def build_set(s, cache, out):
    src = fetch(s, cache)
    built = []
    for name, folder in s["packs"].items():
        d = os.path.join(src, folder)
        icons, skipped, warned = [], 0, 0
        for f in sorted(os.listdir(d)):
            if not f.endswith(".svg"):
                continue
            try:
                icon, warnings = svg2uic.convert(open(os.path.join(d, f), encoding="utf-8").read(), f[:-4])
            except Exception as e:      # one broken file does not stop the pack
                print(f"  {name}: skipped {f}: {e}", file=sys.stderr)
                skipped += 1
                continue
            warned += bool(warnings)
            icons.append(icon)
        data = pack(icons)
        open(os.path.join(out, f"{name}.uic"), "wb").write(data)
        built.append((name, len(icons), len(data)))
        print(f"  {name}.uic: {len(icons)} icons, {len(data)} bytes"
              + (f", {skipped} skipped" if skipped else "") + (f", {warned} with warnings" if warned else ""))
    lic = os.path.join(src, s["licence_file"])
    os.makedirs(os.path.join(out, "LICENSES"), exist_ok=True)
    shutil.copyfile(lic, os.path.join(out, "LICENSES", f"{s['id']}.txt"))
    return built


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    sources, out = argv[0], argv[1]
    cache, only = os.path.join(out, "src"), None
    rest = argv[2:]
    while rest:
        opt = rest.pop(0)
        if opt == "--cache":
            cache = rest.pop(0)
        elif opt == "--only":
            only = set(rest.pop(0).split(","))
        else:
            sys.exit(__doc__)
    conf = json.load(open(sources, encoding="utf-8"))
    os.makedirs(out, exist_ok=True)
    notice, failed = ["Icon packs built from these open icon sets:", ""], 0
    for s in conf["sets"]:
        if only and s["id"] not in only:
            continue
        print(f"{s['name']} ({s['licence']}) @ {s['commit'][:12]}")
        try:
            built = build_set(s, cache, out)
        except Exception as e:
            print(f"  failed: {e}", file=sys.stderr)
            failed += 1
            continue
        notice += [f"{s['name']} - {s['licence']} - {s['attribution']}",
                   f"  {s['repo']} @ {s['commit']}",
                   "  packs: " + ", ".join(f"{n}.uic ({c} icons)" for n, c, _ in built),
                   f"  licence text: LICENSES/{s['id']}.txt", ""]
    for k, why in conf.get("excluded", {}).items():
        notice.append(f"Not included: {k} - {why}")
    open(os.path.join(out, "NOTICE"), "w", encoding="utf-8").write("\n".join(notice) + "\n")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main(sys.argv[1:])
