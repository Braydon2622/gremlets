// Floating biome islands: the habitat's ledges drawn as little chunks of a world (port of the Mac app's IslandArt.swift).
// A layered terrain body (topsoil, dirt, stone, ore) that tapers to a jagged underside with roots, vines or icicles
// hanging off it, plus a strip of life on top (grass tufts, flowers, trees, cacti, crystals, glowing mushrooms).
// Platform geometry is untouched: only the drawing changes.
import { PixelCanvas, ArtRNG, int } from './pixelart.js';

export const BIOMES = ['meadow', 'snow', 'desert', 'jungle', 'glowshroom', 'crystal', 'cherry', 'autumn', 'sky'];

/** Top layer, its highlight, soil, deep stone, and a gem/ore colour. */
const PALETTES = {
  meadow:     { top: 0x5DBB46, topLight: 0x9BE36A, soil: 0x8A5A35, soilDark: 0x6B4428, stone: 0x7D7A74, stoneDark: 0x5A5752, ore: 0xF2C94C },
  snow:       { top: 0xF4FAFF, topLight: 0xFFFFFF, soil: 0x7B6A62, soilDark: 0x5C4F49, stone: 0x8C9BB0, stoneDark: 0x66738A, ore: 0x8FE3FF },
  desert:     { top: 0xF0D58C, topLight: 0xFFEDB3, soil: 0xD9B26A, soilDark: 0xB98E4E, stone: 0xC98E5A, stoneDark: 0x9E6B40, ore: 0xE85D5D },
  jungle:     { top: 0x3E9E3A, topLight: 0x6BD15A, soil: 0x5B4434, soilDark: 0x433226, stone: 0x5E6B4C, stoneDark: 0x434E36, ore: 0xB6F05C },
  glowshroom: { top: 0x3F7FE0, topLight: 0x7FB8FF, soil: 0x3B3A5A, soilDark: 0x2A2944, stone: 0x4A4A66, stoneDark: 0x33334D, ore: 0x6FF2FF },
  crystal:    { top: 0x7BA889, topLight: 0xA9D3B2, soil: 0x6E6A78, soilDark: 0x524E5C, stone: 0x5D5870, stoneDark: 0x423E52, ore: 0xD58CFF },
  cherry:     { top: 0x7CCB6A, topLight: 0xF7B6D2, soil: 0x8A5A35, soilDark: 0x6B4428, stone: 0x7D7A74, stoneDark: 0x5A5752, ore: 0xFF9EC7 },
  autumn:     { top: 0xD98A3A, topLight: 0xF2B45C, soil: 0x7A5232, soilDark: 0x5C3D24, stone: 0x7D7A74, stoneDark: 0x5A5752, ore: 0xF2C94C },
  sky:        { top: 0x6CC04A, topLight: 0x9BE36A, soil: 0x8A5A35, soilDark: 0x6B4428, stone: 0xA9BCD6, stoneDark: 0x7E93B3, ore: 0xFFE45C },
};

export const Biome = {
  palette: (b) => PALETTES[b],

  /** Which biome a shelf becomes: its style picks the family, the seed picks the variant, the season nudges it. */
  pick(style, seed, month) {
    switch (style) {
      case 'stone': return 'crystal';
      case 'leaf': return 'jungle';
      case 'mushroom': return 'glowshroom';
      case 'cloud': return 'sky';
      default: {
        let pool = ['meadow', 'meadow', 'desert', 'jungle', 'autumn', 'cherry', 'snow'];
        if ([12, 1, 2].includes(month)) pool = pool.concat(['snow', 'snow']);
        if ([3, 4, 5].includes(month)) pool = pool.concat(['cherry', 'cherry']);
        if ([9, 10, 11].includes(month)) pool = pool.concat(['autumn', 'autumn']);
        return pool[Number(BigInt(seed) % BigInt(pool.length))];
      }
    }
  },
};

/** The art seed for the habitat's ledge number `index`: fixed, so an island looks the same across frames and resizes. */
export const ledgeSeed = (index) => index * 7919 + 11;

/** A ledge's biome from its index: the ledges cycle through the shelf styles the Mac app builds (stone → crystal,
 *  cloud → sky, leaf → jungle, mushroom → glowshroom), with the plain planks taking a seeded seasonal pick (snow likelier
 *  in winter, cherry in spring, autumn in autumn). */
export function ledgeBiome(index, month) {
  const style = ['plank', 'stone', 'cloud', 'plank', 'leaf', 'plank', 'mushroom', 'cloud'][index % 8];
  return Biome.pick(style, ledgeSeed(index), month);
}

export const IslandArt = {
  /** The island's body, from the walking surface down. The top row of the image is the surface (the shelf's top edge). */
  body(b, w, seed) {
    const pal = PALETTES[b];
    const depth = Math.max(9, Math.min(22, int(w * 0.3)));
    const h = depth + 8;   // room for things hanging off the bottom
    const cv = new PixelCanvas(w, h);
    const r = new ArtRNG(BigInt(seed) + 11n);
    const seedN = Number(BigInt(seed) % 7n), seedI = Number(seed);
    // Underside profile: deepest in the middle, tapering to the ends, with a ragged edge.
    const bottom = new Array(w);
    for (let x = 0; x < w; x++) {
      const u = (x + 0.5) / w * 2 - 1;
      const shape = Math.pow(Math.max(0, 1 - u * u), 0.65);
      const ragged = r.range(-1.4, 1.4) + Math.sin(x * 0.9 + seedN) * 0.8;
      bottom[x] = Math.max(2, int(depth * shape + ragged));
    }
    // Canvas y is bottom-up; the surface is the top row (y = h - 1).
    const top = h - 1;
    for (let x = 0; x < w; x++) {
      for (let d = 0; d < bottom[x]; d++) {
        const y = top - d;
        let c;
        if (d === 0) c = (x + seedI) % 7 === 0 ? pal.topLight : pal.top;
        else if (d === 1) c = b === 'snow' || b === 'desert' ? pal.top : (x % 3 === 0 ? pal.top : pal.soil);   // grass roots into the dirt
        else if (d < 4 + int(r.range(0, 2))) c = (x * 7 + d * 3) % 11 === 0 ? pal.soilDark : pal.soil;
        else {
          c = (x * 5 + d * 7) % 13 === 0 ? pal.stoneDark : pal.stone;
          if (r.next() < 0.045) c = pal.ore;   // ore and gems glinting in the stone
        }
        if (b === 'desert' && d > 1 && d % 3 === 0) c = pal.soilDark;   // sandstone strata
        cv.set(x, y, c);
      }
    }
    cv.outline(0.62);
    // Re-light the top edge (outline darkened it).
    for (let x = 0; x < w; x++) if (cv.get(x, top) != null) cv.set(x, top, (x + seedI) % 7 === 0 ? pal.topLight : pal.top);
    // Things hanging off the underside.
    for (let x = 2; x < w - 2; x++) {
      if (!(r.next() < 0.16)) continue;
      const y0 = top - bottom[x], len = int(r.range(1, 6));
      for (let k = 0; k < len; k++) {
        let c;
        switch (b) {
          case 'snow': c = k === len - 1 ? 0xFFFFFF : 0xBFE6FF; break;                                   // icicles
          case 'jungle': case 'meadow': case 'cherry': case 'autumn': c = k % 2 === 0 ? 0x4F8A3A : 0x3E7030; break;   // roots and vines
          case 'glowshroom': c = k === len - 1 ? 0x6FF2FF : 0x3B5A8A; break;                             // glowing tendrils
          case 'crystal': c = k === len - 1 ? 0xE6B8FF : 0xA06BD6; break;                                // hanging crystals
          case 'desert': c = 0xB98E4E; break;                                                            // trickling sand
          default: continue;                                                                             // sky: clouds instead (below)
        }
        cv.set(x, y0 - k, c);
      }
    }
    // A sky island floats on a wreath of cloud hugging its underside.
    if (b === 'sky') {
      const cr = new ArtRNG(BigInt(seed) + 21n);
      let x = 1.0;
      while (x < w - 1) {
        const ix = int(x);
        const under = top - bottom[Math.min(w - 1, Math.max(0, ix))];
        const rad = cr.range(2.4, 4.2);
        cv.blob(x, under + 0.5, rad, rad * 0.7, 0xF5FAFF, 0xFFFFFF, 0xC6D6EA);
        x += rad * 1.3;
      }
      cv.blob(-1, top - bottom[0] + 3, 3.5, 2.5, 0xF5FAFF, 0xFFFFFF, 0xC6D6EA);
      cv.blob(w, top - bottom[w - 1] + 3, 3.5, 2.5, 0xF5FAFF, 0xFFFFFF, 0xC6D6EA);
    }
    return cv;
  },

  /** Life on top of the island, drawn upward from the surface (the bottom row of the image sits on the shelf's top edge).
   *  Keeps the middle low, with the landmark out at the right-hand end (flip the image for a left-hand island). */
  decor(b, w, seed, night) {
    const h = 24;
    const cv = new PixelCanvas(w, h);
    const r = new ArtRNG(BigInt(seed) + 99n);
    const pal = PALETTES[b];
    // Low tufts all along.
    for (let x = 0; x < w; x++) {
      if (!(r.next() < 0.45)) continue;
      let t;
      switch (b) {
        case 'snow': t = 0xE8F4FF; break;
        case 'desert': t = r.next() < 0.3 ? 0x9CB45A : pal.topLight; break;
        case 'glowshroom': t = 0x5FA0FF; break;
        case 'crystal': t = 0x7BA889; break;
        case 'autumn': t = r.next() < 0.5 ? 0xE0A04A : 0xC77A30; break;
        default: t = r.next() < 0.5 ? pal.topLight : pal.top;
      }
      cv.set(x, 0, t);
      if (r.next() < 0.35) cv.set(x, 1, t);
    }
    // Small flowers / pebbles scattered.
    for (let i = 0; i < int(w / 9); i++) {
      const x = int(r.range(1, w - 2));
      switch (b) {
        case 'meadow': cv.set(x, 2, [0xFF6B6B, 0xFFD45E, 0xFFFFFF, 0xB98CFF][int(r.range(0, 3.99))]); cv.set(x, 1, 0x3E8E3A); break;
        case 'cherry': cv.set(x, 1, 0xFFB6D9); break;
        case 'jungle': cv.set(x, 2, 0xFF5FA2); cv.set(x, 1, 0x2F7A2C); break;
        case 'autumn': cv.blob(x, 1.5, 1.6, 1.3, 0xE8862C, 0xFFB45C); break;   // tiny pumpkins
        case 'glowshroom': cv.set(x, 1, night ? 0x9FFFFF : 0x6FD2FF); cv.set(x, 0, 0xCFE6FF); break;
        case 'crystal': cv.set(x, 1, pal.ore); cv.set(x, 2, 0xF3D9FF); break;
        case 'snow': cv.set(x, 0, 0xFFFFFF); break;
        case 'desert': cv.set(x, 0, 0xC9A36A); break;
        case 'sky': cv.set(x, 1, 0xFFE45C); break;
      }
    }
    // The landmark at the outer end.
    const ex = w - 7, exi = int(ex);
    switch (b) {
      case 'meadow':
        cv.rect(exi, 0, 2, 9, 0x7A5232);
        cv.blob(ex + 1, 13, 6, 5, 0x4FA83A, 0x8BD66A, 0x2F7A2C);
        break;
      case 'cherry':
        cv.rect(exi, 0, 2, 9, 0x6B4428);
        cv.blob(ex + 1, 13, 6.5, 5, 0xF7A6CB, 0xFFD6E8, 0xD6789F);
        break;
      case 'autumn':
        cv.rect(exi, 0, 2, 8, 0x6B4428);
        cv.blob(ex + 1, 12, 6, 5, 0xE0782C, 0xF7B45C, 0xB5521F);
        break;
      case 'snow':   // a snowy pine
        cv.rect(exi, 0, 2, 3, 0x6B4428);
        [6, 5, 4, 3, 2, 1].forEach((rw, i) => {
          cv.rect(exi + 1 - rw, 3 + i * 3, rw * 2, 3, 0x2F6B4A);
          cv.rect(exi + 1 - rw, 5 + i * 3, rw * 2, 1, 0xF4FAFF);
        });
        break;
      case 'desert':   // a cactus with an arm
        cv.rect(exi, 0, 3, 12, 0x5E9E4A); cv.rect(exi, 0, 1, 12, 0x3E7A34);
        cv.rect(exi + 3, 5, 2, 2, 0x5E9E4A); cv.rect(exi + 4, 5, 2, 5, 0x5E9E4A);
        cv.set(exi + 1, 12, 0xFF6B9A);
        break;
      case 'jungle':   // big drooping leaves
        cv.rect(exi, 0, 1, 10, 0x2F7A2C);
        cv.blob(ex - 3, 9, 4.5, 2, 0x3EA83A, 0x7FD66A);
        cv.blob(ex + 4, 11, 4.5, 2, 0x3EA83A, 0x7FD66A);
        cv.blob(ex, 13, 3, 2, 0x4FB84A, 0x8FE07A);
        break;
      case 'glowshroom':
        for (const [dx, hgt, rad] of [[0, 9, 4.5], [-6, 5, 3], [5, 6, 2.6]]) {
          cv.rect(int(ex + dx), 0, 1, int(hgt), 0xCFE6FF);
          cv.blob(ex + dx, hgt, rad, rad * 0.6, night ? 0x5FE8FF : 0x3FA8E0, 0xBFFFFF);
        }
        break;
      case 'crystal':
        for (const [dx, hgt] of [[0, 11], [-3, 7], [3, 8]]) {
          for (let y = 0; y < hgt; y++) {
            const half = Math.max(0, int((hgt - y) / 3));
            cv.rect(int(ex + dx) - half, y, half * 2 + 1, 1, y > hgt - 3 ? 0xF3D9FF : 0xB57AF2);
          }
        }
        break;
      case 'sky':   // a little golden fence and a star
        for (let x = exi - 6; x <= exi + 4; x += 3) cv.rect(x, 0, 1, 4, 0xE8C25A);
        cv.rect(exi - 6, 3, 11, 1, 0xE8C25A);
        cv.set(exi + 3, 9, 0xFFE45C); cv.set(exi + 2, 9, 0xFFF3A0); cv.set(exi + 3, 10, 0xFFF3A0);
        break;
    }
    return cv;
  },
};
