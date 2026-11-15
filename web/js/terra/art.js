// Pixel art for the Terrarium (web/terrarium.html): the glass room, the moss as it takes over, and everything the
// Gremlets build. Everything is snapped to the room's pixel grid (P screen pixels per art pixel), so it matches their
// chunky look. Coordinates here are SCREEN coordinates (y down); main.js converts.

export const C = {
  moss: '#5aa54e', mossLight: '#7cc46a', mossDark: '#3e7a34', mossTip: '#9ad884',
  wood: '#a5774f', woodLight: '#c08e5f', woodDark: '#6b4428', twig: '#8a5f3e',
  pink: '#ff8fb1', yellow: '#ffe45c', white: '#ffffff', blue: '#8fd3ff', red: '#e0453a', orange: '#f28a2e',
  water: '#6fb8e6', waterLight: '#bfe6fa', waterDark: '#3f8cc9',
};

/** A seeded random stream (so the moss and the plants look the same every time). */
export function rng(seed) {
  let s = seed >>> 0;
  return () => { s = (s + 0x6d2b79f5) >>> 0; let t = Math.imul(s ^ (s >>> 15), s | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}

const snap = (v, P) => Math.round(v / P) * P;

/** A soft round glow (radial, fading to nothing). */
export function glow(g, x, y, r, rgb, a) {
  const gr = g.createRadialGradient(x, y, 0, x, y, r);
  gr.addColorStop(0, `rgba(${rgb},${a})`); gr.addColorStop(1, `rgba(${rgb},0)`);
  g.fillStyle = gr; g.fillRect(x - r, y - r, r * 2, r * 2);
}

/** Fills art pixels: (x, y) in screen pixels, snapped; w, h in art pixels. */
export function px(g, x, y, w, h, color, P) {
  g.fillStyle = color;
  g.fillRect(snap(x, P), snap(y, P), w * P, h * P);
}

// ---------------------------------------------------------------- the room

/**
 * The glass room behind everything: pearly white (dusky blue at night), a glossy floor, and the moss on the floor,
 * up the walls and over the ceiling for moss level `m` (0...1). Drawn once into a canvas, redrawn as the moss grows.
 */
export function paintRoom(g, { W, H, P, floor, m, seedX, night, overgrown }) {
  const sky = g.createLinearGradient(0, 0, 0, H);
  if (night) { sky.addColorStop(0, '#262d45'); sky.addColorStop(1, '#1b2133'); }
  else { sky.addColorStop(0, '#fbfdff'); sky.addColorStop(0.7, '#f1f5f8'); sky.addColorStop(1, '#e6ecf1'); }
  g.fillStyle = sky; g.fillRect(0, 0, W, H);
  // A soft glow in the middle of the glass.
  const glow = g.createRadialGradient(W * 0.5, H * 0.35, 10, W * 0.5, H * 0.35, Math.max(W, H) * 0.7);
  glow.addColorStop(0, night ? 'rgba(120,140,200,0.10)' : 'rgba(255,255,255,0.9)'); glow.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = glow; g.fillRect(0, 0, W, H);
  // The glossy floor: pale tiles with a reflection line.
  const fy = H - floor;
  g.fillStyle = night ? '#2c3448' : '#f4f7f9'; g.fillRect(0, fy, W, floor);
  g.fillStyle = night ? '#3a4460' : '#ffffff'; g.fillRect(0, fy, W, P);
  g.fillStyle = night ? '#232a3c' : '#dfe6ec';
  for (let x = 0; x < W; x += P * 24) g.fillRect(snap(x, P), fy + P * 2, P, floor);
  g.fillRect(0, fy + P * 6, W, P);
  if (m <= 0) return;
  paintMoss(g, { W, H, P, fy, m, seedX, night, overgrown });
}

function paintMoss(g, { W, H, P, fy, m, seedX, night, overgrown }) {
  const r = rng(7);
  const dark = night ? '#2f5a2c' : C.mossDark, base = night ? '#3c6e38' : C.moss, light = night ? '#4f8a48' : C.mossLight, tip = night ? '#62a058' : C.mossTip;
  const flowers = night ? ['#c07090', '#c0b050', '#b0b8c8'] : [C.pink, C.yellow, C.white];
  // The floor: spreading out from where the first seed went in.
  const reach = Math.min(1, m / 0.3) * W * 0.75;
  const lo = Math.max(0, seedX - reach), hi = Math.min(W, seedX + reach);
  for (let x = snap(lo, P); x < hi; x += P) {
    const edge = Math.min(x - lo, hi - x) / (P * 6);
    const t = Math.max(1, Math.min(4, Math.round(1 + r() * 2.2 + Math.min(1.5, edge * 0.5))));
    for (let k = 0; k < t; k++) { g.fillStyle = k === t - 1 ? light : k === 0 ? dark : base; g.fillRect(x, fy - (k + 1) * P, P, P); }
    if (r() < 0.12) { g.fillStyle = tip; g.fillRect(x, fy - (t + 1) * P, P, P); }
    if (r() < 0.035 && m > 0.15) { g.fillStyle = flowers[(r() * 3) | 0]; g.fillRect(x, fy - (t + 1) * P, P, P); }
  }
  // Up the glass walls.
  if (m > 0.28) {
    const up = Math.min(1, (m - 0.28) / 0.32) * fy;
    for (const side of [0, 1]) {
      for (let y = fy; y > fy - up; y -= P) {
        const wdt = Math.max(1, Math.round(2 + r() * 3 + (y > fy - up + P * 8 ? 1 : -1)));
        for (let k = 0; k < wdt; k++) {
          g.fillStyle = k === wdt - 1 ? light : k === 0 ? dark : base;
          g.fillRect(side ? W - (k + 1) * P : k * P, snap(y, P), P, P);
        }
        if (r() < 0.03) { g.fillStyle = flowers[(r() * 3) | 0]; g.fillRect(side ? W - (wdt + 1) * P : wdt * P, snap(y, P), P, P); }
      }
    }
  }
  // Over the ceiling, in from both corners, and then hanging down in strands.
  if (m > 0.55) {
    const across = Math.min(1, (m - 0.55) / 0.3) * W * 0.5;
    for (let x = 0; x < W; x += P) {
      if (x > across && x < W - across) continue;
      const t = Math.max(1, Math.round(2 + r() * 2));
      for (let k = 0; k < t; k++) { g.fillStyle = k === t - 1 ? light : k === 0 ? dark : base; g.fillRect(x, k * P, P, P); }
      const strand = m > 0.75 && r() < (overgrown ? 0.22 : 0.08);
      if (strand) {
        const len = Math.round((overgrown ? 6 : 3) + r() * (overgrown ? 26 : 10));
        for (let k = t; k < t + len; k++) { g.fillStyle = k % 3 === 0 ? light : base; g.fillRect(x, k * P, P, P); }
        if (r() < 0.4) { g.fillStyle = flowers[(r() * 3) | 0]; g.fillRect(x, (t + len) * P, P, P); }
      }
    }
  }
}

/** The glass itself, over everything: a thin frame and a couple of soft diagonal glints. */
export function paintGlass(g, { W, H, P, night }) {
  g.fillStyle = night ? 'rgba(160,180,230,0.25)' : 'rgba(170,190,205,0.45)';
  g.fillRect(0, 0, W, P); g.fillRect(0, H - P, W, P); g.fillRect(0, 0, P, H); g.fillRect(W - P, 0, P, H);
  g.fillStyle = night ? 'rgba(255,255,255,0.05)' : 'rgba(255,255,255,0.55)';
  g.fillRect(P, P, W - 2 * P, P);
  g.save();
  g.globalAlpha = night ? 0.04 : 0.1;
  g.fillStyle = '#ffffff';
  for (const [x0, w] of [[0.12, 0.05], [0.2, 0.015], [0.74, 0.03]]) {
    g.beginPath();
    g.moveTo(W * x0, 0); g.lineTo(W * (x0 + w), 0); g.lineTo(W * (x0 + w) - H * 0.35, H); g.lineTo(W * x0 - H * 0.35, H);
    g.closePath(); g.fill();
  }
  g.restore();
}

// ---------------------------------------------------------------- what they build

/**
 * A twig ledge from x0 to x1 (screen px) with its top at y, `p` built (0...1): planks go in one at a time from the
 * wall end; the rest is a dotted outline on a pole of scaffolding. Mossy on top once there's moss about.
 */
export function paintLedge(g, { x0, x1, y, p, P, moss, night, fromLeft }) {
  const n = Math.max(1, Math.round((x1 - x0) / (P * 4)));
  const done = Math.floor(n * p + 1e-6);
  for (let i = 0; i < n; i++) {
    const k = fromLeft ? i : n - 1 - i;
    const x = x0 + k * P * 4;
    if (i < done) {
      px(g, x, y, 4, 1, i % 2 ? C.woodLight : C.wood, P);
      px(g, x, y + P, 4, 2, i % 2 ? C.wood : C.twig, P);
      px(g, x, y + P * 3, 4, 1, C.woodDark, P);
      px(g, x + P * 3, y + P, 1, 2, C.woodDark, P);
    } else {
      g.fillStyle = night ? 'rgba(160,190,230,0.35)' : 'rgba(110,150,190,0.35)';
      if (i % 2 === 0) g.fillRect(snap(x, P), snap(y, P), P * 3, P);
    }
  }
  if (p < 1) {
    // A scaffold pole while it's going up.
    const sx = fromLeft ? x0 + done * P * 4 : x1 - done * P * 4;
    g.fillStyle = C.twig; g.fillRect(snap(sx, P), snap(y + P * 4, P), P, P * 400);
    return;
  }
  // A bracket into the glass wall, and moss along the top.
  const wx = fromLeft ? x0 : x1 - P * 2;
  px(g, wx, y + P * 4, 2, 1, C.woodDark, P); px(g, wx + (fromLeft ? 0 : P), y + P * 5, 1, 3, C.woodDark, P);
  if (moss > 0.2) {
    const r = rng(Math.round(x0 * 7 + y));
    for (let x = x0; x < x1; x += P) {
      if (r() < 1 - Math.min(1, (moss - 0.2) * 2.5)) continue;
      g.fillStyle = r() < 0.5 ? (night ? '#3c6e38' : C.moss) : (night ? '#4f8a48' : C.mossLight);
      g.fillRect(snap(x, P), snap(y - P, P), P, P);
      if (r() < 0.12) { g.fillStyle = night ? '#62a058' : C.mossTip; g.fillRect(snap(x, P), snap(y - 2 * P, P), P, P); }
    }
  }
}

/** A climbing vine from (x, top) down to the floor at `bottom`, leaves every few pixels (a ladder for the Gremlets). */
export function paintVine(g, { x, top, bottom, P, t = 0, night }) {
  const sway = Math.round(Math.sin(t * 0.8 + x) * 0.6);
  for (let y = top; y < bottom; y += P) {
    const off = Math.round(Math.sin((y - top) / (P * 6)) * 1 + sway) * P;
    g.fillStyle = night ? '#3c6e38' : C.mossDark; g.fillRect(snap(x + off, P), snap(y, P), P, P);
    if (((y - top) / P) % 5 === 0) { g.fillStyle = night ? '#4f8a48' : C.mossLight; g.fillRect(snap(x + off + ((y / P) % 2 ? P : -P), P), snap(y, P), P, P); }
  }
}

/** The tree in the middle of the room, `s` grown (0...1+): a trunk that thickens, two branches, and a crown of
 *  round leafy clumps (lighter on top), with blossoms once it's big. */
export function paintTree(g, { x, y, s, P, t, night, p = 1 }) {
  const size = Math.max(0.15, Math.min(1, s)) * Math.min(1, p * 1.2);
  const h = Math.round(8 + 30 * size), thick = size > 0.5 ? 3 : 2;
  for (let k = 0; k < h; k++) {
    const w = k < 3 ? thick + 2 : thick;
    px(g, x - Math.floor(w / 2) * P, y - (k + 1) * P, w, 1, k % 5 === 2 ? C.woodDark : (k % 2 ? C.wood : C.twig), P);
  }
  const top = y - h * P;
  if (size > 0.35) for (const d of [-1, 1]) for (let k = 0; k < Math.round(6 * size); k++) px(g, x + d * (k + 1) * P, top + (6 - k) * P, 1, 1, C.wood, P);
  const leaf = night ? ['#2f5a2c', '#3c6e38', '#4f8a48', '#5f9a54'] : [C.mossDark, C.moss, C.mossLight, C.mossTip];
  const R = 4 + 10 * size, sway = Math.sin(t * 0.6) * P * 0.4;
  const clumps = [[0, -R * 0.9, R], [-R * 0.95, -R * 0.35, R * 0.8], [R * 0.95, -R * 0.35, R * 0.8], [-R * 0.45, -R * 1.5, R * 0.7], [R * 0.45, -R * 1.5, R * 0.7]];
  for (const [cx, cy, r] of clumps) {
    for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) {
      if (dx * dx + dy * dy > r * r) continue;
      const shade = dy < -r * 0.45 ? 3 : dy < 0 ? 2 : dy < r * 0.5 ? 1 : 0;
      g.fillStyle = leaf[shade];
      g.fillRect(snap(x + (cx + dx) * P + sway, P), snap(top + (cy + dy) * P, P), P, P);
    }
  }
  if (size > 0.6) {
    const r = rng(11);
    for (let i = 0; i < 9; i++) px(g, x + (r() - 0.5) * R * 3 * P, top - r() * R * 2.2 * P, 1, 1, night ? '#c07090' : (i % 3 ? C.pink : C.white), P);
  }
}

/** A little plant: kind 0 flower, 1 fern, 2 mushroom (glowing ones at night), 3 berry sprig. `s`: grown 0...1. */
export function paintPlant(g, { x, y, kind, s, P, t, night, glow: glowing, hue = 0 }) {
  const h = Math.max(1, Math.round((kind === 2 ? 3 : 5) * Math.min(1, s)));
  const sway = Math.round(Math.sin(t * 1.4 + x * 0.05) * 0.5) * P;
  const stem = night ? '#3c6e38' : C.moss;
  if (kind === 2) {
    px(g, x, y - h * P, 1, h, night ? '#c8c0b0' : '#f2e6d0', P);
    const cap = glowing ? (night ? '#7ff0d8' : '#5fd0b8') : C.red;
    px(g, x - P, y - (h + 1) * P, 3, 1, cap, P); px(g, x, y - (h + 2) * P, 1, 1, cap, P);
    if (!glowing) px(g, x - P, y - (h + 1) * P, 1, 1, '#ffffff', P);
    if (glowing && night) glow(g, x + P / 2, y - (h + 1) * P, P * 7, '127,240,216', 0.35);
    return;
  }
  for (let k = 0; k < h; k++) px(g, x + (k > 1 ? sway : 0), y - (k + 1) * P, 1, 1, stem, P);
  const top = y - (h + 1) * P;
  if (kind === 0 && s >= 0.7) {
    const col = [C.pink, C.yellow, C.white, '#b98cff'][hue % 4];
    px(g, x + sway - P, top + P, 3, 1, col, P); px(g, x + sway, top, 1, 1, col, P); px(g, x + sway, top + P, 1, 1, C.yellow, P);
  } else if (kind === 1) {
    for (let k = 1; k < h; k++) { px(g, x + sway - P, y - (k + 1) * P, 1, 1, night ? '#4f8a48' : C.mossLight, P); px(g, x + sway + P, y - k * P, 1, 1, night ? '#4f8a48' : C.mossLight, P); }
  } else if (kind === 3 && s >= 0.7) {
    px(g, x + sway - P, top + P, 1, 1, C.red, P); px(g, x + sway + P, top + 2 * P, 1, 1, C.red, P); px(g, x + sway, top, 1, 1, '#b02a3a', P);
  } else px(g, x + sway, top + P, 1, 1, night ? '#4f8a48' : C.mossLight, P);
}

/** A hanging home: a woven nest with a leaf roof, a round door, a lit window, a porch, hung by two vines. */
export function paintHome(g, { x, y, p, P, t, night, sway = 0, sleepers = 0, ceiling = 0 }) {
  const ox = x + sway;
  // The vines up to the ceiling.
  for (const dx of [-8, 8]) for (let yy = ceiling; yy < y - 16 * P; yy += P) px(g, ox + dx * P + Math.sin((yy + t * 20) / 40) * 0, yy, 1, 1, night ? '#3c6e38' : C.mossDark, P);
  if (p < 1) {
    // Going up: a frame of twigs, then the weave filling in from the bottom.
    const rows = Math.floor(16 * p);
    for (let k = 0; k < 16; k++) {
      const half = Math.round(9 * Math.sqrt(1 - ((k - 8) / 9) ** 2));
      if (k < rows) px(g, ox - half * P, y - (k + 1) * P, half * 2, 1, k % 2 ? '#c9a15a' : '#b8924e', P);
      else { px(g, ox - half * P, y - (k + 1) * P, 1, 1, C.twig, P); px(g, ox + (half - 1) * P, y - (k + 1) * P, 1, 1, C.twig, P); }
    }
    px(g, ox - 12 * P, y, 24, 1, C.woodDark, P);
    return;
  }
  // The weave.
  for (let k = 0; k < 16; k++) {
    const half = Math.round(9 * Math.sqrt(1 - ((k - 8) / 9) ** 2));
    px(g, ox - half * P, y - (k + 1) * P, half * 2, 1, k % 2 ? '#c9a15a' : '#b8924e', P);
    if (k % 3 === 0) for (let i = -half; i < half; i += 3) px(g, ox + i * P, y - (k + 1) * P, 1, 1, '#a88445', P);
  }
  // Leaf roof.
  for (let k = 0; k < 5; k++) px(g, ox - (11 - k * 2) * P, y - (16 + k) * P, 22 - k * 4, 1, k % 2 ? C.mossLight : C.moss, P);
  // Door and window.
  px(g, ox - 5 * P, y - 7 * P, 3, 6, '#4a3020', P); px(g, ox - 4 * P, y - 8 * P, 1, 1, '#4a3020', P);
  const lit = night || sleepers > 0;
  px(g, ox + 2 * P, y - 11 * P, 3, 3, lit ? '#ffd36b' : '#3b4660', P);
  if (lit) glow(g, ox + 3.5 * P, y - 9.5 * P, P * 10, '255,211,107', 0.35);
  // The porch they stand on.
  px(g, ox - 12 * P, y, 24, 1, C.woodLight, P); px(g, ox - 12 * P, y + P, 24, 1, C.woodDark, P);
  if (sleepers > 0 && Math.floor(t * 1.2) % 2 === 0) px(g, ox + 6 * P, y - 20 * P - Math.floor(t * 3 % 3) * P, 2, 1, '#8fa8d8', P);
}

/** The pond sunk into the floor: a basin of water edged with stones, ripples, lily pads and a flower. */
export function paintPond(g, { x0, x1, y, p, P, t, night }) {
  const w = Math.round((x1 - x0) / P), D = 7;
  for (let i = 0; i < w; i++) {
    const edge = Math.min(i, w - 1 - i);
    const depth = Math.min(D, Math.round(Math.sqrt(edge) * 2.4));
    const fill = Math.round(depth * p);
    for (let k = 0; k < depth; k++) {
      const wet = k >= depth - fill;
      px(g, x0 + i * P, y + k * P, 1, 1, !wet ? '#c8bca8' : k === 0 ? (night ? '#4a7aa0' : C.water) : k < 3 ? (night ? '#3a6890' : '#5aa8dc') : (night ? '#2f5c80' : C.waterDark), P);
    }
    if (edge === 0 || edge === 1) px(g, x0 + i * P, y - P, 1, 1, edge ? '#9a8f80' : '#b8ad9c', P);
  }
  if (p >= 1) {
    const rip = (t * 5) % w;
    px(g, x0 + Math.round(rip) * P, y, 2, 1, night ? '#7aa8c8' : C.waterLight, P);
    px(g, x0 + Math.round((rip + w / 2) % w) * P, y + P, 1, 1, night ? '#7aa8c8' : C.waterLight, P);
    for (const [f, len] of [[0.28, 3], [0.62, 2], [0.45, 2]]) px(g, x0 + Math.round(w * f) * P, y, len, 1, C.mossLight, P);
    px(g, x0 + Math.round(w * 0.28 + 1) * P, y - P, 1, 1, C.pink, P);
  }
}

/** A rope bridge (planks hung from a rope) from xa to xb at y, `p` built in from both ends. */
export function paintBridge(g, { xa, xb, y, p, P, night }) {
  const n = Math.max(1, Math.round((xb - xa) / (P * 2)));
  for (let i = 0; i < n; i++) {
    const fromEnd = Math.min(i, n - 1 - i) / (n / 2);
    if (fromEnd > p) continue;
    const sag = Math.round(Math.sin((i / (n - 1 || 1)) * Math.PI) * 3) * P;
    px(g, xa + i * P * 2, y + sag, 2, 1, i % 3 ? C.woodLight : C.wood, P);
    px(g, xa + i * P * 2, y + sag + P, 2, 1, C.woodDark, P);
    px(g, xa + i * P * 2, y + sag - 4 * P, 2, 1, night ? '#8a7060' : '#b8935a', P);
    if (i % 4 === 0) px(g, xa + i * P * 2, y + sag - 3 * P, 1, 3, night ? '#8a7060' : '#b8935a', P);
  }
}

/** Water pouring off a ledge's end into the pond. */
export function paintFalls(g, { x, top, bottom, p, P, t, night }) {
  const len = (bottom - top) * p;
  for (let y = top; y < top + len; y += P) {
    for (let k = 0; k < 3; k++) {
      const shimmer = (Math.floor(y / P + t * 12 + k * 3) % 5) === 0;
      px(g, x + k * P, y, 1, 1, shimmer ? (night ? '#a8c8e0' : C.waterLight) : (night ? '#4a7aa0' : C.water), P);
    }
  }
  if (p >= 1) for (let k = -2; k < 5; k++) if ((Math.floor(t * 8) + k) % 3 === 0) px(g, x + k * P, bottom - P, 1, 1, C.white, P);
}

/** A little waterwheel turning in the falls: a rim, eight spokes and paddles, on a post. */
export function paintWheel(g, { x, y, p, P, t }) {
  const R = 7, a0 = p >= 1 ? t * 1.2 : 0;
  px(g, x, y, 1, 10, C.woodDark, P);
  for (let i = 0; i < 48; i++) { const a = (i / 48) * Math.PI * 2; if (i / 48 <= p) px(g, x + Math.cos(a) * R * P, y + Math.sin(a) * R * P, 1, 1, C.woodDark, P); }
  for (let k = 0; k < 8; k++) {
    if (k / 8 > p) continue;
    const a = a0 + (k * Math.PI) / 4;
    for (let r = 1; r < R; r++) px(g, x + Math.cos(a) * r * P, y + Math.sin(a) * r * P, 1, 1, C.wood, P);
    px(g, x + Math.cos(a) * (R + 1) * P, y + Math.sin(a) * (R + 1) * P, 1, 1, C.woodLight, P);
  }
  px(g, x - P, y - P, 2, 2, C.woodDark, P);
}

/** A mushroom house: a big spotted cap, a stalk with a door and a round window. */
export function paintShroomHouse(g, { x, y, p, P, night }) {
  const h = Math.round(16 * Math.min(1, p * 1.4));
  for (let k = 0; k < h; k++) px(g, x - 6 * P, y - (k + 1) * P, 12, 1, k % 2 ? '#f2e6d0' : '#e8dcc2', P);
  if (p < 0.6) return;
  px(g, x - 2 * P, y - 7 * P, 4, 6, '#6b4428', P); px(g, x + P, y - 4 * P, 1, 1, '#e0b04a', P);
  px(g, x + 3 * P, y - 12 * P, 2, 2, night ? '#ffd36b' : '#5a6a88', P);
  const capRows = Math.round(9 * Math.min(1, (p - 0.6) / 0.4));
  for (let k = 0; k < capRows; k++) {
    const half = Math.round(13 - k * 1.3);
    px(g, x - half * P, y - (16 + k) * P, half * 2, 1, k % 3 === 0 ? '#c0303a' : C.red, P);
  }
  if (p >= 1) for (const [dx, dy] of [[-8, 18], [-2, 21], [5, 19], [9, 17], [1, 23]]) px(g, x + dx * P, y - dy * P, 2, 1, C.white, P);
}

/** The lanternbloom: a tall stem with a glowing bulb (bright at night). */
export function paintBloom(g, { x, y, p, P, t, night }) {
  const h = Math.round(22 * p);
  for (let k = 0; k < h; k++) px(g, x + Math.round(Math.sin(k / 5) * 0.6) * P, y - (k + 1) * P, 1, 1, C.mossDark, P);
  if (p < 1) return;
  const by = y - (h + 3) * P, pulse = 0.6 + 0.4 * Math.sin(t * 2);
  if (night) { const gr = g.createRadialGradient(x, by, 2, x, by, P * 22); gr.addColorStop(0, `rgba(255,210,110,${0.35 * pulse})`); gr.addColorStop(1, 'rgba(255,210,110,0)'); g.fillStyle = gr; g.fillRect(x - P * 22, by - P * 22, P * 44, P * 44); }
  px(g, x - 2 * P, by - P, 5, 4, '#ffc845', P); px(g, x - P, by, 3, 2, '#fff0b8', P);
  px(g, x - 3 * P, by + 3 * P, 2, 1, C.moss, P); px(g, x + 2 * P, by + 3 * P, 2, 1, C.moss, P);
}

/** A crystal cluster that catches the light. */
export function paintCrystal(g, { x, y, p, P, t, night }) {
  const shards = [[0, 12, 3], [-4, 8, 2], [4, 9, 2], [-7, 5, 2]];
  for (const [dx, hh, w] of shards) {
    const h = Math.round(hh * p);
    for (let k = 0; k < h; k++) px(g, x + dx * P, y - (k + 1) * P, w, 1, k > h - 3 ? '#e8d8ff' : (night ? '#9a7ae0' : '#b98cff'), P);
  }
  if (p >= 1 && Math.floor(t * 2) % 4 === 0) px(g, x + P, y - 10 * P, 1, 1, '#ffffff', P);
  if (p >= 1 && night) glow(g, x, y - 6 * P, P * 16, '185,140,255', 0.3);
}

/** A lantern hanging from a ledge (glowing at night). */
export function paintLantern(g, { x, y, P, t, night, i = 0 }) {
  const swing = Math.round(Math.sin(t * 1.5 + i) * 0.5) * P;
  px(g, x, y, 1, 3, C.woodDark, P);
  px(g, x - P + swing, y + 3 * P, 3, 3, night ? '#ffc845' : '#e8c070', P); px(g, x + swing, y + 4 * P, 1, 1, '#fff0b8', P);
  if (night) glow(g, x + P / 2 + swing, y + 4.5 * P, P * 9, '255,200,90', 0.4);
}

/** A small flag planted in the moss (one per Claude task finished today). */
export function paintFlag(g, { x, y, P, t, hue }) {
  const col = ['#e8574a', '#f5b82e', '#5fb8ff', '#b98cff', '#ff8fb1'][hue % 5];
  px(g, x, y - 7 * P, 1, 7, C.woodDark, P);
  const flap = Math.floor(t * 3 + hue) % 2;
  px(g, x + P, y - 7 * P, 3, 2, col, P); px(g, x + 4 * P, y - (7 - flap) * P, 1, 1, col, P);
}

/** Critters: ladybug, snail, bee, butterfly, firefly. `f`: animation frame. */
export function paintCritter(g, { kind, x, y, f, P, facing, night }) {
  const d = facing >= 0 ? 1 : -1;
  const at = (dx, dy, w, h, c) => px(g, x + (d > 0 ? dx : -dx - w + 1) * P, y - dy * P, w, h, c, P);
  switch (kind) {
    case 'ladybug': at(-1, 2, 3, 2, C.red); at(0, 2, 1, 1, '#1e1a16'); at(2, 1, 1, 1, '#1e1a16'); break;
    case 'snail': at(-2, 1, 4, 1, '#d8c8a0'); at(-1, 3, 3, 2, '#b07a40'); at(0, 3, 1, 1, '#f2c070'); at(2, 2, 1, 1, '#d8c8a0'); break;
    case 'bee': at(-1, 2, 3, 2, '#ffd23d'); at(0, 2, 1, 2, '#2a2620'); at(0, 3 + f, 2, 1, '#dff4ff'); break;
    case 'butterfly': at(0, 2, 1, 2, '#3a2a1c'); at(-2, 3 - f, 2, 2, '#ff8fb1'); at(1, 3 - f, 2, 2, '#ffb6d9'); break;
    case 'firefly': {
      const on = night && f === 1;
      at(0, 1, 1, 1, '#3a3a2a');
      if (night) glow(g, x, y - P, P * 6, '220,255,120', on ? 0.55 : 0.2);
      at(0, 0, 1, 1, on ? '#f2ff8a' : '#b8c46a');
      break;
    }
  }
}

/** A pixel icon (for the recent strip and the status lantern): 'thinking' cloud, 'waiting' lantern, 'done' flag. */
export function icon(state, size = 9) {
  const cv = document.createElement('canvas'); cv.width = size; cv.height = size;
  const g = cv.getContext('2d');
  const set = (x, y, w, h, c) => { g.fillStyle = c; g.fillRect(x, size - y - h, w, h); };
  if (state === 'thinking') { set(1, 3, 7, 4, '#f4f6fb'); set(2, 7, 5, 1, '#f4f6fb'); set(1, 1, 1, 1, '#f4f6fb'); set(2, 5, 1, 1, '#6a7390'); set(4, 5, 1, 1, '#6a7390'); set(6, 5, 1, 1, '#6a7390'); }
  else if (state === 'waiting') { set(3, 7, 3, 1, '#553620'); set(4, 8, 1, 1, '#3a2a1c'); set(2, 2, 5, 5, '#ffc845'); set(3, 3, 3, 3, '#fff0b8'); set(2, 1, 5, 1, '#553620'); }
  else { set(1, 0, 1, 9, '#6b4428'); set(2, 4, 5, 4, '#e8574a'); set(2, 6, 3, 1, '#f58a7a'); set(0, 0, 4, 1, '#5faf4a'); }
  return cv;
}
