#!/usr/bin/env python3
"""Rename xcresult-exported attachments to their human names (NN-foo.png).

Usage: _rename_shots.py <export_dir> <dest_dir>
The export dir is what `xcresulttool export attachments` produced (files +
manifest.json). Robust to manifest key spelling differences across Xcode
versions: it just walks the JSON for any node carrying both an exported
filename and a human-readable name shaped like "NN-foo".
"""
import json
import re
import shutil
import sys
from pathlib import Path

src, dst = Path(sys.argv[1]), Path(sys.argv[2])
dst.mkdir(parents=True, exist_ok=True)
manifest = json.loads((src / "manifest.json").read_text())

NAME_KEYS = ("suggestedHumanReadableName", "humanReadableName", "name")
FILE_KEYS = ("exportedFileName", "fileName", "exportedName")


def walk(obj):
    if isinstance(obj, dict):
        yield obj
        for v in obj.values():
            yield from walk(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from walk(v)


count, seen = 0, set()
for node in walk(manifest):
    fn = next((node[k] for k in FILE_KEYS if isinstance(node.get(k), str)), None)
    hn = next((node[k] for k in NAME_KEYS if isinstance(node.get(k), str)), None)
    if not fn or not hn:
        continue
    m = re.match(r"(\d{2}-[a-z0-9-]+)", hn)
    if not m or not (src / fn).exists():
        continue
    name = m.group(1) + ".png"
    if name in seen:
        continue
    shutil.copyfile(src / fn, dst / name)
    seen.add(name)
    count += 1

print(f"copied {count} screenshots -> {dst}")
if count == 0:
    sys.exit("no screenshots matched; inspect manifest.json")
