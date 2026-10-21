// Escopos: caixas alinhadas aos eixos usadas para montar estruturas sem calcular coordenadas
// (ideia das gramáticas de divisão do CGA/CityEngine). Um escopo não aparece na cena: ele é
// dividido (split), repetido (tile) e preenchido (fill) com formas.
import { ScriptError } from './parser.js';
import { Native, typeName, tuple, fmtNum, num } from './runtime.js';
import { Shape, METHODS, union } from './shapes.js';

const AXES = { x: 0, y: 1, z: 2 };
const EPS = 1e-6;

// quem chama funções do script (o interpretador registra ao começar)
let caller = null;
export function setScopeCaller(fn) { caller = fn; }

const isCallable = (v) => v instanceof Native || v?.isFunc;

function axisOf(v, what) {
  const i = AXES[String(v).toLowerCase()];
  if (i === undefined) throw new ScriptError(`${what}: eixo deve ser "x", "y" ou "z", recebeu ${JSON.stringify(v)}`, null);
  return i;
}

// Um tamanho do split: número (metros), "~" (1 parte do que sobra), "2fr" (2 partes) ou "30%".
function parseSize(v, total, what) {
  if (typeof v === 'number') {
    if (!(v >= 0)) throw new ScriptError(`${what}: tamanhos não podem ser negativos`, null);
    return { m: v };
  }
  const s = typeof v === 'string' ? v.trim().toLowerCase() : null;
  if (s === '~') return { fr: 1 };
  let m;
  if (s && (m = /^(\d*\.?\d+)\s*fr$/.exec(s))) return { fr: +m[1] };
  if (s && (m = /^(\d*\.?\d+)\s*%$/.exec(s))) return { m: (total * m[1]) / 100 };
  throw new ScriptError(`${what}: tamanho inválido ${typeof v === 'string' ? `'${v}'` : typeName(v)}`, null,
    'use metros (0.4), "~" (o que sobrar), "2fr" (partes do que sobrar) ou "30%"');
}

export class Scope {
  constructor(min, max) {
    this.min = min;
    this.max = max;
    this.isScope = true;
  }

  static of(s, what) {
    if (s instanceof Scope) return s;
    if (s instanceof Shape) {
      const b = s.bbox;
      if (!b.min.every((v) => v > -1e3) || !b.max.every((v) => v < 1e3)) throw new ScriptError(`${what}: a forma é infinita`, null);
      return new Scope([...b.min], [...b.max]);
    }
    throw new ScriptError(`${what} espera uma forma ou um escopo, recebeu ${typeName(s)}`, null);
  }

  get size() { return [0, 1, 2].map((i) => this.max[i] - this.min[i]); }
  get center() { return [0, 1, 2].map((i) => (this.min[i] + this.max[i]) / 2); }

  describe() {
    return `<escopo ${this.size.map(fmtNum).join(' x ')} centro (${this.center.map(fmtNum).join(', ')})>`;
  }

  with(i, lo, hi) {
    const min = [...this.min], max = [...this.max];
    min[i] = lo;
    max[i] = hi;
    return new Scope(min, max);
  }

  // divide no eixo; sizes é uma lista de tamanhos ou um inteiro (partes iguais)
  split(axis, sizes) {
    const i = axisOf(axis, 'split()');
    const L = this.size[i];
    if (typeof sizes === 'number') {
      const n = Math.round(sizes);
      if (!(n >= 1) || n !== sizes) throw new ScriptError('split(): o número de partes deve ser um inteiro >= 1', null);
      sizes = Array(n).fill('~');
    }
    if (!Array.isArray(sizes) || !sizes.length) throw new ScriptError('split() espera uma lista de tamanhos', null, 'ex.: parede.split("y", [0.4, "~", 0.5])');
    const parts = sizes.map((v) => parseSize(v, L, 'split()'));
    const fixed = parts.reduce((a, p) => a + (p.m ?? 0), 0);
    const frs = parts.reduce((a, p) => a + (p.fr ?? 0), 0);
    const left = L - fixed;
    if (left < -EPS) {
      throw new ScriptError(`split(): os tamanhos fixos somam ${fmtNum(fixed)} m, mais que os ${fmtNum(L)} m do eixo ${axis}`, null);
    }
    if (frs === 0 && Math.abs(left) > EPS) {
      throw new ScriptError(`split(): os tamanhos somam ${fmtNum(fixed)} m mas o eixo ${axis} tem ${fmtNum(L)} m`, null,
        'use "~" numa das partes para ela ocupar o que sobrar');
    }
    let at = this.min[i];
    return parts.map((p) => {
      const len = p.m ?? (left * p.fr) / frs;
      const s = this.with(i, at, at + len);
      at += len;
      return s;
    });
  }

  // repete cópias de ~size ao longo do eixo, ajustando o tamanho para caberem exatas
  tile(axis, size, f, gap) {
    const i = axisOf(axis, 'tile()');
    const L = this.size[i];
    const sz = num(size, 'size'), g = num(gap, 'gap');
    if (!(sz > 0)) throw new ScriptError('tile(): size deve ser maior que zero', null);
    if (g < 0) throw new ScriptError('tile(): gap não pode ser negativo', null);
    const n = Math.max(1, Math.round((L + g) / (sz + g)));
    const len = (L - g * (n - 1)) / n;
    if (!(len > 0)) throw new ScriptError('tile(): o gap não deixa espaço para as cópias', null);
    const cells = Array.from({ length: n }, (_, k) => this.with(i, this.min[i] + k * (len + g), this.min[i] + k * (len + g) + len));
    if (f === null) return cells;
    return group(cells.map((c, k) => c.fill(f, { index: k })), 'tile()');
  }

  inset(a) {
    const d = Array.isArray(a.x) ? a.x.map((v) => num(v, 'inset')) : a.y === null && a.z === null
      ? [a.x, a.x, a.x].map((v) => num(v, 'inset'))
      : [a.x, a.y ?? 0, a.z ?? 0].map((v) => num(v, 'inset'));
    const min = this.min.map((v, i) => v + d[i]), max = this.max.map((v, i) => v - d[i]);
    if (min.some((v, i) => v > max[i] + EPS)) throw new ScriptError('inset(): o recuo é maior que o escopo', null);
    return new Scope(min, max.map((v, i) => Math.max(v, min[i])));
  }

  // preenche com uma cor/material (caixa), uma forma (encaixada) ou uma função f(escopo)
  fill(x, opts = {}) {
    const { fit = 'stretch', round = 0, bevel = 0, align = 'bottom', index = null } = opts;
    if (x === null) return null;
    if (isCallable(x)) {
      if (!caller) throw new ScriptError('fill(): funções não disponíveis aqui', null);
      const nArgs = x instanceof Native ? x.params.length : (x.params?.length ?? 1);
      const r = caller(x, index !== null && nArgs >= 2 ? [this, index] : [this]);
      return r === null ? null : group([r], 'fill()');
    }
    if (x instanceof Shape) return this.fit(x, fit, align);
    if (Array.isArray(x) && x.some((v) => v instanceof Shape || isCallable(v))) {
      return group(x.map((v) => this.fill(v, opts)), 'fill()');
    }
    // cor ou material: uma caixa do tamanho do escopo
    const s = this.size;
    if (s.some((v) => v <= EPS)) return null;
    const r = Math.min(num(round, 'round'), Math.min(...s) / 2);
    const c = Math.min(num(bevel, 'bevel'), Math.min(...s) / 2);
    let box = c > 0 ? new Shape('cbox', { size: s, c, r }) : new Shape('box', { size: s, r });
    box = METHODS.color[1](box, { c: x });
    return METHODS.at[1](box, { x: tuple(this.center), y: 0, z: 0 });
  }

  // encaixa uma forma: "stretch" estica para ocupar o escopo, "contain" escala por igual até caber,
  // "none" só posiciona; nos dois últimos a forma fica apoiada na base (align="bottom") ou centrada
  fit(s, fit, align) {
    const b = s.bbox;
    const ss = [0, 1, 2].map((i) => b.max[i] - b.min[i]);
    if (ss.some((v) => !(v < 1e3))) throw new ScriptError('fill(): a forma é infinita', null);
    const sz = this.size;
    let k;
    if (fit === 'stretch') k = ss.map((v, i) => (v > EPS && sz[i] > EPS ? sz[i] / v : 1));
    else if (fit === 'contain') {
      const u = Math.min(...ss.map((v, i) => (v > EPS ? sz[i] / v : Infinity)));
      k = [u, u, u];
    } else if (fit === 'none') k = [1, 1, 1];
    else throw new ScriptError(`fill(): fit deve ser "stretch", "contain" ou "none", recebeu '${fit}'`, null);
    let out = s;
    if (k.some((v) => Math.abs(v - 1) > EPS)) out = METHODS.scale[1](s, { s: tuple(k), pivot: null });
    const ob = out.bbox;
    const oc = [0, 1, 2].map((i) => (ob.min[i] + ob.max[i]) / 2);
    const c = this.center;
    const dy = align === 'center' || fit === 'stretch' ? c[1] - oc[1] : this.min[1] - ob.min[1];
    if (!['bottom', 'center'].includes(align)) throw new ScriptError(`fill(): align deve ser "bottom" ou "center"`, null);
    return METHODS.at[1](out, { x: tuple([c[0] - oc[0], dy, c[2] - oc[2]]), y: 0, z: 0 });
  }

  attr3di(name) {
    const N = (n, params, fn) => new Native(n, params, fn);
    const sz = this.size, c = this.center;
    switch (name) {
      case 'w': case 'width': return sz[0];
      case 'h': case 'height': return sz[1];
      case 'd': case 'depth': return sz[2];
      case 'size': return tuple(sz);
      case 'center': return tuple(c);
      case 'x': return c[0];
      case 'y': return c[1];
      case 'z': return c[2];
      case 'left': return this.min[0];
      case 'right': return this.max[0];
      case 'bottom': return this.min[1];
      case 'top': return this.max[1];
      case 'back': return this.min[2];
      case 'front': return this.max[2];
      case 'min': return tuple([...this.min]);
      case 'max': return tuple([...this.max]);
      case 'split': return N('split', ['axis', 'sizes'], (a) => this.split(a.axis, a.sizes));
      case 'tile': return N('tile', ['axis', 'size', 'f=None', 'gap=0'], (a) => this.tile(a.axis, a.size, a.f, a.gap));
      case 'fill': return N('fill', ['what', 'fit="stretch"', 'round=0', 'bevel=0', 'align="bottom"'], (a) =>
        this.fill(a.what, { fit: String(a.fit), round: a.round, bevel: a.bevel, align: String(a.align) }));
      case 'inset': return N('inset', ['x', 'y=None', 'z=None'], (a) => this.inset(a));
    }
    const names = ['w', 'h', 'd', 'size', 'center', 'x', 'y', 'z', 'left', 'right', 'bottom', 'top', 'back', 'front',
      'min', 'max', 'split', 'tile', 'fill', 'inset'];
    throw new ScriptError(`escopo não tem o atributo '${name}'`, null, `atributos: ${names.join(', ')}`);
  }
}

// junta resultados de fill (formas, listas aninhadas, None) numa forma, ou None se vazio
function group(items, what) {
  const out = [];
  const walk = (v) => {
    if (v === null || v === undefined) return;
    if (Array.isArray(v)) { v.forEach(walk); return; }
    if (v instanceof Shape) { out.push(v); return; }
    throw new ScriptError(`${what}: a função deve devolver formas (ou None), devolveu ${typeName(v)}`, null);
  };
  walk(items);
  if (!out.length) return null;
  return out.length === 1 ? out[0] : union(out);
}

// funções globais e métodos das formas
export function scopeBuiltins() {
  return {
    space: new Native('space', ['w=1', 'h=None', 'd=None'], (a) => {
      const w = num(a.w, 'w'), h = a.h === null ? w : num(a.h, 'h'), d = a.d === null ? w : num(a.d, 'd');
      if (!(w > 0 && h > 0 && d > 0)) throw new ScriptError('space(): tamanhos devem ser positivos', null);
      // como as formas: centrado em x/z, mas com a base no chão (y = 0), pronto para construir
      return new Scope([-w / 2, 0, -d / 2], [w / 2, h, d / 2]);
    }),
  };
}

const SCOPE_METHODS = {
  space: [[], (s) => Scope.of(s, 'space()')],
  split: [['axis', 'sizes'], (s, a) => Scope.of(s, 'split()').split(a.axis, a.sizes)],
  tile: [['axis', 'size', 'f=None', 'gap=0'], (s, a) => Scope.of(s, 'tile()').tile(a.axis, a.size, a.f, a.gap)],
};

// formas também viram escopos (a caixa envolvente): forma.split(...), forma.tile(...), forma.space()
Object.assign(METHODS, SCOPE_METHODS);
