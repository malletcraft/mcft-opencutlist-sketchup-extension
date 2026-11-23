#!/bin/bash
# ---------------------------------------------------------------------------
# tools/mcft-refresh-outputs.sh, RUN against a throwaway copy of this commit —
# on Linux, with the very cp command the Mac runs (docs/mcft/MOP-ON-OCL8.md
# §7.3 check 5). The refresh is what every SketchUp start trusts to make the
# build outputs match HEAD, and --verify is what stops the updater announcing
# "up to date" on a clone that no longer holds MOP; both are proved here.
# ---------------------------------------------------------------------------
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0
ok()   { echo "  ok    $*"; }
bad()  { echo "  FAIL  $*"; fails=$((fails + 1)); }
expect() { # expect <code> <what> -- command...
  local want=$1 what=$2; shift 3
  "$@" > "$work/out" 2>&1; local got=$?
  if [ "$got" -eq "$want" ]; then ok "$what (exit $got)"; else bad "$what: exit $got, expected $want"; sed 's/^/        /' "$work/out" | tail -5; fi
}

R="$work/repo"
git init -q "$R"
git -C "$R" fetch -q --depth=1 "file://$ROOT" "$(git -C "$ROOT" rev-parse HEAD)" || { echo "cannot copy the commit"; exit 1; }
git -C "$R" checkout -q FETCH_HEAD
git -C "$R" -c user.name=check -c user.email=check@invalid commit -q --allow-empty -m base
S="$R/tools/mcft-refresh-outputs.sh"
O="$R/src/ladb_opencutlist"

# Stale outputs of the kind 7.1 left on the Mac.
mkdir -p "$O/bin/osx/lib"
echo stale > "$O/bin/osx/lib/libPacky.dylib"
echo stale > "$O/extension_info.txt"
echo stale > "$O/ladb_opencutlist.susig"
before=$(git -C "$R" ls-files -s)

echo "a refresh"
expect 0 'refresh runs' -- "$S"
[ "$(git -C "$R" ls-files -s)" = "$before" ] && [ -z "$(git -C "$R" status --porcelain --untracked-files=no)" ] \
  && ok 'every tracked file is byte-identical' || bad 'a tracked file changed'
cmp -s "$O/bin/osx/lib/libPacky.dylib" <(unzip -p "$R/dist/ladb_opencutlist.rbz" ladb_opencutlist/bin/osx/lib/libPacky.dylib) \
  && ok 'a stale libPacky.dylib is replaced by the rbz one' || bad 'libPacky.dylib is not the rbz one'
[ ! -e "$O/extension_info.txt" ] && [ ! -e "$O/ladb_opencutlist.susig" ] \
  && ok 'stale extension_info.txt and .susig are gone' || bad 'a stale extension_info.txt or .susig survived'
[ ! -e "$O/ladb_opencutlist" ] && ok 'no nested src/ladb_opencutlist/ladb_opencutlist' || bad 'cp nested a second ladb_opencutlist'
rbz_only=$(cd "$work" && unzip -Z1 "$R/dist/ladb_opencutlist.rbz" 'ladb_opencutlist/*' | grep -v '/$' \
  | sed 's#^#src/#' | grep -vxF -f <(git -C "$R" ls-files src) | wc -l)
lines=$(($(wc -l < "$O/.mcft-outputs") - 2))
[ "$(head -1 "$O/.mcft-outputs" | cut -d' ' -f1)" = "$(git -C "$R" rev-parse HEAD:dist/ladb_opencutlist.rbz)" ] && [ "$lines" -eq "$rbz_only" ] && [ "$rbz_only" -gt 0 ] \
  && ok "the stamp names HEAD's rbz and carries one cksum line per output ($lines)" || bad "stamp: $lines lines for $rbz_only rbz-only files"
[ -z "$(git -C "$R" status --porcelain --untracked-files=all)" ] \
  && ok 'nothing untracked: every rbz output falls under an ignore rule' \
  || { bad 'untracked files after a refresh (an rbz output with no ignore rule?)'; git -C "$R" status --porcelain --untracked-files=all | head -5; }

echo "--if-stale"
m1=$(cksum < "$O/.mcft-outputs")
expect 0 'an up-to-date stamp is a no-op' -- "$S" --if-stale
grep -q 'already from rbz' "$work/out" && [ "$(cksum < "$O/.mcft-outputs")" = "$m1" ] \
  && ok 'it did not refresh' || bad '--if-stale refreshed an up-to-date tree'

echo "--verify"
expect 0 'a fresh refresh verifies' -- "$S" --verify
echo '# edited' >> "$R/README.md"
expect 10 'a tracked file edited' -- "$S" --verify
git -C "$R" checkout -q -- README.md
f=$(sed -n '3p' "$O/.mcft-outputs" | cut -d' ' -f3-)
printf 'x' >> "$R/$f"
expect 12 "one byte appended to an output ($f)" -- "$S" --verify
expect 0 'a full refresh heals it' -- "$S"
expect 0 'and it verifies again' -- "$S" --verify
rm "$O/.mcft-outputs"
expect 11 'the stamp deleted' -- "$S" --verify
expect 0 '--if-stale with no stamp refreshes' -- "$S" --if-stale

echo "a commit that changes what is tracked, with the same rbz"
# The review: the stamp keyed on the rbz blob alone, so a fast-forward that
# started or stopped tracking an rbz file left the outputs wrong under "up to
# date". The file is one the rbz carries and this line does not track today.
cb=src/ladb_opencutlist/js/bundles/common-bundle.js
commit() { git -C "$R" -c user.name=check -c user.email=check@invalid commit -q "$@"; }
echo '// an MCFT copy' >> "$R/$cb"
git -C "$R" add -f "$cb" && commit -m 'start tracking common-bundle.js'
expect 11 'starting to track an rbz file: --verify asks for a refresh, not 0 or 12' -- "$S" --verify
expect 0 '--if-stale refreshes' -- "$S" --if-stale
grep -q 'laid down' "$work/out" && ok 'it did refresh' || bad '--if-stale did not refresh'
expect 0 'and it verifies' -- "$S" --verify
tail -1 "$R/$cb" | grep -q 'an MCFT copy' && ok 'the tracked copy won' || bad 'the refresh overwrote the tracked copy'
git -C "$R" rm -q "$cb" && commit -m 'stop tracking it again'
[ ! -e "$R/$cb" ] && ok 'the commit deleted it' || bad 'the file is still there'
expect 11 'stopping tracking an rbz file: --verify asks for a refresh, not 0' -- "$S" --verify
expect 0 '--if-stale refreshes' -- "$S" --if-stale
cmp -s "$R/$cb" <(unzip -p "$R/dist/ladb_opencutlist.rbz" "ladb_opencutlist/js/bundles/common-bundle.js") \
  && ok "the rbz's copy is laid down again" || bad 'common-bundle.js is missing or not the rbz one'
expect 0 'and it verifies' -- "$S" --verify
[ -z "$(git -C "$R" status --porcelain --untracked-files=all)" ] && ok 'nothing untracked' || bad 'untracked files left'

echo "the installer, with a fake HOME"
# The review: it cleared Plugins BEFORE the refresh, so a refused refresh left
# no OpenCutList at all under words that said "src/ untouched". Run for real,
# with a stock 8 install in a fake Plugins and an unzip that fails first.
H="$work/home"; P="$H/Library/Application Support/SketchUp 2026/SketchUp/Plugins"
mkdir -p "$P/ladb_opencutlist" "$work/bin"; echo stock > "$P/ladb_opencutlist.rb"
printf '#!/bin/sh\nexit 9\n' > "$work/bin/unzip"; chmod +x "$work/bin/unzip"
git -C "$R" checkout -q -B mcft
expect 1 'a refused refresh stops the installer' -- env HOME="$H" PATH="$work/bin:$PATH" bash "$R/tools/dev-install-mac.sh"
grep -q 'Plugins was not touched' "$work/out" && ok 'and it says Plugins was not touched' || bad 'no plain words for a refused install'
[ -d "$P/ladb_opencutlist" ] && [ ! -L "$P/ladb_opencutlist" ] && [ "$(cat "$P/ladb_opencutlist.rb")" = stock ] \
  && ok 'the stock install is still in Plugins' || bad 'Plugins lost its OpenCutList on a refused install'
expect 0 'with a working unzip it installs' -- env HOME="$H" bash "$R/tools/dev-install-mac.sh"
[ "$(readlink "$P/ladb_opencutlist")" = "$R/src/ladb_opencutlist" ] && [ "$(readlink "$P/ladb_opencutlist.rb")" = "$R/src/ladb_opencutlist.rb" ] \
  && [ -f "$P/!mcft_autoupdate.rb" ] && ok 'the two links and the stub are in Plugins' || bad 'the links or the stub are missing'
expect 0 'and the clone verifies' -- "$S" --verify

echo "a build mismatch"
listing() { (cd "$O" && find . -type f -print0 | sort -z | xargs -0 cksum); }
sed -i 's/"build": *"[0-9]*"/"build": "190001010000"/' "$R/dist/manifest.json"
git -C "$R" -c user.name=check -c user.email=check@invalid commit -q -am 'plant a build mismatch'
pre=$(listing)
expect 20 'the refresh refuses' -- "$S"
[ "$(listing)" = "$pre" ] && ok 'and src/ is untouched' || bad 'src/ changed although the refresh refused'

echo
if [ "$fails" -gt 0 ]; then echo "::error::check-refresh-outputs: $fails check(s) failed"; exit 1; fi
echo "check-refresh-outputs: refresh, --if-stale and --verify behave as the updater relies on"
