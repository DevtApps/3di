// toJson: mesmo formato que plain(parse(src)) do scripts/golden.mjs (chaves, nulos e arrays iguais).
#include "ast.h"

namespace tdi {

static Json opt(const NodeP &n) { return n ? toJson(*n) : Json(); }

Json toJson(const Block &b) {
  Json a = Json::array();
  for (auto &n : b) a.push(toJson(*n));
  return a;
}

static Json target(const Target &t) {
  if (!t.tuple) return Json(t.name);
  Json a = Json::array();
  for (auto &x : t.items) a.push(target(x));
  return a;
}

static Json params(const std::vector<Param> &ps) {
  Json a = Json::array();
  for (auto &p : ps) {
    Json o = Json::object();
    o.set("def", opt(p.def));
    o.set("name", p.name);
    a.push(std::move(o));
  }
  return a;
}

static const char *kindName(K k) {
  switch (k) {
    case K::Pass: return "pass"; case K::Break: return "break"; case K::Continue: return "continue";
    case K::Return: return "return"; case K::Assign: return "assign"; case K::Aug: return "aug";
    case K::Expr: return "expr"; case K::Def: return "def"; case K::If: return "if"; case K::For: return "for";
    case K::While: return "while"; case K::Tuple: return "tuple"; case K::List: return "list";
    case K::Starred: return "starred"; case K::Lambda: return "lambda"; case K::IfExp: return "ifexp";
    case K::Or: return "or"; case K::And: return "and"; case K::Not: return "not"; case K::Cmp: return "cmp";
    case K::Bin: return "bin"; case K::Unary: return "unary"; case K::Call: return "call"; case K::Attr: return "attr";
    case K::Index: return "index"; case K::Slice: return "slice"; case K::Comp: return "comp"; case K::Num: return "num";
    case K::Str: return "str"; case K::Concat: return "concat"; case K::Fmt: return "fmt"; case K::Name: return "name";
    case K::Const: return "const"; case K::Dict: return "dict";
  }
  return "?";
}

Json toJson(const Node &n) {
  Json o = Json::object();
  o.set("t", kindName(n.k));
  o.set("line", n.line);
  switch (n.k) {
    case K::Pass: case K::Break: case K::Continue: break;
    case K::Return: case K::Expr: case K::Starred: case K::Not: o.set("e", opt(n.e)); break;
    case K::Assign: o.set("targets", toJson(n.items)); o.set("value", opt(n.value)); break;
    case K::Aug: o.set("target", opt(n.target)); o.set("op", n.s); o.set("value", opt(n.value)); break;
    case K::Def:
      o.set("name", n.s); o.set("params", params(n.params));
      o.set("star", n.hasStar ? Json(n.star) : Json()); o.set("body", toJson(n.body));
      break;
    case K::If: {
      Json tests = Json::array();
      for (auto &[c, b] : n.tests) { Json p = Json::array(); p.push(toJson(*c)); p.push(toJson(b)); tests.push(std::move(p)); }
      o.set("tests", std::move(tests));
      o.set("orelse", n.hasOrelse ? toJson(n.orelse) : Json());
      break;
    }
    case K::For: o.set("target", target(n.tgt)); o.set("iter", opt(n.iter)); o.set("body", toJson(n.body)); break;
    case K::While: o.set("cond", opt(n.cond)); o.set("body", toJson(n.body)); break;
    case K::Tuple: case K::List: o.set("items", toJson(n.items)); break;
    case K::Lambda: o.set("params", params(n.params)); o.set("body", opt(n.body1)); break;
    case K::IfExp: o.set("cond", opt(n.cond)); o.set("a", opt(n.a)); o.set("b", opt(n.b)); break;
    case K::Or: case K::And: o.set("a", opt(n.a)); o.set("b", opt(n.b)); break;
    case K::Cmp: {
      Json ops = Json::array();
      for (auto &s : n.ops) ops.push(s);
      o.set("first", opt(n.first)); o.set("ops", std::move(ops)); o.set("rest", toJson(n.items));
      break;
    }
    case K::Bin: o.set("op", n.s); o.set("a", opt(n.a)); o.set("b", opt(n.b)); break;
    case K::Unary: o.set("op", n.s); o.set("e", opt(n.e)); break;
    case K::Call: {
      Json args = Json::array();
      for (auto &a : n.args) {
        Json x = Json::object();
        x.set("e", opt(a.e));
        x.set("line", a.line);
        if (!a.kw.empty()) x.set("kw", a.kw);
        if (a.star) x.set("star", true);
        args.push(std::move(x));
      }
      o.set("fn", opt(n.fn)); o.set("args", std::move(args));
      break;
    }
    case K::Attr: o.set("obj", opt(n.obj)); o.set("name", n.s); break;
    case K::Index: o.set("obj", opt(n.obj)); o.set("idx", opt(n.idx)); break;
    case K::Slice: o.set("start", opt(n.start)); o.set("stop", opt(n.stop)); o.set("step", opt(n.step)); break;
    case K::Comp: {
      Json cl = Json::array();
      for (auto &c : n.clauses) {
        Json x = Json::object();
        x.set("target", target(c.target)); x.set("iter", opt(c.iter)); x.set("conds", toJson(c.conds));
        cl.push(std::move(x));
      }
      o.set("kind", n.s); o.set("elt", opt(n.elt)); o.set("clauses", std::move(cl));
      break;
    }
    case K::Num: o.set("v", n.num); break;
    case K::Str: o.set("v", n.s); break;
    case K::Concat: o.set("parts", toJson(n.items)); break;
    case K::Fmt: o.set("e", opt(n.e)); o.set("spec", n.hasSpec ? Json(n.spec) : Json()); break;
    case K::Name: o.set("name", n.s); break;
    case K::Const: o.set("v", n.cv == ConstV::True ? Json(true) : n.cv == ConstV::False ? Json(false) : Json()); break;
    case K::Dict: o.set("keys", toJson(n.items)); o.set("values", toJson(n.values)); break;
  }
  return o;
}

}  // namespace tdi
