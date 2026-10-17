// Utilitários de cor para a linguagem: tudo em sRGB 0..1, que é o que .color((r, g, b)) espera.
import { parseColor } from './shapes.js';

const linearToSrgb = (c) => (c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055);
const clamp01 = (x) => Math.min(1, Math.max(0, x));

// nome, "#rrggbb" ou tupla -> [r, g, b] em sRGB 0..1
export function toSrgb(v) {
  return parseColor(v).map((c) => clamp01(linearToSrgb(c)));
}

export function hsvToRgb(h, s, v) {
  const hh = (((h % 360) + 360) % 360) / 60;
  const i = Math.floor(hh), f = hh - i;
  const p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f));
  return [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][i % 6];
}

export function rgbToHsv([r, g, b]) {
  const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
  let h = 0;
  if (d > 1e-9) {
    if (max === r) h = ((g - b) / d) % 6;
    else if (max === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h *= 60;
    if (h < 0) h += 360;
  }
  return [h, max <= 0 ? 0 : d / max, max];
}

export const isColorLike = (v) => typeof v === 'string' || (Array.isArray(v) && v.length === 3 && v.every((x) => typeof x === 'number'));
