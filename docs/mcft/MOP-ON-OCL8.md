# S3 MOP on OpenCutList 8 — the design of the move

Written 23 Nov 2026 on branch `mcft8` (cut from `origin/mcft` `6b0ba3e`), and
revised the same day after a critic's review: §10 lists every finding, how
it was checked, and what it changed. It is a plan, not a record of work
done: nothing below has been built yet, and nothing in it has been run in
SketchUp. SketchUp is not available where this was written. Every sentence
about how SketchUp or OpenCutList behaves comes from reading code, and where
it is an inference it says **NOT CONFIRMED**.

Labels used throughout:

- **RAN**: run in the cloud container (Ruby 3.3, Node 22) against throwaway
  copies of this repository.
- **SEEN**: read in the code or in git.
- **NOT CONFIRMED**: an inference that a Mac, or SketchUp, still has to prove.

Paths: `7:` means MOP on `origin/mcft` `6b0ba3e`, and `8:` means
`upstream/8.0.0` `c5405bd4` (the "+ LAB build" commit, `8.0.0-lab`, build
`202611191727`). Both are under `src/ladb_opencutlist/ruby/` unless the path
says otherwise.

---

## 0. Amit's words, and what they mean

Amit, 23 Nov 2026, answering "when should Claude move MOP onto OpenCutList 8?".
Claude had recommended waiting for a stable 8.0. He wrote:

> "i have already started using lab 8 and uninstalled 7.1. start using lab 8
> with know risk. it has lot of promising drawing feature which save a lot of
> time"

What this means, taken literally:

1. **The decision is made, and the risk is accepted.** MOP moves onto
   OpenCutList **8.0.0 LAB** now. It does not wait for a stable 8.0. A LAB
   build can break, and Amit has said he knows that. This document does not
   reopen the question. It keeps the risk small and easy to undo (§9).
2. **He wants both halves in one SketchUp:** 8's drawing tools (Smart Build,
   Smart Reshape / Stretch, Paneling, Boolean) AND the MCFT estimate. Both
   come from ONE extension, because MOP and OpenCutList share the plugin id
   `ladb_opencutlist` and cannot be installed side by side. So MOP-on-8 is
   OpenCutList 8 LAB with the MCFT code added. It replaces the stock 8 LAB he
   installed from its `.rbz`.
3. **Today he has no MCFT estimate in SketchUp at all.** MOP 7.1 is
   uninstalled. It was two symlinks from SketchUp's Plugins folder into
   `~/dev/malletcraft/mcft-opencutlist-sketchup-extension`. Whether
   Extension Manager's uninstall deleted files through those links into the
   clone is not known. This design does not depend on the answer, because the
   old clone is replaced (§6.4).
4. **"Restart is the deploy" must survive.** Claude pushes and Amit restarts
   SketchUp. He never runs `git pull`, never runs OpenCutList's own Upgrade,
   and never installs an `.rbz` (the standing rules in
   `mcft-erpnext-code/CLAUDE.md`: "NEVER TELL AMIT TO `git pull` THE PLUGIN",
   "NO FALLBACKS"). Moving to 8 changes how the dialog is built, and that
   would quietly break this rule (§6.1). Most of the work below exists to
   keep it.
5. **S1 MEST (the bench) is not touched.** It stays pull-only:
   "unless plugin changes touches my custom development for pull do not make
   any changes to bench". Every change below is on the plugin side. Where 8
   creates a difference the bench cannot see, MOP says so on screen. The
   bench is not taught about it.

---

## 1. The branch

### 1.1 The first move: MERGE upstream/8.0.0 into the mcft line

- **Work happens on `mcft8`**, in the worktree `/home/user/mop8`, cut from
  `origin/mcft` `6b0ba3e`. The worktree's hooks are active
  (`core.hooksPath .githooks`, SEEN); a fresh clone needs
  `git config core.hooksPath .githooks` before its first commit.
- **Bring 8 in by a merge, never by a rebase.** Amit's Mac updates by
  `git merge --ff-only origin/mcft`, so every new `mcft` must be a
  descendant of the old one. A merge commit is a descendant of both
  parents, so `mcft` → `mcft8` is a fast-forward. The 78 MCFT commits are
  not rewritten.
- **The merge records ancestry. It does not decide content.** It is made
  with `git merge --no-commit -s ours <build sha>`, so git's own three-way
  merge never decides what an upstream file contains. Its base here is a
  virtual one (§2.1), and after any "go back to an earlier build" commit it
  would be the bad build (§9.1). Both are wrong bases. The tree is made
  instead by `tools/mcft-take-upstream.sh <build sha>` (§2.2). Every path
  that is not MCFT's is taken from the build, byte for byte. Each upstream
  file that MCFT changes is three-way merged against the build the tree last
  equalled, which `docs/mcft/UPSTREAM` names. CI proves the result (§7.3,
  check 6). (RAN in a throwaway worktree: §2.1.)
- **Tag the last 7.1 MOP commit before anything moves:**
  `git tag -a mcft-7.1-final 6b0ba3e -m "Last MOP on OpenCutList 7.1"`.
  Push the tag before `mcft` moves. It is the way back (§9.2).
- **The order of the commits on `mcft8`.** Each commit does one thing, so a
  red check names its cause. All are local until §1.3.
  0. **P — the path list and the upstream pointer, still on 7.1.** It adds
     `docs/mcft/MCFT-PATHS`, and `docs/mcft/UPSTREAM` set to
     `d03f4548e161ed25615b2ea828214a79e0f3e07a`. That value is correct
     because `git diff --name-only d03f4548 origin/mcft` lists exactly the
     MCFT paths (§2.1, SEEN), so `origin/mcft` IS `d03f4548` plus MCFT. P
     also adds `tools/mcft-take-upstream.sh`, `tools/check-upstream-tree.rb`
     with its CI step, and `mcft8` to the workflow's push branches. P is
     pushed alone, first. The new check therefore goes green on the 7.1 tree
     before anything else moves.
  1. **M — the merge,** by the procedure of §1.2, steps 3–5. The extension
     must LOAD at this commit, so the `McftController` require lands here,
     not later. `js/templates/tabs-twig-templates.js` is still tracked at
     M. It is recompiled from 8's twig and staged, so 7.1's pre-commit hook
     passes without `--no-verify`; B untracks it. M sets `UPSTREAM` to
     `c5405bd4343a59a5988a5f8fa792d8d9ddf1e2e3` and drops
     `_slide-cuttingdiagram-2d.twig` from `MCFT-PATHS`.
  2. **D — delete the all-boards diagram print** (§2.4).
  3. **V — the version string** (§2.3).
  4. **B — track the dialog bundle.** This covers the `.gitignore`
     exception, the committed `tabs-bundle.js`, `build/package-lock.json`,
     untracking `tabs-twig-templates.js`, the pre-commit and pre-merge-commit
     hooks, and the CI job (§6.1, §7).
  5. **I — the installer, the output refresh and the autoupdater** (§6).
  6. **U — the upgrade refusal and its check** (§6.3, §7).
  7. **A — the assembly rule for groups, the payload shape, and the source
     of the "not counted" warning, with its check** (§4).
  8. **N — the on-screen notes** (§3, §4.3, §5).
  9. **C — the CI additions not already in P, B, U or A** (§7).
- **Every commit that adds or removes an MCFT path edits
  `docs/mcft/MCFT-PATHS` in the same commit.** M, D, B, I, U and C all do.
  Check 6 fails otherwise.
- **There must be no window in which `mcft` loads and shows stock 8's
  dialog.** M alone would do exactly that on a Mac (§6.1). So `mcft` is not
  fast-forwarded to any commit before B and I are in. It moves once, to the
  tip, when every check on the tip is green.

### 1.2 Every later LAB build

OpenCutList publishes LAB builds two to four times a week. Each one is a
commit titled "+ LAB build" on `upstream/8.0.0` (`c5405bd`, `4d5949a`,
`bfc7630`, …). That commit carries the new `dist/ladb_opencutlist.rbz`, and
its `constants.rb` together with it (SEEN). Commits between builds change
the source without changing the rbz, and those two must never disagree on a
Mac (§6.2). So the procedure is:

1. `git fetch upstream`.
2. Pick the newest "+ LAB build" commit on `upstream/8.0.0`, and call its
   full sha `B`. Never pick the branch tip if the tip is not a build commit.
3. On `mcft8`, run `git merge --no-commit -s ours $B`. This records `B` as
   the second parent and changes nothing in the tree.
4. Run `tools/mcft-take-upstream.sh $B`. It reads the old build from
   `docs/mcft/UPSTREAM` and the MCFT paths from `docs/mcft/MCFT-PATHS`.
   Then, in order:
   - it checks out from `B` every path `B` has that is not MCFT's;
   - it runs `git rm` on every path HEAD has that is neither in `B` nor
     MCFT's;
   - for each upstream file that MCFT changes, it runs `git merge-file` with
     HEAD's version (MCFT's) as the current side, the old build's version as
     the base, and `B`'s version as the other side, and leaves conflict
     markers where they clash;
   - it writes `B` into `docs/mcft/UPSTREAM`.

   It stops and names the path in two cases. The first is an MCFT-changed
   file that is absent from `B`, because 8 deleted it; that is resolved by
   hand, as `_slide-cuttingdiagram-2d.twig` was. The second is an MCFT-own
   path that appears in `B`.
5. Resolve the conflict markers. In practice they are only in the files
   MCFT changes (§2.2). Keep MCFT's version and name, and take 8's build
   string (§2.3).
6. **The lockfile, and only when `B` changed `build/package.json`:** run
   `cd build && npm install --package-lock-only`. Never do this otherwise. A
   lockfile regenerated on every merge puts the registry's mood back into
   the build (§6.1).
7. **Rebuild the one committed output:** run `cd build && npm ci && npx
   gulp twig_compile`, then `npx gulp js_bundle_tabs`. These are two separate
   invocations (§6.1). **Never run `gulp bundle`.** It also builds the CSS
   bundle, whose inputs are not in git, and so it fails on a clean checkout
   (RAN).
8. Run `git add` on the bundle (and the lockfile), run every check in
   `mcft-checks.yml` locally, then run `git commit`. The merge, its bundle,
   its lockfile and its `UPSTREAM` land in ONE commit, and the pre-commit
   hook runs on it. A merge that git would commit by itself is refused by
   `.githooks/pre-merge-commit` (§7.2). That is what holds the procedure to
   `--no-commit`.
9. Push `mcft8`. Wait until **every workflow run on the full 40-character
   sha** is green. Then fast-forward `mcft` to it and push.
10. Amit restarts SketchUp. The autoupdater checks the clone, gates the
    commit on CI, fast-forwards it, and refreshes the build outputs from the
    new rbz (§6.2).

**Going back to an earlier build** (a bad LAB build, §9.1) uses the same
script with no merge. Run `tools/mcft-take-upstream.sh <good build sha>` on
top of the bad merge, then steps 5–9 with a plain `git commit`. The script
takes content from the build it is given and never from git's merge base.
So the NEXT merge brings everything the newer build has, including what the
bad build introduced and the go-back took out. A plain `git merge` after a
go-back would silently leave those changes out. That is why no merge on this
line is ever a plain one.

**When to merge:** Claude merges when Amit asks for a build, or when a LAB
build fixes something that is in his way. There is no fixed cadence. A merge
that no one asked for is a risk for nothing.

**What is never used:** OpenCutList 8's own updater, and its Upgrade button.
MOP refuses that button (§6.3).

**When stable 8.0 is published,** the same procedure merges its tag. The
update check is left on for exactly this reason (§6.3): the orange dot it
shows is the signal for Claude to move MOP onto stable.

### 1.3 Pushing

- **First, upstream's history goes to `origin` in pieces.** Without this,
  the first push of `mcft8` after M would send all of upstream 8's history
  at once. That is 1,570 commits that are not on origin, and
  `git rev-list --disk-usage --objects upstream/8.0.0 --not --remotes=origin`
  gives 1,721,149,389 bytes (RAN). Almost all of it is 233 versions of the
  rbz. GitHub refuses any single push over 2 GB, and the container's agent
  proxy can cut off a long transfer. So, before M is pushed:
  - Walk `git rev-list --first-parent --reverse upstream/8.0.0 --not
    --remotes=origin`. Push the furthest commit `c` whose
    `git rev-list --disk-usage --objects $c --not --remotes=origin` is under
    400 MB, with `git push origin $c:refs/heads/upstream-8.0.0`. Fetch
    origin, and repeat.
  - The cumulative sizes along that history (RAN) are:

    | first-parent commit | 200 | 400 | 600 | 800 | 1,000 | 1,200 | 1,367 (tip) |
    |---|---|---|---|---|---|---|---|
    | size | 99 MB | 251 MB | 514 MB | 641 MB | 944 MB | 1.3 GB | 1.72 GB |

    That makes about six pushes.
  - The steps are chosen by size, not by "+ LAB build" commits. Only 12 of
    the 1,570 commits carry that title, which is too coarse to give even
    pieces.
  - `disk-usage` measures the size of those objects in the local pack. The
    pack that a push builds is computed afresh and can differ. Each step
    stays far enough under the limit that the difference cannot matter.
  - Nothing runs on that branch. Upstream's two workflows are
    `workflow_dispatch` only (SEEN), and `MCFT checks` triggers on `mcft`
    and `mcft8` only.
  - It is safe for the Mac. The old stub fetches `origin mcft` only (SEEN in
    `tools/dev-install-mac.sh`), and step 1 of §6.4 removes that stub
    anyway.
  - Afterwards, `git rev-list --disk-usage --objects mcft8 --not
    --remotes=origin` must be a few MB before `mcft8` is pushed. That is
    the MCFT commits after P, the merge and the bundle.
- **After that, `mcft8` may be pushed freely.** It is not a branch the Mac
  fetches, and CI runs on it from P (§7). This is where a red build costs
  nothing.
- `mcft` is fast-forwarded only to a commit that is fully green. It is
  pushed only after Amit has done step 1 of §6.4. Otherwise the old startup
  stub on his Mac would download about 1.7 GB of history into the old clone
  the next time SketchUp starts (§6.2, "Size").

---

## 2. Every MCFT change, carried to 8, file by file

### 2.1 What the MCFT work is

- **The MCFT work is `d03f4548..origin/mcft`:** 78 commits, 35 files outside
  `node_modules`, +7,732/−591. `d03f4548` is upstream master past 7.1.0.
  (SEEN)
- **`git diff --name-only d03f4548 origin/mcft` lists exactly the MCFT
  paths:** those files, plus the 1,832 files tracked under the root
  `node_modules/` (SEEN). Nine of the files are upstream files that MCFT
  changed. 8 deleted one of them, `_slide-cuttingdiagram-2d.twig`. The rest
  are MCFT's own. So `origin/mcft` is `d03f4548` plus MCFT, and that makes
  `d03f4548` the right base for P's `UPSTREAM`.
- **`git merge-base --all origin/mcft upstream/8.0.0` returns TWO bases,**
  `0e27407d` (7.1.0) and `d84715d0` (7.0.0). Git therefore merges through a
  virtual base, and that produces conflicts in files MCFT never touched.
- **The control:** with git's own merge, merging bare upstream master
  `d03f4548` into 8.0.0 gives 63 conflicts, and merging `origin/mcft` gives
  64. The extra one is MCFT's `_slide-cuttingdiagram-2d.twig`. (RAN)
- **When the 78 commits were replayed onto 8** in a throwaway copy, 72
  applied cleanly and 6 clashed.
- **With `-s ours` and the script, the same move gives a clean answer**
  (RAN, in a throwaway worktree of `origin/mcft` merging `c5405bd4`):
  - 1,108 paths were taken from 8.
  - 75 paths were removed. These are 7.1 files that 8 deleted,
    `_slide-cuttingdiagram-2d.twig` among them.
  - The 8 MCFT-changed files that 8 still has were three-way merged against
    `d03f4548`. `_slide-estimate.twig` and `tab.twig` merged clean. The
    other six conflict, in 8 hunks: `.gitignore` 2, `plugin.rb` 2, the
    loader 1, `constants.rb` 1, `build/package.json` 1, `tab-cutlist.js` 1.
  - Afterwards, `git diff --name-only upstream/8.0.0` lists the 34 MCFT
    paths and `node_modules/`, and nothing else. The 34 are 26 MCFT-own
    paths outside `node_modules` and the 8 changed files.
  - The 57 conflicts in files MCFT never touched do not occur.

### 2.2 The table

| File | What 8 did to it | What it becomes on 8 |
|---|---|---|
| `ruby/worker/mcft/mcft_estimate_worker.rb` | absent in 8, MCFT-own | Unchanged, except the assembly walk and the payload (§4), the notes (§3, §5), and `is_rbz` in the stamp (§2.3). Every OpenCutList name it calls still exists in 8 with the same shape (§2.5). |
| `ruby/worker/mcft/mcft_estimate_dialog.rb`, `mcft_estimate_store.rb`, `mcft_pull_worker.rb`, `mcft_create_materials_worker.rb`, `mcft_iso_worker.rb` | absent, MCFT-own | Unchanged. |
| `ruby/worker/mcft/mcft_push_worker.rb` | absent, MCFT-own | Unchanged. It is still SUSPENDED and still guarded. The estimate keeps borrowing `parts_csv`, `ocl_totals` and `plugin_rev` from it. |
| `ruby/worker/mcft/mcft_log.rb` | absent, MCFT-own | Unchanged. It has no OpenCutList dependency. |
| `ruby/controller/mcft_controller.rb` | absent, MCFT-own | Unchanged. Its wiring in `plugin.rb` is redone (row below). |
| `ruby/plugin.rb` | heavily changed (+549/−189): controllers load lazily inside `start()`, a new `Updater` class, a new menu loop. 2 conflict hunks under `merge-file` (RAN). | Take 8's side in each conflict. Then re-place MCFT's three hunks. **(1)** Add `require_relative 'controller/mcft_controller'` inside 8's lazy block (8:1167-1180), and `@controllers.push(McftController.new)` after `HardwareController`. **(2)** The menu hunk `McftController.new.setup_menu(submenu)` lands in 8's `setup()` (8:1074-1077). But `setup()` runs at load time, BEFORE `start()` has required anything, so it needs its own `require_relative 'controller/mcft_controller'` on the line just above it. That is 8's own pattern for the smart tools (8:1060). Without that line, a `NameError` stops the whole extension at load, and CI as it stands stays green (§7.3, check 3). **(3)** The upgrade refusal goes at the top of 8's `upgrade_command` (8:1695) (§6.3). **Also:** drop MCFT's old top-level requires. 7.1's `importer_controller` no longer exists in 8. |
| `src/ladb_opencutlist.rb` (the loader) | +13/−8. 1 conflict hunk (RAN). | 8's file, with three MCFT additions: the name `OpenCutList (MCFT Edition)`; the version line with MCFT's private `##` marker, so gulp's `version` task never rewrites it; and the SketchUp 2021 floor, `Sketchup.version_number < 2100000000` (8 gates only at 2017). |
| `ruby/constants.rb` | version `8.0.0-lab`, build `202611191727`, languages `bg`/`ro` added and `ar`/`sr` removed. 1 conflict hunk (RAN). | 8's file with `EXTENSION_NAME 'OpenCutList (MCFT Edition)'` and the MCFT version (§2.3). **`EXTENSION_BUILD` stays upstream's, byte for byte** (§2.3). |
| `js/plugins/tabs/jquery.ladb.tab-cutlist.js` | +227/−1,227. ONE conflict hunk under `merge-file` against `d03f4548` (RAN): the legacy 1D/2D block that 8 deleted, which holds MCFT's pack hunk (7:6886-7028). | Take 8's side in that hunk, then delete the rest of the pack (§2.4). Everything else merges clean. That includes 8's four hunks (`$selectRectangleLeftoverMode`, the `use_pre_process`/`write_*` inputs, `SELECT_PICKER_TABS_OPTIONS`, a semicolon), which conflicted only under git's virtual base. It also includes MCFT's: the menu-item handle (7:61, 185), the 1,332-line estimate block (7:1351-2682), the hook into the estimate slide (7:2725-2743, which lands inside 8's `generateEstimate` → `fnCreateSlide`), and the `mcft_estimate_ready` / `mcft_materials_created` callbacks (7:8098-8107). |
| `twig/tabs/cutlist/_slide-cuttingdiagram-2d.twig` | deleted by 8 (`ec4deb0f`), and MCFT-changed | The script stops on it (§1.2, step 4). It is removed with `git rm` and dropped from `MCFT-PATHS` in M. |
| `twig/tabs/cutlist/_cuttingdiagram-2d-body.twig`, `_slide-mcft-diagram-pack.twig` | absent, MCFT-own, but dead on 8: they render the deleted engine's `sheets` and 41 `tab.cutlist.cuttingdiagram.*` keys that 8 no longer has | Deleted in D (§2.4). |
| `twig/tabs/cutlist/_slide-estimate.twig` | 3 button-label lines changed. Merges clean (RAN). | As merged. |
| `twig/tabs/cutlist/tab.twig` | unchanged in 8. Merges clean (RAN). | The "Cutting diagrams — all boards" item is removed (§2.4). |
| `js/templates/tabs-twig-templates.js` (a tracked build output on 7.1) | not tracked upstream | Tracked at M, recompiled from 8's twig. **No longer tracked from B.** On 8 it is only an input to `tabs-bundle.js`, and nothing loads it by itself. One delivered output, not two (§6.1). |
| `js/bundles/tabs-bundle.js` (8's build output) | new in 8, and gitignored | **Tracked on `mcft` from B**, through the exception in the `.gitignore` row. |
| `.gitignore` | changed. 2 conflict hunks under `merge-file` (RAN). | **At M:** 8's lines plus MCFT's (7.1's templates exception, `extension_info.txt`, `*.susig`). 8's `*~.skp` covers MCFT's `/docs/skp/*~.skp`. **At B:** 8's `/src/ladb_opencutlist/js/bundles/` becomes `/src/ladb_opencutlist/js/bundles/*` followed by `!/src/ladb_opencutlist/js/bundles/tabs-bundle.js`. Git cannot re-include a file whose parent DIRECTORY is excluded, so a `!` line after 8's own line is silently ignored. (RAN in a scratch repo: `git add src` skipped the file, and `git check-ignore -v` named the directory line. With `/*`, the file went in.) This is 7.1's templates shape again. Also at B: `js/templates/` is ignored whole, and 7.1's exception goes; `!/build/package-lock.json` is added after 8's `/build/package-lock.json`, which works because that line names a file; and `/src/ladb_opencutlist/.mcft-outputs` is added. 8 ignores `CLAUDE.md`, so a CLAUDE.md in this repo needs `git add -f`. |
| `build/package.json` | version and dependency bumps. 1 conflict hunk (RAN). | 8's file, with `"jsdom": "^30.0.1"` re-added (the smoke test needs it). |
| `build/package-lock.json` | gitignored in both 7 and 8 | **Tracked on `mcft` from B** (§6.1). |
| `docs/mcft/UPSTREAM`, `docs/mcft/MCFT-PATHS`, `tools/mcft-take-upstream.sh`, `tools/check-upstream-tree.rb` | — | New in P (below, and §7.3 check 6). |
| `tools/check-*.rb` (7), `.githooks/pre-commit`, `.github/workflows/mcft-checks.yml`, `test/smoke/*`, root `package.json` / `package-lock.json` / `node_modules/` (1,832 tracked files) | absent, MCFT-own | Kept, with the changes in §7. The smoke test's diagram-pack block is deleted together with the pack. |
| `tools/dev-install-mac.sh` | absent, MCFT-own | Rewritten (§6.2). |
| Translations | MCFT added none. Its strings are hard-coded English. | Nothing to carry. |

**The path list.** `docs/mcft/MCFT-PATHS` holds two lists, one path per
line.

- **`own:`** holds the paths MCFT adds. Each must exist at HEAD and be absent
  at the build. A line ending in `/` is a directory, and every file under it
  is MCFT's: `src/ladb_opencutlist/ruby/worker/mcft/`, `test/smoke/`,
  `node_modules/`, `.githooks/`, `docs/mcft/`. Every other entry is a single
  file. `tools/` is not a prefix, because upstream has files there too.
- **`changed:`** holds the upstream files MCFT edits. Each must exist at HEAD
  and at the build. At M these are the 8 files of §2.1.

**Why the script, and not git's merge.** Upstream master equals 7.1.0
everywhere except 5 files (the make-c-libs workflow split, CHANGELOG, the
rbz, `docs/json/tutorials.json`), and 8.0.0 already supersedes all 5. So
taking 8 for every non-MCFT path is right (SEEN). Git's merge reaches that
answer only after 57 conflicts in kuix, the manipulators, the smart tools,
Packy, css/woff, the make-c-libs workflows, CHANGELOG, the rbz and four
modify/delete files. Worse, after a go-back commit it reaches a wrong
answer, silently (§9.1). The script reaches the right answer directly,
whatever the merge base is.

**What proves it is CI, not a commit message.** Check 6
(`tools/check-upstream-tree.rb`, §7.3) runs on every push. It asserts that
every path outside `MCFT-PATHS` is the build's, byte for byte, and that no
other path exists.

### 2.3 The version string, and the build string

- **Version: `8.0.0-lab.mcft.1`**, and the same string on the loader's `ex.version`
  line. It ends in a digit ON PURPOSE.
  - 8 sets `IS_LAB = EXTENSION_VERSION =~ /-[a-z]+\z/` (8 `plugin.rb:27`).
    So a string such as `8.0.0-mcft` or `-mcftlab` would make `IS_LAB` true.
  - With `IS_LAB` true, `plugin.rb:1155`, `SKETCHUP_CONSOLE.clear if IS_LAB`,
    would wipe the `[MCFT] OpenCutList (MCFT Edition) up to date @ <rev>`
    line that the startup stub prints just before. That line is the first
    diagnostic the house rules name.
  - With `IS_LAB` true, the dialog would also read the LAB manifest and show
    the orange Upgrade dot every LAB week.
- **What `IS_LAB` false costs (SEEN, every use read in 8):**
  - The stable manifest is read, so there is no dot until stable 8.0 is
    published.
  - The `zz` debug languages are hidden.
  - The docs, tutorials and changelog links point at the stable pages, not
    the LAB ones.
  - The Settings tab's "Debug" preset dump is hidden.
  - The dialog title and the upgrade modal do not print the build number.
  - **No tool or feature of 8 is gated on `IS_LAB`.** Smart Build, Smart
    Reshape, Paneling and Boolean are all present either way.
- **`IS_RBZ`, unlike `IS_LAB`, DOES gate behaviour** (SEEN, every use read in
  8). 8 sets `IS_RBZ = PLUGIN_DIR.start_with?(<Plugins folder>)`
  (8 `plugin.rb:26`). When it is true:
  - Smart Join is left out of the menu unless SketchUp runs in debug mode
    (`plugin.rb:103`).
  - The packing engine's time limit is fixed at 300 s
    (`cutlist_packing_worker.rb:289`).
  - The native libraries are copied to a temp folder before loading
    (`lib/fiddle/wrapper.rb:72`).
  - The dialog's local server sends `Cache-Control: public, max-age=…`
    instead of `no-cache` (`server/local_http_server.rb:381`).
  - `setup()` discards leftover `*.upgrade_backup` paths (`plugin.rb:1014`),
    and the refused Upgrade would back up first (`:1714`).
  - The build tag in the docs and news URLs says `rbz` instead of `src`
    (`:464`, `abstract-dialog.js:546`). Two uses also need `IS_LAB`, so with
    `IS_LAB` false they come out the same either way: the highlighted
    bug-report link (`layout-tabs.twig:48`), and the cut list's `isDebug`
    (`tab-cutlist.js:2748`).
- **What `IS_RBZ` will be for MOP is NOT CONFIRMED** (§6.3). It is true if
  the loader's `__FILE__` is the link path in Plugins, and false if SketchUp
  hands Ruby the resolved path. True is expected, and it is what stock 8 LAB
  gives Amit today. False would bring Smart Join into the menu and lift the
  300 s limit, so the menus and timings would differ from what he has been
  using.
- **So the estimate's stamp, which runs every time, prints it:**
  `[MCFT] estimate — plugin <rev> is_rbz=<true|false> is_lab=<true|false>`
  (estimate worker `:174`). §6.4 step 6 reads it through the bridge.
  `is_lab` rides along because it proves this section's version reasoning on
  the Mac for nothing.
- **The `.mcft.N` suffix increases with each MCFT release made on one
  upstream build.** When a new LAB build is merged, the number stays where it
  is. The build string is what identifies the upstream build.
- **`EXTENSION_BUILD` is never changed from upstream's.**
  - The dialog's JS `common-bundle.js` comes from the rbz, and it carries
    `js/constants.js` with upstream's build.
  - When the Ruby build and the JS build differ, the dialog locks itself into
    upstream's "zzz" layout (8 `jquery.ladb.dialog-tabs.js:801-816`, SEEN).
  - 7.1 MOP already follows this rule (`202511301621`). CI enforces it
    (§7.3, checks 2 and 6).

### 2.4 The all-boards diagram print: TAKEN OUT, code deleted

On 7.1, "Cutting diagrams — all boards" printed every sheet-good group's 2D
diagram in one pack. It was built on `cutlist_group_cuttingdiagram2d_start`
and `_advance`. **8 deleted that engine.** Neither command exists in 8. The
legacy 2D slide and its i18n keys are gone too (SEEN).

**Rebuilding it on 8's packing engine is NOT a contained change**, so it is
not rebuilt. Here is what a rebuild would take (SEEN unless noted):

1. `CutlistPackingWorker` (8 `cutlist_packing_worker.rb:224`) takes PART IDS,
   not a group. The pack would have to gather each group's visible part ids
   the way 8's JS does (`grabVisiblePartIdsWithContext`). Then, for each
   group, it would start a run and poll `_advance` every 250 ms. The groups
   would have to run one after another, because the controller keeps a
   single `@packing_worker`.
2. Its bins come only from the preset's `std_bin_2d_sizes`. An empty value
   gives no standard boards at all. How 8's own modal fills that value is
   NOT CONFIRMED.
3. `time_limit` is forced to 300 s whenever `IS_RBZ` is true (`:289`).
   `IS_RBZ` is expected to be true on Amit's Mac (§2.3, NOT CONFIRMED). If
   it is, a pack would take minutes, not seconds (inferred, not run).
4. The results render in `_slide-packing.twig`, 419 lines in one piece. A
   print slide means one of two things: a new MCFT hunk splitting that
   upstream file into a partial, which conflicts on every LAB merge; or
   MCFT's own markup against 8's `solution` object, which drifts from 8 on
   every LAB build.
5. The smoke test would have to be rewritten against the packing commands.

That is a new feature built on a LAB engine that is still moving. A half
version of it (a menu item that is slow, or that fails on a group with no
board sizes) is the "half-working button" this move must not ship.

**What is deleted** (commit D, after the merge):

- `twig/tabs/cutlist/_cuttingdiagram-2d-body.twig` and
  `_slide-mcft-diagram-pack.twig`, together with their `MCFT-PATHS` lines.
- The menu item in `twig/tabs/cutlist/tab.twig`.
- In `tab-cutlist.js`: `$itemMcftDiagramPack` (7:61, 185), its click handler
  (7:8027-8031), and whatever of `mcftDiagramPack` / `mcftShowDiagramPack`
  the merge left behind.
- The smoke test's diagram-pack block, which failed 4 checks in the trial
  (RAN).
- After the deletion, `git grep -n -i "diagrampack\|diagram-pack\|cuttingdiagram2d"
  -- src test tools` must return nothing.

**What Amit is told:** on MOP-on-8, every board prints from OpenCutList 8's
own Packing slide, one group at a time. The all-boards print has gone, and
nothing stands in its place. If he wants it back, it is a new piece of work,
built once 8's packing engine is stable.

### 2.5 Every OpenCutList name MOP calls, 7.1 against 8 (SEEN)

All of them still exist in 8, and all keep their shape except where a row
says otherwise.

- **`CutlistGenerateWorker.new(part_folding:, active_entity:, active_path:,
  hidden_group_ids:)`**: 7 `cutlist_generate_worker.rb:32`, 8 `:42`.
  - 8 adds `names_filter:` and `+`/`−` tags-filter semantics. MOP passes
    neither.
  - Called at estimate `:181` and push `:80`, `:103`.
- **`LayerVisibilityHelper`**: the same blob `1f0dccf9` on both;
  `_layer_visible?(layer, from_root=false)` at `:14`.
  - The cut list's own visibility gate moved from 7 `:929/:986` to 8
    `:1120/:1199`.
  - MOP uses the helper at estimate `:38/:421`, push `:24/:136` and iso
    `:22/:70`.
- **`Cutlist#errors` and `#groups`**: `cutlist.rb:11` on both.
- **`Group`** (`id`, `material_type`, `material_name`, `std_thickness`,
  `parts`, `total_cutting_volume`) and **`group.def`**: present on both
  (8 `group.rb:13-25`). `GroupDef#total_cutting_volume` uses the same
  formula (7 `:707`, 8 `:746`).
- **`Part`** (`name`, `count`, `length`, `width`, `thickness`, `tags`,
  `edge_material_names`, `face_material_names`): 8 `part.rb:14-26`.
- **`MaterialAttributes`**:
  - Types 1–6 are unchanged. 8 adds `TYPE_MACHINING = 7` (§3.3).
  - `initialize` gains an optional `defaults_type = nil`.
  - MOP's `_material_type_name` (push `:374`) maps types 1–5.
- **`Controller`, `register_command`, `add_event_callback`, `trigger_event`,
  `core_get_model_preset`**: unchanged in shape. Only their line numbers
  moved.
- **`PLUGIN.get_attribute(entity, key)`**: reads the `ladb_opencutlist`
  dictionary (8 `plugin.rb:572`). §4.3 uses it for `stretch_cutters`.
- **Dialog JS**: unchanged in shape.
  - `rubyCallCommand`, `addEventCallback`, `pushNewSlide`, `popSlide`,
    `print`.
  - `startProgress`, `incProgress`, `finishProgress`, `notifyErrors`,
    `setupTooltips`.
  - The tab fields MOP reads (`generateOptions.hidden_group_ids`,
    `dimension_column_order_strategy`, `cutlistTitle`, `filename`,
    `modelName`, `pageName`, `lengthUnit`, `groups`).
- **Gone:** only the diagram pack's commands and keys (§2.4).

---

## 3. The numbers on 8, and what MOP does about each difference

MOP sends `estimate_preview` these things (SEEN, estimate worker `:210-246`):

- a parts CSV with one row per OpenCutList part, carrying each part's
  FINISHED length and width, the board thickness for sheet goods, the edge
  and face material names, and a `Tags` column;
- the assembly count from its own walk, and the size map when there is one
  (§4.3);
- `lumber_stock`.

`ocl_totals` stays on the plugin.

The bench nests the sheets itself. It takes laminate from the face columns
and edge metres from length × width × qty. Hardware is the summed Quantity
column.

The same model can give different figures on 8 in these places.

### 3.1 Per-part cutting allowance

**What 8 does (SEEN):**

- A component definition can now carry its OWN length, width and thickness
  increase. 8 adds it to the material's (8 `cutlist_generate_worker.rb:418-421`).
  7 used the material's alone.
- The type sanitiser keeps all three for Solid Wood. It zeroes thickness for
  Sheet Good, zeroes width and thickness for Dimensional, and zeroes all three
  for Undefined and Hardware.
- `total_cutting_volume` still sums the cutting sizes. So on 8,
  `lumber_stock.bought_mm3` grows by any per-part allowance.
- A solid-wood thickness increase also enters the nearest-highest
  standard-thickness search. It can move a part up to the next board.

**For timber: KEEP IT, and do nothing.** The rule "ALL TIMBER PRICES BY
OPENCUTLIST'S CUTTING VOLUME" makes this exactly OpenCutList's own statement
of what must be bought. "WASTAGE AND CONSUMED ARE MOP'S" makes it MOP's to
send.

- The bench takes `bought_mm3` as given.
- It computes the used side from the finished sizes.
- So nothing counts twice.

The same model can price timber higher on 8 than on 7.1, and that is the
correct direction.

**For sheet goods: SAY IT.**

- MOP sends finished sizes, so a per-part length or width increase on a
  sheet part never reaches the bench's nest. OpenCutList 8's own Packing
  diagram does include it.
- Do NOT send the cutting size instead. The same Length and Width columns
  drive the edge metres, and OpenCutList itself bands the FINISHED length
  (8 `:691`).
- Ply is decided by the bench (the deliberate exception recorded in
  `mcft-erpnext-code/CLAUDE.md`). So MOP reports it on the estimate slide,
  plugin-side only:

  > **N1:** "OpenCutList cuts these sheet parts larger than ERP nests them:
  > <part names> (length +x mm / width +y mm)."

  The list is the parts of sheet-good groups with
  `Part#length_increased` / `width_increased` (8 `part.rb:72-77`). The note
  is shown only when the list is not empty.
- Whether ply should honour the allowance is a question for Amit, raised
  only if N1 ever fires on a real model.

### 3.2 Hardware: a painted component, or a named group, is ONE part

**What 8 does (SEEN):** a ComponentInstance, or a NAMED group, whose
instance is painted with a Hardware material is one part, and nothing inside
it is walked (8 `:1135-1151`; the bounds helper `:27` excludes it too). 7
always walked into the children.

**What it does to MOP's numbers:**

- **Leaf hardware** (faces directly inside, the instance painted `HWD_`)
  gives the same part and the same Qty on 7 and on 8. Amit's 3 Sep report
  has that shape (`HWD_AH_SC_0` Qty 5, `HWD_DR_SC_550mm` 2). So his current
  hardware is very likely unchanged (an inference, NOT CONFIRMED).
- **A painted component that has sub-components inside it:**
  - 7 made one part per child, named after the child.
  - 8 makes one part named after the parent. The parent is the packet, which
    matches the per-packet hardware rule.
  - The designation the bench keys rates on can still change.
- **A NAMED group painted `HWD_` inside a door:**
  - 7 made no part of it, and its faces were folded into the door's bounds,
    so the door measured larger.
  - 8 makes it a hardware row, and the door shrinks to its real size. That
    can change a nest input.
- **Anything made of sheet material inside a hardware-painted container
  vanishes from the cut list on 8.** 8's new Paint "Dropup" paints parent
  containers (CHANGELOG 2026-11-08), so one mis-applied Dropup on a door
  could turn the door into a hardware row (NOT CONFIRMED).

**The comparison between plugin and bench still agrees on 8.** Both sides
come from the same 8 cut list: `ocl_totals` sums `part.count`, and the bench
sums Quantity. Only 7.1 against 8, on the same model, can differ.

**What MOP does: ACCEPT 8's rule.** "Respect native cut list part
generation" is Amit's own instruction. Patching OpenCutList's core walk
inside MOP would make a second answer to a question with one.

**One check, on the Mac, after the move:** open one PB4 carcass that Amit
has already estimated on 7.1 and compare its Hardware table on 8 with the
7.1 figures he has. Whether PB4's post members carry an instance `HWD_`
material is NOT CONFIRMED. The catalogue's Material column is blank.

### 3.3 Machining: excluded upstream, and it never reaches MOP

**What 8 does (SEEN):** 8's `_fetch_useful_instance_infos` returns 0 for any
Group or ComponentInstance whose INSTANCE material is of `TYPE_MACHINING` (7)
(8 `cutlist_generate_worker.rb:1132-1133`). It does this before any part or
group exists, and before the entity's children are walked. So the container,
and everything inside it, never reaches the cut list, and never reaches
MOP.

The earlier version of this section said MOP's skipped-group warning
(push `:216-222`) would name such a group. It cannot. That warning names
cut-list GROUPS whose material type MOP's map does not know, and here no
group ever forms.

**What that means:**

- Boolean's cutters are machining-painted, and they are not material, so
  excluding them is right.
- A real panel painted with a machining material by mistake, or a container
  of parts painted so (one mis-applied Paint Dropup), drops out of the
  estimate with nothing said. That is the same shape as §3.2's hardware
  containers.

**Decision: ACCEPT it, as for hardware.** Cutters are not material. "Respect
native cut list part generation" applies here too, and detecting it inside
MOP would mean re-walking the model by a rule of MOP's own: a second answer.

**One check, on the Mac** (§6.4 step 6): after a Boolean cut, the cut panel
must still appear in the parts list and in the estimate.

### 3.4 What does NOT change (SEEN)

- **Grain continuity.** It adds `grain_groups`, which only Packy reads.
  Parts, counts and sizes are untouched.
- **Edge detection and edge length.** Edge length is still the finished
  length.
- **`std_thickness`**, the group-id formula (so hidden-group ids still
  filter), and the scope rule (selection, else `active_entities`).
- **The type names.** 8 relabels type 3 "Board", but MOP writes its own
  names, so the bench still sees "Dimensional".
- **8's EstimateWorker changes.** MOP never calls OpenCutList's own
  EstimateWorker.
- **The sheet count.** 8's own Packing diagram can disagree with the bench's
  sheet count. That is information, not an error. The bench's
  `nesting.pack_sheets` stays the authority for ply, as today.

---

## 4. The assembly rule, extended to Smart Build modules

### 4.1 What happens today on an 8 model

- **A Smart Build module is a GROUP** in `active_entities`, with no wrapping
  component (SB `:2023-2024`).
  - Its instance name is always set, to the library file's basename
    (SB `:2063`).
  - Saving to My Library proposes the definition name as the file name. So a
    component `ASMBL_M_WAR`, once saved and placed, comes back as a GROUP
    named `ASMBL_M_WAR`.
  - The group's definition is SketchUp's `Group#n`.
  - The group's definition carries `stretch_cutters` in the
    `ladb_opencutlist` dictionary (SB `:2066`).
- **MOP's walk** (`_assembly_counts`, estimate worker `:382-460`) starts with
  `next unless e.is_a?(Sketchup::ComponentInstance)`. That line runs before
  the visibility test and before the "ignored" list. So a module named
  `ASMBL_M_…` is dropped SILENTLY, and is not even listed as ignored.

**A correction to the earlier report:** the result is NOT zero labour.

- MOP sends every size as 0.
- The bench's `apply_assembly_count` returns early on 0
  (`estimate_pdf.py:236-237`).
- So ERP's own rule stands for the seven steps that follow the assembly
  count: 1 + drawer rails.

**But the badge says the plugin counted. The bench already has the right
label for this case, and MOP never reaches it** (SEEN, `mallet_estimator`
`main`, `api.py:1429-1457`):

- The `if assembly_counts:` branch sets `plugin:ASMBL size counts` whenever
  the map is non-empty.
- MOP always sends a non-empty map: the sizes, plus `top_level`, `ignored`,
  `scope`, `scope_size` and `hidden_skipped` (estimate worker `:221-222`,
  `:441-453`).
- Only when `assembly_counts` is absent and `assembly_count` is 0 does the
  bench say `erp:1 + drawer rails (no ASMBL component in model)`. That is
  the case its own comment was written for: "So zero falls through to the
  ERP rule and SAYS it did."
- The slide prints that source on the assembly line
  (`tab-cutlist.js:1609-1617`). Beside a note saying that ERP priced the
  steps, that would be two answers on one screen.
- The same mislabel happens on 7.1 today, for any model with no ASMBL
  component.

The fix is on the plugin side and touches no bench code: MOP sends no size
map when it counted nothing (§4.3). That is not "something new" for the pull
endpoint to return. It is the plugin sending less.

### 4.2 The rule

> **An assembly is an entity AT THE TOP of the scope being estimated, VISIBLE
> by OpenCutList's own test, whose name carries an ASMBL size token. For a
> COMPONENT the name is its instance name or its definition name. For a GROUP
> the name is its instance name only.**
> `ROOT_ASSEMBLY_RE` is unchanged, and the size token (L, M or S) is still
> required. Depth is still the qualifier: nothing below the top of the scope
> is ever examined.

What follows from the rule:

- A group `ASMBL_L_*` that holds a component `ASMBL_M_side` counts once, as L.
- A component assembly that holds a Smart Build group counts once.
- Dividers, fronts, backs and Paneling parts sit inside their container, so
  the walk never reaches them.
- A loose "Part" at the top does not match the regex.
- Nothing is counted twice.
- A group's DEFINITION name is never read. It is SketchUp's `Group#n`, which
  nobody sees and nobody chose.
- Hidden groups are skipped by the same `e.visible? &&
  _layer_visible?(e.layer, true)` test that components already pass.
- NO FALLBACKS: no size is ever guessed.

**This extends Amit's rule of `a996b7f4`** (components only) to the shape 8
draws. It is not a new theory. Depth and the name token still decide. It
lands with the move, because without it every model drawn with Smart Build
is priced by ERP's own rule even when its modules are named. It is the one
question in this design for Amit: "Does a Smart Build GROUP named
`ASMBL_M_…` count as a medium assembly, exactly as a component does? Claude
recommends yes." Commit A is built with that answer. If Amit says no, the
group clause is dropped from A. The payload shape, the warning's source,
the unnamed-module list and N4 still ship, because they are right either
way.

### 4.3 The code

In `mcft_estimate_worker.rb`, extract pure functions with no `Sketchup`
constants:

```ruby
# kind: :component or :group. Returns 'large' | 'medium' | 'small', or nil.
def self.assembly_size(kind, instance_name, definition_name)
  names = kind == :group ? [instance_name.to_s] : [instance_name.to_s, definition_name.to_s]
  name  = names.find { |n| ROOT_ASSEMBLY_RE.match(n) }
  name && SIZE_OF[ROOT_ASSEMBLY_RE.match(name)[1].upcase]
end

# A top-level group that OpenCutList 8 built or stretched, with no size token.
def self.unnamed_module?(kind, instance_name, has_cutters)
  kind == :group && has_cutters && assembly_size(kind, instance_name, '').nil? &&
    !(instance_name.to_s =~ ASSEMBLY_ISH_RE)
end

# What the walk sends. A count of ZERO sends NO size map, so the bench takes
# the branch it already has for "no ASMBL component in model" and says so.
def self.assembly_payload(counts)
  total = counts['large'] + counts['medium'] + counts['small']
  out = { 'assembly_count' => total }
  out['assembly_counts'] = counts if total > 0
  out
end
```

**In the walk:**

- Admit both kinds: `next unless e.is_a?(Sketchup::ComponentInstance) ||
  e.is_a?(Sketchup::Group)`.
- Keep the image check for components only.
- Run the visibility test first, as now.
- Then call `assembly_size(kind, e.name, (kind == :component ? d.name : ''))`.
- The ASMBL-ish "ignored" check uses the same names list, so a group named
  `ASMBL_WAR` with no size token is listed as ignored, not dropped.
- Then `unnamed_module?(kind, e.name, !PLUGIN.get_attribute(d,
  'stretch_cutters').nil?)` fills a new list, `unnamed_modules`.
- `McftLog.say` prints `kind=group|component` on each line.

**The payload, and the walk's own numbers on screen:**

- The payload is built through `assembly_payload(_counts)`, merged into
  `payload`. There is no other literal `'assembly_counts' =>` in the file.
- The worker keeps `_counts`, and `_deliver` hands it to the dialog as
  `data['mcft_assembly_walk']`. This is the way `ocl_totals` already travels
  beside the priced rows. It is never posted.
- The tab renders the "not counted" warning (`tab-cutlist.js:2413`) from
  `d.mcft_assembly_walk.ignored`, which is the plugin's own list, instead of
  the bench's `assembly_unsized` echo. That echo reads 0 once no size map is
  sent. So the warning now has ONE source, the walk, whatever the bench is
  sent.

**Unnamed Smart Build modules are announced. This is decided, and it
ships.**

- A top-level, visible group whose definition carries `stretch_cutters` and
  whose instance name has no size token goes into `unnamed_modules`.
- The slide says: "<n> group(s) at the top of this <model|selection> look
  like OpenCutList 8 modules but have no ASMBL_L_ / ASMBL_M_ / ASMBL_S_ name,
  so they are NOT counted as assemblies: <names>."
- It is a separate key from `ignored`, not a member of it. `ignored` means
  "named ASMBL… with no size token". It travels to the bench as `unsized`,
  and its warning says exactly that, which would be false for a group named
  `Wardrobe 600`.
- It is a statement, not a marker. Smart Reshape writes the same attribute
  (SB `:516`, `:1767`, `smart_reshape_tool.rb:2161`), so a reshaped plain
  group at the top is listed too. That is still true, since it is not
  counted either, and it is why the wording says "look like" and not "are".
- A Smart Build module's instance name is always its file's basename
  (SB `:2063`), so the list shows what Amit sees in the Outliner.

**N4, and the line beside it:**

- When the walk counts no sized assembly (`top_level` false), MOP sends no
  size map. So the assembly line reads the bench's own `0 assemblies (0
  large, 0 medium, 0 small) (erp:1 + drawer rails (no ASMBL component in
  model))`.
- Directly under that line, N4 says: "An assembly is a component or group at
  the top of this <model|selection> named ASMBL_L_, ASMBL_M_ or ASMBL_S_.
  None was found, so ERP priced the seven assembly steps by its own rule."
- N4 does not repeat the bench's words. It adds the naming rule and the
  scope, which only the plugin knows.
- It is shown exactly when `mcft_assembly_walk.top_level` is false.

**The hazard to tell Amit, once:** wrapping an ASMBL component in an UNNAMED
group (for example, to make a cavity) hides it at depth 2, and it counts 0.
It is not needed, because a component can be the cavity container. Such a
group is not listed as an unnamed module unless 8 gave it `stretch_cutters`.

### 4.4 The test that pins it

`tools/check-assembly-rule.rb` loads the worker's pure functions, as it
already loads the regex, and asserts:

| kind | instance name | definition name | stretch_cutters | expected |
|---|---|---|---|---|
| component | `''` | `ASMBL_M_WAR` | no | medium |
| component | `ASMBL_L_X` | `Part` | no | large (unchanged) |
| group | `ASMBL_M_WAR_600` | `Group#12` | yes | medium, not an unnamed module |
| group | `''` | `ASMBL_M_WAR` | no | nil (a group's definition name is not read) |
| group | `Part` | `Group#3` | no | nil, not an unnamed module |
| group | `ASMBL_WAR` | `''` | yes | nil, ignored, not an unnamed module |
| group | `mcft_asmbl_s_loft` | `Group#1` | no | small (the existing case-insensitive `MCFT_` prefix) |
| group | `Wardrobe 600` | `Group#4` | yes | nil, an unnamed module |
| component | `Wardrobe 600` | `Wardrobe` | yes | nil, not an unnamed module (groups only) |

It also keeps today's 18 name cases, and it adds three more assertions:

- `assembly_payload` with every size 0 returns `{'assembly_count' => 0}`
  and no `assembly_counts` key. With one medium, it returns both keys.
- `_assembly_counts` iterates its scope with `each` and calls no
  `.entities` (no descent).
- The visibility test comes before naming, for both kinds, and the payload
  is built only through `assembly_payload`.

The check must be proved by breaking it. Drop the `Sketchup::Group` clause,
and at least the two group rows that count must fail. Make
`assembly_payload` always include the map, and the zero row must fail.

---

## 5. Smart Build parts: no tag, no edge band, named "Part"

**What 8 makes (SEEN):** Smart Build's dividers, fronts and backs, and
Paneling's panels, are ComponentInstances.

- Each is created by `model.definitions.add(PLUGIN.get_i18n_string('default.part_single').capitalize)`
  (SB `:3535`, `:7754`). The default part name is "Part" in English.
- SketchUp makes definition names unique, so the parts become `Part`,
  `Part#1`, `Part#2` and so on. That is SketchUp API behaviour, NOT
  CONFIRMED here. The cut list names a component part by its DEFINITION name
  (8 `model/cutlist/instance_info.rb:30-31`).
- They carry no MCFT part tag and no edge band.
- Their material is whatever was hovered or picked when they were drawn.
- Fronts and backs carry the definition role `front_panel` / `back_panel`.

**What breaks: nothing.** `estimate_preview` drives no labour from tags. Its
drivers are:

- the bench's own sheet nest;
- the banded-edge count;
- hardware categories by substring;
- the assembly count.

The name only keys hardware rates, and Smart Build makes no hardware. Empty
tags send `[]`. (MOP's CSV header is `Tags`, while the bench's saved-SKU job
card reads `Tag`. That is a mismatch that predates 8, touches only the
suspended saved-SKU path, and is left alone.)

**What changes money, silently:**

- No edge band means no `EB_` metres for that part.
- No face veneer means no laminate from that part.
- A door picked off a V0 carcass comes out V0 with no laminate, so it is
  under-priced.

**What MOP does:**

- **It sends the parts exactly as they are.** The CSV describes the model.
  Inventing edges or laminate would be a fallback.
- **It SAYS two things on the estimate slide**, plugin-side only. Each is
  shown only when its count is above zero:
  - **N2:** "<n> parts still carry OpenCutList's default name". The test is
    a pure function:

    ```ruby
    def self.default_part_name?(name, default)
      /\A#{Regexp.escape(default)}(#\d+)?\z/.match?(name.to_s)
    end
    ```

    It is called with
    `PLUGIN.get_i18n_string('default.part_single').capitalize`, not the
    literal "Part", because the default name is translated. A plain equality
    test would count only the first part, because the rest are `Part#n`. The
    cases are pinned (§7.3, check 7): `Part` and `Part#12` match;
    `Partition`, `Part 2` and `part` do not.
  - **N3:** "<names>: a front panel with no face laminate". These are parts
    whose definition role is `front_panel` (the DefinitionAttributes role
    reader, 8 `definition_attributes.rb:110-122`) with no Frontside/Backside
    veneer.
- **There is NO general "no edge band" warning.** Every back panel would set
  it off, and a warning that fires every time teaches the reader to skip the
  line the real one appears on.

---

## 6. Install and update on the Mac

### 6.1 Why 8 breaks "restart is the deploy", and the fix

**The problem (SEEN):**

- On 7.1, `twig/dialog-tabs.twig` loads about 60 scripts one by one, with
  `jquery.ladb.tab-cutlist.js` taken straight from git. So git carried MOP's
  JS to the screen, and the one tracked build output
  (`tabs-twig-templates.js`) carried its templates.
- On 8 the same twig loads only three files: `js/bundles/common-bundle.js`,
  `js/bundles/tabs-bundle.js` and `js/i18n/<lang>.js`
  (8 `twig/dialog-tabs.twig:19-21`).
- `tabs-bundle.js` concatenates every tab plugin (`tab-cutlist.js` among
  them), the compiled twig templates, `dialog.js` and `dialog-tabs.js`
  (8 `build/gulpfile.js` `TABS_JS_FILES`, task `js_bundle_tabs`).
- 8 gitignores `js/bundles/`.
- So with the rbz's stock bundle, MOP's Ruby would load, but the estimate
  slide and the MCFT buttons would not be there. Nothing would say why.
  This is the 3 Sep 2026 fault again, made worse.

**The fix:**

- **Track `src/ladb_opencutlist/js/bundles/tabs-bundle.js`** through a
  `.gitignore` exception of 7.1's shape:
  `/src/ladb_opencutlist/js/bundles/*`, then
  `!/src/ladb_opencutlist/js/bundles/tabs-bundle.js`. The directory form 8
  uses cannot be re-included (§2.2, `.gitignore` row, RAN). CI asserts it
  both ways (§7.2). It becomes the ONE delivered MCFT build output.
  `tabs-twig-templates.js` stops being tracked (§2.2).
- **Build it, and only it, by two invocations:**
  ```sh
  cd build && npm ci && npx gulp twig_compile
  npx gulp js_bundle_tabs
  ```
  - They are not chained, because `twig_compile` starts an asynchronous
    `del()` and returns only its last stream, so a series that chains it can
    race (SEEN).
  - `js_bundle_tabs` writes only `tabs-bundle.js`.
  - **Never `gulp bundle`.** It runs `css_bundle` in parallel with the four
    JS bundles (8 `gulpfile.js:281-286`). `css_bundle` reads
    `css/lib/*.min.css`, which are gitignored and made only by
    `css_minify`. So on a clean checkout it fails with "File not found with
    singular glob: …/css/lib/bootstrap.min.css" (RAN, on
    `git archive upstream/8.0.0`). The earlier byte-identical result came
    from a copy where `gulp compile` had already run.
- **Track `build/package-lock.json`.**
  - Neither branch has one, so `npm ci` stops with EUSAGE (RAN).
  - With `npm install`, the tree is whatever the registry serves that day:
    a newer uglify re-minified `common-bundle.js`, and a newer less wrote
    invalid CSS (`margin-bottom:1.25rem/2`) (RAN).
  - A CI compare that depends on the registry's mood is a check that will go
    red for no reason, and then get deleted.
  - So the lockfile is committed on `mcft`, and CI and every build use
    `npm ci`. B creates it with `npm install --package-lock-only`. After
    that it is regenerated the same way, ONLY when a merge changes
    `build/package.json`, followed by `npm ci`, in the merge commit
    (§1.2, step 6).
- **The merge and its bundle land in ONE commit** (§1.2, steps 3–8), so the
  pre-commit hook sees them together. A merge that commits by itself runs
  `pre-merge-commit`, not `pre-commit`, so that hook is added too (§7.2).
- **Take every other output from the rbz, never from a local build:**
  `common-bundle.js`, the modal and viewer bundles, the css, the html
  dialogs, i18n, and the ten native engines (Clippy, Imagy, Meshy, Packy and
  Skpy, as a `.dylib` and a `.dll` each).
  - MOP touches none of them.
  - The native engines cannot be built here: upstream's make-c-libs is
    `workflow_dispatch` on a macOS runner.
  - If MOP ever adds i18n keys, `js/i18n` must be built and tracked in the
    same commit. Until then, MOP's strings stay hard-coded English.
- **Verified** (RAN): on a clean `git archive upstream/8.0.0` with
  `build/node_modules` in place, `npx gulp twig_compile` and then
  `npx gulp js_bundle_tabs` gave a `tabs-bundle.js` byte-identical to the
  one in 8's rbz (128 templates, 18,378 lines). The `node_modules` came from
  an earlier `npm install` of 8's `build/package.json`. No lockfile exists
  yet, so this was not `npm ci`.

### 6.2 What `dev-install-mac.sh` becomes, and the autoupdater

**What is wrong today (SEEN):**

- The script extracts the rbz with `unzip -nq`, which never overwrites. On
  a clone that holds 7.1's outputs, it would keep 7.1's html (which loads
  scripts that 8 bundles), 7.1's i18n (which lacks 8's keys), and 7.1's
  Packy, Clippy and Imagy. It would only ADD Meshy, Skpy and the bundles.
- It would also keep 7.1's `.susig` and `extension_info.txt`, which describe
  files that no longer exist. What SketchUp does with a stale signature is
  NOT CONFIRMED.
- 8's rbz is unsigned and carries neither file.
- The updater prints "up to date" whenever HEAD equals `origin/mcft`, and
  never looks at what is on disk. If anything wrote INTO the clone through
  the links, it would go on announcing MOP while stock 8 loads (below).

**Every rbz-only file is covered by an ignore rule** (RAN). The 8.0.0 rbz
holds 177 files that are not tracked: 5 + 5 native libraries, 4 bundles,
40 + 40 i18n files, 80 html and 3 css. All 177 match 8's `.gitignore`, and
a control path that should not match did not. So a clean refresh leaves no
untracked file, and check 5 asserts that it stays so.

**The new pieces, all tracked in the repo:**

1. **`tools/mcft-refresh-outputs.sh [--if-stale | --verify]`** is the ONE
   implementation of "make the build outputs on disk match HEAD", and of
   "do they still?". Both the installer and the autoupdater call it. A
   refresh does this, in order:
   1. With `--if-stale`, it stops at once if the first line of the stamp
      `src/ladb_opencutlist/.mcft-outputs` equals
      `git rev-parse HEAD:dist/ladb_opencutlist.rbz`. This keeps the call
      cheap.
   2. Run `tmp=$(mktemp -d)`, then `unzip -q dist/ladb_opencutlist.rbz
      'ladb_opencutlist/*' -d "$tmp"`.
   3. Verify that `EXTENSION_BUILD` is the same in three places: the rbz's
      `ruby/constants.rb`, HEAD's `src/ladb_opencutlist/ruby/constants.rb`,
      and `dist/manifest.json`. If not, refuse loudly. Nothing under `src/`
      has been touched yet.
   4. For every path that `git ls-files src` lists, delete its copy in
      `$tmp`. Then the branded loader, the live Ruby and the committed
      `tabs-bundle.js` always win.
   5. Run `git clean -fdXq -- src/`. This deletes EVERY ignored file under
      `src/`: every old output, 7.1's dylibs, the `.susig`,
      `extension_info.txt` and the old stamp. Nothing Amit owns lives under
      `src/`: the estimate log and the update log are in Application
      Support (SEEN).
   6. Run `cp -R "$tmp/ladb_opencutlist/." "src/ladb_opencutlist/"`. That is
      ONE command on macOS and on Linux, because BSD and GNU `cp` both copy
      a directory's contents for a source ending in `/.`. It is not `ditto`,
      which exists only on macOS and would leave CI proving a command Amit
      never runs. It is not `cp -R "$tmp/ladb_opencutlist"
      src/ladb_opencutlist` either, which, into an existing folder, nests a
      second `ladb_opencutlist` inside it (RAN, GNU `cp`).
   7. Write the stamp LAST (it is gitignored). Line 1 is the rbz blob id,
      line 2 is the build, and then comes one `cksum` line (CRC, size, path)
      per output it laid down, listed from `$tmp` after step 4. `cksum` is
      POSIX, the same command on both platforms, and it reads content, so a
      touch that changes nothing is not a change. (RAN: the 177 rbz-only
      files of 8.0.0, 57 MB, in under 0.1 s here.)

   A refresh exits with a distinct code for each of three outcomes: failed
   before touching `src/`, failed after touching it, and done.

   **`--verify` changes nothing.** It exits 0 only when all three of these
   hold, with a distinct code for each failure:
   - **10:** a tracked file has changed
     (`git status --porcelain --untracked-files=no` is not empty);
   - **11:** the stamp is missing, or its line 1 is not HEAD's rbz blob;
   - **12:** an output listed in the stamp no longer matches its `cksum`
     line.

2. **`tools/mcft-autoupdate.rb`** is the update logic, loaded from the clone
   on every start (the S4 MDT pattern, `dev/load_from_checkout.rb`). Changes
   to the updater then reach the Mac with no re-install. The code that runs
   is the current HEAD's, and that commit has already passed the gate. In
   order:
   1. **Integrity first, before the fetch:** run
      `mcft-refresh-outputs.sh --verify`.
      - **10 or 12:** something wrote into the clone. That could be an
        `.rbz` install, or 8's Upgrade, writing THROUGH the links (whether
        SketchUp does that is NOT CONFIRMED, §6.3). Then there is no fetch,
        no fast-forward and no refresh. A line `ok=false
        reason=clone-modified <10|12>` goes in the log. A messagebox says:
        "Something replaced MOP's files in <clone>. Quit SketchUp and run:
        bash …/tools/dev-install-mac.sh". The updater **never prints "up to
        date" on a modified clone.** Without this check, HEAD == origin/mcft
        reads "Already up to date", `--if-stale` matches the stamp, and the
        stub announces MOP while stock 8 loads. The symlink test in step 6
        cannot see this case, because the links still resolve into the
        clone.
      - **11:** the stamp is written last and `git clean` removes it first,
        so a missing stamp on a clean tree is exactly an interrupted
        refresh. The updater runs a full refresh (not `--if-stale`), logs
        it, and carries on. That is the one implementation running again,
        not a second path.
   2. Fetch, then the CI gate, then `merge --ff-only`, exactly as today.
      Today's gate reads the runs whose name starts with `MCFT checks` for
      the target sha, and refuses `pending` and `unknown`.
   3. Then `mcft-refresh-outputs.sh --if-stale`. This runs before
      OpenCutList loads, so no dylib is loaded yet: the `!` name makes the
      stub load first.
   4. **If the refresh fails before touching `src/`** (a bad rbz, or the
      three builds disagree), run `git reset --keep <the HEAD before the
      fast-forward>`. That puts back the source that matches the outputs
      still on disk. Then a messagebox says "held at <rev>: <reason>", and a
      line goes in the log. The next start tries again.
   5. **If it fails after touching `src/`** (for example, a full disk), a
      messagebox names ONE command, to run with SketchUp quit:
      `bash ~/dev/malletcraft/mcft-opencutlist-sketchup-extension/tools/dev-install-mac.sh`.
   6. **Check what will actually load.** `Plugins/ladb_opencutlist` and
      `Plugins/ladb_opencutlist.rb` must both be symlinks that resolve into
      this clone (`File.symlink?`, `File.realpath`). If not, say so loudly:
      "OpenCutList in Plugins is not MOP — an .rbz install or OpenCutList's
      Upgrade replaced it. Quit SketchUp and run: <the install command>".
      Together with step 1, this closes both blind spots: links that no
      longer point at the clone, and a clone that no longer holds MOP.
   7. Print `[MCFT] OpenCutList (MCFT Edition) up to date @ <rev>`, and
      append `ok=… rev=… outputs=<stamp line 1>` to
      `~/Library/Application Support/mcft-ocl-update.log`.
   8. **Every failure message names the install script, never `git pull`.**
      Today's box says `cd <repo> && git pull`. That contradicts the house
      rule and bypasses the gate, and it goes.

3. **The stub written into Plugins** (`!mcft_autoupdate.rb`) holds the
   clone's path and `load`s `tools/mcft-autoupdate.rb`. If that file is
   missing, the stub raises a messagebox naming the path and the install
   command. It never falls back to an older copy (NO FALLBACKS).

4. **`tools/dev-install-mac.sh`**, in order:
   1. Refuse while SketchUp runs: `pgrep -xq SketchUp && { echo "Quit
      SketchUp first"; exit 1; }`.
   2. Refuse unless HEAD is on branch `mcft` and `git status --porcelain
      --untracked-files=no` is empty. The outputs are refreshed against
      HEAD, so HEAD must be the published commit. The refusal names the way
      out: §6.4 steps 2–4 (delete the clone, clone it again, install).
      Claude first reads the clone's `git status` through the bridge, so
      nothing is deleted unseen.
   3. In Plugins, `rm -rf` four paths: `ladb_opencutlist`,
      `ladb_opencutlist.rb`, `ladb_opencutlist.upgrade_backup` and
      `ladb_opencutlist.rb.upgrade_backup`. The last two are 8's updater
      backup names. `rm` removes a link, not its target. This also removes
      8 LAB's real folder and file.
      `~/Library/Application Support/OpenCutList` is left alone. It holds
      8's `upgrade.log` and asset library, which MOP on 8 shares, because
      the plugin id is the same.
   4. Run `tools/mcft-refresh-outputs.sh` (not `--if-stale`). Where only
      outputs were touched (`--verify` 12), this heals them.
   5. Symlink the two paths, as today.
   6. Write the stub.
   7. Run `git config core.hooksPath .githooks`, so the clone's hooks are
      active.

**When a fast-forward brings a new rbz,** the refresh runs at start. It does
not refuse. A weekly LAB merge plus a refusal would send Amit to Terminal
every week, which breaks "restart IS the update". The refresh is safe to run
at start for two reasons: it happens before OpenCutList loads, and a failure
that touched nothing is rolled back by `reset --keep`.

**Size** (RAN, `git rev-list --disk-usage`):

- Merging `upstream/8.0.0` brings 1,570 commits, 233 of which touch the rbz:
  about 1.72 GB of new objects, almost all of it rbz.
- Today's stub FETCHES FIRST and gates afterwards. So the first start after
  `mcft` moves would pull about 1.7 GB into the old clone, at startup,
  whether CI is green or not.
- After that, each LAB rbz is about 7 MB packed.
- Hence a fresh PARTIAL clone (§6.4, step 3), and the old stub removed
  before the push (§6.4, step 1). The push from this container is §1.3.
- In a `--filter=blob:none` clone, later fetches keep the filter, and the
  checkout fetches the blobs it needs. This has not been tried on Amit's Mac
  (NOT CONFIRMED). A plain clone also works, but fetches about 1.7 GB once.

### 6.3 Blocking 8's own update

**How 8 updates itself (SEEN):**

- When the tabs dialog starts, it fetches the stable or LAB manifest from
  lairdubois.fr (`dialog-tabs.js:121-170`). If `data.build >
  capabilities.build`, the Upgrade button gets an orange dot.
- A click sends `core_upgrade`, which reaches `upgrade_command`
  (8 `plugin.rb:1695`) → `Updater.new(PLUGIN_DIR, backup: IS_RBZ, …)` →
  `download_and_install`.
  - It downloads with `Sketchup::Http` and checks every CRC and the build.
  - With `IS_RBZ` it COPIES the registrar to `*.rb.upgrade_backup` and
    RENAMES the folder to `*.upgrade_backup`.
  - Then it calls `Sketchup.install_from_archive`, then `discard_backup`.

**What one click would do to MOP's links (NOT CONFIRMED):**

- The rename moves the LINK, not the clone.
- The registrar is copied, so when the archive installs, it is still a
  symlink. Whether SketchUp then writes THROUGH it into the clone, or
  replaces the link, is unknown. Writing through would dirty the clone;
  `--verify` then stops the updater loudly (§6.2, step 2.1). Replacing the
  link is caught by the symlink test (§6.2, step 2.6).
- Either way, stock 8 replaces MOP.
- `IS_RBZ` is `PLUGIN_DIR.start_with?(<Plugins>)`, with `PLUGIN_DIR` built
  from the loader's `__FILE__` (8 `src/ladb_opencutlist.rb:18`). It is true
  if `__FILE__` is the link path (likely), and false if it is the resolved
  path (NOT CONFIRMED). It gates more than the backup (§2.3), and the
  estimate stamp prints it.

**The block, carried from 7.1 MOP** (7 `plugin.rb:1368`):

- **The refusal is the FIRST statement of 8's `upgrade_command`,** before
  `Updater.new`. It shows a messagebox and returns `{cancelled: true}`. The
  message reads: "This is OpenCutList (MCFT Edition). It updates when
  SketchUp restarts. Never click Upgrade here, and never install an
  OpenCutList .rbz on this SketchUp."
- `core_upgrade` is the only route to `download_and_install`. The other
  `Updater` use in `setup()` (8 `:1014`) only discards `*.upgrade_backup`
  paths, and stays as it is.
- **The update CHECK is left on.** With `IS_LAB` false (§2.3), it reads the
  STABLE manifest. So there is no dot during the LAB weeks. The dot appears
  only when stable 8.0 is published, and then it tells Claude (through
  Amit) that MOP can move to stable. The click is refused either way. A dot
  that appears once and means something is worth keeping. One that appeared
  every week would not be.
- A new check pins the refusal (§7.3, check 4). Nothing checks it today.

### 6.4 The ONE-TIME steps on Amit's Mac

These steps are handed to Amit ONE AT A TIME. Each next step waits for his
report of what the last one did. The paths assume SketchUp 2026 and the
workspace at `~/dev/malletcraft`.

Before step 1, Claude reads the Mac through the bridge. These are reads, so
the bridge does them; Amit is not asked:

- whether the old clone has anything uncommitted or unpushed;
- `git --version` (it must be 2.19 or later for a partial clone);
- what is in Plugins now.

If the clone holds anything that is not on GitHub, step 2 waits until that
has been dealt with.

**Step 1 — BEFORE Claude pushes the 8 line to `mcft`.** Quit SketchUp, then:

```sh
rm -f "$HOME/Library/Application Support/SketchUp 2026/SketchUp/Plugins/!mcft_autoupdate.rb"
```

The old stub is not an extension, so Extension Manager's uninstall left it
in Plugins. It still fetches into the old clone on every start. After this
step, SketchUp runs stock 8 LAB alone, which is exactly what Amit has today.

*[Claude pushes upstream's history in pieces (§1.3), builds §1.1's commits on
`mcft8`, pushes `mcft8`, waits until every workflow run on the tip's full
sha is green, fast-forwards `mcft`, pushes it, and confirms the runs on
`mcft` too.]*

**Step 2 — with SketchUp quit**, delete the old clone:

```sh
rm -rf ~/dev/malletcraft/mcft-opencutlist-sketchup-extension
```

Nothing in it is unique. All MCFT work is on GitHub, the estimate log is in
Application Support, and the bridge read before step 1 has confirmed it.

**Step 3** — make a fresh partial clone of `mcft`:

```sh
git clone --filter=blob:none --branch mcft https://github.com/malletcraft/mcft-opencutlist-sketchup-extension.git ~/dev/malletcraft/mcft-opencutlist-sketchup-extension
```

**Step 4** — run the installer. It removes 8 LAB's real files and any
`.upgrade_backup` from Plugins, fills every build output from 8's rbz, links
the clone and writes the new stub:

```sh
bash ~/dev/malletcraft/mcft-opencutlist-sketchup-extension/tools/dev-install-mac.sh
```

**Step 5** — start SketchUp. **Before clearing the console**, read three
things:

- The console line `[MCFT] OpenCutList (MCFT Edition) up to date @ <rev>`.
- Extension Manager. It should list "OpenCutList (MCFT Edition)", enabled.
  If it shows disabled, Amit enables it.
- The update log, which should show `ok=true` and an `outputs=` stamp. Claude
  reads it through the bridge. Amit does not have to:
  `tail -1 "$HOME/Library/Application Support/mcft-ocl-update.log"`.

**Step 6** — Amit opens a model he has already estimated on 7.1, runs the
MCFT estimate, and says whether it looks like the 7.1 one. Claude then reads
`mcft-estimate.log` through the bridge for three things:

- the stamp line `[MCFT] estimate — plugin <rev> is_rbz=… is_lab=…`, which
  settles `IS_RBZ` (§2.3; `is_rbz=true` and `is_lab=false` are expected);
- the two estimates side by side, raising the §3.2 hardware comparison if
  the figures differ;
- on a model with a Boolean cut, the cut panel, which must still be in the
  parts list and in the estimate (§3.3).

**After this, Amit never:**

- uninstalls OpenCutList in Extension Manager (it acts on the links, with an
  unknown effect);
- clicks OpenCutList's Upgrade;
- installs any `.rbz`;
- lets `mcft-workspace/bootstrap.sh` update this repo. It runs `git pull
  --ff-only`, which bypasses both the CI gate and the output refresh, and on
  a new machine `gh repo clone` fetches the whole 1.7 GB. That is an S7 HUB
  fix: bootstrap skips MOP, and points at this install script instead. It is
  its own change, in its own repo, and it lands before step 3.

Models Amit saves in 8 LAB keep their OpenCutList attributes and
preferences, because MOP on 8 uses the same plugin id.

---

## 7. CI

`.github/workflows/mcft-checks.yml` stays the workflow whose runs the Mac's
gate reads (run name `MCFT checks`). Every check runs on the merged tree,
exactly as on 7.1.

### 7.1 The existing checks, on 8

In the trial (RAN, on the resolved merge, Ruby 3.3 and Node 22):

- `ruby -c` passed on 223 files.
- check-ruby-floor passed (0 fatal). check-requires passed (705 requires,
  all present). check-dialog-api passed (57 methods).
- check-csv-thickness, check-assembly-rule (18 names), check-push-suspended
  and check-mcft-log all passed.
- The templates job was RED: the bundle was not recompiled. Commit B fixes
  that.
- The smoke job was RED, with 4 failures, every one of them in the diagram
  pack. Commit D fixes that.
- Every estimate check in the smoke test passed: the render, the
  reconciliation, both buttons, and the hidden-group ids.

### 7.2 Changes to existing checks

- **Triggers:** add `mcft8` to the `push` branches, in P. Red on `mcft8` is
  free.
- **The Ruby floor stays at Ruby 2.7 / SketchUp 2021** (Amit, 2026-08-24).
  - 8 sits under it: check-ruby-floor on the untouched 8.0.0 tree gave
    "214 files, 0 fatal, 0 warn" (RAN). Spot greps of 8's Ruby find no
    syntax newer than 2.2.
  - **The check now also scans the loader**, `src/ladb_opencutlist.rb`, and
    so does the `ruby -c` loop. Both read only `ruby/**`, and a parse error
    in the loader takes down the whole extension.
  - The job title "parses on SketchUp 2017" becomes "parses on SketchUp 2021".
- **The templates job becomes "Committed dialog bundle matches its source":**
  - On the clean checkout, `cd build && npm ci && npx gulp twig_compile`,
    then `npx gulp js_bundle_tabs`, as two invocations. Never `gulp bundle`
    (§6.1).
  - Then a SORTED compare of `js/bundles/tabs-bundle.js` against the
    committed file, as today's compare of the template bundle. The template
    order inside it still comes from a glob. This is the failure of
    2026-09-03: a twig or tab JS edit committed without its output.
  - Then two pairs of assertions. `git check-ignore -q
    src/ladb_opencutlist/js/bundles/tabs-bundle.js` must FAIL, and `git
    ls-files --error-unmatch src/ladb_opencutlist/js/bundles/tabs-bundle.js`
    must succeed. The same pair applies to `build/package-lock.json`. A
    directory-level `git add` on a later merge would otherwise drop the
    bundle without any error.
  - The error names the two build commands.
- **The smoke job loads exactly what SketchUp loads. This is decided.**
  - In the order of 8 `twig/dialog-tabs.twig:19-21`, it loads three files:
    `unzip -p dist/ladb_opencutlist.rbz
    ladb_opencutlist/js/bundles/common-bundle.js`, then the committed
    `src/ladb_opencutlist/js/bundles/tabs-bundle.js`, then `unzip -p
    dist/ladb_opencutlist.rbz ladb_opencutlist/js/i18n/en.js`. The job
    fails if any of them cannot load.
  - Each runs as a `vm.Script` in jsdom's own context
    (`dom.getInternalVMContext()`). That shares top-level `const` and `let`
    between scripts, the way separate `<script>` tags do. It is NOT
    `window.eval`, as the harness uses today. An indirect eval keeps each
    script's `const`s to itself, so the tabs bundle then dies on
    `TOKENFIELD_OPTIONS is not defined`, which `constants.js` declares
    inside common-bundle. (RAN with 8's own bundles: `eval` threw;
    `vm.Script` loaded all three.)
  - The load raises exactly one jsdom error: `dialog-tabs.js` sets
    `window.location.href = "skp:ladb_opencutlist_setup_dialog_context"` on
    document ready. That is the SketchUp bridge, and jsdom reports it as
    "Not implemented: navigation to another Document" (RAN). The harness
    expects it exactly once, as proof that the bundle's entry script ran,
    and fails on any other error.
  - With the real `en.js`, i18next is the real one, with the real strings,
    so the harness's i18next stub goes.
  - The sources path is removed. The job no longer reads `js/templates/`,
    so it no longer runs `twig_compile`. It installs jsdom with `npm ci` in
    `build/`.
  - The diagram-pack block is deleted.
  - It is proved by breaking it: reintroduce the 2026-09-03 TypeError, and
    it must fail.
- **The hooks:**
  - **`pre-commit`** refuses a commit that stages a `.twig`, any file in
    `TABS_JS_FILES`, or `build/package.json`, but does not stage
    `js/bundles/tabs-bundle.js` (and, for `package.json`, the lockfile).
  - **`pre-merge-commit` is new.** Git runs it, and not `pre-commit`, when a
    merge commits by itself (per git's documentation). It refuses every
    such merge with: "On this branch a merge is made with --no-commit, then
    tools/mcft-take-upstream.sh, then git commit
    (docs/mcft/MOP-ON-OCL8.md §1.2)." A fast-forward makes no merge commit
    and is not affected.

### 7.3 New checks

1. **`check-assembly-rule.rb` extended** with the group cases, the
   unnamed-module cases, the payload shape and the source assertions
   (§4.4).
2. **`tools/check-build-matches-rbz.rb`.** The rbz's
   `ruby/constants.rb` `EXTENSION_BUILD`, `src/ladb_opencutlist/ruby/constants.rb`
   `EXTENSION_BUILD` and `dist/manifest.json`'s `build` are all equal. This
   is the "zzz" trap of §2.3. It also checks two things about the
   version: that `EXTENSION_VERSION` does not match `/-[a-z]+\z/`, so
   `IS_LAB` stays false and the startup line survives; and that the
   loader's `ex.version` equals it.
3. **`tools/check-mcft-wiring.rb`.** The trial showed check-requires
   passing while `setup()` named `McftController` before anything had
   required it, which would be a load-time `NameError`. The new check reads
   `plugin.rb` and asserts two things: every method that names
   `McftController` has a `require_relative 'controller/mcft_controller'`
   earlier in the same method, or at file level before the method; and the
   controller is pushed in `start()`. It is proved by deleting the require
   above `setup_menu`: the check must fail.
4. **`tools/check-upgrade-refused.rb`.** It asserts three things: the first
   statement of `upgrade_command` returns `{cancelled: true}` after a
   messagebox; nothing in `ruby/` outside `lib/` calls `download_and_install`
   or `install_from_archive`; and the only other `Updater` use is
   `discard_backup`. It is proved by deleting the refusal.
5. **`tools/check-refresh-outputs.sh`** runs `mcft-refresh-outputs.sh`
   against a throwaway copy of the checkout, on Linux, with the same `cp`
   command the Mac runs (§6.2). It asserts:
   - every tracked file is byte-identical after the refresh;
   - a planted stale `bin/osx/lib/libPacky.dylib`, `.susig` and
     `extension_info.txt` are gone;
   - the stamp is written, with one `cksum` line per output;
   - `src/ladb_opencutlist/ladb_opencutlist` does not exist;
   - `git status --porcelain --untracked-files=all` is empty after the
     refresh, so any future rbz output with no ignore rule turns CI red;
   - with a planted build mismatch, the script refuses without touching
     `src/`;
   - `--verify` returns 0 on a fresh refresh, 10 with a tracked file
     edited, 11 with the stamp deleted, and 12 with one byte appended to an
     output.
6. **`tools/check-upstream-tree.rb`** (in P). It reads `docs/mcft/UPSTREAM`
   and `docs/mcft/MCFT-PATHS`. It adds
   `https://github.com/lairdubois/lairdubois-opencutlist-sketchup-extension`
   as a promisor remote with `partialclonefilter blob:none`, and fetches that
   one sha with `--depth=1 --filter=blob:none`. Trees only: 52 KiB for
   `c5405bd4` (RAN). It then asserts:
   - every HEAD path outside `MCFT-PATHS` has the same mode and the same
     object id as at the build. Equal ids mean equal bytes, so no blob is
     downloaded;
   - every build path outside `MCFT-PATHS` exists at HEAD, so nothing is
     missing and nothing is extra;
   - every `own:` path exists at HEAD and not at the build, and every
     `changed:` path exists at both;
   - the build's own `constants.rb` `EXTENSION_BUILD` equals HEAD's. That
     one blob is fetched lazily, and was the only one (RAN). Together with
     check 2, and the rbz compared by object id, this means the build's
     sources, its rbz and MOP all name one build. A merge that took a
     mid-week commit, whose sources are newer than its rbz, fails here.

   It is proved by breaking it three ways: change one byte of a non-MCFT
   file, add a stray file, and leave a stale `own:` line. Each must fail.
7. **`tools/check-estimate-notes.rb`.** It loads `default_part_name?`
   (§5) and asserts the cases: `Part` and `Part#12` match, while
   `Partition`, `Part 2` and `part` do not. It also asserts, from the
   source, that the estimate stamp prints `is_rbz=` and `is_lab=` (§2.3). A
   stamp is the first thing to vanish when a path is rearranged.

**Before merging, every workflow on the full sha must be green, not only
`MCFT checks`.** Upstream's `make-c-libs-*` workflows are `workflow_dispatch`
only, and never run on a push.

---

## 8. What S4 MDT needs

**Nothing for the move.**

- `grep -rn -i "ladb|opencutlist"` over `mcft-design-tools` finds only prose
  (README, CLAUDE.md).
- MDT uses its own `MCFT::*` modules, the SketchUp API and PB4's PBAPI. It
  reads and writes no `ladb_opencutlist` dictionary.
- `views.rb:48` accepts a Group or a ComponentInstance.
- So by code read, MDT keeps working beside MOP on 8. A restart updates both.

**Two indirect points, not part of this move:**

- `assembly_gen.rb` names its assembly from `spec[:article]` (default
  `WARDROBE-01`). Without an `ASMBL_[LMS]_` name, MOP counts it as 0 on 7.1
  and on 8 alike. N4 (§4.3) now says so on screen, under the bench's own
  "no ASMBL component" label. Naming generated assemblies
  `ASMBL_<size>_<article>` is a separate S4 MDT change, to be offered to
  Amit on its own.
- Whether PB4 hardware posts collapse under 8's hardware rule (§3.2) is NOT
  CONFIRMED. It is the same Mac check.

---

## 9. Risks, and the way back to 7.1

### 9.1 Risks

| Risk | How likely | What contains it |
|---|---|---|
| A LAB build breaks a drawing tool or the cut list | real; Amit accepted it | Claude merges only "+ LAB build" commits and only on request (§1.2). A bad build is undone by a go-back commit (§1.2): `tools/mcft-take-upstream.sh <last good build>` on top, never a reset, never a plain `git merge`. §9.2 is the last resort. |
| Upstream changes left out with no conflict, after a go-back or through git's virtual base | certain if git's merge decided content: after a go-back the bad build is the next merge base, so everything it changed that the newer build did not touch again stays at the good build's version, silently | Every merge is `-s ours --no-commit` plus the script, which takes content from the named build. Check 6 proves on every push that every non-MCFT path is that build's. The pre-merge-commit hook refuses a merge that skips the procedure. |
| A LAB build changes an OpenCutList API MOP calls | low per build; certain over months | `check-requires`, `check-dialog-api` and the smoke test catch a rename at merge time, on `mcft8`. A change of meaning (as §3.2) is caught only by reading the CHANGELOG of each merged build. Claude reads it for every merge and lists anything touching the cut list in the merge commit. |
| The dialog shows stock 8 with no estimate | would be certain without §6.1 | The tracked bundle, the bundle CI compare, the ignore assertions, the hooks. |
| A build mismatch between the outputs and the source | each LAB merge | The refresh at start, the three-way build check (§6.2, §7.3 checks 2 and 6), `reset --keep` on failure. |
| Something writes through the links into the clone (an `.rbz` install, 8's Upgrade) | unknown | `--verify` before every start. A modified clone is never announced "up to date"; it stops with one command named (§6.2). |
| Amit clicks Upgrade, or installs an `.rbz` | low | The refusal (§6.3) and its check. The symlink test and `--verify` say loudly when Plugins or the clone no longer hold MOP. |
| Extension Manager acts on the symlinks | unknown | Amit is told never to uninstall there. The installer repairs any state (step 4 can always be re-run). |
| `bootstrap.sh` pulls MOP around the gate | real | The S7 HUB fix (§6.4), before step 3. |
| A Smart Build model priced by ERP's rule under the plugin's badge | certain without §4 | The group rule (§4), no size map when nothing was counted, N4 under the bench's own label. |
| An unnamed Smart Build module not counted | likely, wherever a library file is not named ASMBL_ | The unnamed-module list (§4.3) names it on the slide. |
| A panel painted with a machining material vanishes from the estimate unannounced | possible, by a mis-applied Paint | Accepted, as 8's rule (§3.3). The Mac check after a Boolean cut. |
| `IS_RBZ` false for MOP: Smart Join in the menu, no 300 s packing limit | unknown | The estimate stamp prints it; §6.4 step 6 reads it. |
| Sheet parts priced without a part's own allowance | only if a part carries one | N1 says so. |
| Hardware counts differ from 7.1 on the same model | possible on PB4 carcasses | The Mac check (§3.2, §6.4 step 6). |
| The first push carries 1.72 GB of upstream history | certain without §1.3 | Upstream's history pushed first, in pieces under 400 MB, to `upstream-8.0.0`. |
| The 1.7 GB fetch at startup | certain if step 1 is skipped | Step 1 before the push, and the partial clone. |
| A model drawn in 8 is opened in 7.1 | only on the way back | See §9.2. |

### 9.2 Going back to MOP on 7.1

The last 7.1 MOP commit stays tagged `mcft-7.1-final` (`6b0ba3e`). It is
pushed before `mcft` moves. History on `mcft` is never rewritten, so going
back is done by a commit on top, not a reset:

1. **Claude builds the commit.** On `mcft`, run `git read-tree -u --reset
   mcft-7.1-final`, then check out from the 8 line:
   `tools/mcft-refresh-outputs.sh`, `tools/mcft-autoupdate.rb`,
   `tools/mcft-take-upstream.sh`, the new `tools/dev-install-mac.sh` and the
   new checks. Commit with the message "Back to MOP on OpenCutList 7.1:
   <why>". The tree is 7.1's code, 7.1's rbz and 7.1's tracked template
   bundle, together with the tooling that knows how to refresh outputs. The
   refresh's build check holds, because 7.1's rbz and 7.1's `constants.rb`
   agree.
   - `docs/mcft/UPSTREAM` goes back to `d03f4548`, and `MCFT-PATHS` to P's
     lists plus every tooling path carried over. Check 6 then proves the
     tree is 7.1 plus MCFT, exactly as it proved P.
   - The `.gitignore` must go back to tracking `tabs-twig-templates.js`.
   - The CI templates job must go back to 7.1's compare. 7.1 has no
     `js/bundles/`.
   - The commit is built on `mcft8` first, and proved green there.
   - If MOP later returns to 8, that merge again uses the script, from the
     `d03f4548` base the tree then names.
2. **Amit restarts SketchUp.** The autoupdater checks the clone, gates the
   commit and fast-forwards it. The refresh sees a new rbz blob, clears 8's
   outputs, and lays 7.1's down. MOP 7.1 loads.
3. **What going back costs:**
   - All of 8's tools: Smart Build, Smart Reshape, Paneling, Boolean. MOP
     and stock 8 cannot be installed side by side, because they share the
     plugin id.
   - A model saved with Smart Build opens in 7.1 as plain groups and
     components. Its modules can no longer be edited as modules.
   - Whether 7.1 is upset by 8's extra attributes on definitions and
     materials is NOT CONFIRMED. OpenCutList reads attributes by key, so
     unknown keys are most likely ignored.
   - MOP's estimate is unaffected by any of this. It reads names, parts and
     materials.
4. **If the Mac is in a state the autoupdater cannot fix** (a broken clone,
   a damaged Plugins folder), the same one command applies, with SketchUp
   quit:
   `bash ~/dev/malletcraft/mcft-opencutlist-sketchup-extension/tools/dev-install-mac.sh`.
   If the clone itself is gone, or dev-install refuses a modified clone,
   steps 2 to 5 of §6.4 rebuild it, at whatever `mcft` holds.

### 9.3 What is NOT in this move

- No bench change, of any kind. The payload change of §4.3 sends the bench
  less, on a path it already handles.
- No rebuilt all-boards diagram print (§2.4).
- No i18n for MOP's own strings.
- No change to the suspended push path. It is still SUSPENDED, still
  guarded, and still not deleted.
- No S4 MDT change (§8).
- The S7 HUB `bootstrap.sh` fix (§6.4) is its own change in its own
  repository.

---

## 10. The critic

A critic reviewed the first version of this design on 23 Nov 2026 and made
twelve findings. Each was checked against the code, or re-run, before it was
applied. All twelve were confirmed. In four, part of the proposed fix was
done differently, and each says why.

1. **The bundle build command fails on a clean checkout** (major).
   CONFIRMED. A clean `git archive upstream/8.0.0` was re-run with
   `build/node_modules` in place: `npx gulp twig_compile` exited 0, and
   `npx gulp bundle` exited 1 on `css_bundle`, "File not found with singular
   glob: …/css/lib/bootstrap.min.css". `npx gulp js_bundle_tabs` alone gave
   a file byte-identical to the rbz's (RAN). 8 `gulpfile.js:281-286` and its
   `.gitignore` (`css/lib/*.min.css`) agree (SEEN). §1.2 and §6.1 also
   disagreed about `npm ci` and `npm install`. **Applied:** §1.2 steps 6–8,
   §6.1 and §7.2 build with `npm ci && npx gulp twig_compile`, then
   `npx gulp js_bundle_tabs`. The lockfile is regenerated only when
   `build/package.json` changes, with `npm install --package-lock-only`.
   Every merge is `--no-commit`, so the merge and its bundle are one commit
   and `pre-commit` runs on it. **Added by Claude:** a `pre-merge-commit`
   hook that refuses any merge that commits by itself, so the
   `--no-commit` route is enforced rather than remembered.
2. **The planned `.gitignore` exception cannot re-include `tabs-bundle.js`**
   (major). CONFIRMED (RAN, scratch repo). With `/src/js/bundles/` then
   `!/src/js/bundles/tabs-bundle.js`, `git add src` skipped the file and
   `git check-ignore -v` named line 1. With `/*`, it went in, and
   `check-ignore -q` exited 1. **Applied:** §2.2 and §6.1 use 7.1's
   `bundles/*` shape. §7.2 adds both assertions, and the same pair for
   `build/package-lock.json`.
3. **The updater can print "up to date" while stock 8 runs** (major).
   CONFIRMED by code read of today's stub: HEAD == origin/mcft reads
   "Already up to date" and nothing reads the disk (SEEN). **Applied, with
   two changes:**
   - The integrity check runs FIRST, before the fetch, so a modified clone
     is never fast-forwarded or refreshed over.
   - It records `cksum` (CRC and size) per output instead of size and
     mtime. `cksum` is POSIX, so it is one command on macOS and Linux;
     `stat` differs between them, which would have made a platform branch.
     It reads content, so a harmless touch does not raise a false alarm.
     It ran in under 0.1 s on 57 MB.
   - A missing stamp on a clean tree is an interrupted refresh, and is
     healed by refreshing again. A dirty tree or a changed output stops
     loudly.
   - dev-install's refusal (it is in this design, not in today's script)
     names the re-clone steps, after a bridge read.

   Whether an rbz install writes through the links stays NOT CONFIRMED, as
   the critic said.
4. **A forward-commit undo breaks every later merge, and nothing checks the
   upstream tree** (major). CONFIRMED by reasoning: after a go-back commit,
   the bad build is an ancestor and becomes the next merge base. This is
   git's own "reverting a faulty merge" case. **Applied, and extended:**
   - `docs/mcft/UPSTREAM`, `docs/mcft/MCFT-PATHS`, `tools/check-upstream-tree.rb`
     (check 6, in P, proved on 7.1 first) and the go-back rule in §1.2 and
     §9.1.
   - **Extended:** the merge itself is `-s ours`, and
     `tools/mcft-take-upstream.sh` makes the tree. The critic's fix covered
     non-MCFT paths. The eight upstream files MCFT changes would still have
     been merged against git's base, so they are three-way merged with
     `git merge-file` against the build `UPSTREAM` names. That makes git's
     merge base irrelevant everywhere. In a throwaway worktree this gave
     exactly the MCFT paths as the only difference from 8, and 8 conflict
     hunks in 6 files instead of 64 conflicts (RAN, §2.1).
   - **Done differently:** the check compares object ids from a
     `--depth=1 --filter=blob:none` fetch (52 KiB), not downloaded bytes.
     It fetches only `constants.rb` lazily, to compare the builds (RAN).
5. **Two answers on assembly labour for a Smart-Build-only model**
   (major). CONFIRMED on `mallet_estimator` `main`: `api.py:1433-1438`
   labels any non-empty map `plugin:ASMBL size counts`. `:1444-1455`
   already says `erp:1 + drawer rails (no ASMBL component in model)` when
   the map is absent and the count is 0. The bench's comment shows this was
   its intent. MOP always sends a non-empty map (estimate worker
   `:221-222`, `:441-453`) (SEEN). **Applied** as proposed, plugin-only:
   `assembly_payload`, the walk's numbers handed to the dialog as
   `mcft_assembly_walk`, the warning rendered from them, N4 under the
   bench's own label, and the pins in check-assembly-rule.
6. **The first push is about 1.7 GB, close to GitHub's 2 GB push limit**
   (major). CONFIRMED (RAN): 1,570 commits and 1,721,149,389 bytes not on
   origin. **Applied in §1.3, with one change.** The pieces are chosen by
   measured size along the first-parent history (about six pushes under
   400 MB), not "a few '+ LAB build' commits per push", because only 12 of
   the 1,570 commits carry that title. The verification uses
   `--disk-usage --objects`, since without `--objects` it counts commits
   only. Upstream's workflows are `workflow_dispatch` only, so pushing that
   branch runs nothing (SEEN).
7. **N2 would count at most one Smart Build part** (minor). CONFIRMED in
   the code: SB `:3535` and `:7754`, and 8 `instance_info.rb:30-31` (a
   component part takes its definition's name). SketchUp's renaming to
   `Part#n` is API behaviour, NOT CONFIRMED here. **Applied:**
   `default_part_name?` and check 7.
8. **The refresh test on Linux runs a different command, and `cp -R` nests
   the folder** (minor). CONFIRMED (RAN, GNU `cp`): the plain form made
   `src/ladb_opencutlist/ladb_opencutlist`, and the `/.` form merged into
   the existing folder. All 177 rbz-only files of 8.0.0 fall under an
   ignore rule, checked with a control path that did not (RAN). **Applied:**
   one `cp -R …/. …/` command, `ditto` dropped, and check 5's two new
   assertions. That the `/.` form behaves the same in macOS's BSD `cp` is
   its documented behaviour, NOT CONFIRMED on the Mac.
9. **The smoke test is left as "the bundle if it can, otherwise the
   sources"** (minor). CONFIRMED. **Applied:** the job loads
   common-bundle and `en.js` from the rbz and the committed tabs bundle, and
   fails if one cannot load. Trying it found two things the proposal did
   not say (RAN). They must run as `vm.Script` in jsdom's context, because
   `window.eval` loses the `const`s that common-bundle declares
   (`TOKENFIELD_OPTIONS`). And `dialog-tabs.js` raises one expected jsdom
   error, the `skp:` bridge navigation, which the harness must expect once.
10. **The machining note was wrong** (minor). CONFIRMED: 8
    `cutlist_generate_worker.rb:1132-1133` returns before any part or group
    exists (SEEN). **Applied:** §3.3 rewritten, the decision recorded
    (accept, as for hardware), and the Boolean-cut check added to §6.4
    step 6.
11. **Two choices were left "optional" or conditional** (minor).
    CONFIRMED. **Applied:** the unnamed-module announcement ships, with
    check rows, and N4's rendering is concrete (§4.3). **Done differently
    in one detail:** these groups go in their own key, `unnamed_modules`,
    and do not join `ignored`. `ignored` travels to the bench as `unsized`
    under the words "named ASMBL… but carry no size token", which would be
    false for a group named `Wardrobe 600`.
12. **`IS_RBZ`, not only `IS_LAB`, changes 8's behaviour** (minor).
    CONFIRMED, every use read in 8 (SEEN). Beyond the critic's list, it
    also sets the `rbz`/`src` build tag in URLs, and it feeds two dialog
    conditions that also need `IS_LAB`, so with `IS_LAB` false they are
    inert. **Applied:** §2.3 lists the gates, §2.4 item 3 no longer states
    `IS_RBZ` as fact, and the estimate stamp prints `is_rbz=` (with
    `is_lab=`), read in §6.4 step 6. Check 7 pins the stamp.

Nothing was declined outright. The partial departures are in findings 3, 4,
6 and 11 above, and each is a change to how a fix is done, not to whether it
is done.

---

## 11. As built

Built on 23 Nov 2026 on `mcft8` in `/home/user/mop8`, on top of the design
commits `25581ca7` and `f14e0bf1`. **Everything below is LOCAL: nothing was
pushed**, so no GitHub run exists yet for any of these commits. "Ran" means it
ran in the cloud container (Ruby 3.3, Node 22, Linux). **Nothing ran in
SketchUp**, and nothing ran on a Mac.

### 11.1 The commits

`mcft8` is a fast-forward of `origin/mcft` (`git merge-base --is-ancestor
origin/mcft mcft8` is true). In first-parent order:

| Commit | What it is | Design |
|---|---|---|
| `faa7ed7f` | **P** — `docs/mcft/MCFT-PATHS`, `docs/mcft/UPSTREAM` (= `d03f4548`), `tools/mcft-take-upstream.sh`, `tools/check-upstream-tree.rb` and its CI step, `tools/mcft_paths.rb` (the one reader of the path list), `mcft8` added to the workflow's push branches. Made on the 7.1 tree. | §1.1 step 0 |
| `07da7c32` | **M** — the merge of `c5405bd4` (`8.0.0-lab`, build `202611191727`), with **D** (the all-boards print deleted) and **V** (the version string) folded in. | §1.1 steps 1–3, §2 |
| `94d4de31` | **B** — `tabs-bundle.js` and `build/package-lock.json` tracked, `tabs-twig-templates.js` untracked, the two hooks, the bundle CI job, the smoke test on the bundles. | §6.1, §7.2 |
| `66cd3038` | **U** — `check-mcft-wiring.rb`, `check-upgrade-refused.rb`, `check-build-matches-rbz.rb`, the floor check and `ruby -c` reading the loader, the job renamed "SketchUp 2021". | §7.3 checks 2–4 |
| `adb17a0d` | **A + N** — groups as assemblies, no size map when nothing was counted, the walk's lists and the notes on the slide, the stamp's `is_rbz=`/`is_lab=`, `check-estimate-notes.rb`. | §4, §3, §5, §2.3 |
| `13fdadc7` | **I** — `mcft-refresh-outputs.sh`, `mcft-autoupdate.rb`, the stub, `dev-install-mac.sh`, `check-refresh-outputs.sh` (its own CI job), `check-autoupdate.rb`. | §6.2, §7.3 check 5 |
| this commit | This section. | — |

There is no separate **C** commit: every CI addition landed in the commit
whose code it checks.

The tag `mcft-7.1-final` (annotated, on `6b0ba3e`, "Last MOP on OpenCutList
7.1") exists locally and is not pushed. It must be pushed before `mcft` moves
(§9.2).

### 11.2 What was run, and what it said

**MOP's CI, run job by job as `.github/workflows/mcft-checks.yml` runs it**:
for each job a fresh depth-1 fetch of the commit, each `run:` under `bash
--noprofile --norc -eo pipefail`, the `uses:` steps being the container's own
Ruby 3.3 and Node 22. **Green at every one of P, M, B, U, A+N and I.** At the
tip (`13fdadc7`), every step passed:

- ruby: `ruby -c` (now including the loader and the updater); the floor check
  — `226 files, 0 fatal, 0 warn`; check-requires — all present;
  check-dialog-api — 57 real methods; check-csv-thickness; check-assembly-rule
  — `18 names, 9 kind cases, the payload shape and 7 source rules hold`;
  check-estimate-notes — `11 default-name cases`; check-push-suspended;
  check-mcft-log; check-mcft-wiring — `2 use(s) of McftController in
  plugin.rb, each required first`; check-upgrade-refused; check-build-matches-rbz
  — `build 202611191727 in the rbz, src and manifest; version 8.0.0-lab.mcft.1
  (IS_LAB false)`; check-autoupdate; check-upstream-tree — `1109 upstream
  path(s) equal build c5405bd43`. In the fresh depth-1 checkout the build was
  NOT present, so check 6 fetched it trees-only from GitHub, as CI will.
- smoke: `dialog smoke: all checks passed`, loading `common-bundle.js` and
  `en.js` from the rbz and the committed `tabs-bundle.js` as `vm.Script`s, the
  one `skp:` bridge navigation seen exactly once.
- bundle: the rebuilt `tabs-bundle.js` matches the committed one, sorted; both
  files tracked and not ignored.
- refresh: every assertion of check 5 (below).

**Each new check was proved by breaking it** (all RAN):

| Check | Broken by | Result |
|---|---|---|
| check-upstream-tree (6) | one byte appended to `README.md`; a stray `stray.txt`; a stale `own:` line | each fails, naming the path |
| check-mcft-wiring (3) | the `require_relative` above `setup_menu` deleted | fails, `plugin.rb:1084 (setup)` |
| check-upgrade-refused (4) | the refusal deleted | fails |
| check-build-matches-rbz (2) | version `8.0.0-lab-mcft`; build off by one | each fails |
| check-assembly-rule (1) | a group's definition name read; the size map always sent; the walk's Group clause dropped | each fails |
| check-estimate-notes (7) | `is_rbz=` renamed in the stamp | fails |
| smoke | the 2026-09-03 `this.dialog.stopProgress()` put into the bundle's `mcftRender` | exits 1 |
| pre-commit | a staged `.twig` without the bundle; `build/package.json` without the lockfile | each refused |
| pre-merge-commit | a plain `git merge --no-ff` | refused, HEAD unchanged |

**`tools/mcft-take-upstream.sh` re-run on the tip with the same build**
changed nothing (0 taken that differ, 0 removed, all 7 changed: files "merged
clean", 0 conflict hunks). For the merge itself it reported exactly the design's
numbers: 1,108 taken, 74 removed (75 with the `_slide-cuttingdiagram-2d.twig`
it stopped on, resolved by hand), conflicts in `.gitignore` (2), `plugin.rb`
(2), the loader, `constants.rb`, `build/package.json` and `tab-cutlist.js` (1
each).

**The bundle**: built by `cd build && npm ci && npx gulp twig_compile`, then
`npx gulp js_bundle_tabs`. Against the rbz's own `tabs-bundle.js` (18,378
lines; ours 19,739+), sorted, the only differences are MCFT's added
`tab-cutlist.js` lines and the estimate slide's one template line. It was
built by the repo's own build; it was not edited by hand.

**The install and update, end to end, on Linux with fakes** (a fake `HOME`
with a SketchUp 2026 Plugins folder holding a stock 8 LAB install unzipped
from the rbz; a stub `UI.messagebox`; the CI gate answered locally; an
"origin" repository on disk): `dev-install-mac.sh` replaced the stock install
with the two links and the stub and laid 176 outputs down; then simulated
starts:

1. nothing new — `up to date @ <rev>`, `ok=true … Already up to date.`;
2. a green commit carrying a NEW rbz — fast-forwarded, the refresh laid 177
   outputs down, `--verify` clean, `ok=true … fast-forwarded to <rev>`;
3. a red commit — held, the "HELD BACK" box, nothing moved;
4. a tracked file written through the link — `NOT verified … (10)`, the box
   naming the installer, no fetch;
5. the folder link replaced by a real folder — `OpenCutList in Plugins is NOT
   MOP: ladb_opencutlist`;
6. the stamp deleted — healed by a full refresh, `--verify` clean after;
7. an rbz that `unzip` only warns about — the refresh refused before touching
   `src/`, `reset --keep` put the old HEAD back, "held at <rev>";
8. the updater file missing — the stub said so and named no fallback.

The installer refused a dirty clone and a clone on another branch, printing
the fresh-clone commands. None of this ran on macOS: BSD `cp`, BSD `xargs`,
macOS `unzip`, SketchUp's Ruby and its `UI` are inferred to behave as their
Linux counterparts did (NOT CONFIRMED).

### 11.3 What could only be read (NOT CONFIRMED)

- That OpenCutList (MCFT Edition) LOADS in SketchUp 2026 on 8: the requires
  resolve (check-requires), `McftController` is required before use
  (check-mcft-wiring), and every OpenCutList name MOP calls exists with its
  shape (§2.5, re-read for the new code: `Sketchup::Group#definition`,
  `PLUGIN.get_attribute`, `DefinitionAttributes.role_of` and `ROLE_FRONT_PANEL`,
  `Part#length_increased` / `#width_increased` / `#length_increase` /
  `#width_increase` / `#face_material_names`, `part.def.definition`,
  `MaterialAttributes::TYPE_SHEET_GOOD`, `Plugin::IS_RBZ` / `Plugin::IS_LAB`).
  Requiring `controller/mcft_controller` inside `setup()` loads the MCFT
  workers (and with them `cutlist_generate_worker`) at load time, before 8's
  lazy `start()`; 7.1 MOP did the same from the top of `plugin.rb`, but on 8
  this is read, not run.
- That the estimate slide renders in SketchUp's own browser: the smoke test
  renders it in jsdom from the very bundle SketchUp will load.
- What `IS_RBZ` is for a symlinked install: the stamp now prints it
  (`is_rbz=`), so the first estimate on the Mac answers it.
- Everything in §3 about numbers on 8 (hardware as one part, machining,
  per-part allowance) and §4 about Smart Build groups: code reads of 8. `N1`
  uses `Part#length_increased`, which on 8 is the DEFINITION's own increase
  only (`cutlist_generate_worker.rb:549`), exactly the part-level allowance
  §3.1 is about.
- Whether `Sketchup.install_from_archive` writes through the links (§6.3).
- The `--filter=blob:none` clone on the Mac (§6.2, "Size").

### 11.4 Where this build departs from the design, and why

1. **The tag is `mcft-7.1-final`** (annotated), as §1.1 and §9.2 name it. The
   build instruction said `mcft-7.1-last`; the design's name was kept because
   §9.2's way back refers to it. One tag, not two.
2. **Fewer commits than §1.1 lists.** D and V are folded into M, A and N are
   one commit, and C has no commit of its own. The build instruction required
   every commit to leave MOP's checks green, and M without D is red (the smoke
   test's pack scenario calls a function 8 deleted). V is the conflict
   resolution of `constants.rb` and the loader, so it is part of making M. A
   and N change the same worker and the same slide.
3. **`tab.twig` left `changed:`.** With the all-boards item deleted it equals
   8's file byte for byte, so it is no longer an MCFT-changed file; check 6
   now holds it as upstream's.
4. **The assembly rule lives in `worker/mcft/mcft_estimate_rules.rb`**, not as
   class methods of the worker. The worker requires SketchUp-only files, so a
   check could not load it; the rules file has no SketchUp and no requires,
   and the checks RUN it. The worker keeps no copy of the regex.
5. **The stamp reads `Plugin::IS_RBZ` / `Plugin::IS_LAB`**: on 8 both are
   constants of `class Plugin` (`plugin.rb:26-27`), not of the module, so a
   bare `IS_RBZ` from the worker would not resolve.
6. **`pgrep -x SketchUp > /dev/null`, not `pgrep -xq`**: the redirect means
   the same on macOS and Linux; Linux's procps has no `-q`, so the `-q` form
   could not be run here at all.
7. **Refresh exit codes are 0 / 20 / 21** (done / refused before touching
   `src/` / failed after); §6.2 asked only that they be distinct. `--verify`
   uses 10 / 11 / 12 as designed. An `unzip` WARNING counts as a failure
   before `src/` is touched: refusing costs one restart.
8. **176 rbz-only outputs, not 177**: the tabs bundle is now tracked, so the
   refresh does not lay it down.
9. **Added beyond the design:** `check-upstream-tree.rb --index` (checks what
   is staged, used before committing the merge); `tools/mcft_ruby_source.rb`
   (the one method reader checks 3 and 4 share); `tools/check-autoupdate.rb`
   (the updater's decisions RUN: what each `--verify` and refresh exit means,
   the CI verdicts, the Plugins test, and `run()`'s order read); the updater
   held to the Ruby floor and `ruby -c`; a smoke scenario for the notes that
   also asserts none shows when there is nothing to say; the stamp's `*.tmp`
   ignored.
10. **§2.4's grep "must return nothing"** holds over MCFT's paths (only a
    comment saying the pack is gone matches). Over all of `src`, upstream's own
    files still name `cuttingdiagram2d` (an icon class, deprecated i18n preset
    keys, `_modal-packing.twig`), which are 8's and are not MCFT's to remove.
11. **N2 counts pieces** (the sum of `part.count`), so "3 part(s)" means three
    pieces on the cut list.
12. **The smoke harness** routes the Twig `i18next` filter to the REAL
    `i18next.t` with `en.js`'s strings; the other filters stay stubbed, as
    they were.

**Not done here, because it cannot be done locally:** the pushes (§1.3: the
upstream history in pieces under 400 MB to `upstream-8.0.0`, then `mcft8`;
`git rev-list --disk-usage --objects mcft8 --not --remotes=origin` is
1,722,445,223 bytes today, of which the MCFT commits after P are 1,300,054
bytes), the GitHub runs on the full sha, the tag push, the fast-forward of
`mcft`, and the S7 HUB `bootstrap.sh` change (another repository; it must land
before step 3 below).

**The one question for Amit (§4.2) was built with Claude's recommended
answer**, yes: a Smart Build GROUP named `ASMBL_M_…` counts as a medium
assembly. If he answers no, delete the `:group` clause of
`McftEstimateRules.assembly_size` (and its three kind rows); everything else
in that commit stays.

### 11.5 The one-time steps on Amit's Mac, exactly as he will be given them

Handed over ONE AT A TIME; the next is written only after Amit reports what
the last one did. Before step 1 Claude reads the Mac through the bridge (reads
only): `git -C ~/dev/malletcraft/mcft-opencutlist-sketchup-extension status
--porcelain` and `git -C … log origin/mcft..HEAD --oneline` (anything not on
GitHub must be dealt with first), `git --version` (2.19 or later), and
`ls -la "$HOME/Library/Application Support/SketchUp 2026/SketchUp/Plugins"`.

**Step 1 (S3 MOP), before Claude moves `mcft`.** Quit SketchUp, then in
Terminal:

```sh
rm -f "$HOME/Library/Application Support/SketchUp 2026/SketchUp/Plugins/!mcft_autoupdate.rb"
```

The old startup stub is not an extension, so Extension Manager's uninstall
left it; it still fetches into the old clone on every start. After this,
SketchUp runs stock OpenCutList 8 LAB alone, exactly as today.

*[Claude then pushes upstream's history in pieces, the tag, and `mcft8`;
waits until every workflow run on the tip's full 40-character sha is green;
fast-forwards `mcft`, pushes it and confirms its runs; and lands the S7 HUB
`bootstrap.sh` change.]*

**Step 2 (S3 MOP).** With SketchUp quit:

```sh
rm -rf ~/dev/malletcraft/mcft-opencutlist-sketchup-extension
```

**Step 3 (S3 MOP).**

```sh
git clone --filter=blob:none --branch mcft https://github.com/malletcraft/mcft-opencutlist-sketchup-extension.git ~/dev/malletcraft/mcft-opencutlist-sketchup-extension
```

**Step 4 (S3 MOP).**

```sh
bash ~/dev/malletcraft/mcft-opencutlist-sketchup-extension/tools/dev-install-mac.sh
```

It ends with "Installed. Start SketchUp: …".

**Step 5 (S3 MOP).** Start SketchUp. Before clearing the Ruby Console, read
its line `[MCFT] OpenCutList (MCFT Edition) up to date @ <rev>`, and check
Extension Manager lists "OpenCutList (MCFT Edition)" enabled (enable it if
not). Claude reads the update log through the bridge:
`tail -1 "$HOME/Library/Application Support/mcft-ocl-update.log"` — it should
show `ok=true` and an `outputs=` stamp.

**Step 6 (S3 MOP).** Open a model already estimated on 7.1, run the MCFT
estimate, and say whether it looks like the 7.1 one. Claude reads
`mcft-estimate.log` through the bridge: the stamp line `[MCFT] estimate —
plugin <rev> is_rbz=… is_lab=…` (expected `is_rbz=true is_lab=false`), the
two estimates side by side (the hardware comparison of §3.2), and, on a model
with a Boolean cut, that the cut panel is still in the parts list and the
estimate (§3.3).

After this Amit never uninstalls OpenCutList in Extension Manager, never
clicks OpenCutList's Upgrade (MOP refuses it and says why), never installs an
`.rbz`, and never runs `bootstrap.sh` over this repo. Restarting SketchUp is
the update.
