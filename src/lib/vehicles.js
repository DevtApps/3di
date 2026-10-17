// Gerador de veículos: vehicle(kind, style, length, color, wheels_angle, seed).
//
//   kind  car, hatch, suv, pickup, van, bus, truck, tractor, bike, motorbike
//   style lowpoly = carroceria em caixas, cores chapadas · stylized = caixas bem arredondadas, tinta
//         brilhante, rodas grossas · realistic = proporções reais, caixas de roda, para-choques,
//         grade, retrovisores, aros com raios, faróis e lanternas
//
// Convenções: o veículo anda para +z (frente), o eixo das rodas é x, as rodas tocam y = 0.
// `wheels_angle` gira as rodas em graus e aceita `time` (rodas girando na animação).
// Vidros são placas finas sobre a carroceria e os faróis têm brilho próprio: tudo caixa/elipsoide
// simples, então o veículo é barato de compilar.
import { Native, didYouMean, num } from '../runtime.js';
import { ScriptError } from '../parser.js';
import { isExpr } from '../expr.js';
import { toSrgb } from '../color.js';
import * as K from './kit.js';
import { resolveStyle } from './style.js';
import { randTools, rngFor } from './rand.js';
import { mixc, addv, rad } from './util.js';

const CARS = {
  car:    { L: 4.5, W: 1.8,  bh: 0.68, cl: 2.3, ch: 0.62, cz: -0.1,  c: 0.17, wr: 0.33, info: 'sedã de três volumes' },
  hatch:  { L: 3.9, W: 1.75, bh: 0.66, cl: 2.3, ch: 0.66, cz: -0.25, c: 0.17, wr: 0.31, info: 'hatch compacto' },
  suv:    { L: 4.7, W: 1.9,  bh: 0.8,  cl: 3.1, ch: 0.68, cz: -0.45, c: 0.26, wr: 0.38, info: 'SUV alto' },
  pickup: { L: 5.3, W: 1.9,  bh: 0.85, cl: 1.55, ch: 0.66, cz: 0.95, c: 0.27, wr: 0.4,  bed: true, info: 'picape com caçamba' },
  van:    { L: 5.0, W: 1.95, bh: 0.9,  cl: 3.9, ch: 0.9,  cz: -0.2,  c: 0.22, wr: 0.36, info: 'van de carga ou passageiros' },
};
export const VEHICLE_KINDS = [...Object.keys(CARS), 'bus', 'truck', 'tractor', 'bike', 'motorbike'];

const PAINTS = ['#c8372d', '#2d5fc8', '#e8e8e2', '#2a2f35', '#d8a21a', '#3a9a5a', '#8a8d92', '#e07a2a'];
const GLASS = [0.07, 0.12, 0.17];
const DARK = [0.09, 0.09, 0.1];

export function builtins(ctx) {
  const N = (name, params, fn) => new Native(name, params, fn);

  // ---------- peças comuns ----------
  function kit(S, paint, u) {
    const lowpoly = S.facets, real = S.name === 'realistic';
    const body = (shape) => K.material(K.color(shape, paint), { rough: lowpoly ? 0.85 : 0.28, metal: lowpoly ? 0 : 0.55 });
    const dark = (shape, c = DARK) => K.material(K.color(shape, c), { rough: 0.7, metal: 0 });
    const glass = (shape) => K.material(K.color(shape, GLASS), { rough: 0.05, metal: 0.3 });
    const glow = (shape, c, g = 0.9) => K.material(K.color(shape, c), { rough: 0.2, glow: g });
    const rbox = (w, h, d, rf) => K.box(w, h, d, lowpoly ? 0 : rf * Math.min(w, h, d));
    // roda de eixo x, centro em (x, r, z); a rotação gira em volta do próprio eixo
    const wheel = (r, w, x, z, spin, rimCol = [0.78, 0.8, 0.84]) => {
      const parts = [K.color(K.rot(K.cyl(r, w, lowpoly ? 0 : w * 0.3), 0, 0, 90), [0.05, 0.05, 0.055])];
      const rr = r * 0.62;
      if (lowpoly) parts.push(K.color(K.box(w * 1.05, rr * 1.6, rr * 0.35), rimCol));
      else {
        parts.push(K.material(K.color(K.rot(K.cyl(rr, w * 1.04), 0, 0, 90), rimCol), { rough: 0.3, metal: 0.8 }));
        // marcas no aro para a rotação aparecer: um raio (stylized) ou cinco (realistic)
        const spokes = real ? 5 : 1;
        for (let i = 0; i < spokes; i++) {
          const sp = K.color(K.box(w * 1.1, rr * 0.28, rr * 1.7), real ? [0.5, 0.52, 0.56] : [0.25, 0.25, 0.28]);
          parts.push(K.rot(sp, (i * 180) / spokes, 0, 0));
        }
      }
      let g = K.group(parts);
      if (spin !== 0) g = K.rot(g, spin, 0, 0);
      return K.at(g, x, r, z);
    };
    const light = (w, h, d, x, y, z, c, g) => (lowpoly ? glow(K.at(K.box(w, h, d), x, y, z), c, g) : glow(K.at(K.ellipsoid(w / 2, h / 2, d / 2), x, y, z), c, g));
    return { body, dark, glass, glow, rbox, wheel, light, lowpoly, real };
  }

  // ---------- família dos carros (car, hatch, suv, pickup, van) ----------
  function carFamily(P, S, paint, u, spin) {
    const k = kit(S, paint, u);
    const { L, bh, cl, ch, cz, c, wr } = P;
    const W = P.W;            // bitola (rodas)
    const Wb = W * 0.93;       // largura da carroceria: um pouco menor, para as rodas aparecerem
    const parts = [];
    const r = k.lowpoly ? 0 : 0.28;
    // carroceria baixa e cabine
    parts.push(k.body(K.at(k.rbox(Wb, bh, L, r * 0.9), 0, c + bh / 2, 0)));
    const cw = Wb * (P.bed ? 0.92 : 0.9);
    parts.push(k.body(K.at(k.rbox(cw, ch, cl, r), 0, c + bh + ch / 2 - 0.02, cz)));
    // vidros: laterais, para-brisa inclinado e vidro traseiro
    const gy = c + bh + ch * 0.5;
    for (const sx of [-1, 1]) parts.push(k.glass(K.at(K.box(0.03, ch * 0.62, cl * 0.84), sx * (cw / 2 + 0.005), gy, cz)));
    const slope = P.bed ? 22 : 28;
    parts.push(k.glass(K.at(K.rot(K.box(cw * 0.9, ch * 0.78, 0.03), -slope, 0, 0), 0, gy - 0.02, cz + cl / 2 + 0.01)));
    parts.push(k.glass(K.at(K.rot(K.box(cw * 0.9, ch * 0.78, 0.03), (P === CARS.hatch || P === CARS.suv || P === CARS.van) ? 12 : slope, 0, 0), 0, gy - 0.02, cz - cl / 2 - 0.01)));
    // caçamba (pickup): piso e três paredes
    if (P.bed) {
      const zb = -L / 2 + (cz - cl / 2 + L / 2) / 2;
      const bl = cz - cl / 2 + L / 2;
      parts.push(k.dark(K.at(K.box(Wb * 0.92, 0.04, bl), 0, c + bh + 0.01, zb), [0.12, 0.12, 0.13]));
      for (const sx of [-1, 1]) parts.push(k.body(K.at(k.rbox(0.07, 0.3, bl, 0.2), sx * (Wb / 2 - 0.035), c + bh + 0.15, zb)));
      parts.push(k.body(K.at(k.rbox(Wb * 0.92, 0.3, 0.07, 0.2), 0, c + bh + 0.15, -L / 2 + 0.035)));
      parts.push(k.body(K.at(k.rbox(Wb * 0.92, 0.3, 0.07, 0.2), 0, c + bh + 0.15, cz - cl / 2 - 0.04)));
    }
    // rodas
    const wb = L * 0.58, tw = k.lowpoly ? 0.24 : 0.26;
    for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
      parts.push(k.wheel(wr, tw, sx * (W / 2 - tw / 2), sz * wb / 2, spin));
      if (k.real) parts.push(k.dark(K.at(K.rot(K.cyl(wr * 1.12, 0.04), 0, 0, 90), sx * (Wb / 2 + 0.002), wr, sz * wb / 2)));
    }
    // faróis e lanternas
    const ly = c + bh * 0.68;
    for (const sx of [-1, 1]) {
      parts.push(k.light(0.3, 0.14, 0.06, sx * Wb * 0.32, ly, L / 2 + 0.005, [1, 0.95, 0.75], 0.8));
      parts.push(k.light(0.26, 0.12, 0.05, sx * Wb * 0.34, ly, -L / 2 - 0.005, [0.9, 0.08, 0.06], 0.7));
    }
    if (k.real || S.name === 'stylized') {
      parts.push(k.dark(K.at(K.box(Wb * 1.0, 0.16, 0.2), 0, c + 0.12, L / 2 - 0.05)));          // para-choque dianteiro
      parts.push(k.dark(K.at(K.box(Wb * 1.0, 0.16, 0.2), 0, c + 0.12, -L / 2 + 0.05)));         // traseiro
    }
    if (k.real) {
      parts.push(k.dark(K.at(K.box(Wb * 0.42, 0.14, 0.04), 0, c + bh * 0.6, L / 2 + 0.01)));   // grade
      for (const sx of [-1, 1]) parts.push(k.body(K.at(K.box(0.14, 0.09, 0.1), sx * (cw / 2 + 0.1), gy + ch * 0.12, cz + cl / 2 - 0.2))); // retrovisores
    }
    return { parts, height: c + bh + ch };
  }

  // ---------- ônibus ----------
  function bus(S, paint, u, spin) {
    const k = kit(S, paint, u);
    const L = 11, W = 2.5, H = 3.1, c = 0.3, wr = 0.5;
    const Wb = W * 0.94;
    const parts = [k.body(K.at(k.rbox(Wb, H - c, L, 0.12), 0, c + (H - c) / 2, 0))];
    parts.push(k.body(K.color(K.at(k.rbox(Wb * 1.002, 0.55, L * 1.002, 0.1), 0, c + 0.3, 0), mixc(paint, [0, 0, 0], 0.35))));   // saia
    for (const sx of [-1, 1]) {
      parts.push(k.glass(K.at(K.box(0.04, 0.95, L * 0.8), sx * (Wb / 2 + 0.005), 2.05, -0.5)));
      parts.push(k.dark(K.at(K.box(0.05, 1.7, 1.0), sx * (Wb / 2 + 0.006), 1.15, L * 0.34)));
    }
    parts.push(k.glass(K.at(K.box(W * 0.9, 1.2, 0.04), 0, 1.95, L / 2 + 0.005)));
    parts.push(k.glass(K.at(K.box(W * 0.7, 0.7, 0.04), 0, 2.0, -L / 2 - 0.005)));
    for (const sx of [-1, 1]) for (const z of [L * 0.3, -L * 0.28]) {
      parts.push(k.wheel(wr, 0.32, sx * (W / 2 - 0.16), z, spin));
      if (k.real) parts.push(k.dark(K.at(K.rot(K.cyl(wr * 1.1, 0.04), 0, 0, 90), sx * (Wb / 2 + 0.002), wr, z)));
    }
    for (const sx of [-1, 1]) {
      parts.push(k.light(0.32, 0.16, 0.06, sx * W * 0.36, 0.75, L / 2 + 0.005, [1, 0.95, 0.75], 0.8));
      parts.push(k.light(0.28, 0.14, 0.05, sx * W * 0.36, 0.75, -L / 2 - 0.005, [0.9, 0.08, 0.06], 0.7));
    }
    return { parts, height: H };
  }

  // ---------- caminhão: cabine, chassi e baú ----------
  function truck(S, paint, u, spin) {
    const k = kit(S, paint, u);
    const L = 7.5, W = 2.5, c = 0.5, wr = 0.5;
    const cabL = 2.0, cabH = 2.0, boxL = 5.2, boxH = 2.6;
    const Wb = W * 0.94;
    const parts = [k.dark(K.at(K.box(W * 0.8, 0.3, L), 0, c + 0.1, 0), [0.14, 0.14, 0.15])];
    parts.push(k.body(K.at(k.rbox(Wb, cabH, cabL, 0.14), 0, c + 0.25 + cabH / 2, L / 2 - cabL / 2)));
    parts.push(k.glass(K.at(K.rot(K.box(W * 0.88, 0.85, 0.04), -8, 0, 0), 0, c + 0.25 + cabH * 0.68, L / 2 + 0.005)));
    for (const sx of [-1, 1]) parts.push(k.glass(K.at(K.box(0.04, 0.8, cabL * 0.55), sx * (Wb / 2 + 0.005), c + 0.25 + cabH * 0.68, L / 2 - cabL * 0.42)));
    parts.push(K.material(K.color(K.at(k.rbox(Wb * 0.98, boxH, boxL, 0.05), 0, c + 0.25 + boxH / 2, -L / 2 + boxL / 2), [0.93, 0.93, 0.9]), { rough: 0.7, metal: 0 }));
    const axles = [L / 2 - 1.2, -L / 2 + 1.3, -L / 2 + 2.45];
    for (const sx of [-1, 1]) for (const z of axles) {
      parts.push(k.wheel(wr, 0.3, sx * (W / 2 - 0.15), z, spin));
      if (k.real) parts.push(k.dark(K.at(K.rot(K.cyl(wr * 1.1, 0.04), 0, 0, 90), sx * (W / 2 + 0.002), wr, z)));
    }
    for (const sx of [-1, 1]) {
      parts.push(k.light(0.3, 0.16, 0.06, sx * W * 0.34, c + 0.7, L / 2 + 0.005, [1, 0.95, 0.75], 0.8));
      parts.push(k.light(0.26, 0.14, 0.05, sx * W * 0.38, c + 0.7, -L / 2 - 0.005, [0.9, 0.08, 0.06], 0.7));
    }
    return { parts, height: c + 0.25 + boxH };
  }

  // ---------- trator ----------
  function tractor(S, paint, u, spin) {
    const k = kit(S, paint, u);
    const L = 3.8, W = 1.9, wrB = 0.78, wrF = 0.46;
    const parts = [k.body(K.at(k.rbox(0.9, 0.85, 2.0, 0.2), 0, 0.95, 0.85))];                  // capô
    parts.push(k.dark(K.at(k.rbox(0.7, 0.55, 0.3, 0.2), 0, 1.0, 1.9), [0.12, 0.12, 0.13]));    // grade
    parts.push(k.dark(K.at(K.box(1.1, 0.35, 2.4), 0, 0.55, 0.3), [0.2, 0.2, 0.22]));           // chassi
    // cabine aberta: quatro colunas, teto e vidros
    for (const sx of [-1, 1]) for (const sz of [-1, 1]) parts.push(k.body(K.at(K.box(0.07, 1.25, 0.07), sx * 0.62, 1.95, -0.55 + sz * 0.5)));
    parts.push(k.body(K.at(k.rbox(1.45, 0.09, 1.25, 0.3), 0, 2.6, -0.55)));
    parts.push(k.glass(K.at(K.box(1.2, 0.8, 0.03), 0, 2.0, -1.05)));
    parts.push(k.dark(K.at(K.box(0.5, 0.12, 0.5), 0, 1.35, -0.55), [0.15, 0.12, 0.1]));        // banco
    parts.push(k.dark(K.at(K.cyl(0.05, 0.9), 0.35, 1.9, 1.4), [0.3, 0.3, 0.32]));              // escapamento
    for (const sx of [-1, 1]) {
      parts.push(k.wheel(wrB, 0.42, sx * (W / 2 - 0.2), -0.7, spin));
      parts.push(k.wheel(wrF, 0.26, sx * (W / 2 - 0.5), 1.3, spin));
    }
    for (const sx of [-1, 1]) parts.push(k.light(0.2, 0.16, 0.06, sx * 0.3, 1.1, 1.92, [1, 0.95, 0.75], 0.8));
    return { parts, height: 2.65 };
  }

  // ---------- bicicleta ----------
  function bike(S, paint, u, spin) {
    const lowpoly = S.facets, real = S.name === 'realistic';
    const frame = (a, b, r) => K.material(K.color(K.segment(a, b, r), paint), { rough: 0.35, metal: 0.6 });
    const wr = 0.34, wb = 1.0;
    const parts = [];
    const wheelB = (z) => {
      const tire = K.color(K.rot(K.torus(wr - 0.02, lowpoly ? 0.03 : 0.022), 0, 0, 90), [0.05, 0.05, 0.055]);
      const spokes = K.color(K.group([K.segment([0, -(wr - 0.03), 0], [0, wr - 0.03, 0], 0.004), K.segment([0, 0, -(wr - 0.03)], [0, 0, wr - 0.03], 0.004)]), [0.7, 0.72, 0.75]);
      let g = K.group(real ? [tire, spokes, K.color(K.rot(K.cyl(0.03, 0.05), 0, 0, 90), [0.5, 0.5, 0.54])] : [tire, spokes]);
      if (spin !== 0) g = K.rot(g, spin, 0, 0);
      return K.at(g, 0, wr, z);
    };
    parts.push(wheelB(wb / 2), wheelB(-wb / 2));
    const bb = [0, 0.3, -0.05], seat = [0, 0.86, -0.3], head = [0, 0.9, 0.34];
    parts.push(frame(bb, seat, 0.017), frame(bb, head, 0.019), frame(seat, head, 0.016));            // selim -> mesa, quadro
    parts.push(frame(bb, [0, wr, -wb / 2], 0.014), frame(seat, [0, wr, -wb / 2], 0.012));            // garfo traseiro
    parts.push(frame(head, [0, wr, wb / 2], 0.016));                                                 // garfo dianteiro
    parts.push(K.color(K.segment([-0.22, 1.0, 0.36], [0.22, 1.0, 0.36], 0.013), [0.12, 0.12, 0.13])); // guidão
    parts.push(K.color(K.at(K.ellipsoid(0.07, 0.025, 0.13), 0, 0.89, -0.32), [0.1, 0.1, 0.11]));      // selim
    if (!lowpoly) parts.push(K.color(K.segment([-0.15, 0.3, -0.05], [0.15, 0.3, -0.05], 0.01), [0.3, 0.3, 0.32]), K.color(K.at(K.rot(K.cyl(0.08, 0.01), 0, 0, 90), 0.02, 0.3, -0.05), [0.6, 0.6, 0.64]));
    return { parts, height: 1.05 };
  }

  // ---------- moto ----------
  function motorbike(S, paint, u, spin) {
    const lowpoly = S.facets, real = S.name === 'realistic';
    const body = (shape) => K.material(K.color(shape, paint), { rough: 0.3, metal: lowpoly ? 0 : 0.55 });
    const wr = 0.32, wb = 1.35;
    const parts = [];
    for (const z of [wb / 2, -wb / 2]) {
      let g = K.group([K.color(K.rot(K.torus(wr - 0.06, 0.075), 0, 0, 90), [0.05, 0.05, 0.055]), K.material(K.color(K.rot(K.cyl(wr * 0.6, 0.1), 0, 0, 90), [0.7, 0.72, 0.76]), { rough: 0.3, metal: 0.8 }), K.color(K.box(0.12, 0.05, wr * 1.2), [0.3, 0.3, 0.33])]);
      if (spin !== 0) g = K.rot(g, spin, 0, 0);
      parts.push(K.at(g, 0, wr, z));
    }
    parts.push(K.color(K.at(K.box(0.28, 0.34, 0.55, lowpoly ? 0 : 0.05), 0, 0.5, 0.0), [0.22, 0.22, 0.25]));        // motor
    parts.push(body(K.at(lowpoly ? K.box(0.3, 0.26, 0.55) : K.ellipsoid(0.17, 0.14, 0.3), 0, 0.88, 0.22)));          // tanque
    parts.push(K.color(K.at(K.box(0.24, 0.1, 0.6, lowpoly ? 0 : 0.04), 0, 0.82, -0.32), [0.1, 0.1, 0.11]));          // banco
    parts.push(K.color(K.segment([0, 0.95, wb / 2 - 0.1], [0, wr, wb / 2], 0.025), [0.7, 0.72, 0.76]));              // garfo
    parts.push(K.color(K.segment([-0.3, 1.02, wb / 2 - 0.15], [0.3, 1.02, wb / 2 - 0.15], 0.016), [0.12, 0.12, 0.13])); // guidão
    parts.push(K.material(K.color(K.at(K.sphere(0.09), 0, 0.98, wb / 2 + 0.02), [1, 0.95, 0.75]), { glow: 0.8, rough: 0.2 }));
    parts.push(K.color(K.segment([0.16, 0.38, 0.2], [0.18, 0.3, -0.75], 0.04), [0.55, 0.57, 0.6]));               // escapamento
    parts.push(K.color(K.segment([0, 0.5, -0.2], [0, wr, -wb / 2], 0.03), [0.25, 0.25, 0.28]));                    // balança
    if (real) parts.push(body(K.at(K.ellipsoid(0.15, 0.1, 0.24), 0, 0.68, -0.52)));                                  // rabeta
    return { parts, height: 1.15 };
  }

  return {
    vehicle: N('vehicle', ['kind="car"', 'style="stylized"', 'length=None', 'color=None', 'wheels_angle=0', 'seed=None'], (a) => {
      const kindName = String(a.kind).toLowerCase();
      if (!VEHICLE_KINDS.includes(kindName)) {
        throw new ScriptError(`vehicle(): tipo desconhecido '${a.kind}'`, null, didYouMean(kindName, VEHICLE_KINDS) ?? `use ${VEHICLE_KINDS.join(', ')}`);
      }
      const S = resolveStyle(a.style, 'vehicle()');
      const rng = rngFor(ctx, a.seed);
      const { u, pick } = randTools(rng);
      const paint = toSrgb(a.color ?? pick(PAINTS));
      const spin = isExpr(a.wheels_angle) ? a.wheels_angle : num(a.wheels_angle, 'wheels_angle');
      let built;
      if (CARS[kindName]) built = carFamily(CARS[kindName], S, paint, u, spin);
      else if (kindName === 'bus') built = bus(S, paint, u, spin);
      else if (kindName === 'truck') built = truck(S, paint, u, spin);
      else if (kindName === 'tractor') built = tractor(S, paint, u, spin);
      else if (kindName === 'bike') built = bike(S, paint, u, spin);
      else built = motorbike(S, paint, u, spin);
      let out = K.group(built.parts);
      if (a.length !== null) {
        const len = num(a.length, 'length');
        if (!(len > 0)) throw new ScriptError('vehicle(): length deve ser maior que zero', null);
        const b = out.bbox;
        out = K.scale(out, len / (b.max[2] - b.min[2]));
      }
      return K.named(K.ground(out), `veiculo-${kindName}`);
    }),
  };
}
