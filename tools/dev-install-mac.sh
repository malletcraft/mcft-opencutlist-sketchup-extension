#!/bin/bash
# ---------------------------------------------------------------------------
# MCFT dev install for SketchUp on macOS (S3 MOP on OpenCutList 8).
#
# Run ONCE, with SketchUp quit. From then on the ONLY update step is:
# restart SketchUp. Never `git pull` this clone, never click OpenCutList's
# Upgrade, never install an OpenCutList .rbz (docs/mcft/MOP-ON-OCL8.md §6.4).
#
# What it does, in order:
#   1. refuses while SketchUp runs;
#   2. refuses unless this clone is on branch mcft with no tracked file
#      changed — the build outputs are laid down against HEAD, so HEAD must be
#      the published commit. The way out is a fresh clone (below);
#   3. clears Plugins of whatever OpenCutList is there: a stock install's real
#      folder and file, old links, and OpenCutList 8's updater backups
#      (rm removes a link, never its target). ~/Library/Application
#      Support/OpenCutList is left alone: MOP on 8 shares it (same plugin id);
#   4. lays every build output down from dist/ladb_opencutlist.rbz
#      (tools/mcft-refresh-outputs.sh — the same script every start runs);
#   5. links this clone into Plugins;
#   6. writes the startup stub, which loads tools/mcft-autoupdate.rb from this
#      clone on every start;
#   7. turns on this clone's git hooks.
#
# Usage:  bash tools/dev-install-mac.sh
# Fresh clone, if step 2 refuses (SketchUp quit; nothing in the clone is
# unique — all MCFT work is on GitHub, the logs are in Application Support):
#   rm -rf <this clone>
#   git clone --filter=blob:none --branch mcft \
#     https://github.com/malletcraft/mcft-opencutlist-sketchup-extension.git <this clone>
#   bash <this clone>/tools/dev-install-mac.sh
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$(pwd)"

# 1.
if pgrep -x SketchUp > /dev/null; then
  echo "Quit SketchUp first, then run this again."
  exit 1
fi

# 2.
branch=$(git symbolic-ref -q --short HEAD || echo '(detached)')
dirty=$(git status --porcelain --untracked-files=no)
if [ "$branch" != "mcft" ] || [ -n "$dirty" ]; then
  echo "REFUSED: this clone is on '$branch'${dirty:+ with changed tracked files}."
  echo "MOP installs only from a clean clone of branch mcft. With SketchUp quit:"
  echo "  rm -rf \"$REPO\""
  echo "  git clone --filter=blob:none --branch mcft https://github.com/malletcraft/mcft-opencutlist-sketchup-extension.git \"$REPO\""
  echo "  bash \"$REPO/tools/dev-install-mac.sh\""
  [ -n "$dirty" ] && { echo; echo "Changed tracked files:"; echo "$dirty" | head -10; }
  exit 1
fi

PLUG=$(ls -d "$HOME/Library/Application Support/SketchUp "*/SketchUp/Plugins 2>/dev/null | sort | tail -1)
[ -n "$PLUG" ] || { echo "No SketchUp Plugins folder found under ~/Library/Application Support"; exit 1; }
echo "Plugins folder: $PLUG"

# 3.
rm -rf "$PLUG/ladb_opencutlist" "$PLUG/ladb_opencutlist.rb" \
       "$PLUG/ladb_opencutlist.upgrade_backup" "$PLUG/ladb_opencutlist.rb.upgrade_backup"

# 4.
bash "$REPO/tools/mcft-refresh-outputs.sh"

# 5.
ln -s "$REPO/src/ladb_opencutlist.rb" "$PLUG/ladb_opencutlist.rb"
ln -s "$REPO/src/ladb_opencutlist"    "$PLUG/ladb_opencutlist"

# 6. The stub holds the clone's path and nothing else; the logic lives in the
#    clone (tools/mcft-autoupdate.rb), so it updates with the code it updates.
#    If the clone or the updater is missing it says so and names the way back:
#    it never falls back to an older copy.
cat > "$PLUG/!mcft_autoupdate.rb" <<RUBY
# MCFT auto-update stub — written by tools/dev-install-mac.sh. It loads the
# updater from the MOP clone below on every SketchUp start, before OpenCutList
# (the "!" sorts first). Delete this file only to stop MOP updating.
begin
  repo = '$REPO'
  updater = File.join(repo, 'tools', 'mcft-autoupdate.rb')
  if File.file?(updater)
    load updater
    McftAutoupdate.run(repo, __dir__)
  else
    puts "[MCFT] update NOT RUN: #{updater} is missing"
    UI.messagebox("MCFT: MOP's updater is missing:\n#{updater}\n\n" \\
                  "The clone at #{repo} is gone or damaged. With SketchUp quit, make a fresh clone " \\
                  "of branch mcft there and run its tools/dev-install-mac.sh.")
  end
rescue StandardError, ScriptError => e
  puts "[MCFT] update skipped (#{e.class}: #{e.message})"
end
RUBY

# 7.
git config core.hooksPath .githooks

echo "Installed. Start SketchUp: Extension Manager should show OpenCutList (MCFT Edition),"
echo "and the Ruby Console '[MCFT] OpenCutList (MCFT Edition) up to date @ <rev>'."
echo "From now on the ONLY update step is: restart SketchUp."
