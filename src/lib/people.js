// Gerador de pessoas: person(style, height, build, skin, hair, outfit, pose, seed).
//
// O corpo é montado por cinemática direta: cada braço e perna tem duas juntas (ombro/quadril e
// cotovelo/joelho) com ângulos de balanço (alpha, para a frente) e abertura (beta, para o lado).
// A pose define esses ângulos; o estilo define a geometria de cada peça; a roupa só decide a cor
// de cada trecho do corpo (camisa, calça, sapato), então vestir não custa primitivas extras.
//
//   style  lowpoly = peças em caixa, cores chapadas · stylized = formas lisas (como boneco.3di)
//          realistic = juntas, pescoço, orelhas, nariz, mãos e sapatos com sola, tecido com relevo
//   build  slim, average, stocky, child, elder
//   pose   stand, walk, sit, arms_up
//   hair   short, long, bald, ponytail, curly, bun
//   outfit casual, suit, sport, dress, uniform
import { Native, didYouMean, num } from '../runtime.js';
import { ScriptError } from '../parser.js';
import { toSrgb } from '../color.js';
import * as K from './kit.js';
import { resolveStyle } from './style.js';
import { randTools, rngFor } from './rand.js';
import { mixc, jitter, addv, scalev, rad, boxSeg, limbDir } from './util.js';

// frações da altura: legL = altura do quadril, torso = quadril -> ombro, neck, head = altura da cabeça
const BUILDS = {
  average: { legL: 0.52, torso: 0.3,  neck: 0.04, head: 0.14, sh: 0.125, chest: 1,    hip: 1,    limb: 1,    belly: 0,    lean: 0 },
  slim:    { legL: 0.53, torso: 0.3,  neck: 0.045, head: 0.125, sh: 0.11, chest: 0.85, hip: 0.85, limb: 0.8,  belly: 0,    lean: 0 },
  stocky:  { legL: 0.5,  torso: 0.3,  neck: 0.03, head: 0.17, sh: 0.15,  chest: 1.25, hip: 1.2,  limb: 1.3,  belly: 0.03, lean: 0 },
  child:   { legL: 0.44, torso: 0.3,  neck: 0.03, head: 0.23, sh: 0.11,  chest: 0.95, hip: 0.95, limb: 0.9,  belly: 0.015, lean: 0 },
  elder:   { legL: 0.51, torso: 0.3,  neck: 0.04, head: 0.15, sh: 0.12,  chest: 1,    hip: 1,    limb: 0.95, belly: 0.015, lean: 9 },
};
export const PERSON_BUILDS = Object.keys(BUILDS);
export const PERSON_POSES = ['stand', 'walk', 'sit', 'arms_up'];
export const PERSON_HAIRS = ['short', 'long', 'bald', 'ponytail', 'curly', 'bun'];
export const PERSON_OUTFITS = ['casual', 'suit', 'sport', 'dress', 'uniform'];

const SKINS = ['#f1c9a5', '#e0ac86', '#c68b5c', '#a5683c', '#7a4a2a', '#52331f'];
const HAIRS = ['#1a1410', '#3b2415', '#6b4423', '#b8864b', '#d9b46a', '#8a3a1e'];
const SHIRTS = ['#d94f4f', '#3f7fd0', '#e8c43a', '#4fb06a', '#e8e8e2', '#8a5cc8', '#e0803a', '#2f2f35'];
const PANTS = ['#2f4a7a', '#3b3b44', '#6b5a3a', '#4a5a3a', '#7a7a80'];
const lvl = (S, a) => a[S.name === 'lowpoly' ? 0 : S.name === 'stylized' ? 1 : 2];

// ângulos de cada pose (graus): braço = [alpha, beta, dobra do cotovelo], perna = [alpha, beta, dobra do joelho]
const POSES = {
  stand:   { armL: [4, 9, 8],    armR: [4, 9, 8],    legL: [0, 3, 0],   legR: [0, 3, 0],   sit: false },
  walk:    { armL: [-28, 6, 10], armR: [30, 6, 30],  legL: [26, 2, 6],  legR: [-24, 2, 30], sit: false },
  sit:     { armL: [28, 6, 70],  armR: [28, 6, 70],  legL: [88, 6, 0],  legR: [88, 6, 0],   sit: true },
  arms_up: { armL: [172, 14, 8], armR: [172, 14, 8], legL: [0, 4, 0],   legR: [0, 4, 0],   sit: false },
};

export function builtins(ctx) {
  const N = (name, params, fn) => new Native(name, params, fn);
  const pickOf = (what, value, list) => {
    const v = String(value).toLowerCase();
    if (!list.includes(v)) throw new ScriptError(`person(): ${what} desconhecido '${value}'`, null, didYouMean(v, list) ?? `use ${list.join(', ')}`);
    return v;
  };
  return {
    person: N('person', ['style="stylized"', 'height=None', 'build="average"', 'skin=None', 'hair=None', 'outfit="casual"', 'pose="stand"', 'seed=None'], (a) => {
      const S = resolveStyle(a.style, 'person()');
      const buildName = pickOf('build', a.build, PERSON_BUILDS);
      // altura padrão por tipo: adulto 1,75 m, idoso 1,65 m, criança 1,1 m
      const H = a.height === null ? { child: 1.1, elder: 1.65 }[buildName] ?? 1.75 : num(a.height, 'height');
      if (!(H > 0)) throw new ScriptError('person(): height deve ser maior que zero', null);
      const outfit = pickOf('outfit', a.outfit, PERSON_OUTFITS);
      const poseName = pickOf('pose', a.pose, PERSON_POSES);
      const hairName = a.hair === null ? null : pickOf('hair', a.hair, PERSON_HAIRS);
      const rng = rngFor(ctx, a.seed);
      const { u, pick } = randTools(rng);
      const Bd = BUILDS[buildName];
      const pose = POSES[poseName];

      // ---------- cores ----------
      const skin = toSrgb(a.skin ?? pick(SKINS));
      const hairCol = toSrgb(buildName === 'elder' && a.hair === null ? '#cfcfcf' : pick(HAIRS));
      const hairStyle = hairName ?? (buildName === 'child' ? pick(['short', 'ponytail', 'curly']) : pick(['short', 'long', 'bald', 'ponytail', 'curly', 'bun']));
      const shirt = toSrgb(outfit === 'suit' ? pick(['#2a2f45', '#3a3a40', '#4a4036']) : outfit === 'uniform' ? '#8fb4d8' : pick(SHIRTS));
      const pants = toSrgb(outfit === 'suit' ? shirt.map((c) => c) : outfit === 'uniform' ? '#2a3350' : outfit === 'sport' ? pick(['#2a2f45', '#d94f4f', '#2f2f35']) : pick(PANTS));
      const shoes = toSrgb(outfit === 'suit' ? '#1a1612' : pick(['#f0f0ec', '#2f2f35', '#8a4a2a', '#d94f4f']));
      const sleeveLong = outfit === 'suit' || (outfit === 'casual' && u() < 0.4);
      const sleeveless = outfit === 'dress';
      const shortsOnly = outfit === 'sport';

      // ---------- dimensões (m), já na altura pedida ----------
      const Hh = H;
      const legL = Bd.legL * Hh, torso = Bd.torso * Hh, neckL = Bd.neck * Hh, headH = Bd.head * Hh;
      const shHalf = Bd.sh * Hh * (outfit === 'suit' ? 1.05 : 1);
      const ankle = 0.04 * Hh;
      const Lt = (legL - ankle) / 2, Ls = Lt;
      const Lu = 0.165 * Hh * (buildName === 'child' ? 0.85 : 1), Lf = 0.15 * Hh * (buildName === 'child' ? 0.85 : 1);
      const rU = 0.03 * Hh * Bd.limb, rF = 0.023 * Hh * Bd.limb, rW = 0.016 * Hh * Bd.limb;
      const rT = 0.052 * Hh * Bd.limb, rK = 0.036 * Hh * Bd.limb, rA = 0.024 * Hh * Bd.limb;
      const hipX = 0.055 * Hh * Bd.hip;
      const pelvisY = pose.sit ? ankle + Ls : legL;
      const shoulderY = pelvisY + torso;
      const headCy = shoulderY + neckL + headH / 2;
      const ry = headH / 2, rx = ry * 0.82, rz = ry * 0.9;

      // ---------- peças ----------
      const lowpoly = S.facets, real = S.name === 'realistic';
      const cloth = (shape, col) => {
        const c = K.color(shape, col);
        // tecido: no realista, manchas finas e relevo; senão, cor chapada
        return real ? K.texture(c, 'mottle', { color2: mixc(col, [0, 0, 0], 0.18), size: Hh * 0.09, bump: S.bump * 0.12 }) : c;
      };
      const skinned = (shape) => (real ? K.texture(K.color(shape, skin), 'mottle', { color2: mixc(skin, [0.8, 0.3, 0.3], 0.2), size: Hh * 0.05, bump: 0.05 }) : K.color(shape, skin));
      const limbSeg = (from, to, r0, r1, paint) => paint(lowpoly ? boxSeg(from, to, (r0 + r1) * 1.15, (r0 + r1) * 1.0) : K.taper(from, to, r0, r1));
      const blob = (rr, p, paint) => paint(K.at(lowpoly ? K.box(rr[0] * 1.6, rr[1] * 1.6, rr[2] * 1.6) : K.ellipsoid(rr[0], rr[1], rr[2]), ...p));

      const parts = { head: [], torso: [], armL: [], armR: [], legL: [], legR: [] };
      const sk = (s) => skinned(s);

      // pernas
      const feetY = [];
      for (const side of [1, -1]) {
        const name = side === 1 ? 'legL' : 'legR';
        const [al, be, bend] = side === 1 ? pose.legL : pose.legR;
        const hip = [side * hipX, pelvisY, 0];
        const knee = addv(hip, scalev(limbDir(al, be, side), Lt));
        const ank = addv(knee, scalev(limbDir(al - bend, be * 0.4, side), Ls));
        const thighPaint = shortsOnly ? (s) => cloth(s, pants) : (s) => (outfit === 'dress' ? sk(s) : cloth(s, pants));
        const shinPaint = shortsOnly || outfit === 'dress' ? sk : (s) => cloth(s, pants);
        parts[name].push(limbSeg(hip, knee, rT, rK, thighPaint), limbSeg(knee, ank, rK, rA, shinPaint));
        if (real && !lowpoly) parts[name].push(K.color(K.at(K.sphere(rK * 1.02), ...knee), outfit === 'dress' || shortsOnly ? skin : pants));
        // pé: caixa/elipsoide a partir do tornozelo para a frente
        const fl = 0.07 * Hh * Bd.limb;
        const footC = addv(ank, [0, -0.018 * Hh, fl * 0.55]);
        if (lowpoly) parts[name].push(K.color(K.at(K.box(rA * 2.2, 0.04 * Hh, fl * 2), ...footC), shoes));
        else if (real) {
          parts[name].push(K.color(K.at(K.box(rA * 2.3, 0.032 * Hh, fl * 2.1, 0.012 * Hh), ...footC), shoes));
          parts[name].push(K.color(K.at(K.box(rA * 2.4, 0.008 * Hh, fl * 2.15), footC[0], footC[1] - 0.02 * Hh, footC[2]), [0.12, 0.1, 0.09]));
        } else parts[name].push(K.color(K.at(K.ellipsoid(rA * 1.3, 0.024 * Hh, fl), ...footC), shoes));
        feetY.push(footC[1]);
      }

      // tronco
      const bw = Bd.chest;
      const dressC = outfit === 'dress' ? shirt : null;
      const torsoPaint = (s) => cloth(s, shirt);
      const chestC = [0, pelvisY + torso * 0.66, 0], waistC = [0, pelvisY + torso * 0.3, 0], pelvC = [0, pelvisY + 0.01 * Hh, 0];
      // tronco em blocos arredondados (caixa lowpoly): peito, cintura e quadril
      const block = (w, h, d, c, paint, round) => paint(K.at(K.box(w, h, d, lowpoly ? 0 : round), ...c));
      parts.torso.push(block(shHalf * 2 * bw * 0.96, torso * 0.62, 0.15 * Hh * bw, chestC, torsoPaint, 0.045 * Hh));
      parts.torso.push(block(0.19 * Hh * bw * (1 + Bd.belly * 2), torso * 0.52, 0.125 * Hh * (1 + Bd.belly * 6), waistC, torsoPaint, 0.04 * Hh));
      parts.torso.push(blob([0.105 * Hh * Bd.hip, 0.06 * Hh, 0.072 * Hh], pelvC, (s) => (dressC ? cloth(s, shirt) : cloth(s, pants))));
      if (outfit === 'dress') {
        const hem = pelvisY - Lt * 0.9;
        parts.torso.push(K.color(K.at(lowpoly ? K.pyramid(0.34 * Hh, pelvisY - hem + 0.05 * Hh) : K.cone(0.19 * Hh, pelvisY - hem + 0.05 * Hh, 0.085 * Hh), 0, (pelvisY + hem) / 2 + 0.025 * Hh, 0), shirt));
      }
      if (outfit === 'suit' && !lowpoly) parts.torso.push(K.color(K.at(K.ellipsoid(0.012 * Hh, 0.09 * Hh, 0.01 * Hh), 0, chestC[1] - 0.03 * Hh, 0.078 * Hh * bw), [0.75, 0.15, 0.2]));
      if (outfit === 'uniform' && !lowpoly) parts.torso.push(K.color(K.at(K.box(0.2 * Hh * Bd.hip, 0.018 * Hh, 0.15 * Hh), 0, pelvisY + 0.045 * Hh, 0), [0.15, 0.13, 0.12]));

      // pescoço e cabeça
      parts.head.push(limbSeg([0, shoulderY - 0.02 * Hh, 0], [0, shoulderY + neckL + 0.01 * Hh, 0], 0.03 * Hh * Bd.limb, 0.027 * Hh * Bd.limb, sk));
      const headShape = lowpoly ? K.box(rx * 2, ry * 2, rz * 2.1) : K.ellipsoid(rx, ry, rz);
      parts.head.push(sk(K.at(headShape, 0, headCy, 0)));
      // z da superfície da frente do rosto em (x, y): na caixa (lowpoly) é a face plana
      const front = (x, y) => (lowpoly ? rz * 1.05 + ry * 0.03 : rz * Math.sqrt(Math.max(0.05, 1 - (x / rx) ** 2 - (y / ry) ** 2)) * 0.97);
      {
        for (const sx of [-1, 1]) {
          const ex = sx * rx * 0.42, ey = ry * 0.08;
          if (real) {
            parts.head.push(K.color(K.at(K.sphere(ry * 0.09), ex, headCy + ey, front(ex, ey)), [0.96, 0.96, 0.96]));
            parts.head.push(K.color(K.at(K.sphere(ry * 0.055), ex, headCy + ey, front(ex, ey) + ry * 0.05), [0.18, 0.12, 0.08]));
            parts.head.push(sk(K.at(K.ellipsoid(rx * 0.12, ry * 0.2, ry * 0.12), sx * rx * 0.98, headCy, 0)));
          } else parts.head.push(K.color(K.at(K.sphere(ry * 0.075), ex, headCy + ey, front(ex, ey)), [0.1, 0.09, 0.09]));
        }
      }
      if (real) {
        parts.head.push(sk(K.at(K.ellipsoid(ry * 0.09, ry * 0.15, ry * 0.12), 0, headCy - ry * 0.12, front(0, -ry * 0.12) + ry * 0.03)));
        parts.head.push(K.color(K.at(K.ellipsoid(ry * 0.28, ry * 0.04, ry * 0.05), 0, headCy - ry * 0.45, front(0, -ry * 0.45)), mixc(skin, [0.7, 0.2, 0.25], 0.5)));
      }

      // cabelo
      const hc = jitter(hairCol, u, 4, S.vary * 0.6, S.vary * 0.5);
      const hairPaint = (s) => (real ? K.texture(K.color(s, hc), 'mottle', { color2: mixc(hc, [0, 0, 0], 0.35), size: ry * 0.25, bump: S.bump * 0.5 }) : K.color(s, hc));
      if (hairStyle !== 'bald') {
        const capShape = lowpoly ? K.box(rx * 2.15, ry * 1.1, rz * 2.2) : K.ellipsoid(rx * 1.08, ry * 0.82, rz * 1.1);
        parts.head.push(hairPaint(K.at(capShape, 0, headCy + ry * (lowpoly ? 0.72 : 0.3), -rz * 0.08)));
        if (hairStyle === 'long') parts.head.push(hairPaint(limbSeg([0, headCy + ry * 0.3, -rz * 0.75], [0, shoulderY - 0.02 * Hh, -rz * 0.7], rx * 0.95, rx * 0.8, (s) => s)));
        if (hairStyle === 'ponytail') parts.head.push(hairPaint(limbSeg([0, headCy + ry * 0.35, -rz * 0.95], [0, headCy - ry * 0.7, -rz * 1.6], rx * 0.3, rx * 0.16, (s) => s)));
        if (hairStyle === 'bun') parts.head.push(hairPaint(K.at(K.sphere(rx * 0.45), 0, headCy + ry * 1.05, -rz * 0.2)));
        if (hairStyle === 'curly') for (let i = 0; i < lvl(S, [4, 6, 8]); i++) {
          const a2 = rad((i * 360) / lvl(S, [4, 6, 8]) + u(-15, 15));
          parts.head.push(hairPaint(K.at(K.sphere(rx * 0.42), Math.cos(a2) * rx * 0.85, headCy + ry * (0.35 + 0.35 * u()), Math.sin(a2) * rz * 0.8 - rz * 0.1)));
        }
      }

      // braços
      for (const side of [1, -1]) {
        const name = side === 1 ? 'armL' : 'armR';
        const [al, be, bend] = side === 1 ? pose.armL : pose.armR;
        const sh = [side * shHalf, shoulderY - 0.025 * Hh, 0];
        const elbow = addv(sh, scalev(limbDir(al, be, side), Lu));
        const wrist = addv(elbow, scalev(limbDir(al + bend, be * 0.5, side), Lf));
        const upperPaint = sleeveless ? sk : (s) => cloth(s, shirt);
        const lowerPaint = sleeveLong ? (s) => cloth(s, shirt) : sk;
        parts[name].push(limbSeg(sh, elbow, rU, rF, upperPaint), limbSeg(elbow, wrist, rF, rW, lowerPaint));
        if (!lowpoly) parts[name].push(K.color(K.at(K.sphere(rU * 1.12), ...sh), sleeveless ? skin : shirt));
        const hd = scalev(limbDir(al + bend, be * 0.5, side), rW * 1.8);
        const handC = addv(wrist, hd);
        parts[name].push(lowpoly ? sk(K.at(K.box(rW * 2.4, rW * 2.8, rW * 1.8), ...handC)) : sk(K.at(K.ellipsoid(rW * 1.2, rW * (real ? 1.9 : 1.4), rW * 0.8), ...handC)));
        if (real) parts[name].push(sk(K.at(K.ellipsoid(rW * 0.4, rW * 1.1, rW * 0.5), handC[0] + side * rW * 0.9, handC[1] + rW * 0.4, handC[2] + rW * 0.7)));
      }

      // monta, inclina o tronco no idoso e apoia no chão
      const upper = K.group([...parts.head, ...parts.torso, ...parts.armL, ...parts.armR]);
      const upperLean = Bd.lean ? K.rot(upper, Bd.lean, 0, 0, [0, pelvisY, 0]) : upper;
      const body = K.group([
        K.named(K.group(parts.legL), 'perna-esq'), K.named(K.group(parts.legR), 'perna-dir'),
        K.named(upperLean, 'tronco-e-cabeca'),
      ]);
      return K.named(K.ground(body), `pessoa-${buildName}`);
    }),
  };
}
