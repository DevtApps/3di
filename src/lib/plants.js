// Gerador de plantas pequenas: plant(kind=..., style=...).
//
//   kind  = que planta é   (flower, daisy, lavender, fern, bush, cactus, mushroom)
//   style = como é desenhada (lowpoly, stylized, realistic)
//
// `density` vira "quantas": mais hastes na lavanda, mais frondes na samambaia, mais blocos no
// arbusto, e touceiras de 1 a 6 plantas nas flores e cogumelos. `color` é a cor de destaque
// (pétalas, chapéu do cogumelo, espigas) ou a da folhagem (samambaia, arbusto, cacto).
import { Native, didYouMean, num } from '../runtime.js';
import { ScriptError } from '../parser.js';
import { toSrgb } from '../color.js';
import * as K from './kit.js';
import { resolveStyle } from './style.js';
import { randTools, rngFor } from './rand.js';
import { mixc, jitter, addv, scalev, dirVec, rad, placedRibbon, paintStyle } from './util.js';

const KINDS = {
  flower:   { h: 0.35, color: null,      leaf: '#2f7a2a', info: 'flor de cinco pétalas num caule' },
  daisy:    { h: 0.3,  color: '#fafaf2', leaf: '#3a8a30', info: 'margarida: muitas pétalas finas' },
  lavender: { h: 0.5,  color: '#8a5cc8', leaf: '#5f8a4a', info: 'lavanda: hastes com espigas roxas' },
  fern:     { h: 0.5,  color: '#2f8a3a', leaf: '#2f8a3a', info: 'samambaia de frondes arqueadas' },
  bush:     { h: 0.9,  color: '#3a7d2c', leaf: '#3a7d2c', info: 'arbusto de blocos de folhas' },
  cactus:   { h: 1.4,  color: '#3f8f4a', leaf: '#3f8f4a', info: 'cacto saguaro com braços' },
  mushroom: { h: 0.18, color: '#c8382b', leaf: '#e8dcc2', info: 'cogumelo de chapéu com manchas' },
};
export const PLANT_KINDS = Object.keys(KINDS);

const PETALS = [[0.95, 0.4, 0.6], [1, 0.85, 0.2], [0.65, 0.4, 0.9], [0.95, 0.3, 0.25], [1, 0.6, 0.2], [0.98, 0.98, 0.95]];
const lvl = (S, a) => a[S.name === 'lowpoly' ? 0 : S.name === 'stylized' ? 1 : 2];

// posições de uma touceira: a primeira no centro, as outras em volta
function clump(n, radius, u) {
  const out = [[0, 0, 0]];
  for (let i = 1; i < n; i++) {
    const a = rad(((i - 1) * 360) / Math.max(1, n - 1) + u(-30, 30)), r = radius * u(0.7, 1.2);
    out.push([Math.cos(a) * r, 0, Math.sin(a) * r]);
  }
  return out;
}

// Caule de 1 a 2 peças com leve curvatura; devolve { shape, top }.
function stem(B, at, h, r) {
  const { S, u } = B;
  const pieces = lvl(S, [1, 2, 2]);
  const parts = [];
  let pos = at;
  const yaw = u(0, 360), bend = u(2, 9);
  for (let k = 0; k < pieces; k++) {
    const next = addv(pos, scalev(dirVec(yaw, bend * (k + 1)), h / pieces));
    parts.push(K.taper(pos, next, r * (1 - 0.3 * (k / pieces)), r * (1 - 0.3 * ((k + 1) / pieces))));
    pos = next;
  }
  return { shape: K.color(K.group(parts), mixc(B.leaf, [0, 0.1, 0], 0.15)), top: pos };
}

// Flor: caule, folhas, pétalas em roda e miolo.
function bloom(B, at, o) {
  const { S, u, H } = B;
  const h = H * o.size * u(0.85, 1.1);
  const st = stem(B, at, h, H * 0.018);
  const parts = [st.shape];
  const n = o.petals ?? lvl(S, [5, 6, 8]);
  const pl = H * o.pl * o.size, pw = H * o.pw * o.size;
  const petalCol = o.petal;
  for (let i = 0; i < n; i++) {
    let p = S.facets ? K.scale(K.pyramid(pw * 2, pl * 2), [1, 1, 0.3]) : K.ellipsoid(pw, pl, pw * 0.3);
    p = S.facets ? K.ground(p) : K.at(p, 0, pl, 0);
    p = K.rot(p, o.tilt + u(-6, 6), 0, 0, [0, 0, 0]);
    p = K.move(K.rot(p, 0, (i * 360) / n + u(-8, 8), 0, [0, 0, 0]), addv(st.top, [0, H * 0.012 * o.size, 0]));
    parts.push(paintStyle(p, S, mixc(petalCol, [1, 1, 1], 0.05), mixc(petalCol, [1, 1, 0.9], 0.25), pl));
  }
  parts.push(K.color(K.at(K.sphere(H * o.eye * o.size), ...addv(st.top, [0, H * 0.02 * o.size, 0])), o.center));
  if (S.name !== 'lowpoly') {
    for (let l = 0; l < 2; l++) {
      const at2 = addv(at, [0, h * (0.2 + 0.2 * l), 0]);
      const r = placedRibbon(at2, l * 180 + u(-30, 30), H * 0.35 * o.size, H * 0.09, [50, 90], 0.12);
      parts.push(paintStyle(r.shape, S, B.leaf, mixc(B.leaf, [0.7, 1, 0.4], 0.35), H * 0.2));
    }
  }
  return parts;
}

function flowerLike(B, o) {
  const n = Math.max(1, Math.min(6, Math.round(B.density)));
  const budget = Math.max(1, Math.floor(70 / (lvl(B.S, [8, 13, 17]))));
  return clump(Math.min(n, budget), B.H * 0.45, B.u).flatMap((p) => bloom(B, p, o));
}

function lavender(B) {
  const { S, u, H } = B;
  const n = Math.min(14, Math.max(2, Math.round(lvl(S, [3, 5, 8]) * B.density)));
  const parts = [];
  for (let i = 0; i < n; i++) {
    const at = addv([0, 0, 0], [u(-0.12, 0.12) * H, 0, u(-0.12, 0.12) * H]);
    const yaw = u(0, 360), lean = u(4, 22), h = H * u(0.75, 1);
    const r = placedRibbon(at, yaw, h, H * 0.025, [lean, lean + 6], 1);
    parts.push(K.color(r.shape, B.leaf));
    const dir = dirVec(yaw + 90, lean + 4);
    const spikeLen = H * u(0.2, 0.28);
    for (let k = 0; k < (S.name === 'lowpoly' ? 1 : 2); k++) {
      const c = addv(r.tip, scalev(dir, spikeLen * (0.3 + k * 0.45)));
      const e = K.rot(K.ellipsoid(H * 0.035, spikeLen * (k ? 0.32 : 0.4), H * 0.035), lean + 4, yaw + 90, 0);
      parts.push(paintStyle(K.move(e, c), S, jitter(B.accent, u, 8, S.vary, S.vary * 0.6), mixc(B.accent, [1, 0.85, 1], 0.35), spikeLen));
    }
  }
  return parts;
}

function fern(B) {
  const { S, u, H } = B;
  const n = Math.min(20, Math.round(lvl(S, [6, 9, 13]) * B.density));
  const parts = [];
  for (let i = 0; i < n; i++) {
    const yaw = (i * 360) / n + u(-14, 14);
    const tilts = S.name === 'lowpoly' ? [32, 84] : [26 + u(-4, 6), 56, 86 + u(0, 12)];
    const r = placedRibbon([0, 0, 0], yaw, H * u(0.85, 1.15), H * 0.2, tilts, 0.1);
    parts.push(paintStyle(r.shape, S, jitter(B.accent, u, 5, S.vary, S.vary * 0.6), mixc(B.accent, [0.7, 1, 0.45], 0.4), H * 0.2));
  }
  return parts;
}

function bush(B) {
  const { S, u, H } = B;
  const n = Math.min(14, Math.round(lvl(S, [4, 6, 9]) * B.density));
  const parts = [];
  for (let i = 0; i < n; i++) {
    const a = rad((i * 360) / n + u(-20, 20)), d = H * 0.42 * (i === 0 ? 0 : u(0.6, 1)), r = H * u(0.26, 0.4) * (i === 0 ? 1.15 : 1);
    let s = S.facets ? K.rot(K.box(r * 1.5, r * 1.3, r * 1.5), u(-15, 15), u(0, 90), u(-15, 15)) : K.scale(K.sphere(r), [1, 0.85, 1]);
    if (S.name === 'realistic') s = K.displace(s, r * 0.25, r * 0.7);
    const base = jitter(B.accent, u, 6, S.vary, S.vary * 0.8);
    parts.push(K.move(paintStyle(s, S, base, mixc(base, [0.75, 1, 0.45], 0.4), r), [Math.cos(a) * d, r * 0.82, Math.sin(a) * d]));
  }
  return parts;
}

function cactus(B) {
  const { S, u, H } = B;
  const r = H * 0.1, armR = H * 0.07;
  const paint = (s) => {
    const c = K.color(s, B.accent);
    if (S.name === 'realistic') return K.texture(c, 'relief', { size: H * 0.05, bump: S.bump });
    if (S.gradient) return K.texture(c, 'gradient', { color2: mixc(B.accent, [0.8, 1, 0.5], 0.3) });
    return c;
  };
  const parts = [paint(K.at(K.capsule(r, H), 0, H / 2, 0))];
  const arms = lvl(S, [1, 2, 2]);
  for (let i = 0; i < arms; i++) {
    const side = i % 2 ? -1 : 1, y = H * (0.42 + 0.14 * i) * u(0.92, 1.08), reach = r + H * u(0.16, 0.22);
    parts.push(paint(K.segment([side * r * 0.4, y, 0], [side * reach, y, 0], armR)));
    parts.push(paint(K.segment([side * reach, y, 0], [side * reach, y + H * u(0.22, 0.32), 0], armR)));
  }
  if (S.name === 'realistic') parts.push(K.color(K.at(K.sphere(H * 0.035), 0, H * 1.01, 0), [0.95, 0.4, 0.55]));
  return parts;
}

function mushroom(B) {
  const { S, u, H } = B;
  const n = Math.min(5, Math.max(1, Math.round(B.density * 1.5)));
  const parts = [];
  for (const p of clump(n, H * 0.9, u)) {
    const sz = H * u(0.6, 1.1);
    const stemS = K.color(K.taper(p, addv(p, [0, sz * 0.8, 0]), sz * 0.14, sz * 0.1), B.leaf);
    const rx = sz * 0.48, ry = sz * 0.27;
    let cap = S.facets ? K.pyramid(sz * 0.75, sz * 0.4) : K.ellipsoid(rx, ry, rx);
    cap = S.facets ? K.at(cap, 0, sz * 0.2, 0) : cap;
    const top = addv(p, [0, sz * 0.85, 0]);
    const parts2 = [K.color(cap, jitter(B.accent, u, 6, S.vary, S.vary * 0.6))];
    // manchas brancas: discos achatados sobre a superfície do chapéu
    const spots = lvl(S, [0, 4, 6]);
    for (let k = 0; k < spots; k++) {
      const th = rad(u(15, 62)), ph = rad(u(0, 360));
      const q = [rx * Math.sin(th) * Math.cos(ph), ry * Math.cos(th), rx * Math.sin(th) * Math.sin(ph)];
      const spot = K.scale(K.sphere(sz * u(0.045, 0.07)), [1, 0.35, 1]);
      parts2.push(K.color(K.move(spot, q.map((v) => v * 1.02)), [0.97, 0.95, 0.9]));
    }
    parts.push(stemS, K.move(K.group(parts2), top));
  }
  return parts;
}

export function builtins(ctx) {
  const N = (name, params, fn) => new Native(name, params, fn);
  return {
    plant: N('plant', ['kind="flower"', 'style="stylized"', 'height=None', 'color=None', 'density=1', 'seed=None'], (a) => {
      const kindName = String(a.kind).toLowerCase();
      const kind = KINDS[kindName];
      if (!kind) throw new ScriptError(`plant(): tipo desconhecido '${a.kind}'`, null, didYouMean(kindName, PLANT_KINDS) ?? `use ${PLANT_KINDS.join(', ')}`);
      const S = resolveStyle(a.style, 'plant()');
      const H = a.height === null ? kind.h : num(a.height, 'height');
      if (!(H > 0)) throw new ScriptError('plant(): height deve ser maior que zero', null);
      const density = num(a.density, 'density');
      if (!(density > 0)) throw new ScriptError('plant(): density deve ser maior que zero', null, 'density=1 é uma planta; 3 é uma touceira');
      const rng = rngFor(ctx, a.seed);
      const { u, pick } = randTools(rng);
      const accent = toSrgb(a.color ?? kind.color ?? pick(PETALS));
      const B = { S, u, H, density, accent, leaf: toSrgb(kindName === 'mushroom' ? kind.leaf : kind.leaf) };
      if (kindName === 'fern' || kindName === 'bush' || kindName === 'cactus') B.accent = toSrgb(a.color ?? kind.color);
      let parts;
      switch (kindName) {
        case 'flower': parts = flowerLike(B, { size: 1, pl: 0.1, pw: 0.045, tilt: 78, eye: 0.04, petal: accent, center: [0.95, 0.75, 0.15] }); break;
        case 'daisy': parts = flowerLike(B, { size: 0.9, pl: 0.1, pw: 0.018, tilt: 84, eye: 0.06, petals: lvl(S, [8, 12, 16]), petal: accent, center: [0.98, 0.8, 0.12] }); break;
        case 'lavender': parts = lavender(B); break;
        case 'fern': parts = fern(B); break;
        case 'bush': parts = bush(B); break;
        case 'cactus': parts = cactus(B); break;
        default: parts = mushroom(B);
      }
      return K.named(K.group(parts), `planta-${kindName}`);
    }),
  };
}
