// Tiny pixel-art particles (same designs as the Mac app) and a lightweight particle system.

function stamp(rows, palette) {
  const h = rows.length, w = rows[0].length;
  const cv = document.createElement('canvas');
  cv.width = w; cv.height = h;
  const ctx = cv.getContext('2d');
  rows.forEach((row, y) => [...row].forEach((ch, x) => {
    const c = palette[ch];
    if (c == null) return;
    ctx.fillStyle = '#' + c.toString(16).padStart(6, '0');
    ctx.fillRect(x, y, 1, 1);
  }));
  return cv;
}

export const FX = {
  heart: stamp(['.rr.rr.', 'rRRrrrr', 'rRrrrrr', '.rrrrr.', '..rrr..', '...r...'], { r: 0xff5e7e, R: 0xffd1dc }),
  smallHeart: stamp(['r.r', 'rrr', '.r.'], { r: 0xff8fa8 }),
  bang: stamp(['.oo.', 'oYYo', 'oYYo', 'oYYo', 'oYYo', '.oo.', '....', '.oo.', 'oYYo', '.oo.'], { o: 0x5a2a10, Y: 0xffd23d }),
  smallBang: stamp(['oYo', 'oYo', '...', 'oYo'], { o: 0x5a2a10, Y: 0xffd23d }),
  star: stamp(['..y..', '.yYy.', 'yYYYy', '.yYy.', 'y...y'], { y: 0xf5b82e, Y: 0xfff29a }),
  smallStar: stamp(['.y.', 'yYy', '.y.'], { y: 0xf5b82e, Y: 0xfff29a }),
  dust: stamp(['.ww.', 'wWWw', 'wWWw', '.ww.'], { w: 0xd9d2c5, W: 0xf4f0e8 }),
  zzz: stamp(['zzzz', '..z.', '.z..', 'zzzz'], { z: 0x8fa8d8 }),
  note: stamp(['..nn', '..nN', '..n.', '..n.', 'nnn.', 'nnn.'], { n: 0x3a3a6a, N: 0x6f6fb0 }),
  note2: stamp(['.nnnn', '.n..n', '.n..n', 'nn.nn', 'nn.nn'], { n: 0x5a2a6a }),
  flame: stamp(['..A.', '.AaA', 'AaYa', '.aa.'], { A: 0xff6a2b, a: 0xffc23d, Y: 0xfff6a8 }),
  flame2: stamp(['.A.', 'AYA', '.A.'], { A: 0xff8a3d, Y: 0xfff6a8 }),
  smoke: stamp(['.ss.', 'sSSs', 'sSSs', '.ss.'], { s: 0x8a8494, S: 0xbdb8c6 }),
  snow: stamp(['w.w', '.W.', 'w.w'], { w: 0xa8c8f0, W: 0xffffff }),
  rain: stamp(['.b', 'bB', 'bb'], { b: 0x6fb8f0, B: 0xd8f0ff }),
  petal: stamp(['.pp', 'pPp', 'pp.'], { p: 0xff9ec4, P: 0xffe0ee }),
  leaf: stamp(['..gg', '.gGg', 'gGg.', 'g...'], { g: 0x5faf4a, G: 0xa8e08a }),
  leaf2: stamp(['..oo', '.oOo', 'oOo.', 'o...'], { o: 0xe8784a, O: 0xffc08a }),
  seed: stamp(['.k.', 'kKk', '.k.'], { k: 0x3a3a40, K: 0xe8e2d0 }),
  pollen: stamp(['.y.', 'yYy', '.y.'], { y: 0xffc93c, Y: 0xfff29a }),
  steam: stamp(['.ww.', 'wWWw', '.ww.'], { w: 0xdfe6ee, W: 0xffffff }),
  cloud: stamp(['.ww..', 'wWWww', 'wwwww'], { w: 0xe0e8f4, W: 0xffffff }),
  bubble: stamp(['.bb.', 'bW.b', 'b..b', '.bb.'], { b: 0x8fd3f0, W: 0xffffff }),
  ink: stamp(['.kk.', 'kKkk', 'kkkk', '.kk.'], { k: 0x2a1e3a, K: 0x5a4a7a }),
  sparkle: stamp(['..y..', '..y..', 'yyWyy', '..y..', '..y..'], { y: 0xffd86b, W: 0xffffff }),
};

const easeOut = (t) => 1 - (1 - t) * (1 - t);

/** Particles fly from a start to an end point over their lifetime, fading in and out. */
export class Particles {
  constructor() { this.list = []; }

  burst(img, at, { count = 1, dx = [0, 0], dy = [0, 0], duration = 1, delay = 0, stagger = 0, spin = 1.2, imgs = null } = {}) {
    for (let i = 0; i < count; i++) {
      const r = (a) => a[0] + Math.random() * (a[1] - a[0]);
      this.list.push({
        img: imgs ? imgs[i % imgs.length] : img, x0: at.x, y0: at.y, x1: at.x + r(dx), y1: at.y + r(dy),
        t: -(delay + i * stagger), life: duration * (0.85 + Math.random() * 0.3), rot: (Math.random() * 2 - 1) * spin,
      });
    }
  }

  /** Orbiting stars (dizzy). `follow` returns the current centre so they track the creature. */
  orbit(follow, duration = 1.85) {
    for (let i = 0; i < 3; i++) this.list.push({ img: i === 1 ? FX.smallStar : FX.star, orbit: follow, phase: i / 3, t: 0, life: duration });
  }

  update(dt) {
    for (const p of this.list) p.t += dt;
    this.list = this.list.filter((p) => p.t < p.life);
  }

  /** Draws in world coordinates via `toScreen` (y-up world → canvas). */
  draw(ctx, toScreen, px) {
    for (const p of this.list) {
      if (p.t < 0) continue;
      const k = p.t / p.life;
      let x, y, a;
      if (p.orbit) {
        const c = p.orbit();
        const ang = (p.t / 0.8 + p.phase) * Math.PI * 2;
        x = c.x + Math.cos(ang) * 22; y = c.y + Math.sin(ang) * 6;
        a = k < 0.1 ? k / 0.1 : k > 0.85 ? (1 - k) / 0.15 : 1;
      } else {
        const e = easeOut(k);
        x = p.x0 + (p.x1 - p.x0) * e; y = p.y0 + (p.y1 - p.y0) * e;
        a = k < 0.1 ? k / 0.1 : k > 0.6 ? Math.max(0, (1 - k) / 0.4) : 1;
      }
      const s = toScreen(x, y);
      const w = p.img.width * px, h = p.img.height * px;
      ctx.save();
      ctx.globalAlpha = a;
      ctx.translate(Math.round(s.x), Math.round(s.y));
      if (p.rot) ctx.rotate(p.rot * k);
      ctx.drawImage(p.img, -w / 2, -h / 2, w, h);
      ctx.restore();
    }
  }
}
