// Procedural pixel art helpers: ports of the Mac app's `PixelCanvas`, `ArtRNG` (SpectacleArt.swift) and `SplitMix64`
// (Random.swift). Everything is drawn at "art pixel" resolution and shown with nearest-neighbour scaling, so it matches
// the Gremlets' chunky look. No DOM access except `toCanvas()`, so the art can be rasterised in a plain JS shell (tests).

const TWO53 = 2 ** 53;

/** Swift's `Int(x)`: truncation toward zero. */
export const int = Math.trunc;
/** Swift's `.rounded()`: to nearest, ties away from zero. */
export const rounded = (x) => Math.sign(x) * Math.round(Math.abs(x));
/** 64-bit wrapping arithmetic on BigInts. */
export const u64 = (x) => BigInt.asUintN(64, x);
export const hex = (c) => '#' + c.toString(16).padStart(6, '0');

/** A tiny pixel canvas. (0,0) is the bottom-left, like the screen; colours are 0xRRGGBB, empty is transparent. */
export class PixelCanvas {
  constructor(w, h) {
    this.w = Math.max(1, w | 0); this.h = Math.max(1, h | 0);
    this.px = new Int32Array(this.w * this.h).fill(-1);
  }
  set(x, y, c) {
    x = int(x); y = int(y);
    if (x >= 0 && x < this.w && y >= 0 && y < this.h) this.px[(this.h - 1 - y) * this.w + x] = c;
  }
  get(x, y) {
    x = int(x); y = int(y);
    if (x < 0 || x >= this.w || y < 0 || y >= this.h) return null;
    const c = this.px[(this.h - 1 - y) * this.w + x];
    return c < 0 ? null : c;
  }
  rect(x, y, rw, rh, c) { for (let yy = y; yy < y + rh; yy++) for (let xx = x; xx < x + rw; xx++) this.set(xx, yy, c); }
  /** Filled ellipse with a simple top-left light: `light` on the upper-left, `base` in the middle, `shade` below. */
  blob(cx, cy, rx, ry, base, light = null, shade = null) {
    const x0 = int(cx - rx - 1), x1 = int(cx + rx + 1), y0 = int(cy - ry - 1), y1 = int(cy + ry + 1);
    for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
      const dx = (x + 0.5 - cx) / rx, dy = (y + 0.5 - cy) / ry;
      if (!(dx * dx + dy * dy <= 1)) continue;
      let c = base;
      if (light != null && dx * -0.6 + dy * 0.8 > 0.45) c = light;
      if (shade != null && (dy < -0.45 || dx * 0.5 + dy * -0.85 > 0.62)) c = shade;
      this.set(x, y, c);
    }
  }
  line(x0, y0, x1, y1, c, width = 1) {
    const n = Math.max(1, int(Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0))));
    for (let i = 0; i <= n; i++) {
      const t = i / n;
      this.rect(int(x0 + (x1 - x0) * t) - int(width / 2), int(y0 + (y1 - y0) * t), width, 1, c);
    }
  }
  /** Darkens every pixel that touches transparency: a selective outline that keeps shapes readable at any size. */
  outline(factor = 0.55) {
    const out = this.px.slice();
    for (let y = 0; y < this.h; y++) for (let x = 0; x < this.w; x++) {
      const c = this.get(x, y);
      if (c == null) continue;
      if (this.get(x - 1, y) == null || this.get(x + 1, y) == null || this.get(x, y - 1) == null || this.get(x, y + 1) == null) {
        out[(this.h - 1 - y) * this.w + x] = PixelCanvas.darken(c, factor);
      }
    }
    this.px = out;
  }
  static darken(c, f) {
    const r = ((c >> 16) & 0xFF) * f, g = ((c >> 8) & 0xFF) * f, b = (c & 0xFF) * (f + (1 - f) * 0.25);
    return (int(r) << 16) | (int(g) << 8) | int(Math.min(255, b));
  }
  get filled() { let n = 0; for (const c of this.px) if (c >= 0) n++; return n; }
  /** Browser only: the pixels as a 1:1 canvas, to draw scaled up with `imageSmoothingEnabled = false`. */
  toCanvas() {
    const cv = document.createElement('canvas');
    cv.width = this.w; cv.height = this.h;
    const g = cv.getContext('2d'), img = g.createImageData(this.w, this.h), d = img.data;
    for (let i = 0; i < this.px.length; i++) {
      const c = this.px[i];
      if (c < 0) continue;
      d[i * 4] = (c >> 16) & 255; d[i * 4 + 1] = (c >> 8) & 255; d[i * 4 + 2] = c & 255; d[i * 4 + 3] = 255;
    }
    g.putImageData(img, 0, 0);
    return cv;
  }
}

/** Deterministic little RNG for art (same plant, same look every time): a 64-bit LCG, 53 bits out. */
export class ArtRNG {
  constructor(seed) { this.s = u64(BigInt(seed)); }
  next() { this.s = u64(this.s * 6364136223846793005n + 1442695040888963407n); return Number(this.s >> 11n) / TWO53; }
  range(a, b) { return a + (b - a) * this.next(); }
}

/** Small seedable RNG so behavior is reproducible (same sequence as the Swift `SplitMix64`). */
export class SplitMix64 {
  constructor(seed) { this.state = u64(BigInt(seed)); }
  /** The next 64 random bits, as a BigInt. */
  next() {
    this.state = u64(this.state + 0x9E3779B97F4A7C15n);
    let z = this.state;
    z = u64((z ^ (z >> 30n)) * 0xBF58476D1CE4E5B9n);
    z = u64((z ^ (z >> 27n)) * 0x94D049BB133111EBn);
    return z ^ (z >> 31n);
  }
  /** Swift's `Double.random(in: 0..<1, using:)`: `next(upperBound: 1 << 53)` (the top 53 bits) scaled to [0, 1). */
  unit() { return Number(this.next() >> 11n) * (2 ** -53); }
  /** Swift's `Double.random(in: lo...hi, using:)`. */
  range(lo, hi) { return (hi - lo) * this.unit() + lo; }
  chance(p) { return this.unit() < p; }
}

/** FNV-1a over the UTF-8 bytes of a string, as a 64-bit BigInt (the same hash the Mac app seeds bonsai from). */
export function fnv1a(s) {
  let h = 0xcbf29ce484222325n;
  for (const ch of s) {
    const cp = ch.codePointAt(0), bytes = [];
    if (cp < 0x80) bytes.push(cp);
    else if (cp < 0x800) bytes.push(0xC0 | (cp >> 6), 0x80 | (cp & 63));
    else if (cp < 0x10000) bytes.push(0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63));
    else bytes.push(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 63), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63));
    for (const b of bytes) { h ^= BigInt(b); h = u64(h * 0x100000001b3n); }
  }
  return h;
}
