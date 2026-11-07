// Little things growing in the moss on the branches (see the sprouts section of engine.js): a straight port of the Mac
// app's SproutArt.swift. 9 × 11 art pixels, the base on row 0 (PixelCanvas is y-up, like the Swift one), so the
// pixels match the Mac's exactly. No DOM access here, so the art can be checked in a plain JS shell (tests).
import { PixelCanvas, int } from './pixelart.js';

const STEM = 0x5E9E46, LEAF = 0x8BD66A, DARK = 0x3F7A34, WHITE = 0xFFFFFF;

function draw(kind, ripe, cv) {
  switch (kind) {
    case 'daisy':
      for (let y = 0; y <= 5; y++) cv.set(4, y, STEM);
      cv.set(3, 2, LEAF); cv.set(2, 3, LEAF); cv.set(5, 3, LEAF); cv.set(6, 4, LEAF);
      if (ripe) {
        for (const [x, y] of [[4, 9], [4, 6], [2, 8], [6, 8], [3, 9], [5, 9], [3, 7], [5, 7], [2, 7], [6, 7]]) cv.set(x, y, WHITE);
        cv.set(3, 8, 0xF2C94C); cv.set(4, 8, 0xF5B82E); cv.set(5, 8, 0xF2C94C); cv.set(4, 7, 0xE0A030);
      } else {
        cv.set(4, 6, LEAF); cv.set(4, 7, 0xF2E6B0); cv.set(3, 6, STEM); cv.set(5, 6, STEM);
      }
      break;
    case 'mushroom': {
      const cap = 0xD9534F, capLight = 0xEE7A6A, stalk = 0xF2E6D0;
      if (ripe) {
        cv.rect(3, 0, 3, 3, stalk); cv.set(5, 1, 0xD8C8AE);
        cv.rect(1, 3, 7, 2, cap); cv.rect(2, 5, 5, 1, cap); cv.rect(3, 6, 3, 1, capLight);
        cv.set(2, 4, WHITE); cv.set(5, 5, WHITE); cv.set(6, 3, WHITE);
        cv.set(0, 0, LEAF); cv.set(7, 0, LEAF); cv.set(8, 1, LEAF);
      } else {
        cv.rect(4, 0, 1, 2, stalk); cv.rect(3, 2, 3, 1, cap); cv.set(4, 3, capLight);
        cv.set(2, 0, LEAF); cv.set(6, 0, LEAF);
      }
      break;
    }
    case 'berries': {
      for (let y = 0; y <= 4; y++) cv.set(4, y, STEM);
      cv.set(3, 5, STEM); cv.set(5, 5, STEM); cv.set(2, 6, STEM); cv.set(6, 6, STEM);
      cv.set(1, 6, LEAF); cv.set(2, 7, LEAF); cv.set(7, 6, LEAF); cv.set(6, 7, LEAF); cv.set(4, 5, LEAF); cv.set(4, 6, LEAF);
      const b = ripe ? 0x6A4FC8 : 0x9CCB6A, bl = ripe ? 0x9A84E8 : 0xC4E39A;
      for (const [x, y] of [[2, 3], [6, 3], [3, 2], [5, 4]]) cv.set(x, y, b);
      cv.set(2, 4, bl); cv.set(6, 4, bl);
      if (ripe) { cv.set(3, 3, 0xD9534F); cv.set(5, 2, 0xD9534F); }
      break;
    }
    case 'dandelion':
      for (let y = 0; y <= 6; y++) cv.set(4, y, STEM);
      cv.set(3, 1, LEAF); cv.set(2, 1, LEAF); cv.set(5, 2, LEAF); cv.set(6, 1, LEAF); cv.set(1, 0, DARK); cv.set(7, 0, DARK);
      if (ripe) {
        // The seed clock.
        for (const [x, y] of [[4, 10], [2, 9], [6, 9], [1, 8], [7, 8], [2, 7], [6, 7], [4, 6], [3, 10], [5, 10], [1, 7], [7, 7]]) cv.set(x, y, WHITE);
        for (const [x, y] of [[3, 8], [4, 8], [5, 8], [3, 9], [5, 9], [4, 9], [3, 7], [5, 7], [4, 7]]) cv.set(x, y, 0xE8E4DA);
        cv.set(4, 8, 0xC9C2B0);
      } else {
        cv.rect(3, 7, 3, 2, 0xF5C431); cv.set(4, 9, 0xF5D75A); cv.set(2, 8, 0xF5C431); cv.set(6, 8, 0xF5C431);
      }
      break;
  }
}

/** The night version of a colour (same factors as the Mac's). */
export function dimmed(c) {
  const r = ((c >> 16) & 0xFF) * 0.72, g = ((c >> 8) & 0xFF) * 0.74, b = (c & 0xFF) * 0.85;
  return (int(r) << 16) | (int(g) << 8) | int(b);
}

export const SproutArt = {
  KINDS: ['daisy', 'mushroom', 'berries', 'dandelion'],

  /** One sprout at stage 0 (a shoot, whatever it'll be), 1 (budding) or 2 (ready), as a 9 × 11 PixelCanvas. */
  canvas(kind, stage, night) {
    const cv = new PixelCanvas(9, 11);
    if (stage === 0) {
      cv.set(4, 0, STEM); cv.set(4, 1, STEM); cv.set(3, 2, LEAF); cv.set(5, 2, LEAF); cv.set(4, 2, STEM);
    } else {
      draw(kind, stage === 2, cv);
    }
    // White petals and seed clocks stay white through the outline.
    const white = [];
    cv.px.forEach((c, i) => { if (c === WHITE) white.push(i); });
    cv.outline(0.66);
    for (const i of white) cv.px[i] = WHITE;
    if (night) cv.px = cv.px.map((c) => (c < 0 ? c : c === WHITE ? 0xD8DCE8 : dimmed(c)));
    return cv;
  },

  /** One drifting dandelion seed, 3 × 4. */
  seedCanvas() {
    const cv = new PixelCanvas(3, 4);
    cv.set(1, 0, 0x9C8F78); cv.set(1, 1, 0xD9D2C5); cv.set(0, 2, WHITE); cv.set(1, 3, WHITE); cv.set(2, 2, WHITE); cv.set(1, 2, 0xF4F0E8);
    return cv;
  },
};
