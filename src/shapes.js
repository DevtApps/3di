// Modelo de cena: formas imutáveis, transformações, layout semântico e caixas envolventes.
import { ScriptError } from './parser.js';
import { Native, bindArgs, didYouMean, num, numT, vec3, tuple, typeName, fmtNum } from './runtime.js';
import { isExpr, val0, sym as esym } from './expr.js';

export const INF = 1e4;

export class Shape {
  constructor(kind, props = {}, children = []) {
    this.kind = kind;
    this.props = props;
    this.children = children;
    this._bb = null;
    this._leaves = null;
  }
  get bbox() { return (this._bb ??= computeBBox(this)); }
  // as próprias propriedades dependem de time?
  get selfAnimated() {
    const p = this.props;
    return [p.v, p.angles, p.s].some((a) => Array.isArray(a) && a.some(isExpr)) || isExpr(p.glow);
  }
  get animated() {
    return (this._anim ??= this.selfAnimated || this.children.some((c) => c.animated));
  }
  get leaves() {
    if (this._leaves === null) {
      this._leaves = this.children.length ? this.children.reduce((n, c) => n + c.leaves, 0) : 1;
    }
    return this._leaves;
  }
  describe() {
    const b = this.bbox;
    const name = this.kind === 'label' ? this.props.name : '';
    if (!isFiniteBB(b)) return `<forma ${name}${name ? ' ' : ''}infinita>`;
    const s = size(b).map(fmtNum).join(' x ');
    const c = center(b).map(fmtNum).join(', ');
    return `<forma ${name}${name ? ' ' : ''}${s} centro (${c})>`;
  }
}

// ---------- caixas envolventes ----------

const bb = (min, max) => ({ min, max });
const isFiniteBB = (b) => b.min.every((v) => v > -INF / 2) && b.max.every((v) => v < INF / 2);
const center = (b) => [0, 1, 2].map((i) => (b.min[i] + b.max[i]) / 2);
const size = (b) => [0, 1, 2].map((i) => b.max[i] - b.min[i]);
const sym = (x, y, z) => bb([-x, -y, -z], [x, y, z]);
const expand = (b, r) => bb(b.min.map((v) => v - r), b.max.map((v) => v + r));

function corners(b) {
  const out = [];
  for (let i = 0; i < 8; i++) out.push([i & 1 ? b.max[0] : b.min[0], i & 2 ? b.max[1] : b.min[1], i & 4 ? b.max[2] : b.min[2]]);
  return out;
}

function fromPoints(pts) {
  const min = [Infinity, Infinity, Infinity], max = [-Infinity, -Infinity, -Infinity];
  for (const p of pts) for (let i = 0; i < 3; i++) { min[i] = Math.min(min[i], p[i]); max[i] = Math.max(max[i], p[i]); }
  return bb(min, max);
}

function unionBB(list) {
  return bb([0, 1, 2].map((i) => Math.min(...list.map((b) => b.min[i]))), [0, 1, 2].map((i) => Math.max(...list.map((b) => b.max[i]))));
}

export function mulMV(m, v) {
  return [0, 1, 2].map((r) => m[r * 3] * v[0] + m[r * 3 + 1] * v[1] + m[r * 3 + 2] * v[2]);
}

// Caixa de s depois de p -> m*p + t, empurrando a transformação até as folhas.
// Girar a caixa já girada do filho infla a caixa a cada nível; assim ela fica justa.
function transformedBBox(s, m, t) {
  switch (s.kind) {
    case 'translate': {
      const mv = mulMV(m, s.props.v.map(val0));
      return transformedBBox(s.children[0], m, t.map((v, i) => v + mv[i]));
    }
    case 'rotate': return transformedBBox(s.children[0], mul3(m, s.props.m), t);
    case 'scale': {
      const S = s.props.s.map(val0);
      return transformedBBox(s.children[0], mul3(m, [S[0], 0, 0, 0, S[1], 0, 0, 0, S[2]]), t);
    }
    case 'affine': {
      const mv = mulMV(m, s.props.t);
      return transformedBBox(s.children[0], mul3(m, s.props.m), t.map((v, i) => v + mv[i]));
    }
    case 'union': return unionBB(s.children.map((c) => transformedBBox(c, m, t)));
    case 'subtract': case 'material': case 'label': case 'bound':
      return transformedBBox(s.children[0], m, t);
  }
  return fromPoints(corners(s.bbox).map((c) => mulMV(m, c).map((v, i) => v + t[i])));
}

function clampInf(b) {
  return bb(b.min.map((v) => Math.max(v, -INF)), b.max.map((v) => Math.min(v, INF)));
}

function computeBBox(s) {
  const p = s.props;
  const c0 = s.children[0];
  switch (s.kind) {
    case 'box': return sym(p.size[0] / 2, p.size[1] / 2, p.size[2] / 2);
    case 'sphere': return sym(p.r, p.r, p.r);
    case 'cylinder': return sym(p.r, p.h / 2, p.r);
    case 'cone': { const r = Math.max(p.r, p.top); return sym(r, p.h / 2, r); }
    case 'torus': return sym(p.R + p.r, p.r, p.R + p.r);
    case 'capsule': return sym(p.r, p.h / 2, p.r);
    case 'ellipsoid': return sym(...p.radii);
    case 'pyramid': return sym(p.w / 2, p.h / 2, p.w / 2);
    case 'prism': return sym(p.w / 2, p.h / 2, p.d / 2);
    case 'plane': return bb([-INF, -INF, -INF], [INF, 0, INF]);
    case 'affine': return transformedBBox(c0, p.m, p.t);
    case 'union': return unionBB(s.children.map((c) => c.bbox));
    case 'subtract': return c0.bbox;
    case 'intersect': {
      const bs = s.children.map((c) => c.bbox);
      return bb([0, 1, 2].map((i) => Math.max(...bs.map((b) => b.min[i]))), [0, 1, 2].map((i) => Math.min(...bs.map((b) => b.max[i]))));
    }
    case 'translate': return clampInf(bb(c0.bbox.min.map((v, i) => v + val0(p.v[i])), c0.bbox.max.map((v, i) => v + val0(p.v[i]))));
    case 'rotate': {
      if (!isFiniteBB(c0.bbox)) return bb([-INF, -INF, -INF], [INF, INF, INF]);
      return transformedBBox(c0, p.m, [0, 0, 0]);
    }
    case 'scale': return clampInf(bb(c0.bbox.min.map((v, i) => v * val0(p.s[i])), c0.bbox.max.map((v, i) => v * val0(p.s[i]))));
    case 'displace': return expand(c0.bbox, p.amt);
    case 'mirror': {
      const b = c0.bbox;
      const min = [...b.min], max = [...b.max];
      for (let i = 0; i < 3; i++) {
        if (!p.axes[i]) continue;
        min[i] = Math.min(b.min[i], -b.max[i]);
        max[i] = Math.max(b.max[i], -b.min[i]);
      }
      return bb(min, max);
    }
    case 'round': return expand(c0.bbox, p.r);
    case 'shell': return expand(c0.bbox, p.t / 2);
    case 'twist': {
      const b = c0.bbox;
      const R = Math.max(...corners(b).map((c) => Math.hypot(c[0], c[2])));
      return bb([-R, b.min[1], -R], [R, b.max[1], R]);
    }
    case 'repeat': {
      const b = c0.bbox;
      const ext = p.n.map((n, i) => ((n - 1) * p.s[i]) / 2);
      return bb(b.min.map((v, i) => v - ext[i]), b.max.map((v, i) => v + ext[i]));
    }
    case 'material':
    case 'label':
    case 'bound':
      return c0.bbox;
  }
  throw new Error(`bbox: tipo desconhecido ${s.kind}`);
}

// ---------- construtores internos ----------

export function translate(s, v) {
  if (v.every((x) => !isExpr(x) && Math.abs(x) < 1e-9)) return s;
  if (s.kind === 'translate') return translate(s.children[0], v.map((x, i) => esym('+', x, s.props.v[i])));
  return new Shape('translate', { v }, [s]);
}

export function rotMatrix(ax, ay, az) {
  const [x, y, z] = [ax, ay, az].map((d) => (d * Math.PI) / 180);
  const cx = Math.cos(x), sx = Math.sin(x), cy = Math.cos(y), sy = Math.sin(y), cz = Math.cos(z), sz = Math.sin(z);
  const Rx = [1, 0, 0, 0, cx, -sx, 0, sx, cx];
  const Ry = [cy, 0, sy, 0, 1, 0, -sy, 0, cy];
  const Rz = [cz, -sz, 0, sz, cz, 0, 0, 0, 1];
  return mul3(Rz, mul3(Ry, Rx));
}

function mul3(a, b) {
  const r = new Array(9).fill(0);
  for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) for (let k = 0; k < 3; k++) r[i * 3 + j] += a[i * 3 + k] * b[k * 3 + j];
  return r;
}

function pivotOf(s, pivot) {
  if (pivot !== null && pivot !== undefined) return vec3(pivot, 'pivot');
  return isFiniteBB(s.bbox) ? center(s.bbox) : [0, 0, 0];
}

export function aroundPivot(s, c, wrap) {
  const neg = c.map((x) => -x);
  return translate(wrap(translate(s, neg)), c);
}

// cápsula de a até b (membros de personagens, canos, galhos...)
export function segmentShape(a, b, r) {
  const d = b.map((v, i) => v - a[i]);
  const len = Math.hypot(...d);
  const mid = a.map((v, i) => (v + b[i]) / 2);
  if (len < 1e-9) return translate(new Shape('sphere', { r }), mid);
  const n = d.map((v) => v / len);
  const ax = (Math.asin(Math.max(-1, Math.min(1, n[2]))) * 180) / Math.PI;
  const az = (Math.atan2(-n[0], n[1]) * 180) / Math.PI;
  const cap = new Shape('capsule', { r, h: len + 2 * r });
  return translate(new Shape('rotate', { m: rotMatrix(ax, 0, az) }, [cap]), mid);
}

export function union(list, k = 0) {
  if (list.length === 1) return list[0];
  return new Shape('union', { k }, list);
}

function flatten(values, what, out = []) {
  for (const v of values) {
    if (v === null || v === undefined) continue;
    if (Array.isArray(v)) flatten(v, what, out);
    else if (v instanceof Shape) out.push(v);
    else {
      throw new ScriptError(`${what} espera formas, recebeu ${typeName(v)}`, null,
        typeof v === 'number' ? 'para posicionar use .at(x, y, z)' : undefined);
    }
  }
  return out;
}

function needFinite(s, what) {
  if (!isFiniteBB(s.bbox)) {
    throw new ScriptError(`${what} não funciona com formas infinitas (plane)`, null,
      'mostre o plane separadamente: show(plane(), objeto)');
  }
}

function xyzArgs(a, what) {
  if (Array.isArray(a.x)) return vec3(a.x, what);
  return [num(a.x, `${what} x`), num(a.y, `${what} y`), num(a.z, `${what} z`)];
}

// como xyzArgs, mas aceita valores animados (time)
function xyzArgsT(a, what) {
  const v = Array.isArray(a.x) ? a.x : [a.x, a.y, a.z];
  if (v.length !== 3) throw new ScriptError(`${what} espera (x, y, z)`, null);
  return v.map((x, i) => numT(x, `${what} ${'xyz'[i]}`));
}

// ---------- cores e materiais ----------

const COLORS = {
  red: '#d63c3c', vermelho: '#d63c3c',
  green: '#4caf50', verde: '#4caf50',
  blue: '#3b6fd6', azul: '#3b6fd6',
  yellow: '#f2c53d', amarelo: '#f2c53d',
  orange: '#ee8a2e', laranja: '#ee8a2e',
  purple: '#8e5ad6', roxo: '#8e5ad6',
  pink: '#ec7fb0', rosa: '#ec7fb0',
  cyan: '#3cc8d6', ciano: '#3cc8d6',
  white: '#f2f2f2', branco: '#f2f2f2',
  black: '#1c1c1c', preto: '#1c1c1c',
  gray: '#8a8a8a', grey: '#8a8a8a', cinza: '#8a8a8a',
  lightgray: '#c8c8c8', darkgray: '#444444',
  brown: '#7a4e2d', marrom: '#7a4e2d',
  wood: '#a0703f', madeira: '#a0703f',
  darkwood: '#5c3a1e',
  gold: '#e0b040', ouro: '#e0b040',
  silver: '#c0c4c8', prata: '#c0c4c8',
  copper: '#c47a4a', cobre: '#c47a4a',
  grass: '#5d9b3a', grama: '#5d9b3a',
  leaf: '#3f8a35', folha: '#3f8a35',
  stone: '#9a968e', pedra: '#9a968e',
  brick: '#a8503a', tijolo: '#a8503a',
  sand: '#dcc79a', areia: '#dcc79a',
  water: '#3a8fc4', agua: '#3a8fc4', 'água': '#3a8fc4',
  skin: '#e8b996', pele: '#e8b996',
  concrete: '#b5b2aa', concreto: '#b5b2aa',
  snow: '#fbfbff', neve: '#fbfbff',
};

const srgbToLinear = (c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);

export function parseColor(v) {
  if (Array.isArray(v) && v.length === 3) {
    const c = vec3(v, 'cor');
    const scale = c.some((x) => x > 1) ? 255 : 1;
    return c.map((x) => srgbToLinear(Math.min(1, Math.max(0, x / scale))));
  }
  if (typeof v === 'string') {
    let hex = COLORS[v.toLowerCase()] ?? v;
    if (/^#?[0-9a-f]{3}$/i.test(hex)) hex = hex.replace(/^#?(.)(.)(.)$/, '#$1$1$2$2$3$3');
    const m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex);
    if (m) return [m[1], m[2], m[3]].map((h) => srgbToLinear(parseInt(h, 16) / 255));
    throw new ScriptError(`cor desconhecida '${v}'`, null,
      didYouMean(v, Object.keys(COLORS)) ?? 'use um nome (red, wood...), "#rrggbb" ou (r, g, b)');
  }
  throw new ScriptError(`cor inválida: ${typeName(v)}`, null, 'use um nome (red, wood...), "#rrggbb" ou (r, g, b)');
}

function material(s, { color = null, rough = null, metal = null, glow = null, tex = null }) {
  const props = {
    color: color === null ? null : parseColor(color),
    rough: rough === null ? null : num(rough, 'rough'),
    metal: metal === null ? null : num(metal, 'metal'),
    glow: glow === null ? null : numT(glow, 'glow'),
    tex,
  };
  return new Shape('material', props, [s]);
}

// ---------- métodos e propriedades das formas ----------

const TEXTURES = {
  noise: 1, ruido: 1, 'ruído': 1,
  wood: 2, madeira: 2,
  marble: 3, marmore: 3, 'mármore': 3,
  stripes: 4, listras: 4,
  checker: 5, xadrez: 5,
  bricks: 6, tijolos: 6,
};
const TEXTURE_NAMES = ['noise', 'wood', 'marble', 'stripes', 'checker', 'bricks'];

const SIDES = {
  right: [0, 1], direita: [0, 1], '+x': [0, 1],
  left: [0, -1], esquerda: [0, -1], '-x': [0, -1],
  front: [2, 1], frente: [2, 1], '+z': [2, 1],
  back: [2, -1], 'trás': [2, -1], tras: [2, -1], '-z': [2, -1],
};

function moveTo(s, target) {
  const c = center(s.bbox);
  return translate(s, target.map((v, i) => (v === null ? 0 : v - c[i])));
}

function bottomCenter(b) {
  const c = center(b);
  return [c[0], b.min[1], c[2]];
}

const METHODS = {
  at: [['x=0', 'y=0', 'z=0'], (s, a) => translate(s, xyzArgsT(a, 'at'))],
  move: [['x=0', 'y=0', 'z=0'], (s, a) => translate(s, xyzArgsT(a, 'move'))],
  place: [['x=0', 'y=0', 'z=0'], (s, a) => {
    needFinite(s, 'place()');
    const target = xyzArgs(a, 'place');
    const cur = bottomCenter(s.bbox);
    return translate(s, target.map((v, i) => v - cur[i]));
  }],
  ground: [[], (s) => { needFinite(s, 'ground()'); return translate(s, [0, -s.bbox.min[1], 0]); }],
  on: [['target', 'x=None', 'z=None', 'gap=0'], (s, a) => stack(s, a, +1)],
  under: [['target', 'x=None', 'z=None', 'gap=0'], (s, a) => stack(s, a, -1)],
  beside: [['target', 'side="right"', 'gap=0'], (s, a) => {
    const t = asShape(a.target, 'beside()');
    needFinite(s, 'beside()');
    needFinite(t, 'beside()');
    const side = SIDES[String(a.side).toLowerCase()];
    if (!side) throw new ScriptError(`lado desconhecido '${a.side}'`, null, "use 'right', 'left', 'front' ou 'back'");
    const [axis, dir] = side;
    const sb = s.bbox, tb = t.bbox;
    const tc = center(tb), sc = center(sb);
    const d = [tc[0] - sc[0], tb.min[1] - sb.min[1], tc[2] - sc[2]];
    d[axis] = dir > 0 ? tb.max[axis] + num(a.gap, 'gap') - sb.min[axis] : tb.min[axis] - num(a.gap, 'gap') - sb.max[axis];
    return translate(s, d);
  }],
  rotate: [['x=0', 'y=0', 'z=0', 'pivot=None'], (s, a) => {
    const ang = xyzArgsT(a, 'rotate');
    if (ang.every((v) => v === 0)) return s;
    const m = rotMatrix(...ang.map(val0));
    const props = ang.some(isExpr) ? { m, angles: ang } : { m };
    return aroundPivot(s, pivotOf(s, a.pivot), (q) => new Shape('rotate', props, [q]));
  }],
  scale: [['s', 'pivot=None'], (s, a) => {
    const f = Array.isArray(a.s) ? vec3(a.s, 'scale') : [0, 1, 2].map(() => numT(a.s, 'scale'));
    if (f.some((v) => val0(v) <= 0)) throw new ScriptError('scale() deve ser positivo', null, 'para inverter use mirror()');
    return aroundPivot(s, pivotOf(s, a.pivot), (q) => new Shape('scale', { s: f }, [q]));
  }],
  mirror: [['axes="x"'], (s, a) => {
    const ax = String(a.axes).toLowerCase();
    if (!/^[xyz]+$/.test(ax)) throw new ScriptError(`eixos inválidos '${a.axes}'`, null, 'use "x", "z", "xz"...');
    return new Shape('mirror', { axes: ['x', 'y', 'z'].map((c) => ax.includes(c)) }, [s]);
  }],
  repeat: [['x=1', 'y=1', 'z=1', 'spacing=None'], (s, a) => {
    needFinite(s, 'repeat()');
    const n = [a.x, a.y, a.z].map((v, i) => {
      const k = num(v, 'xyz'[i]);
      if (!Number.isInteger(k) || k < 1) throw new ScriptError('repeat() precisa de quantidades inteiras >= 1', null);
      return k;
    });
    if (n[0] * n[1] * n[2] > 10000) throw new ScriptError('repeat() com cópias demais', null);
    const sz = size(s.bbox);
    let sp;
    if (a.spacing === null) sp = sz.map((v) => (v > 0 ? v * 1.5 : 1));
    else if (Array.isArray(a.spacing)) sp = vec3(a.spacing, 'spacing');
    else sp = [0, 1, 2].map(() => num(a.spacing, 'spacing'));
    const fits = [0, 1, 2].every((i) => n[i] === 1 || sz[i] <= sp[i] + 1e-6);
    const c = center(s.bbox);
    if (fits) {
      return aroundPivot(s, c, (q) => new Shape('repeat', { n, s: sp }, [q]));
    }
    if (n[0] * n[1] * n[2] > 64) {
      throw new ScriptError('repeat(): as cópias se sobrepõem e são muitas para desenrolar', null,
        'aumente spacing para ser maior que o tamanho da forma');
    }
    const copies = [];
    for (let i = 0; i < n[0]; i++) for (let j = 0; j < n[1]; j++) for (let k = 0; k < n[2]; k++) {
      copies.push(translate(s, [(i - (n[0] - 1) / 2) * sp[0], (j - (n[1] - 1) / 2) * sp[1], (k - (n[2] - 1) / 2) * sp[2]]));
    }
    return union(copies);
  }],
  round: [['r'], (s, a) => new Shape('round', { r: num(a.r, 'round') }, [s])],
  shell: [['thickness'], (s, a) => new Shape('shell', { t: num(a.thickness, 'shell') }, [s])],
  twist: [['degrees'], (s, a) => {
    needFinite(s, 'twist()');
    const h = size(s.bbox)[1] || 1;
    const k = (num(a.degrees, 'twist') * Math.PI) / 180 / h;
    return aroundPivot(s, center(s.bbox), (q) => new Shape('twist', { k }, [q]));
  }],
  color: [['c'], (s, a) => material(s, { color: a.c })],
  material: [['color=None', 'rough=None', 'metal=None', 'glow=None'], (s, a) => material(s, a)],
  name: [['label'], (s, a) => new Shape('label', { name: String(a.label) }, [s])],
  bind: [['bone'], (s, a) => {
    if (!a.bone?.isBone) throw new ScriptError('bind() espera um osso', null, 'crie com esq = skeleton(); osso = esq.bone("nome", head=(x, y, z))');
    return new Shape('bound', { bone: a.bone }, [s]);
  }],
  texture: [['kind', 'color2=None', 'size=None', 'axis="y"'], (s, a) => {
    const kind = TEXTURES[String(a.kind).toLowerCase()];
    if (!kind) {
      throw new ScriptError(`textura desconhecida '${a.kind}'`, null,
        didYouMean(String(a.kind), Object.keys(TEXTURES)) ?? `use ${TEXTURE_NAMES.join(', ')}`);
    }
    const axis = { x: 0, y: 1, z: 2 }[String(a.axis).toLowerCase()];
    if (axis === undefined) throw new ScriptError(`eixo inválido '${a.axis}'`, null, 'use "x", "y" ou "z"');
    const sz = a.size === null ? null : num(a.size, 'size');
    if (sz !== null && sz <= 0) throw new ScriptError('size da textura deve ser maior que zero', null);
    return material(s, { tex: { kind, c2: a.color2 === null ? null : parseColor(a.color2), size: sz, axis } });
  }],
  displace: [['amount=0.05', 'size=0.3'], (s, a) => {
    const amt = num(a.amount, 'amount'), sz = num(a.size, 'size');
    if (sz <= 0) throw new ScriptError('size deve ser maior que zero', null);
    return new Shape('displace', { amt, size: sz }, [s]);
  }],
  union: [['*others', 'smooth=0'], (s, a) => union([s, ...flatten(a.others, 'union()')], num(a.smooth, 'smooth'))],
  subtract: [['*others', 'smooth=0'], (s, a) => subtract(s, flatten(a.others, 'subtract()'), a.smooth)],
  intersect: [['*others', 'smooth=0'], (s, a) => intersect([s, ...flatten(a.others, 'intersect()')], a.smooth)],
};

function stack(s, a, dir) {
  const t = asShape(a.target, dir > 0 ? 'on()' : 'under()');
  needFinite(s, dir > 0 ? 'on()' : 'under()');
  const sb = s.bbox, tb = t.bbox;
  const sc = center(sb);
  const gap = num(a.gap, 'gap');
  const dy = dir > 0 ? tb.max[1] + gap - sb.min[1] : tb.min[1] - gap - sb.max[1];
  let dx, dz;
  if (isFiniteBB(tb)) {
    const tc = center(tb);
    dx = tc[0] + (a.x === null ? 0 : num(a.x, 'x')) - sc[0];
    dz = tc[2] + (a.z === null ? 0 : num(a.z, 'z')) - sc[2];
  } else {
    dx = a.x === null ? 0 : num(a.x, 'x') - sc[0];
    dz = a.z === null ? 0 : num(a.z, 'z') - sc[2];
  }
  return translate(s, [dx, dy, dz]);
}

function asShape(v, what) {
  if (v instanceof Shape) return v;
  throw new ScriptError(`${what} espera uma forma, recebeu ${typeName(v)}`, null);
}

function subtract(a, others, smooth = 0) {
  if (!others.length) return a;
  return new Shape('subtract', { k: num(smooth, 'smooth') }, [a, union(others)]);
}

function intersect(list, smooth = 0) {
  if (list.length === 1) return list[0];
  return new Shape('intersect', { k: num(smooth, 'smooth') }, list);
}

const PROPS = {
  top: (b) => b.max[1], bottom: (b) => b.min[1],
  left: (b) => b.min[0], right: (b) => b.max[0],
  back: (b) => b.min[2], front: (b) => b.max[2],
  width: (b) => size(b)[0], height: (b) => size(b)[1], depth: (b) => size(b)[2],
  size: (b) => tuple(size(b)), center: (b) => tuple(center(b)),
  x: (b) => center(b)[0], y: (b) => center(b)[1], z: (b) => center(b)[2],
};

export function getShapeAttr(s, name) {
  if (name in PROPS) return PROPS[name](s.bbox);
  if (name in METHODS) {
    const [params, fn] = METHODS[name];
    return new Native(name, params, (a) => fn(s, a));
  }
  throw new ScriptError(`forma não tem o método/atributo '${name}'`, null,
    didYouMean(name, [...Object.keys(METHODS), ...Object.keys(PROPS)]) ?? `métodos: ${Object.keys(METHODS).join(', ')}`);
}

export function shapeBinary(op, a, b) {
  if (a instanceof Shape && b instanceof Shape) {
    if (op === '+' || op === '|') return union([a, b]);
    if (op === '-') return subtract(a, [b]);
    if (op === '&') return intersect([a, b]);
  }
  throw new ScriptError(`operação '${op}' não suportada entre ${typeName(a)} e ${typeName(b)}`, null,
    'formas aceitam a + b (união), a - b (subtração) e a & b (interseção); para mover use .at(x, y, z)');
}

// ---------- funções globais ----------

function positive(v, what) {
  const x = num(v, what);
  if (x <= 0) throw new ScriptError(`${what} deve ser maior que zero`, null);
  return x;
}

export function shapeBuiltins(scene) {
  const N = (name, params, fn) => new Native(name, params, fn);
  return {
    box: N('box', ['w=1', 'h=None', 'd=None', 'round=0'], (a) => {
      const w = positive(a.w, 'w');
      const size3 = [w, a.h === null ? w : positive(a.h, 'h'), a.d === null ? w : positive(a.d, 'd')];
      const r = Math.min(num(a.round, 'round'), Math.min(...size3) / 2);
      return new Shape('box', { size: size3, r });
    }),
    cube: N('cube', ['size=1', 'round=0'], (a) => {
      const s = positive(a.size, 'size');
      return new Shape('box', { size: [s, s, s], r: Math.min(num(a.round, 'round'), s / 2) });
    }),
    sphere: N('sphere', ['r=0.5'], (a) => new Shape('sphere', { r: positive(a.r, 'r') })),
    cylinder: N('cylinder', ['r=0.5', 'h=1', 'round=0'], (a) => {
      const r = positive(a.r, 'r'), h = positive(a.h, 'h');
      return new Shape('cylinder', { r, h, round: Math.min(num(a.round, 'round'), r, h / 2) });
    }),
    cone: N('cone', ['r=0.5', 'h=1', 'top=0'], (a) => new Shape('cone', { r: positive(a.r, 'r'), h: positive(a.h, 'h'), top: num(a.top, 'top') })),
    torus: N('torus', ['radius=0.5', 'thickness=0.1'], (a) => new Shape('torus', { R: positive(a.radius, 'radius'), r: positive(a.thickness, 'thickness') })),
    capsule: N('capsule', ['r=0.25', 'h=1'], (a) => {
      const r = positive(a.r, 'r');
      return new Shape('capsule', { r, h: Math.max(positive(a.h, 'h'), 2 * r) });
    }),
    ellipsoid: N('ellipsoid', ['x=0.5', 'y=0.3', 'z=0.5'], (a) => new Shape('ellipsoid', { radii: [positive(a.x, 'x'), positive(a.y, 'y'), positive(a.z, 'z')] })),
    pyramid: N('pyramid', ['w=1', 'h=1'], (a) => new Shape('pyramid', { w: positive(a.w, 'w'), h: positive(a.h, 'h') })),
    prism: N('prism', ['w=1', 'h=0.5', 'd=1'], (a) => new Shape('prism', { w: positive(a.w, 'w'), h: positive(a.h, 'h'), d: positive(a.d, 'd') })),
    plane: N('plane', [], () => new Shape('plane')),
    segment: N('segment', ['a', 'b', 'r=0.05'], (a) => segmentShape(vec3(a.a, 'a'), vec3(a.b, 'b'), positive(a.r, 'r'))),
    group: N('group', ['*shapes', 'smooth=0'], (a) => {
      const list = flatten(a.shapes, 'group()');
      if (!list.length) throw new ScriptError('group() vazio', null);
      return union(list, num(a.smooth, 'smooth'));
    }),
    union: N('union', ['*shapes', 'smooth=0'], (a) => {
      const list = flatten(a.shapes, 'union()');
      if (!list.length) throw new ScriptError('union() vazio', null);
      return union(list, num(a.smooth, 'smooth'));
    }),
    subtract: N('subtract', ['base', '*cutters', 'smooth=0'], (a) => subtract(asShape(a.base, 'subtract()'), flatten(a.cutters, 'subtract()'), a.smooth)),
    intersect: N('intersect', ['*shapes', 'smooth=0'], (a) => {
      const list = flatten(a.shapes, 'intersect()');
      if (!list.length) throw new ScriptError('intersect() vazio', null);
      return intersect(list, a.smooth);
    }),
    show: N('show', ['*shapes'], (a) => {
      scene.shapes.push(...flatten(a.shapes, 'show()'));
      return null;
    }),
    camera: N('camera', ['pos', 'look=None', 'fov=45'], (a) => {
      scene.camera = { pos: vec3(a.pos, 'pos'), look: a.look === null ? null : vec3(a.look, 'look'), fov: num(a.fov, 'fov') };
      return null;
    }),
    sun: N('sun', ['x=0.6', 'y=1', 'z=0.4', 'color=None'], (a) => {
      scene.sun = { dir: [num(a.x, 'x'), num(a.y, 'y'), num(a.z, 'z')], color: a.color === null ? null : parseColor(a.color) };
      return null;
    }),
    sky: N('sky', ['color'], (a) => { scene.sky = parseColor(a.color); return null; }),
    fog: N('fog', ['density=0.02'], (a) => { scene.fog = num(a.density, 'fog'); return null; }),
  };
}

// ---------- inspeção (para a IA conferir o que montou) ----------

const IDENT = [1, 0, 0, 0, 1, 0, 0, 0, 1];

export function collectParts(shapes) {
  const parts = [];
  const visit = (s, m, t) => {
    switch (s.kind) {
      case 'translate': visit(s.children[0], m, t.map((v, i) => v + mulMV(m, s.props.v.map(val0))[i])); return;
      case 'rotate': visit(s.children[0], mul3(m, s.props.m), t); return;
      case 'scale': {
        const sv = s.props.s.map(val0);
        const S = [sv[0], 0, 0, 0, sv[1], 0, 0, 0, sv[2]];
        visit(s.children[0], mul3(m, S), t);
        return;
      }
      case 'label': {
        const world = isFiniteBB(s.bbox) ? transformedBBox(s, m, t) : s.bbox;
        parts.push({ name: s.props.name, bbox: world });
        break;
      }
    }
    for (const c of s.children) visit(c, m, t);
  };
  shapes.forEach((s) => visit(s, IDENT, [0, 0, 0]));
  return parts;
}

export { isFiniteBB, center, size, unionBB, mul3, corners, fromPoints, transformedBBox, METHODS, PROPS, COLORS, TEXTURES, SIDES };
