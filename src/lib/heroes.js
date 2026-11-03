// Heróis low poly (estilo chibi, como os pacotes KayKit) e equipamento.
//
//   hero(kind="knight")  knight, barbarian, rogue, mage, ranger
//   gear(kind="sword")   sword, dagger, axe, hammer, staff, wand, bow, shield, round_shield, book, mug, quiver
//
// Tudo é feito de faces planas (box chanfrado, hull, formas com poucos lados): sai exato no GLB pela
// malha direta, com poucos triângulos, e combina com a exportação com paleta (--palette).
// O herói declara âncoras para encaixar o equipamento sem contas:
//   mao_dir, mao_esq (palma, para cima), braco_esq (antebraço, para fora), costas, cabeca (topo), cintura
// e cada peça de equipamento tem a âncora "punho" (para baixo, onde a mão segura):
//   gear("sword").attach(heroi, "mao_dir", to="punho")
import { Native, didYouMean, num } from '../runtime.js';
import { ScriptError } from '../parser.js';
import { Shape, hullShape, METHODS } from '../shapes.js';
import { ringPoints, lowSphere } from '../hull.js';
import * as K from './kit.js';

const M = (name, s, args) => METHODS[name][1](s, args);
const place = (s, x, y, z) => M('place', s, { x, y, z });
// caixa com as arestas chanfradas (box(bevel=))
const cbox = (w, h, d, c) => new Shape('cbox', { size: [w, h, d], c: Math.min(c, Math.min(w, h, d) / 2), r: 0 });
const prism = (r, h, n) => hullShape([...ringPoints(r, -h / 2, n), ...ringPoints(r, h / 2, n)]);
const lowCone = (r, h, top, n) => hullShape([...ringPoints(r, -h / 2, n), ...(top > 1e-9 ? ringPoints(top, h / 2, n) : [[0, h / 2, 0]])]);
const ball = (r, n) => hullShape(lowSphere(r, n));
const anchor = (s, name, p, n) => new Shape('translate', { v: [0, 0, 0], anchors: [{ name, p, n }] }, [s]);

const STEEL = '#c9ced6', STEEL_D = '#8d949e', LEATHER = '#7a4a2a', GOLD = '#e2b33c', DARK = '#2a2320', WOOD = '#8a5a34';
const SKINS = ['#f0c39a', '#d9a172', '#a86f47', '#6e4529'];
const HAIRS = ['#6b4423', '#2b1d14', '#d9b46a', '#a8432a'];

// ---------- heróis ----------
const KINDS = {
  knight: { main: '#3f6fb5', dark: '#2b4c80', wide: 1 },
  barbarian: { main: '#8a3a2a', dark: '#5a2a1e', wide: 1.18 },
  rogue: { main: '#3d5a3a', dark: '#263826', wide: 0.95 },
  mage: { main: '#6a4bb0', dark: '#45307a', wide: 1 },
  ranger: { main: '#4f7a3a', dark: '#6b4a2a', wide: 1 },
};
export const HERO_KINDS = Object.keys(KINDS);

function hero(kind, o) {
  const P = KINDS[kind];
  const W = P.wide;
  const main = o.color ?? P.main, dark = P.dark;
  const skin = o.skin ?? SKINS[o.variant % SKINS.length], hair = o.hair ?? HAIRS[o.variant % HAIRS.length];
  const c = (s, col) => K.color(s, col);
  const parts = [];
  const armor = kind === 'knight' ? STEEL : kind === 'barbarian' ? skin : main;
  // pernas e botas
  for (const x of [0.09, -0.09]) {
    parts.push(c(place(cbox(0.15 * W, 0.24, 0.17, 0.03), x * W, 0.12, 0), kind === 'barbarian' ? LEATHER : dark));
    parts.push(c(place(cbox(0.18 * W, 0.13, 0.24, 0.035), x * W, 0, 0.02), kind === 'mage' ? dark : LEATHER));
  }
  // tronco em trapézio (ombros largos)
  const ch = (y, hw, hd) => [[-hw, y, -hd], [hw, y, -hd], [-hw, y, hd], [hw, y, hd]];
  parts.push(c(place(hullShape([...ch(0, 0.2 * W, 0.13), ...ch(0.3, 0.25 * W, 0.15), ...ch(0.36, 0.18 * W, 0.11)]), 0, 0.4, 0), armor));
  parts.push(c(place(cbox(0.42 * W, 0.06, 0.28, 0.015), 0, 0.36, 0), LEATHER));
  parts.push(c(place(cbox(0.07, 0.06, 0.02, 0.01), 0, 0.36, 0.145), GOLD));
  if (kind === 'knight') {
    parts.push(c(place(cbox(0.3, 0.28, 0.02, 0.01), 0, 0.44, 0.15), main));
    parts.push(c(K.at(hullShape([[0, 0.08, 0], [0.06, 0, 0], [0, -0.08, 0], [-0.06, 0, 0], [0, 0, 0.02]]), 0, 0.6, 0.165), GOLD));
    parts.push(c(place(lowCone(0.23, 0.12, 0.21, 8), 0, 0.26, 0), STEEL_D));
  } else if (kind === 'mage') {
    // túnica longa até as botas
    parts.push(c(place(lowCone(0.3, 0.36, 0.2, 8), 0, 0.02, 0), main));
    parts.push(c(place(cbox(0.08, 0.3, 0.02, 0.01), 0, 0.42, 0.15), GOLD));
  } else if (kind === 'barbarian') {
    // tanga de pele e cinto largo de couro
    parts.push(c(place(lowCone(0.25 * W, 0.12, 0.22 * W, 8), 0, 0.26, 0), '#6b4a2a'));
    parts.push(c(K.at(hullShape([[-0.12, 0, 0], [0.12, 0, 0], [0, 0.1, 0], [0, 0.05, 0.03]]), 0, 0.55, 0.14), LEATHER));
  } else {
    parts.push(c(place(lowCone(0.23, 0.12, 0.21, 8), 0, 0.26, 0), dark));
  }
  // braços: ombreira, braço e luva
  for (const side of [1, -1]) {
    const x = side * 0.3 * W;
    const bare = kind === 'barbarian';
    const shoulder = kind === 'knight' ? STEEL : kind === 'barbarian' ? '#c9b48f' : kind === 'mage' ? main : dark;
    parts.push(c(K.at(K.scale(ball(0.11 * W, 6), [1, 0.75, 1]), x, 0.72, 0), shoulder));
    parts.push(c(place(cbox(0.11 * W, 0.26, 0.12, 0.025), x, 0.42, 0), bare ? skin : kind === 'knight' ? dark : main));
    parts.push(c(place(cbox(0.13 * W, 0.11, 0.13, 0.03), x, 0.33, 0), bare ? LEATHER : kind === 'mage' ? skin : LEATHER));
  }
  // cabeça (chibi: ~1/3 da altura), olhos e cabelo
  parts.push(c(place(cbox(0.38, 0.34, 0.34, 0.07), 0, 0.78, 0), skin));
  parts.push(c(K.mirror(K.at(K.box(0.04, 0.05, 0.02), 0.07, 0.86, 0.172), 'x'), DARK));
  const hullAt = (pts, x, y, z, col) => c(place(hullShape(pts), x, y, z), col);
  const dome = (y0, hw, hd, h) => [...ch(0, hw, hd), ...ch(h * 0.68, hw * 0.92, hd * 0.92), ...ch(h, hw * 0.48, hd * 0.52)];
  if (kind === 'knight' && o.helmet) {
    parts.push(hullAt(dome(0, 0.22, 0.2, 0.32), 0, 0.9, 0, STEEL));
    parts.push(c(K.at(K.box(0.3, 0.05, 0.03), 0, 0.98, 0.205), '#20242b'));
    parts.push(c(K.at(hullShape([[0, 0, -0.14], [0, 0, 0.12], [0, 0.12, -0.06], [0.02, 0.04, 0], [-0.02, 0.04, 0]]), 0, 1.21, 0), main));
  } else if (kind === 'barbarian' && o.helmet) {
    parts.push(hullAt(dome(0, 0.21, 0.19, 0.18), 0, 0.95, 0, STEEL_D));
    for (const s of [1, -1]) parts.push(c(K.at(K.rot(lowCone(0.05, 0.22, 0, 6), 0, 0, -s * 55, [0, 0, 0]), s * 0.27, 1.08, 0), '#efe6d2'));
    parts.push(c(K.at(hullShape([[-0.14, 0, 0], [0.14, 0, 0], [0, -0.16, 0.02], [0, -0.04, 0.05]]), 0, 0.74, 0.17), hair));
  } else if (kind === 'rogue') {
    // capuz: casca sobre a cabeça, aberta no rosto, e lenço cobrindo o nariz
    parts.push(hullAt([...ch(0, 0.22, 0.2), ...ch(0.2, 0.2, 0.19), ...ch(0.3, 0.1, 0.12), [0, 0.18, -0.26]], 0, 0.9, -0.025, main));
    parts.push(c(K.at(K.box(0.32, 0.07, 0.03), 0, 0.97, 0.18), main));
    parts.push(c(K.at(cbox(0.36, 0.1, 0.05, 0.02), 0, 0.71, 0.155), dark));
  } else if (kind === 'mage') {
    // chapéu pontudo com aba larga, e barba
    parts.push(c(place(prism(0.3, 0.03, 10), 0, 0.92, 0), main));
    parts.push(c(K.at(K.rot(lowCone(0.17, 0.42, 0, 8), -12, 0, 0, [0, -0.21, 0]), 0, 1.16, -0.02), main));
    parts.push(c(place(prism(0.18, 0.04, 8), 0, 0.93, 0), GOLD));
    parts.push(c(K.at(hullShape([[-0.13, 0, 0], [0.13, 0, 0], [0, -0.2, 0.04], [0, -0.02, 0.05]]), 0, 0.73, 0.17), o.hair ?? '#e8e4da'));
  } else if (kind === 'ranger') {
    // gorro com pena e capa nas costas
    parts.push(hullAt([...ch(0, 0.21, 0.19), ...ch(0.1, 0.19, 0.17), [0, 0.2, -0.12], [0, 0.16, 0.1]], 0, 0.92, 0, main));
    parts.push(c(K.at(K.rot(hullShape([[0, 0, 0], [0.02, 0.18, 0], [-0.02, 0.18, 0], [0, 0.1, 0.03]]), 0, 0, -25, [0, 0, 0]), 0.14, 1.0, -0.05), '#c8382b'));
    parts.push(c(place(cbox(0.42, 0.5, 0.03, 0.01), 0, 0.28, -0.17), dark));
  }
  if (kind !== 'rogue' && !(kind === 'knight' && o.helmet) && kind !== 'ranger' && kind !== 'mage' && !(kind === 'barbarian' && o.helmet)) {
    parts.push(hullAt(dome(0, 0.2, 0.18, 0.12), 0, 0.92, -0.01, hair));
  }
  let body = K.named(K.group(parts), `heroi-${kind}`);
  // âncoras de encaixe (em coordenadas do herói)
  const hx = 0.3 * W;
  body = anchor(body, 'mao_dir', [hx, 0.33, 0.04], [0, 1, 0]);
  body = anchor(body, 'mao_esq', [-hx, 0.33, 0.04], [0, 1, 0]);
  body = anchor(body, 'braco_esq', [-hx - 0.06 * W, 0.42, 0], [-1, 0, 0]);
  body = anchor(body, 'costas', [0, 0.55, -0.16], [0, 0, -1]);
  body = anchor(body, 'cabeca', [0, kind === 'mage' ? 1.37 : 1.1, 0], [0, 1, 0]);
  body = anchor(body, 'cintura', [0.2 * W, 0.36, 0.06], [1, 0, 0]);
  return body;
}

// ---------- equipamento (em pé no eixo y, punho na origem) ----------
function gear(kind, o) {
  const metal = o.color ?? STEEL;
  const c = (s, col) => K.color(s, col);
  const blade = (w, t, len, tip) => hullShape([[w, 0, 0], [-w, 0, 0], [0, 0, t], [0, 0, -t], [w * 0.85, len, 0], [-w * 0.85, len, 0], [0, len, t * 0.8], [0, len, -t * 0.8], [0, len + tip, 0]]);
  let parts, grip = [0, 0, 0];
  switch (kind) {
    case 'sword':
      parts = [c(K.at(blade(0.035, 0.012, 0.5, 0.08), 0, 0.075, 0), metal), c(K.at(cbox(0.18, 0.035, 0.05, 0.012), 0, 0.06, 0), GOLD),
        c(prism(0.018, 0.12, 6), LEATHER), c(K.at(ball(0.028, 6), 0, -0.07, 0), GOLD)];
      break;
    case 'dagger':
      parts = [c(K.at(blade(0.025, 0.009, 0.2, 0.05), 0, 0.055, 0), metal), c(K.at(cbox(0.1, 0.025, 0.035, 0.008), 0, 0.045, 0), GOLD), c(prism(0.014, 0.08, 6), LEATHER)];
      break;
    case 'axe':
      parts = [c(K.at(prism(0.02, 0.6, 6), 0, 0.22, 0), WOOD),
        c(K.at(hullShape([[0, -0.07, 0.012], [0, 0.07, 0.012], [0, -0.07, -0.012], [0, 0.07, -0.012], [0.16, -0.12, 0.004], [0.16, 0.12, 0.004], [0.16, -0.12, -0.004], [0.16, 0.12, -0.004], [0.19, 0, 0]]), 0.01, 0.43, 0), metal)];
      break;
    case 'hammer':
      parts = [c(K.at(prism(0.02, 0.5, 6), 0, 0.17, 0), WOOD), c(K.at(cbox(0.2, 0.11, 0.11, 0.025), 0, 0.44, 0), metal), c(K.at(cbox(0.06, 0.13, 0.13, 0.02), 0, 0.44, 0), GOLD)];
      break;
    case 'staff':
      parts = [c(K.at(prism(0.022, 1.1, 6), 0, 0.25, 0), WOOD), c(K.at(K.rot(lowCone(0.05, 0.12, 0.02, 6), 180, 0, 0, [0, 0, 0]), 0, 0.82, 0), WOOD),
        K.material(K.color(K.at(ball(0.06, 6), 0, 0.89, 0), o.color ?? '#5ad1e6'), { glow: 0.8 })];
      break;
    case 'wand':
      parts = [c(K.at(lowCone(0.016, 0.32, 0.009, 6), 0, 0.08, 0), WOOD), K.material(K.color(K.at(ball(0.025, 6), 0, 0.25, 0), o.color ?? '#f2c53d'), { glow: 0.8 })];
      break;
    case 'bow': {
      // arco em gomos (casco por trecho) e a corda reta
      const arcPts = [];
      for (let i = 0; i <= 6; i++) { const a = ((i / 6) - 0.5) * 2.2; arcPts.push([0, Math.sin(a) * 0.4, Math.cos(a) * 0.18 - 0.12]); }
      parts = [];
      for (let i = 0; i < 6; i++) parts.push(c(K.segment(arcPts[i], arcPts[i + 1], 0.016), WOOD));
      parts.push(c(K.segment(arcPts[0], arcPts[6], 0.004), '#efe6d2'), c(K.at(cbox(0.04, 0.09, 0.04, 0.01), 0, 0, 0.06), LEATHER));
      grip = [0, 0, 0.06];
      break;
    }
    case 'shield':
      parts = [c(hullShape([[-0.2, 0.22, 0], [0.2, 0.22, 0], [-0.2, 0.22, 0.04], [0.2, 0.22, 0.04], [-0.18, -0.08, 0], [0.18, -0.08, 0], [-0.18, -0.08, 0.04], [0.18, -0.08, 0.04], [0, -0.3, 0], [0, -0.3, 0.04]]), o.color ?? '#3f6fb5'),
        c(K.at(hullShape([[0, 0.1, 0], [0.07, 0, 0], [0, -0.1, 0], [-0.07, 0, 0], [0, 0, 0.03]]), 0, 0, 0.04), GOLD)];
      grip = [0, 0, 0];
      break;
    case 'round_shield':
      parts = [c(K.rot(prism(0.2, 0.04, 8), 90, 0, 0, [0, 0, 0]), o.color ?? WOOD), c(K.at(K.rot(prism(0.215, 0.03, 8), 90, 0, 0, [0, 0, 0]), 0, 0, -0.008), STEEL_D),
        c(K.at(ball(0.06, 6), 0, 0, 0.02), GOLD)];
      break;
    case 'book':
      parts = [c(cbox(0.16, 0.22, 0.05, 0.01), o.color ?? '#8a3a2a'), c(K.at(K.box(0.15, 0.2, 0.04), 0.008, 0, 0), '#efe6d2'), c(K.at(cbox(0.05, 0.05, 0.01, 0.005), 0, 0.03, 0.026), GOLD)];
      break;
    case 'mug':
      parts = [c(prism(0.05, 0.11, 8), WOOD), c(K.at(prism(0.052, 0.015, 8), 0, 0.03, 0), STEEL_D), c(K.at(prism(0.044, 0.01, 8), 0, 0.055, 0), '#f2e2b0'),
        c(K.at(cbox(0.03, 0.07, 0.02, 0.008), 0.065, 0, 0), WOOD)];
      break;
    case 'quiver': {
      parts = [c(lowCone(0.06, 0.34, 0.07, 6), LEATHER), c(K.at(prism(0.072, 0.03, 6), 0, 0.15, 0), STEEL_D)];
      for (const [x, z] of [[0.02, 0.01], [-0.02, 0.02], [0, -0.02]]) {
        parts.push(c(K.segment([x, 0.15, z], [x, 0.3, z], 0.005), WOOD), c(K.at(hullShape([[x, 0.3, z - 0.02], [x, 0.3, z + 0.02], [x, 0.36, z], [x + 0.003, 0.32, z], [x - 0.003, 0.32, z]]), 0, 0, 0), '#c8382b'));
      }
      grip = [0, 0, -0.065];
      break;
    }
  }
  let s = K.named(K.group(parts), `equip-${kind}`);
  return anchor(s, 'punho', grip, [0, -1, 0]);
}
export const GEAR_KINDS = ['sword', 'dagger', 'axe', 'hammer', 'staff', 'wand', 'bow', 'shield', 'round_shield', 'book', 'mug', 'quiver'];

const pick = (what, v, list) => {
  const k = String(v).toLowerCase();
  if (!list.includes(k)) throw new ScriptError(`${what}: tipo desconhecido '${v}'`, null, didYouMean(k, list) ?? `use ${list.join(', ')}`);
  return k;
};
const colorArg = (v) => (v === null ? null : v);

export function builtins() {
  return {
    hero: new Native('hero', ['kind="knight"', 'color=None', 'skin=None', 'hair=None', 'helmet=True', 'variant=0'], (a) => {
      const kind = pick('hero()', a.kind, HERO_KINDS);
      const variant = num(a.variant, 'variant');
      if (!Number.isInteger(variant) || variant < 0) throw new ScriptError('hero(): variant deve ser um inteiro >= 0', null);
      return hero(kind, { color: colorArg(a.color), skin: colorArg(a.skin), hair: colorArg(a.hair), helmet: !!a.helmet, variant });
    }),
    gear: new Native('gear', ['kind="sword"', 'color=None'], (a) => gear(pick('gear()', a.kind, GEAR_KINDS), { color: colorArg(a.color) })),
  };
}
