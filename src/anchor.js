// Âncoras: pontos com direção guardados na forma ("porta", "cume", "apoio") que acompanham as
// transformações. attach() cola uma peça na âncora de outra, girando-a para encarar a face.
// (ideia dos pontos de encaixe do ShapeAssembly). A âncora vive num nó translate de deslocamento
// zero (props.anchors), que o compilador, o SDF e o export já atravessam sem custo.
import { ScriptError } from './parser.js';
import { typeName, tuple, num } from './runtime.js';
import { val0 } from './expr.js';
import { Shape, METHODS, SHAPE_ATTRS, translate, aroundPivot, mul3, mulMV, isFiniteBB, center } from './shapes.js';

const IDENT = [1, 0, 0, 0, 1, 0, 0, 0, 1];

// direções por nome (inglês e português); as faces da caixa envolvente usam os mesmos nomes
const DIRS = {
  top: [0, 1, 0], topo: [0, 1, 0], up: [0, 1, 0], cima: [0, 1, 0], '+y': [0, 1, 0],
  bottom: [0, -1, 0], base: [0, -1, 0], down: [0, -1, 0], baixo: [0, -1, 0], '-y': [0, -1, 0],
  right: [1, 0, 0], direita: [1, 0, 0], '+x': [1, 0, 0],
  left: [-1, 0, 0], esquerda: [-1, 0, 0], '-x': [-1, 0, 0],
  front: [0, 0, 1], frente: [0, 0, 1], '+z': [0, 0, 1],
  back: [0, 0, -1], 'trás': [0, 0, -1], tras: [0, 0, -1], '-z': [0, 0, -1],
};
const FACES = ['top', 'bottom', 'right', 'left', 'front', 'back'];

const norm = (v) => {
  const l = Math.hypot(...v);
  return l > 1e-12 ? v.map((x) => x / l) : [0, 1, 0];
};
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];

function inv3(m) {
  const [a, b, c, d, e, g, h, i, k] = m;
  const A = e * k - g * i, B = -(d * k - g * h), C = d * i - e * h;
  const det = a * A + b * B + c * C;
  return [A, -(b * k - c * i), b * g - c * e, B, a * k - c * h, -(a * g - c * d), C, -(a * i - b * h), a * e - b * d].map((x) => x / det);
}
const transpose = (m) => [m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]];

function boxOf(x) {
  if (x instanceof Shape) return x.bbox;
  if (x?.isScope) return { min: x.min, max: x.max };
  return null;
}

// âncoras padrão: centro de cada face da caixa envolvente (direção para fora) e o centro (para cima)
function faceAnchor(b, name) {
  const c = center(b);
  if (name === 'center' || name === 'centro') return { p: c, n: [0, 1, 0] };
  const n = DIRS[name];
  if (!n || !FACES.some((f) => DIRS[f] === n)) return null;
  const p = [...c];
  const i = n.findIndex((v) => v !== 0);
  p[i] = n[i] > 0 ? b.max[i] : b.min[i];
  return { p, n: [...n] };
}

// âncoras declaradas com .anchor(), em coordenadas do mundo; a mais externa (a última definida) vence
export function declaredAnchors(s) {
  if (s._anchors) return s._anchors;
  const out = new Map();
  const visit = (q, m, t) => {
    const P = q.props;
    if (q.kind === 'translate' && P.anchors) {
      const nm = transpose(inv3(m));
      for (const a of P.anchors) {
        if (!out.has(a.name)) out.set(a.name, { p: mulMV(m, a.p).map((v, i) => v + t[i]), n: norm(mulMV(nm, a.n)) });
      }
    }
    switch (q.kind) {
      case 'translate': visit(q.children[0], m, t.map((v, i) => v + mulMV(m, P.v.map(val0))[i])); return;
      case 'rotate': visit(q.children[0], mul3(m, P.m), t); return;
      case 'scale': {
        const sv = P.s.map(val0);
        visit(q.children[0], mul3(m, [sv[0], 0, 0, 0, sv[1], 0, 0, 0, sv[2]]), t);
        return;
      }
      case 'subtract': visit(q.children[0], m, t); return;
    }
    for (const c of q.children) visit(c, m, t);
  };
  visit(s, IDENT, [0, 0, 0]);
  return (s._anchors = out);
}

export function resolveAnchor(x, name, what) {
  const key = String(name);
  if (x instanceof Shape) {
    const a = declaredAnchors(x).get(key);
    if (a) return a;
  }
  const b = boxOf(x);
  if (!b) throw new ScriptError(`${what} espera uma forma ou um escopo, recebeu ${typeName(x)}`, null);
  if (!isFiniteBB(b)) throw new ScriptError(`${what}: a forma é infinita`, null);
  const f = faceAnchor(b, key.toLowerCase());
  if (f) return f;
  const names = [...(x instanceof Shape ? declaredAnchors(x).keys() : []), ...FACES, 'center'];
  throw new ScriptError(`${what}: âncora '${key}' não existe`, null, `âncoras disponíveis: ${names.join(', ')}`);
}

function vecOf(v, what) {
  if (typeof v === 'string') {
    const d = DIRS[v.toLowerCase()];
    if (!d) throw new ScriptError(`${what}: direção desconhecida '${v}'`, null, 'use "up", "down", "front", "back", "left", "right" ou (x, y, z)');
    return [...d];
  }
  if (Array.isArray(v) && v.length === 3) return v.map((x) => num(x, what));
  throw new ScriptError(`${what} espera um ponto/direção (x, y, z), recebeu ${typeName(v)}`, null);
}

// .anchor(name, at=None, dir=None, x=None, y=None, z=None)
function anchorMethod(s, a) {
  const name = String(a.name);
  if (!name) throw new ScriptError('anchor(): o nome não pode ser vazio', null);
  let p, n = [0, 1, 0];
  if (a.at === null) {
    const b = s.bbox;
    if (!isFiniteBB(b)) throw new ScriptError('anchor(): a forma é infinita; passe at=(x, y, z)', null);
    p = center(b);
  } else if (typeof a.at === 'string') ({ p, n } = resolveAnchor(s, a.at, 'anchor()'));
  else if (a.at instanceof Shape || a.at?.isScope) {
    const b = boxOf(a.at);
    if (!isFiniteBB(b)) throw new ScriptError('anchor(): at é infinito', null);
    p = center(b);
  } else p = vecOf(a.at, 'anchor() at');
  p = [...p];
  ['x', 'y', 'z'].forEach((k, i) => { if (a[k] !== null) p[i] = num(a[k], `anchor() ${k}`); });
  if (a.dir !== null) n = norm(vecOf(a.dir, 'anchor() dir'));
  return new Shape('translate', { v: [0, 0, 0], anchors: [{ name, p, n }] }, [s]);
}

// rotação que leva a direção u até v (Rodrigues); em torno de y quando as duas são horizontais
function rotationTo(u, v) {
  const c = dot(u, v);
  let k = cross(u, v);
  let sn = Math.hypot(...k);
  if (sn < 1e-9) {
    if (c > 0) return null;
    // opostas: meia volta em torno de y (ou de x, se forem verticais)
    k = Math.abs(u[1]) > 0.9 ? [1, 0, 0] : [0, 1, 0];
    sn = 0;
  } else k = k.map((x) => x / sn);
  const ang = Math.atan2(sn, c);
  const [x, y, z] = k, C = Math.cos(ang), S = Math.sin(ang), T = 1 - C;
  return [
    T * x * x + C, T * x * y - S * z, T * x * z + S * y,
    T * x * y + S * z, T * y * y + C, T * y * z - S * x,
    T * x * z - S * y, T * y * z + S * x, T * z * z + C,
  ];
}

// peça.attach(alvo, at, to=None, gap=0, offset=None, turn=True, align="center")
function attachMethod(s, a) {
  const A = resolveAnchor(a.target, a.at, 'attach()');
  const gap = num(a.gap, 'gap');
  const off = a.offset === null ? [0, 0, 0] : vecOf(a.offset, 'attach() offset');
  let piece = s;
  let B;
  if (a.to === null) {
    // a face da peça que encara a âncora do alvo (a de direção mais oposta)
    const want = A.n.map((x) => -x);
    const face = FACES.reduce((best, f) => (dot(DIRS[f], want) > dot(DIRS[best], want) ? f : best), FACES[0]);
    B = resolveAnchor(piece, face, 'attach()');
  } else {
    B = resolveAnchor(piece, a.to, 'attach()');
    if (a.turn) {
      const R = rotationTo(B.n, A.n.map((x) => -x));
      if (R) {
        // gira em volta da própria âncora: o ponto fica, a direção gira junto
        piece = aroundPivot(piece, B.p, (q) => new Shape('rotate', { m: R }, [q]));
        B = { p: B.p, n: mulMV(R, B.n) };
      }
    }
  }
  const dest = A.p.map((v, i) => v + A.n[i] * gap + off[i]);
  const move = dest.map((v, i) => v - B.p[i]);
  // align: "bottom"/"top" apoia a base (ou o topo) da peça na altura da âncora, como uma porta no chão
  const align = String(a.align).toLowerCase();
  if (align === 'bottom' || align === 'top') {
    const b = piece.bbox;
    move[1] = dest[1] - (align === 'bottom' ? b.min[1] : b.max[1]);
  } else if (align !== 'center') {
    throw new ScriptError(`attach(): align deve ser "center", "bottom" ou "top", recebeu '${a.align}'`, null);
  }
  return translate(piece, move);
}

Object.assign(METHODS, {
  anchor: [['name', 'at=None', 'dir=None', 'x=None', 'y=None', 'z=None'], anchorMethod],
  attach: [['target', 'at', 'to=None', 'gap=0', 'offset=None', 'turn=True', 'align="center"'], attachMethod],
  point: [['name'], (s, a) => tuple(resolveAnchor(s, a.name, 'point()').p)],
  facing: [['name'], (s, a) => tuple(resolveAnchor(s, a.name, 'facing()').n.map((v) => +v.toFixed(12)))],
});

SHAPE_ATTRS.anchors = (s) => [...declaredAnchors(s).keys()];
