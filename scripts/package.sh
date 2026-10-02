#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$repo_dir/dist"
python3 - "$repo_dir" <<'PY'
import pathlib, sys, zipfile
root = pathlib.Path(sys.argv[1])
target = root / "dist/pr-pulse.plasmoid"
with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
    for item in [root / "metadata.json", root / "LICENSE", *(root / "contents").rglob("*")]:
        if item.is_file():
            archive.write(item, item.relative_to(root))
    archive.write(root / "src/pr_pulse.py", "contents/code/pr_pulse.py")
PY
echo "dist/pr-pulse.plasmoid"
