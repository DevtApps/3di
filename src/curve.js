// Curvas (spline, bezier) avaliadas na CPU e o que se faz com elas: sweep (um perfil varrido ao
// longo da curva) e along (cópias distribuídas pela curva). Tudo vira primitivas comuns (cones
// arredondados, caixas, perfis extrudados), então vai para a BVH e não pede shader novo.
import { ScriptError } from './parser.js';
import { Native, typeName, tuple, fmtNum, num } from './runtime.js';
import { Shape, METHODS, translate, roundCone, segmentShape, union } from './shapes.js';

const SAMPLES = 64; // amostras por trecho na tabela de comprimento de arco

const sub = (a, b) => a.map((v, i) => v - b[i]);
const add = (a, b) => a.map((v, i) => v + b[i]);
const mulS = (a, k) => a.map((v) => v * k);
const len = (a) => Math.hypot(...a);
const norm = (a) => { const l = len(a); return l > 1e-12 ? mulS(a, 1 / l) : [1, 0, 0]; };
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];

function vec3(v, what) {
  if (!Array.isArray(v) || (v.length !== 3 && v.length !== 2)) throw new ScriptError(`${what}: espera um ponto (x, y, z), recebeu ${typeName(v)}`, null);
  const p = v.map((x) => num(x, what));
  return p.length === 2 ? [p[0], p[1], 0] : p;
}

export class Curve {
  // f(u) com u de 0 a 1 no parâmetro da curva; a tabela converte para comprimento de arco
  constructor(f, spans, label) {
    this.f = f;
    this.label = label;
    const n = Math.max(1, spans) * SAMPLES;
    this.us = [];
    this.ls = [];
    let prev = f(0), total = 0;
    for (let i = 0; i <= n; i++) {
      const u = i / n, p = f(u);
      total += len(sub(p, prev));
      prev = p;
      this.us.push(u);
      this.ls.push(total);
    }
    this.length = total;
  }

  // ponto na fração s (0 a 1) do comprimento: pontos igualmente espaçados de verdade
  param(s) {
    const L = Math.min(1, Math.max(0, s)) * this.length;
    let lo = 0, hi = this.ls.length - 1;
    while (hi - lo > 1) {
      const mid = (lo + hi) >> 1;
      if (this.ls[mid] < L) lo = mid; else hi = mid;
    }
    const span = this.ls[hi] - this.ls[lo];
    const k = span > 1e-12 ? (L - this.ls[lo]) / span : 0;
    return this.us[lo] + (this.us[hi] - this.us[lo]) * k;
  }
  pointAt(s) { return this.f(this.param(s)); }
  tangentAt(s) {
    const u = this.param(s), e = 1e-4;
    return norm(sub(this.f(Math.min(1, u + e)), this.f(Math.max(0, u - e))));
  }
  sample(n) { return Array.from({ length: n + 1 }, (_, i) => this.pointAt(i / n)); }

  describe() {
    const a = this.f(0), b = this.f(1);
    return `<curva ${this.label} ${fmtNum(+this.length.toFixed(3))} m de (${a.map(fmtNum).join(', ')}) até (${b.map(fmtNum).join(', ')})>`;
  }

  attr3di(name) {
    const N = (n, params, fn) => new Native(n, params, fn);
    const t3 = (p) => tuple(p.map((v) => +v.toFixed(9)));
    switch (name) {
      case 'length': return this.length;
      case 'start': return t3(this.f(0));
      case 'end': return t3(this.f(1));
      case 'point': return N('point', ['t'], ({ t }) => t3(this.pointAt(num(t, 't'))));
      case 'tangent': return N('tangent', ['t'], ({ t }) => t3(this.tangentAt(num(t, 't'))));
      case 'points': return N('points', ['n=16'], ({ n }) => {
        const k = Math.round(num(n, 'n'));
        if (!(k >= 1 && k <= 4096)) throw new ScriptError('points(): n deve ser um inteiro de 1 a 4096', null);
        return this.sample(k).map(t3);
      });
      case 'offset': return N('offset', ['x=0', 'y=0', 'z=0'], (a) => {
        const d = Array.isArray(a.x) ? vec3(a.x, 'offset') : [a.x, a.y, a.z].map((v) => num(v, 'offset'));
        return new Curve((u) => add(this.f(u), d), this.us.length / SAMPLES, this.label);
      });
      case 'reverse': return N('reverse', [], () => new Curve((u) => this.f(1 - u), this.us.length / SAMPLES, this.label));
    }
    throw new ScriptError(`curva não tem o atributo '${name}'`, null,
      'atributos: length, start, end, point(t), tangent(t), points(n), offset(x, y, z), reverse()');
  }
}

// Catmull-Rom centrípeta: passa por todos os pontos sem laçadas nem bicos
function catmullRom(pts, closed) {
  const P = closed ? [...pts, pts[0]] : pts;
  const n = P.length - 1;
  const get = (i) => (closed ? pts[((i % pts.length) + pts.length) % pts.length]
    : i < 0 ? add(P[0], sub(P[0], P[1])) : i > n ? add(P[n], sub(P[n], P[n - 1])) : P[i]);
  return [(u) => {
    const x = Math.min(n, Math.max(0, u * n));
    const i = Math.min(n - 1, Math.floor(x)), t = x - i;
    const p0 = get(i - 1), p1 = get(i), p2 = get(i + 1), p3 = get(i + 2);
    // nos pontos de controle, devolve o ponto exato (a curva fechada termina onde começou)
    if (t === 0) return [...p1];
    if (t === 1) return [...p2];
    const tj = (ti, a, b) => ti + Math.max(1e-6, Math.sqrt(len(sub(b, a))));
    const t0 = 0, t1 = tj(t0, p0, p1), t2 = tj(t1, p1, p2), t3 = tj(t2, p2, p3);
    const tt = t1 + (t2 - t1) * t;
    const lerp = (a, b, ta, tb) => add(mulS(a, (tb - tt) / (tb - ta)), mulS(b, (tt - ta) / (tb - ta)));
    const A1 = lerp(p0, p1, t0, t1), A2 = lerp(p1, p2, t1, t2), A3 = lerp(p2, p3, t2, t3);
    const B1 = lerp(A1, A2, t0, t2), B2 = lerp(A2, A3, t1, t3);
    return lerp(B1, B2, t1, t2);
  }, n];
}

function bezierFn(c) {
  return (u) => {
    // de Casteljau: funciona para qualquer grau
    let q = c;
    while (q.length > 1) q = q.slice(1).map((p, i) => add(mulS(q[i], 1 - u), mulS(p, u)));
    return q[0];
  };
}

function asCurve(v, what) {
  if (v instanceof Curve) return v;
  if (Array.isArray(v) && v.length >= 2 && v.every((p) => Array.isArray(p))) {
    const pts = v.map((p, i) => vec3(p, `${what} ponto ${i}`));
    const [f, n] = catmullRom(pts, false);
    return new Curve(f, n, 'spline');
  }
  throw new ScriptError(`${what} espera uma curva (spline/bezier) ou uma lista de pontos, recebeu ${typeName(v)}`, null);
}

// Matriz de rotação cujas colunas são o referencial (lado, normal, tangente): o eixo z local
// segue a tangente e o x local fica na horizontal (o perfil não gira à toa em volta da curva).
function frame(T, up = [0, 1, 0]) {
  let S = cross(up, T);
  if (len(S) < 1e-6) S = cross([0, 0, 1], T);
  S = norm(S);
  const N = cross(T, S);
  return [S[0], N[0], T[0], S[1], N[1], T[1], S[2], N[2], T[2]];
}

function rangeOf(v, what) {
  if (Array.isArray(v)) {
    if (v.length !== 2) throw new ScriptError(`${what} deve ser um número ou (início, fim)`, null);
    return v.map((x) => num(x, what));
  }
  const x = num(v, what);
  return [x, x];
}

// sweep(profile, path, steps=None, twist=0): profile é um raio, (raio_inicio, raio_fim),
// ("box", largura, altura) ou uma lista de pontos 2D (x, y) do perfil
function sweep(a) {
  const c = asCurve(a.path, 'sweep()');
  if (!(c.length > 1e-9)) throw new ScriptError('sweep(): a curva tem comprimento zero', null);
  const prof = a.profile;
  let kind, r0, r1, w, h, pts;
  if (typeof prof === 'number' || (Array.isArray(prof) && prof.length === 2 && prof.every((v) => typeof v === 'number'))) {
    kind = 'round';
    [r0, r1] = rangeOf(prof, 'sweep() profile');
    if (!(r0 > 0 && r1 > 0)) throw new ScriptError('sweep(): o raio deve ser maior que zero', null);
  } else if (Array.isArray(prof) && prof[0] === 'box') {
    kind = 'box';
    [w, h] = [num(prof[1], 'largura'), num(prof[2] ?? prof[1], 'altura')];
    if (!(w > 0 && h > 0)) throw new ScriptError('sweep(): ("box", largura, altura) deve ter tamanhos positivos', null);
  } else if (Array.isArray(prof) && prof.length >= 3 && prof.every((p) => Array.isArray(p) && p.length === 2)) {
    kind = 'poly';
    pts = prof.map((p) => p.map((v) => num(v, 'perfil')));
  } else {
    throw new ScriptError(`sweep(): profile inválido (${typeName(prof)})`, null,
      'use um raio (0.05), (raio_início, raio_fim), ("box", largura, altura) ou uma lista de pontos (x, y)');
  }
  const size = kind === 'round' ? Math.min(r0, r1) : kind === 'box' ? Math.min(w, h) : 0.05;
  let n = a.steps === null ? Math.round(c.length / Math.max(size * 1.5, c.length / 48)) : Math.round(num(a.steps, 'steps'));
  n = Math.max(1, Math.min(256, n));
  const P = c.sample(n);
  const segs = [];
  for (let i = 0; i < n; i++) {
    const A = P[i], B = P[i + 1];
    if (kind === 'round') {
      // raio constante: cápsulas (vão para a BVH, baratas); afinando: cones arredondados (viram código)
      segs.push(r0 === r1 ? segmentShape(A, B, r0) : roundCone(A, B, r0 + ((r1 - r0) * i) / n, r0 + ((r1 - r0) * (i + 1)) / n));
      continue;
    }
    // trechos retos com uma sobreposição pequena para não abrir frestas nas curvas
    const d = len(sub(B, A));
    if (d < 1e-9) continue;
    const T = norm(sub(B, A));
    const ext = d + size * 0.5;
    const piece = kind === 'box'
      ? new Shape('box', { size: [w, h, ext], r: 0 })
      : new Shape('extrude', { pts, h: ext, axis: 'z', r: 0 });
    const m = frame(T);
    segs.push(translate(new Shape('rotate', { m }, [piece]), mulS(add(A, B), 0.5)));
  }
  return union(segs, num(a.smooth, 'smooth'));
}

// forma.along(curva, count=None, spacing=None, orient="yaw", start=0, end=1)
function along(s, a) {
  const c = asCurve(a.path, 'along()');
  const [s0, s1] = [num(a.start, 'start'), num(a.end, 'end')];
  if (!(s0 >= 0 && s1 <= 1 && s0 <= s1)) throw new ScriptError('along(): start e end devem ficar entre 0 e 1, com start <= end', null);
  const span = (s1 - s0) * c.length;
  let n;
  if (a.count !== null) n = Math.round(num(a.count, 'count'));
  else if (a.spacing !== null) {
    const sp = num(a.spacing, 'spacing');
    if (!(sp > 0)) throw new ScriptError('along(): spacing deve ser maior que zero', null);
    n = Math.floor(span / sp + 1e-9) + 1;
  } else throw new ScriptError('along(): diga count= (quantas cópias) ou spacing= (distância em metros)', null);
  if (!(n >= 1 && n <= 4096)) throw new ScriptError('along(): de 1 a 4096 cópias', null);
  const orient = String(a.orient).toLowerCase();
  if (!['yaw', 'full', 'none'].includes(orient)) throw new ScriptError(`along(): orient deve ser "yaw", "full" ou "none"`, null);
  const closed = len(sub(c.f(0), c.f(1))) < 1e-6;
  const copies = [];
  for (let i = 0; i < n; i++) {
    // curva fechada: a última cópia não cai em cima da primeira
    const k = n === 1 ? 0.5 : closed && s0 === 0 && s1 === 1 ? i / n : i / (n - 1);
    const t = s0 + (s1 - s0) * k;
    const p = c.pointAt(t), T = c.tangentAt(t);
    let q = s;
    if (orient === 'yaw' && Math.hypot(T[0], T[2]) > 1e-6) {
      // gira em y para o +x da forma seguir a curva (vista de cima)
      const ang = Math.atan2(-T[2], T[0]);
      const C = Math.cos(ang), S = Math.sin(ang);
      q = new Shape('rotate', { m: [C, 0, S, 0, 1, 0, -S, 0, C] }, [q]);
    } else if (orient === 'full') {
      // +x da forma na tangente, y o mais perto possível de cima
      const F = frame(T);
      // colunas (lado, normal, tangente) -> queremos x=T, y=N, z=-S
      const Sd = [F[0], F[3], F[6]], Nd = [F[1], F[4], F[7]];
      q = new Shape('rotate', { m: [T[0], Nd[0], -Sd[0], T[1], Nd[1], -Sd[1], T[2], Nd[2], -Sd[2]] }, [q]);
    }
    copies.push(translate(q, p));
  }
  return union(copies);
}

export function curveBuiltins() {
  return {
    spline: new Native('spline', ['points', 'closed=False'], (a) => {
      if (!Array.isArray(a.points) || a.points.length < 2 || a.points.length > 256) throw new ScriptError('spline(): points deve ser uma lista de 2 a 256 pontos (x, y, z)', null);
      const pts = a.points.map((p, i) => vec3(p, `spline() ponto ${i}`));
      const closed = !!a.closed;
      if (closed && pts.length < 3) throw new ScriptError('spline(closed=True) precisa de pelo menos 3 pontos', null);
      const [f, n] = catmullRom(pts, closed);
      return new Curve(f, n, closed ? 'spline fechada' : 'spline');
    }),
    bezier: new Native('bezier', ['*points'], (a) => {
      const raw = a.points.length === 1 && Array.isArray(a.points[0]) && Array.isArray(a.points[0][0]) ? a.points[0] : a.points;
      if (raw.length < 2 || raw.length > 16) throw new ScriptError('bezier(): de 2 a 16 pontos de controle (início, controles..., fim)', null);
      const c = raw.map((p, i) => vec3(p, `bezier() ponto ${i}`));
      return new Curve(bezierFn(c), Math.max(1, c.length - 2), 'bézier');
    }),
    sweep: new Native('sweep', ['profile', 'path', 'steps=None', 'smooth=0'], (a) => sweep(a)),
  };
}

Object.assign(METHODS, {
  along: [['path', 'count=None', 'spacing=None', 'orient="yaw"', 'start=0', 'end=1'], along],
});
