// Expressões simbólicas que dependem do tempo. `time` não é um número: é uma
// expressão que vira GLSL (uTime) e é avaliada a cada quadro na GPU.
// Para layout e caixas envolventes usamos o valor em t = 0.

export class Expr {
  constructor(op, args = []) {
    this.op = op;
    this.args = args;
  }

  glsl() {
    // variáveis de posição (x, y, z) viram campos de `ip`, o parâmetro das funções de formas implícitas
    if (this.op === 'var') return `ip.${this.args[0]}`;
    const a = this.args.map(glslOf);
    switch (this.op) {
      case 'time': return 'uTime';
      case 'hypot': return `sqrt(${a.map((x) => `${x} * ${x}`).join(' + ')})`;
      case '+': case '-': case '*': case '/': return `(${a[0]} ${this.op} ${a[1]})`;
      case '%': return `mod(${a[0]}, ${a[1]})`;
      case '**': return `pow(${a[0]}, ${a[1]})`;
      case 'neg': return `(-${a[0]})`;
      default: return `${GLSL_FN[this.op] ?? this.op}(${a.join(', ')})`;
    }
  }

  eval(t, env) {
    if (this.op === 'var') return env[this.args[0]];
    const a = this.args.map((x) => (x instanceof Expr ? x.eval(t, env) : x));
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

  describe() { return `<expressão: ${this.glsl().replace(/uTime/g, 'time').replace(/ip\./g, '')}>`; }

  usesTime() {
    return this.op === 'time' || this.args.some((x) => x instanceof Expr && x.usesTime());
  }

  usesPosition() {
    return this.op === 'var' || this.args.some((x) => x instanceof Expr && x.usesPosition());
  }

  // Compila para uma função (x, y, z, t) => número, sem eval(): usada na exportação, que
  // chama a fórmula milhões de vezes.
  compile() {
    const node = (e) => {
      if (!(e instanceof Expr)) return () => e;
      if (e.op === 'var') { const i = { x: 0, y: 1, z: 2 }[e.args[0]]; return (v) => v[i]; }
      if (e.op === 'time') return (v) => v[3];
      const k = e.args.map(node);
      switch (e.op) {
        case '+': return (v) => k[0](v) + k[1](v);
        case '-': return (v) => k[0](v) - k[1](v);
        case '*': return (v) => k[0](v) * k[1](v);
        case '/': return (v) => k[0](v) / k[1](v);
        case '%': return (v) => { const a = k[0](v), b = k[1](v); return a - b * Math.floor(a / b); };
        case '**': return (v) => k[0](v) ** k[1](v);
        case 'neg': return (v) => -k[0](v);
        default: { const f = JS_FN[e.op]; return (v) => f(...k.map((c) => c(v))); }
      }
    };
    const fn = node(this);
    return (x, y, z, t = 0) => fn([x, y, z, t]);
  }
}

const GLSL_FN = { lerp: 'mix', fract: 'fract', atan2: 'atan' };

const JS_FN = {
  sin: Math.sin, cos: Math.cos, tan: Math.tan, abs: Math.abs, sqrt: Math.sqrt,
  floor: Math.floor, exp: Math.exp, min: Math.min, max: Math.max,
  log: Math.log, ceil: Math.ceil, sign: Math.sign, atan2: Math.atan2, hypot: Math.hypot,
  step: (e, x) => (x < e ? 0 : 1),
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
// variáveis de posição para formas implícitas: implicit(lambda x, y, z: ...)
export const POS_VARS = { x: new Expr('var', ['x']), y: new Expr('var', ['y']), z: new Expr('var', ['z']) };
