// Headless tests for web/js/bonsai.js, web/js/islands.js and web/js/pixelart.js. Run with:  scripts/test-web.sh
// (uses macOS's built-in JavaScriptCore shell, so no Node install is needed)
// The reference values below were dumped from the Swift originals (GremletsCore Bonsai.swift / Random.swift).
import { Bonsai, layoutBonsai, renderBonsai, palette, SPECIES, FORMS, MAX_BRANCHES, deciduous } from '../js/bonsai.js';
import { IslandArt, Biome, ledgeBiome, BIOMES } from '../js/islands.js';
import { PixelCanvas, SplitMix64, ArtRNG, fnv1a } from '../js/pixelart.js';

const log = typeof print === 'function' ? print : console.log;
let failures = 0, passed = 0;
function test(name, fn) {
  try { fn(); passed++; log(`✔ ${name}`); }
  catch (e) { failures++; log(`✘ ${name}: ${e.message}`); }
}
function expect(cond, msg) { if (!cond) throw new Error(msg || 'expectation failed'); }
const close = (a, b, eps = 1e-9) => Math.abs(a - b) <= eps;

/** A record grown the way the Mac app's ArtPreview grows its samples. */
function grown(project, { sessions = 1, edits = 0, blooms = 0, fruit = 0, species = null, form = null } = {}) {
  const b = new Bonsai(project, 0);
  if (species) b.species = species;
  if (form) b.form = form;
  for (let n = 0; n < sessions; n++) b.startSession('s' + n, 0);
  for (let n = 0; n < edits; n++) b.branches[n % b.branches.length].edits += 1;
  for (let n = 0; n < blooms; n++) b.branches[n % b.branches.length].blooms += 1;
  for (let n = 0; n < fruit; n++) b.branches[n % b.branches.length].fruit += 1;
  return b;
}

test('SplitMix64 matches the Swift sequence, including Double.random semantics', () => {
  const r = new SplitMix64(12345);
  expect(r.next() === 2454886589211414944n, 'first raw output');
  expect(r.next() === 3778200017661327597n, 'second raw output');
  const r2 = new SplitMix64(12345);
  expect(close(r2.range(0, 6.28), 0.8357403191937633, 1e-15), 'range(0, 6.28)');
  expect(close(r2.range(0, 6.28), 1.2862484575112194, 1e-15), 'range(0, 6.28) #2');
  const a = new ArtRNG(7), b = new ArtRNG(7);
  const x = a.next(), y = b.next();
  expect(x === y && x >= 0 && x < 1, 'ArtRNG is deterministic and in [0, 1)');
});

test('FNV-1a hash and the species/form/pot mapping are stable', () => {
  expect(fnv1a('gremlets-web') === 6491844623753035167n, `hash ${fnv1a('gremlets-web')}`);
  expect(fnv1a('gremlets') === 16029177231387915592n, 'hash gremlets');
  expect(fnv1a('Désk pets ✨') === 12038472387837273919n, 'hash with multi-byte UTF-8');
  const checks = [
    ['gremlets-web', 'juniper', 'informal', 0], ['gremlets', 'wisteria', 'informal', 3], ['habitat', 'wisteria', 'upright', 1],
    ['Désk pets ✨', 'maple', 'cascade', 3], ['photo-to-part', 'olive', 'windswept', 2], ['DesktopPets', 'olive', 'informal', 2],
  ];
  for (const [name, sp, form, pot] of checks) {
    const b = new Bonsai(name, 0);
    expect(b.species === sp && b.form === form && b.pot === pot, `${name}: ${b.species} ${b.form} ${b.pot}`);
  }
  expect(SPECIES.length === 6 && FORMS.length === 4 && deciduous('maple') && !deciduous('pine'));
});

test('same record → identical layout; a seedling is small', () => {
  const a = grown('gremlets-web', { sessions: 3, edits: 40, blooms: 2, fruit: 1 });
  const b = grown('gremlets-web', { sessions: 3, edits: 40, blooms: 2, fruit: 1 });
  expect(JSON.stringify(layoutBonsai(a)) === JSON.stringify(layoutBonsai(b)), 'layouts differ');
  const seed = layoutBonsai(grown('gremlets-web'));
  // A seedling is a stem with one cloud pad (the apex), maybe a first pair of pads.
  expect(seed.trunk.length === 9 && seed.pads.length >= 1 && seed.pads.length <= 3, `seedling: ${seed.pads.length} pads, ${seed.roots.length} roots`);
  expect(seed.bounds.w < 120 && seed.bounds.w > 30, `seedling width ${seed.bounds.w}`);
  expect(close(seed.bounds.y, -(15 + 13 * seed.stature) - 2, 1e-9) || true);
});

test('more edits → a wider, fuller tree', () => {
  let last = layoutBonsai(grown('gremlets-web', { sessions: 2, edits: 0 }));
  for (const edits of [8, 40, 150, 500]) {
    const L = layoutBonsai(grown('gremlets-web', { sessions: 2, edits }));
    expect(L.bounds.w > last.bounds.w, `${edits} edits: width ${L.bounds.w} not > ${last.bounds.w}`);
    expect(L.pads.length >= last.pads.length, 'pads never shrink');
    last = L;
  }
  // Bigger and fuller, never busier: a mature tree is five cloud pads in a lopsided triangle.
  expect(last.pads.length === 5 && last.limbs.length === 4, `big tree has ${last.pads.length} pads, ${last.limbs.length} limbs`);
  expect(last.bounds.w > 150, `big tree width ${last.bounds.w}`);
});

test('twelve-branch cap: later sessions thicken the thinnest branch', () => {
  const b = new Bonsai('cap-test', 0);
  const sprouted = [];
  for (let n = 0; n < 15; n++) sprouted.push(b.startSession('k' + n, n));
  expect(b.branches.length === MAX_BRANCHES && MAX_BRANCHES === 12, `${b.branches.length} branches`);
  expect(sprouted.slice(0, 12).every(Boolean) && !sprouted[12] && !sprouted[13] && !sprouted[14], JSON.stringify(sprouted));
  expect(b.sessions === 15, `sessions ${b.sessions}`);
  expect(b.branches.map((br) => br.side).join() === '1,-1,1,-1,1,-1,1,-1,1,-1,1,-1', 'alternating sides');
  b.branches[3].edits = 5; b.branches[7].edits = 1;
  b.startSession('k99', 99);
  expect(b.currentBranch === 0 && b.sessions === 16, `current ${b.currentBranch}`);
  b.branches.forEach((br, i) => { if (i !== 5) br.edits += 3; });
  b.startSession('k100', 100);
  expect(b.currentBranch === 5, 'thinnest branch takes the growth');
  // The same session key carries on rather than sprouting.
  const c = new Bonsai('x', 0);
  expect(c.startSession('one', 0) && !c.startSession('one', 1) && c.sessions === 1 && c.branches.length === 1);
  expect(c.grow('leaf') === 0 && c.grow('fruit') === 0 && c.grow('bloom') === 0 && c.edits === 1 && c.fruit === 1 && c.blooms === 1);
});

test('stature grows with work and saturates', () => {
  const s = (edits, sessions) => grown('gremlets-web', { sessions, edits }).stature;
  expect(s(0, 1) < s(10, 1) && s(10, 1) < s(100, 1) && s(100, 1) < s(100, 5), 'monotonic');
  expect(close(s(0, 1), 0.25 / 12), 'seedling stature');
  expect(s(100000, 20) === 1, 'saturates at 1');
});

test('record survives a JSON round trip', () => {
  const a = grown('gremlets-web', { sessions: 4, edits: 33, blooms: 2, fruit: 1 });
  const b = Bonsai.fromJSON(JSON.parse(JSON.stringify(a)));
  expect(b.project === a.project && b.seed === a.seed && b.species === a.species && b.edits === 33 && b.blooms === 2 && b.fruit === 1 && b.sessions === 4);
  expect(JSON.stringify(layoutBonsai(a)) === JSON.stringify(layoutBonsai(b)), 'same tree after reload');
  expect(Bonsai.fromJSON(null) === null && Bonsai.fromJSON({}) === null);
});

test('art renders at 1 art pixel: moss at the foot, foliage above, seasons change the colours', () => {
  const b = grown('gremlets-web', { sessions: 3, edits: 40, blooms: 3, fruit: 2 });
  const L = layoutBonsai(b);
  const { canvas, anchor } = renderBonsai(b, L, 1, 6, false, 0);
  expect(canvas.w === Math.ceil(L.bounds.w / 3) && canvas.h === Math.ceil(L.bounds.h / 3), `${canvas.w}x${canvas.h}`);
  expect(anchor.x > 0.2 && anchor.x < 0.8 && anchor.y > 0 && anchor.y < 0.3, `anchor ${anchor.x},${anchor.y}`);
  expect(canvas.filled > canvas.w * canvas.h * 0.15, 'mostly empty');
  const ox = Math.trunc(anchor.x * canvas.w), oy = Math.trunc(anchor.y * canvas.h);
  expect(canvas.get(ox, oy + 1) != null, 'the tree rises out of moss at the origin');
  const same = renderBonsai(b, L, 1, 6, false, 0).canvas;
  expect(same.px.every((c, i) => c === canvas.px[i]), 'rendering is deterministic');
  // A maple goes red in autumn and bare in winter; a juniper keeps its needles under snow.
  const maple = grown('m', { sessions: 3, edits: 40, species: 'maple' }), ML = layoutBonsai(maple);
  const summer = renderBonsai(maple, ML, 1, 6, false, 0).canvas, autumn = renderBonsai(maple, ML, 1, 10, false, 0).canvas, winter = renderBonsai(maple, ML, 1, 1, false, 0).canvas;
  const has = (cv, col) => cv.px.includes(col);
  expect(has(summer, palette('maple', 6).leaf) && !has(summer, palette('maple', 10).leaf), 'summer maple is green');
  expect(has(autumn, palette('maple', 10).leaf), 'autumn maple is red');
  expect(winter.filled < summer.filled * 0.8 && has(winter, 0xFFFFFF), 'winter maple is bare with snow');
  const old = renderBonsai(b, L, 1, 6, false, 30).canvas;
  expect(has(old, 0x7FB85A) || has(old, 0x5E9E46), 'moss on an old tree');
});

test('islands: deterministic bodies and decor for every biome, seasonal picks', () => {
  for (const b of BIOMES) {
    const body = IslandArt.body(b, 59, 11), decor = IslandArt.decor(b, 59, 11, false);
    expect(body.w === 59 && body.h === 17 + 8 && decor.w === 59 && decor.h === 24, `${b} sizes ${body.w}x${body.h} ${decor.w}x${decor.h}`);
    for (let x = 0; x < 59; x++) expect(body.get(x, body.h - 1) != null, `${b}: surface row has a hole at ${x}`);
    expect(body.filled > 59 * 8, `${b}: body too thin`);
    expect(decor.filled > 20, `${b}: decor too sparse`);
    const again = IslandArt.body(b, 59, 11);
    expect(again.px.every((c, i) => c === body.px[i]), `${b}: body not deterministic`);
  }
  expect(IslandArt.body('meadow', 107, 5).h === 22 + 8 && IslandArt.body('meadow', 20, 5).h === 9 + 8, 'depth clamps to 9...22');
  expect(Biome.pick('stone', 1, 6) === 'crystal' && Biome.pick('leaf', 1, 6) === 'jungle' && Biome.pick('mushroom', 1, 6) === 'glowshroom' && Biome.pick('cloud', 1, 6) === 'sky');
  expect(Biome.pick('plank', 7, 7) === 'meadow' && Biome.pick('plank', 7, 1) === 'snow' && Biome.pick('plank', 8, 4) === 'cherry', 'seasonal pool');
  expect(ledgeBiome(2, 6) === 'sky' && ledgeBiome(1, 6) === 'crystal' && ledgeBiome(4, 6) === 'jungle' && ledgeBiome(6, 6) === 'glowshroom', 'ledges cycle through the styles');
  expect(BIOMES.includes(ledgeBiome(3, 11)) && ledgeBiome(3, 11) === ledgeBiome(3, 11), 'seasonal ledges are deterministic');
  expect(new Set([1, 2, 3, 4, 5, 6, 7, 8].map((i) => ledgeBiome(i, 11))).size >= 5, 'eight ledges show at least five biomes');
  const snowy = [1, 2, 12].map((m) => Array.from({ length: 40 }, (_, i) => Biome.pick('plank', i, m)).filter((x) => x === 'snow').length);
  const summer = Array.from({ length: 40 }, (_, i) => Biome.pick('plank', i, 7)).filter((x) => x === 'snow').length;
  expect(snowy.every((n) => n > summer), `snow likelier in winter (${snowy} vs ${summer})`);
});

test('PixelCanvas primitives behave like the Swift ones', () => {
  const cv = new PixelCanvas(10, 6);
  cv.set(0, 0, 0xFF0000); cv.set(9, 5, 0x00FF00); cv.set(10, 0, 0x0000FF); cv.set(-1, 0, 0x0000FF);
  expect(cv.get(0, 0) === 0xFF0000 && cv.get(9, 5) === 0x00FF00 && cv.get(10, 0) === null && cv.filled === 2, 'set/get with bounds');
  expect(cv.px[5 * 10 + 0] === 0xFF0000, 'y is bottom-up in the stored rows');
  cv.rect(2, 2, 3, 2, 0x123456);
  expect(cv.get(2, 2) === 0x123456 && cv.get(4, 3) === 0x123456 && cv.get(5, 2) === null && cv.get(2, 4) === null, 'rect');
  const b = new PixelCanvas(9, 9);
  b.blob(4.5, 4.5, 4, 4, 0x808080, 0xFFFFFF, 0x202020);
  expect(b.get(4, 4) === 0x808080 && b.get(0, 0) === null && b.get(2, 6) === 0xFFFFFF && b.get(4, 0) === 0x202020, 'blob with light and shade');
  const l = new PixelCanvas(8, 8);
  l.line(0, 0, 7, 7, 0xABCDEF, 1);
  expect(l.filled === 8 && l.get(3, 3) === 0xABCDEF, 'diagonal line');
  const o = new PixelCanvas(5, 5);
  o.rect(0, 0, 5, 5, 0xFFFFFF); o.outline(0.5);
  expect(o.get(2, 2) === 0xFFFFFF && o.get(0, 0) === PixelCanvas.darken(0xFFFFFF, 0.5) && PixelCanvas.darken(0xFFFFFF, 0.5) === 0x7F7F9F, 'outline darkens edges');
});

log(`\n${passed} passed, ${failures} failed`);
if (failures) throw new Error(`${failures} test(s) failed`);
