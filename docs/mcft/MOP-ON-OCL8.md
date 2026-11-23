# S3 MOP on OpenCutList 8 — the design of the move

Written 23 Nov 2026 on branch `mcft8` (cut from `origin/mcft` `6b0ba3e`). It is a
plan, not a record of work done: nothing below has been built yet, and nothing
in it has been run in SketchUp. SketchUp is not available where this was
written. Every sentence about how SketchUp or OpenCutList behaves comes from
reading code, and where it is an inference it says **NOT CONFIRMED**.

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
  `origin/mcft` `6b0ba3e`.
- **Bring 8 in by `git merge upstream/8.0.0`, never by a rebase.** Amit's
  Mac updates by `git merge --ff-only origin/mcft`, so every new `mcft` must
  be a descendant of the old one. A merge commit is a descendant of both
  parents, so `mcft` → `mcft8` is a fast-forward. The 78 MCFT commits are
  not rewritten.
- **Tag the last 7.1 MOP commit before anything moves:**
  `git tag -a mcft-7.1-final 6b0ba3e -m "Last MOP on OpenCutList 7.1"`.
  Push the tag before `mcft` moves. It is the way back (§9.2).
- **The order of the commits on `mcft8`.** Each commit does one thing, so a
  red check names its cause. All are local until §1.3.
  1. **M — the merge.** Resolve the conflicts as in §2.2. The
     extension must LOAD at this commit, so the `McftController` require
     lands here, not later.
  2. **D — delete the all-boards diagram print** (§2.4).
  3. **V — the version string** (§2.3).
  4. **B — track the dialog bundle**: the `.gitignore` exception, the
     committed `tabs-bundle.js`, `build/package-lock.json`, the pre-commit
     hook, and the CI job (§6.1, §7).
  5. **I — the installer, the output refresh and the autoupdater** (§6).
  6. **U — the upgrade refusal and its check** (§6.3, §7).
  7. **A — the assembly rule for groups, and its check** (§4).
  8. **N — the on-screen notes** (§3, §5).
  9. **C — the CI additions not already in B, U or A** (§7).
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
2. Pick the newest "+ LAB build" commit on `upstream/8.0.0`. Never pick the
   branch tip if the tip is not a build commit.
3. On `mcft8`, run `git merge <that sha>`. The conflicts are, in practice,
   only the files MCFT touches (§2.1). Keep MCFT's version and name, and take
   8's build string (§2.3).
4. Rebuild and commit `tabs-bundle.js` with `cd build && npm ci && npx gulp
   twig_compile`, then `npx gulp bundle`. These are two separate invocations
   (§6.1).
5. Push `mcft8`. Wait until **every workflow run on the full 40-character
   sha** is green. Then fast-forward `mcft` to it and push.
6. Amit restarts SketchUp. The autoupdater gates the commit on CI,
   fast-forwards it, and refreshes the build outputs from the new rbz (§6.2).

**When to merge:** Claude merges when Amit asks for a build, or when a LAB
build fixes something that is in his way. There is no fixed cadence. A merge
that no one asked for is a risk for nothing.

**What is never used:** OpenCutList 8's own updater, and its Upgrade button.
MOP refuses that button (§6.3).

**When stable 8.0 is published,** the same procedure merges its tag. The
update check is left on for exactly this reason (§6.3): the orange dot it
shows is the signal for Claude to move MOP onto stable.

### 1.3 Pushing

- `mcft8` may be pushed freely. It is not a branch the Mac fetches, and CI
  runs on it once `mcft8` is added to `mcft-checks.yml` (§7). This is where a
  red build costs nothing.
- `mcft` is fast-forwarded only to a commit that is fully green. It is
  pushed only after Amit has done step 1 of §6.4. Otherwise the old startup
  stub on his Mac would download about 1.6 GB of rbz history into the old
  clone the next time SketchUp starts (§6.2, "Size").

---

## 2. Every MCFT change, carried to 8, file by file

### 2.1 What the MCFT work is

- The MCFT work is `d03f4548..origin/mcft`: 78 commits, 35 files outside
  `node_modules`, +7,732/−591. `d03f4548` is upstream master past 7.1.0.
  (SEEN)
- `git merge-base --all origin/mcft upstream/8.0.0` returns TWO bases,
  `0e27407d` (7.1.0) and `d84715d0` (7.0.0). Git therefore merges through a
  virtual base. That produces conflicts in files MCFT never touched.
- The control: merging bare upstream master `d03f4548` into 8.0.0 gives 63
  conflicts. Merging `origin/mcft` gives 64. The extra one is MCFT's
  `_slide-cuttingdiagram-2d.twig`. (RAN)
- When the 78 commits were replayed onto 8 in a throwaway copy, 72 applied
  cleanly and 6 clashed. The 6 are the files in the "conflicts" rows of §2.2.

### 2.2 The table

| File | What 8 did to it | What it becomes on 8 |
|---|---|---|
| `ruby/worker/mcft/mcft_estimate_worker.rb` | absent in 8, so it merges clean | Unchanged, except the assembly walk (§4) and the notes (§3, §5). Every OpenCutList name it calls still exists in 8 with the same shape (§2.5). |
| `ruby/worker/mcft/mcft_estimate_dialog.rb`, `mcft_estimate_store.rb`, `mcft_pull_worker.rb`, `mcft_create_materials_worker.rb`, `mcft_iso_worker.rb` | absent, merges clean | Unchanged. |
| `ruby/worker/mcft/mcft_push_worker.rb` | absent, merges clean | Unchanged. It is still SUSPENDED and still guarded. The estimate keeps borrowing `parts_csv`, `ocl_totals` and `plugin_rev` from it. |
| `ruby/worker/mcft/mcft_log.rb` | absent, merges clean | Unchanged. It has no OpenCutList dependency. |
| `ruby/controller/mcft_controller.rb` | absent, merges clean | Unchanged. Its wiring in `plugin.rb` is redone (row below). |
| `ruby/plugin.rb` | heavily changed (+549/−189): controllers load lazily inside `start()`, a new `Updater` class, a new menu loop. Conflicts. | Take 8's file. Then re-place MCFT's three hunks. **(1)** Add `require_relative 'controller/mcft_controller'` inside 8's lazy block (8:1167-1180), and `@controllers.push(McftController.new)` after `HardwareController`. **(2)** The menu hunk `McftController.new.setup_menu(submenu)` merges by itself into 8's `setup()` (8:1074-1077). But `setup()` runs at load time, BEFORE `start()` has required anything, so it needs its own `require_relative 'controller/mcft_controller'` on the line just above it. That is 8's own pattern for the smart tools (8:1060). Without that line, a `NameError` stops the whole extension at load, and CI as it stands stays green (§7, new check 3). **(3)** The upgrade refusal merges by itself to the top of 8's `upgrade_command` (8:1695) (§6.3). **Also:** drop MCFT's old top-level requires. 7.1's `importer_controller` no longer exists in 8. |
| `src/ladb_opencutlist.rb` (the loader) | +13/−8. Conflicts. | 8's file, with three MCFT additions: the name `OpenCutList (MCFT Edition)`; the version line with MCFT's private `##` marker, so gulp's `version` task never rewrites it; and the SketchUp 2021 floor, `Sketchup.version_number < 2100000000` (8 gates only at 2017). |
| `ruby/constants.rb` | version `8.0.0-lab`, build `202611191727`, languages `bg`/`ro` added and `ar`/`sr` removed. Conflicts. | 8's file with `EXTENSION_NAME 'OpenCutList (MCFT Edition)'` and the MCFT version (§2.3). **`EXTENSION_BUILD` stays upstream's, byte for byte** (§2.3). |
| `js/plugins/tabs/jquery.ladb.tab-cutlist.js` | +227/−1,227. Conflicts. | Take 8's side of the four 8-only hunks (`$selectRectangleLeftoverMode`, the `use_pre_process`/`write_*` inputs, `SELECT_PICKER_TABS_OPTIONS`, a semicolon). These MCFT hunks merge clean: the menu-item handle (7:61, 185), the 1,332-line estimate block (7:1351-2682), the hook into the estimate slide (7:2725-2743, which lands inside 8's `generateEstimate` → `fnCreateSlide`), and the `mcft_estimate_ready` / `mcft_materials_created` callbacks (7:8098-8107). The pack hunk (7:6886-7028) sits inside the legacy 1D/2D block that 8 deleted. Take 8's side there, then delete the rest of the pack (§2.4). |
| `twig/tabs/cutlist/_slide-cuttingdiagram-2d.twig` | deleted by 8 (`ec4deb0f`). modify/delete conflict. | `git rm`. |
| `twig/tabs/cutlist/_cuttingdiagram-2d-body.twig`, `_slide-mcft-diagram-pack.twig` | absent. They merge clean, but are dead on 8: they render the deleted engine's `sheets` and 41 `tab.cutlist.cuttingdiagram.*` keys that 8 no longer has. | Deleted (§2.4). |
| `twig/tabs/cutlist/_slide-estimate.twig` | 3 button-label lines changed. Merges clean. | As merged. |
| `twig/tabs/cutlist/tab.twig` | unchanged in 8. Merges clean. | The "Cutting diagrams — all boards" item is removed (§2.4). |
| `js/templates/tabs-twig-templates.js` (a tracked build output) | — | **No longer tracked.** On 8 it is only an input to `tabs-bundle.js` and is not loaded by itself. One delivered output, not two (§6.1). |
| `js/bundles/tabs-bundle.js` (8's build output) | new in 8, and gitignored | **Tracked on `mcft`**, through a `.gitignore` exception (§6.1). |
| `.gitignore` | changed. Conflicts in three hunks. | Hunk 1: keep 8's new ignores (`css/vendor.min.css`, `js/bundles/`) plus `!/src/ladb_opencutlist/js/bundles/tabs-bundle.js`, and ignore `js/templates/` whole. Hunk 2: take 8's `*~.skp`, which covers MCFT's `/docs/skp/*~.skp`. Hunk 3: keep both 8's lines (`tools/python/*.dxf`, `CLAUDE.md`, `.claude`, `.idea/`) and MCFT's `extension_info.txt`, `*.susig`. Also add `!/build/package-lock.json` and `/src/ladb_opencutlist/.mcft-outputs`. 8 ignores `CLAUDE.md`, so a CLAUDE.md in this repo needs `git add -f`. |
| `build/package.json` | version and dependency bumps. Conflicts. | 8's file, with `"jsdom": "^30.0.1"` re-added (the smoke test needs it). |
| `build/package-lock.json` | gitignored in both 7 and 8 | **Tracked on `mcft`** (§6.1). |
| `tools/check-*.rb` (7), `.githooks/pre-commit`, `.github/workflows/mcft-checks.yml`, `test/smoke/*`, root `package.json` / `package-lock.json` / `node_modules/` | absent, merge clean | Kept, with the changes in §7. The smoke test's diagram-pack block is deleted together with the pack. |
| `tools/dev-install-mac.sh` | absent, merges clean | Rewritten (§6.2). |
| Translations | MCFT added none. Its strings are hard-coded English. | Nothing to carry. |

**The 57 conflicts that are not MCFT's** are virtual-base noise: kuix, the
manipulators, the smart tools, Packy, css/woff, the make-c-libs workflows,
CHANGELOG, the rbz, and four modify/delete files (`smart_axes_tool_new.rb`,
the 1D and 2D cutting-diagram workers, `_modal-cuttingdiagram-2d.twig`).

- Resolution: take `upstream/8.0.0` for every one, and `git rm` every path
  8 deleted. This is right because upstream master equals 7.1.0 everywhere
  except 5 files (the make-c-libs workflow split, CHANGELOG, the rbz,
  `docs/json/tutorials.json`), and 8.0.0 already supersedes all 5.
- The check after the merge (RAN in the trial): `git diff --name-only
  upstream/8.0.0`, minus the MCFT files in the table, must be EMPTY. Every
  other path must be 8's, byte for byte. The merge commit message records
  this.

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
- **The `.mcft.N` suffix increases with each MCFT release made on one
  upstream build.** When a new LAB build is merged, the number stays where it
  is. The build string is what identifies the upstream build.
- **`EXTENSION_BUILD` is never changed from upstream's.**
  - The dialog's JS `common-bundle.js` comes from the rbz, and it carries
    `js/constants.js` with upstream's build.
  - When the Ruby build and the JS build differ, the dialog locks itself into
    upstream's "zzz" layout (8 `jquery.ladb.dialog-tabs.js:801-816`, SEEN).
  - 7.1 MOP already follows this rule (`202511301621`). A CI check enforces
    it (§7, new check 2).

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
3. `time_limit` is forced to 300 s whenever `IS_RBZ` is true (`:289`). It is
   true on Amit's Mac, because the linked folder sits under Plugins. So a
   pack would take minutes, not seconds (inferred, not run).
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
  `_slide-mcft-diagram-pack.twig`.
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
  - Types 1–6 are unchanged. 8 adds `TYPE_MACHINING = 7`.
  - `initialize` gains an optional `defaults_type = nil`.
  - MOP's `_material_type_name` (push `:374`) maps types 1–5.
- **`Controller`, `register_command`, `add_event_callback`, `trigger_event`,
  `core_get_model_preset`**: unchanged in shape. Only their line numbers
  moved.
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

MOP sends `estimate_preview` four things (SEEN, estimate worker `:210-246`):

- a parts CSV with one row per OpenCutList part, carrying each part's
  FINISHED length and width, the board thickness for sheet goods, the edge
  and face material names, and a `Tags` column;
- the assembly counts from its own walk;
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
it is walked (8 `:1137-1151`; the bounds helper `:27` excludes it too). 7
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

### 3.3 Machining

8's new `TYPE_MACHINING` (7) is excluded from the cut list (8 `:1132-1134`).
If such a group ever reaches MOP, the existing skipped-group warning
(push `:216-222`) names it. Nothing to change.

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
  - Its instance name is the library file's basename (SB `:2063`).
  - Saving to My Library proposes the definition name as the file name. So a
    component `ASMBL_M_WAR`, once saved and placed, comes back as a GROUP
    named `ASMBL_M_WAR`.
  - The group's definition is SketchUp's `Group#n`.
- **MOP's walk** (`_assembly_counts`, estimate worker `:399-440`) starts with
  `next unless e.is_a?(Sketchup::ComponentInstance)`. That line runs before
  the visibility test and before the "ignored" list. So a module named
  `ASMBL_M_…` is dropped SILENTLY, and is not even listed as ignored.

**A correction to the earlier report:** the result is NOT zero labour.

- MOP sends every size as 0.
- The bench's `apply_assembly_count` returns early on 0
  (`estimate_pdf.py:236-237`).
- So ERP's own rule stands for the seven steps that follow the assembly
  count: 1 + drawer rails.
- The bench still LABELS that figure "plugin:ASMBL size counts"
  (`api.py:1433-1438`).

So a Smart-Build-only model is priced by ERP's guess, under a badge saying
the plugin counted. That is wrong and mislabelled. The label is bench code
and is not changed here (§0.5). The plugin-side answer is note N4 in §4.3.

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
is priced by ERP's guess under the plugin's badge. It is the one question
in this design for Amit: "Does a Smart Build GROUP named `ASMBL_M_…` count
as a medium assembly, exactly as a component does? Claude recommends yes."
Commit A is built with that answer. If Amit says no, A is dropped, and N4
(§4.3) still ships.

### 4.3 The code

In `mcft_estimate_worker.rb`, extract a pure function with no `Sketchup`
constants:

```ruby
# kind: :component or :group. Returns 'large' | 'medium' | 'small', or nil.
def self.assembly_size(kind, instance_name, definition_name)
  names = kind == :group ? [instance_name.to_s] : [instance_name.to_s, definition_name.to_s]
  name  = names.find { |n| ROOT_ASSEMBLY_RE.match(n) }
  name && SIZE_OF[ROOT_ASSEMBLY_RE.match(name)[1].upcase]
end
```

In the walk:

- Admit both kinds: `next unless e.is_a?(Sketchup::ComponentInstance) ||
  e.is_a?(Sketchup::Group)`.
- Keep the image check for components only.
- Run the visibility test first, as now.
- Then call `assembly_size(kind, e.name, (kind == :component ? d.name : ''))`.
- The ASMBL-ish "ignored" check uses the same names list, so a group named
  `ASMBL_WAR` with no size token is listed as ignored, not dropped.
- `McftLog.say` prints `kind=group|component` on each line.

**N4, the plugin's own statement:**

- When the walk counts no assembly, the estimate slide says: "No assembly at
  the top of this model: an assembly is a component or group named ASMBL_L_,
  ASMBL_M_ or ASMBL_S_. ERP priced the seven assembly steps by its own rule."
- It is shown only when the walk's `top_level` is false.
- If the dialog already says this in other words, N4 replaces those words.
  It does not add a second line saying the same thing.

**Optional, and recommended:** a top-level Group whose definition carries
`ladb_opencutlist/stretch_cutters`, but whose name has no size token, joins
`ignored`. Then an unnamed module is announced. It is still not counted, and
it does not serve as a marker by itself, because Smart Reshape writes the
same key (SB `:516`, `:1767`).

**The hazard to tell Amit, once:** wrapping an ASMBL component in an UNNAMED
group (for example, to make a cavity) hides it at depth 2, and it counts 0.
It is not needed, because a component can be the cavity container.

### 4.4 The test that pins it

`tools/check-assembly-rule.rb` loads the worker's pure function, as it
already loads the regex, and asserts:

| kind | instance name | definition name | expected |
|---|---|---|---|
| component | `''` | `ASMBL_M_WAR` | medium |
| component | `ASMBL_L_X` | `Part` | large (unchanged) |
| group | `ASMBL_M_WAR_600` | `Group#12` | medium |
| group | `''` | `ASMBL_M_WAR` | nil (a group's definition name is not read) |
| group | `Part` | `Group#3` | nil |
| group | `ASMBL_WAR` | `''` | nil, and ignored |
| group | `mcft_asmbl_s_loft` | `Group#1` | small (the existing case-insensitive `MCFT_` prefix) |

It also keeps today's 18 name cases. Two source assertions go with it:

- `_assembly_counts` iterates its scope with `each` and calls no
  `.entities` (no descent).
- The visibility test comes before naming, for both kinds.

The check must be proved by breaking it: drop the `Sketchup::Group` clause,
and at least the two group rows must fail.

---

## 5. Smart Build parts: no tag, no edge band, named "Part"

**What 8 makes (SEEN):** Smart Build's dividers, fronts and backs, and
Paneling's panels, are ComponentInstances.

- They are named with 8's default part name, which is "Part" in English
  (SB `:3535`, `:7754`).
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
  - **N2:** "<n> parts still carry OpenCutList's default name". The test
    compares the name against
    `PLUGIN.get_i18n_string('default.part_single').capitalize`, not the
    literal "Part", because the default name is translated.
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
  `js/bundles/tabs-bundle.js` and `js/i18n/<lang>.js`.
- `tabs-bundle.js` concatenates every tab plugin (`tab-cutlist.js` among
  them), the compiled twig templates, `dialog.js` and `dialog-tabs.js`
  (8 `build/gulpfile.js` `TABS_JS_FILES`, task `js_bundle_tabs`).
- 8 gitignores `js/bundles/`.
- So with the rbz's stock bundle, MOP's Ruby would load, but the estimate
  slide and the MCFT buttons would not be there. Nothing would say why.
  This is the 3 Sep 2026 fault again, made worse.

**The fix:**

- **Track `src/ladb_opencutlist/js/bundles/tabs-bundle.js`** through a
  `.gitignore` exception. It becomes the ONE delivered MCFT build output.
  `tabs-twig-templates.js` stops being tracked (§2.2).
- **Build it by two invocations, never chained:**
  ```sh
  cd build && npm ci && npx gulp twig_compile
  npx gulp bundle
  ```
  `twig_compile` starts an asynchronous `del()` and returns only its last
  stream, so a series that chains it into `bundle` can race (SEEN).
  `bundle` rebuilds all four bundles. Only `tabs-bundle.js` is committed.
- **Track `build/package-lock.json`.**
  - Neither branch has one, so `npm ci` stops with EUSAGE (RAN).
  - With `npm install`, the tree is whatever the registry serves that day:
    a newer uglify re-minified `common-bundle.js`, and a newer less wrote
    invalid CSS (`margin-bottom:1.25rem/2`) (RAN).
  - The tabs bundle is plain concatenation and came out byte-identical to
    the rbz's (RAN). But a CI compare that depends on the registry's mood is
    a check that will go red for no reason, and then get deleted.
  - So the lockfile is committed on `mcft`, CI uses `npm ci`, and every LAB
    merge regenerates it with `npm install` in the same commit.
- **Take every other output from the rbz, never from a local build:**
  `common-bundle.js`, the modal and viewer bundles, the css, the html
  dialogs, i18n, and the ten native engines (Clippy, Imagy, Meshy, Packy and
  Skpy, as a `.dylib` and a `.dll` each).
  - MOP touches none of them.
  - The native engines cannot be built here: upstream's make-c-libs is
    `workflow_dispatch` on a macOS runner.
  - If MOP ever adds i18n keys, `js/i18n` must be built and tracked in the
    same commit. Until then, MOP's strings stay hard-coded English.
- **Verified** (RAN): the targeted build gave a `tabs-bundle.js`
  byte-identical to the one in 8's rbz (128 templates, 18,378 lines). So the
  build route reproduces upstream's.

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

**The new pieces, all tracked in the repo:**

1. **`tools/mcft-refresh-outputs.sh [--if-stale]`** is the ONE
   implementation of "make the build outputs on disk match HEAD". Both the
   installer and the autoupdater call it. In order:
   1. `--if-stale` stops at once if the stamp
      `src/ladb_opencutlist/.mcft-outputs` already holds
      `git rev-parse HEAD:dist/ladb_opencutlist.rbz`. This makes the call
      cheap, and it also heals a refresh that was interrupted.
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
      `src/`: every old output, 7.1's dylibs, the `.susig` and
      `extension_info.txt`. Nothing Amit owns lives under `src/`: the
      estimate log and the update log are in Application Support (SEEN).
   6. Run `ditto "$tmp/ladb_opencutlist" src/ladb_opencutlist`.
   7. Write the stamp (gitignored): the rbz blob id, then the build.

   It exits with a distinct code for each of three outcomes: failed before
   touching `src/`, failed after touching it, and done.

2. **`tools/mcft-autoupdate.rb`** is the update logic, loaded from the clone
   on every start (the S4 MDT pattern, `dev/load_from_checkout.rb`). Changes
   to the updater then reach the Mac with no re-install. The code that runs
   is the current HEAD's, and that commit has already passed the gate. In
   order:
   1. Fetch, then the CI gate, then `merge --ff-only`, exactly as today.
      Today's gate reads the runs whose name starts with `MCFT checks` for
      the target sha, and refuses `pending` and `unknown`.
   2. Then `mcft-refresh-outputs.sh --if-stale`. This runs before
      OpenCutList loads, so no dylib is loaded yet: the `!` name makes the
      stub load first.
   3. **If the refresh fails before touching `src/`** (a bad rbz, or the
      three builds disagree), run `git reset --keep <the HEAD before the
      fast-forward>`. That puts back the source that matches the outputs
      still on disk. Then a messagebox says "held at <rev>: <reason>", and a
      line goes in the log. The next start tries again.
   4. **If it fails after touching `src/`** (for example, a full disk), a
      messagebox names ONE command, to run with SketchUp quit:
      `bash ~/dev/malletcraft/mcft-opencutlist-sketchup-extension/tools/dev-install-mac.sh`.
   5. **Check what will actually load.** `Plugins/ladb_opencutlist` and
      `Plugins/ladb_opencutlist.rb` must both be symlinks that resolve into
      this clone (`File.symlink?`, `File.realpath`). If not, say so loudly:
      "OpenCutList in Plugins is not MOP — an .rbz install or OpenCutList's
      Upgrade replaced it. Quit SketchUp and run: <the install command>".
      This closes the blind spot where the stub prints "up to date" while
      nothing loads the clone.
   6. Print `[MCFT] OpenCutList (MCFT Edition) up to date @ <rev>`, and
      append `ok=… rev=… outputs=<stamp>` to
      `~/Library/Application Support/mcft-ocl-update.log`.
   7. **Every failure message names the install script, never `git pull`.**
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
      HEAD, so HEAD must be the published commit.
   3. In Plugins, `rm -rf` four paths: `ladb_opencutlist`,
      `ladb_opencutlist.rb`, `ladb_opencutlist.upgrade_backup` and
      `ladb_opencutlist.rb.upgrade_backup`. The last two are 8's updater
      backup names. `rm` removes a link, not its target. This also removes
      8 LAB's real folder and file.
      `~/Library/Application Support/OpenCutList` is left alone. It holds
      8's `upgrade.log` and asset library, which MOP on 8 shares, because
      the plugin id is the same.
   4. Run `tools/mcft-refresh-outputs.sh` (not `--if-stale`).
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

- Merging `upstream/8.0.0` brings 233 commits that touch the rbz: about
  1.57 GiB packed, out of 1.60 GiB of new objects.
- Today's stub FETCHES FIRST and gates afterwards. So the first start after
  `mcft` moves would pull about 1.6 GB into the old clone, at startup,
  whether CI is green or not.
- After that, each LAB rbz is about 7 MB packed.
- Hence a fresh PARTIAL clone (§6.4, step 4), and the old stub removed
  before the push (§6.4, step 1).
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
  symlink. Whether SketchUp then writes THROUGH it into the clone (dirtying
  the clone, so the next fast-forward fails) or replaces the link is
  unknown.
- Either way, stock 8 replaces MOP.
- `IS_RBZ` is `PLUGIN_DIR.start_with?(<Plugins>)`, with `PLUGIN_DIR` built
  from the loader's `__FILE__` (8 `src/ladb_opencutlist.rb:18`). It is true
  if `__FILE__` is the link path (likely), and false if it is the resolved
  path (NOT CONFIRMED).

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
- A new check pins the refusal (§7, new check 4). Nothing checks it today.

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

*[Claude builds §1.1's commits on `mcft8`, pushes `mcft8`, waits until every
workflow run on the tip's full sha is green, fast-forwards `mcft`, pushes it,
and confirms the runs on `mcft` too.]*

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
MCFT estimate, and says whether it looks like the 7.1 one. Claude compares
the two from `mcft-estimate.log` through the bridge, then raises the §3.2
hardware comparison if the figures differ.

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

- **Triggers:** add `mcft8` to the `push` branches. Red on `mcft8` is free.
- **The Ruby floor stays at Ruby 2.7 / SketchUp 2021** (Amit, 2026-08-24).
  - 8 sits under it: check-ruby-floor on the untouched 8.0.0 tree gave
    "214 files, 0 fatal, 0 warn" (RAN). Spot greps of 8's Ruby find no
    syntax newer than 2.2.
  - **The check now also scans the loader**, `src/ladb_opencutlist.rb`, and
    so does the `ruby -c` loop. Both read only `ruby/**`, and a parse error
    in the loader takes down the whole extension.
  - The job title "parses on SketchUp 2017" becomes "parses on SketchUp 2021".
- **The templates job becomes "Committed dialog bundle matches its source"**:
  - `npm ci`, then `npx gulp twig_compile`, then `npx gulp bundle`, as two
    invocations.
  - Then a SORTED compare of `js/bundles/tabs-bundle.js` against the
    committed file, as today's compare of the template bundle. This is the
    failure of 2026-09-03: a twig or tab JS edit committed without its
    output.
  - The error names the two commands to run.
- **The smoke job loads what SketchUp loads, where it can.**
  - It runs the committed `tabs-bundle.js` in jsdom, instead of the source
    files, if it can provide `common-bundle.js`'s libraries from
    `build/node_modules`.
  - If it cannot, it keeps loading the sources, and the bundle job above
    guarantees the bundle equals them. NOT CONFIRMED which of the two it
    will be.
  - The diagram-pack block is deleted.
  - It is proved by breaking it: reintroduce the 2026-09-03 TypeError, and
    it must fail.
- **The pre-commit hook** refuses a commit that stages a `.twig`, any file
  in `TABS_JS_FILES`, or `build/package.json`, but does not stage
  `js/bundles/tabs-bundle.js` (and, for `package.json`, the lockfile).

### 7.3 New checks

1. **`check-assembly-rule.rb` extended** with the group cases and the two
   source assertions (§4.4).
2. **`tools/check-build-matches-rbz.rb`.** The rbz's
   `ruby/constants.rb` `EXTENSION_BUILD`, `src/ladb_opencutlist/ruby/constants.rb`
   `EXTENSION_BUILD` and `dist/manifest.json`'s `build` are all equal. This
   is the "zzz" trap of §2.3, and also the guard against a merge that took a
   mid-week upstream commit (§1.2). It also checks two things about the
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
   against a throwaway copy of the checkout, on Linux. `ditto` is macOS-only,
   so the script takes `cp -R` when `ditto` is absent. That is the same
   operation, not a fallback path, and it is the only difference. The check
   asserts three things: every tracked file is byte-identical after the
   refresh; a planted stale `bin/osx/lib/libPacky.dylib`, `.susig` and
   `extension_info.txt` are gone; and the stamp is written. It also runs the
   refresh once with a planted build mismatch, and asserts that the script
   refuses without touching `src/`.

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
  and on 8 alike. N4 (§4.3) now says so on screen. Naming generated
  assemblies `ASMBL_<size>_<article>` is a separate S4 MDT change, to be
  offered to Amit on its own.
- Whether PB4 hardware posts collapse under 8's hardware rule (§3.2) is NOT
  CONFIRMED. It is the same Mac check.

---

## 9. Risks, and the way back to 7.1

### 9.1 Risks

| Risk | How likely | What contains it |
|---|---|---|
| A LAB build breaks a drawing tool or the cut list | real; Amit accepted it | Claude merges only "+ LAB build" commits and only on request (§1.2). A bad build is undone by a forward commit that merges nothing new: Claude points `mcft` at a tree equal to the last good merge (a commit on top, never a reset). §9.2 is the last resort. |
| A LAB build changes an OpenCutList API MOP calls | low per build; certain over months | `check-requires`, `check-dialog-api` and the smoke test catch a rename at merge time, on `mcft8`. A change of meaning (as §3.2) is caught only by reading the CHANGELOG of each merged build. Claude reads it for every merge and lists anything touching the cut list in the merge commit. |
| The dialog shows stock 8 with no estimate | would be certain without §6.1 | The tracked bundle, the bundle CI compare, the pre-commit hook. |
| A build mismatch between the outputs and the source | each LAB merge | The refresh at start, the three-way build check (§6.2, §7.3 check 2), `reset --keep` on failure. |
| Amit clicks Upgrade, or installs an `.rbz` | low | The refusal (§6.3) and its check. The stub's "what will load" test says loudly when Plugins no longer points at the clone. |
| Extension Manager acts on the symlinks | unknown | Amit is told never to uninstall there. The installer repairs any state (step 4 can always be re-run). |
| `bootstrap.sh` pulls MOP around the gate | real | The S7 HUB fix (§6.4), before step 3. |
| Smart Build models are priced by ERP's guess under the plugin's badge | certain without §4 | The group rule (§4) and N4. |
| Sheet parts priced without a part's own allowance | only if a part carries one | N1 says so. |
| Hardware counts differ from 7.1 on the same model | possible on PB4 carcasses | The Mac check (§3.2, §6.4 step 6). |
| The 1.6 GB fetch at startup | certain if step 1 is skipped | Step 1 before the push, and the partial clone. |
| A model drawn in 8 is opened in 7.1 | only on the way back | See §9.2. |

### 9.2 Going back to MOP on 7.1

The last 7.1 MOP commit stays tagged `mcft-7.1-final` (`6b0ba3e`). It is
pushed before `mcft` moves. History on `mcft` is never rewritten, so going
back is done by a commit on top, not a reset:

1. **Claude builds the commit.** On `mcft`, run `git read-tree -u --reset
   mcft-7.1-final`, then check out from the 8 line: `tools/mcft-refresh-outputs.sh`,
   `tools/mcft-autoupdate.rb`, the new `tools/dev-install-mac.sh` and the new
   checks. Commit with the message "Back to MOP on OpenCutList 7.1: <why>".
   The tree is 7.1's code, 7.1's rbz and 7.1's tracked template bundle,
   together with the tooling that knows how to refresh outputs. The
   refresh's build check holds, because 7.1's rbz and 7.1's `constants.rb`
   agree.
   - The `.gitignore` must go back to tracking `tabs-twig-templates.js`.
   - The CI templates job must go back to 7.1's compare. 7.1 has no
     `js/bundles/`.
   - The commit is built on `mcft8` first, and proved green there.
2. **Amit restarts SketchUp.** The autoupdater gates the commit and
   fast-forwards it. The refresh sees a new rbz blob, clears 8's outputs,
   and lays 7.1's down. MOP 7.1 loads.
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
   If the clone itself is gone, steps 2 to 5 of §6.4 rebuild it, at
   whatever `mcft` holds.

### 9.3 What is NOT in this move

- No bench change, of any kind.
- No rebuilt all-boards diagram print (§2.4).
- No i18n for MOP's own strings.
- No change to the suspended push path. It is still SUSPENDED, still
  guarded, and still not deleted.
- No S4 MDT change (§8).
- The S7 HUB `bootstrap.sh` fix (§6.4) is its own change in its own
  repository.
