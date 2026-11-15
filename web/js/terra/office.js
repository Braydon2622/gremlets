// The Back Office on the iPad: the same pixel building as on the Mac (a port of OfficeArt.swift), big, live from the
// Mac's office notes. Rooms act out the news (a train car per sale, a pigeon per letter, a car round the rooftop
// track per trade, crates, fish), fireworks on a milestone, a storm cloud on a red day. Read-only. The Mac sends
// each event's room only (never where it came from). With no Mac linked, "See a demo" plays a made-up day.

const W = 138, H = 78;

class Canvas {
  constructor(w, h) { this.w = w; this.h = h; this.px = new Array(w * h).fill(null); }
  set(x, y, c) { x |= 0; y |= 0; if (x < 0 || x >= this.w || y < 0 || y >= this.h) return; this.px[(this.h - 1 - y) * this.w + x] = c; }
  get(x, y) { if (x < 0 || x >= this.w || y < 0 || y >= this.h) return null; return this.px[(this.h - 1 - y) * this.w + x]; }
  rect(x, y, w, h, c) { for (let yy = y; yy < y + h; yy++) for (let xx = x; xx < x + w; xx++) this.set(xx, yy, c); }
  blob(cx, cy, rx, ry, base, light, shade) {
    for (let y = Math.floor(cy - ry - 1); y <= cy + ry + 1; y++) for (let x = Math.floor(cx - rx - 1); x <= cx + rx + 1; x++) {
      const dx = (x - cx) / rx, dy = (y - cy) / ry;
      if (dx * dx + dy * dy > 1) continue;
      this.set(x, y, dy > 0.35 && dx < 0.2 ? light : dy < -0.45 ? shade : base);
    }
  }
  outline(f) {
    const out = this.px.slice();
    for (let y = 0; y < this.h; y++) for (let x = 0; x < this.w; x++) {
      const c = this.get(x, y);
      if (c == null) continue;
      if (this.get(x - 1, y) == null || this.get(x + 1, y) == null || this.get(x, y - 1) == null || this.get(x, y + 1) == null) {
        const r = ((c >> 16) & 255) * f, g = ((c >> 8) & 255) * f, b = Math.min(255, (c & 255) * (f + (1 - f) * 0.25));
        out[(this.h - 1 - y) * this.w + x] = (r << 16) | (g << 8) | b;
      }
    }
    this.px = out;
  }
  image() {
    const d = new ImageData(this.w, this.h);
    this.px.forEach((c, i) => { if (c == null) return; d.data[i * 4] = (c >> 16) & 255; d.data[i * 4 + 1] = (c >> 8) & 255; d.data[i * 4 + 2] = c & 255; d.data[i * 4 + 3] = 255; });
    return d;
  }
}

function boarded(cv, x, y, w, h) {
  cv.rect(x, y, w, h, 0x4A3A2C);
  for (let k = 0; k < h; k += 4) cv.rect(x, y + k, w, 2, 0x8A6A48);
  for (let i = 0; i < w; i++) if ((i + y) % 9 === 0) cv.rect(x + i, y, 1, h, 0x6B4A34);
}

// A room that's open but has nothing to show yet: drawn curtains (OfficeArt.curtained).
function curtained(cv, x, y, w, h, night) {
  cv.rect(x, y, w, h, night ? 0xE8C77A : 0x5A6A88);
  const cw = Math.max(3, Math.floor(w / 3));
  for (let k = 0; k < cw; k++) { const c = k % 2 === 0 ? 0xC98A9A : 0xB87888; cv.rect(x + k, y, 1, h, c); cv.rect(x + w - 1 - k, y, 1, h, c); }
  cv.rect(x, y + h - 2, w, 2, 0x8A5A35);
  cv.set(x + cw - 1, y + (h >> 1), 0xF6EFDF); cv.set(x + w - cw, y + (h >> 1), 0xF6EFDF);
}

/** The building at one moment. `s`: the scene (rooms Set, t, night, and each room's state). */
export function building(s) {
  const cv = new Canvas(W, H);
  const wood = 0xB8875A, woodDark = 0x8A5A35, woodLine = 0xA5764C;
  cv.rect(0, 0, 120, 2, 0x8A7A68);
  cv.rect(0, 2, 72, 28, 0x6B4A34);
  cv.rect(72, 2, 48, 28, 0x9E5A44);
  for (let y = 4; y < 30; y += 3) for (let x = 72 + (y % 2) * 3; x < 120; x += 6) cv.set(x, y, 0x844634);
  cv.rect(0, 30, 120, 2, woodDark);
  cv.rect(0, 32, 120, 28, wood);
  for (let y = 35; y < 60; y += 4) cv.rect(0, y, 120, 1, woodLine);
  cv.rect(39, 32, 1, 28, woodDark); cv.rect(79, 32, 1, 28, woodDark); cv.rect(71, 2, 1, 28, 0x553620);
  for (let i = 0, y = 60; y <= 67; i++, y++) cv.rect(i, y, 120 - 2 * i, 1, i === 0 ? 0x4C8A3A : (i % 2 === 0 ? 0x6CC04A : 0x7FCB5A));
  for (let x = 2; x < 118; x += 7) { cv.set(x, 59, 0x5E9E46); cv.set(x + 1, 58, 0x4C8A3A); }
  cv.rect(66, 22, 6, 1, 0x553620);
  // Polish (OfficeArt.dressRoof): shingles, a sunlit ridge with moss tufts, window sills, a shadow under the beam.
  for (let i = 0, y = 60; y <= 66; i++, y++) for (let x = i + 2 + (y % 2) * 2; x < 118 - i; x += 4) cv.set(x, y, y % 2 === 0 ? 0x5EAE42 : 0x6FBF50);
  cv.rect(7, 67, 106, 1, 0x9BDB6E);
  for (let x = 8; x < 112; x += 5) { cv.set(x, 68, 0x7FCB5A); if (x % 3 === 0) cv.set(x + 1, 69, 0x6CC04A); }
  cv.rect(3, 34, 33, 1, 0xD9B07A); cv.rect(42, 33, 36, 1, 0xD9B07A);
  cv.rect(0, 31, 120, 1, 0x6E4426);
  const has = (r) => s.rooms.has(r);

  if (has('railroad')) {
    cv.rect(0, 3, 71, 1, 0x5E5A52); cv.rect(0, 5, 71, 1, 0x5E5A52);
    for (let x = 1; x < 71; x += 3) cv.rect(x, 2, 1, 5, 0x6B4428);
    cv.rect(20, 7, 38, 3, 0xA89C8A); cv.rect(20, 9, 38, 1, 0xC8BCA8);
    for (let i = 0; i < Math.min(12, s.cargo); i++) {
      const x = 23 + (i % 4) * 8, y = 10 + Math.floor(i / 4) * 4;
      cv.rect(x, y, 6, 3, [0xC9A15A, 0xB8924E, 0xD9B46A][i % 3]); cv.set(x + 2, y + 1, 0x8A6A3A);
    }
    cv.rect(26, 22, 22, 4, 0xF2E6D0); cv.rect(26, 22, 22, 1, 0xC9A15A);
    for (let x = 28; x < 46; x += 3) cv.set(x, 24, 0x8A6A3A);
    cv.rect(64, 6, 1, 14, 0x3A3A3A); cv.rect(63, 17, 3, 4, 0x2A2A2A);
    cv.set(64, 19, s.signal ? 0xFF4A3A : 0x4A2A2A); cv.set(64, 18, s.signal ? 0x2A4A2A : 0x5FE06A);
    if (s.car) {
      const x = Math.round(s.car.x), ret = s.car.returning;
      cv.rect(x, 7, 10, 5, ret ? 0x8A7A68 : 0x3F8CC9); cv.rect(x, 11, 10, 1, ret ? 0x6A5A48 : 0x6FB8F0);
      for (const k of [1, 2, 7, 8]) cv.set(x + k, 6, 0x2A2A2A);
      if (!ret) { cv.rect(x + 3, 12, 4, 3, 0xF5B82E); cv.set(x + 4, 13, 0xFFE45C); }
    }
  } else if (s.dormant?.has('railroad')) curtained(cv, 4, 8, 64, 18, s.night); else boarded(cv, 4, 8, 64, 18);

  if (has('factory')) {
    cv.rect(76, 8, 40, 2, 0x3A3A3A);
    for (let x = 77; x < 116; x += 4) cv.set(x, 7, 0x6A6A6A);
    cv.rect(76, 4, 1, 4, 0x553620); cv.rect(115, 4, 1, 4, 0x553620);
    for (const c of s.crates) {
      const x = Math.round(c.x);
      cv.rect(x, 10, 5, 4, 0xC9A15A); cv.rect(x, 13, 5, 1, 0xA88445); cv.set(x + 2, 11, 0x8A6A3A);
      if (x >= 104) cv.rect(x + 1, 11, 3, 2, c.ok ? 0x5FAF4A : 0x5A5A5A);
    }
    cv.rect(104, 18, 6, 3, 0x6B4428); cv.rect(106, 14, 2, 4, 0x8A5A35);
    cv.rect(74, 16, 2, 3, 0x8A7A58);
    cv.rect(108, 60, 5, 12, 0xB0603A); cv.rect(107, 71, 7, 1, 0x8A4A2E);
  } else if (s.dormant?.has('factory')) curtained(cv, 78, 8, 36, 16, s.night); else boarded(cv, 78, 8, 36, 16);

  if (has('workshop')) {
    const glass = s.night ? 0xFFD36B : (s.workers > 0 ? 0xF2E3B0 : 0x5A6A88);
    cv.rect(3, 35, 33, 21, 0x6B4428); cv.rect(4, 36, 31, 19, glass);
    [7, 17, 27].forEach((x, i) => {
      if (i < s.workers) {
        const bob = (Math.floor(s.t * 2.5) + i) % 2;
        cv.rect(x, 41 + bob, 4, 4, 0x8BD66A); cv.set(x + 1, 45 + bob, 0x5E9E46);
        cv.set(x, 43 + bob, 0x2A1A10); cv.set(x + 3, 43 + bob, 0x2A1A10);
      }
      cv.rect(x - 2, 38, 8, 3, 0x8A5A35); cv.set(x + 5, 41, 0xF6EFDF);
    });
    cv.rect(36, 44, 2, 1, 0x3A2A1C); cv.rect(36, 40, 3, 4, s.lantern ? 0xFFC845 : 0x8A7A58); cv.set(37, 42, s.lantern ? 0xFFF0B8 : 0x9A8A68);
    cv.rect(8, 68, 1, 9, 0x6B4428);
    if (s.flag) { cv.rect(9, 72, 6, 4, 0x5FAF4A); cv.set(9, 75, 0x9BDB6E); cv.set(14, 72, 0x4C8A3A); }
  } else if (s.dormant?.has('workshop')) curtained(cv, 4, 36, 31, 19, s.night); else boarded(cv, 4, 36, 31, 19);

  if (has('aquarium')) {
    const murky = s.fish.some((f) => f.e);
    cv.rect(42, 34, 36, 24, 0x6B4428);
    cv.rect(43, 35, 34, 22, murky ? 0x5A7A5A : (s.night ? 0x2F5C80 : 0x5BA7D9));
    cv.rect(43, 54, 34, 3, murky ? 0x6A8A6A : (s.night ? 0x4A7AA0 : 0x8FCBEF));
    cv.rect(43, 35, 34, 2, 0xD8C8A0);
    for (const [x, h] of [[46, 6], [49, 4], [70, 7], [73, 5]]) for (let k = 0; k < h; k++) cv.set(x + (k % 2), 37 + k, 0x4C8A3A);
    for (let i = 0; i < 3; i++) cv.set(52 + i * 7, 37 + Math.floor((s.t * 6 + i * 7) % 17), 0xDFF4FF);
    s.fish.slice(0, 6).forEach((f, i) => {
      const len = 4 + Math.round(Math.min(3, f.s) * 1.5), span = 30 - len;
      const phase = s.t * (f.z ? 0.05 : 0.25 + 0.05 * i) + i * 1.7;
      const x = 44 + Math.round(((Math.sin(phase) + 1) / 2) * span);
      const y = f.z ? 37 : 39 + (i * 3) % 14 + Math.round(Math.sin(s.t * 1.3 + i));
      const dir = Math.cos(phase) >= 0 ? 1 : -1;
      const col = f.z ? 0x9A9A9A : f.p >= 0 ? 0x5FD06A : 0xF06A5A, shade = f.z ? 0x7A7A7A : f.p >= 0 ? 0x3FA04A : 0xC04A3A;
      for (let k = 0; k < len; k++) { cv.set(x + k, y, col); if (len > 4 && k > 0 && k < len - 1) cv.set(x + k, y + 1, shade); }
      const tail = dir > 0 ? x - 1 : x + len;
      cv.set(tail, y + 1, shade); cv.set(tail, y - 1, shade);
      cv.set(dir > 0 ? x + len - 1 : x, y, 0x1E1A16);
    });
  } else if (s.dormant?.has('aquarium')) curtained(cv, 43, 35, 34, 22, s.night); else boarded(cv, 43, 35, 34, 22);

  if (has('postOffice')) {
    cv.rect(80, 32, 40, 28, 0xE8DCC2);
    for (let y = 35; y < 60; y += 4) cv.rect(80, y, 40, 1, 0xD8CCB0);
    for (let r = 0; r < 3; r++) for (let c = 0; c < 5; c++) {
      const x = 83 + c * 4, y = 41 + r * 4, i = r * 5 + c;
      cv.rect(x, y, 4, 4, 0x8A5A35); cv.rect(x + 1, y + 1, 2, 2, 0x5A3A20);
      if (i < s.letters) cv.rect(x + 1, y + 1, 2, 2, i < s.unread ? 0xFFFFFF : 0xD8CCB0);
    }
    cv.rect(106, 35, 8, 9, 0x3F6CC9); cv.rect(106, 43, 8, 1, 0x2F5099); cv.rect(108, 40, 4, 1, 0x1E2A50);
    if (s.unread > 0) { cv.rect(114, 40, 1, 6, 0x553620); cv.rect(115, 44, 3, 2, 0xE0453A); } else cv.rect(114, 39, 4, 1, 0xE0453A);
    cv.rect(90, 68, 12, 6, 0xC9A15A); cv.rect(89, 74, 14, 1, 0x8A5A35); cv.rect(94, 69, 4, 3, 0x3A2614);
    const [px, py] = s.pigeon != null ? [Math.floor(118 - s.pigeon * 22), Math.floor(76 - s.pigeon * 4)] : [98, 75];
    const wing = s.pigeon != null && Math.floor(s.t * 10) % 2 === 0;
    cv.rect(px, py - 2, 3, 2, 0x9AA0AA); cv.set(px - 1, py - 1, 0x9AA0AA); cv.set(px - 1, py, 0x6A6E78);
    cv.set(px + 1, py - (wing ? 0 : 3), 0x7A808A); cv.set(px - 2, py - 1, 0xF2B640);
    if (s.pigeon != null) cv.rect(px + 1, py - 4, 2, 1, 0xFFFFFF);
  } else if (s.dormant?.has('postOffice')) curtained(cv, 82, 36, 34, 20, s.night); else boarded(cv, 82, 36, 34, 20);

  if (has('board')) {
    cv.rect(123, 0, 1, 40, 0x6B4428); cv.rect(135, 0, 1, 40, 0x6B4428);
    cv.rect(121, 16, 17, 22, 0x6B4428); cv.rect(122, 17, 15, 20, 0xC8965A);
    for (let x = 123; x < 137; x += 3) for (let y = 18; y < 37; y += 4) cv.set(x, y, 0xB0804A);
    s.notes.slice(-15).forEach((r, i) => {
      const x = 123 + (i % 3) * 5, y = 33 - Math.floor(i / 3) * 4;
      cv.rect(x, y, 4, 3, r ? 0xFFE45C : 0xBFE6FA); cv.set(x + 1, y + 2, r ? 0xE0453A : 0x3F8CC9);
      cv.set(x + 1, y, r ? 0xD8B83A : 0x8FB8D8); cv.set(x + 2, y + 1, r ? 0xD8B83A : 0x8FB8D8);
    });
    for (let i = 0, y = 38; y <= 40; i++, y++) cv.rect(120 + i, y, 18 - 2 * i, 1, i % 2 === 0 ? 0x6CC04A : 0x4C8A3A);
    if (s.rain) {
      const bob = Math.floor(s.t * 1.5) % 2;
      cv.rect(127, 41, 5, 4, 0x8BD66A); cv.set(128, 43, 0x2A1A10); cv.set(130, 43, 0x2A1A10); cv.rect(127, 41, 5, 1, 0x5E9E46);
      cv.rect(129, 45, 1, 5 + bob, 0x6B4428);
      [11, 9, 5].forEach((w, i) => cv.rect(129 - (w >> 1), 50 + bob + i, w, 1, i === 0 ? 0x3F9A4A : 0x5FBF5A));
    }
  }

  // Growth: flower boxes, string lights, ivy, a gold sign, a clock tower (OfficeArt.swift).
  const lv = s.level | 0;
  if (lv >= 1) for (const [x0, x1] of [[4, 35], [43, 77]]) {
    cv.rect(x0, 33, x1 - x0, 2, 0x8A5A35);
    for (let x = x0 + 1; x < x1; x += 3) { cv.set(x, 35, [0xF27BA8, 0xFFD24A, 0xF6EFDF, 0xB07BF2][Math.floor(x / 3) % 4]); cv.set(x + 1, 35, 0x5E9E46); }
  }
  if (lv >= 2) for (let x = 3; x < 117; x += 4) {
    const on = s.night || (Math.floor(s.t * 2) + Math.floor(x / 4)) % 3 !== 0;
    cv.set(x, 58, on ? [0xFFE45C, 0xF27BA8, 0x7FD4FF, 0x9BEA7A][Math.floor(x / 4) % 4] : 0x6A5A48); cv.set(x + 2, 59, 0x3A2A1C);
  }
  if (lv >= 3) for (let y = 3; y < 58; y++) if ((y * 7) % 5 < 3) {
    cv.set(0, y, y % 3 === 0 ? 0x4C8A3A : 0x5FAF4A); if (y % 4 === 0) cv.set(1, y, 0x6CC04A);
    if (y < 30 && y % 3 !== 1) { cv.set(119, y, 0x4C8A3A); if (y % 5 === 0) cv.set(118, y, 0x6CC04A); }
  }
  if (lv >= 4) { cv.rect(24, 27, 26, 3, 0xD9A82E); cv.rect(25, 28, 24, 1, 0xF5D36A); for (let x = 27; x < 48; x += 4) cv.set(x, 28, 0x8A6A1A); }
  if (lv >= 5 && has('postOffice')) {
    cv.rect(91, 74, 10, 4, 0xC9A15A); cv.rect(90, 77, 12, 1, 0x8A5A35); cv.rect(94, 74, 4, 3, 0xF6EFDF);
    const h = Math.floor(s.t / 3) % 4; cv.set(95 + (h === 1 ? 1 : 0), 75 + (h === 0 ? 1 : 0), 0x1E1A16); cv.set(95, 75, 0x1E1A16);
  }

  if (has('farm')) {   // Rooftop Farm: two planter boxes, the farmer walks the rows during a trade, a sunflower on a green day
    const soil = 0x5A3A22, plank = 0x9A6A3C, plankDark = 0x6B4428;
    for (const [x0, x1] of [[18, 48], [54, 84]]) {
      cv.rect(x0, 68, x1 - x0, 3, plank); cv.rect(x0, 68, x1 - x0, 1, plankDark);
      cv.rect(x0, 70, x1 - x0, 1, 0xB8875A); cv.rect(x0 + 1, 71, x1 - x0 - 2, 1, soil);
      for (let x = x0 + 2; x < x1 - 1; x += 4) cv.set(x, 68, plankDark);
      let i = 0;
      for (let x = x0 + 2; x < x1 - 2; x += 3, i++) {
        const k = (i + x0) % 3;
        if (k === 0) { cv.set(x, 72, 0x4C8A3A); cv.set(x + 1, 72, 0x6CC04A); cv.set(x, 73, 0x7FCB5A); }
        else if (k === 1) { cv.set(x, 72, 0x5E9E46); cv.set(x, 73, 0x7FCB5A); cv.set(x + 1, 74, 0x5E9E46); cv.set(x, 71, 0xF08A2A); }
        else { cv.set(x, 72, 0x4C8A3A); cv.set(x, 73, 0x5E9E46); cv.set(x + 1, 73, 0xE0453A); }
      }
    }
    cv.rect(87, 68, 1, 8, 0x4C8A3A); cv.set(86, 71, 0x6CC04A); cv.set(85, 72, 0x6CC04A); cv.set(88, 73, 0x6CC04A);
    if (s.farmGreen) {
      for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) if (Math.abs(dx) + Math.abs(dy) <= 3 && !(Math.abs(dx) === 2 && Math.abs(dy) === 2)) cv.set(87 + dx, 78 + dy, (dx + dy) % 2 === 0 ? 0xFFD24A : 0xF2B640);
      cv.rect(86, 77, 2, 2, 0x7A4A1A);
    } else { cv.rect(86, 76, 2, 2, 0x6CC04A); cv.set(87, 78, 0x5E9E46); }
    if (!s.farmOk) { cv.set(22, 72, 0xA88A3A); cv.set(23, 73, 0xA88A3A); cv.rect(25, 72, 1, 3, plankDark); cv.rect(23, 75, 5, 3, 0xF6EFDF); cv.set(25, 76, 0xE0453A); }
    if (s.racer) {
      const x = 19 + Math.floor((s.racer.u % 1) * 64), bob = Math.floor(s.t * 4) % 2;
      cv.rect(x, 71 + bob, 3, 3, 0x8BD66A); cv.rect(x, 74 + bob, 3, 1, 0x5E9E46);
      cv.set(x, 72 + bob, 0x2A1A10); cv.set(x + 2, 72 + bob, 0x2A1A10);
      cv.set(x + 3, 73 + bob, s.racer.green ? 0x5FD06A : 0xE0453A); cv.set(x + 3, 74 + bob, 0x4C8A3A);
    }
  }
  // The moss meets the building (OfficeArt.dressMoss).
  if (has('workshop')) { cv.set(5, 54, 0xFFFFFF); cv.set(6, 53, 0xFFFFFF); }
  if (has('aquarium')) { cv.set(44, 55, 0xFFFFFF); cv.set(45, 54, 0xFFFFFF); }
  const greens = [0x4C8A3A, 0x5E9E46, 0x6CC04A, 0x7FCB5A];
  for (let x = 0; x < 120; x++) {
    const h = 1 + (x * 7 + Math.floor(x / 3)) % 3;
    for (let y = 0; y < h; y++) cv.set(x, y, greens[(x + y) % 4]);
    if ((x * 13) % 11 === 0) cv.set(x, h, 0x9BDB6E);
    if ((x * 17) % 23 === 0) cv.set(x, h, [0xF6EFDF, 0xFFD24A, 0xF27BA8][x % 3]);
  }
  for (const [x, top] of [[0, 9], [1, 6], [2, 4], [119, 8], [118, 5], [117, 3]]) for (let y = 2; y < top; y++) cv.set(x, y, greens[(x + y) % 4]);
  if (has('board')) for (const x of [122, 123, 124, 134, 135, 136]) for (let y = 0; y < 2 + x % 3; y++) cv.set(x, y, greens[(x + y) % 4]);
  for (const [x, len] of [[4, 4], [13, 2], [27, 5], [46, 3], [61, 4], [83, 2], [97, 5], [112, 3]]) for (let k = 0; k < len; k++) cv.set(x + (k % 2), 58 - k, k === len - 1 ? 0x7FCB5A : 0x4C8A3A);
  cv.outline(0.72);
  return cv.image();
}

export function cloud(t) {
  const cv = new Canvas(64, 18), drift = Math.sin(t * 0.4) * 1.5;
  for (const [cx, cy, r] of [[12, 7, 6.5], [24, 10, 8.5], [38, 10, 9], [51, 7, 7]]) cv.blob(cx + drift, cy, r, r * 0.75, 0x8C93A3, 0xAEB4C2, 0x6A7182);
  cv.rect(6, 1, 52, 4, 0x6A7182);
  cv.outline(0.7);
  return cv.image();
}

const money = (v) => (v < 0 ? '-' : '') + '$' + Math.abs(v).toFixed(2);
const ICON = { workshop: '🛠', railroad: '🚂', aquarium: '🐟', postOffice: '🕊', factory: '📦', board: '📌', farm: '🌻' };

/** The Back Office view: a full-screen layer over the Terrarium, toggled with the 🏢 button. */
export class OfficeView {
  constructor() {
    this.state = null; this.events = []; this.seen = new Set();
    this.car = null; this.pigeon = null; this.lap = null; this.crates = []; this.fw = []; this.drops = [];
    const root = document.createElement('div'); root.id = 'toffice'; root.hidden = true;
    root.innerHTML = `<canvas></canvas><aside><h2>Back Office</h2><div class="nums"></div><h3>Reminders</h3><ul class="rem"></ul><h3>Latest</h3><ul class="feed"></ul><button class="rot"></button></aside><p class="wait">Waiting for your Mac… (link it from the Gremlets menu) <button class="demo">▶ See a demo</button></p>`;
    document.body.append(root);
    this.root = root; this.cv = root.querySelector('canvas'); this.g = this.cv.getContext('2d');
    this.off = document.createElement('canvas'); this.off.width = W; this.off.height = H;
    this.offCloud = document.createElement('canvas'); this.offCloud.width = 64; this.offCloud.height = 18;
    const btn = document.createElement('button'); btn.id = 'tofficebtn'; btn.textContent = '🏢'; btn.title = 'Back Office';
    btn.addEventListener('click', (e) => { e.stopPropagation(); this.toggle(); });
    document.body.append(btn); this.btn = btn;
    root.addEventListener('click', () => this.toggle(false));
    try { this.rotate = localStorage.getItem('terra.officeRotate') === '1'; } catch { this.rotate = false; }
    const rot = root.querySelector('.rot');
    const label = () => { rot.textContent = this.rotate ? '↻ Wall mode on: switches every 2 min' : '↻ Wall mode: switch views every 2 min'; };
    label();
    rot.addEventListener('click', (e) => { e.stopPropagation(); this.rotate = !this.rotate; this.flipAt = performance.now() / 1000 + 120; label(); try { localStorage.setItem('terra.officeRotate', this.rotate ? '1' : '0'); } catch {} });
    root.querySelector('aside').addEventListener('click', (e) => e.stopPropagation());
    root.querySelector('.demo').addEventListener('click', (e) => { e.stopPropagation(); this.startDemo(); });
    if (new URLSearchParams(location.search).has('officeDemo')) setTimeout(() => { this.toggle(true); this.startDemo(); }, 300);
    this.flipAt = performance.now() / 1000 + 120;
  }
  get open() { return !this.root.hidden; }
  toggle(on = !this.open) { this.root.hidden = !on; this.btn.textContent = on ? '🌿' : '🏢'; if (on) this.renderSide(); }

  /** An office note from the Mac. Returns the new events (for the Terrarium's own sparkle). */
  update(n, fromMac = false) {
    if (fromMac && this.demoTimer) { clearInterval(this.demoTimer); this.demoTimer = null; this.demoing = false; this.events = []; this.seen.clear(); this.root.classList.remove('demo-on'); }
    if (n.state) { this.state = n.state; this.root.classList.add('live'); }
    const fresh = [];
    for (const e of n.events || []) {
      const k = e.at + '|' + e.title;
      if (this.seen.has(k)) continue;
      this.seen.add(k);
      if (this.events.length) fresh.push(e);   // the first note is history, not news
      this.events.push(e);
    }
    this.events = this.events.slice(-12);
    const t = performance.now() / 1000;
    for (const e of fresh) {
      const room = e.room;
      if (room === 'railroad' && (e.kind === 'sale' || e.kind === 'return')) this.car = { returning: e.kind === 'return', t0: t };
      if (room === 'postOffice') this.pigeon = t;
      if (room === 'farm' && (e.kind === 'trade' || e.kind === 'test')) this.lap = { green: (e.amount ?? 0) >= 0, t0: t };
      if (room === 'factory') this.crates.push({ ok: e.severity !== 'urgent' && e.severity !== 'warn', t0: t });
      if (e.severity === 'good') this.firework(2);
    }
    const r = this.state?.report;
    if (r && fresh.length && ((r.salesTotal >= 25 && !this._store) || (r.farmTrades > 0 && r.farmPnl > 0 && !this._farm))) { this.firework(6); }
    if (r) { this._store = r.salesTotal >= 25; this._farm = r.farmTrades > 0 && r.farmPnl > 0; }
    if (this.open) this.renderSide();
    return fresh;
  }

  /** No Mac linked: a made-up day in the office, so anyone can see what it does (nothing here is real). */
  startDemo() {
    if (this.demoTimer || this.root.classList.contains('live') && !this.demoing) return;
    this.demoing = true;
    const now = () => Date.now() / 1000;
    const report = { sales: 2, salesTotal: 21.49, pnl: 6.2, bots: 3, messages: 4, claudeDone: 5, farmTrades: 1, farmPnl: 96, runs: 3, reminders: 2, updates: 1 };
    const base = { rooms: ['workshop', 'railroad', 'aquarium', 'postOffice', 'factory', 'board', 'farm'], workers: 2, lantern: false, flag: true, cargo: 2, signal: false,
      fish: [{ n: 'Trend', p: 4.2, s: 1.4, z: false, e: false }, { n: 'Grid', p: -1.1, s: 0.8, z: false, e: false }, { n: 'Swing', p: 3.1, s: 1.1, z: false, e: false }],
      letters: 4, unread: 1, notes: [true, false, true, false], reminders: ['Review the pull request', 'Reply to the client'], farmGreen: true, farmOk: true, rain: false, level: 3, report };
    const script = [
      { room: 'workshop', kind: 'done', title: 'Website: Claude is done', severity: 'good' },
      { room: 'postOffice', kind: 'mention', title: 'Text from Sam', severity: 'good' },
      { room: 'railroad', kind: 'sale', title: 'Pixel mug', severity: 'good', amount: 14.99 },
      { room: 'farm', kind: 'trade', title: 'Trade · long 1', severity: 'good', amount: 96 },
      { room: 'factory', kind: 'run', title: 'Nightly build', severity: 'good' },
      { room: 'aquarium', kind: 'position', title: 'Trend bot', severity: 'info', amount: 4.2 },
      { room: 'board', kind: 'reminder', title: 'Reply to the client', severity: 'warn' },
      { room: 'postOffice', kind: 'mention', title: 'Missed call from Mom', severity: 'good' },
      { room: 'workshop', kind: 'waiting', title: 'App: Claude needs you', severity: 'warn' },
    ];
    let i = 0;
    const events = [];
    const step = () => {
      const e = { ...script[i % script.length], at: now() + i * 0.001 };
      events.push(e); i++;
      const st = { ...base, rain: i % 18 >= 12, lantern: e.room === 'workshop' && e.kind === 'waiting', unread: 1 + (i % 3) };
      this.update({ type: 'office', state: st, events: events.slice(-6) });
    };
    this.update({ type: 'office', state: base, events: [] });   // history first, then news
    step();
    this.demoTimer = setInterval(step, 4000);
    this.root.classList.add('demo-on');
  }

  firework(n) {
    const t = performance.now() / 1000;
    for (let i = 0; i < n; i++) this.fw.push({ x: 0.15 + Math.random() * 0.7, y: 0.08 + Math.random() * 0.22, t0: t + i * 0.45, hue: Math.floor(Math.random() * 360) });
  }

  renderSide() {
    const s = this.state; if (!s) return;
    const r = s.report || {}, rooms = new Set(s.rooms || []);
    const rows = [];
    if (rooms.has('workshop')) rows.push(['🛠', 'Workshop', `${s.workers} at their desks · ${r.claudeDone} task${r.claudeDone === 1 ? '' : 's'} done`]);
    if (rooms.has('railroad')) rows.push(['🚂', 'Railroad', `${r.sales} sale${r.sales === 1 ? '' : 's'} · ${money(r.salesTotal)}`]);
    if (rooms.has('aquarium')) rows.push(['🐟', 'Aquarium', `${r.bots} bot${r.bots === 1 ? '' : 's'} · ${money(r.pnl)}`]);
    if (rooms.has('farm')) rows.push(['🌻', 'Rooftop Farm', r.farmTrades ? `${r.farmTrades} trade${r.farmTrades === 1 ? '' : 's'} · ${money(r.farmPnl)}` : 'no trades today']);
    if (rooms.has('postOffice')) rows.push(['🕊', 'Post Office', `${s.letters} letter${s.letters === 1 ? '' : 's'}${s.unread ? ` · ${s.unread} new` : ''}`]);
    if (rooms.has('factory')) rows.push(['📦', 'Factory', `${r.runs} run${r.runs === 1 ? '' : 's'}`]);
    const nums = this.root.querySelector('.nums'); nums.replaceChildren();
    for (const [i, a, b] of rows) { const d = document.createElement('div'); const ic = document.createElement('span'); ic.textContent = i; const t = document.createElement('b'); t.textContent = a; const v = document.createElement('small'); v.textContent = b; d.append(ic, t, v); nums.append(d); }
    const rem = this.root.querySelector('.rem'); rem.replaceChildren();
    for (const x of s.reminders || []) rem.append(Object.assign(document.createElement('li'), { textContent: '📌 ' + x }));
    if (!(s.reminders || []).length) rem.append(Object.assign(document.createElement('li'), { textContent: 'Nothing waiting on you.' }));
    const feed = this.root.querySelector('.feed'); feed.replaceChildren();
    for (const e of this.events.slice(-6).reverse()) {
      const li = document.createElement('li'); li.className = e.severity;
      const tm = new Date(e.at * 1000).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
      li.textContent = `${ICON[e.room] ?? '🏢'} ${tm}  ${e.title}` + (e.amount != null ? `  ${money(e.amount)}` : '');
      feed.append(li);
    }
  }

  /** Each frame (cheap when closed). `night` from the Terrarium. Returns true while it's showing. */
  frame(night) {
    const now = performance.now() / 1000;
    if (this.rotate && now > this.flipAt) { this.flipAt = now + 120; this.toggle(); }
    if (!this.open || !this.state) return this.open;
    const s = this.state;
    const scene = { rooms: new Set(s.rooms || []), t: now, night, workers: s.workers | 0, lantern: !!s.lantern, flag: !!s.flag,
      cargo: s.cargo | 0, signal: !!s.signal, fish: s.fish || [], letters: s.letters | 0, unread: s.unread | 0, notes: s.notes || [],
      farmGreen: !!s.farmGreen, farmOk: s.farmOk !== false, rain: !!s.rain, level: s.level | 0, dormant: new Set(s.dormant || []), crates: [], car: null, pigeon: null, racer: null };
    if (this.car) { const u = Math.min(1, (now - this.car.t0) / 3); scene.car = this.car.returning ? { x: 40 - 52 * u, returning: true } : { x: -12 + 52 * u, returning: false }; if (now - this.car.t0 > 5) this.car = null; }
    if (this.pigeon != null) { const u = (now - this.pigeon) / 2.5; if (u >= 1) this.pigeon = null; else scene.pigeon = u; }
    if (this.lap) { const u = (now - this.lap.t0) / 3; if (u >= 2) this.lap = null; else scene.racer = { u: u % 1, green: this.lap.green }; }
    this.crates = this.crates.filter((c) => now - c.t0 < 7);
    scene.crates = this.crates.map((c) => ({ x: 76 + 32 * Math.min(1, (now - c.t0) / 5), ok: c.ok }));

    const dpr = window.devicePixelRatio || 1, cw = this.cv.clientWidth, ch = this.cv.clientHeight;
    if (this.cv.width !== Math.round(cw * dpr) || this.cv.height !== Math.round(ch * dpr)) { this.cv.width = Math.round(cw * dpr); this.cv.height = Math.round(ch * dpr); }
    const g = this.g; g.setTransform(dpr, 0, 0, dpr, 0, 0); g.imageSmoothingEnabled = false;
    const sky = g.createLinearGradient(0, 0, 0, ch);
    if (night) { sky.addColorStop(0, '#1d2340'); sky.addColorStop(1, '#3a3f66'); } else if (scene.rain) { sky.addColorStop(0, '#9aa3b2'); sky.addColorStop(1, '#cfd6de'); } else { sky.addColorStop(0, '#dcecf8'); sky.addColorStop(1, '#fbeedc'); }
    g.fillStyle = sky; g.fillRect(0, 0, cw, ch);
    // Beside the panel on a wide screen, under it on a narrow one; room above for the cloud and fireworks.
    const side = cw >= 700 ? Math.min(360, cw * 0.4) + 24 : 0;
    const k = Math.max(2, Math.floor(Math.min((cw - side - 40) / W, (ch * (side ? 0.62 : 0.45)) / H)));
    const bx = Math.round(side + (cw - side - W * k) / 2), by = Math.round(ch - H * k - ch * 0.08);
    g.fillStyle = night ? '#2f4a2a' : '#6cc04a'; g.fillRect(0, by + H * k - 2, cw, ch);
    this.off.getContext('2d').putImageData(building(scene), 0, 0);
    g.drawImage(this.off, bx, by, W * k, H * k);
    // The storm cloud and its rain.
    if (scene.rain) {
      this.offCloud.getContext('2d').putImageData(cloud(now), 0, 0);
      const ck = k * 1.15;
      g.drawImage(this.offCloud, bx + 60 * k - 32 * ck, by + 2 * k - 18 * ck, 64 * ck, 18 * ck);
      if (Math.random() < 0.6) this.drops.push({ x: bx + (22 + Math.random() * 80) * k, y: by - 4 * k, t0: now });
      g.fillStyle = 'rgba(120,150,200,0.8)';
      this.drops = this.drops.filter((d) => now - d.t0 < 0.6);
      for (const d of this.drops) g.fillRect(d.x, d.y + (now - d.t0) * 40 * k, Math.max(2, k / 2), k * 1.5);
    }
    // Fireworks.
    this.fw = this.fw.filter((f) => now - f.t0 < 1.6);
    for (const f of this.fw) {
      const u = now - f.t0; if (u < 0) continue;
      const x = f.x * cw, y = f.y * ch + 40;
      for (let i = 0; i < 14; i++) {
        const a = (i / 14) * Math.PI * 2, r = u * 90;
        g.fillStyle = `hsla(${f.hue + i * 6},90%,65%,${Math.max(0, 1 - u / 1.6)})`;
        g.fillRect(x + Math.cos(a) * r, y + Math.sin(a) * r + u * u * 20, 5, 5);
      }
    }
    return true;
  }
}
