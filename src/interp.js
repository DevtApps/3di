// Interpretador do subconjunto de Python. Executa o script e devolve a cena montada.
import { parse, ScriptError } from './parser.js';
import { Native, bindArgs, didYouMean, typeName, repr, str, tuple, fmtNum } from './runtime.js';
import { Shape, shapeBuiltins, getShapeAttr, shapeBinary } from './shapes.js';
import { isExpr, sym, TIME, EXPR_FUNCS } from './expr.js';
import { toSrgb, hsvToRgb, rgbToHsv, isColorLike } from './color.js';
import { makeRng } from './lib/rand.js';
import { libBuiltins } from './lib/index.js';
import { rigBuiltins } from './rig.js';

class Scope {
  constructor(parent = null) { this.vars = new Map(); this.parent = parent; }
  lookup(name) {
    for (let s = this; s; s = s.parent) if (s.vars.has(name)) return s.vars;
    return null;
  }
  names() {
    const out = new Set();
    for (let s = this; s; s = s.parent) for (const k of s.vars.keys()) out.add(k);
    return [...out];
  }
}

class UserFunc {
  constructor(name, params, star, body, closure, isLambda = false) {
    Object.assign(this, { name, params, star, body, closure, isLambda });
    this.isFunc = true;
  }
}

class ReturnSignal { constructor(v) { this.v = v; } }
const BREAK = { signal: 'break' };
const CONTINUE = { signal: 'continue' };

const TIME_HINT = 'para variar com o tempo use contas e funções: sin, cos, abs, min, max, clamp, lerp, smoothstep, osc';

export function truthy(v) {
  if (isExpr(v)) throw new ScriptError('valores com time não podem ser usados em if/while/and/or', null, TIME_HINT);
  if (v === null || v === undefined || v === false || v === 0 || v === '') return false;
  if (Array.isArray(v)) return v.length > 0;
  if (v instanceof Map) return v.size > 0;
  return true;
}

function iterate(v) {
  if (Array.isArray(v)) return v;
  if (typeof v === 'string') return [...v];
  if (v instanceof Map) return [...v.keys()];
  throw new ScriptError(`não é possível percorrer ${typeName(v)} com for`, null, 'use uma lista ou range(n)');
}

function eq(a, b) {
  if (Array.isArray(a) && Array.isArray(b)) return a.length === b.length && a.every((x, i) => eq(x, b[i]));
  return a === b;
}

function compare(op, a, b) {
  if (isExpr(a) || isExpr(b)) throw new ScriptError(`não é possível comparar valores com time usando ${op}`, null, TIME_HINT);
  switch (op) {
    case '==': return eq(a, b);
    case '!=': return !eq(a, b);
    case 'is': return a === b;
    case 'is not': return a !== b;
    case 'in': return contains(b, a);
    case 'not in': return !contains(b, a);
  }
  const okNum = typeof a === 'number' && typeof b === 'number';
  const okStr = typeof a === 'string' && typeof b === 'string';
  if (!okNum && !okStr) throw new ScriptError(`não é possível comparar ${typeName(a)} com ${typeName(b)} usando ${op}`, null);
  switch (op) {
    case '<': return a < b;
    case '>': return a > b;
    case '<=': return a <= b;
    case '>=': return a >= b;
  }
}

function contains(container, x) {
  if (Array.isArray(container)) return container.some((y) => eq(x, y));
  if (typeof container === 'string') return container.includes(x);
  if (container instanceof Map) return container.has(x);
  throw new ScriptError(`'in' não funciona com ${typeName(container)}`, null);
}

function binary(op, a, b) {
  if (a instanceof Shape || b instanceof Shape) return shapeBinary(op, a, b);
  if (isExpr(a) || isExpr(b)) {
    const ok = (x) => isExpr(x) || typeof x === 'number';
    if (ok(a) && ok(b)) {
      if (['+', '-', '*', '/', '%', '**'].includes(op)) return sym(op, a, b);
      if (op === '//') return sym('floor', sym('/', a, b));
    }
    throw new ScriptError(`operação '${op}' não suportada entre ${typeName(a)} e ${typeName(b)}`, null, TIME_HINT);
  }
  const na = typeof a === 'number' || typeof a === 'boolean';
  const nb = typeof b === 'number' || typeof b === 'boolean';
  if (na && nb) {
    a = +a; b = +b;
    switch (op) {
      case '+': return a + b;
      case '-': return a - b;
      case '*': return a * b;
      case '/':
        if (b === 0) throw new ScriptError('divisão por zero', null);
        return a / b;
      case '//':
        if (b === 0) throw new ScriptError('divisão por zero', null);
        return Math.floor(a / b);
      case '%': return ((a % b) + b) % b;
      case '**': return a ** b;
      case '|': return a | b;
      case '&': return a & b;
      case '^': return a ^ b;
    }
  }
  if (op === '+' && typeof a === 'string' && typeof b === 'string') return a + b;
  if (op === '+' && Array.isArray(a) && Array.isArray(b)) {
    const r = [...a, ...b];
    return a.isTuple ? tuple(r) : r;
  }
  if (op === '*' && (typeof a === 'string' || Array.isArray(a)) && typeof b === 'number') {
    if (typeof a === 'string') return a.repeat(Math.max(0, b));
    const r = [];
    for (let i = 0; i < b; i++) r.push(...a);
    return a.isTuple ? tuple(r) : r;
  }
  if (op === '%' && typeof a === 'string') return a.replace(/%[sdf]/g, () => str(Array.isArray(b) ? b.shift() : b));
  let hint;
  if (op === '+' && (typeof a === 'string' || typeof b === 'string')) hint = 'use str(x) para converter números em texto, ou f"...{x}..."';
  if (Array.isArray(a) && Array.isArray(b)) hint = 'tuplas não fazem conta de vetor; some cada componente separadamente';
  throw new ScriptError(`operação '${op}' não suportada entre ${typeName(a)} e ${typeName(b)}`, null, hint);
}

function formatSpec(v, spec) {
  if (!spec) return str(v);
  const m = /^\.(\d+)f$/.exec(spec);
  if (m && typeof v === 'number') return v.toFixed(+m[1]);
  return str(v);
}


export class Interpreter {
  constructor({ maxSteps = 3e6 } = {}) {
    this.maxSteps = maxSteps;
    this.steps = 0;
    this.depth = 0;
    this.logs = [];
    this.scene = { shapes: [], camera: null, sun: null, sky: null, fog: null, anim: null };
    this.rng = makeRng(1);
    this.globals = new Scope();
    for (const [name, v] of Object.entries(this.builtins())) this.globals.vars.set(name, v);
    this.builtinNames = new Set(this.globals.vars.keys());
  }

  builtins() {
    const N = (name, params, fn) => new Native(name, params, fn);
    const math1 = (name, f) => N(name, ['x'], ({ x }) => {
      if (isExpr(x)) {
        if (EXPR_FUNCS.includes(name)) return sym(name, x);
        throw new ScriptError(`${name}() não funciona com time`, null, TIME_HINT);
      }
      return f(this.toNum(x, name));
    });
    const anyT = (xs) => xs.some(isExpr);
    const b = {
      pi: Math.PI,
      tau: Math.PI * 2,
      print: N('print', ['*values'], ({ values }) => { this.logs.push(values.map(str).join(' ')); return null; }),
      range: N('range', ['a', 'b=None', 'step=1'], ({ a, b, step }) => {
        let start = 0, stop = a;
        if (b !== null) { start = a; stop = b; }
        if (step === 0) throw new ScriptError('range() com passo 0', null);
        const out = [];
        for (let i = start; step > 0 ? i < stop : i > stop; i += step) {
          out.push(i);
          if (out.length > 1e5) throw new ScriptError('range() grande demais', null);
        }
        return out;
      }),
      linspace: N('linspace', ['a', 'b', 'n'], ({ a, b, n }) =>
        Array.from({ length: n }, (_, i) => (n === 1 ? a : a + ((b - a) * i) / (n - 1)))),
      len: N('len', ['x'], ({ x }) => {
        if (Array.isArray(x) || typeof x === 'string') return x.length;
        if (x instanceof Map) return x.size;
        throw new ScriptError(`len() não funciona com ${typeName(x)}`, null);
      }),
      abs: math1('abs', Math.abs),
      sqrt: math1('sqrt', Math.sqrt),
      sin: math1('sin', Math.sin),
      cos: math1('cos', Math.cos),
      tan: math1('tan', Math.tan),
      asin: math1('asin', Math.asin),
      acos: math1('acos', Math.acos),
      atan: math1('atan', Math.atan),
      exp: math1('exp', Math.exp),
      log: math1('log', Math.log),
      floor: math1('floor', Math.floor),
      ceil: math1('ceil', Math.ceil),
      radians: math1('radians', (x) => (x * Math.PI) / 180),
      degrees: math1('degrees', (x) => (x * 180) / Math.PI),
      atan2: N('atan2', ['y', 'x'], ({ y, x }) => Math.atan2(y, x)),
      hypot: N('hypot', ['*xs'], ({ xs }) => Math.hypot(...xs)),
      round: N('round', ['x', 'n=0'], ({ x, n }) => Math.round(x * 10 ** n) / 10 ** n),
      min: N('min', ['*xs'], ({ xs }) => {
        const a = xs.length === 1 ? xs[0] : xs;
        return anyT(a) ? a.reduce((p, q) => sym('min', p, q)) : Math.min(...a);
      }),
      max: N('max', ['*xs'], ({ xs }) => {
        const a = xs.length === 1 ? xs[0] : xs;
        return anyT(a) ? a.reduce((p, q) => sym('max', p, q)) : Math.max(...a);
      }),
      fract: math1('fract', (x) => x - Math.floor(x)),
      smoothstep: N('smoothstep', ['e0', 'e1', 'x'], ({ e0, e1, x }) => sym('smoothstep', e0, e1, x)),
      time: TIME,
      osc: N('osc', ['a', 'b', 'period=2'], ({ a, b, period }) =>
        // vai de a até b e volta, suavemente, a cada `period` segundos (começa em a)
        sym('+', a, sym('*', sym('-', b, a), sym('-', 0.5, sym('*', 0.5, sym('cos', sym('*', TIME, (2 * Math.PI) / period))))))),
      sum: N('sum', ['xs', 'start=0'], ({ xs, start }) => iterate(xs).reduce((acc, x) => binary('+', acc, x), start)),
      clamp: N('clamp', ['x', 'lo=0', 'hi=1'], ({ x, lo, hi }) => sym('clamp', x, lo, hi)),
      lerp: N('lerp', ['a', 'b', 't'], ({ a, b, t }) => sym('lerp', a, b, t)),
      // mistura de cores (nomes, "#rrggbb" ou tuplas) ou de números; devolve uma cor (r, g, b) em 0..1
      mix: N('mix', ['a', 'b', 't=0.5'], ({ a, b, t }) => {
        if (isColorLike(a) && isColorLike(b) && !(typeof a === 'number')) {
          const ca = toSrgb(a), cb = toSrgb(b);
          return tuple(ca.map((x, i) => x + (cb[i] - x) * t));
        }
        return sym('lerp', a, b, t);
      }),
      // cor a partir de matiz (0 a 360), saturação e brilho (0 a 1)
      hsv: N('hsv', ['h', 's=1', 'v=1'], ({ h, s, v }) => tuple(hsvToRgb(h, s, v))),
      // cor com variação aleatória (reprodutível com seed): hue em graus, sat e val em 0..1
      vary: N('vary', ['color', 'hue=0', 'sat=0', 'val=0'], ({ color, hue, sat, val }) => {
        const [h, s, v] = rgbToHsv(toSrgb(color));
        const j = (r) => (this.rng() * 2 - 1) * r;
        return tuple(hsvToRgb(h + j(hue), Math.min(1, Math.max(0, s + j(sat))), Math.min(1, Math.max(0, v + j(val)))));
      }),
      int: N('int', ['x'], ({ x }) => (typeof x === 'string' ? parseInt(x, 10) : Math.trunc(x))),
      float: N('float', ['x'], ({ x }) => Number(x)),
      str: N('str', ['x'], ({ x }) => str(x)),
      bool: N('bool', ['x'], ({ x }) => truthy(x)),
      list: N('list', ['x=None'], ({ x }) => (x === null ? [] : [...iterate(x)])),
      tuple: N('tuple', ['x=None'], ({ x }) => tuple(x === null ? [] : [...iterate(x)])),
      dict: N('dict', [], () => new Map()),
      enumerate: N('enumerate', ['xs', 'start=0'], ({ xs, start }) => iterate(xs).map((x, i) => tuple([i + start, x]))),
      zip: N('zip', ['*lists'], ({ lists }) => {
        const arrs = lists.map(iterate);
        const n = Math.min(...arrs.map((a) => a.length));
        return Array.from({ length: n }, (_, i) => tuple(arrs.map((a) => a[i])));
      }),
      sorted: N('sorted', ['xs', 'reverse=False'], ({ xs, reverse }) => {
        const r = [...iterate(xs)].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
        return reverse ? r.reverse() : r;
      }),
      reversed: N('reversed', ['xs'], ({ xs }) => [...iterate(xs)].reverse()),
      any: N('any', ['xs'], ({ xs }) => iterate(xs).some(truthy)),
      all: N('all', ['xs'], ({ xs }) => iterate(xs).every(truthy)),
      isinstance: N('isinstance', ['x', 't'], () => {
        throw new ScriptError('isinstance() não é suportado', null);
      }),
      seed: N('seed', ['n'], ({ n }) => { this.rng = makeRng(n); return null; }),
      random: N('random', [], () => this.rng()),
      uniform: N('uniform', ['a', 'b'], ({ a, b }) => a + (b - a) * this.rng()),
      randint: N('randint', ['a', 'b'], ({ a, b }) => a + Math.floor((b - a + 1) * this.rng())),
      choice: N('choice', ['xs'], ({ xs }) => { const a = iterate(xs); return a[Math.floor(this.rng() * a.length)]; }),
    };
    return { ...b, ...shapeBuiltins(this.scene), ...rigBuiltins(this.scene), ...libBuiltins({ rng: () => this.rng(), makeRng }) };
  }

  toNum(x, what) {
    if (typeof x === 'number') return x;
    throw new ScriptError(`${what}() espera um número, recebeu ${typeName(x)}`, null);
  }

  tick(line) {
    if (++this.steps > this.maxSteps) {
      throw new ScriptError('o script executou passos demais (loop infinito?)', line,
        'reduza o número de repetições');
    }
  }

  run(src) {
    const program = parse(src);
    this.execBlock(program, this.globals);
    return this.scene;
  }

  execBlock(stmts, scope) {
    for (const s of stmts) this.exec(s, scope);
  }

  exec(s, scope) {
    this.tick(s.line);
    try {
      switch (s.t) {
        case 'expr': this.eval(s.e, scope); return;
        case 'pass': return;
        case 'assign': {
          const v = this.eval(s.value, scope);
          for (const t of s.targets) this.assign(t, v, scope);
          return;
        }
        case 'aug': {
          const cur = this.eval(s.target, scope);
          const v = this.eval(s.value, scope);
          if (s.op === '+' && Array.isArray(cur) && !cur.isTuple) {
            cur.push(...(Array.isArray(v) ? v : [v]));
            return;
          }
          this.assign(s.target, binary(s.op, cur, v), scope);
          return;
        }
        case 'def':
          scope.vars.set(s.name, new UserFunc(s.name, s.params, s.star, s.body, scope));
          return;
        case 'return': throw new ReturnSignal(s.e ? this.eval(s.e, scope) : null);
        case 'break': throw BREAK;
        case 'continue': throw CONTINUE;
        case 'if': {
          for (const [cond, body] of s.tests) {
            if (truthy(this.eval(cond, scope))) { this.execBlock(body, scope); return; }
          }
          if (s.orelse) this.execBlock(s.orelse, scope);
          return;
        }
        case 'for': {
          const items = iterate(this.eval(s.iter, scope));
          for (const item of [...items]) {
            this.bindTarget(s.target, item, scope, s.line);
            try { this.execBlock(s.body, scope); } catch (e) {
              if (e === BREAK) break;
              if (e === CONTINUE) continue;
              throw e;
            }
          }
          return;
        }
        case 'while': {
          while (truthy(this.eval(s.cond, scope))) {
            this.tick(s.line);
            try { this.execBlock(s.body, scope); } catch (e) {
              if (e === BREAK) break;
              if (e === CONTINUE) continue;
              throw e;
            }
          }
          return;
        }
      }
      throw new ScriptError(`comando desconhecido ${s.t}`, s.line);
    } catch (e) {
      if (e instanceof ScriptError && !e.line) e.line = s.line;
      throw e;
    }
  }

  bindTarget(target, v, scope, line) {
    if (typeof target === 'string') { scope.vars.set(target, v); return; }
    const items = iterate(v);
    if (items.length !== target.length) {
      throw new ScriptError(`esperava ${target.length} valores para desempacotar, recebeu ${items.length}`, line);
    }
    target.forEach((t, i) => this.bindTarget(t, items[i], scope, line));
  }

  assign(t, v, scope) {
    if (t.t === 'name') {
      scope.vars.set(t.name, v);
    } else if (t.t === 'tuple' || t.t === 'list') {
      const items = iterate(v);
      const si = t.items.findIndex((x) => x.t === 'starred');
      if (si < 0) {
        if (items.length !== t.items.length) {
          throw new ScriptError(`esperava ${t.items.length} valores para desempacotar, recebeu ${items.length}`, t.line);
        }
        t.items.forEach((x, i) => this.assign(x, items[i], scope));
        return;
      }
      const after = t.items.length - si - 1;
      if (items.length < t.items.length - 1) {
        throw new ScriptError(`esperava pelo menos ${t.items.length - 1} valores para desempacotar, recebeu ${items.length}`, t.line);
      }
      t.items.slice(0, si).forEach((x, i) => this.assign(x, items[i], scope));
      this.assign(t.items[si].e, items.slice(si, items.length - after), scope);
      t.items.slice(si + 1).forEach((x, i) => this.assign(x, items[items.length - after + i], scope));
    } else if (t.t === 'index') {
      const obj = this.eval(t.obj, scope);
      const idx = this.eval(t.idx, scope);
      if (Array.isArray(obj)) {
        if (obj.isTuple) throw new ScriptError('tuplas não podem ser alteradas', t.line, 'use uma lista [..]');
        obj[this.normIndex(obj, idx, t.line)] = v;
      } else if (obj instanceof Map) obj.set(idx, v);
      else throw new ScriptError(`não é possível atribuir por índice em ${typeName(obj)}`, t.line);
    } else {
      throw new ScriptError('formas são imutáveis: não dá para atribuir atributos', t.line,
        'use os métodos, ex: mesa = mesa.at(1, 0, 0)');
    }
  }

  evalItems(items, scope) {
    const out = [];
    for (const x of items) {
      if (x.t === 'starred') out.push(...iterate(this.eval(x.e, scope)));
      else out.push(this.eval(x, scope));
    }
    return out;
  }

  normIndex(arr, idx, line) {
    if (typeof idx !== 'number' || !Number.isInteger(idx)) throw new ScriptError('índice deve ser inteiro', line);
    const i = idx < 0 ? arr.length + idx : idx;
    if (i < 0 || i >= arr.length) throw new ScriptError(`índice ${idx} fora da lista (tamanho ${arr.length})`, line);
    return i;
  }

  eval(e, scope) {
    try {
      return this.evalInner(e, scope);
    } catch (err) {
      if (err instanceof ScriptError && !err.line) err.line = e.line;
      throw err;
    }
  }

  evalInner(e, scope) {
    switch (e.t) {
      case 'num': return e.v;
      case 'str': return e.v;
      case 'const': return e.v;
      case 'concat': return e.parts.map((p) => (p.t === 'fmt' ? formatSpec(this.eval(p.e, scope), p.spec) : this.eval(p, scope))).join('');
      case 'name': {
        const vars = scope.lookup(e.name);
        if (!vars) {
          throw new ScriptError(`'${e.name}' não está definido`, e.line,
            didYouMean(e.name, scope.names()) ?? 'defina a variável antes de usar');
        }
        return vars.get(e.name);
      }
      case 'list': return this.evalItems(e.items, scope);
      case 'tuple': return tuple(this.evalItems(e.items, scope));
      case 'starred': throw new ScriptError("'*' fora de lugar", e.line);
      case 'dict': {
        const m = new Map();
        e.keys.forEach((k, i) => m.set(this.eval(k, scope), this.eval(e.values[i], scope)));
        return m;
      }
      case 'unary': {
        const v = this.eval(e.e, scope);
        if (e.op === '-') {
          if (typeof v === 'number') return -v;
          if (isExpr(v)) return sym('neg', v);
          throw new ScriptError(`não é possível negar ${typeName(v)}`, e.line);
        }
        if (e.op === '+') return v;
        return ~v;
      }
      case 'not': return !truthy(this.eval(e.e, scope));
      case 'and': { const a = this.eval(e.a, scope); return truthy(a) ? this.eval(e.b, scope) : a; }
      case 'or': { const a = this.eval(e.a, scope); return truthy(a) ? a : this.eval(e.b, scope); }
      case 'ifexp': return truthy(this.eval(e.cond, scope)) ? this.eval(e.a, scope) : this.eval(e.b, scope);
      case 'bin': return binary(e.op, this.eval(e.a, scope), this.eval(e.b, scope));
      case 'cmp': {
        let left = this.eval(e.first, scope);
        for (let i = 0; i < e.ops.length; i++) {
          const right = this.eval(e.rest[i], scope);
          if (!compare(e.ops[i], left, right)) return false;
          left = right;
        }
        return true;
      }
      case 'lambda': return new UserFunc('<lambda>', e.params, null, e.body, scope, true);
      case 'comp': {
        const out = [];
        const inner = new Scope(scope);
        const loop = (ci) => {
          if (ci === e.clauses.length) { out.push(this.eval(e.elt, inner)); return; }
          const c = e.clauses[ci];
          for (const item of iterate(this.eval(c.iter, inner))) {
            this.tick(e.line);
            this.bindTarget(c.target, item, inner, e.line);
            if (c.conds.every((cond) => truthy(this.eval(cond, inner)))) loop(ci + 1);
          }
        };
        loop(0);
        return out;
      }
      case 'attr': return this.getAttr(this.eval(e.obj, scope), e.name);
      case 'index': {
        const obj = this.eval(e.obj, scope);
        if (e.idx.t === 'slice') {
          if (!Array.isArray(obj) && typeof obj !== 'string') throw new ScriptError(`não é possível fatiar ${typeName(obj)}`, e.line);
          const n = obj.length;
          const g = (x, d) => { if (!x) return d; const v = this.eval(x, scope); return v < 0 ? Math.max(0, n + v) : Math.min(n, v); };
          const step = e.idx.step ? this.eval(e.idx.step, scope) : 1;
          if (step !== 1) {
            const arr = [...obj], r = [];
            const st = g(e.idx.start, step > 0 ? 0 : n - 1), sp = g(e.idx.stop, step > 0 ? n : -1);
            for (let i = st; step > 0 ? i < sp : i > sp; i += step) r.push(arr[i]);
            return typeof obj === 'string' ? r.join('') : r;
          }
          return obj.slice(g(e.idx.start, 0), g(e.idx.stop, n));
        }
        const idx = this.eval(e.idx, scope);
        if (Array.isArray(obj) || typeof obj === 'string') return obj[this.normIndex(obj, idx, e.line)];
        if (obj instanceof Map) {
          if (!obj.has(idx)) throw new ScriptError(`chave ${repr(idx)} não existe no dict`, e.line);
          return obj.get(idx);
        }
        throw new ScriptError(`não é possível indexar ${typeName(obj)}`, e.line);
      }
      case 'call': {
        const fn = this.eval(e.fn, scope);
        const args = [];
        const kwargs = [];
        for (const a of e.args) {
          const v = this.eval(a.e, scope);
          if (a.star) args.push(...iterate(v));
          else if (a.kw) kwargs.push([a.kw, v]);
          else args.push(v);
        }
        return this.call(fn, args, kwargs, e);
      }
    }
    throw new ScriptError(`expressão desconhecida ${e.t}`, e.line);
  }

  call(fn, args, kwargs, node) {
    if (fn instanceof Native) {
      try {
        return fn.fn(bindArgs(fn, args, kwargs), node);
      } catch (err) {
        if (err instanceof ScriptError && !err.line) err.line = node.line;
        throw err;
      }
    }
    if (fn instanceof UserFunc) {
      if (++this.depth > 200) throw new ScriptError('recursão profunda demais', node.line);
      try {
        const local = new Scope(fn.closure);
        const ps = fn.params;
        args.forEach((v, i) => {
          if (i < ps.length) local.vars.set(ps[i].name, v);
        });
        const extra = args.slice(ps.length);
        if (extra.length && !fn.star) {
          throw new ScriptError(`${fn.name}() recebeu ${args.length} argumentos, aceita ${ps.length}`, node.line);
        }
        if (fn.star) local.vars.set(fn.star, extra);
        for (const [k, v] of kwargs) {
          if (!ps.some((p) => p.name === k)) {
            throw new ScriptError(`${fn.name}() não tem o parâmetro '${k}'`, node.line, didYouMean(k, ps.map((p) => p.name)));
          }
          local.vars.set(k, v);
        }
        for (const p of ps) {
          if (!local.vars.has(p.name)) {
            if (!p.def) throw new ScriptError(`${fn.name}() precisa do argumento '${p.name}'`, node.line);
            local.vars.set(p.name, this.eval(p.def, fn.closure));
          }
        }
        if (fn.isLambda) return this.eval(fn.body, local);
        try {
          this.execBlock(fn.body, local);
        } catch (sig) {
          if (sig instanceof ReturnSignal) return sig.v;
          throw sig;
        }
        return null;
      } finally {
        this.depth--;
      }
    }
    throw new ScriptError(`${typeName(fn)} ${repr(fn).slice(0, 30)} não é uma função`, node.line);
  }

  getAttr(obj, name) {
    if (obj instanceof Shape) return getShapeAttr(obj, name);
    if (obj?.attr3di) return obj.attr3di(name);
    const N = (n, params, f) => new Native(n, params, f);
    if (Array.isArray(obj)) {
      const methods = {
        append: N('append', ['x'], ({ x }) => { this.mutable(obj); obj.push(x); return null; }),
        extend: N('extend', ['xs'], ({ xs }) => { this.mutable(obj); obj.push(...iterate(xs)); return null; }),
        insert: N('insert', ['i', 'x'], ({ i, x }) => { this.mutable(obj); obj.splice(i, 0, x); return null; }),
        pop: N('pop', ['i=-1'], ({ i }) => { this.mutable(obj); return obj.splice(this.normIndex(obj, i, null), 1)[0]; }),
        reverse: N('reverse', [], () => { this.mutable(obj); obj.reverse(); return null; }),
        index: N('index', ['x'], ({ x }) => {
          const i = obj.findIndex((y) => eq(x, y));
          if (i < 0) throw new ScriptError(`${repr(x)} não está na lista`, null);
          return i;
        }),
        count: N('count', ['x'], ({ x }) => obj.filter((y) => eq(x, y)).length),
      };
      if (name in methods) return methods[name];
      throw new ScriptError(`lista não tem o método '${name}'`, null, didYouMean(name, Object.keys(methods)));
    }
    if (typeof obj === 'string') {
      const methods = {
        upper: N('upper', [], () => obj.toUpperCase()),
        lower: N('lower', [], () => obj.toLowerCase()),
        join: N('join', ['xs'], ({ xs }) => iterate(xs).map(str).join(obj)),
        split: N('split', ['sep=None'], ({ sep }) => (sep === null ? obj.trim().split(/\s+/) : obj.split(sep))),
        startswith: N('startswith', ['s'], ({ s }) => obj.startsWith(s)),
        endswith: N('endswith', ['s'], ({ s }) => obj.endsWith(s)),
        replace: N('replace', ['a', 'b'], ({ a, b }) => obj.split(a).join(b)),
        format: N('format', ['*xs'], ({ xs }) => { let i = 0; return obj.replace(/\{\}/g, () => str(xs[i++])); }),
      };
      if (name in methods) return methods[name];
      throw new ScriptError(`texto não tem o método '${name}'`, null, didYouMean(name, Object.keys(methods)));
    }
    if (obj instanceof Map) {
      const methods = {
        get: N('get', ['k', 'default=None'], ({ k, default: d }) => (obj.has(k) ? obj.get(k) : d)),
        keys: N('keys', [], () => [...obj.keys()]),
        values: N('values', [], () => [...obj.values()]),
        items: N('items', [], () => [...obj].map(([k, v]) => tuple([k, v]))),
      };
      if (name in methods) return methods[name];
      throw new ScriptError(`dict não tem o método '${name}'`, null, didYouMean(name, Object.keys(methods)));
    }
    throw new ScriptError(`${typeName(obj)} não tem o atributo '${name}'`, null);
  }

  mutable(arr) {
    if (arr.isTuple) throw new ScriptError('tuplas não podem ser alteradas', null, 'use uma lista [..]');
  }
}

export function runScript(src, opts) {
  const it = new Interpreter(opts);
  try {
    const scene = it.run(src);
    return { ok: true, scene, logs: it.logs };
  } catch (e) {
    if (e === BREAK || e === CONTINUE) e = new ScriptError("'break'/'continue' fora de um loop", null);
    if (e instanceof ReturnSignal) e = new ScriptError("'return' fora de uma função", null);
    if (!(e instanceof ScriptError)) {
      console.error(e);
      e = new ScriptError(`erro interno: ${e.message}`, null);
    }
    return { ok: false, error: e, logs: it.logs };
  }
}

export { fmtNum };
