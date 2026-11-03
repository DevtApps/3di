// Port do Parser do parser.js (descida recursiva, mesmas mensagens de erro).
#include "parser.h"

#include <algorithm>
#include <cstring>

#include "error.h"
#include "lexer.h"

namespace tdi {

static std::string describe(const Token &t) {
  switch (t.type) {
    case Tok::Newline: return "fim de linha";
    case Tok::Indent: return "indentação";
    case Tok::Dedent: return "fim de bloco";
    case Tok::Eof: return "fim do arquivo";
    case Tok::Str: case Tok::FStr: return "texto";
    case Tok::Num: {
      // como o JS mostra números: inteiros sem ".0"
      char b[32];
      std::snprintf(b, sizeof b, "%.15g", t.num);
      return std::string("'") + b + "'";
    }
    default: return "'" + t.value + "'";
  }
}

static const char *AUG_OPS[] = {"+=", "-=", "*=", "/="};
static const char *COMP_OPS[] = {"<", ">", "==", "!=", "<=", ">="};

static NodeP parseFString(const std::string &s, int line);

namespace {
struct Parser {
  std::vector<Token> t;
  size_t i = 0;

  const Token &peek(size_t o = 0) const { return t[std::min(i + o, t.size() - 1)]; }
  const Token &next() { return t[i++]; }
  bool is(Tok type) const { return peek().type == type; }
  bool is(Tok type, const char *v) const { return peek().type == type && peek().value == v; }
  bool isOp(const char *v) const { return is(Tok::Op, v); }
  bool isKw(const char *v) const { return is(Tok::Kw, v); }
  bool accept(Tok type) { if (is(type)) { next(); return true; } return false; }
  bool accept(Tok type, const char *v) { if (is(type, v)) { next(); return true; } return false; }
  [[noreturn]] void fail(const std::string &want, const std::string &hint) {
    throw ScriptError("esperado " + want + ", encontrado " + describe(peek()), peek().line, hint);
  }
  const Token &expect(Tok type, const char *v = nullptr, const std::string &hint = {}) {
    if (v ? is(type, v) : is(type)) return next();
    std::string want = v ? std::string("'") + v + "'" : type == Tok::Name ? "um nome" : type == Tok::Indent ? "um bloco indentado" : "?";
    fail(want, hint);
  }

  Block program() {
    Block body;
    while (!is(Tok::Eof)) {
      if (accept(Tok::Newline)) continue;
      if (is(Tok::Indent)) throw ScriptError("indentação inesperada", peek().line);
      statement(body);
    }
    return body;
  }

  void statement(Block &out) {
    const Token &k = peek();
    if (k.type == Tok::Kw) {
      if (k.value == "def") { out.push_back(funcdef()); return; }
      if (k.value == "if") { out.push_back(ifStmt()); return; }
      if (k.value == "for") { out.push_back(forStmt()); return; }
      if (k.value == "while") { out.push_back(whileStmt()); return; }
    }
    simpleLine(out);
  }

  void simpleLine(Block &out) {
    out.push_back(simple());
    while (accept(Tok::Op, ";")) {
      if (is(Tok::Newline) || is(Tok::Eof)) break;
      out.push_back(simple());
    }
    if (!accept(Tok::Newline) && !is(Tok::Eof) && !is(Tok::Dedent)) {
      const Token &k = peek();
      throw ScriptError(describe(k) + " inesperado", k.line,
                        k.type == Tok::Op && k.value == "=" ? "para comparar use ==" : "cada comando deve ficar em sua própria linha");
    }
  }

  NodeP simple() {
    int line = peek().line;
    if (accept(Tok::Kw, "pass")) return mk(K::Pass, line);
    if (accept(Tok::Kw, "break")) return mk(K::Break, line);
    if (accept(Tok::Kw, "continue")) return mk(K::Continue, line);
    if (accept(Tok::Kw, "return")) {
      auto n = mk(K::Return, line);
      if (!(is(Tok::Newline) || is(Tok::Eof) || isOp(";"))) n->e = exprList();
      return n;
    }
    NodeP e = exprList();
    if (isOp("=")) {
      Block parts{e};
      while (accept(Tok::Op, "=")) parts.push_back(exprList());
      auto n = mk(K::Assign, line);
      n->value = parts.back();
      parts.pop_back();
      for (auto &p : parts) checkTarget(*p);
      n->items = parts;
      return n;
    }
    for (const char *op : AUG_OPS) {
      if (accept(Tok::Op, op)) {
        checkTarget(*e);
        auto n = mk(K::Aug, line);
        n->target = e;
        n->s = std::string(1, op[0]);
        n->value = exprList();
        return n;
      }
    }
    auto n = mk(K::Expr, line);
    n->e = e;
    return n;
  }

  Block block() {
    expect(Tok::Op, ":", "blocos (def, if, for...) terminam com dois-pontos");
    Block body;
    if (accept(Tok::Newline)) {
      expect(Tok::Indent, nullptr, "o conteúdo do bloco deve ser indentado com 4 espaços");
      while (!accept(Tok::Dedent) && !is(Tok::Eof)) {
        if (accept(Tok::Newline)) continue;
        statement(body);
      }
      return body;
    }
    simpleLine(body);
    return body;
  }

  NodeP funcdef() {
    auto n = mk(K::Def, next().line);
    n->s = expect(Tok::Name).value;
    expect(Tok::Op, "(");
    while (!isOp(")")) {
      if (accept(Tok::Op, "*")) {
        n->hasStar = true;
        n->star = expect(Tok::Name).value;
      } else {
        Param p{expect(Tok::Name).value, nullptr};
        if (accept(Tok::Op, "=")) p.def = expr();
        n->params.push_back(std::move(p));
      }
      if (!accept(Tok::Op, ",")) break;
    }
    expect(Tok::Op, ")");
    if (accept(Tok::Op, "->")) expr();
    n->body = block();
    return n;
  }

  NodeP ifStmt() {
    auto n = mk(K::If, next().line);
    NodeP c = expr();
    n->tests.emplace_back(c, block());
    while (true) {
      if (accept(Tok::Kw, "elif")) { NodeP c2 = expr(); n->tests.emplace_back(c2, block()); }
      else if (accept(Tok::Kw, "else")) { n->hasOrelse = true; n->orelse = block(); break; }
      else break;
    }
    return n;
  }

  Target targetList() {
    auto one = [&]() -> Target {
      if (accept(Tok::Op, "(")) {
        Target inner = targetList();
        expect(Tok::Op, ")");
        return inner;
      }
      return Target{expect(Tok::Name).value, {}, false};
    };
    Target first = one();
    if (!isOp(",")) return first;
    Target tup{{}, {first}, true};
    while (accept(Tok::Op, ",")) {
      if (!is(Tok::Name) && !isOp("(")) break;
      tup.items.push_back(one());
    }
    return tup;
  }

  NodeP forStmt() {
    auto n = mk(K::For, next().line);
    n->tgt = targetList();
    expect(Tok::Kw, "in");
    n->iter = exprList();
    n->body = block();
    return n;
  }

  NodeP whileStmt() {
    auto n = mk(K::While, next().line);
    n->cond = expr();
    n->body = block();
    return n;
  }

  NodeP exprList() {
    int line = peek().line;
    NodeP first = starOrExpr();
    if (!isOp(",")) {
      if (first->k == K::Starred) throw ScriptError("'*' só pode ser usado dentro de uma lista ou desempacotamento", line);
      return first;
    }
    auto n = mk(K::Tuple, line);
    n->items.push_back(first);
    while (accept(Tok::Op, ",")) {
      if (is(Tok::Newline) || isOp("=") || isOp(")") || is(Tok::Eof)) break;
      n->items.push_back(starOrExpr());
    }
    return n;
  }

  NodeP starOrExpr() {
    int line = peek().line;
    if (accept(Tok::Op, "*")) { auto n = mk(K::Starred, line); n->e = bitOr(); return n; }
    return expr();
  }

  NodeP expr() {
    int line = peek().line;
    if (accept(Tok::Kw, "lambda")) {
      auto n = mk(K::Lambda, line);
      while (!isOp(":")) {
        Param p{expect(Tok::Name).value, nullptr};
        if (accept(Tok::Op, "=")) p.def = expr();
        n->params.push_back(std::move(p));
        if (!accept(Tok::Op, ",")) break;
      }
      expect(Tok::Op, ":");
      n->body1 = expr();
      return n;
    }
    NodeP e = orTest();
    if (accept(Tok::Kw, "if")) {
      auto n = mk(K::IfExp, line);
      n->cond = orTest();
      expect(Tok::Kw, "else", "expressão condicional precisa de 'else'");
      n->a = e;
      n->b = expr();
      return n;
    }
    return e;
  }

  NodeP logic(K k, const char *kw, NodeP (Parser::*sub)()) {
    NodeP e = (this->*sub)();
    while (is(Tok::Kw, kw)) {
      auto n = mk(k, next().line);
      n->a = e;
      n->b = (this->*sub)();
      e = n;
    }
    return e;
  }
  NodeP orTest() { return logic(K::Or, "or", &Parser::andTest); }
  NodeP andTest() { return logic(K::And, "and", &Parser::notTest); }

  NodeP notTest() {
    if (is(Tok::Kw, "not")) {
      auto n = mk(K::Not, next().line);
      n->e = notTest();
      return n;
    }
    return comparison();
  }

  NodeP comparison() {
    int line = peek().line;
    NodeP first = bitOr();
    std::vector<std::string> ops;
    Block rest;
    while (true) {
      std::string op;
      bool cmp = false;
      for (const char *o : COMP_OPS) cmp |= isOp(o);
      if (cmp) op = next().value;
      else if (isKw("in")) { next(); op = "in"; }
      else if (isKw("not") && peek(1).type == Tok::Kw && peek(1).value == "in") { i += 2; op = "not in"; }
      else if (isKw("is")) { next(); op = accept(Tok::Kw, "not") ? "is not" : "is"; }
      if (op.empty()) break;
      ops.push_back(op);
      rest.push_back(bitOr());
    }
    if (ops.empty()) return first;
    auto n = mk(K::Cmp, line);
    n->first = first;
    n->ops = std::move(ops);
    n->items = std::move(rest);
    return n;
  }

  NodeP binLevel(NodeP (Parser::*sub)(), std::initializer_list<const char *> ops) {
    NodeP e = (this->*sub)();
    while (std::any_of(ops.begin(), ops.end(), [&](const char *o) { return isOp(o); })) {
      const Token &tok = next();
      auto n = mk(K::Bin, tok.line);
      n->s = tok.value;
      n->a = e;
      n->b = (this->*sub)();
      e = n;
    }
    return e;
  }
  NodeP bitOr() { return binLevel(&Parser::bitXor, {"|"}); }
  NodeP bitXor() { return binLevel(&Parser::bitAnd, {"^"}); }
  NodeP bitAnd() { return binLevel(&Parser::arith, {"&"}); }
  NodeP arith() { return binLevel(&Parser::term, {"+", "-"}); }
  NodeP term() { return binLevel(&Parser::factor, {"*", "/", "//", "%", "@"}); }

  NodeP factor() {
    if (isOp("-") || isOp("+") || isOp("~")) {
      const Token &tok = next();
      auto n = mk(K::Unary, tok.line);
      n->s = tok.value;
      n->e = factor();
      return n;
    }
    return power();
  }

  NodeP power() {
    NodeP e = postfix();
    if (isOp("**")) {
      auto n = mk(K::Bin, next().line);
      n->s = "**";
      n->a = e;
      n->b = factor();
      return n;
    }
    return e;
  }

  NodeP postfix() {
    NodeP e = atom();
    while (true) {
      int line = peek().line;
      if (accept(Tok::Op, "(")) {
        auto n = mk(K::Call, line);
        n->fn = e;
        n->args = callArgs();
        e = n;
      } else if (accept(Tok::Op, ".")) {
        auto n = mk(K::Attr, line);
        n->obj = e;
        n->s = expect(Tok::Name, nullptr, "depois do ponto vem o nome de um método").value;
        e = n;
      } else if (accept(Tok::Op, "[")) {
        auto n = mk(K::Index, line);
        n->obj = e;
        n->idx = isOp(":") || lookaheadSlice() ? sliceExpr() : exprList();
        expect(Tok::Op, "]");
        e = n;
      } else break;
    }
    return e;
  }

  bool lookaheadSlice() const {
    int d = 0;
    for (size_t j = i; j < t.size(); j++) {
      const Token &k = t[j];
      if (k.type != Tok::Op) continue;
      const std::string &v = k.value;
      if (v == "(" || v == "[" || v == "{") d++;
      else if (v == ")" || v == "}") d--;
      else if (v == "]") { if (d == 0) return false; d--; }
      else if (v == ":" && d == 0) return true;
    }
    return false;
  }

  NodeP sliceExpr() {
    auto n = mk(K::Slice, peek().line);
    auto part = [&]() -> NodeP { return isOp(":") || isOp("]") ? nullptr : expr(); };
    n->start = part();
    expect(Tok::Op, ":");
    n->stop = part();
    if (accept(Tok::Op, ":")) n->step = part();
    return n;
  }

  std::vector<Arg> callArgs() {
    std::vector<Arg> args;
    while (!isOp(")")) {
      int line = peek().line;
      if (accept(Tok::Op, "*")) {
        args.push_back({expr(), {}, true, line});
      } else if (is(Tok::Name) && peek(1).type == Tok::Op && peek(1).value == "=") {
        std::string kw = next().value;
        next();
        args.push_back({expr(), kw, false, line});
      } else {
        NodeP e = expr();
        if (isKw("for")) {
          args.push_back({comprehension(e, line), {}, false, line});
        } else {
          if (std::any_of(args.begin(), args.end(), [](const Arg &a) { return !a.kw.empty(); }))
            throw ScriptError("argumento posicional depois de argumento nomeado", line,
                              "coloque os argumentos sem nome antes dos nomeados (ex: box(1, 2, 3, round=0.1))");
          args.push_back({e, {}, false, line});
        }
      }
      if (!accept(Tok::Op, ",")) break;
    }
    expect(Tok::Op, ")", "faltou fechar o parêntese da chamada");
    return args;
  }

  NodeP comprehension(NodeP elt, int line) {
    auto n = mk(K::Comp, line);
    n->s = "list";
    n->elt = elt;
    while (accept(Tok::Kw, "for")) {
      Clause c;
      c.target = targetList();
      expect(Tok::Kw, "in");
      c.iter = orTest();
      while (accept(Tok::Kw, "if")) c.conds.push_back(orTest());
      n->clauses.push_back(std::move(c));
    }
    return n;
  }

  NodeP atom() {
    const Token &tok = peek();
    int line = tok.line;
    if (tok.type == Tok::Num) { next(); auto n = mk(K::Num, line); n->num = tok.num; return n; }
    if (tok.type == Tok::Str || tok.type == Tok::FStr) {
      Block parts;
      while (is(Tok::Str) || is(Tok::FStr)) {
        const Token &s = next();
        if (s.type == Tok::FStr) parts.push_back(parseFString(s.value, s.line));
        else { auto n = mk(K::Str, s.line); n->s = s.value; parts.push_back(n); }
      }
      if (parts.size() == 1) return parts[0];
      auto n = mk(K::Concat, line);
      n->items = std::move(parts);
      return n;
    }
    if (tok.type == Tok::Name) { next(); auto n = mk(K::Name, line); n->s = tok.value; return n; }
    if (tok.type == Tok::Kw) {
      ConstV v;
      bool ok = true;
      if (tok.value == "True") v = ConstV::True;
      else if (tok.value == "False") v = ConstV::False;
      else if (tok.value == "None") v = ConstV::None;
      else ok = false;
      if (ok) { next(); auto n = mk(K::Const, line); n->cv = v; return n; }
    }
    if (accept(Tok::Op, "(")) {
      if (accept(Tok::Op, ")")) return mk(K::Tuple, line);
      NodeP first = expr();
      if (isKw("for")) {
        NodeP c = comprehension(first, line);
        expect(Tok::Op, ")");
        return c;
      }
      if (accept(Tok::Op, ")")) return first;
      auto n = mk(K::Tuple, line);
      n->items.push_back(first);
      while (accept(Tok::Op, ",")) {
        if (isOp(")")) break;
        n->items.push_back(expr());
      }
      expect(Tok::Op, ")", "faltou fechar o parêntese");
      return n;
    }
    if (accept(Tok::Op, "[")) {
      if (accept(Tok::Op, "]")) return mk(K::List, line);
      NodeP first = starOrExpr();
      if (isKw("for")) {
        NodeP c = comprehension(first, line);
        expect(Tok::Op, "]");
        return c;
      }
      auto n = mk(K::List, line);
      n->items.push_back(first);
      while (accept(Tok::Op, ",")) {
        if (isOp("]")) break;
        n->items.push_back(starOrExpr());
      }
      expect(Tok::Op, "]", "faltou fechar o colchete da lista");
      return n;
    }
    if (accept(Tok::Op, "{")) {
      auto n = mk(K::Dict, line);
      while (!isOp("}")) {
        n->items.push_back(expr());
        expect(Tok::Op, ":");
        n->values.push_back(expr());
        if (!accept(Tok::Op, ",")) break;
      }
      expect(Tok::Op, "}");
      return n;
    }
    throw ScriptError(describe(tok) + " inesperado", line);
  }

  static void checkTarget(const Node &e) {
    if (e.k == K::Name || e.k == K::Index || e.k == K::Attr) return;
    if (e.k == K::Tuple || e.k == K::List) {
      if (std::count_if(e.items.begin(), e.items.end(), [](const NodeP &x) { return x->k == K::Starred; }) > 1)
        throw ScriptError("só um '*' por desempacotamento", e.line);
      for (auto &x : e.items) checkTarget(x->k == K::Starred ? *x->e : *x);
      return;
    }
    throw ScriptError("não é possível atribuir a essa expressão", e.line,
                      "do lado esquerdo do = deve vir um nome (ex: mesa = box(1, 1, 1))");
  }
};
}  // namespace

static NodeP parseFString(const std::string &s, int line) {
  auto out = mk(K::Concat, line);
  size_t i = 0;
  std::string buf;
  auto flush = [&] {
    if (buf.empty()) return;
    auto n = mk(K::Str, line);
    n->s = buf;
    out->items.push_back(n);
    buf.clear();
  };
  while (i < s.size()) {
    char c = s[i], d = i + 1 < s.size() ? s[i + 1] : '\0';
    if (c == '{' && d == '{') { buf += '{'; i += 2; continue; }
    if (c == '}' && d == '}') { buf += '}'; i += 2; continue; }
    if (c == '{') {
      flush();
      size_t j = s.find('}', i);
      if (j == std::string::npos) throw ScriptError("f-string com '{' sem fechar", line);
      std::string inner = s.substr(i + 1, j - i - 1);
      auto n = mk(K::Fmt, line);
      size_t colon = inner.rfind(':');
      if (colon != std::string::npos && inner.find_first_of("])", colon) == std::string::npos) {
        n->hasSpec = true;
        n->spec = inner.substr(colon + 1);
        inner = inner.substr(0, colon);
      }
      Parser p{tokenize(inner)};
      for (auto &tk : p.t) tk.line = line;
      n->e = p.expr();
      out->items.push_back(n);
      i = j + 1;
      continue;
    }
    buf += s[i++];
  }
  flush();
  return out;
}

Block parse(const std::string &src) { return Parser{tokenize(src)}.program(); }

}  // namespace tdi
