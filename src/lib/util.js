// Utilitários compartilhados pelos geradores: cores, direções e fitas curvas.
import { rgbToHsv, hsvToRgb } from '../color.js';
import { rotMatrix, mulMV } from '../shapes.js';
import * as K from './kit.js';

export const rad = (d) => (d * Math.PI) / 180;
export const mixc = (a, b, t) => a.map((x, i) => x + (b[i] - x) * t);
export const addv = (a, b) => a.map((x, i) => x + b[i]);
export const scalev = (a, k) => a.map((x) => x * k);

// cor com variação em HSV (matiz em graus; sat e val absolutos), reprodutível pelo rng u
export function jitter(c, u, hue, sat, val) {
  const [h, s, v] = rgbToHsv(c);
  const j = (r) => (u() * 2 - 1) * r;
  return hsvToRgb(h + j(hue), Math.min(1, Math.max(0, s + j(sat))), Math.min(1, Math.max(0, v + j(val))));
}

// Direção unitária: tilt = ângulo a partir da vertical (0 = para cima, 90 = horizontal, 180 = para baixo),
// yaw = giro em volta do eixo y.
export function dirVec(yaw, tilt) {
  const t = rad(tilt), y = rad(yaw);
  return [Math.sin(t) * Math.cos(y), Math.cos(t), Math.sin(t) * Math.sin(y)];
}

// Fita curva com a base na origem, achatada em z (folhas, lâminas, frondes). tilts = ângulo de cada
// peça (graus a partir da vertical, para o lado +z); a largura afina até a ponta.
// Devolve { shape, tip }. Gire com K.rot(..., 0, yaw, 0, [0, 0, 0]) e mova com K.move.
export function ribbon(len, w, tilts, flat = 0.15) {
  const n = tilts.length, parts = [];
  let pos = [0, 0, 0];
  for (let k = 0; k < n; k++) {
    const l = len / n;
    const r0 = (w / 2) * (1 - (k / n) * 0.85), r1 = (w / 2) * Math.max(0.04, 1 - ((k + 1) / n) * 0.97);
    let piece = K.at(K.scale(K.cone(r0, l, r1), [1, 1, flat]), 0, l / 2, 0);
    piece = K.move(K.rot(piece, tilts[k], 0, 0, [0, 0, 0]), pos);
    parts.push(piece);
    pos = addv(pos, K.tipOf(l, tilts[k]));
  }
  return { shape: K.group(parts), tip: pos };
}

// Fita já girada em yaw e posicionada em `at`; tip no espaço da cena.
export function placedRibbon(at, yaw, len, w, tilts, flat) {
  const r = ribbon(len, w, tilts, flat);
  return {
    shape: K.move(K.rot(r.shape, 0, yaw, 0, [0, 0, 0]), at),
    tip: addv(mulMV(rotMatrix(0, yaw, 0), r.tip), at),
  };
}

// Tinta uma forma conforme o estilo: degradê (base -> ponta) ou cor chapada; no realista, manchas
// com relevo. `size` é a escala das manchas (m).
export function paintStyle(shape, S, base, tip, size = 0.2) {
  const c = K.color(shape, base);
  if (S.mottle) return K.texture(c, 'mottle', { color2: tip, size, bump: S.bump * 0.6 });
  if (S.gradient) return K.texture(c, 'gradient', { color2: tip });
  return c;
}

// Segmento facetado (caixa) entre dois pontos: o equivalente "low poly" de K.taper.
export function boxSeg(from, to, w, d = w * 0.8) {
  const v = to.map((x, i) => x - from[i]);
  const len = Math.hypot(...v);
  const n = v.map((x) => x / (len || 1));
  const ax = (Math.asin(Math.max(-1, Math.min(1, n[2]))) * 180) / Math.PI;
  const az = (Math.atan2(-n[0], n[1]) * 180) / Math.PI;
  const body = K.rot(K.box(w, Math.max(len, 1e-4), d), ax, 0, az, [0, 0, 0]);
  return K.at(body, ...from.map((x, i) => x + v[i] / 2));
}

// Direção que pende de uma junta: alpha = balanço para a frente (+z), beta = abertura para o lado.
// alpha = beta = 0 aponta reto para baixo; alpha = 180 aponta para cima.
export function limbDir(alpha, beta, side) {
  const a = rad(alpha), b = rad(beta);
  return [side * Math.sin(b), -Math.cos(a) * Math.cos(b), Math.sin(a) * Math.cos(b)];
}
