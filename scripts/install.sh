#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$repo_dir/scripts/package.sh"
if kpackagetool6 --type Plasma/Applet --show io.github.xiahongze.prpulse >/dev/null 2>&1; then
  kpackagetool6 --type Plasma/Applet --upgrade "$repo_dir/dist/pr-pulse.plasmoid"
else
  kpackagetool6 --type Plasma/Applet --install "$repo_dir/dist/pr-pulse.plasmoid"
fi
if command -v kbuildsycoca6 >/dev/null 2>&1; then
  kbuildsycoca6 --noincremental >/dev/null
fi
echo "Installed PR Pulse. Add it from Plasma's widget picker."
