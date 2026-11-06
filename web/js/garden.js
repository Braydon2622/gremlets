// A visiting Gremlet's window box: the same plants, art and rules as the Mac app's Garden.swift, simplified.
// Three spots; the gardener plants, waters, shoos aphids and weeds; plants grow seed → sprout → young → bud → bloom;
// when everything has bloomed it's harvested (and carried home to the Mac later) and a new box is planted.

const PAL = { g: '#6cc04a', G: '#3e8e3a', r: '#ff6f7e', R: '#d8455a', w: '#ffffff', W: '#f4f1e8', y: '#ffd84a', Y: '#e0a92e', o: '#ff9a3c', O: '#d8701e', c: '#5fa84a', C: '#3e7d33', p: '#ff8fbf', P: '#e0588f', b: '#7a4e2a', m: '#7a4e2a', k: '#2b2620', s: '#4a3424', v: '#a98bea', V: '#7a5fc9', B: '#6f8ff0', i: '#d8f0ff', I: '#9fd3f5', l: '#c9b8ff', L: '#f2eeff', x: '#7fe3f0', X: '#c6f7ff', z: '#a98bea' };
const EARLY = [
  ['.....mm.....'],
  ['....g.g.....', '.....G......', '.....G......'],
  ['..gg...gg...', '...gg.gg....', '.....G......', '..gg.G......', '...ggG......', '.....G......'],
];
const BLOOM = {
  tulip: ['....r.r.r...', '....rrrrr...', '....rRrRr...', '.....rrr....', '.....G......', '..gg.G......', '.gggGG......', '.....G.gg...', '.....Ggggg..', '.....G......'],
  daisy: ['...w.w.w....', '....wyw.....', '...wyyyw....', '....wyw.....', '...w.w.w....', '.....G......', '..gg.G......', '...gGG......', '.....G.gg...', '.....G......'],
  carrot: ['..g..g..g...', '...g.g.g....', '..gggggg....', '...gGGGg....', '....gGg.....', '....oOo.....', '....ooo.....'],
  lavender: ['..v...v.....', '.vV..vV.....', '..v.v.v.v...', '..vV.vVvV...', '...v.v.v....', '...g.G.g....', '..gg.G.gg...', '.....G......', '....gGg.....', '.....G......'],
  strawberry: ['...w...w....', '..wyw.wyw...', '...w.g.w....', '..gggggggg..', '.ggGggGgggg.', '..r.gGg.r...', '.rrr.G.rrr..', '.rWr.G.rWr..', '..r..G..r...'],
  tomato: ['....s.......', '...gsg.g....', '..ggsggg....', '.rrgsg.rr...', '.rRgsg.Rr...', '..ggsgg.....', '.g.rsr.g....', '...rsR......', '....s.......', '....s.......'],
  cactus: ['.....p......', '....pyp.....', '.....p......', '....ccc.....', '.c..cCc.....', '.cc.cCc..c..', '..cccCc.cc..', '....cCccc...', '....cCc.....', '....cCc.....'],
  bluebell: ['....GGG.....', '...G.G.G....', '..B..G..B...', '.BBB.G.BBB..', '.B.B.G.B.B..', '.....G......', '..gg.G......', '...gGG.gg...', '.....GGg....', '.....G......'],
  sunflower: ['...y.y.y....', '..yyyyyyy...', '.yyybbbyyy..', '..yybbbyy...', '.yyybbbyyy..', '..yyyyyyy...', '...y.G.y....', '.....G......', '..ggGG......', '.gggGG......', '.....G.gg...', '.....GGggg..', '.....G......', '.....G......'],
  mushroom: ['...rrrrr....', '..rWrrrWr...', '.rrrrWrrrr..', '.rrWrrrrWr..', '....WWWW....', '....WWWW....', '....WWWW....', '.gg.WWWW.gg.'],
  cherryBlossom: ['..p.pp..p...', '.pPpppp.pp..', '..pp.sppPp..', '.pP.s.ss....', '....s.s.....', '.....ss.....', '.....s......', '.....s......', '....ss......', '.....s......'],
  frostbell: ['....i.i.....', '...iIiIi....', '....iii.....', '..i..G..i...', '.iIi.G.iIi..', '..i..G..i...', '.....G......', '..gg.G.gg...', '...gGGGg....', '.....G......'],
  flytrap: ['..G......G..', '.gRg....gRg.', 'gRRRg..gRRRg', 'gRwRg..gRwRg', '.gRg.GG.gRg.', '...G.G.G....', '....GGG.....', '.....G......', '..gg.G.gg...', '.....G......'],
  moonflower: ['....lllll...', '...lLLLLLl..', '..lLLyyLLl..', '..lLyyyyLl..', '..lLLyyLLl..', '...lLLLLl...', '....lllll...', '.....G......', '..gg.G.gg...', '.ggg.G.ggg..', '.....G......', '....gGg.....', '.....G......'],
  crystalRose: ['.....x......', '....xXx.....', '...xXzXx....', '..xXzzzXx...', '...xXzXx....', '....xXx.....', '.....G......', '..g..G..g...', '...gGG......', '.....G.gg...', '.....G......'],
  starLily: ['....p.p.....', '...pLpLp....', '.pLLLyLLLp..', '..pLyYyLp...', '.pLLLyLLLp..', '...pLpLp....', '....p.p.....', '.....G......', '..gg.G.gg...', '...gGG......', '.....G......'],
};
const BUD = { tulip: 'r', daisy: 'w', carrot: 'g', lavender: 'v', strawberry: 'w', tomato: 'y', cactus: 'p', bluebell: 'B', sunflower: 'y', mushroom: 'W', cherryBlossom: 'p', frostbell: 'i', flytrap: 'R', moonflower: 'l', crystalRose: 'x', starLily: 'L' };
const RARITY = { tulip: 0, daisy: 0, carrot: 0, lavender: 0, strawberry: 1, tomato: 1, cactus: 1, bluebell: 1, sunflower: 2, mushroom: 2, cherryBlossom: 2, frostbell: 2, flytrap: 2, moonflower: 3, crystalRose: 3, starLily: 3, giantPumpkin: 4, wishingTree: 4, bonsai: 4 };
const GROW = [150, 200, 280, 340, 420];
const NAMES = { cherryBlossom: 'cherry blossom', crystalRose: 'crystal rose', starLily: 'star lily', flytrap: 'Venus flytrap', giantPumpkin: 'giant pumpkin', wishingTree: 'wishing tree' };
export const plantName = (k) => NAMES[k] || k;

function giantRows(k) {
  const w = 36, h = k === 'wishingTree' ? 26 : k === 'bonsai' ? 22 : 16;
  const g = [...Array(h)].map(() => Array(w).fill('.'));
  const put = (x, y, c) => { if (x >= 0 && x < w && y >= 0 && y < h) g[y][x] = c; };
  const cx = w / 2 - 0.5;
  if (k === 'bonsai') {
    for (const [tx, ty] of [[18, 21], [19, 19], [19, 17], [18, 15], [16, 13], [14, 11], [12, 10], [11, 8], [16, 12], [20, 11], [23, 10], [25, 9], [17, 9], [17, 7], [17, 5]]) { put(tx, ty, 's'); put(tx + 1, ty, 'b'); put(tx, ty + 1, 's'); }
    for (const [pcx, pcy, rx, ry] of [[9, 6, 6, 2.6], [26, 7, 6.5, 2.6], [17, 3, 7, 2.8], [13, 13, 4, 1.8]])
      for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { const dx = (x - pcx) / rx, dy = (y - pcy) / ry; if (dx * dx + dy * dy <= 1) put(x, y, dy < -0.2 ? 'g' : 'G'); }
  } else if (k === 'giantPumpkin') {
    const cy = h - h * 0.38, rx = w / 2 - 1.5, ry = h * 0.38;
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const dx = (x - cx) / rx, dy = (y - cy) / ry;
      if (dx * dx + dy * dy <= 1) put(x, y, Math.floor(x - cx + 100) % 6 === 0 ? 'O' : (dx < -0.3 && dy < -0.2 ? 'y' : 'o'));
    }
    const top = Math.floor(cy - ry);
    for (let y = Math.max(0, top - 4); y <= Math.max(0, top); y++) { put(Math.floor(cx), y, 'G'); put(Math.floor(cx) + 1, y, 'G'); }
  } else {
    for (const [ccx, ccy, r] of [[11, 8, 7.5], [24, 8, 7.5], [17.5, 5, 7], [17.5, 11, 6.5]])
      for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { const dx = x - ccx, dy = y - ccy; if (dx * dx + dy * dy <= r * r) put(x, y, dx > r * 0.35 || dy > r * 0.45 ? 'G' : 'g'); }
    for (const [fx, fy] of [[8, 7], [15, 3], [22, 9], [27, 6], [18, 12], [12, 12], [25, 13]]) { put(fx, fy, 'y'); put(fx + 1, fy, 'Y'); put(fx, fy + 1, 'Y'); }
    for (let y = 14; y < h; y++) for (let x = Math.floor(cx) - 1; x <= Math.floor(cx) + 2; x++) put(x, y, (x + y) % 3 === 0 ? 'b' : 's');
  }
  return g.map((r) => r.join(''));
}
for (const k of ['giantPumpkin', 'wishingTree', 'bonsai']) BLOOM[k] = giantRows(k);

function budRows(k) {
  if (k === 'cactus') return ['.....p......', '....ccc.....', '....cCc.....', '..c.cCc.....', '..cccCc.c...', '....cCccc...', '....cCc.....'];
  if (k === 'mushroom') return ['....WWW.....', '...WWWWW....', '.....W......', '.....W......', '..g..W..g...'];
  const c = BUD[k] || 'g';
  return [`.....${c}......`, `....${c}${c}${c}.....`, '.....G......', '..gg.G.gg...', '.gggGG.Ggg..', '.....G......', '...ggG......', '..gggG......', '.....G......'];
}
const stageOf = (g) => (g >= 1 ? 4 : g >= 0.6 ? 3 : g >= 0.33 ? 2 : g >= 0.1 ? 1 : 0);
function rowsFor(p) {
  const s = stageOf(p.growth);
  if (RARITY[p.kind] === 4 && s === 3) return BLOOM[p.kind].filter((_, i) => i % 2 === 0).map((r) => r.replace(/(.)./g, '$1'));
  return s <= 2 ? EARLY[s] : s === 3 ? budRows(p.kind) : BLOOM[p.kind];
}
function goldify(hex) {
  const n = parseInt(hex.slice(1), 16), lum = (0.3 * (n >> 16 & 255) + 0.59 * (n >> 8 & 255) + 0.11 * (n & 255)) / 255;
  const ramp = ['#6e4e10', '#a8781e', '#d9a72e', '#f2cb52', '#ffe58a', '#fff6cf'];
  return ramp[Math.min(ramp.length - 1, Math.floor(lum * ramp.length))];
}

function pickSeed(emptyBox) {
  const r = Math.random();
  let tier = r < 0.012 ? 4 : r < 0.042 ? 3 : r < 0.132 ? 2 : r < 0.432 ? 1 : 0;
  if (tier === 4 && !emptyBox) tier = 3;
  const month = new Date().getMonth() + 1, h = new Date().getHours(), night = h >= 19 || h < 6;
  let options = Object.keys(RARITY).filter((k) => RARITY[k] === tier
    && !(k === 'cherryBlossom' && ![3, 4, 5].includes(month)) && !(k === 'frostbell' && ![12, 1, 2].includes(month)) && !(k === 'moonflower' && !night));
  if (!options.length) options = Object.keys(RARITY).filter((k) => RARITY[k] === tier);
  return { kind: options[Math.floor(Math.random() * options.length)], growth: 0, water: 0.6, bug: false, golden: Math.random() < 1 / 40 };
}

export class Garden {
  constructor() { this.reset(); this.chore = 0; this.harvested = []; this.msg = null; }
  reset() { this.plants = [null, null, null]; this.doneAt = null; }

  get giant() { return this.plants[1] && RARITY[this.plants[1].kind] === 4 ? this.plants[1] : null; }
  get active() { return this.giant ? [1] : [0, 1, 2]; }
  get bloomed() { return this.giant ? this.giant.growth >= 1 : this.plants.every((p) => p && p.growth >= 1); }

  /** Advances the garden. `tending`: the gardener is at its box. Returns a short event name for effects, if any. */
  update(dt, tending, now) {
    let event = null;
    if (this.doneAt != null) {
      if (now - this.doneAt > 8) this.reset();
      return null;
    }
    for (const i of this.active) {
      const p = this.plants[i];
      if (!p) continue;
      p.water = Math.max(0, p.water - dt / 80);
      if (p.growth < 1) p.growth = Math.min(1, p.growth + dt / GROW[RARITY[p.kind]] * (tending ? 1 : 0.4) * (p.water > 0.12 ? 1 : 0.25) * (p.bug ? 0.4 : 1));
      if (!p.bug && p.kind !== 'flytrap' && p.growth > 0.25 && p.growth < 1 && Math.random() < dt * 0.006) { p.bug = true; p.bugSince = now; }
    }
    if (tending && (this.chore -= dt) <= 0) { this.chore = 2.4; event = this.doChore(now); }
    if (!this.giant && this.plants.some((p) => !p)) return event;
    if (this.bloomed) {
      this.doneAt = now;
      const got = (this.giant ? [this.giant] : this.plants).map((p) => ({ kind: p.kind, golden: !!p.golden }));
      this.harvested.push(...got);
      this.msg = 'Harvest! ' + got.map((p) => (p.golden ? 'golden ' : '') + plantName(p.kind)).join(', ');
      return 'harvest';
    }
    return event;
  }

  doChore(now) {
    const empty = this.plants.findIndex((p) => !p);
    if (!this.giant && empty >= 0) {
      const seed = pickSeed(this.plants.every((p) => !p));
      if (RARITY[seed.kind] === 4) this.plants = [null, seed, null]; else this.plants[empty] = seed;
      return 'plant';
    }
    const bug = this.active.find((i) => this.plants[i]?.bug && now - this.plants[i].bugSince > 6);
    if (bug != null) { this.plants[bug].bug = false; return 'shoo'; }
    const dry = this.active.filter((i) => this.plants[i] && this.plants[i].growth < 1 && this.plants[i].water < 0.45)
      .sort((a, b) => this.plants[a].water - this.plants[b].water)[0];
    if (dry != null) { this.plants[dry].water = 1; return 'water'; }
    return null;
  }

  /** You tapped the box: shoo a bug, else water the driest plant. */
  help() {
    const bug = this.active.find((i) => this.plants[i]?.bug);
    if (bug != null) { this.plants[bug].bug = false; return 'shoo'; }
    const dry = this.active.filter((i) => this.plants[i] && this.plants[i].growth < 1).sort((a, b) => this.plants[a].water - this.plants[b].water)[0];
    if (dry != null) { this.plants[dry].water = 1; this.plants[dry].growth = Math.min(1, this.plants[dry].growth + 0.04); return 'water'; }
    return null;
  }

  describe() {
    if (this.doneAt != null) return this.msg;
    return (this.giant ? [this.giant] : this.plants).map((p) => {
      if (!p) return 'empty spot';
      const n = (p.golden ? 'golden ' : '') + plantName(p.kind);
      if (p.bug) return `${n} has a bug!`;
      if (p.water < 0.2) return `${n} is thirsty`;
      return p.growth >= 1 ? `${n} in bloom` : `${n} ${Math.round(p.growth * 100)}%`;
    }).join(' · ').replace(/^./, (ch) => ch.toUpperCase());
  }

  /** Draws the box with its bottom-centre at screen point (x, y), `px` screen pixels per art pixel. */
  draw(ctx, x, y, px) {
    const W = 38, x0 = Math.round(x - (W * px) / 2), soilY = y - 6 * px;
    const cell = (cx, cy, color) => { ctx.fillStyle = color; ctx.fillRect(x0 + cx * px, cy, px, px); };
    [6, 19, 32].forEach((sx, i) => {
      const p = this.giant ? this.giant : this.plants[i];
      const soil = !p ? '#8a5a35' : p.water > 0.55 ? '#4a2e1a' : p.water > 0.2 ? '#6b4428' : '#9c7048';
      for (let cx = sx - 6; cx <= sx + 6; cx++) if (cx > 0 && cx < W - 1) cell(cx, soilY, soil);
      const plant = this.giant ? (i === 1 ? this.giant : null) : p;
      if (!plant) return;
      const rows = rowsFor(plant);
      const left = rows[0].length > 12 ? sx - Math.floor(rows[0].length / 2) : sx - 5;
      rows.forEach((row, ry) => [...row].forEach((ch, rx) => {
        if (!PAL[ch]) return;
        cell(left + rx, soilY - (rows.length - ry) * px, plant.golden ? goldify(PAL[ch]) : PAL[ch]);
      }));
      if (plant.bug) { const by = soilY - (rows.length - Math.max(1, Math.floor(rows.length / 3))) * px; cell(sx + 2, by, '#2b2620'); cell(sx + 3, by, '#9acd32'); cell(sx + 2, by + px, '#9acd32'); }
    });
    ctx.fillStyle = '#d9a066'; ctx.fillRect(x0, soilY + px, W * px, px);
    ctx.fillStyle = '#b07a44'; ctx.fillRect(x0, soilY + 2 * px, W * px, 3 * px);
    ctx.fillStyle = '#7a5230';
    for (const cx of [0, 13, 26, W - 1]) ctx.fillRect(x0 + cx * px, soilY + 2 * px, px, 3 * px);
    ctx.fillRect(x0 + px, soilY + 5 * px, (W - 2) * px, px);
  }
}
