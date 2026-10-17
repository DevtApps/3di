// Kit de formas para os geradores: a mesma linguagem do script (primitivas, at, rotate, color,
// texture, repeat...), mas em JavaScript e sem checagem de argumentos de usuário.
// Tudo devolve Shapes imutáveis, exatamente como os métodos da linguagem.
import { Shape, METHODS, union, segmentShape, shapeBinary, rotMatrix, mulMV } from '../shapes.js';

const M = (name, s, args) => METHODS[name][1](s, args);

// ---------- primitivas (centradas na origem, como na linguagem) ----------
export const box = (w, h = w, d = w, round = 0) => new Shape('box', { size: [w, h, d], r: Math.min(round, Math.min(w, h, d) / 2) });
export const sphere = (r) => new Shape('sphere', { r });
export const cyl = (r, h, round = 0) => new Shape('cylinder', { r, h, round: Math.min(round, r, h / 2) });
export const cone = (r, h, top = 0) => new Shape('cone', { r, h, top });
export const pyramid = (w, h) => new Shape('pyramid', { w, h });
export const prism = (w, h, d) => new Shape('prism', { w, h, d });
export const ellipsoid = (x, y, z) => new Shape('ellipsoid', { radii: [x, y, z] });
export const capsule = (r, h) => new Shape('capsule', { r, h: Math.max(h, 2 * r) });
export const torus = (R, r) => new Shape('torus', { R, r });
export const plane = () => new Shape('plane');
export const segment = (a, b, r) => segmentShape(a, b, r);

// ---------- transformações ----------
export const at = (s, x = 0, y = 0, z = 0) => M('at', s, { x, y, z });
export const move = (s, v) => at(s, v[0], v[1], v[2]);
export const rot = (s, x = 0, y = 0, z = 0, pivot = null) => M('rotate', s, { x, y, z, pivot });
export const scale = (s, f, pivot = null) => M('scale', s, { s: f, pivot });
export const ground = (s) => M('ground', s, {});
export const mirror = (s, axes = 'x') => M('mirror', s, { axes });
export const repeat = (s, { x = 1, y = 1, z = 1, spacing = null } = {}) => M('repeat', s, { x, y, z, spacing });
export const displace = (s, amount, size) => M('displace', s, { amount, size });

// ---------- materiais ----------
export const color = (s, c) => M('color', s, { c });
export const material = (s, { color: c = null, rough = null, metal = null, glow = null } = {}) => M('material', s, { color: c, rough, metal, glow });
export const texture = (s, kind, { color2 = null, size = null, axis = 'y', bump = 0, triplanar = false, range = null } = {}) =>
  M('texture', s, { kind, color2, size, axis, bump, triplanar, range });
export const named = (s, label) => M('name', s, { label });

// ---------- combinar ----------
export const group = (list, smooth = 0) => union(list.flat(Infinity).filter(Boolean), smooth);
export const subtract = (a, cutters, smooth = 0) => new Shape('subtract', { k: smooth }, [a, union([cutters].flat(Infinity))]);
export const intersect = (a, b) => shapeBinary('&', a, b);

// ---------- geometria auxiliar ----------
// Ponta de um segmento de comprimento len que parte da origem e é girado por (ax, ay, az) graus.
export const tipOf = (len, ax = 0, ay = 0, az = 0) => mulMV(rotMatrix(ax, ay, az), [0, len, 0]);

// Segmento cônico (tronco de cone) com a base em `from` e a ponta em `to`, raios r0 -> r1.
// Serve para galhos, caules, lâminas e membros afinando.
export function taper(from, to, r0, r1) {
  const d = to.map((v, i) => v - from[i]);
  const len = Math.hypot(...d);
  const body = cone(r0, Math.max(len, 1e-4), r1);
  // o cone fica em pé e centrado; gira o eixo y até a direção d e leva a base até `from`
  const n = d.map((v) => v / (len || 1));
  const ax = (Math.asin(Math.max(-1, Math.min(1, n[2]))) * 180) / Math.PI;
  const az = (Math.atan2(-n[0], n[1]) * 180) / Math.PI;
  const rotated = rot(body, ax, 0, az, [0, 0, 0]);
  const mid = from.map((v, i) => v + d[i] / 2);
  return at(rotated, mid[0], mid[1], mid[2]);
}
