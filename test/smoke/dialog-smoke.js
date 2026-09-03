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

// Minimal globals the tab code reaches for. i18next is stubbed to echo its key
// — labels are not what this test is about.
win.eval(read('js/lib/jquery-3.7.1.min.js'));
win.eval(read('js/lib/twig.min.js'));
// ALL FOUR BUNDLES. The tab templates include core/ and components/ ones, and
// loading only the tabs bundle produced "Unable to find template file
// core/_length-unit-extra.twig" — a harness gap that reads exactly like a bug
// in the code under test.
['core', 'components', 'modals', 'tabs'].forEach((b) => {
  win.eval(read(`js/templates/${b}-twig-templates.js`));
});
win.eval('window.i18next = { t: function (k) { return k; }, exists: function () { return true; } };');

// SCAFFOLDING, and named as such. The real Twig filters are registered inside
// LadbAbstractDialog.prototype.init, which also wires settings, the DOM and
// the SketchUp bridge — far more than this harness can or should stand up. The
// filters are stubbed to pass their value through; they affect wording, never
// whether a template resolves or a method exists, which is what is under test.
win.eval(`
  ['i18next','url_beautify','format_currency','sanitize_links','trim_tilde',
   'type_of','sanitize_html','number_format','format_infinite',
   // twig.js's own date() cannot resolve a timezone under jsdom; the pack does
   // not depend on a formatted date, only the slide chrome does.
   'date'].forEach(function (f) {
    try { Twig.extendFilter(f, function (v) { return v === undefined ? '' : v; }); } catch (e) {}
  });
  ['blend_colors','mesure_text','measure_text'].forEach(function (f) {
    try { Twig.extendFunction(f, function () { return 0; }); } catch (e) {}
  });
`);
win.eval('window.Noty = function () { return { show: function () {}, close: function () {} }; };');

// THE REAL DIALOG PROTOTYPE, so a missing method stays missing.
//
// Two loading quirks, both of which bit before this worked:
//  - abstract-dialog.js and abstract-tab.js open with 'use strict', and a
//    strict-mode function declaration inside eval is scoped to that eval
//    rather than becoming a global. So each is handed out explicitly.
//  - the tab file is an IIFE and keeps LadbTabCutlist as a closure const. It
//    is reachable only where the plugin publishes it, on
//    $.fn.ladbTabCutlist.Constructor — which is also how the real dialog gets
//    at it, so the harness is using the same door the app does.
win.eval(read('js/plugins/jquery.ladb.abstract-dialog.js') +
         '\nwindow.LadbAbstractDialog = LadbAbstractDialog;');
win.eval(read('js/plugins/tabs/jquery.ladb.abstract-tab.js') +
         '\nwindow.LadbAbstractTab = LadbAbstractTab;');
win.eval(read('js/plugins/tabs/jquery.ladb.tab-cutlist.js'));

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
// The bench: canned Ruby responses for exactly the commands the pack calls.
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
let advanceLeft = 0;
win.rubyCallCommand = function (name, params, cb) {
  calls.push(name);
  const reply = (r) => { if (typeof cb === 'function') cb(r); };
  switch (name) {
    case 'core_get_model_preset':
      return reply({ preset: { std_sheet: '2440x1220', saw_kerf: '3mm' } });
    case 'cutlist_group_cuttingdiagram2d_start':
      advanceLeft = 2;                       // force the advance loop to run
      return reply({ estimated_steps: 2 });
    case 'cutlist_group_cuttingdiagram2d_advance':
      if (advanceLeft-- > 0) return reply({});          // still working
      return reply({ sheets: [{ index: 1, parts: [], cuts: [], leftovers: [] }],
                     errors: [], options: {}, summary: {} });
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

// ---------------------------------------------------------------------------
console.log('\nmcftDiagramPack()');
let threw = null;
try {
  tab.mcftDiagramPack();
} catch (e) {
  threw = e;
}
// requestAnimationFrame in jsdom is async; drain it.
const drain = () => new Promise((res) => setTimeout(res, 400));

(async () => {
  await drain();
  check(!threw, `no exception thrown${threw ? ' — ' + threw.message : ''}`);
  check(pushed.length === 1, `exactly one slide pushed (got ${pushed.length})`);
  if (pushed.length === 1) {
    check(pushed[0].twigFile === 'tabs/cutlist/_slide-mcft-diagram-pack.twig',
          'the slide is the pack template');
    const packs = pushed[0].params.packs || [];
    check(packs.length === 2,
          `two sheet-good groups packed, hardware skipped (got ${packs.length})`);
    check(pushed[0].length > 200, `the template rendered (${pushed[0].length} chars)`);
  }
  check(calls.filter((c) => c === 'cutlist_group_cuttingdiagram2d_start').length === 2,
        'start called once per sheet-good group');
  check(calls.filter((c) => c === 'cutlist_group_cuttingdiagram2d_advance').length >= 4,
        'the advance loop ran for each group');
  check(notified.length === 0, 'no errors reported');
  check(uncaught.length === 0,
        `nothing thrown inside a callback${uncaught.length ? ' — ' + uncaught.map(String).join(' | ').slice(0, 240) : ''}`);

  
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
  const $box = $('<div id="mcftbox"></div>').appendTo($('#tab', win.document));
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

  console.log('');
  if (failures.length) {
    failures.forEach((f) => console.error(`::error::smoke: ${f}`));
    console.error(`${failures.length} smoke check(s) failed`);
    process.exit(1);
  }
  console.log('dialog smoke: all checks passed');
})();
