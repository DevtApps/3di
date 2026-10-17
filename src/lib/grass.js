// Gerador de grama: grass(largura, fundo, kind=..., style=...).
//
// Dois eixos independentes:
//   kind  = que grama é   (lawn, meadow, tall, dry, tufts, wheat, clover)
//   style = como é desenhada (lowpoly, stylized, realistic)
//
// Como funciona sem pesar: cada "camada" é UMA unidade (lâmina, touceira ou espiga) repetida com
// .repeat(), que não custa primitivas. As camadas têm alturas, larguras, inclinações e
// espaçamentos diferentes e a grade de cada uma é girada um pouco, o que esconde a regularidade
// e dá a sobreposição densa de um campo de verdade. O recorte com uma caixa mantém as bordas retas.
import { Native, didYouMean, num } from '../runtime.js';
import { ScriptError } from '../parser.js';
import { sym, TIME } from '../expr.js';
import { toSrgb, rgbToHsv, hsvToRgb } from '../color.js';
import { rotMatrix, mulMV } from '../shapes.js';
import * as K from './kit.js';
import { resolveStyle } from './style.js';
import { randTools, rngFor } from './rand.js';

// Cada kind: proporções (m) e cores (base escura -> ponta clara).
const KINDS = {
  lawn:   { h: 0.1,  w: 0.05, lean: [6, 18],  curve: 0.25, layers: 8,  base: '#17501a', tip: '#7fd042', info: 'gramado curto de jardim' },
  meadow: { h: 0.17, w: 0.09, lean: [10, 24], curve: 0.3,  layers: 9,  base: '#1d5a18', tip: '#8fd24a', info: 'campo de grama média' },
  tall:   { h: 0.5,  w: 0.06, lean: [5, 16],  curve: 0.7,  layers: 7,  base: '#2a5518', tip: '#b2c94e', info: 'capim alto que pende' },
  dry:    { h: 0.3,  w: 0.05, lean: [10, 30], curve: 0.8,  layers: 8,  base: '#6a5a24', tip: '#e6c872', info: 'grama seca de savana' },
  tufts:  { h: 0.3,  w: 0.05, lean: [14, 34], curve: 0.6,  layers: 3,  base: '#1a521b', tip: '#8ccf45', info: 'touceiras de folhas arqueadas' },
  wheat:  { h: 0.55, w: 0.03, lean: [2, 10],  curve: 0.25, layers: 5,  base: '#7a6a2a', tip: '#e8c25a', info: 'trigo: hastes finas com espigas' },
  clover: { h: 0.07, w: 0.05, lean: [6, 16],  curve: 0.2,  layers: 6,  base: '#1a5a22', tip: '#6fc760', info: 'trevo baixo salpicado de flores' },
};
export const GRASS_KINDS = Object.keys(KINDS);

const FLOWERS = [[1, 1, 0.95], [1, 0.85, 0.2], [0.82, 0.5, 0.95], [1, 0.55, 0.7], [0.98, 0.45, 0.3]];

const rad = (d) => (d * Math.PI) / 180;
const mixc = (a, b, t) => a.map((x, i) => x + (b[i] - x) * t);

// cor com variação em HSV (reprodutível pelo rng)
function jitter(c, u, hue, sat, val) {
  const [h, s, v] = rgbToHsv(c);
  const j = (r) => (u() * 2 - 1) * r;
  return hsvToRgb(h + j(hue), Math.min(1, Math.max(0, s + j(sat))), Math.min(1, Math.max(0, v + j(val))));
}

// Lâmina com a base na origem. pieces = 1: pirâmide achatada (facetada); > 1: cadeia de troncos de
// cone que arqueia (lean cresce a cada peça) e afina até a ponta. Devolve { shape, tip }.
function blade(st, { h, w, lean, yaw, curve, flat }) {
  let shape, tip;
  if (st.facets || st.pieces === 1) {
    shape = K.ground(K.scale(K.pyramid(w, h), [1, 1, flat]));
    shape = K.rot(shape, lean, 0, 0, [0, 0, 0]);
    tip = K.tipOf(h, lean);
  } else {
    const n = st.pieces;
    const parts = [];
    let pos = [0, 0, 0];
    for (let k = 0; k < n; k++) {
      const tilt = lean * (1 + curve * (k / Math.max(1, n - 1)) * 1.5);
      const len = h / n;
      const r0 = (w / 2) * (1 - k / n * 0.85), r1 = (w / 2) * Math.max(0.04, 1 - (k + 1) / n * 0.97);
      let piece = K.at(K.scale(K.cone(r0, len, r1), [1, 1, flat]), 0, len / 2, 0);
      piece = K.move(K.rot(piece, tilt, 0, 0, [0, 0, 0]), pos);
      parts.push(piece);
      const step = K.tipOf(len, tilt);
      pos = pos.map((v, i) => v + step[i]);
    }
    shape = K.group(parts);
    tip = pos;
  }
  return { shape: K.rot(shape, 0, yaw, 0, [0, 0, 0]), tip: mulMV(rotMatrix(0, yaw, 0), tip) };
}

// Pinta a unidade: degradê da base à ponta (se o estilo tiver) ou cor chapada; manchas no realista.
function paint(unit, st, base, tip, t) {
  if (st.gradient) {
    let s = K.texture(K.color(unit, base), 'gradient', { color2: tip });
    return s;
  }
  return K.color(unit, mixc(base, tip, 0.25 + 0.6 * t));
}

export function builtins(ctx) {
  const N = (name, params, fn) => new Native(name, params, fn);
  return {
    grass: N('grass', ['width=2', 'depth=None', 'kind="meadow"', 'style="stylized"', 'height=None', 'density=1', 'color=None', 'tip=None', 'flowers=0', 'sway=0', 'soil=None', 'seed=None'], (a) => {
      const W = num(a.width, 'width');
      const D = a.depth === null ? W : num(a.depth, 'depth');
      if (!(W > 0) || !(D > 0)) throw new ScriptError('grass(): largura e fundo devem ser maiores que zero', null);
      const kindName = String(a.kind).toLowerCase();
      const kind = KINDS[kindName];
      if (!kind) throw new ScriptError(`grass(): tipo desconhecido '${a.kind}'`, null, didYouMean(kindName, GRASS_KINDS) ?? `use ${GRASS_KINDS.join(', ')}`);
      const style = resolveStyle(a.style, 'grass()');
      const density = num(a.density, 'density');
      if (!(density > 0)) throw new ScriptError('grass(): density deve ser maior que zero', null, 'density=1 é o normal; 0.5 é ralo, 2 é denso');
      const H = a.height === null ? kind.h : num(a.height, 'height');
      const flowerAmount = Math.max(0, num(a.flowers, 'flowers')) + (kindName === 'clover' ? 0.35 : 0);
      const sway = num(a.sway, 'sway');
      const rng = rngFor(ctx, a.seed);
      const { u, pick } = randTools(rng);
      const base = toSrgb(a.color ?? kind.base);
      const tip = toSrgb(a.tip ?? kind.tip);

      // quanto cada estilo desenha: número de camadas, de peças por lâmina e a espessura
      const geom = {
        lowpoly: { pieces: 1, layers: 4, flat: 0.5, wScale: 1.7 },
        stylized: { pieces: 1, layers: kind.layers, flat: 0.16, wScale: 1.15 },
        realistic: { pieces: 2, layers: Math.round(kind.layers * 1.5), flat: 0.1, wScale: 0.55 },
      }[style.name];
      const S = { ...style, ...geom };
      const layers = Math.max(2, Math.min(28, Math.round(geom.layers * density)));

      const layerShapes = [];
      // grade um pouco maior que o canteiro, porque cada camada gira alguns graus
      const gW = W + D * 0.22, gD = D + W * 0.22;
      const clip = K.ground(K.box(W, 4, D));
      const maxCells = 9000;

      const addGrid = (unit, layerIndex, color) => {
        const ub = unit.bbox;
        const w = ub.max[0] - ub.min[0], d = ub.max[2] - ub.min[2];
        // o balanço do vento abre mais a célula
        const swayExtra = sway > 0 ? (ub.max[1] - ub.min[1]) * Math.sin(rad(sway)) * 2 : 0;
        let esp = (Math.max(w, d) + swayExtra) * 1.04;
        // se a grade passar de maxCells células, divide o canteiro em ladrilhos
        const cells = (gW / esp) * (gD / esp);
        const tiles = cells > maxCells ? Math.ceil(Math.sqrt(cells / maxCells)) : 1;
        const tW = W / tiles, tD = D / tiles;
        const gtW = tW + tD * 0.22, gtD = tD + tW * 0.22;
        const nx = Math.max(1, Math.floor(gtW / esp)), nz = Math.max(1, Math.floor(gtD / esp));
        for (let ix = 0; ix < tiles; ix++) for (let iz = 0; iz < tiles; iz++) {
          let g = K.repeat(unit, { x: nx, z: nz, spacing: esp });
          g = K.at(g, layerIndex * 0.017, 0, layerIndex * 0.029);
          g = K.rot(g, 0, layerIndex * 5 - 12, 0, [0, 0, 0]);
          const cx = -W / 2 + tW * (ix + 0.5), cz = -D / 2 + tD * (iz + 0.5);
          g = K.at(g, cx, 0, cz);
          const box = K.at(K.ground(K.box(tW, 4, tD)), cx, 0, cz);
          layerShapes.push(K.color(K.intersect(g, box), color));
        }
      };

      // --- unidade de cada camada, conforme o kind ---
      for (let l = 0; l < layers; l++) {
        const t = layers === 1 ? 1 : l / (layers - 1);
        const hl = H * (0.55 + 0.7 * t) * u(0.9, 1.1);
        const wl = kind.w * geom.wScale * u(0.85, 1.25);
        const lean = u(kind.lean[0], kind.lean[1]);
        const yaw = l * 47 + u(-15, 15);
        const bl = jitter(base, u, 4, style.vary, style.vary * 0.8);
        const tp = jitter(tip, u, 6, style.vary, style.vary * 0.8);
        let unit;
        if (kindName === 'tufts') {
          // touceira: lâminas saindo do mesmo ponto, abrindo para fora
          const n = Math.min(9, Math.max(4, Math.round(7 * Math.max(0.6, style.detail))));
          const blades = [];
          for (let i = 0; i < n; i++) {
            blades.push(blade(S, { h: hl * u(0.65, 1.15), w: wl * u(0.9, 1.4), lean: lean * u(0.6, 1.4), yaw: (i * 360) / n + u(-22, 22), curve: kind.curve, flat: geom.flat }).shape);
          }
          unit = paint(K.group(blades), S, bl, tp, t);
        } else if (kindName === 'wheat') {
          const b = blade(S, { h: hl, w: wl, lean, yaw, curve: kind.curve, flat: 1 });
          const head = K.at(K.rot(K.ellipsoid(0.022, 0.07, 0.022), lean * 1.6, yaw, 0, [0, 0, 0]), b.tip[0], b.tip[1] + 0.03, b.tip[2]);
          // a espiga leva a própria cor; a haste sai pintada pelo degradê
          unit = K.group([paint(b.shape, S, bl, tp, t), K.color(head, mixc([0.8, 0.6, 0.18], [0.95, 0.78, 0.36], t))]);
        } else {
          const b = blade(S, { h: hl, w: wl, lean, yaw, curve: kind.curve, flat: geom.flat });
          unit = paint(b.shape, S, bl, tp, t);
        }
        if (sway > 0) {
          const ang = sym('*', sym('sin', sym('+', sym('*', TIME, 1.6), l * 1.3)), sway);
          unit = K.rot(unit, 0, 0, ang, [0, 0, 0]);
        }
        // as unidades já saem pintadas; a cor de fora só cobre as faces do recorte
        addGrid(unit, l, mixc(base, tip, 0.2));
      }

      // --- flores: camadas esparsas (uma por cor), cada uma com espaçamento diferente ---
      if (flowerAmount > 0) {
        const kinds = Math.min(FLOWERS.length, 3 + Math.floor(flowerAmount * 2));
        for (let f = 0; f < kinds; f++) {
          const stemH = H * u(1.0, 1.6) + 0.04;
          const head = K.at(K.sphere(u(0.022, 0.034)), 0, stemH, 0);
          const eye = K.color(K.at(K.sphere(0.012), 0, stemH + 0.026, 0), [1, 0.82, 0.15]);
          const stem = K.color(K.segment([0, 0, 0], [0, stemH, 0], 0.004), mixc(base, tip, 0.3));
          const unit = K.group([stem, K.color(head, FLOWERS[f % FLOWERS.length]), eye]);
          const spacing = (0.34 + f * 0.043) / Math.sqrt(flowerAmount);
          const nx = Math.max(1, Math.floor(W / spacing)), nz = Math.max(1, Math.floor(D / spacing));
          if (nx * nz > maxCells) continue;
          let g = K.repeat(unit, { x: nx, z: nz, spacing });
          layerShapes.push(K.at(g, u(-0.05, 0.05), 0, u(-0.05, 0.05)));
        }
      }

      let out = K.group(layerShapes);
      if (a.soil !== null) out = K.group([out, K.color(K.at(K.box(W, 0.04, D), 0, -0.02, 0), a.soil)]);
      return K.named(out, `grama-${kindName}`);
    }),
  };
}
