// Modo 2D: canvas2d(width, height, background) declara a cena como 2D. As formas 2D são dados
// declarativos (sem funções por tipo de objeto): primitivas, transformações, estilo e combinações.
// Qualquer número pode ser uma expressão de time (keys(), osc...): a árvore atravessa o worker com
// as expressões serializadas e a página (src/draw2d.js) avalia tudo a cada quadro, em Canvas 2D ou SVG.
// Coordenadas em pixels do quadro: origem no canto superior esquerdo, x para a direita, y para baixo.
import { ScriptError } from './parser.js';
import { Native, bindArgs, typeName, repr } from './runtime.js';
import { isExpr, Expr } from './expr.js';
import { toSrgb } from './color.js';
import { layoutText } from './text3d.js';

export class Shape2D {
  constructor(node) { this.node = node; }
  describe() { return `<forma 2D ${this.node.k}${this.node.name ? ` '${this.node.name}'` : ''}>`; }
  with(patch) { return new Shape2D({ ...this.node, ...patch }); }
  attr3di(name) {
    const m = METHODS2D[name];
    if (!m) {
      throw new ScriptError(`forma 2D não tem o método '${name}'`, null, `métodos 2D: ${Object.keys(METHODS2D).join(', ')}`);
    }
    return new Native(name, m[0], (a) => m[1](this, a));
  }
}

export class Gradient2D {
  constructor(g) { this.g = g; }
  describe() { return `<gradiente ${this.g.type}>`; }
}

export const is2D = (v) => v instanceof Shape2D;

// ---------- valores ----------

const numT = (v, what) => {
  if (isExpr(v)) return v;
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'boolean') return +v;
  throw new ScriptError(`${what} deve ser um número (ou expressão de time), recebeu ${typeName(v)} ${repr(v).slice(0, 30)}`, null);
};
const pos = (v, what) => {
  const x = numT(v, what);
  if (!isExpr(x) && !(x > 0)) throw new ScriptError(`${what} deve ser > 0`, null);
  return x;
};
const point = (v, what) => {
  if (!Array.isArray(v) || v.length !== 2) throw new ScriptError(`${what} deve ser um ponto (x, y), recebeu ${typeName(v)} ${repr(v).slice(0, 30)}`, null);
  return v.map((x, i) => numT(x, `${what}[${i}]`));
};
const points = (v, what, min) => {
  if (!Array.isArray(v)) throw new ScriptError(`${what} deve ser uma lista de pontos [(x, y), ...]`, null);
  if (v.length < min) throw new ScriptError(`${what} precisa de pelo menos ${min} pontos`, null);
  if (v.length > 4000) throw new ScriptError(`${what}: no máximo 4000 pontos`, null);
  return v.map((p, i) => point(p, `${what}[${i}]`));
};

// cor: nome, "#rrggbb", (r, g, b) em 0..1 (componentes podem ser time), gradiente ou None
export function color2d(v, what = 'cor') {
  if (v === null || v === undefined || v === 'none') return null;
  if (v instanceof Gradient2D) return v.g;
  if (Array.isArray(v) && (v.length === 3 || v.length === 4) && v.some(isExpr)) return { rgb: v.map((x, i) => numT(x, `${what}[${i}]`)) };
  if (Array.isArray(v) && v.length === 4) return { rgb: [...toSrgb(v.slice(0, 3)), numT(v[3], `${what}[3]`)] };
  try { return { rgb: toSrgb(v) }; } catch (e) { throw new ScriptError(`${what}: ${e.message}`, null, e.hint); }
}

function stops(list, what) {
  if (list.length < 2) throw new ScriptError(`${what} precisa de pelo menos 2 cores`, null, 'ex.: linear_gradient(0, 0, 200, 0, "red", "blue")');
  return list.map((s, i) => {
    // (posição, cor) ou só a cor (espaçadas por igual)
    if (Array.isArray(s) && s.length === 2 && (typeof s[0] === 'number' || isExpr(s[0]))) return { at: numT(s[0], `${what} posição`), color: color2d(s[1], what) };
    return { at: i / (list.length - 1), color: color2d(s, what) };
  });
}

// ---------- construção ----------

let uid = 0;
const make = (k, p, c) => new Shape2D({ k, p, c, tf: [], st: {}, id: ++uid });

function flat2d(values, what, out = []) {
  for (const v of values) {
    if (v === null || v === undefined) continue;
    if (Array.isArray(v)) flat2d(v, what, out);
    else if (v instanceof Shape2D) out.push(v);
    else throw new ScriptError(`${what} espera formas 2D, recebeu ${typeName(v)}`, null, 'formas 2D: circle, ellipse, rect, polygon, star, line, path, text, image');
  }
  return out;
}

const tf = (s, t) => s.with({ tf: [...s.node.tf, t] });
const style = (s, patch) => s.with({ st: { ...s.node.st, ...patch } });

const METHODS2D = {
  at: [['x=0', 'y=0'], (s, a) => tf(s, { t: 'at', x: numT(a.x, 'at x'), y: numT(a.y, 'at y') })],
  move: [['x=0', 'y=0'], (s, a) => tf(s, { t: 'at', x: numT(a.x, 'move x'), y: numT(a.y, 'move y') })],
  // graus, no sentido horário (y para baixo); pivot = (x, y) no espaço da forma
  rotate: [['angle', 'pivot=None'], (s, a) => tf(s, { t: 'rot', a: numT(a.angle, 'rotate'), pv: a.pivot === null ? null : point(a.pivot, 'pivot') })],
  scale: [['s', 'sy=None', 'pivot=None'], (s, a) => {
    const sx = numT(a.s, 'scale'), sy = a.sy === null ? sx : numT(a.sy, 'scale sy');
    return tf(s, { t: 'scale', x: sx, y: sy, pv: a.pivot === null ? null : point(a.pivot, 'pivot') });
  }],
  fill: [['color'], (s, a) => style(s, { fill: color2d(a.color, 'fill()') })],
  color: [['color'], (s, a) => style(s, { fill: color2d(a.color, 'color()') })],
  stroke: [['color="black"', 'width=2', 'dash=None', 'cap="round"', 'join="round"'], (s, a) => {
    if (!['butt', 'round', 'square'].includes(a.cap)) throw new ScriptError('stroke(): cap deve ser "butt", "round" ou "square"', null);
    if (!['miter', 'round', 'bevel'].includes(a.join)) throw new ScriptError('stroke(): join deve ser "miter", "round" ou "bevel"', null);
    const dash = a.dash === null ? null : (Array.isArray(a.dash) ? a.dash : [a.dash, a.dash]).map((d) => numT(d, 'dash'));
    return style(s, { stroke: color2d(a.color, 'stroke()'), width: numT(a.width, 'stroke width'), dash, cap: a.cap, join: a.join });
  }],
  opacity: [['a'], (s, a) => style(s, { opacity: numT(a.a, 'opacity()') })],
  // desenha só um trecho do contorno (0..1): anime para "escrever" linhas e caminhos
  trim: [['end=1', 'start=0'], (s, a) => style(s, { trim: [numT(a.start, 'trim start'), numT(a.end, 'trim end')] })],
  shadow: [['color="black"', 'blur=8', 'x=0', 'y=4'], (s, a) => style(s, { shadow: { color: color2d(a.color, 'shadow()'), blur: numT(a.blur, 'blur'), x: numT(a.x, 'x'), y: numT(a.y, 'y') } })],
  name: [['label'], (s, a) => s.with({ name: String(a.label) })],
  union: [['*others'], (s, a) => make('union', {}, [s, ...flat2d(a.others, 'union()')].map((q) => q.node))],
  subtract: [['*others'], (s, a) => make('subtract', {}, [s, ...flat2d(a.others, 'subtract()')].map((q) => q.node))],
  intersect: [['*others'], (s, a) => make('intersect', {}, [s, ...flat2d(a.others, 'intersect()')].map((q) => q.node))],
};

const N = (name, params, fn) => new Native(name, params, fn);
const ALIGN = ['left', 'center', 'right'];

// funções que só existem no 2D
function only2d(scene) {
  return {
    canvas2d: N('canvas2d', ['width=1280', 'height=720', 'background="white"'], (a) => {
      const w = Math.round(+a.width), h = Math.round(+a.height);
      if (!(w >= 16 && w <= 8192 && h >= 16 && h <= 8192)) throw new ScriptError('canvas2d(): width e height de 16 a 8192 pixels', null);
      scene.canvas2d = { width: w, height: h, background: color2d(a.background, 'background') };
      return null;
    }),
    circle: N('circle', ['r=50'], (a) => make('ellipse', { rx: pos(a.r, 'r'), ry: pos(a.r, 'r') })),
    ellipse: N('ellipse', ['rx=60', 'ry=40'], (a) => make('ellipse', { rx: pos(a.rx, 'rx'), ry: pos(a.ry, 'ry') })),
    // centrado na origem; round = raio dos cantos
    rect: N('rect', ['w=100', 'h=None', 'round=0'], (a) => make('rect', { w: pos(a.w, 'w'), h: pos(a.h ?? a.w, 'h'), r: numT(a.round, 'round') })),
    line: N('line', ['a', 'b'], (a) => make('path', { pts: [point(a.a, 'a'), point(a.b, 'b')], closed: false, curve: false })),
    // polilinha pelos pontos; curve=True passa uma curva suave por eles; closed fecha o contorno
    path: N('path', ['points', 'closed=False', 'curve=False'], (a) => make('path', { pts: points(a.points, 'path()', 2), closed: !!a.closed, curve: !!a.curve })),
    // texto com as fontes do text3d; a base da primeira linha fica em y = 0
    text: N('text', ['content', 'size=48', 'font="sans"', 'align="center"', 'spacing=0', 'line=1.2'], (a) => {
      const content = String(a.content);
      if ([...content].length > 2000) throw new ScriptError('text(): no máximo 2000 letras', null);
      if (!ALIGN.includes(a.align)) throw new ScriptError('text(): align deve ser "left", "center" ou "right"', null);
      const lay = layoutText(content, { font: a.font, spacing: +a.spacing, line: +a.line, align: a.align });
      return make('text', { text: content, size: pos(a.size, 'size'), font: a.font, align: a.align, spacing: +a.spacing, line: +a.line, width: lay.width });
    }),
    // imagem (caminho/URL relativo à página, http(s) ou data:), centrada; sem h mantém a proporção
    image: N('image', ['src', 'w=200', 'h=None'], (a) => make('image', { src: String(a.src), w: pos(a.w, 'w'), h: a.h === null ? null : pos(a.h, 'h') })),
    linear_gradient: N('linear_gradient', ['x1', 'y1', 'x2', 'y2', '*colors'], (a) =>
      new Gradient2D({ type: 'linear', from: [numT(a.x1, 'x1'), numT(a.y1, 'y1')], to: [numT(a.x2, 'x2'), numT(a.y2, 'y2')], stops: stops(a.colors, 'linear_gradient()') })),
    radial_gradient: N('radial_gradient', ['x', 'y', 'r', '*colors'], (a) =>
      new Gradient2D({ type: 'radial', at: [numT(a.x, 'x'), numT(a.y, 'y')], r: pos(a.r, 'r'), stops: stops(a.colors, 'radial_gradient()') })),
  };
}

// funções que já existem no 3D: com canvas2d() declarado (ou com formas 2D nos argumentos), fazem a versão 2D
function shared2d(scene) {
  return {
    polygon: N('polygon', ['sides=6', 'r=50', 'points=None'], (a) => {
      if (a.points !== null) return make('path', { pts: points(a.points, 'polygon()', 3), closed: true, curve: false });
      const n = Math.round(+a.sides);
      if (!(n >= 3 && n <= 256)) throw new ScriptError('polygon(): sides de 3 a 256', null);
      return make('ngon', { n, r: pos(a.r, 'r'), inner: null });
    }),
    star: N('star', ['points=5', 'r=50', 'inner=None'], (a) => {
      const n = Math.round(+a.points);
      if (!(n >= 2 && n <= 128)) throw new ScriptError('star(): points de 2 a 128', null);
      const r = pos(a.r, 'r');
      return make('ngon', { n, r, inner: a.inner === null ? (isExpr(r) ? new Expr('*', [r, 0.45]) : r * 0.45) : pos(a.inner, 'inner') });
    }),
    group: N('group', ['*shapes'], (a) => make('group', {}, flat2d(a.shapes, 'group()').map((q) => q.node))),
    union: N('union', ['*shapes'], (a) => make('union', {}, flat2d(a.shapes, 'union()').map((q) => q.node))),
    subtract: N('subtract', ['base', '*cutters'], (a) => make('subtract', {}, flat2d([a.base, ...a.cutters], 'subtract()').map((q) => q.node))),
    intersect: N('intersect', ['*shapes'], (a) => make('intersect', {}, flat2d(a.shapes, 'intersect()').map((q) => q.node))),
    show: N('show', ['*shapes'], (a) => {
      scene.shapes2d = scene.shapes2d ?? [];
      scene.shapes2d.push(...flat2d(a.shapes, 'show()').map((q) => q.node));
      return null;
    }),
  };
}

const has2d = (vs) => vs.some((v) => v instanceof Shape2D || (Array.isArray(v) && has2d(v)));

// Junta as funções 2D às builtins: as que só existem no 2D entram direto; as compartilhadas
// escolhem a versão 2D quando a cena chamou canvas2d() ou recebeu formas 2D.
export function builtins2d(scene, base) {
  const out = { ...only2d(scene) };
  for (const [name, f2] of Object.entries(shared2d(scene))) {
    const f3 = base[name];
    if (!(f3 instanceof Native)) { out[name] = f2; continue; }
    const w = new Native(name, ['*args', '**kw'], ({ args, kw }, node) => {
      const use2d = !!scene.canvas2d || has2d(args) || has2d(Object.values(kw));
      const f = use2d ? f2 : f3;
      return f.fn(bindArgs(f, args, Object.entries(kw)), node);
    });
    // o catálogo da linguagem continua mostrando a assinatura 3D; a 2D fica em signature2d
    w.f3 = f3;
    w.f2 = f2;
    w.signature = () => `${f3.signature()} | 2D: ${f2.signature()}`;
    out[name] = w;
  }
  return out;
}

// + une, - recorta, & intersecta (como nas formas 3D)
export function binary2d(op, a, b) {
  if (!(a instanceof Shape2D) || !(b instanceof Shape2D)) throw new ScriptError(`operação '${op}' entre ${typeName(a)} e ${typeName(b)}: misture só formas 2D`, null);
  const k = { '+': 'union', '|': 'union', '-': 'subtract', '&': 'intersect' }[op];
  if (!k) throw new ScriptError(`operação '${op}' não existe entre formas 2D`, null, 'use + (união), - (recorte) ou & (interseção)');
  return make(k, {}, [a.node, b.node]);
}

// ---------- serialização (worker -> página) ----------

// Expressões viram { $e: op, a: [...] }; o resto já é dado simples
export function ser2d(v) {
  if (v instanceof Expr) return { $e: v.op, a: v.args.map(ser2d) };
  if (Array.isArray(v)) return v.map(ser2d);
  if (v && typeof v === 'object') {
    const o = {};
    for (const [k, x] of Object.entries(v)) if (x !== undefined) o[k] = ser2d(x);
    return o;
  }
  return v;
}

export function hydrate2d(v) {
  if (Array.isArray(v)) return v.map(hydrate2d);
  if (v && typeof v === 'object') {
    if ('$e' in v) return new Expr(v.$e, v.a.map(hydrate2d));
    const o = {};
    for (const [k, x] of Object.entries(v)) o[k] = hydrate2d(x);
    return o;
  }
  return v;
}

// Dados da cena 2D que vão para a página; null se a cena é 3D
export function scene2dMeta(scene) {
  if (!scene.canvas2d) return null;
  const items = scene.shapes2d ?? [];
  let count = 0, animated = false;
  const walk = (v) => {
    if (v instanceof Expr) { if (v.usesTime()) animated = true; return; }
    if (Array.isArray(v)) v.forEach(walk);
    else if (v && typeof v === 'object') { if (v.k && v.tf) count++; Object.values(v).forEach(walk); }
  };
  walk(items);
  return { ...scene.canvas2d, items: ser2d(items), count, animated };
}
