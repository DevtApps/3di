// Compila a árvore de formas em uma função GLSL de distância (SDF):
//   mapAll(p, wantMat) -> M: distância + material.
// O renderer chama mapAll em um único ponto do shader (veja renderer.js), então a cena
// aparece uma só vez no código da GPU, o que mantém a compilação rápida.
import { ScriptError } from './parser.js';
import { isExpr, glslOf } from './expr.js';
import { resolveRig } from './rig.js';
import { polygonGlsl } from './profile.js';
import { Shape, union, isFiniteBB, center, size, unionBB, collectParts, mul3, mulMV, corners, fromPoints, texOffset } from './shapes.js';

export const MAX_LEAVES = 2000;        // primitivas compiladas como código
export const MAX_INSTANCES = 16000;    // primitivas guardadas como dados (BVH)
export const INSTANCE_THRESHOLD = 40;  // abaixo disso, tudo vira código (mais rápido por pixel)

export const GLSL_LIB = /* glsl */ `
// d: distância, c: cor, m: (rough, metal, glow), c2: 2ª cor da textura,
// tx: (tipo, tamanho, eixo (3 = triplanar), relevo) da textura, tp: posição no espaço da textura
// fc: facetas (low poly) e verniz: tamanho + 16 * variação de tom em % + 1024 * verniz em décimos
struct M { float d; vec3 c; vec3 m; vec3 c2; vec4 tx; vec3 tp; float fc; };
float hash31(vec3 p) { p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3)); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float vnoise(vec3 x) {
  vec3 i = floor(x), f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(mix(hash31(i), hash31(i + vec3(1, 0, 0)), f.x), mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), f.x), f.y),
             mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), f.x), mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
  float a = 0.5, s = 0.0;
  for (int i = 0; i < 5; i++) { s += a * vnoise(p); p = p * 2.02 + vec3(1.7, 9.2, 3.1); a *= 0.5; }
  return s / 0.96875;
}
mat3 rotEuler(vec3 deg) {
  vec3 r = radians(deg);
  float cx = cos(r.x), sx = sin(r.x), cy = cos(r.y), sy = sin(r.y), cz = cos(r.z), sz = sin(r.z);
  mat3 Rx = mat3(1.0, 0.0, 0.0, 0.0, cx, sx, 0.0, -sx, cx);
  mat3 Ry = mat3(cy, 0.0, -sy, 0.0, 1.0, 0.0, sy, 0.0, cy);
  mat3 Rz = mat3(cz, sz, 0.0, -sz, cz, 0.0, 0.0, 0.0, 1.0);
  return Rz * Ry * Rx;
}
vec3 axisY(vec3 p, float axis) { return axis < 0.5 ? p.yxz : (axis < 1.5 ? p : p.xzy); }
// Padrões planares (listras, xadrez, tijolos) em coordenadas 2D g: x = fator de mistura (ou
// argamassa), y = variação por tijolo. Servem tanto à projeção normal quanto à triplanar.
vec2 planar(int k, vec2 g, float s) {
  if (k == 4) return vec2(step(0.5, fract(g.y / s)), 0.0);
  if (k == 5) return vec2(mod(floor(g.x / s + 0.5) + floor(g.y / s + 0.5), 2.0), 0.0);
  // tijolos: comprimento s, altura 0.4 s, fiadas desencontradas
  float bh = s * 0.4;
  float row = floor(g.y / bh + 0.02);
  float u = g.x / s + 0.5 * mod(row, 2.0);
  vec2 c = vec2(fract(u) * s, fract(g.y / bh + 0.02) * bh);
  float mortar = min(s, bh) * 0.08;
  return vec2(1.0 - step(mortar, c.x) * step(mortar, c.y), hash31(vec3(floor(u), row, 3.0)));
}
// fator de mistura entre as duas cores (x) e variação por tijolo (y) da textura k no ponto p
vec2 texField(vec3 p, int k, float s, float axis, vec3 n) {
  vec3 q = axisY(p, axis);
  if (k == 1) return vec2(smoothstep(0.3, 0.75, fbm(p / s)), 0.0);
  if (k == 2) {
    // madeira: anéis em volta do eixo, deformados por ruído, mais veios finos
    float r = length(q.xz + (vec2(fbm(q * vec3(1.0, 0.08, 1.0) / s), fbm(q * vec3(1.0, 0.08, 1.0) / s + 7.0)) - 0.5) * s * 3.0) / s;
    float ring = pow(fract(r), 4.0);
    float grain = fbm(q * vec3(25.0, 1.0, 25.0) / s);
    return vec2(clamp(ring * 0.75 + (grain - 0.5) * 0.5 + 0.1, 0.0, 1.0), 0.0);
  }
  if (k == 3) {
    // mármore: veios finos ao longo de uma senoide turbulenta
    float nz = fbm(p / s);
    float v = abs(sin((p.x + p.y * 0.6 + p.z * 0.3) / s * 1.4 + nz * 7.0));
    float vein = 1.0 - smoothstep(0.0, 0.14, v);
    float soft = smoothstep(0.4, 0.9, fbm(p / s * 2.3 + 3.0));
    return vec2(clamp(vein * 0.9 + soft * 0.2, 0.0, 1.0), 0.0);
  }
  if (k == 4 || k == 5 || k == 6) {
    if (axis > 2.5) {
      // triplanar: projeta nos 3 planos e mistura pelo peso da normal (faces x, y e z)
      vec3 w = pow(abs(n), vec3(6.0));
      w /= (w.x + w.y + w.z + 1e-6);
      vec2 f = vec2(0.0);
      if (w.x > 0.02) f += planar(k, p.zy, s) * w.x;
      if (w.y > 0.02) f += planar(k, p.xz, s) * w.y;
      if (w.z > 0.02) f += planar(k, p.xy, s) * w.z;
      return f;
    }
    if (k == 4) return planar(4, vec2(0.0, q.y), s);
    if (k == 5) return vec2(mod(floor(p.x / s + 0.5) + floor(p.y / s + 0.5) + floor(p.z / s + 0.5), 2.0), 0.0);
    return planar(6, vec2(p.x + p.z, p.y), s);
  }
  if (k == 7) return vec2(clamp(q.y / s, 0.0, 1.0), 0.0);           // degradê ao longo do eixo
  if (k == 8) return vec2(fbm(p / s), 0.0);                          // manchas suaves
  if (k == 9) return vec2(fbm(p / s), 0.0);                          // relevo puro (c2 = c1)
  return vec2(0.0);
}
vec3 texColor(vec3 p, vec3 c1, vec3 c2, vec4 tx, vec3 n) {
  int k = int(tx.x + 0.5);
  vec2 f = texField(p, k, tx.y, tx.z, n);
  if (k == 6) {
    vec3 brick = c1 * (0.75 + 0.4 * f.y) * (0.85 + 0.3 * vnoise(p * 40.0 / tx.y));
    return mix(brick, c2, f.x);
  }
  return mix(c1, c2, f.x);
}
// altura da textura (0..1) para o relevo (bump): tijolos e veios ficam rebaixados
float texHeight(vec3 p, vec4 tx, vec3 n) {
  int k = int(tx.x + 0.5);
  if (k == 0 || tx.w <= 0.0 || k == 7) return 0.0;
  vec2 f = texField(p, k, tx.y, tx.z, n);
  if (k == 6) return 1.0 - f.x + 0.12 * f.y;
  if (k == 3) return 1.0 - f.x;
  return f.x;
}
// Relevo em espaço de tela (Mikkelsen): usa as derivadas da altura e da posição, então não
// depende da orientação do sistema de coordenadas da textura.
vec3 bumpNormal(vec3 n, float amp, float dhx, float dhy, vec3 dpx, vec3 dpy, float px) {
  vec3 r1 = cross(dpy, n), r2 = cross(n, dpx);
  float det = dot(dpx, r1);
  if (abs(det) < 1e-14 || length(dpx) > 12.0 * px || length(dpy) > 12.0 * px) return n;
  vec3 g = sign(det) * (dhx * r1 + dhy * r2);
  return normalize(abs(det) * n - amp * g);
}
// extrusão de uma distância 2D d2: altura total 2*hh centrada em 0, quinas arredondadas por r
float sdExt(float d2, float hz, float hh, float r) {
  vec2 w = vec2(d2 + r, abs(hz) - (hh - r));
  return min(max(w.x, w.y), 0.0) + length(max(w, 0.0)) - r;
}
float sdBox(vec3 p, vec3 b) { vec3 q = abs(p) - b; return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0); }
// caixa com arestas chanfradas a 45° (c = largura do chanfro); r arredonda o resultado
float sdCBox(vec3 p, vec3 b, float c) {
  vec3 q = abs(p) - b;
  float d = length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
  float e = max(max(q.x + q.y, q.y + q.z), q.z + q.x) + c;
  return max(d, e * 0.70710678);
}
float sdCyl(vec3 p, float r, float h) { vec2 d = abs(vec2(length(p.xz), p.y)) - vec2(r, h); return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)); }
float sdCone(vec3 p, float h, float r1, float r2) {
  vec2 q = vec2(length(p.xz), p.y);
  vec2 k1 = vec2(r2, h); vec2 k2 = vec2(r2 - r1, 2.0 * h);
  vec2 ca = vec2(q.x - min(q.x, (q.y < 0.0) ? r1 : r2), abs(q.y) - h);
  vec2 cb = q - k1 + k2 * clamp(dot(k1 - q, k2) / dot(k2, k2), 0.0, 1.0);
  float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
  return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
}
float sdTorus(vec3 p, float R, float r) { vec2 q = vec2(length(p.xz) - R, p.y); return length(q) - r; }
float sdCapsule(vec3 p, float r, float a) { p.y -= clamp(p.y, -a, a); return length(p) - r; }
float sdEllipsoid(vec3 p, vec3 r) { float k0 = length(p / r); float k1 = length(p / (r * r)); return k1 > 0.0 ? k0 * (k0 - 1.0) / k1 : -min(r.x, min(r.y, r.z)); }
float sdPyramid(vec3 p, float h) {
  float m2 = h * h + 0.25;
  p.xz = abs(p.xz); p.xz = (p.z > p.x) ? p.zx : p.xz; p.xz -= 0.5;
  vec3 q = vec3(p.z, h * p.y - 0.5 * p.x, h * p.x + 0.5 * p.y);
  float s = max(-q.x, 0.0);
  float t = clamp((q.y - 0.5 * p.z) / (m2 + 0.25), 0.0, 1.0);
  float a = m2 * (q.x + s) * (q.x + s) + q.y * q.y;
  float b = m2 * (q.x + 0.5 * t) * (q.x + 0.5 * t) + (q.y - m2 * t) * (q.y - m2 * t);
  float d2 = min(q.y, -q.x * m2 - q.y * 0.5) > 0.0 ? 0.0 : min(a, b);
  return sqrt((d2 + q.z * q.z) / m2) * sign(max(q.z, -p.y));
}
float sdTriIso(vec2 p, vec2 q) {
  p.x = abs(p.x);
  vec2 a = p - q * clamp(dot(p, q) / dot(q, q), 0.0, 1.0);
  vec2 b = p - q * vec2(clamp(p.x / q.x, 0.0, 1.0), 1.0);
  float s = -sign(q.y);
  vec2 d = min(vec2(dot(a, a), s * (p.x * q.y - p.y * q.x)), vec2(dot(b, b), s * (p.y - q.y)));
  return -sqrt(d.x) * sign(d.y);
}
float sdPrism(vec3 p, float hw, float h, float hd) {
  vec2 w = vec2(sdTriIso(vec2(p.x, h * 0.5 - p.y), vec2(hw, h)), abs(p.z) - hd);
  return min(max(w.x, w.y), 0.0) + length(max(w, 0.0));
}
// cone arredondado de a (raio r1) até b (raio r2): membros, caudas e orelhas que afinam
float sdRoundCone(vec3 p, vec3 a, vec3 b, float r1, float r2) {
  vec3 ba = b - a; float l2 = dot(ba, ba), rr = r1 - r2, a2 = l2 - rr * rr, il2 = 1.0 / l2;
  vec3 pa = p - a; float y = dot(pa, ba), z = y - l2;
  vec3 xv = pa * l2 - ba * y; float x2 = dot(xv, xv), y2 = y * y * l2, z2 = z * z * l2;
  float k = sign(rr) * rr * rr * x2;
  if (sign(z) * a2 * z2 > k) return sqrt(x2 + z2) * il2 - r2;
  if (sign(y) * a2 * y2 < k) return sqrt(x2 + y2) * il2 - r1;
  return (sqrt(x2 * a2 * il2) + y * rr) * il2 - r1;
}
float smin(float a, float b, float k) { float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0); return mix(b, a, h) - k * h * (1.0 - h); }
float smax(float a, float b, float k) { return -smin(-a, -b, k); }
M mU(M a, M b) { if (a.d < b.d) return a; return b; }
M mUs(M a, M b, float k) {
  float h = clamp(0.5 + 0.5 * (b.d - a.d) / k, 0.0, 1.0);
  M r = b; if (h > 0.5) r = a;
  r.d = mix(b.d, a.d, h) - k * h * (1.0 - h); r.c = mix(b.c, a.c, h); r.m = mix(b.m, a.m, h); r.c2 = mix(b.c2, a.c2, h);
  return r;
}
// Junção entre duas formas (merge): perfil 0 = filete redondo, 1 = chanfro, 2 = sulco (emenda
// afundada ao longo da linha de contato). cm: 0 = cores nítidas (cada forma mantém a sua),
// 1 = cores misturadas no filete. sw > 0 pinta a emenda com sc numa faixa de largura ~r.
M mMerge(M a, M b, float r, int prof, int cm, vec3 sc, float sw) {
  M m = b; if (a.d < b.d) m = a;
  float h = clamp(0.5 + 0.5 * (b.d - a.d) / r, 0.0, 1.0);
  if (prof == 0) m.d = mix(b.d, a.d, h) - r * h * (1.0 - h);
  else if (prof == 1) m.d = min(min(a.d, b.d), (a.d + b.d - r) * 0.70710678);
  else m.d = max(min(a.d, b.d), r * 0.5 - length(vec2(a.d, b.d)));
  if (cm == 1) { m.c = mix(b.c, a.c, h); m.m = mix(b.m, a.m, h); }
  if (sw > 0.0) m.c = mix(m.c, sc, 1.0 - smoothstep(sw * 0.5, sw, length(vec2(a.d, b.d))));
  return m;
}
M mS(M a, M b) { a.d = max(a.d, -b.d); return a; }
M mSs(M a, M b, float k) { a.d = smax(a.d, -b.d, k); return a; }
M mI(M a, M b) { a.d = max(a.d, b.d); return a; }
M mIs(M a, M b, float k) { a.d = smax(a.d, b.d, k); return a; }
`;

export function f(x) {
  if (isExpr(x)) return glslOf(x);
  let s = String(+(+x).toFixed(6));
  if (s === '-0') s = '0';
  return /[.e]/.test(s) ? s : s + '.0';
}
const v3 = (v) => `vec3(${v.map(f).join(', ')})`;

const M_FAR = 'M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0)';

const DEFAULT_MAT = { color: [0.6, 0.6, 0.62], rough: 0.6, metal: 0, glow: 0, tex: null, facet: null, coat: 0 };
const MAT_KEYS = ['color', 'rough', 'metal', 'glow', 'tex', 'facet', 'coat'];
// facetas e verniz num float só: tamanho da faceta (< 16 m) + 16 * variação de tom em % (< 64)
// + 1024 * verniz em décimos (0 a 10)
export const facetCode = (fc, coat = 0) => (fc ? fc.size + 16 * Math.round(fc.vary * 100) : 0) + 1024 * Math.round(Math.min(1, Math.max(0, coat ?? 0)) * 10);

// tamanho padrão de cada textura (m) e segunda cor padrão
const TEX_SIZE = { 1: 0.25, 2: 0.06, 3: 0.3, 4: 0.1, 5: 0.25, 6: 0.25, 7: 1, 8: 0.3, 9: 0.1 };
function texParams(tex, color) {
  if (!tex) return { c2: [0, 0, 0], tx: [0, 1, 1, 0] };
  const mortar = [0.69, 0.65, 0.58];
  const k = tex.kind;
  // relevo puro não muda a cor (c2 = c1); o degradê e as manchas clareiam por padrão
  const c2 = tex.c2 ?? (k === 9 ? color : k === 6 ? mortar : k === 8 ? color.map((c) => c * 0.55) : k === 7 ? color.map((c) => Math.min(1, c * 1.6 + 0.04)) : color.map((c) => c * (k === 3 ? 0.25 : k === 5 || k === 4 ? 0.35 : 0.5)));
  return { c2, tx: [k, tex.size ?? TEX_SIZE[k], tex.axis, tex.bump ?? 0] };
}
const v4 = (v) => `vec4(${v.map(f).join(', ')})`;

// Nós caros de avaliar (ruído, repetição, torção) valem uma checagem de caixa antes, mesmo sozinhos:
// um bloco com displace chama fbm (5 oitavas) em todo passo do raio se não for pulado de longe.
const HEAVY = new Set(['displace', 'repeat', 'twist', 'bend', 'taper', 'polar', 'extrude', 'lathe', 'implicit']);
export function isHeavy(sh) {
  return (sh._heavy ??= HEAVY.has(sh.kind) || sh.children.some(isHeavy));
}

// Gera o corpo de mapAll: cada nó vira variáveis do tipo M (distância + material).
class Gen {
  constructor() {
    this.lines = [];
    this.funcs = []; // funções GLSL geradas por forma (polígonos de extrude/lathe)
    this.n = 0;
    this.indent = 1;
  }
  // registra uma função GLSL com nome único e devolve o nome
  fn(prefix, make) {
    const name = `${prefix}${this.n++}`;
    this.funcs.push(make(name));
    return name;
  }
  line(s) { this.lines.push('  '.repeat(this.indent) + s); }
  tmp(prefix) { return `${prefix}${this.n++}`; }
  vec(expr) { const q = this.tmp('q'); this.line(`vec3 ${q} = ${expr};`); return q; }

  leaf(expr, mat) {
    const m = this.tmp('m');
    const full = { ...DEFAULT_MAT, ...Object.fromEntries(Object.entries(mat).filter(([, v]) => v !== null && v !== undefined)) };
    const tp = texParams(full.tex, full.color);
    const texP = full.tex ? mat.texP : 'vec3(0.0)';
    this.line(`M ${m} = M(${expr}, ${v3(full.color)}, ${v3([full.rough, full.metal, full.glow])}, ${v3(tp.c2)}, ${v4(tp.tx)}, ${texP}, ${f(facetCode(full.facet, full.coat))});`);
    return m;
  }

  // altera a distância de um resultado (round, shell, escala)
  mapDist(r, fn) {
    const m = this.tmp('m');
    this.line(`M ${m} = ${r}; ${m}.d = ${fn(`${r}.d`)};`);
    return m;
  }

  combine(a, b, op, k) {
    const out = this.tmp('m');
    const fn = { u: 'mU', s: 'mS', i: 'mI' }[op] + (k ? 's' : '');
    this.line(`M ${out} = ${fn}(${a}, ${b}${k ? `, ${f(k)}` : ''});`);
    return out;
  }

  emit(s, p, mat) {
    const P = s.props;
    const c0 = s.children[0];
    switch (s.kind) {
      case 'box': {
        const h = P.size.map((x) => x / 2 - P.r);
        return this.leaf(P.r ? `sdBox(${p}, ${v3(h)}) - ${f(P.r)}` : `sdBox(${p}, ${v3(h)})`, mat);
      }
      case 'sphere': return this.leaf(`length(${p}) - ${f(P.r)}`, mat);
      case 'cbox': {
        const h = P.size.map((x) => x / 2 - P.r);
        return this.leaf(`sdCBox(${p}, ${v3(h)}, ${f(Math.max(0, P.c - P.r))})${P.r ? ` - ${f(P.r)}` : ''}`, mat);
      }
      case 'cylinder': {
        const rr = P.round;
        return this.leaf(`sdCyl(${p}, ${f(P.r - rr)}, ${f(P.h / 2 - rr)})${rr ? ` - ${f(rr)}` : ''}`, mat);
      }
      case 'cone': return this.leaf(`sdCone(${p}, ${f(P.h / 2)}, ${f(P.r)}, ${f(P.top)})`, mat);
      case 'torus': return this.leaf(`sdTorus(${p}, ${f(P.R)}, ${f(P.r)})`, mat);
      case 'capsule': return this.leaf(`sdCapsule(${p}, ${f(P.r)}, ${f(P.h / 2 - P.r)})`, mat);
      case 'ellipsoid': return this.leaf(`sdEllipsoid(${p}, ${v3(P.radii)})`, mat);
      case 'pyramid': return this.leaf(`sdPyramid((${p} + vec3(0.0, ${f(P.h / 2)}, 0.0)) / ${f(P.w)}, ${f(P.h / P.w)}) * ${f(P.w)}`, mat);
      case 'prism': return this.leaf(`sdPrism(${p}, ${f(P.w / 2)}, ${f(P.h)}, ${f(P.d / 2)})`, mat);
      case 'plane': return this.leaf(`${p}.y`, mat);
      case 'roundcone': return this.leaf(`sdRoundCone(${p}, ${v3(P.a)}, ${v3(P.b)}, ${f(P.r1)}, ${f(P.r2)})`, mat);
      case 'affine': {
        const mi = P.minv;
        const cols = [0, 1, 2].flatMap((c) => [mi[c], mi[3 + c], mi[6 + c]]);
        const r = this.emit(c0, this.vec(`mat3(${cols.map(f).join(', ')}) * (${p} - ${v3(P.t)})`), mat);
        return P.ds === 1 ? r : this.mapDist(r, (d) => `${d} * ${f(P.ds)}`);
      }

      case 'translate': return this.emit(c0, this.vec(`${p} - ${v3(P.v)}`), mat);
      case 'rotate': {
        if (P.angles) return this.emit(c0, this.vec(`${p} * rotEuler(${v3(P.angles)})`), mat);
        const m = P.m;
        const cols = [0, 1, 2].flatMap((c) => [m[c], m[3 + c], m[6 + c]]);
        return this.emit(c0, this.vec(`${p} * mat3(${cols.map(f).join(', ')})`), mat);
      }
      case 'scale': {
        const r = this.emit(c0, this.vec(`${p} / ${v3(P.s)}`), mat);
        const smin = P.s.some(isExpr) ? P.s[0] : Math.min(...P.s);
        return this.mapDist(r, (d) => `${d} * ${f(smin)}`);
      }
      case 'mirror': {
        const q = this.vec(p);
        const c = center(c0.bbox);
        P.axes.forEach((on, i) => {
          if (!on) return;
          const comp = 'xyz'[i];
          this.line(`${q}.${comp} = ${c[i] < 0 ? '-' : ''}abs(${q}.${comp});`);
        });
        return this.emit(c0, q, mat);
      }
      case 'repeat': {
        const sp = P.s.map((x, i) => (P.n[i] > 1 ? x : 1));
        const h = P.n.map((n) => (n - 1) / 2);
        const id = this.tmp('id');
        this.line(`vec3 ${id} = clamp(round(${p} / ${v3(sp)} + ${v3(h)}), vec3(0.0), ${v3(P.n.map((n) => n - 1))});`);
        return this.emit(c0, this.vec(`${p} - ${v3(sp)} * (${id} - ${v3(h)})`), mat);
      }
      case 'twist': {
        const c = this.tmp('c'), sn = this.tmp('s');
        this.line(`float ${c} = cos(${f(P.k)} * ${p}.y), ${sn} = sin(${f(P.k)} * ${p}.y);`);
        const q = this.vec(`vec3(${c} * ${p}.x - ${sn} * ${p}.z, ${p}.y, ${sn} * ${p}.x + ${c} * ${p}.z)`);
        const b = c0.bbox;
        const R = Math.max(Math.abs(b.min[0]), Math.abs(b.max[0]), Math.abs(b.min[2]), Math.abs(b.max[2])) * Math.SQRT2;
        const lip = 1 / Math.sqrt(1 + (P.k * R) ** 2);
        const r = this.emit(c0, q, mat);
        return this.mapDist(r, (d) => `${d} * ${f(lip)}`);
      }
      case 'taper': {
        const ax = P.axis, X = 'xyz';
        const t = this.tmp('tp'), sc = this.tmp('sc');
        this.line(`float ${t} = clamp((${p}.${X[ax]} - ${f(P.lo)}) / ${f(Math.max(1e-6, P.hi - P.lo))}, 0.0, 1.0);`);
        this.line(`float ${sc} = mix(${f(P.bottom)}, ${f(P.top)}, ${t});`);
        const q = this.vec(`vec3(${[0, 1, 2].map((i) => (i === ax ? `${p}.${X[i]}` : `${p}.${X[i]} / ${sc}`)).join(', ')})`);
        const b = c0.bbox;
        const R = Math.max(...[0, 1, 2].filter((i) => i !== ax).map((i) => Math.max(Math.abs(b.min[i]), Math.abs(b.max[i])))) * Math.SQRT2;
        const smin = Math.min(P.top, P.bottom), slope = Math.abs(P.top - P.bottom) / Math.max(1e-6, P.hi - P.lo);
        const lip = smin / Math.sqrt(1 + ((slope * R) / smin) ** 2);
        return this.mapDist(this.emit(c0, q, mat), (d) => `${d} * ${f(lip)}`);
      }
      case 'bend': {
        const X = 'xyz', c = this.tmp('c'), sn = this.tmp('s');
        const u = `(${p}.${X[P.axis]} - ${f(P.pivot)})`, v = `${p}.${X[P.toward]}`;
        this.line(`float ${c} = cos(${f(P.k)} * ${u}), ${sn} = sin(${f(P.k)} * ${u});`);
        const q = this.vec(`vec3(${[0, 1, 2].map((i) => (i === P.axis ? `${c} * ${u} - ${sn} * ${v} + ${f(P.pivot)}` : i === P.toward ? `${sn} * ${u} + ${c} * ${v}` : `${p}.${X[i]}`)).join(', ')})`);
        const b = c0.bbox;
        const R = Math.hypot(Math.max(Math.abs(b.min[P.axis] - P.pivot), Math.abs(b.max[P.axis] - P.pivot)), Math.max(Math.abs(b.min[P.toward]), Math.abs(b.max[P.toward])));
        return this.mapDist(this.emit(c0, q, mat), (d) => `${d} / sqrt(1.0 + ${f((P.k * R) ** 2)})`);
      }
      case 'shear': {
        const q = this.vec(`vec3(${p}.x - ${f(P.sx)} * (${p}.y - ${f(P.y0)}), ${p}.y, ${p}.z - ${f(P.sz)} * (${p}.y - ${f(P.y0)}))`);
        return this.mapDist(this.emit(c0, q, mat), (d) => `${d} / sqrt(${f(1 + P.sx * P.sx + P.sz * P.sz)})`);
      }
      case 'polar': {
        const sec = this.tmp('sec'), an = this.tmp('an'), rr = this.tmp('rr');
        this.line(`float ${sec} = ${f((2 * Math.PI) / P.n)}, ${rr} = length(${p}.xz);`);
        this.line(`float ${an} = mod(atan(${p}.z, ${p}.x) + 0.5 * ${sec}, ${sec}) - 0.5 * ${sec};`);
        return this.emit(c0, this.vec(`vec3(${rr} * cos(${an}), ${p}.y, ${rr} * sin(${an}))`), mat);
      }
      case 'elongate': {
        const hv = v3(P.h);
        return this.emit(c0, this.vec(`${p} - clamp(${p}, -${hv}, ${hv})`), mat);
      }
      case 'extrude': {
        const name = this.fn('sdPoly', (n) => polygonGlsl(n, P.pts));
        const d2 = P.axis === 'z' ? `${name}(${p}.xy)` : `${name}(${p}.xz)`;
        return this.leaf(`sdExt(${d2}, ${P.axis === 'z' ? `${p}.z` : `${p}.y`}, ${f(P.h / 2)}, ${f(P.r)})`, mat);
      }
      case 'implicit': {
        // a fórmula vira uma função GLSL de ip (x, y, z); o resultado é recortado pela caixa de tamanho `size`
        const name = this.fn('sdImpl', (n) => `float ${n}(vec3 ip) {\n  return ${glslOf(P.f)};\n}`);
        return this.leaf(`max(${name}(${p}) * ${f(P.lip)}, sdBox(${p}, ${v3(P.half)}))`, mat);
      }
      case 'lathe': {
        const name = this.fn('sdPoly', (n) => polygonGlsl(n, P.pts));
        return this.leaf(`${name}(vec2(length(${p}.xz), ${p}.y))`, mat);
      }
      case 'round': return this.mapDist(this.emit(c0, p, mat), (d) => `${d} - ${f(P.r)}`);
      case 'shell': return this.mapDist(this.emit(c0, p, mat), (d) => `abs(${d}) - ${f(P.t / 2)}`);
      case 'displace': {
        // ruído deforma a superfície; o fator reduz o passo para o raymarch não atravessar
        const lip = 1 / (1 + (2.5 * P.amt) / P.size);
        return this.mapDist(this.emit(c0, p, mat),
          (d) => `(${d} + ${f(P.amt)} * (fbm(${p} / ${f(P.size)}) * 2.0 - 1.0)) * ${f(lip)}`);
      }
      case 'material': {
        const merged = { ...mat };
        // a cor mais interna vence: .color() externo só pinta o que ainda não tem cor
        for (const k of MAT_KEYS) if (P[k] !== null && P[k] !== undefined) merged[k] = P[k];
        // a textura usa o sistema de coordenadas do nó onde foi aplicada
        if (P.tex) {
          const off = texOffset(P.tex);
          merged.texP = off ? `(${p} - ${v3(off)})` : p;
        }
        return this.emit(c0, p, merged);
      }
      case 'label': return this.emit(c0, p, mat);
      case 'paint': {
        // pinta a superfície da base onde ela está dentro da região (a geometria não muda);
        // a região só é avaliada perto da superfície
        const a = this.emit(c0, p, mat);
        const w = this.tmp('w');
        this.line(`if (${a}.d < ${f(P.k + 0.06 + 2 * Math.abs(P.relief ?? 0))}) {`);
        this.indent++;
        const r = this.emit(s.children[1], p, mat);
        this.line(`float ${w} = 1.0 - smoothstep(${f(-P.k)}, ${f(P.k + 1e-5)}, ${r}.d);`);
        // o relevo inclina o campo (até 0,75 relief/k a mais); dividir mantém o passo do raio seguro
        if (P.relief) this.line(`${a}.d -= ${f(P.relief)} * ${w};`);
        this.line(`${a}.c = mix(${a}.c, ${r}.c, ${w}); ${a}.m = mix(${a}.m, ${r}.m, ${w});`);
        this.line(`if (${w} > 0.5) { ${a}.c2 = ${r}.c2; ${a}.tx = ${r}.tx; ${a}.tp = ${r}.tp; ${a}.fc = ${r}.fc; }`);
        this.indent--;
        this.line('}');
        return a;
      }

      case 'union': return this.emitUnion(s, p, mat);
      case 'merge': {
        let acc = this.emit(s.children[0], p, mat);
        const prof = { round: 0, chamfer: 1, groove: 2 }[P.profile];
        for (const c of s.children.slice(1)) {
          const b = this.emit(c, p, mat);
          const out = this.tmp('m');
          this.line(`M ${out} = mMerge(${acc}, ${b}, ${f(P.r)}, ${prof}, ${P.colors === 'blend' ? 1 : 0}, ${v3(P.seam ?? [0, 0, 0])}, ${f(P.seam ? P.seamWidth : 0)});`);
          acc = out;
        }
        return acc;
      }
      case 'subtract': {
        const a = this.emit(s.children[0], p, mat);
        const b = this.emit(s.children[1], p, mat);
        return this.combine(a, b, 's', P.k);
      }
      case 'intersect': {
        let acc = this.emit(s.children[0], p, mat);
        for (const c of s.children.slice(1)) acc = this.combine(acc, this.emit(c, p, mat), 'i', P.k);
        return acc;
      }
    }
    throw new Error(`compilador: tipo desconhecido ${s.kind}`);
  }

  emitUnion(s, p, mat) {
    const k = s.props.k;
    if (k) {
      let acc = this.emit(s.children[0], p, mat);
      for (const c of s.children.slice(1)) acc = this.combine(acc, this.emit(c, p, mat), 'u', k);
      return acc;
    }
    // União simples: pula filhos complexos cuja caixa está mais longe que o melhor resultado.
    const acc = this.tmp('u');
    this.line(`M ${acc} = ${M_FAR};`);
    for (const c of s.children) {
      const b = c.bbox;
      const bounded = (c.leaves >= 3 || isHeavy(c)) && isFiniteBB(b) && !c.animated;
      if (bounded) {
        const half = size(b).map((x) => x / 2 + 0.01);
        this.line(`if (sdBox(${p} - ${v3(center(b))}, ${v3(half)}) < ${acc}.d) {`);
      } else {
        // bloco próprio: os temporários de cada filho morrem ao fim dele (compila mais rápido)
        this.line('{');
      }
      this.indent++;
      const d = this.emit(c, p, mat);
      this.line(`${acc} = mU(${acc}, ${d});`);
      this.indent--;
      this.line('}');
    }
    return acc;
  }
}

// ---------- primitivas como dados (BVH) ----------

const PRIM_IDS = { box: 1, sphere: 2, cylinder: 3, cone: 4, torus: 5, capsule: 6, ellipsoid: 7, pyramid: 8, prism: 9 };

function primParams(s) {
  const P = s.props;
  switch (s.kind) {
    case 'box': return [...P.size.map((x) => x / 2 - P.r), P.r];
    case 'sphere': return [P.r, 0, 0, 0];
    case 'cylinder': return [P.r - P.round, P.h / 2 - P.round, P.round, 0];
    case 'cone': return [P.h / 2, P.r, P.top, 0];
    case 'torus': return [P.R, P.r, 0, 0];
    case 'capsule': return [P.r, P.h / 2 - P.r, 0, 0];
    case 'ellipsoid': return [...P.radii, 0];
    case 'pyramid': return [P.w, P.h, 0, 0];
    case 'prism': return [P.w / 2, P.h, P.d / 2, 0];
  }
}

const IDENT = [1, 0, 0, 0, 1, 0, 0, 0, 1];

export function inv3(m) {
  const [a, b, c, d, e, g, h, i, k] = m;
  const A = e * k - g * i, B = -(d * k - g * h), C = d * i - e * h;
  const det = a * A + b * B + c * C;
  return [A, -(b * k - c * i), b * g - c * e, B, a * k - c * h, -(a * g - c * d), C, -(a * i - b * h), a * e - b * d].map((x) => x / det);
}

const mergeMat = (mat, P) => {
  const out = { ...mat };
  for (const k of MAT_KEYS) if (P[k] !== null && P[k] !== undefined) out[k] = P[k];
  return out;
};

// Separa a cena em primitivas simples (viram dados) e subárvores complexas (viram código).
export function splitScene(shapes) {
  const instances = [], residual = [];
  const visit = (s, m, t, ds, mat) => {
    const c0 = s.children[0];
    switch (s.selfAnimated ? 'animated' : s.kind) {
      case 'translate': {
        const mv = mulMV(m, s.props.v);
        visit(c0, m, t.map((v, i) => v + mv[i]), ds, mat);
        return;
      }
      case 'rotate': visit(c0, mul3(m, s.props.m), t, ds, mat); return;
      case 'scale': {
        const S = s.props.s;
        visit(c0, mul3(m, [S[0], 0, 0, 0, S[1], 0, 0, 0, S[2]]), t, ds * Math.min(...S), mat);
        return;
      }
      case 'material': {
        const merged = mergeMat(mat, s.props);
        if (s.props.tex) {
          // o início do degradê desloca a origem da textura (no espaço do nó onde ela foi aplicada)
          const off = texOffset(s.props.tex);
          const shift = off ? mulMV(m, off) : null;
          merged.texFrame = { m, t: shift ? t.map((v, i) => v + shift[i]) : t };
        }
        visit(c0, m, t, ds, merged);
        return;
      }
      case 'label': visit(c0, m, t, ds, mat); return;
      case 'union':
        if (!s.props.k) { s.children.forEach((c) => visit(c, m, t, ds, mat)); return; }
        break;
    }
    if (PRIM_IDS[s.kind]) { instances.push({ s, m, t, ds, mat }); return; }
    // subárvore complexa: reaplica transformação e material acumulados como nós
    let node = s;
    const { texFrame, ...matProps } = mat;
    if (Object.keys(matProps).length) node = new Shape('material', { color: null, rough: null, metal: null, glow: null, tex: null, facet: null, coat: null, ...matProps }, [node]);
    const isIdent = m.every((v, i) => Math.abs(v - IDENT[i]) < 1e-12) && t.every((v) => v === 0);
    if (!isIdent) node = new Shape('affine', { m, t, minv: inv3(m), ds }, [node]);
    residual.push(node);
  };
  shapes.forEach((s) => visit(s, IDENT, [0, 0, 0], 1, {}));
  return { instances, residual };
}

const INST_W = 11; // texels por instância
const BVH_W = 2;  // texels por nó
const LEAF_SIZE = 4;

function packInstances(list) {
  const data = new Float32Array(list.length * INST_W * 4);
  list.forEach((it, n) => {
    const o = n * INST_W * 4;
    const pr = primParams(it.s);
    const mi = inv3(it.m);
    const mt = mulMV(mi, it.t);
    const { texFrame, ...matProps } = it.mat;
    const full = { ...DEFAULT_MAT, ...matProps };
    const tp = texParams(full.tex, full.color);
    data.set([PRIM_IDS[it.s.kind], pr[0], pr[1], pr[2]], o);
    data.set([pr[3], it.ds, tp.tx[3], facetCode(full.facet, full.coat)], o + 4);
    for (let r = 0; r < 3; r++) data.set([mi[r * 3], mi[r * 3 + 1], mi[r * 3 + 2], -mt[r]], o + 8 + r * 4);
    data.set([...full.color, full.rough], o + 20);
    data.set([full.metal, full.glow, tp.tx[0], tp.tx[1]], o + 24);
    data.set([...tp.c2, tp.tx[2]], o + 28);
    // linhas da transformação mundo -> espaço da textura
    const tf = texFrame ?? { m: IDENT, t: [0, 0, 0] };
    const ti = inv3(tf.m), tt = mulMV(ti, tf.t);
    for (let r = 0; r < 3; r++) data.set([ti[r * 3], ti[r * 3 + 1], ti[r * 3 + 2], -tt[r]], o + 32 + r * 4);
  });
  return data;
}

function buildBVH(instances) {
  const items = instances.map((it, idx) => {
    const b = fromPoints(corners(it.s.bbox).map((c) => mulMV(it.m, c).map((v, i) => v + it.t[i])));
    return { b, c: center(b), idx };
  });
  const nodes = [], order = [];
  const build = (list) => {
    const ni = nodes.length;
    nodes.push(null);
    const b = unionBB(list.map((x) => x.b));
    if (list.length <= LEAF_SIZE) {
      nodes[ni] = { b, a: order.length, count: list.length };
      order.push(...list.map((x) => x.idx));
      return ni;
    }
    const cb = fromPoints(list.map((x) => x.c));
    const ext = size(cb);
    const axis = ext.indexOf(Math.max(...ext));
    list.sort((p, q) => p.c[axis] - q.c[axis]);
    const mid = list.length >> 1;
    build(list.slice(0, mid));
    const right = build(list.slice(mid));
    nodes[ni] = { b, a: right, count: 0 };
    return ni;
  };
  build(items);
  const data = new Float32Array(nodes.length * BVH_W * 4);
  nodes.forEach((n, i) => {
    data.set([...n.b.min, n.a], i * 8);
    data.set([...n.b.max, n.count], i * 8 + 4);
  });
  return { bvh: data, nodeCount: nodes.length, order };
}

const GLSL_BVH = /* glsl */ `
uniform highp sampler2D uInst;
uniform highp sampler2D uBvh;
float instD(vec3 p, int i) {
  vec4 a = texelFetch(uInst, ivec2(0, i), 0);
  vec4 b = texelFetch(uInst, ivec2(1, i), 0);
  vec4 r0 = texelFetch(uInst, ivec2(2, i), 0);
  vec4 r1 = texelFetch(uInst, ivec2(3, i), 0);
  vec4 r2 = texelFetch(uInst, ivec2(4, i), 0);
  vec3 q = vec3(dot(r0.xyz, p) + r0.w, dot(r1.xyz, p) + r1.w, dot(r2.xyz, p) + r2.w);
  int t = int(a.x);
  float d;
  if (t == 1) d = sdBox(q, a.yzw) - b.x;
  else if (t == 2) d = length(q) - a.y;
  else if (t == 3) d = sdCyl(q, a.y, a.z) - a.w;
  else if (t == 4) d = sdCone(q, a.y, a.z, a.w);
  else if (t == 5) d = sdTorus(q, a.y, a.z);
  else if (t == 6) d = sdCapsule(q, a.y, a.z);
  else if (t == 7) d = sdEllipsoid(q, a.yzw);
  else if (t == 8) d = sdPyramid((q + vec3(0.0, a.z * 0.5, 0.0)) / a.y, a.z / a.y) * a.y;
  else d = sdPrism(q, a.y, a.z, a.w);
  return d * b.y;
}
float boxDist(vec3 p, int ni) {
  vec3 mn = texelFetch(uBvh, ivec2(0, ni), 0).xyz;
  vec3 mx = texelFetch(uBvh, ivec2(1, ni), 0).xyz;
  return sdBox(p - (mn + mx) * 0.5, (mx - mn) * 0.5);
}
// Percorre a BVH a partir da melhor distância já conhecida; devolve a nova melhor e o índice atingido.
float bvhD(vec3 p, float best, out int hit) {
  hit = -1;
  int stack[40];
  int sp = 0;
  int ni = 0;
  if (boxDist(p, 0) >= best) return best;
  for (int it = 0; it < 2048; it++) {
    vec4 a = texelFetch(uBvh, ivec2(0, ni), 0);
    int cnt = int(texelFetch(uBvh, ivec2(1, ni), 0).w);
    if (cnt > 0) {
      int st = int(a.w);
      for (int k = 0; k < cnt; k++) {
        float d = instD(p, st + k);
        if (d < best) { best = d; hit = st + k; }
      }
    } else {
      int l = ni + 1, r = int(a.w);
      float dl = boxDist(p, l), dr = boxDist(p, r);
      int nearN = dl < dr ? l : r, farN = dl < dr ? r : l;
      float dn = min(dl, dr), df = max(dl, dr);
      if (df < best && sp < 40) stack[sp++] = farN;
      if (dn < best) { ni = nearN; continue; }
    }
    // desempilha o próximo nó que ainda pode conter algo mais perto
    bool found = false;
    while (sp > 0) {
      int c = stack[--sp];
      if (boxDist(p, c) < best) { ni = c; found = true; break; }
    }
    if (!found) break;
  }
  return best;
}
`;

export function compileScene(scene) {
  // partes presas a ossos recebem a pose do esqueleto
  const shapes = resolveRig(scene.shapes);
  if (!shapes.length) {
    throw new ScriptError('nada para mostrar', null, 'termine o script com show(forma1, forma2, ...)');
  }
  const { instances, residual } = splitScene(shapes);
  const useBVH = instances.length >= INSTANCE_THRESHOLD;
  if (instances.length > MAX_INSTANCES) {
    throw new ScriptError(`cena grande demais (${instances.length} primitivas, máximo ${MAX_INSTANCES})`, null,
      'use .repeat() ou .mirror(): eles não custam primitivas extras');
  }
  const codeRoot = useBVH ? (residual.length ? union(residual) : null) : union(shapes);
  const codeLeaves = codeRoot ? codeRoot.leaves : 0;
  if (codeLeaves > MAX_LEAVES) {
    throw new ScriptError(`cena complexa demais (${codeLeaves} primitivas dentro de booleanas/smooth/mirror, máximo ${MAX_LEAVES})`, null,
      'subtrações e uniões suaves viram código no shader; prefira group() simples quando possível');
  }

  let mBody = `  return ${M_FAR};`;
  let funcs = '';
  if (codeRoot) {
    const Mg = new Gen();
    const mOut = Mg.emit(codeRoot, 'p', {});
    mBody = `${Mg.lines.join('\n')}\n  return ${mOut};`;
    funcs = Mg.funcs.length ? `\n${Mg.funcs.join('\n')}\n` : '';
  }

  let glsl, data = null;
  if (useBVH) {
    const { bvh, nodeCount, order } = buildBVH(instances);
    data = { inst: packInstances(order.map((i) => instances[i])), instCount: instances.length, bvh, nodeCount, instW: INST_W, bvhW: BVH_W };
    glsl = `${GLSL_LIB}${GLSL_BVH}${funcs}
M codeM(vec3 p) {
${mBody}
}
M mapAll(vec3 p, bool wantMat) {
  M r = codeM(p);
  int hit;
  r.d = bvhD(p, r.d, hit);
  if (hit >= 0 && wantMat) {
    vec4 bb = texelFetch(uInst, ivec2(1, hit), 0);
    vec4 c = texelFetch(uInst, ivec2(5, hit), 0);
    vec4 e = texelFetch(uInst, ivec2(6, hit), 0);
    vec4 c2 = texelFetch(uInst, ivec2(7, hit), 0);
    vec4 t0 = texelFetch(uInst, ivec2(8, hit), 0), t1 = texelFetch(uInst, ivec2(9, hit), 0), t2 = texelFetch(uInst, ivec2(10, hit), 0);
    vec3 tp = vec3(dot(t0.xyz, p) + t0.w, dot(t1.xyz, p) + t1.w, dot(t2.xyz, p) + t2.w);
    r = M(r.d, c.rgb, vec3(c.a, e.x, e.y), c2.rgb, vec4(e.z, e.w, c2.a, bb.z), tp, bb.w);
  }
  return r;
}
`;
  } else {
    glsl = `${GLSL_LIB}${funcs}
M mapAll(vec3 p, bool wantMat) {
${mBody}
}
`;
  }

  const finite = shapes.filter((s) => isFiniteBB(s.bbox)).map((s) => s.bbox);
  const bbox = finite.length ? unionBB(finite) : { min: [-1, 0, -1], max: [1, 1, 1] };
  return {
    glsl,
    data,
    bbox,
    hasPlane: shapes.some((s) => !isFiniteBB(s.bbox)),
    animated: glsl.includes('uTime'),
    leaves: codeLeaves + (useBVH ? instances.length : 0),
    codeLeaves,
    instances: useBVH ? instances.length : 0,
    parts: collectParts(shapes),
  };
}
