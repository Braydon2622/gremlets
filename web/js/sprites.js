// Loads Gremlet sprite sheets (Aseprite JSON format, same files the Mac app uses) for the web habitat.
import { Species } from './engine.js';

let base = null;

/** Finds the Species folder: next to the page (deployed) or one level up (running from the repo). */
export async function speciesBase() {
  if (base) return base;
  for (const candidate of ['Species/', '../Species/']) {
    try {
      const r = await fetch(candidate + 'index.json', { cache: 'no-cache' });
      if (r.ok) { base = candidate; return base; }
    } catch { /* try next */ }
  }
  throw new Error('Could not find the Species folder');
}

export async function loadIndex() {
  const b = await speciesBase();
  return (await (await fetch(b + 'index.json')).json()).species;
}

function loadImage(src) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('failed to load ' + src));
    img.src = src;
  });
}

const cache = new Map();

/**
 * Loads one species. `scale` overrides the on-screen pixel size (phones use a smaller scale).
 * Returns { species, image, rects } where rects[i] is the source rect of frame i in the sheet.
 */
export async function loadSpecies(id, scale) {
  const key = id + '@' + scale;
  if (cache.has(key)) return cache.get(key);
  const promise = (async () => {
    const b = await speciesBase();
    const [sheet, info, image] = await Promise.all([
      fetch(`${b}${id}/sheet.json`).then((r) => r.json()),
      fetch(`${b}${id}/species.json`).then((r) => r.json()).catch(() => ({})),
      loadImage(`${b}${id}/sheet.png`),
    ]);
    const frames = Array.isArray(sheet.frames) ? sheet.frames : Object.values(sheet.frames);
    const rects = frames.map((f) => f.frame);
    const durations = frames.map((f) => (f.duration ?? 100) / 1000);

    // Alpha masks for per-pixel hit testing.
    const cv = document.createElement('canvas');
    cv.width = image.width; cv.height = image.height;
    const ctx = cv.getContext('2d', { willReadFrequently: true });
    ctx.drawImage(image, 0, 0);
    const masks = rects.map((r) => {
      const d = ctx.getImageData(r.x, r.y, r.w, r.h).data;
      const m = new Array(r.w * r.h);
      for (let i = 0; i < m.length; i++) m[i] = d[i * 4 + 3] > 24;
      return m;
    });

    const animations = {};
    for (const tag of sheet.meta?.frameTags ?? []) {
      let idx = [];
      for (let i = tag.from; i <= tag.to; i++) idx.push(i);
      if (tag.direction === 'reverse') idx.reverse();
      if (tag.direction === 'pingpong') idx = idx.concat(idx.slice(1, -1).reverse());
      animations[tag.name.toLowerCase()] = { frames: idx, durations: idx.map((i) => durations[i]) };
    }
    if (!animations.idle) animations.idle = { frames: rects.map((_, i) => i), durations };

    const species = new Species({
      id, name: info.name ?? id, element: info.element ?? '', family: info.family ?? '', description: info.description ?? '',
      frameWidth: Math.max(...rects.map((r) => r.w)), frameHeight: Math.max(...rects.map((r) => r.h)),
      scale, animations, masks,
      walkSpeed: info.walkSpeed ?? 70, jumpPower: info.jumpPower ?? 1, sleepiness: info.sleepiness ?? 1,
      flies: !!info.flies, special: info.special ?? 'sparkle',
    });
    return { species, image, rects };
  })();
  cache.set(key, promise);
  return promise;
}
