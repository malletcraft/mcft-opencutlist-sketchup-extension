#!/bin/bash
# ---------------------------------------------------------------------------
# THE BUILD OUTPUTS ON DISK, MADE TO MATCH HEAD — and the check that they do.
#
#   tools/mcft-refresh-outputs.sh             refresh, always
#   tools/mcft-refresh-outputs.sh --if-stale  refresh only if the stamp names
#                                             another rbz than HEAD's
#   tools/mcft-refresh-outputs.sh --verify    change nothing; say whether the
#                                             clone still holds MOP
#
# The ONE implementation of both, called by tools/dev-install-mac.sh and by
# tools/mcft-autoupdate.rb at every SketchUp start (docs/mcft/MOP-ON-OCL8.md
# §6.2). SketchUp loads BUILT files — compiled dialog html, the common, modal
# and viewer bundles, i18n, css and the ten native engines — which upstream's
# build writes into src/ and .gitignore excludes. MOP takes every one of them
# from dist/ladb_opencutlist.rbz, never from a local build (the engines cannot
# be built here at all), and tracks exactly one itself: js/bundles/tabs-bundle.js.
#
# A refresh, in order:
#   1. (--if-stale) stop at once if the stamp's first line is HEAD's rbz blob;
#   2. unzip the rbz into a temp folder;
#   3. refuse unless the rbz's, HEAD's src and HEAD's dist/manifest.json name
#      ONE EXTENSION_BUILD (else the dialog's "zzz" lock) — nothing under src/
#      has been touched yet;
#   4. drop from the temp copy every path git tracks under src/, so the
#      branded loader, the live Ruby and the committed tabs bundle always win;
#   5. `git clean -fdXq -- src/`: every IGNORED file under src/ goes — every
#      old output, 7.1's dylibs, a stale .susig or extension_info.txt, the old
#      stamp. Nothing Amit owns lives under src/ (the estimate and update logs
#      are in Application Support);
#   6. copy the temp tree in with ONE command that means the same on macOS
#      (BSD cp) and on Linux (GNU cp, where CI proves it): cp -R <dir>/. <dir>/.
#      Not ditto, which exists only on macOS; not `cp -R a b` into an existing
#      b, which nests a second ladb_opencutlist inside it;
#   7. write the stamp LAST: the rbz blob, the build, then one POSIX cksum line
#      (CRC, size, path) per output laid down — content, not mtimes, and the
#      same command on both platforms.
#
# Exit codes, so the caller can tell the cases apart:
#   refresh   0 done · 20 failed BEFORE touching src/ · 21 failed AFTER
#   --verify  0 the clone holds MOP · 10 a tracked file has changed ·
#             11 the stamp is missing or names another rbz (an interrupted
#             refresh: git clean removes it first, it is written last) ·
#             12 an output no longer matches its cksum line
# ---------------------------------------------------------------------------
set -uo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.." || exit 20
STAMP=src/ladb_opencutlist/.mcft-outputs
RBZ=dist/ladb_opencutlist.rbz
mode="${1:-}"
case "$mode" in ''|--if-stale|--verify) ;; *) echo "usage: $0 [--if-stale|--verify]" >&2; exit 2 ;; esac

blob=$(git rev-parse --verify -q "HEAD:$RBZ") || { echo "refresh: HEAD has no $RBZ" >&2; exit 20; }

if [ "$mode" = "--verify" ]; then
  if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "verify: tracked files have changed:" >&2
    git status --porcelain --untracked-files=no | head -10 >&2
    exit 10
  fi
  if [ ! -f "$STAMP" ] || [ "$(head -1 "$STAMP")" != "$blob" ]; then
    echo "verify: no stamp for HEAD's rbz ${blob:0:9} (an interrupted or missing refresh)" >&2
    exit 11
  fi
  expected=$(tail -n +3 "$STAMP")
  actual=$(printf '%s\n' "$expected" | cut -d' ' -f3- | tr '\n' '\0' | xargs -0 cksum 2>/dev/null)
  if [ "$expected" != "$actual" ]; then
    echo "verify: build outputs differ from the stamp:" >&2
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | head -10 >&2
    exit 12
  fi
  echo "verify: tracked files clean; $(printf '%s\n' "$expected" | wc -l | tr -d ' ') outputs match rbz ${blob:0:9}"
  exit 0
fi

if [ "$mode" = "--if-stale" ] && [ -f "$STAMP" ] && [ "$(head -1 "$STAMP")" = "$blob" ]; then
  echo "refresh: outputs already from rbz ${blob:0:9}"
  exit 0
fi

tmp=$(mktemp -d) || exit 20
trap 'rm -rf "$tmp"' EXIT
fail_before() { echo "refresh REFUSED (src/ untouched): $*" >&2; exit 20; }
fail_after()  { echo "refresh FAILED after src/ was touched: $*" >&2; exit 21; }

unzip -q "$RBZ" 'ladb_opencutlist/*' -d "$tmp" || fail_before "cannot unzip $RBZ"
[ -d "$tmp/ladb_opencutlist" ] || fail_before "$RBZ holds no ladb_opencutlist/"

build_of() { sed -n "s/.*EXTENSION_BUILD *= *'\([^']*\)'.*/\1/p" | head -1; }
b_rbz=$(build_of < "$tmp/ladb_opencutlist/ruby/constants.rb")
b_src=$(git show "HEAD:src/ladb_opencutlist/ruby/constants.rb" | build_of)
b_man=$(git show "HEAD:dist/manifest.json" | sed -n 's/.*"build" *: *"\([^"]*\)".*/\1/p' | head -1)
if [ -z "$b_rbz" ] || [ "$b_rbz" != "$b_src" ] || [ "$b_rbz" != "$b_man" ]; then
  fail_before "EXTENSION_BUILD differs: rbz=$b_rbz src=$b_src manifest=$b_man"
fi

# Tracked files win: drop them from what will be copied.
git ls-files -z -- src/ladb_opencutlist/ | while IFS= read -r -d '' p; do
  rm -f "$tmp/${p#src/}"
done
find "$tmp/ladb_opencutlist" -depth -type d -empty -delete 2>/dev/null
[ -d "$tmp/ladb_opencutlist" ] || fail_before "the rbz holds nothing that git does not already track"

# From here on src/ is being changed.
git clean -fdXq -- src/ || fail_after "git clean -fdXq -- src/ failed"
cp -R "$tmp/ladb_opencutlist/." "src/ladb_opencutlist/" || fail_after "copying the outputs into src/ failed"

{
  echo "$blob"
  echo "$b_rbz"
  (cd "$tmp" && find ladb_opencutlist -type f | sort) | sed 's#^#src/#' | tr '\n' '\0' | xargs -0 cksum
} > "$STAMP.tmp" || fail_after "writing the stamp failed"
mv "$STAMP.tmp" "$STAMP" || fail_after "writing the stamp failed"
echo "refresh: $(($(wc -l < "$STAMP") - 2)) outputs laid down from rbz ${blob:0:9} (build $b_rbz)"
exit 0
