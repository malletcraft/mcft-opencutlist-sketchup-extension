// HEADLESS SMOKE TEST for the cutlist tab's MCFT actions.
//
// Why this exists. On 2026-09-03 the "Cutting diagrams — all boards" feature
// shipped calling two methods that have never existed — dialog.stopProgress
// and dialog.advanceProgress — and the only thing that found them was Amit
// clicking the button and getting a red TypeError. `node --check` parses;
// tools/check-dialog-api.rb now checks names statically; NEITHER runs the
// code. This does.
//
// THE ONE DESIGN DECISION THAT MAKES IT WORK: the fake dialog is built from
// the REAL LadbAbstractDialog.prototype, not hand-written. A hand-written stub
// would have had a stopProgress on it — because I would have written whatever
// the code appeared to need — and the test would have passed while the plugin
// crashed. Only methods that genuinely exist are stubbed; anything else throws
// exactly as SketchUp's browser does.
const fs = require('fs');
const path = require('path');
const { JSDOM } = require('jsdom');

const ROOT = path.resolve(__dirname, '../..');
const SRC = path.join(ROOT, 'src/ladb_opencutlist');
const read = (p) => fs.readFileSync(path.join(SRC, p), 'utf8');

const failures = [];
// AN ERROR INSIDE A CALLBACK MUST FAIL THE RUN, and this is the harness's
// most important property rather than a detail. jsdom LOGS an exception thrown
// inside a requestAnimationFrame callback and carries on, so the first version
// of this file printed a ReferenceError stack and then reported "no exception
// thrown — all checks passed". The bug this test exists to catch
// (dialog.stopProgress) throws in exactly that position, so without this the
// whole thing would have been theatre.
const uncaught = [];
const check = (ok, what) => {
  console.log(`  ${ok ? 'ok  ' : 'FAIL'}  ${what}`);
  if (!ok) failures.push(what);
};

const dom = new JSDOM('<!doctype html><html><body><div id="tab"></div></body></html>', {
  runScripts: 'outside-only',
  pretendToBeVisual: true,
  virtualConsole: new (require('jsdom').VirtualConsole)()
    .on('jsdomError', (e) => uncaught.push(e.detail || e))
    .on('error', (...a) => uncaught.push(a.join(' '))),
});
const win = dom.window;
win.addEventListener('error', (e) => uncaught.push(e.error || e.message));
win.addEventListener('unhandledrejection', (e) => uncaught.push(e.reason));

// EXACTLY WHAT SKETCHUP LOADS, in the order 8's twig/dialog-tabs.twig loads it
// (lines 19-21): common-bundle.js and js/i18n/en.js out of the rbz — they are
// build outputs MOP takes from the rbz on the Mac too — and the COMMITTED
// tabs-bundle.js, which is the file MOP delivers. Not the sources: on 8 no
// source file reaches the screen except through that bundle, so a harness that
// read the sources would pass while the bundle SketchUp loads was stale.
// Any of the three failing to load fails the run.
//
// Each runs as a vm.Script in jsdom's own context, which shares top-level
// const/let between scripts the way separate <script> tags do. window.eval
// does not: an indirect eval keeps each script's consts to itself, and the
// tabs bundle then dies on TOKENFIELD_OPTIONS, which constants.js declares
// inside common-bundle.
const { execFileSync } = require('child_process');
const vm = require('vm');
const RBZ = path.join(ROOT, 'dist/ladb_opencutlist.rbz');
const fromRbz = (p) => execFileSync('unzip', ['-p', RBZ, `ladb_opencutlist/${p}`],
                                    { maxBuffer: 64 << 20 }).toString('utf8');
const ctx = dom.getInternalVMContext();
[['common-bundle.js (rbz)', () => fromRbz('js/bundles/common-bundle.js')],
 ['tabs-bundle.js (committed)', () => read('js/bundles/tabs-bundle.js')],
 ['i18n/en.js (rbz)', () => fromRbz('js/i18n/en.js')]].forEach(([name, src]) => {
  try {
    new vm.Script(src(), { filename: name }).runInContext(ctx);
  } catch (e) {
    console.error(`::error::smoke: ${name} did not load — ${e.message}`);
    process.exit(1);
  }
});

// SCAFFOLDING, and named as such. The real Twig filters are registered inside
// LadbAbstractDialog.prototype.init, which also wires settings, the DOM and
// the SketchUp bridge — far more than this harness can or should stand up. The
// filters are stubbed to pass their value through (i18next to the REAL
// i18next, with the real English strings from en.js); they affect wording,
// never whether a template resolves or a method exists, which is what is
// under test.
win.eval(`
  try { Twig.extendFilter('i18next', function (v) { return i18next.t(v); }); } catch (e) {}
  ['url_beautify','format_currency','sanitize_links','trim_tilde',
   'type_of','sanitize_html','number_format','format_infinite',
   // twig.js's own date() cannot resolve a timezone under jsdom; the estimate
   // does not depend on a formatted date, only the slide chrome does.
   'date'].forEach(function (f) {
    try { Twig.extendFilter(f, function (v) { return v === undefined ? '' : v; }); } catch (e) {}
  });
  ['blend_colors','mesure_text','measure_text'].forEach(function (f) {
    try { Twig.extendFunction(f, function () { return 0; }); } catch (e) {}
  });
`);
win.eval('window.Noty = function () { return { show: function () {}, close: function () {} }; };');

// THE REAL DIALOG PROTOTYPE, so a missing method stays missing. The tab file
// is an IIFE and keeps LadbTabCutlist as a closure const; it is reachable only
// where the plugin publishes it, on $.fn.ladbTabCutlist.Constructor, which is
// also how the real dialog gets at it.
const TabCutlist = win.jQuery.fn.ladbTabCutlist &&
                   win.jQuery.fn.ladbTabCutlist.Constructor;
if (!TabCutlist) {
  console.error('::error::smoke: the cutlist tab plugin did not register');
  process.exit(1);
}

const realDialogMethods = Object.keys(win.LadbAbstractDialog.prototype);
check(realDialogMethods.length > 20,
      `dialog prototype loaded (${realDialogMethods.length} methods)`);

// ---------------------------------------------------------------------------
// The bench: canned Ruby responses for the commands the estimate calls.
const GROUPS = [
  { id: 'g16', material_name: 'SG_PLY_V0_a_a', material_type: 2, part_count: 6,
    std_dimension: '2440 x 1220 x 16', show_cutting_dimensions: false,
    show_edges: false, show_faces: false, parts: [] },
  { id: 'g12', material_name: 'SG_PLY_V0_a_a', material_type: 2, part_count: 3,
    std_dimension: '2440 x 1220 x 12', show_cutting_dimensions: false,
    show_edges: false, show_faces: false, parts: [] },
  // Not a sheet good: must be skipped rather than packed.
  { id: 'ghw', material_name: 'HWD_Hinge', material_type: 5, part_count: 4,
    std_dimension: '', parts: [] },
];

const calls = [];
// The PARAMS too, not only the names. Scenario 3 asserts what the estimate
// buttons send, and the bug it guards against lives entirely in a parameter.
const sent = [];
win.rubyCallCommand = function (name, params, cb) {
  calls.push(name);
  sent.push({ name: name, params: params });
  const reply = (r) => { if (typeof cb === 'function') cb(r); };
  switch (name) {
    case 'core_get_model_preset':
      return reply({ preset: { std_sheet: '2440x1220', saw_kerf: '3mm' } });
    default:
      return reply({});
  }
};

// ---------------------------------------------------------------------------
const $ = win.jQuery;
const tab = Object.create(TabCutlist.prototype);
tab.groups = GROUPS;
tab.generateOptions = { dimension_column_order_strategy: 'width>length>thickness' };
tab.filename = 'SMOKE.skp';
tab.modelName = 'smoke';
tab.modelDescription = '';
tab.modelActivePath = '';
tab.pageName = '';
tab.pageDescription = '';
tab.isEntitySelection = false;
tab.lengthUnit = 0;
tab.cutlistTitle = 'smoke';
tab.$element = $('#tab', win.document);
tab.$rootSlide = $('#tab', win.document);
tab.slides = [];

// Only what the REAL prototype has. A method absent here is absent in SketchUp.
const notified = [];
tab.dialog = { capabilities: { sketchup_version_number: 2200000000, webgl_available: false } };
realDialogMethods.forEach((m) => { tab.dialog[m] = function () {}; });
tab.dialog.notifyErrors = function (e) { notified.push(e); };

// pushNewSlide/popSlide/print touch DOM plumbing this harness does not build;
// they are upstream code and not what is under test. Recorded instead.
const pushed = [];
tab.pushNewSlide = function (id, twigFile, params, cb) {
  // RENDER FOR REAL. This is the half that matters: the pack template is
  // compiled Twig and a bad variable reference throws here, exactly as it
  // would on screen.
  const html = win.Twig.twig({ ref: twigFile }).render(params);
  pushed.push({ id: id, twigFile: twigFile, params: params, length: html.length });
  const $slide = $('<div>' + html + '</div>');
  // DEFERRED, because the real pushSlide fires this from a 300 ms
  // switchClass completion. Calling it synchronously made the harness report
  // a TDZ error on `const $slide = this.pushNewSlide(..., cb)` that cannot
  // happen in the app — a false alarm is as expensive as a miss, and this one
  // very nearly had me "fix" correct code.
  if (typeof cb === 'function') setTimeout(cb, 0);
  return $slide;
};
tab.popSlide = function () {};
tab.print = function () {};

// requestAnimationFrame in jsdom is async; drain it.
const drain = () => new Promise((res) => setTimeout(res, 400));

(async () => {
  // ONE jsdom error IS EXPECTED, and it is proof rather than noise:
  // dialog-tabs.js, the last script in the tabs bundle, sets
  // window.location.href = "skp:ladb_opencutlist_setup_dialog_context" on
  // document ready. That is the SketchUp bridge, and jsdom reports it as "Not
  // implemented: navigation to another Document". Seeing it exactly once says
  // the bundle's entry script ran; any other error still fails the run.
  await drain();
  const isBridge = (e) => /Not implemented: navigation/.test(String(e && (e.message || e)));
  const bridge = uncaught.filter(isBridge).length;
  check(bridge === 1, `the bundle's entry script ran: one skp: bridge navigation (got ${bridge})`);
  for (let i = uncaught.length - 1; i >= 0; i--) { if (isBridge(uncaught[i])) uncaught.splice(i, 1); }
  check(uncaught.length === 0,
        `nothing else thrown while the three files loaded${uncaught.length ? ' — ' + uncaught.map(String).join(' | ').slice(0, 240) : ''}`);

  // SCENARIO 1 WAS THE ALL-BOARDS DIAGRAM PRINT, and it is gone with the
  // engine it was built on: OpenCutList 8 deleted cutlist_group_
  // cuttingdiagram2d_start/_advance, so MOP on 8 prints each board from 8's
  // own Packing slide (docs/mcft/MOP-ON-OCL8.md §2.4).
  // -------------------------------------------------------------------------
  // SCENARIO 2 — the estimate screen, which is the surface Amit uses daily and
  // the one changed most this week: purchase list, totals, packet quantities,
  // trade names, thickness order.
  //
  // The fixture is a REAL estimate_preview payload captured from mcft-stg, so
  // the test breaks if the server's shape drifts from what the plugin reads —
  // which no hand-written fixture would notice. Every money value in it is
  // ZEROED: this fork is public, and cost data never enters a repo. The counts,
  // units and codes are untouched, because those are what the rendering
  // actually branches on.
  console.log('\nmcftRender(estimate payload)');
  const payload = JSON.parse(
    fs.readFileSync(path.join(__dirname, 'estimate-payload.json'), 'utf8'));
  // THE REAL DOM SHAPE, not a bare div. mcftStartEstimate walks up to the
  // enclosing .ladb-slide and then looks for #ladb_mcft_estimate inside it,
  // returning silently when either is missing — so a hand-shaped box made
  // scenario 3's button clicks do nothing at all while every assertion about
  // what they sent passed on an empty list. A vacuous pass is worse than a
  // failure; this is the two elements the code actually reaches for.
  const $box = $('<div class="ladb-slide"><div id="ladb_mcft_estimate"></div></div>')
    .appendTo($('#tab', win.document)).find('#ladb_mcft_estimate');
  tab.$mcftBox = $box;
  tab.mcftEdits = null;

  let renderThrew = null;
  const before = uncaught.length;
  try {
    tab.mcftRender(payload);
  } catch (e) {
    renderThrew = e;
  }
  await drain();

  const html = $box.html() || '';
  check(!renderThrew, `mcftRender did not throw${renderThrew ? ' — ' + renderThrew.message : ''}`);
  check(uncaught.length === before, 'nothing thrown while rendering the estimate');
  check(html.length > 5000, `the estimate rendered (${html.length} chars)`);

  // The tables Amit asked for, each by the heading he reads.
  [['Material', 'material table'],
   ['Purchase list', 'purchase list'],
   ['Labour', 'labour table'],
   ['Logistics', 'logistics table'],
   ['Totals', 'totals table'],
   ['Material consumed vs bought', 'consumed vs bought']].forEach(([needle, what]) => {
    check(html.indexOf(needle) !== -1, `${what} is on screen`);
  });

  // The things that were bugs this week, asserted as behaviour rather than
  // trusted because the code looks right.
  check(html.indexOf('Plywood 16 mm (8x4)') !== -1, 'ply carries its trade name');
  check(html.indexOf('SG_LAM_V0_1mm_a') !== -1, 'internal laminate clubbed to one purchase code');
  check(/16 mm[\s\S]*12 mm/.test(html), '16 mm is listed above 12 mm');
  check(html.indexOf('laminate sheets for') !== -1, 'the sandwich line is stated');
  check((html.match(/<tfoot>/g) || []).length >= 4,
        `every amount column carries a total (${(html.match(/<tfoot>/g) || []).length} tfoots)`);
  check(html.indexOf('UNDERSTATED') === -1, 'the withdrawn grouped-hardware banner is gone');

  // SG_PLY_V0_1mm (Amit, 2026-09-09). A part carrying the ply material at
  // 1 mm reached the priced lines as a red NOT-IN-ERP board, which invited
  // somebody to create an Item for 1 mm plywood. The bench now holds those
  // parts back and names them; this is the half that puts them ON SCREEN,
  // and it must NOT read like a missing rate.
  check(html.indexOf('not a board anybody makes') !== -1,
        'the impossible-board banner is shown');
  check(html.indexOf('SG_PLY_V0_a_a at 1 mm') !== -1,
        'the banner names the material and the millimetres to find in SketchUp');
  const banner = html.slice(html.indexOf('not a board anybody makes'),
                            html.indexOf('not a board anybody makes') + 900);
  check(banner.indexOf('Nothing to create in ERP') !== -1,
        'the banner says there is nothing to create, unlike the unpriced one');
  check(banner.indexOf('ladb_mcft_btn_create') === -1,
        'the impossible-board banner offers no create button');

  // The casters (Amit, 2026-09-20). OCL counted 43 hardware pieces, the
  // estimate priced 39, and nothing on the page said so. This is the line
  // that would have said it.
  check(html.indexOf('OpenCutList counted') !== -1,
        'the hardware tally is shown');
  check(html.indexOf('4 piece(s) are missing') !== -1,
        'the tally names how many pieces went missing');
  check(html.indexOf('Type is Hardware') !== -1,
        'it says what to actually go and fix');

  // THE RECONCILIATION, now computed in the plugin rather than on the bench.
  //
  // The fixture's ocl_totals exercise all four branches at once, and the two
  // that must stay SILENT are the more important half: a warning that fires on
  // every estimate is worse than none, because it teaches the reader to skip
  // the line where the real one will appear.
  check(html.indexOf('OpenCutList against the estimate') !== -1,
        'the per-type reconciliation line is shown');
  // 62 panels nesting into 9 boards is the nesting working. The server-side
  // version of this check compared those two numbers directly and would have
  // reported 53 pieces missing on this very payload.
  // Timber the bench refused to price for want of a MOP offcut figure.
  // Amit, 2026-09-28, chose refusal over a zero-waste fallback; the banner is
  // what makes that choice visible instead of a line quietly missing.
  check(html.indexOf('no cutting volume from OpenCutList') !== -1,
        'held-back timber gets its own banner');
  check(html.indexOf('DIM_Pine') !== -1 && html.indexOf('NOT PRICED') !== -1,
        'the banner names the material and says it was not priced');
  check(html.indexOf('ladb_mcft_btn_create') === -1
        || html.indexOf('no cutting volume from OpenCutList') <
           html.indexOf('ladb_mcft_btn_create'),
        'the timber banner offers no create button of its own');
  // And the priced one. The source label ("OpenCutList cutting size") rides on
  // the line's `desc`, which this table does not render — it reaches the saved
  // Estimate SKU in ERPNext, not this screen. That is fine, and the reason is
  // the invariant worth asserting instead: a timber line priced in CUBIC FEET
  // can only exist because MOP sent a cutting volume, since the bench holds
  // back every material it did not get one for. Presence IS the provenance.
  check(html.indexOf('SW_Teak') !== -1 && html.indexOf('Cubic Foot') !== -1,
        'priced timber appears in cubic feet, which only a MOP figure can produce');

  check(html.indexOf('Sheet Goods: 62 piece(s)') !== -1
        && html.indexOf('3 board line(s)') !== -1,
        'sheet goods are reported as panels against board lines, not board counts');
  check(!/Sheet Goods: OpenCutList counted/.test(html),
        'nesting 62 panels into 9 boards raises no alarm');
  check(!/Edge Banding: OpenCutList counted/.test(html),
        'edge banding counted as bands and priced in metres raises no alarm');
  // Solid wood, now PRICED by volume (26 Sep). The green line states the
  // cubic feet and not a line count, because "6 pieces to 1 line" says
  // nothing about whether the right timber was measured.
  check(html.indexOf('Solid Wood: 6 piece(s)') !== -1
        && html.indexOf('0.50 cft') !== -1,
        'priced solid wood reports its volume, not a line count');
  check(!/Solid Wood: OpenCutList counted/.test(html),
        'priced solid wood raises no alarm');
  // Dimensional is in the model and has no line, which is what a bench older
  // than 26 Sep looks like — and what a material with no Type set looks like
  // on any bench. Both need saying.
  check(html.indexOf('Dimensional: OpenCutList counted 6 piece(s)') !== -1,
        'a type with no priced line at all is reported');
  check(html.indexOf('older than 26 Sep') !== -1,
        'the report names the other reason a line can be absent');
  // The casters again, this time from the plugin's own arithmetic: 103
  // counted against the 99 pieces the priced rows add up to.
  check(html.indexOf('Hardware: OpenCutList counted 103 piece(s)') !== -1,
        'the plugin-side hardware count is reported');
  check(html.indexOf('The estimate does not hold everything the model does') !== -1,
        'the problems are collected where they cannot be missed');
  check(html.indexOf('Veneer') === -1 || !/Veneer: OpenCutList/.test(html),
        'veneer is never reconciled — it is deliberately not pushed');

  // -------------------------------------------------------------------------
  // SCENARIO 2b — WHAT THE PLUGIN'S OWN READING SAYS (OpenCutList 8).
  //
  // The assembly walk and the notes travel beside the priced rows as
  // mcft_assembly_walk and mcft_notes, never posted. Asserted both ways: every
  // line appears when it has something to say, and NONE appears when it has
  // not — a note that fires on every estimate teaches the reader to skip it.
  console.log('\nthe plugin\'s notes (assembly walk, N1-N4)');
  const said = (extra) => {
    tab.mcftRender(Object.assign(JSON.parse(JSON.stringify(payload)), extra));
    return $box.html() || '';
  };
  let notesHtml = said({
    assembly_unsized: 0,
    mcft_assembly_walk: { large: 0, medium: 0, small: 0, top_level: false, scope: 'model',
                          ignored: ['ASMBL_WAR'], unnamed_modules: ['Wardrobe 600'] },
    mcft_notes: { cut_larger: ['Door (length +10mm)'], default_named: 3, default_name: 'Part',
                  bare_fronts: ['Part#2'] },
  });
  await drain();
  check(notesHtml.indexOf('None was found, so ERP priced the seven assembly steps by its own rule') !== -1,
        'N4: a walk that counted nothing says ERP priced the steps, with the naming rule');
  check(notesHtml.indexOf('look like OpenCutList 8 modules') !== -1 &&
        notesHtml.indexOf('Wardrobe 600') !== -1,
        'unnamed Smart Build modules are named on the slide');
  check(/1 component\(s\) or group\(s\)[^<]*ASMBL_WAR/.test(notesHtml),
        'the "not counted" warning comes from the walk, not the bench echo (assembly_unsized 0)');
  check(notesHtml.indexOf('cuts these sheet parts larger than ERP nests them: Door (length +10mm)') !== -1,
        'N1: sheet parts with their own allowance are named');
  check(notesHtml.indexOf('3 part(s) still carry OpenCutList') !== -1, 'N2: default-named parts are counted');
  check(notesHtml.indexOf('Part#2: a front panel with no face laminate') !== -1, 'N3: bare fronts are named');
  notesHtml = said({
    mcft_assembly_walk: { large: 1, medium: 0, small: 0, top_level: true, scope: 'model',
                          ignored: [], unnamed_modules: [] },
    mcft_notes: { cut_larger: [], default_named: 0, default_name: 'Part', bare_fronts: [] },
  });
  await drain();
  check(['None was found', 'look like OpenCutList 8 modules', 'NOT counted as assemblies',
         'larger than ERP nests', 'default name', 'no face laminate']
          .every((t) => notesHtml.indexOf(t) === -1),
        'with nothing to say, none of those lines is shown');

  // -------------------------------------------------------------------------
  // SCENARIO 3 — THE ESTIMATE BUTTONS READ THE MODEL. Both of them.
  //
  // Amit, 2026-09-28: "Even though i hide a medium assembly, mop estimate
  // still use it for estimate purpose and thus wrong estimate." Refresh used
  // to send reuse_scan, which told Ruby to re-price the LAST model reading
  // rather than take a new one — so hiding an assembly and refreshing kept
  // charging for it. His console showed it exactly: four estimate runs, one
  // assembly walk.
  //
  // The parameter is gone, and this is what keeps it gone. A check on the
  // wire rather than on the source, because the source has read as correct
  // throughout: the danger was even written in the comment beside the two
  // buttons, and shipped anyway.
  console.log('\nthe estimate buttons');
  const estimatesBefore = sent.filter((c) => c.name === 'mcft_estimate').length;
  // RE-RENDERED BEFORE EACH CLICK, because the first thing mcftStartEstimate
  // does is replace the whole box with "Asking ERPNext…" — which destroys
  // the other button. That is real behaviour and not a harness quirk; the
  // answer comes back through an event and re-renders.
  for (const sel of ['#ladb_mcft_btn_recalc', '#ladb_mcft_btn_refresh']) {
    tab.mcftRender(payload);
    await drain();
    check($(sel, win.document).length === 1, `${sel} is on screen and bound`);
    $(sel, win.document).trigger('click');
    await drain();
  }
  const estimates = sent.filter((c) => c.name === 'mcft_estimate');
  check(estimates.length === estimatesBefore + 2,
        `both buttons asked ERP to price (${estimates.length - estimatesBefore} call(s))`);
  // Guarded on length, so neither of these can pass on an empty list — which
  // is exactly how the first version of this scenario reported success while
  // the clicks were reaching nothing.
  check(estimates.length > 0 &&
        estimates.every((c) => !('reuse_scan' in (c.params || {}))),
        'no estimate asks Ruby to skip the model read');
  check(estimates.length > 0 &&
        estimates.every((c) => Array.isArray((c.params || {}).hidden_group_ids)),
        'every estimate carries what the Parts List hid');

  check(notified.length === 0, 'no errors reported');
  check(uncaught.length === 0,
        `nothing thrown inside a callback${uncaught.length ? ' — ' + uncaught.map(String).join(' | ').slice(0, 240) : ''}`);

  console.log('');
  if (failures.length) {
    failures.forEach((f) => console.error(`::error::smoke: ${f}`));
    console.error(`${failures.length} smoke check(s) failed`);
    process.exit(1);
  }
  console.log('dialog smoke: all checks passed');
})();
