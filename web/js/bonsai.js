// The project bonsai: a port of the Mac app's Bonsai.swift (the record and its deterministic layout) and
// BonsaiArt.swift (the pixel art). Every project you work on with Claude grows a tree from the work:
//   a new session → a new branch (up to twelve; after that the tree thickens instead)
//   a file edit   → a leaf: the foliage pad on that session's branch fills out
//   a finished task → a flower on that pad;  tests pass → a golden fruit
// The species, style and pot come from the project's name, so the same project always grows the same tree, and it
// changes with the seasons: maples turn red in autumn, cherries blossom in spring, the deciduous ones stand bare in winter.
// Layout coordinates are points with the origin at the middle of the pot's top (soil level), y up.
import { PixelCanvas, ArtRNG, SplitMix64, fnv1a, int, rounded, u64 } from './pixelart.js';

const V = (x, y) => ({ x, y });
const add = (a, b) => V(a.x + b.x, a.y + b.y);
const sub = (a, b) => V(a.x - b.x, a.y - b.y);
const mul = (a, s) => V(a.x * s, a.y * s);

export const SPECIES = ['pine', 'maple', 'cherry', 'juniper', 'wisteria', 'olive'];
export const FORMS = ['upright', 'informal', 'windswept', 'cascade'];
export const FORM_NAMES = { upright: 'formal upright', informal: 'informal upright', windswept: 'windswept', cascade: 'cascade' };
export const MAX_BRANCHES = 12;
/** Loses its leaves in winter. */
export const deciduous = (species) => ['maple', 'cherry', 'wisteria'].includes(species);
export const isWinter = (m) => m === 12 || m <= 2;
/** Art pixels per layout point at scale 1 (the Mac app's `artScale`). */
export const ART_SCALE = 3;

export class Bonsai {
  constructor(project, now = Date.now() / 1000) {
    this.project = project;
    this.seed = Bonsai.hash(project);
    this.species = SPECIES[Number(this.seed % BigInt(SPECIES.length))];
    this.form = FORMS[Number((this.seed >> 8n) % BigInt(FORMS.length))];
    this.pot = Number((this.seed >> 16n) % 4n);
    this.branches = [];          // { side (+1 right, -1 left), edits, blooms, fruit }
    this.sessions = 0;
    this.minutes = 0;
    this.firstSeen = now; this.lastSeen = now;
    this.currentSession = null; this.currentBranch = null;
  }

  /** FNV-1a, so the same project name always grows the same tree. */
  static hash(s) { return fnv1a(s); }

  get edits() { return this.branches.reduce((n, b) => n + b.edits, 0); }
  get blooms() { return this.branches.reduce((n, b) => n + b.blooms, 0); }
  get fruit() { return this.branches.reduce((n, b) => n + b.fruit, 0); }
  /** 0 (a seedling) ... 1 (a venerable tree, around 400 edits and a dozen sessions). */
  get stature() { return Math.min(1, 0.75 * Math.log2(1 + this.edits) / 8.6 + 0.25 * Math.min(this.sessions, 12) / 12); }
  ageDays(now) { return Math.max(0, now - this.firstSeen) / 86400; }

  /** A Claude session starts (or sends another prompt). A new session sprouts a branch; the same one carries on.
   *  Returns true when a branch sprouted. */
  startSession(key, now) {
    this.lastSeen = now;
    if (this.currentSession === key && this.currentBranch != null && this.currentBranch < this.branches.length) return false;
    this.currentSession = key;
    this.sessions += 1;
    if (this.branches.length < MAX_BRANCHES) {
      const side = this.form === 'windswept' ? ((this.seed >> 24n) % 2n === 0n ? 1 : -1) : (this.branches.length % 2 === 0 ? 1 : -1);
      this.branches.push({ side, edits: 0, blooms: 0, fruit: 0 });
      this.currentBranch = this.branches.length - 1;
      return true;
    }
    // Full: the thinnest branch takes the new growth, and the tree gets denser.
    this.currentBranch = this.thinnest();
    return false;
  }
  endSession() { this.currentSession = null; }

  thinnest() {
    let best = null;
    this.branches.forEach((b, i) => { if (best == null || b.edits < this.branches[best].edits) best = i; });
    return best;
  }
  /** Where new growth goes (the current branch, or the thinnest one). */
  get growthBranch() {
    if (this.currentBranch != null && this.currentBranch < this.branches.length) return this.currentBranch;
    return this.thinnest();
  }
  /** Claude did something: the tree grows a `leaf`, `bloom` or `fruit`. Returns the branch it went on. */
  grow(part, count = 1) {
    const b = this.growthBranch;
    if (b == null || count <= 0) return null;
    this.branches[b][part === 'leaf' ? 'edits' : part === 'bloom' ? 'blooms' : 'fruit'] += count;
    return b;
  }

  toJSON() {
    const { project, branches, sessions, minutes, firstSeen, lastSeen } = this;
    return { project, branches, sessions, minutes, firstSeen, lastSeen };
  }
  static fromJSON(o) {
    if (!o || typeof o.project !== 'string') return null;
    const b = new Bonsai(o.project, +o.firstSeen || Date.now() / 1000);
    b.branches = (Array.isArray(o.branches) ? o.branches : []).slice(0, MAX_BRANCHES)
      .map((br) => ({ side: br.side < 0 ? -1 : 1, edits: Math.max(0, br.edits | 0), blooms: Math.max(0, br.blooms | 0), fruit: Math.max(0, br.fruit | 0) }));
    b.sessions = Math.max(b.branches.length, o.sessions | 0);
    b.minutes = +o.minutes || 0;
    b.lastSeen = +o.lastSeen || b.firstSeen;
    return b;
  }
}

// ---------------------------------------------------------------- shape

/**
 * A classic bonsai silhouette: a tapering trunk with movement, the lowest branches longest and each one shorter up the
 * tree, pads of foliage at the end of every limb and twig, a crown on top and surface roots at the base. Deterministic
 * from the record, so the same work always grows the same tree, and it only ever adds to what was there.
 * Returns { trunk, limbs: [{points, thickness}], roots, pads: [{center, rx, ry, branch, blooms, fruit}], potWidth,
 * potHeight, thickness, bounds: {x, y, w, h} } (bounds include the pot; y from -potHeight).
 */
export function layoutBonsai(b) {
  const rng = new SplitMix64(b.seed + 1n);
  const s = b.stature;
  const H = 48 + 160 * s;
  const W = 70 + 250 * s;
  const windDir = (b.seed >> 24n) % 2n === 0n ? 1 : -1;
  const phase = rng.range(0, 6.28);
  const wiggle = Array.from({ length: 10 }, () => rng.range(-1, 1));

  // Trunk.
  const trunk = [V(0, 0)];
  const n = 8;
  for (let k = 1; k <= n; k++) {
    const t = k / n;
    let p;
    switch (b.form) {
      case 'upright': p = V(0.05 * H * t + wiggle[k] * 3 * s, t * H); break;
      case 'informal': p = V(Math.sin(t * Math.PI * 1.7 + phase) * (12 + 18 * s) + wiggle[k] * 2, t * H); break;
      case 'windswept': p = V(windDir * (0.08 * H * t + 0.45 * H * t * t), t * H * (1 - 0.28 * t)); break;
      default:   // cascade
        if (t < 0.3) p = V(windDir * t * 26, t * H * 0.9);
        else p = V(windDir * (8 + (t - 0.3) * H * 0.8), 0.27 * H - (t - 0.3) * H * 0.9);
    }
    trunk.push(p);
  }
  const along = (t) => {
    const f = t * n, i = Math.min(n - 1, int(f)), u = f - i;
    return add(trunk[i], mul(sub(trunk[i + 1], trunk[i]), u));
  };
  const baseThickness = 5 + 15 * s;

  // Surface roots.
  const roots = [];
  const rootCount = s < 0.15 ? 0 : 2 + int(s * 3);
  for (let r = 0; r < rootCount; r++) {
    const dir = r % 2 === 0 ? 1 : -1;
    const len = (8 + 14 * s) * rng.range(0.7, 1.3);
    roots.push([V(dir * baseThickness * 0.3, 2), V(dir * len * 0.6, 0.5), V(dir * len, -1)]);
  }

  // Branches, longest at the bottom, each with its pad and (as it fills out) a twig or two.
  const limbs = [], pads = [];
  const count = b.branches.length;
  b.branches.forEach((br, i) => {
    const brng = new SplitMix64(b.seed ^ u64(BigInt(i + 1) * 0x9E3779B97F4A7C15n));
    const t = Math.min(0.9, 0.2 + 0.68 * (i + 0.5) / Math.max(count, 1));
    const root = along(t);
    const fullness = Math.min(1, Math.log2(1 + br.edits) / 7);
    const L = W * 0.5 * (1 - 0.55 * t) * (0.45 + 0.55 * fullness);
    const side = b.form === 'windswept' ? windDir : br.side;
    let angle;
    switch (b.form) {
      case 'windswept': angle = brng.range(-0.1, 0.25); break;
      case 'cascade': angle = t > 0.45 ? brng.range(-0.55, -0.2) : brng.range(0.05, 0.35); break;
      default: angle = brng.range(0.08, 0.32) - 0.12 * t;   // upper branches flatter
    }
    const droop = s > 0.6 ? -0.08 * fullness : 0;   // old branches sag a little at the tip
    const p1 = add(root, V(side * Math.cos(angle + 0.22) * L * 0.45, Math.sin(angle + 0.22) * L * 0.45));
    const end = add(p1, V(side * Math.cos(angle + droop) * L * 0.55, Math.sin(angle + droop) * L * 0.55));
    const thick = baseThickness * (0.55 - 0.3 * t);
    limbs.push({ points: [root, p1, end], thickness: thick });
    const rx = (10 + 26 * fullness) * (0.55 + 0.45 * s);
    const padCenters = [end];
    if (fullness > 0.35) {
      const q = add(p1, V(side * Math.cos(angle + 0.9) * L * 0.32, Math.sin(angle + 0.9) * L * 0.32));
      limbs.push({ points: [p1, q], thickness: thick * 0.5 });
      padCenters.push(q);
    }
    if (fullness > 0.7) {
      const m = add(p1, mul(sub(end, p1), 0.55));
      const q = add(m, V(side * Math.cos(angle - 0.35) * L * 0.28, Math.sin(angle - 0.35) * L * 0.28 - 4));
      limbs.push({ points: [m, q], thickness: thick * 0.45 });
      padCenters.push(q);
    }
    // Blooms and fruit spread over this branch's pads.
    const pc = padCenters.length;
    const bloomSpots = padCenters.map(() => []), fruitSpots = padCenters.map(() => []);
    padCenters.forEach((c, k) => {
      const r = k === 0 ? rx : rx * 0.68;
      for (let j = 0; j < 4; j++) bloomSpots[k].push(add(c, V(brng.range(-0.8, 0.8) * r, brng.range(-0.1, 0.9) * r * 0.4)));
      for (let j = 0; j < 3; j++) fruitSpots[k].push(add(c, V(brng.range(-0.7, 0.7) * r, -r * 0.4 - 3 - brng.range(0, 5))));
    });
    let bloomsLeft = Math.min(br.blooms, 4 * pc), fruitLeft = Math.min(br.fruit, 3 * pc);
    padCenters.forEach((c, k) => {
      const r = k === 0 ? rx : rx * 0.68;
      const nb = Math.min(bloomSpots[k].length, int((bloomsLeft + pc - 1 - k) / pc));
      const nf = Math.min(fruitSpots[k].length, int((fruitLeft + pc - 1 - k) / pc));
      bloomsLeft -= nb; fruitLeft -= nf;
      pads.push({ center: c, rx: r, ry: r * 0.4, branch: i, blooms: bloomSpots[k].slice(0, nb), fruit: fruitSpots[k].slice(0, nf) });
    });
  });
  // The crown: a cluster at the top (for a cascade, at the bend).
  const top = b.form === 'cascade' ? add(along(0.3), V(-windDir * 5, 10)) : add(trunk[n], V(0, 5));
  const crx = 11 + 22 * s, cry = crx * 0.42;
  pads.push({ center: top, rx: crx, ry: cry, branch: -1, blooms: [], fruit: [] });
  if (s > 0.4) {
    pads.push({ center: add(top, V(-crx * 0.7, -cry * 0.9)), rx: crx * 0.65, ry: cry * 0.7, branch: -1, blooms: [], fruit: [] });
    pads.push({ center: add(top, V(crx * 0.75, -cry * 1.1)), rx: crx * 0.6, ry: cry * 0.7, branch: -1, blooms: [], fruit: [] });
  }

  // Pot, and the bounds of it all.
  const potW = 44 + 56 * s, potH = 15 + 13 * s;
  let minX = -potW / 2, maxX = potW / 2, minY = -potH, maxY = 0;
  for (const p of trunk) { minX = Math.min(minX, p.x - 6); maxX = Math.max(maxX, p.x + 6); minY = Math.min(minY, p.y); maxY = Math.max(maxY, p.y); }
  for (const r of roots) for (const p of r) { minX = Math.min(minX, p.x - 2); maxX = Math.max(maxX, p.x + 2); }
  for (const p of pads) {
    minX = Math.min(minX, p.center.x - p.rx - 3); maxX = Math.max(maxX, p.center.x + p.rx + 3);
    minY = Math.min(minY, p.center.y - p.ry - 10); maxY = Math.max(maxY, p.center.y + p.ry + 5);
  }
  return { trunk, limbs, roots, pads, potWidth: potW, potHeight: potH, thickness: baseThickness,
    bounds: { x: minX - 4, y: minY - 2, w: maxX - minX + 8, h: maxY - minY + 6 } };
}

// ---------------------------------------------------------------- art

/** Bark, leaf and bloom colours for a species in a given month (1...12). */
export function palette(sp, month) {
  const autumn = month >= 9 && month <= 11, spring = month >= 3 && month <= 5;
  switch (sp) {
    case 'pine':
      return { bark: 0x6E5A4A, barkLight: 0x8C7560, barkDark: 0x4A3A2E, leaf: 0x2F6B3A, leafLight: 0x4E9A4A, leafDark: 0x1F4A2A, bloom: 0xC9A24A, bloomLight: 0xF2D37A };
    case 'maple': {
      const [l, ll, ld] = autumn ? [0xE0582C, 0xF7B45C, 0xA83A1E] : [0x5DBB46, 0x9BE36A, 0x2F7A2C];
      return { bark: 0x8A8278, barkLight: 0xA59D92, barkDark: 0x5E5850, leaf: l, leafLight: ll, leafDark: ld, bloom: 0xE8574A, bloomLight: 0xFF9A8A };
    }
    case 'cherry': {
      const [l, ll, ld] = spring ? [0xF7B6D2, 0xFFE0EF, 0xD6789F] : [0x4FA83A, 0x8BD66A, 0x2F7A2C];
      return { bark: 0x5A3A2A, barkLight: 0x7A5232, barkDark: 0x3A2418, leaf: l, leafLight: ll, leafDark: ld, bloom: 0xFF8FB1, bloomLight: 0xFFE0EF };
    }
    case 'juniper':
      return { bark: 0x8A4A3A, barkLight: 0xA8685A, barkDark: 0x5E2E22, leaf: 0x4F8F7A, leafLight: 0x7FBFA8, leafDark: 0x2F5F52, bloom: 0xF2D37A, bloomLight: 0xFFF3C4 };
    case 'wisteria':
      return { bark: 0x6E6258, barkLight: 0x8E8276, barkDark: 0x4A4038, leaf: 0x5E9E46, leafLight: 0x8BD66A, leafDark: 0x3E7A34, bloom: 0xB98CFF, bloomLight: 0xE0C2FF };
    default:   // olive
      return { bark: 0x7A7060, barkLight: 0x9A9080, barkDark: 0x524A3E, leaf: 0x8FA98A, leafLight: 0xC2D4B8, leafDark: 0x5F7A5C, bloom: 0xFFFFFF, bloomLight: 0xFFFFFF };
  }
}

/**
 * Draws a tree from its layout at `scale` points per point (art pixels = points * scale / ART_SCALE): pot, surface roots,
 * a tapering trunk with lit and shaded bark, limbs and twigs, clouds of foliage in the species' colours for the season,
 * blossoms, golden fruit, and the marks of age (moss on the pot, lichen on old bark, silvered deadwood on an old juniper).
 * Returns { canvas: PixelCanvas, anchor: {x, y} } where `anchor` is where the layout origin (the pot's top-centre) sits in
 * the image, as a fraction of its size measured from the bottom-left.
 */
export function renderBonsai(b, layout, scale, month, night, ageDays = 0) {
  const k = scale / ART_SCALE;
  const bounds = layout.bounds, minX = bounds.x, minY = bounds.y;
  const w = Math.max(4, Math.ceil(bounds.w * k)), h = Math.max(4, Math.ceil(bounds.h * k));
  const cv = new PixelCanvas(w, h);
  const pal = palette(b.species, month);
  const winter = isWinter(month);
  const r = new ArtRNG(b.seed + 9n);
  const px = (p) => [(p.x - minX) * k, (p.y - minY) * k];
  const pline = (a, c, col, width) => { const [x0, y0] = px(a), [x1, y1] = px(c); cv.line(x0, y0, x1, y1, col, Math.max(1, width)); };

  // Pot.
  drawPot(cv, b.pot, layout.potWidth * k, layout.potHeight * k, px(V(0, 0)), ageDays, winter);

  // Trunk (behind the limbs), tapering, with a lit side and a shaded side.
  const trunkPixels = [];
  const segs = layout.trunk.length - 1;
  for (let i = 0; i < segs; i++) {
    const t = i / segs;
    const thick = Math.max(1, int(rounded(layout.thickness * (1 - 0.7 * t) * k)));
    pline(layout.trunk[i], layout.trunk[i + 1], pal.bark, thick);
  }
  // Bark texture: a light column on the left of the trunk, dark on the right.
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    if (cv.get(x, y) !== pal.bark) continue;
    trunkPixels.push([x, y]);
    if (cv.get(x - 1, y) == null) cv.set(x, y, pal.barkLight);
    else if (cv.get(x + 1, y) == null) cv.set(x, y, pal.barkDark);
  }
  // Surface roots over the soil.
  for (const root of layout.roots) for (let i = 0; i < root.length - 1; i++) pline(root[i], root[i + 1], i === 0 ? pal.bark : pal.barkDark, i === 0 ? 2 : 1);
  // Limbs and twigs.
  for (const limb of layout.limbs) {
    for (let i = 0; i < limb.points.length - 1; i++) {
      const thick = Math.max(1, int(rounded(limb.thickness * (1 - 0.5 * i / Math.max(1, limb.points.length - 1)) * k)));
      pline(limb.points[i], limb.points[i + 1], i === 0 ? pal.bark : pal.barkDark, thick);
    }
  }
  // Old juniper: a silvered streak of deadwood up the trunk.
  if (b.species === 'juniper' && ageDays > 14) {
    for (let i = 0; i < segs; i++) pline(add(layout.trunk[i], V(2, 0)), add(layout.trunk[i + 1], V(2, 0)), 0xE8E4DA, 1);
  }
  // Lichen on old bark.
  if (ageDays > 7) {
    for (const [x, y] of trunkPixels) if (r.next() < Math.min(0.18, ageDays / 200)) cv.set(x, y, 0xBFD8B0);
  }

  // Foliage.
  for (const pad of layout.pads) {
    const [cx, cy] = px(pad.center);
    const rx = pad.rx * k, ry = pad.ry * k;
    if (winter && deciduous(b.species)) {
      // Bare: a fan of twigs with snow at the tips.
      for (let n = 0; n < 5; n++) {
        const a = 0.25 + n * 0.65;
        const ex = cx + Math.cos(a) * rx * 0.9, ey = cy + Math.sin(a) * ry * 1.6;
        cv.line(cx, cy, ex, ey, pal.bark);
        cv.set(int(ex), int(ey) + 1, 0xFFFFFF);
      }
      continue;
    }
    cv.blob(cx, cy - ry * 0.25, rx, ry * 0.95, pal.leafDark);
    cv.blob(cx, cy, rx, ry, pal.leaf, pal.leafLight, pal.leafDark);
    cv.blob(cx - rx * 0.28, cy + ry * 0.3, rx * 0.5, ry * 0.5, pal.leafLight);
    texture(cv, b.species, cx, cy, rx, ry, pal, r);
    if (winter) {
      // Snow along the top of evergreen pads.
      for (let x = int(cx - rx); x <= int(cx + rx); x++) {
        const dx = (x + 0.5 - cx) / rx;
        if (!(Math.abs(dx) < 1)) continue;
        const top = int(cy + ry * Math.sqrt(1 - dx * dx)) - 1;
        if (cv.get(x, top) != null) cv.set(x, top, 0xFFFFFF);
      }
    }
  }
  // Blossoms (per species) and golden fruit.
  for (const pad of layout.pads) {
    for (const p of pad.blooms) {
      const [x, y] = px(p);
      switch (b.species) {
        case 'pine': cv.rect(int(x), int(y) - 1, 2, 3, pal.bloom); cv.set(int(x), int(y) + 1, pal.bloomLight); break;   // little cones
        case 'wisteria': {   // hanging racemes
          const len = 3 + int(r.range(0, 3));
          for (let d = 0; d < len; d++) cv.set(int(x), int(y) - d - 2, d === 0 ? pal.bloomLight : pal.bloom);
          break;
        }
        default: cv.blob(x, y, 1.3, 1.3, pal.bloom, pal.bloomLight);
      }
    }
    for (const p of pad.fruit) {
      const [x, y] = px(p);
      cv.blob(x, y, 1.7, 1.7, night ? 0xFFD84A : 0xF2B33A, 0xFFF3A0, 0xB8761A);
      cv.set(int(x), int(y) + 2, pal.barkDark);   // its stalk
    }
  }
  cv.outline(0.66);
  return { canvas: cv, anchor: { x: (-minX * k) / w, y: (-minY * k) / h } };
}

/** Species-specific texture on a foliage pad. */
function texture(cv, sp, cx, cy, rx, ry, pal, r) {
  const x0 = int(cx - rx), x1 = int(cx + rx), y0 = int(cy - ry), y1 = int(cy + ry);
  if (!(x1 > x0 && y1 > y0)) return;
  switch (sp) {
    case 'pine':
      // Needle layers: dithered dark rows through the lower half, and a fringe hanging under the edge.
      for (let y = y0; y <= int(cy); y++) for (let x = x0; x <= x1; x++) if ((x + y) % 2 === 0 && cv.get(x, y) === pal.leaf) cv.set(x, y, pal.leafDark);
      for (let x = x0 + 1; x <= x1 - 1; x += 3) if (cv.get(x, y0) != null && cv.get(x, y0 - 1) == null) cv.set(x, y0 - 1, pal.leafDark);
      break;
    case 'juniper':
      for (let y = y0; y <= y1; y += 2) for (let x = x0; x <= x1; x++) if (cv.get(x, y) === pal.leaf && r.next() < 0.6) cv.set(x, y, pal.leafDark);
      break;
    case 'olive':
      for (let i = 0, n = int(rx * ry / 3); i < n; i++) {
        const x = int(r.range(x0, x1)), y = int(r.range(y0, y1));
        if (cv.get(x, y) === pal.leaf) cv.set(x, y, pal.leafLight);
      }
      break;
    default:   // maple, cherry, wisteria
      for (let i = 0, n = int(rx * ry / 5); i < n; i++) {
        const x = int(r.range(x0, x1)), y = int(r.range(y0, y1));
        if (cv.get(x, y) === pal.leaf) cv.set(x, y, r.next() < 0.5 ? pal.leafLight : pal.leafDark);
      }
  }
}

const POTS = [
  [0x3F6FA8, 0x6F9FD8, 0x2A4A78],   // glazed blue
  [0xA8684A, 0xC9895F, 0x7A4A32],   // unglazed terracotta
  [0x8E8B83, 0xB8B6AE, 0x5E5B55],   // stone tray
  [0x4F9A7A, 0x7FC9A8, 0x2F6B52],   // glazed jade
];

function drawPot(cv, style, potW, potH, [ox, oy], ageDays, winter) {
  const w = Math.max(6, int(potW)), hgt = Math.max(4, int(style === 2 ? potH * 0.6 : potH));
  const x0 = int(ox - potW / 2), y0 = int(oy) - hgt;
  const [body, light, dark] = POTS[style % 4];
  for (let y = 0; y < hgt; y++) {
    const taper = style === 1 ? 0 : (y < 2 ? 2 - y : 0);          // rounded bottom corners
    const inset = style === 1 ? (y === hgt - 1 ? -1 : 0) : taper;  // the terracotta pot has a lip
    cv.rect(x0 + inset, y0 + y, w - inset * 2, 1, y === hgt - 1 ? light : (y === 0 ? dark : body));
  }
  cv.rect(x0 + 1, y0 + 1, 2, hgt - 2, light);          // glaze highlight
  cv.rect(x0 + w - 3, y0 + 1, 2, hgt - 2, dark);       // shaded side
  if (style === 0 || style === 3) for (let x = x0 + 5; x < x0 + w - 5; x += 7) cv.set(x, y0 + int(hgt / 2), light);   // crackle glints
  // Soil.
  const soilRows = Math.min(2, hgt - 1);
  for (let y = 0; y < soilRows; y++) cv.rect(x0 + 2, y0 + hgt - 1 - y, w - 4, 1, 0x4A3424);
  for (let x = x0 + 3; x < x0 + w - 3; x += 4) cv.set(x, y0 + hgt - 1, 0x6B4A30);
  // Moss gathers on an old pot.
  if (ageDays > 2) {
    const r = new ArtRNG(w * 31 + style);
    const cover = Math.min(0.7, ageDays / 40);
    for (let x = x0; x < x0 + w; x++) if (r.next() < cover) cv.set(x, y0 + hgt - 1, r.next() < 0.5 ? 0x5E9E46 : 0x7DBE52);
    for (let x = x0; x < x0 + w; x += 5) if (r.next() < cover * 0.6) { cv.set(x, y0 + hgt - 2, 0x5E9E46); if (r.next() < 0.5) cv.set(x, y0 + hgt - 3, 0x4F8A3A); }
  }
  if (winter) for (let x = x0; x < x0 + w; x++) if (x % 3 !== 0) cv.set(x, y0 + hgt, 0xFFFFFF);
}
