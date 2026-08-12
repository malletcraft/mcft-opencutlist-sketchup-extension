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

# 2. BUILD OUTPUTS from the shipped rbz -> src tree. The repo holds SOURCE
#    (twig templates, less, i18n-src); SketchUp loads the BUILT files —
#    compiled dialog html, bundled js/css, i18n yml, native engines — which
#    upstream's gulp build writes into src/ and .gitignore excludes. Without
#    them the extension dies at first get_i18n_string (missing en.yml).
#    Copy every rbz file missing from src; NEVER overwrite src files, so the
#    branded loader and live source always win. Re-runs just top up.
#    (unzip -n = never overwrite; rbz entries are 'ladb_opencutlist/...' so
#    -d src lands them exactly at src/ladb_opencutlist/...)
unzip -nq "$REPO/dist/ladb_opencutlist.rbz" 'ladb_opencutlist/*' -d "$REPO/src"
echo "Build outputs synced from dist rbz (i18n, dialog html, js/css, native engines)"

# 3. symlink the live source
ln -s "$REPO/src/ladb_opencutlist.rb" "$PLUG/ladb_opencutlist.rb"
ln -s "$REPO/src/ladb_opencutlist"    "$PLUG/ladb_opencutlist"

# 4. the auto-updater: every SketchUp start fast-forwards this clone from
#    GitHub BEFORE OpenCutList loads, so "restart SketchUp" IS the update.
#    The leading "!" makes it load first (SketchUp loads Plugins in sorted
#    order). Fails silently and instantly when offline; never merges — if the
#    clone has local edits it just skips, it cannot destroy work.
cat > "$PLUG/!mcft_autoupdate.rb" <<RUBY
# MCFT auto-update — written by dev-install-mac.sh; safe to delete to opt out.
begin
  repo = '$REPO'
  if File.directory?(File.join(repo, '.git'))
    out = \`git -C "#{repo}" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=4 pull --ff-only --quiet 2>&1\`
    if \$?.success?
      rev = \`git -C "#{repo}" log -1 --format=%h\`.strip
      puts "[MCFT] OpenCutList (MCFT Edition) up to date @ #{rev}"
    else
      puts "[MCFT] update skipped (#{out.lines.last.to_s.strip})"
    end
  end
rescue StandardError => e
  puts "[MCFT] update skipped (#{e.message})"
end
RUBY

echo "Linked + auto-update installed. Restart SketchUp — Extension Manager"
echo "should show:  OpenCutList (MCFT Edition)"
echo "From now on the ONLY update step is: restart SketchUp."
