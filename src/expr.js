// Expressões simbólicas que dependem do tempo. `time` não é um número: é uma
// expressão que vira GLSL (uTime) e é avaliada a cada quadro na GPU.
// Para layout e caixas envolventes usamos o valor em t = 0.

export class Expr {
  constructor(op, args = []) {
    this.op = op;
    this.args = args;
  }

  glsl() {
    const a = this.args.map(glslOf);
    switch (this.op) {
      case 'time': return 'uTime';
      case '+': case '-': case '*': case '/': return `(${a[0]} ${this.op} ${a[1]})`;
      case '%': return `mod(${a[0]}, ${a[1]})`;
      case '**': return `pow(${a[0]}, ${a[1]})`;
      case 'neg': return `(-${a[0]})`;
      default: return `${GLSL_FN[this.op] ?? this.op}(${a.join(', ')})`;
    }
  }

  eval(t) {
    const a = this.args.map((x) => (x instanceof Expr ? x.eval(t) : x));
    switch (this.op) {
      case 'time': return t;
      case '+': return a[0] + a[1];
      case '-': return a[0] - a[1];
      case '*': return a[0] * a[1];
      case '/': return a[0] / a[1];
      case '%': return a[0] - a[1] * Math.floor(a[0] / a[1]);
      case '**': return a[0] ** a[1];
      case 'neg': return -a[0];
      default: return JS_FN[this.op](...a);
    }
  }

  describe() { return `<expressão com time: ${this.glsl().replace(/uTime/g, 'time')}>`; }
}

const GLSL_FN = { lerp: 'mix', fract: 'fract' };

const JS_FN = {
  sin: Math.sin, cos: Math.cos, tan: Math.tan, abs: Math.abs, sqrt: Math.sqrt,
  floor: Math.floor, exp: Math.exp, min: Math.min, max: Math.max,
  fract: (x) => x - Math.floor(x),
  clamp: (x, lo, hi) => Math.min(hi, Math.max(lo, x)),
  lerp: (a, b, t) => a + (b - a) * t,
  smoothstep: (e0, e1, x) => { const t = Math.min(1, Math.max(0, (x - e0) / (e1 - e0))); return t * t * (3 - 2 * t); },
};

export const EXPR_FUNCS = Object.keys(JS_FN);

export const isExpr = (x) => x instanceof Expr;

// valor em t = 0 (para layout, caixas e enquadramento)
let layoutTime = 0;
export const val0 = (x) => (x instanceof Expr ? x.eval(layoutTime) : x);

// Roda fn() com o "t = 0" trocado por t: rodar o script e compilar dentro dela dá a caixa
// envolvente da cena naquele instante (usado para enquadrar vistas de cenas animadas).
export function withTime(t, fn) {
  const prev = layoutTime;
  layoutTime = t;
  try { return fn(); } finally { layoutTime = prev; }
}

function fmt(x) {
  let s = String(+(+x).toFixed(6));
  if (s === '-0') s = '0';
  return /[.e]/.test(s) ? s : s + '.0';
}

export function glslOf(x) {
  return x instanceof Expr ? x.glsl() : fmt(x);
}

// Constrói uma expressão; se nenhum argumento depende do tempo, já calcula o número.
export function sym(op, ...args) {
  if (!args.some(isExpr)) return op === 'neg' ? -args[0] : new Expr(op, args).eval(0);
  if (op === '+' && args[1] === 0) return args[0];
  if (op === '+' && args[0] === 0) return args[1];
  if (op === '*' && (args[0] === 1)) return args[1];
  if (op === '*' && (args[1] === 1)) return args[0];
  return new Expr(op, args);
}

export const TIME = new Expr('time');
