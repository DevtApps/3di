// Padrões de superfície que mudam a silhueta: tábuas (planks), telhas (shingles) e alvenaria
// (masonry). Custo constante: não cria uma primitiva por tábua; o nó só soma à distância da forma
// um sulco calculado em 2D na face dominante da caixa da peça (sem reavaliar a forma, então não
// pesa na compilação do shader). Os sulcos só tiram material: a caixa envolvente não muda.
import { ScriptError } from './parser.js';
import { num } from './runtime.js';
import { Shape, METHODS } from './shapes.js';

export const PATTERN_KINDS = { planks: 1, shingles: 2, masonry: 3 };
const AXES = { x: 0, y: 1, z: 2 };

// mesma conta no GLSL e na CPU (export, testes): devolve g >= 0, quanto afundar (em unidades de depth)
export const PATTERN_GLSL = /* glsl */ `
float patHash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float patG(vec3 p, vec3 bmin, vec3 bc, vec3 hf, int kind, vec2 sz, float gap, int ax, float vary) {
  vec3 q = abs(p - bc) / max(hf, vec3(1e-4));
  int n = q.x > q.y ? (q.x > q.z ? 0 : 2) : (q.y > q.z ? 1 : 2);
  vec3 r = p - bmin;
  int iu, iv;
  if (kind == 1) { iu = ax != n ? ax : (n == 1 ? 0 : 1); iv = 3 - n - iu; }
  else { iv = n == 1 ? 2 : 1; iu = 3 - n - iv; }
  float u = r[iu], v = r[iv];
  float H = sz.y, L = sz.x;
  float row = floor(v / H), fv = v / H - row;
  float shift = kind == 3 ? 0.5 * mod(row, 2.0) : patHash(vec2(row, 7.0));
  float uu = L > 0.0 ? u / L + shift : 0.5;
  float col = L > 0.0 ? floor(uu) : 0.0, fu = L > 0.0 ? uu - col : 0.5;
  float e = min(min(fv, 1.0 - fv) * H, L > 0.0 ? min(fu, 1.0 - fu) * L : 1e3);
  float soft = kind == 3 ? 0.25 * min(L, H) : 0.5 * gap;
  float groove = 1.0 - smoothstep(0.5 * gap, 0.5 * gap + soft, e);
  if (kind == 2) {
    // telhas: cada fileira é mais grossa embaixo (cobre a de baixo) e afina até o topo
    float slope = fv * (1.0 - smoothstep(1.0 - gap / H, 1.0, fv));
    float side = L > 0.0 ? 1.0 - smoothstep(0.5 * gap, gap, min(fu, 1.0 - fu) * L) : 0.0;
    groove = max(slope, side);
  }
  float h = vary * patHash(vec2(col, row) + 0.37);
  return groove + h * (1.0 - groove);
}
`;

const fract = (x) => x - Math.floor(x);
const smooth = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
const hash = (x, y) => fract(Math.sin(x * 127.1 + y * 311.7) * 43758.5453);

export function patternG(p, P) {
  const { bmin, bc, hf, kind, sz, gap, ax, vary } = P;
  const q = [0, 1, 2].map((i) => Math.abs(p[i] - bc[i]) / Math.max(hf[i], 1e-4));
  const n = q[0] > q[1] ? (q[0] > q[2] ? 0 : 2) : (q[1] > q[2] ? 1 : 2);
  let iu, iv;
  if (kind === 1) { iu = ax !== n ? ax : (n === 1 ? 0 : 1); iv = 3 - n - iu; }
  else { iv = n === 1 ? 2 : 1; iu = 3 - n - iv; }
  const u = p[iu] - bmin[iu], v = p[iv] - bmin[iv];
  const [L, H] = sz;
  const row = Math.floor(v / H), fv = v / H - row;
  const shift = kind === 3 ? 0.5 * (((row % 2) + 2) % 2) : hash(row, 7);
  const uu = L > 0 ? u / L + shift : 0.5;
  const col = L > 0 ? Math.floor(uu) : 0, fu = L > 0 ? uu - col : 0.5;
  const e = Math.min(Math.min(fv, 1 - fv) * H, L > 0 ? Math.min(fu, 1 - fu) * L : 1e3);
  const soft = kind === 3 ? 0.25 * Math.min(L, H) : 0.5 * gap;
  let groove = 1 - smooth(0.5 * gap, 0.5 * gap + soft, e);
  if (kind === 2) {
    const slope = fv * (1 - smooth(1 - gap / H, 1, fv));
    const side = L > 0 ? 1 - smooth(0.5 * gap, gap, Math.min(fu, 1 - fu) * L) : 0;
    groove = Math.max(slope, side);
  }
  const h = vary * hash(col + 0.37, row + 0.37);
  return groove + h * (1 - groove);
}

// o sulco muda rápido (largura ~gap): o fator encurta o passo do raio para não atravessá-lo
export const patternLip = (P) => 1 / (1 + (2 * P.depth) / Math.max(P.gap, 1e-4));

function make(s, kind, L, H, gap, depth, vary, axis, what) {
  const b = s.bbox;
  if (!b.min.every((v) => v > -1e3) || !b.max.every((v) => v < 1e3)) throw new ScriptError(`${what} não funciona com formas infinitas (plane)`, null);
  const pos = (v, n) => { const x = num(v, n); if (!(x > 0)) throw new ScriptError(`${what}: ${n} deve ser maior que zero`, null); return x; };
  const sz = [L === null ? 0 : pos(L, 'length'), pos(H, kind === 1 ? 'width' : 'height')];
  const g = pos(gap, 'gap'), d = pos(depth, 'depth'), va = num(vary, 'vary');
  if (va < 0 || va > 1) throw new ScriptError(`${what}: vary deve ficar entre 0 e 1`, null);
  const ax = AXES[String(axis).toLowerCase()];
  if (ax === undefined) throw new ScriptError(`${what}: axis deve ser "x", "y" ou "z"`, null);
  return new Shape('pattern', {
    kind, sz, gap: g, depth: d, vary: va, ax,
    bmin: [...b.min], bc: b.min.map((v, i) => (v + b.max[i]) / 2), hf: b.min.map((v, i) => (b.max[i] - v) / 2),
  }, [s]);
}

Object.assign(METHODS, {
  // tábuas de largura `width` correndo ao longo de `axis`; com `length`, emendas desencontradas
  planks: [['width=0.2', 'length=None', 'axis="y"', 'gap=0.008', 'depth=0.012', 'vary=0.25'],
    (s, a) => make(s, 1, a.length, a.width, a.gap, a.depth, a.vary, a.axis, 'planks()')],
  // fileiras de telhas de `height`, cada uma cobrindo a de baixo; `width` separa as telhas da fileira
  shingles: [['width=0.25', 'height=0.18', 'gap=0.01', 'depth=0.025', 'vary=0.3'],
    (s, a) => make(s, 2, a.width, a.height, a.gap, a.depth, a.vary, 'y', 'shingles()')],
  // pedras/tijolos de `length` x `height` em amarração (cada fileira deslocada meia peça), cantos gastos
  masonry: [['length=0.4', 'height=0.2', 'gap=0.015', 'depth=0.02', 'vary=0.4'],
    (s, a) => make(s, 3, a.length, a.height, a.gap, a.depth, a.vary, 'y', 'masonry()')],
});
