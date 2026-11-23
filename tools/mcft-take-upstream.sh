#!/bin/bash
# ---------------------------------------------------------------------------
# MAKE THE TREE FROM AN UPSTREAM BUILD — the content half of every upstream
# move on the mcft line (docs/mcft/MOP-ON-OCL8.md §1.2).
#
#   tools/mcft-take-upstream.sh <build sha>
#
# Run it after `git merge --no-commit -s ours <build sha>` (a move to a newer
# build), or on its own (going back to an earlier build). It never asks git's
# merge base anything: git's base on this line is a virtual one, and after a
# go-back commit it would be the bad build, so a plain merge silently leaves
# out whatever that build changed. Content comes from the build NAMED here.
#
# In order:
#   1. every path the build has that is not MCFT's is checked out from it;
#   2. every path HEAD has that is neither in the build nor MCFT's is removed;
#   3. every upstream file MCFT changes is three-way merged — MCFT's version
#      (the work tree) against the build docs/mcft/UPSTREAM names (the base)
#      and the new build (the other side) — leaving conflict markers;
#   4. the new build's sha is written to docs/mcft/UPSTREAM.
#
# It STOPS, naming the path, on an MCFT-changed file the new build no longer
# has (resolve by hand, as _slide-cuttingdiagram-2d.twig was) and on an
# MCFT-own path the build now has. Nothing is committed: resolve the markers,
# rebuild the dialog bundle, run the checks, then `git commit`.
# ---------------------------------------------------------------------------
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: $0 <upstream build sha>" >&2; exit 2; }
cd "$(git rev-parse --show-toplevel)"
export GIT_LITERAL_PATHSPECS=1

NEW=$(git rev-parse --verify "$1^{commit}")
OLD=$(tr -d '[:space:]' < docs/mcft/UPSTREAM)
git rev-parse --verify -q "$OLD^{commit}" > /dev/null \
  || { echo "docs/mcft/UPSTREAM names $OLD, which is not in this repository (git fetch upstream)" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git ls-tree -r --name-only "$NEW" > "$tmp/new"
git ls-files > "$tmp/head"
ruby tools/mcft_paths.rb changed > "$tmp/changed"
ruby tools/mcft_paths.rb own > "$tmp/own"

# The stops come first, so a refusal leaves the tree exactly as it was.
stop=0
while IFS= read -r p; do
  if ! git cat-file -e "$NEW:$p" 2>/dev/null; then
    echo "STOP: MCFT changes $p, and $NEW no longer has it. Resolve by hand" >&2
    echo "      (keep or delete MCFT's version; move it between own:/changed: in docs/mcft/MCFT-PATHS)." >&2
    stop=1
  elif ! git cat-file -e "$OLD:$p" 2>/dev/null; then
    echo "STOP: $p is listed changed: but $OLD (docs/mcft/UPSTREAM) does not have it" >&2
    stop=1
  fi
done < "$tmp/changed"
# An own: path the build now carries. Directories are matched by prefix.
grep -vxF -f <(ruby tools/mcft_paths.rb upstream < "$tmp/new") "$tmp/new" \
  | grep -vxF -f "$tmp/changed" > "$tmp/clash" || true
if [ -s "$tmp/clash" ]; then
  sed 's/^/STOP: MCFT owns a path the build now has: /' "$tmp/clash" >&2
  stop=1
fi
[ "$stop" -eq 0 ] || exit 1

# 1. Take every non-MCFT path from the build.
ruby tools/mcft_paths.rb upstream < "$tmp/new" > "$tmp/take"
if [ -s "$tmp/take" ]; then
  tr '\n' '\0' < "$tmp/take" | git checkout "$NEW" --pathspec-from-file=- --pathspec-file-nul
fi
echo "taken from ${NEW:0:9}: $(wc -l < "$tmp/take") path(s)"

# 2. Remove what neither the build nor MCFT has.
ruby tools/mcft_paths.rb upstream < "$tmp/head" | grep -vxF -f "$tmp/new" > "$tmp/gone" || true
if [ -s "$tmp/gone" ]; then
  tr '\n' '\0' < "$tmp/gone" | git rm -q --pathspec-from-file=- --pathspec-file-nul
fi
echo "removed (not in the build, not MCFT's): $(wc -l < "$tmp/gone") path(s)"

# 3. Three-way merge each file MCFT changes.
conflicts=0
while IFS= read -r p; do
  git show "$OLD:$p" > "$tmp/base"
  git show "$NEW:$p" > "$tmp/other"
  if git merge-file -L "mcft (HEAD)" -L "upstream ${OLD:0:9}" -L "upstream ${NEW:0:9}" \
       "$p" "$tmp/base" "$tmp/other"; then
    git add -- "$p"
    echo "merged clean: $p"
  else
    n=$?
    [ "$n" -gt 0 ] && [ "$n" -lt 128 ] || { echo "git merge-file failed on $p ($n)" >&2; exit 1; }
    conflicts=$((conflicts + n))
    echo "CONFLICT ($n hunk(s)): $p"
  fi
done < "$tmp/changed"

# 4. Record which build the tree now equals.
echo "$NEW" > docs/mcft/UPSTREAM
git add docs/mcft/UPSTREAM
echo "docs/mcft/UPSTREAM: ${OLD:0:9} -> ${NEW:0:9}; $conflicts conflict hunk(s) left to resolve"
