// Lexer + parser para o subconjunto de Python usado pela linguagem 3DI.

export class ScriptError extends Error {
  constructor(message, line, hint) {
    super(message);
    this.line = line;
    this.hint = hint;
  }
  toString() {
    const where = this.line ? `linha ${this.line}: ` : '';
    return where + this.message + (this.hint ? `\n  dica: ${this.hint}` : '');
  }
}

const KEYWORDS = new Set([
  'def', 'return', 'for', 'in', 'if', 'elif', 'else', 'while', 'and', 'or', 'not',
  'True', 'False', 'None', 'pass', 'break', 'continue', 'lambda', 'is',
]);

const OPS2 = ['**', '//', '==', '!=', '<=', '>=', '+=', '-=', '*=', '/=', '->'];
const OPS1 = '()[]{},:.+-*/%<>=|&^~@;';

export function tokenize(src) {
  src = src.replace(/\r\n?/g, '\n').replace(/\t/g, '    ');
  const toks = [];
  const indents = [0];
  let i = 0, line = 1, depth = 0, atLineStart = true;
  const push = (type, value) => toks.push({ type, value, line });

  while (i < src.length) {
    if (atLineStart && depth === 0) {
      let col = 0;
      while (src[i] === ' ') { col++; i++; }
      if (i >= src.length) break;
      if (src[i] === '\n' || src[i] === '#') {
        while (i < src.length && src[i] !== '\n') i++;
        if (src[i] === '\n') { i++; line++; }
        continue;
      }
      atLineStart = false;
      if (col > indents.at(-1)) {
        indents.push(col);
        push('INDENT');
      } else {
        while (col < indents.at(-1)) { indents.pop(); push('DEDENT'); }
        if (col !== indents.at(-1)) {
          throw new ScriptError('indentação inconsistente', line, 'use sempre 4 espaços por nível');
        }
      }
    }

    const c = src[i];
    if (c === '\n') {
      if (depth === 0) { push('NEWLINE'); atLineStart = true; }
      i++; line++;
      continue;
    }
    if (c === ' ') { i++; continue; }
    if (c === '#') { while (i < src.length && src[i] !== '\n') i++; continue; }
    if (c === '\\' && src[i + 1] === '\n') { i += 2; line++; continue; }

    if (/[0-9]/.test(c) || (c === '.' && /[0-9]/.test(src[i + 1]))) {
      const m = /^(?:\d[\d_]*\.?[\d_]*|\.\d[\d_]*)(?:[eE][+-]?\d+)?/.exec(src.slice(i, i + 64));
      push('NUM', parseFloat(m[0].replace(/_/g, '')));
      i += m[0].length;
      continue;
    }

    const isStrStart = c === '"' || c === "'";
    const isFStr = (c === 'f' || c === 'F') && (src[i + 1] === '"' || src[i + 1] === "'");
    if (isStrStart || isFStr) {
      if (isFStr) i++;
      const q = src[i];
      const triple = src.startsWith(q.repeat(3), i);
      const end = triple ? q.repeat(3) : q;
      i += end.length;
      let s = '';
      const startLine = line;
      while (true) {
        if (i >= src.length) throw new ScriptError('texto (string) sem fechar aspas', startLine);
        if (src.startsWith(end, i)) { i += end.length; break; }
        const ch = src[i];
        if (ch === '\n') {
          if (!triple) throw new ScriptError('texto (string) sem fechar aspas', startLine);
          line++;
        }
        if (ch === '\\' && i + 1 < src.length) {
          const e = src[i + 1];
          s += { n: '\n', t: '\t', '\\': '\\', "'": "'", '"': '"' }[e] ?? '\\' + e;
          i += 2;
          continue;
        }
        s += ch;
        i++;
      }
      push(isFStr ? 'FSTR' : 'STR', s);
      continue;
    }

    if (/[\p{L}_]/u.test(c)) {
      let j = i + 1;
      while (j < src.length && /[\p{L}\p{N}_]/u.test(src[j])) j++;
      const word = src.slice(i, j);
      push(KEYWORDS.has(word) ? 'KW' : 'NAME', word);
      i = j;
      continue;
    }

    const two = src.slice(i, i + 2);
    if (OPS2.includes(two)) { push('OP', two); i += 2; continue; }
    if (OPS1.includes(c)) {
      if ('([{'.includes(c)) depth++;
      if (')]}'.includes(c)) depth = Math.max(0, depth - 1);
      push('OP', c);
      i++;
      continue;
    }
    throw new ScriptError(`caractere inesperado '${c}'`, line);
  }
  if (toks.length && toks.at(-1).type !== 'NEWLINE') push('NEWLINE');
  while (indents.length > 1) { indents.pop(); push('DEDENT'); }
  push('EOF');
  return toks;
}

function describe(tok) {
  switch (tok.type) {
    case 'NEWLINE': return 'fim de linha';
    case 'INDENT': return 'indentação';
    case 'DEDENT': return 'fim de bloco';
    case 'EOF': return 'fim do arquivo';
    case 'STR': case 'FSTR': return 'texto';
    default: return `'${tok.value}'`;
  }
}

const AUG_OPS = ['+=', '-=', '*=', '/='];
const COMP_OPS = ['<', '>', '==', '!=', '<=', '>='];

class Parser {
  constructor(tokens) { this.t = tokens; this.i = 0; }
  peek(o = 0) { return this.t[Math.min(this.i + o, this.t.length - 1)]; }
  next() { return this.t[this.i++]; }
  is(type, value) {
    const k = this.peek();
    return k.type === type && (value === undefined || k.value === value);
  }
  isOp(v) { return this.is('OP', v); }
  isKw(v) { return this.is('KW', v); }
  accept(type, value) { return this.is(type, value) ? this.next() : null; }
  expect(type, value, hint) {
    if (this.is(type, value)) return this.next();
    const k = this.peek();
    const want = value !== undefined ? `'${value}'` : { NAME: 'um nome', INDENT: 'um bloco indentado' }[type] ?? type;
    throw new ScriptError(`esperado ${want}, encontrado ${describe(k)}`, k.line, hint);
  }

  program() {
    const body = [];
    while (!this.is('EOF')) {
      if (this.accept('NEWLINE')) continue;
      if (this.is('INDENT')) throw new ScriptError('indentação inesperada', this.peek().line);
      body.push(...this.statement());
    }
    return body;
  }

  statement() {
    const k = this.peek();
    if (k.type === 'KW') {
      if (k.value === 'def') return [this.funcdef()];
      if (k.value === 'if') return [this.ifStmt()];
      if (k.value === 'for') return [this.forStmt()];
      if (k.value === 'while') return [this.whileStmt()];
    }
    return this.simpleLine();
  }

  simpleLine() {
    const out = [this.simple()];
    while (this.accept('OP', ';')) {
      if (this.is('NEWLINE') || this.is('EOF')) break;
      out.push(this.simple());
    }
    if (!this.accept('NEWLINE') && !this.is('EOF') && !this.is('DEDENT')) {
      const k = this.peek();
      throw new ScriptError(`${describe(k)} inesperado`, k.line,
        k.value === '=' ? 'para comparar use ==' : 'cada comando deve ficar em sua própria linha');
    }
    return out;
  }

  simple() {
    const line = this.peek().line;
    if (this.accept('KW', 'pass')) return { t: 'pass', line };
    if (this.accept('KW', 'break')) return { t: 'break', line };
    if (this.accept('KW', 'continue')) return { t: 'continue', line };
    if (this.accept('KW', 'return')) {
      const e = this.is('NEWLINE') || this.is('EOF') || this.isOp(';') ? null : this.exprList();
      return { t: 'return', e, line };
    }
    const e = this.exprList();
    if (this.isOp('=')) {
      const parts = [e];
      while (this.accept('OP', '=')) parts.push(this.exprList());
      const value = parts.pop();
      parts.forEach((p) => checkTarget(p));
      return { t: 'assign', targets: parts, value, line };
    }
    for (const op of AUG_OPS) {
      if (this.accept('OP', op)) {
        checkTarget(e);
        return { t: 'aug', target: e, op: op[0], value: this.exprList(), line };
      }
    }
    return { t: 'expr', e, line };
  }

  block() {
    this.expect('OP', ':', 'blocos (def, if, for...) terminam com dois-pontos');
    if (this.accept('NEWLINE')) {
      this.expect('INDENT', undefined, 'o conteúdo do bloco deve ser indentado com 4 espaços');
      const body = [];
      while (!this.accept('DEDENT') && !this.is('EOF')) {
        if (this.accept('NEWLINE')) continue;
        body.push(...this.statement());
      }
      return body;
    }
    return this.simpleLine();
  }

  funcdef() {
    const line = this.next().line;
    const name = this.expect('NAME').value;
    this.expect('OP', '(');
    const params = [];
    let star = null;
    while (!this.isOp(')')) {
      if (this.accept('OP', '*')) {
        star = this.expect('NAME').value;
      } else {
        const p = { name: this.expect('NAME').value, def: null };
        if (this.accept('OP', '=')) p.def = this.expr();
        params.push(p);
      }
      if (!this.accept('OP', ',')) break;
    }
    this.expect('OP', ')');
    if (this.accept('OP', '->')) this.expr();
    return { t: 'def', name, params, star, body: this.block(), line };
  }

  ifStmt() {
    const line = this.next().line;
    const tests = [[this.expr(), this.block()]];
    let orelse = null;
    while (true) {
      if (this.accept('KW', 'elif')) tests.push([this.expr(), this.block()]);
      else if (this.accept('KW', 'else')) { orelse = this.block(); break; } else break;
    }
    return { t: 'if', tests, orelse, line };
  }

  // alvo de for/compreensão: nomes e tuplas aninhadas, ex: (a, b), c
  targetList() {
    const one = () => {
      if (this.accept('OP', '(')) {
        const inner = this.targetList();
        this.expect('OP', ')');
        return inner;
      }
      return this.expect('NAME').value;
    };
    const first = one();
    if (!this.isOp(',')) return first;
    const items = [first];
    while (this.accept('OP', ',')) {
      if (!this.is('NAME') && !this.isOp('(')) break;
      items.push(one());
    }
    return items;
  }

  forStmt() {
    const line = this.next().line;
    const target = this.targetList();
    this.expect('KW', 'in');
    const iter = this.exprList();
    return { t: 'for', target, iter, body: this.block(), line };
  }

  whileStmt() {
    const line = this.next().line;
    const cond = this.expr();
    return { t: 'while', cond, body: this.block(), line };
  }

  exprList() {
    const line = this.peek().line;
    const first = this.starOrExpr();
    if (!this.isOp(',')) {
      if (first.t === 'starred') throw new ScriptError("'*' só pode ser usado dentro de uma lista ou desempacotamento", line);
      return first;
    }
    const items = [first];
    while (this.accept('OP', ',')) {
      if (this.is('NEWLINE') || this.isOp('=') || this.isOp(')') || this.is('EOF')) break;
      items.push(this.starOrExpr());
    }
    return { t: 'tuple', items, line };
  }

  starOrExpr() {
    const line = this.peek().line;
    if (this.accept('OP', '*')) return { t: 'starred', e: this.bitOr(), line };
    return this.expr();
  }

  expr() {
    const line = this.peek().line;
    if (this.accept('KW', 'lambda')) {
      const params = [];
      while (!this.isOp(':')) {
        const p = { name: this.expect('NAME').value, def: null };
        if (this.accept('OP', '=')) p.def = this.expr();
        params.push(p);
        if (!this.accept('OP', ',')) break;
      }
      this.expect('OP', ':');
      return { t: 'lambda', params, body: this.expr(), line };
    }
    const e = this.orTest();
    if (this.accept('KW', 'if')) {
      const cond = this.orTest();
      this.expect('KW', 'else', "expressão condicional precisa de 'else'");
      return { t: 'ifexp', cond, a: e, b: this.expr(), line };
    }
    return e;
  }

  orTest() {
    let e = this.andTest();
    while (this.is('KW', 'or')) { const line = this.next().line; e = { t: 'or', a: e, b: this.andTest(), line }; }
    return e;
  }

  andTest() {
    let e = this.notTest();
    while (this.is('KW', 'and')) { const line = this.next().line; e = { t: 'and', a: e, b: this.notTest(), line }; }
    return e;
  }

  notTest() {
    if (this.is('KW', 'not')) { const line = this.next().line; return { t: 'not', e: this.notTest(), line }; }
    return this.comparison();
  }

  comparison() {
    const line = this.peek().line;
    const first = this.bitOr();
    const ops = [], rest = [];
    while (true) {
      let op = null;
      if (COMP_OPS.some((o) => this.isOp(o))) op = this.next().value;
      else if (this.isKw('in')) { this.next(); op = 'in'; }
      else if (this.isKw('not') && this.peek(1).type === 'KW' && this.peek(1).value === 'in') { this.i += 2; op = 'not in'; }
      else if (this.isKw('is')) { this.next(); op = this.accept('KW', 'not') ? 'is not' : 'is'; }
      if (!op) break;
      ops.push(op);
      rest.push(this.bitOr());
    }
    return ops.length ? { t: 'cmp', first, ops, rest, line } : first;
  }

  binLevel(next, ops) {
    let e = next();
    while (ops.some((o) => this.isOp(o))) {
      const tok = this.next();
      e = { t: 'bin', op: tok.value, a: e, b: next(), line: tok.line };
    }
    return e;
  }

  bitOr() { return this.binLevel(() => this.bitXor(), ['|']); }
  bitXor() { return this.binLevel(() => this.bitAnd(), ['^']); }
  bitAnd() { return this.binLevel(() => this.arith(), ['&']); }
  arith() { return this.binLevel(() => this.term(), ['+', '-']); }
  term() { return this.binLevel(() => this.factor(), ['*', '/', '//', '%', '@']); }

  factor() {
    if (this.isOp('-') || this.isOp('+') || this.isOp('~')) {
      const tok = this.next();
      return { t: 'unary', op: tok.value, e: this.factor(), line: tok.line };
    }
    return this.power();
  }

  power() {
    const e = this.postfix();
    if (this.isOp('**')) {
      const line = this.next().line;
      return { t: 'bin', op: '**', a: e, b: this.factor(), line };
    }
    return e;
  }

  postfix() {
    let e = this.atom();
    while (true) {
      const line = this.peek().line;
      if (this.accept('OP', '(')) {
        e = { t: 'call', fn: e, args: this.callArgs(), line };
      } else if (this.accept('OP', '.')) {
        e = { t: 'attr', obj: e, name: this.expect('NAME', undefined, 'depois do ponto vem o nome de um método').value, line };
      } else if (this.accept('OP', '[')) {
        let idx;
        if (this.isOp(':') || this.lookaheadSlice()) idx = this.sliceExpr();
        else idx = this.exprList();
        this.expect('OP', ']');
        e = { t: 'index', obj: e, idx, line };
      } else break;
    }
    return e;
  }

  lookaheadSlice() {
    // procura ':' no mesmo nível antes do ']'
    let d = 0;
    for (let j = this.i; j < this.t.length; j++) {
      const k = this.t[j];
      if (k.type !== 'OP') continue;
      if ('([{'.includes(k.value)) d++;
      else if (')}'.includes(k.value)) d--;
      else if (k.value === ']') { if (d === 0) return false; d--; }
      else if (k.value === ':' && d === 0) return true;
    }
    return false;
  }

  sliceExpr() {
    const line = this.peek().line;
    const part = () => (this.isOp(':') || this.isOp(']') ? null : this.expr());
    const start = part();
    this.expect('OP', ':');
    const stop = part();
    let step = null;
    if (this.accept('OP', ':')) step = part();
    return { t: 'slice', start, stop, step, line };
  }

  callArgs() {
    const args = [];
    while (!this.isOp(')')) {
      const line = this.peek().line;
      if (this.accept('OP', '*')) {
        args.push({ star: true, e: this.expr(), line });
      } else if (this.is('NAME') && this.peek(1).type === 'OP' && this.peek(1).value === '=') {
        const kw = this.next().value;
        this.next();
        args.push({ kw, e: this.expr(), line });
      } else {
        const e = this.expr();
        if (this.isKw('for')) {
          args.push({ e: this.comprehension(e, 'list', line), line });
        } else {
          if (args.some((a) => a.kw)) {
            throw new ScriptError('argumento posicional depois de argumento nomeado', line,
              'coloque os argumentos sem nome antes dos nomeados (ex: box(1, 2, 3, round=0.1))');
          }
          args.push({ e, line });
        }
      }
      if (!this.accept('OP', ',')) break;
    }
    this.expect('OP', ')', 'faltou fechar o parêntese da chamada');
    return args;
  }

  comprehension(elt, kind, line) {
    const clauses = [];
    while (this.accept('KW', 'for')) {
      const target = this.targetList();
      this.expect('KW', 'in');
      const iter = this.orTest();
      const conds = [];
      while (this.accept('KW', 'if')) conds.push(this.orTest());
      clauses.push({ target, iter, conds });
    }
    return { t: 'comp', kind, elt, clauses, line };
  }

  atom() {
    const tok = this.peek();
    const line = tok.line;
    if (tok.type === 'NUM') { this.next(); return { t: 'num', v: tok.value, line }; }
    if (tok.type === 'STR' || tok.type === 'FSTR') {
      const parts = [];
      while (this.is('STR') || this.is('FSTR')) {
        const s = this.next();
        parts.push(s.type === 'FSTR' ? parseFString(s.value, s.line) : { t: 'str', v: s.value, line: s.line });
      }
      return parts.length === 1 ? parts[0] : { t: 'concat', parts, line };
    }
    if (tok.type === 'NAME') { this.next(); return { t: 'name', name: tok.value, line }; }
    if (tok.type === 'KW') {
      if (tok.value === 'True') { this.next(); return { t: 'const', v: true, line }; }
      if (tok.value === 'False') { this.next(); return { t: 'const', v: false, line }; }
      if (tok.value === 'None') { this.next(); return { t: 'const', v: null, line }; }
    }
    if (this.accept('OP', '(')) {
      if (this.accept('OP', ')')) return { t: 'tuple', items: [], line };
      const first = this.expr();
      if (this.isKw('for')) {
        const c = this.comprehension(first, 'list', line);
        this.expect('OP', ')');
        return c;
      }
      if (this.accept('OP', ')')) return first;
      const items = [first];
      while (this.accept('OP', ',')) {
        if (this.isOp(')')) break;
        items.push(this.expr());
      }
      this.expect('OP', ')', 'faltou fechar o parêntese');
      return { t: 'tuple', items, line };
    }
    if (this.accept('OP', '[')) {
      if (this.accept('OP', ']')) return { t: 'list', items: [], line };
      const first = this.starOrExpr();
      if (this.isKw('for')) {
        const c = this.comprehension(first, 'list', line);
        this.expect('OP', ']');
        return c;
      }
      const items = [first];
      while (this.accept('OP', ',')) {
        if (this.isOp(']')) break;
        items.push(this.starOrExpr());
      }
      this.expect('OP', ']', 'faltou fechar o colchete da lista');
      return { t: 'list', items, line };
    }
    if (this.accept('OP', '{')) {
      const keys = [], values = [];
      while (!this.isOp('}')) {
        keys.push(this.expr());
        this.expect('OP', ':');
        values.push(this.expr());
        if (!this.accept('OP', ',')) break;
      }
      this.expect('OP', '}');
      return { t: 'dict', keys, values, line };
    }
    throw new ScriptError(`${describe(tok)} inesperado`, line);
  }
}

function checkTarget(e) {
  if (e.t === 'name' || e.t === 'index' || e.t === 'attr') return;
  if (e.t === 'tuple' || e.t === 'list') {
    if (e.items.filter((x) => x.t === 'starred').length > 1) throw new ScriptError("só um '*' por desempacotamento", e.line);
    e.items.forEach((x) => checkTarget(x.t === 'starred' ? x.e : x));
    return;
  }
  throw new ScriptError('não é possível atribuir a essa expressão', e.line,
    'do lado esquerdo do = deve vir um nome (ex: mesa = box(1, 1, 1))');
}

function parseFString(s, line) {
  const parts = [];
  let i = 0, buf = '';
  while (i < s.length) {
    if (s[i] === '{' && s[i + 1] === '{') { buf += '{'; i += 2; continue; }
    if (s[i] === '}' && s[i + 1] === '}') { buf += '}'; i += 2; continue; }
    if (s[i] === '{') {
      if (buf) parts.push({ t: 'str', v: buf, line });
      buf = '';
      const j = s.indexOf('}', i);
      if (j < 0) throw new ScriptError("f-string com '{' sem fechar", line);
      let inner = s.slice(i + 1, j);
      let spec = null;
      const colon = inner.lastIndexOf(':');
      if (colon >= 0 && !/[\])]/.test(inner.slice(colon))) { spec = inner.slice(colon + 1); inner = inner.slice(0, colon); }
      const p = new Parser(tokenize(inner).map((t) => ({ ...t, line })));
      parts.push({ t: 'fmt', e: p.expr(), spec, line });
      i = j + 1;
      continue;
    }
    buf += s[i++];
  }
  if (buf) parts.push({ t: 'str', v: buf, line });
  return { t: 'concat', parts, line };
}

export function parse(src) {
  return new Parser(tokenize(src)).program();
}
