#!/bin/bash
# ---------------------------------------------------------------------------
# MCFT dev install for SketchUp on macOS — symlink once, then every update is
#   git pull && restart SketchUp
#
# What it does:
#   1. finds your newest SketchUp Plugins folder
#   2. removes any installed stock OpenCutList (files only — uninstall via
#      Extension Manager first if it was installed from Extension Warehouse)
#   3. symlinks THIS CLONE's src/ into Plugins
#   4. extracts the native engines (Packy/Clippy/Imagy dylibs) out of
#      dist/ladb_opencutlist.rbz into the tree — they are not in git, and
#      without them cutting diagrams cannot load (everything else runs)
#
# Usage:  ./tools/dev-install-mac.sh
# Update: git pull   (re-run this script only if upstream bumps the binaries)
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$(pwd)"

PLUG=$(ls -d "$HOME/Library/Application Support/SketchUp "*/SketchUp/Plugins 2>/dev/null | sort | tail -1)
[ -n "$PLUG" ] || { echo "No SketchUp Plugins folder found under ~/Library/Application Support"; exit 1; }
echo "Plugins folder: $PLUG"

# 1. clear stock OCL / previous copies (symlinks or real dirs)
rm -rf "$PLUG/ladb_opencutlist" "$PLUG/ladb_opencutlist.rb"

# 2. native engines from the built rbz -> src tree (gitignored; survives pulls)
if [ ! -d "$REPO/src/ladb_opencutlist/bin/osx" ]; then
  TMP=$(mktemp -d)
  unzip -q "$REPO/dist/ladb_opencutlist.rbz" 'ladb_opencutlist/bin/osx/*' -d "$TMP"
  mkdir -p "$REPO/src/ladb_opencutlist/bin"
  cp -R "$TMP/ladb_opencutlist/bin/osx" "$REPO/src/ladb_opencutlist/bin/osx"
  rm -rf "$TMP"
  echo "Native engines extracted (bin/osx)"
fi

# 3. symlink the live source
ln -s "$REPO/src/ladb_opencutlist.rb" "$PLUG/ladb_opencutlist.rb"
ln -s "$REPO/src/ladb_opencutlist"    "$PLUG/ladb_opencutlist"
echo "Linked. Restart SketchUp — Extension Manager should show:"
echo "  OpenCutList (MCFT Edition)"
echo "From now on:  git pull && restart SketchUp"
