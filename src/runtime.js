// Tipos de valor e utilitários compartilhados pelo interpretador e pelas formas.
import { ScriptError } from './parser.js';
import { isExpr } from './expr.js';

// Função nativa com assinatura no estilo Python: ['w', 'h=None', 'round=0', '*items'].
export class Native {
  constructor(name, params, fn) {
    this.name = name;
    this.fn = fn;
    this.params = params.map(parseParam);
    this.star = this.params.find((p) => p.star)?.name ?? null;
    this.params = this.params.filter((p) => !p.star);
  }
  signature() {
    const ps = this.params.map((p) => (p.required ? p.name : `${p.name}=${repr(p.def)}`));
    if (this.star) ps.splice(this.params.filter((p) => p.required).length, 0, `*${this.star}`);
    return `${this.name}(${ps.join(', ')})`;
  }
}

function parseParam(spec) {
  if (spec.startsWith('*')) return { name: spec.slice(1), star: true };
  const eq = spec.indexOf('=');
  if (eq < 0) return { name: spec, required: true };
  const raw = spec.slice(eq + 1);
  let def;
  if (raw === 'None') def = null;
  else if (raw === 'True') def = true;
  else if (raw === 'False') def = false;
  else if (/^["']/.test(raw)) def = raw.slice(1, -1);
  else def = Number(raw);
  return { name: spec.slice(0, eq), required: false, def };
}

export function bindArgs(native, args, kwargs) {
  const out = {};
  const ps = native.params;
  let extra = [];
  args.forEach((v, i) => {
    if (i < ps.length && !(native.star && i >= ps.filter((p) => p.required).length)) out[ps[i].name] = v;
    else extra.push(v);
  });
  if (extra.length && !native.star) {
    throw new ScriptError(`${native.name}() recebeu argumentos demais (${args.length})`, null,
      `assinatura: ${native.signature()}`);
  }
  if (native.star) out[native.star] = extra;
  for (const [k, v] of kwargs) {
    const p = ps.find((q) => q.name === k);
    if (!p) {
      throw new ScriptError(`${native.name}() não tem o parâmetro '${k}'`, null,
        didYouMean(k, ps.map((q) => q.name)) ?? `assinatura: ${native.signature()}`);
    }
    if (k in out) throw new ScriptError(`${native.name}() recebeu '${k}' duas vezes`, null);
    out[k] = v;
  }
  for (const p of ps) {
    if (!(p.name in out)) {
      if (p.required) {
        throw new ScriptError(`${native.name}() precisa do argumento '${p.name}'`, null,
          `assinatura: ${native.signature()}`);
      }
      out[p.name] = p.def;
    }
  }
  return out;
}

export function levenshtein(a, b) {
  const m = a.length, n = b.length;
  const d = Array.from({ length: m + 1 }, (_, i) => [i]);
  for (let j = 1; j <= n; j++) d[0][j] = j;
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    }
  }
  return d[m][n];
}

export function didYouMean(word, options) {
  let best = null, bestD = Infinity;
  for (const o of options) {
    const dist = levenshtein(word.toLowerCase(), o.toLowerCase());
    if (dist < bestD) { bestD = dist; best = o; }
  }
  return best && bestD <= Math.max(2, Math.floor(word.length / 3)) ? `você quis dizer '${best}'?` : null;
}

export function typeName(v) {
  if (v === null || v === undefined) return 'None';
  if (typeof v === 'number') return 'número';
  if (typeof v === 'string') return 'texto';
  if (typeof v === 'boolean') return 'bool';
  if (Array.isArray(v)) return 'lista';
  if (v instanceof Map) return 'dict';
  if (v?.constructor?.name === 'Shape') return 'forma';
  if (isExpr(v)) return 'expressão animada';
  if (v instanceof Native || v?.isFunc) return 'função';
  return 'objeto';
}

export function repr(v) {
  if (v === null || v === undefined) return 'None';
  if (v === true) return 'True';
  if (v === false) return 'False';
  if (typeof v === 'number') return fmtNum(v);
  if (typeof v === 'string') return `'${v}'`;
  if (Array.isArray(v)) return v.isTuple ? `(${v.map(repr).join(', ')}${v.length === 1 ? ',' : ''})` : `[${v.map(repr).join(', ')}]`;
  if (v instanceof Map) return `{${[...v].map(([k, x]) => `${repr(k)}: ${repr(x)}`).join(', ')}}`;
  if (v?.describe) return v.describe();
  if (v instanceof Native) return `<função ${v.name}>`;
  if (v?.isFunc) return `<função ${v.name}>`;
  return String(v);
}

export function str(v) {
  return typeof v === 'string' ? v : repr(v);
}

export function fmtNum(x) {
  if (Number.isInteger(x)) return String(x);
  return String(Math.round(x * 1e6) / 1e6);
}

export function tuple(arr) {
  arr.isTuple = true;
  return arr;
}

export function num(v, what) {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (isExpr(v)) {
    throw new ScriptError(`${what} não aceita valores animados (time)`, null,
      'time funciona em at/move, rotate, scale (uniforme) e no glow de material()');
  }
  if (typeof v === 'boolean') return v ? 1 : 0;
  throw new ScriptError(`${what} deve ser um número, recebeu ${typeTag(v)}`, null);
}

// número ou expressão animada (time)
export function numT(v, what) {
  return isExpr(v) ? v : num(v, what);
}

export function vec3(v, what) {
  if (Array.isArray(v) && v.length === 3) return v.map((x, i) => num(x, `${what}[${i}]`));
  throw new ScriptError(`${what} deve ser uma tupla (x, y, z), recebeu ${typeTag(v)}`, null);
}

function typeTag(v) {
  const t = typeName(v);
  return t === 'None' ? 'None' : `${t} ${repr(v).slice(0, 30)}`;
}
