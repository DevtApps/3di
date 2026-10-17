// Gerador de árvores: tree(kind=..., style=...).
//
//   kind  = que árvore é   (oak, pine, birch, palm, willow, dead, round, bonsai)
//   style = como é desenhada (lowpoly, stylized, realistic)
//
// Troncos e galhos são troncos de cone afinando (kit.taper); copas são blocos (esferas achatadas,
// cubos girados no lowpoly) agrupados nas pontas dos galhos. O estilo muda a geometria: lowpoly é
// facetado e de cor chapada; stylized tem degradê; realistic tem mais galhos, copas rugosas
// (displace), manchas de cor e relevo na casca.
import { Native, didYouMean, num } from '../runtime.js';
import { ScriptError } from '../parser.js';
import { toSrgb } from '../color.js';
import * as K from './kit.js';
import { resolveStyle } from './style.js';
import { randTools, rngFor } from './rand.js';
import { mixc, jitter, addv, scalev, dirVec, placedRibbon, paintStyle } from './util.js';

const KINDS = {
  oak:    { h: 5,   trunk: '#6b4a2b', leaves: '#3a7d2c', top: '#86c64a', info: 'carvalho: copa larga e redonda' },
  pine:   { h: 6,   trunk: '#5a3e24', leaves: '#1f5a34', top: '#4f9a5a', info: 'pinheiro: camadas de folhas em cone' },
  birch:  { h: 5,   trunk: '#e8e4da', leaves: '#6fa83a', top: '#c3e06a', info: 'bétula: tronco branco e copa fina' },
  palm:   { h: 6,   trunk: '#8a6a42', leaves: '#2f8a3a', top: '#8fd25a', info: 'palmeira: tronco curvo e frondes' },
  willow: { h: 5.5, trunk: '#5e4a30', leaves: '#5a9a3a', top: '#b4d86a', info: 'salgueiro: ramos que pendem' },
  dead:   { h: 4,   trunk: '#4a3b2e', leaves: '#000000', top: '#000000', info: 'árvore seca, só galhos' },
  round:  { h: 3,   trunk: '#6b4a2b', leaves: '#3f9a3a', top: '#9be05a', info: 'árvore de pirulito: tronco fino e copa redonda' },
  bonsai: { h: 0.5, trunk: '#5b3f2a', leaves: '#2f7a3a', top: '#7cc14a', info: 'bonsai num vaso' },
};
export const TREE_KINDS = Object.keys(KINDS);

// parâmetros de copa dos tipos "folhosos" (carvalho, bétula, salgueiro, pirulito)
const BROADLEAF = {
  oak:    { trunkH: 0.4,  trunkR: 0.05,  nb: [3, 4, 6], tilt: [38, 62], len: [0.22, 0.32], blobR: [0.17, 0.23], crown: 0.27, lift: 0.14, squash: 0.82 },
  birch:  { trunkH: 0.55, trunkR: 0.026, nb: [3, 4, 5], tilt: [14, 34], len: [0.18, 0.27], blobR: [0.1, 0.14],  crown: 0.15, lift: 0.1,  squash: 1.15 },
  willow: { trunkH: 0.42, trunkR: 0.06,  nb: [3, 4, 5], tilt: [50, 75], len: [0.2, 0.3],   blobR: [0.16, 0.21], crown: 0.24, lift: 0.1,  squash: 0.8, strands: [6, 10, 14] },
  round:  { trunkH: 0.5,  trunkR: 0.035, nb: [0, 0, 2], tilt: [30, 50], len: [0.1, 0.16],  blobR: [0.12, 0.16], crown: 0.3,  lift: 0.18, squash: 0.95 },
};

const lvl = (S, a) => a[S.name === 'lowpoly' ? 0 : S.name === 'stylized' ? 1 : 2];

// Bloco de copa: esfera achatada (stylized/realistic) ou cubo girado (lowpoly, facetado).
function blob(B, pos, r, squash = 0.85) {
  const { S, u } = B;
  let s;
  if (S.facets) s = K.rot(K.box(r * 1.55, r * 1.35 * squash, r * 1.55), u(-18, 18), u(0, 90), u(-18, 18));
  else s = K.scale(K.sphere(r), [1, squash, 1]);
  if (S.name === 'realistic') s = K.displace(s, r * 0.26, r * 0.75);
  const base = jitter(B.leaf, u, 6, S.vary, S.vary * 0.8);
  const tip = jitter(B.leafTop, u, 8, S.vary, S.vary * 0.8);
  return K.move(paintStyle(s, S, base, tip, r * 0.9), pos);
}

// Casca: cor chapada (lowpoly), degradê (stylized) ou veios com relevo (realistic); bétula tem marcas escuras.
function bark(B, shape, birch = false) {
  const { S, H } = B;
  const c = K.color(shape, B.trunk);
  if (birch && S.name !== 'lowpoly') return K.texture(c, 'stripes', { color2: [0.16, 0.14, 0.13], size: H * 0.045, axis: 'y', bump: S.bump * 0.5 });
  if (S.name === 'realistic') return K.texture(c, 'wood', { color2: mixc(B.trunk, [0, 0, 0], 0.55), size: H * 0.012, axis: 'y', bump: S.bump });
  if (S.gradient) return K.texture(c, 'gradient', { color2: mixc(B.trunk, [1, 0.95, 0.85], 0.2) });
  return c;
}

// Tronco: cadeia de troncos de cone com uma leve curvatura. Devolve { parts, top }.
function trunkChain(B, pieces, height, r0, r1, bend) {
  const { u } = B;
  const parts = [];
  let pos = [0, 0, 0];
  const yaw = u(0, 360);
  for (let k = 0; k < pieces; k++) {
    const next = addv(pos, scalev(dirVec(yaw + k * 70, bend * (k + 1)), height / pieces));
    parts.push(K.taper(pos, next, r0 + (r1 - r0) * (k / pieces), r0 + (r1 - r0) * ((k + 1) / pieces)));
    pos = next;
  }
  return { parts, top: pos };
}

function broadleaf(B, P, kind) {
  const { S, u, H } = B;
  const pieces = lvl(S, [1, 2, 3]);
  const nb = lvl(S, P.nb);
  const tH = H * P.trunkH, r0 = H * P.trunkR;
  const tr = trunkChain(B, pieces, tH, r0, r0 * 0.6, u(2, 7) * (S.name === 'lowpoly' ? 0.5 : 1));
  const top = tr.top;
  const wood = [bark(B, K.group(tr.parts), kind === 'birch')];
  const leaves = [];
  const branches = [];
  for (let i = 0; i < nb; i++) {
    const yaw = (i * 360) / nb + u(-25, 25), tilt = u(P.tilt[0], P.tilt[1]), len = H * u(P.len[0], P.len[1]);
    const from = addv(top, [0, -tH * u(0, 0.15), 0]);
    const to = addv(from, scalev(dirVec(yaw, tilt), len));
    branches.push(K.taper(from, to, r0 * 0.5, r0 * 0.2));
    leaves.push(blob(B, addv(to, [0, H * 0.03, 0]), H * u(P.blobR[0], P.blobR[1]), P.squash));
    if (S.name === 'realistic') leaves.push(blob(B, addv(to, scalev(dirVec(yaw + u(-60, 60), tilt + 25), len * 0.4)), H * P.blobR[0] * 0.65, P.squash));
  }
  if (branches.length) wood.push(K.color(K.group(branches), mixc(B.trunk, [0, 0, 0], 0.15)));
  leaves.push(blob(B, addv(top, [0, H * P.lift, 0]), H * P.crown, P.squash));
  if (P.strands) {
    // salgueiro: ramos que pendem do contorno da copa
    const n = lvl(S, P.strands), rim = H * 0.2, y0 = top[1] + H * P.lift * 0.8;
    for (let i = 0; i < n; i++) {
      const yaw = (i * 360) / n + u(-14, 14);
      const at = addv(top, [Math.cos((yaw * Math.PI) / 180) * rim, y0 - top[1], Math.sin((yaw * Math.PI) / 180) * rim]);
      const r = placedRibbon(at, yaw + 90, H * u(0.3, 0.42), H * 0.035, [168, 176], 0.25);
      leaves.push(paintStyle(r.shape, S, jitter(B.leaf, u, 6, S.vary, S.vary), B.leafTop, H * 0.2));
    }
  }
  return [...wood, ...leaves];
}

function pine(B) {
  const { S, u, H } = B;
  const n = lvl(S, [4, 6, 8]);
  const parts = [K.color(K.taper([0, 0, 0], [0, H * 0.9, 0], H * 0.03, H * 0.008), B.trunk)];
  for (let i = 0; i < n; i++) {
    const t = n === 1 ? 0 : i / (n - 1);
    const r = H * 0.23 * (1 - 0.82 * t), hh = H * 0.3 * (1 - 0.25 * t), y0 = H * 0.16 + t * H * 0.7;
    let tier;
    if (S.facets) tier = K.rot(K.at(K.pyramid(r * 2, hh), 0, y0 + hh / 2, 0), 0, u(0, 90), 0, [0, y0, 0]);
    else tier = K.at(K.cone(r, hh), 0, y0 + hh / 2, 0);
    if (S.name === 'realistic') tier = K.displace(tier, r * 0.13, r * 0.5);
    const base = jitter(mixc(B.leaf, B.leafTop, t * 0.5), u, 4, S.vary, S.vary * 0.7);
    parts.push(paintStyle(tier, S, base, mixc(base, B.leafTop, 0.45), r * 0.7));
  }
  return parts;
}

function palm(B) {
  const { S, u, H } = B;
  const pieces = lvl(S, [2, 3, 4]);
  const tr = trunkChain(B, pieces, H * 0.78, H * 0.035, H * 0.022, 6);
  let trunk = K.color(K.group(tr.parts), B.trunk);
  if (S.name !== 'lowpoly') trunk = K.texture(trunk, 'stripes', { color2: mixc(B.trunk, [0, 0, 0], 0.4), size: H * 0.035, axis: 'y', bump: S.bump * 0.6 });
  const parts = [trunk];
  const n = lvl(S, [5, 7, 10]);
  for (let i = 0; i < n; i++) {
    const yaw = (i * 360) / n + u(-14, 14);
    const tilts = S.name === 'lowpoly' ? [70, 118] : [48 + u(-8, 8), 82, 112 + u(0, 14)];
    const r = placedRibbon(tr.top, yaw, H * u(0.46, 0.58), H * 0.11, tilts, 0.14);
    parts.push(paintStyle(r.shape, S, jitter(B.leaf, u, 5, S.vary, S.vary * 0.6), B.leafTop, H * 0.2));
  }
  for (let i = 0; i < 3; i++) parts.push(K.color(K.at(K.sphere(H * 0.028), ...addv(tr.top, [u(-0.12, 0.12) * H * 0.4, -H * 0.03, u(-0.12, 0.12) * H * 0.4])), [0.42, 0.28, 0.12]));
  return parts;
}

// Árvore seca: ramificação recursiva (o tronco abre em 3, os galhos em 2).
function dead(B) {
  const { S, u, H } = B;
  const depth = lvl(S, [2, 3, 3]);
  const out = [];
  const grow = (pos, yaw, tilt, len, r, d) => {
    const to = addv(pos, scalev(dirVec(yaw, tilt), len));
    out.push(K.taper(pos, to, r, r * 0.62));
    if (d === 0) return;
    const kids = d === depth ? 3 : 2;
    for (let k = 0; k < kids; k++) grow(to, yaw + (k * 360) / kids + u(-40, 40), Math.min(85, tilt + u(18, 40)), len * u(0.6, 0.78), r * 0.6, d - 1);
  };
  grow([0, 0, 0], u(0, 360), 3, H * 0.4, H * 0.05, depth);
  return [bark(B, K.group(out))];
}

function bonsai(B) {
  const { S, u, H } = B;
  const pot = K.color(K.at(K.box(H * 0.55, H * 0.2, H * 0.4, H * 0.02), 0, H * 0.1, 0), [0.55, 0.3, 0.2]);
  const soil = K.color(K.at(K.box(H * 0.5, H * 0.02, H * 0.35), 0, H * 0.205, 0), [0.2, 0.13, 0.09]);
  const base = [0, H * 0.2, 0];
  const parts = [pot, soil];
  const tr = [];
  let pos = base;
  const n = lvl(S, [2, 3, 3]);
  for (let k = 0; k < n; k++) {
    const next = addv(pos, scalev(dirVec(k % 2 ? 40 : 220, 22 + k * 6), H * 0.55 / n));
    tr.push(K.taper(pos, next, H * 0.04 * (1 - k * 0.2), H * 0.04 * (1 - (k + 1) * 0.2)));
    pos = next;
  }
  parts.push(bark(B, K.group(tr)));
  const discs = lvl(S, [2, 3, 3]);
  for (let i = 0; i < discs; i++) {
    const c = addv(pos, [(i % 2 ? 1 : -1) * H * 0.18 * (i > 0 ? 1 : 0), -H * 0.12 * i, u(-0.04, 0.04) * H]);
    parts.push(blob(B, c, H * (i === 0 ? 0.24 : 0.19), 0.5));
  }
  return parts;
}

export function builtins(ctx) {
  const N = (name, params, fn) => new Native(name, params, fn);
  return {
    tree: N('tree', ['kind="oak"', 'style="stylized"', 'height=None', 'trunk=None', 'leaves=None', 'seed=None'], (a) => {
      const kindName = String(a.kind).toLowerCase();
      const kind = KINDS[kindName];
      if (!kind) throw new ScriptError(`tree(): tipo desconhecido '${a.kind}'`, null, didYouMean(kindName, TREE_KINDS) ?? `use ${TREE_KINDS.join(', ')}`);
      const S = resolveStyle(a.style, 'tree()');
      const H = a.height === null ? kind.h : num(a.height, 'height');
      if (!(H > 0)) throw new ScriptError('tree(): height deve ser maior que zero', null);
      const rng = rngFor(ctx, a.seed);
      const { u } = randTools(rng);
      const leaf = toSrgb(a.leaves ?? kind.leaves);
      const B = {
        S, u, H,
        trunk: toSrgb(a.trunk ?? kind.trunk),
        leaf,
        leafTop: a.leaves === null ? toSrgb(kind.top) : mixc(leaf, [0.95, 1, 0.5], 0.45),
      };
      let parts;
      if (kindName === 'pine') parts = pine(B);
      else if (kindName === 'palm') parts = palm(B);
      else if (kindName === 'dead') parts = dead(B);
      else if (kindName === 'bonsai') parts = bonsai(B);
      else parts = broadleaf(B, BROADLEAF[kindName], kindName);
      return K.named(K.group(parts), `arvore-${kindName}`);
    }),
  };
}
