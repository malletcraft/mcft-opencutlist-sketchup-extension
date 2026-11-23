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
[ "$(head -1 "$O/.mcft-outputs")" = "$(git -C "$R" rev-parse HEAD:dist/ladb_opencutlist.rbz)" ] && [ "$lines" -eq "$rbz_only" ] && [ "$rbz_only" -gt 0 ] \
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
