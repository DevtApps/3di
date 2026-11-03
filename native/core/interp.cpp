// Port de interp.js.
#include "interp.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <regex>

#include "expr.h"
#include "parser.h"

namespace tdi {

namespace {
struct BreakSig {};
struct ContinueSig {};
struct ReturnSig {
  Value v;
};
const char *TIME_HINT =
    "para variar com o tempo (ou numa fórmula de implicit) use contas e funções: sin, cos, abs, min, max, clamp, lerp, smoothstep, step, osc";
}  // namespace

// ---------- escopos ----------

Value *Scope::find(const std::string &name) {
  for (Scope *s = this; s; s = s->parent.get()) {
    auto it = s->index.find(name);
    if (it != s->index.end()) return &s->order[it->second].second;
  }
  return nullptr;
}
void Scope::set(const std::string &name, Value v) {
  auto it = index.find(name);
  if (it != index.end()) { order[it->second].second = std::move(v); return; }
  index[name] = order.size();
  order.emplace_back(name, std::move(v));
}
std::vector<std::string> Scope::names() const {
  std::vector<std::string> out;
  for (const Scope *s = this; s; s = s->parent.get())
    for (auto &[k, v] : s->order)
      if (std::find(out.begin(), out.end(), k) == out.end()) out.push_back(k);
  return out;
}

// ---------- operações ----------

static bool contains(const Value &container, const Value &x) {
  if (container.isList()) {
    for (auto &y : container.list()->items)
      if (eq(x, y)) return true;
    return false;
  }
  if (container.isStr()) return container.s().find(str(x)) != std::string::npos;
  if (container.isDict()) return container.dict()->find(x) != nullptr;
  throw ScriptError("'in' não funciona com " + typeName(container));
}

// a < b do JS para números e textos (o resto compara como igual, como no sort do JS com tipos misturados)
static int jsCmp(const Value &a, const Value &b) {
  if (a.isNum() && b.isNum()) return a.n() < b.n() ? -1 : a.n() > b.n() ? 1 : 0;
  if (a.isStr() && b.isStr()) return a.s() < b.s() ? -1 : a.s() > b.s() ? 1 : 0;
  return 0;
}

static bool compare(const std::string &op, const Value &a, const Value &b) {
  if (a.isExpr() || b.isExpr())
    throw ScriptError("não é possível comparar valores que variam (time, ou x, y, z numa fórmula) usando " + op, 0, TIME_HINT);
  if (op == "==") return eq(a, b);
  if (op == "!=") return !eq(a, b);
  if (op == "is") return same(a, b);
  if (op == "is not") return !same(a, b);
  if (op == "in") return contains(b, a);
  if (op == "not in") return !contains(b, a);
  bool okNum = a.isNum() && b.isNum(), okStr = a.isStr() && b.isStr();
  if (!okNum && !okStr) throw ScriptError("não é possível comparar " + typeName(a) + " com " + typeName(b) + " usando " + op);
  if (okNum) {
    double x = a.n(), y = b.n();
    if (op == "<") return x < y;
    if (op == ">") return x > y;
    if (op == "<=") return x <= y;
    return x >= y;
  }
  const std::string &x = a.s(), &y = b.s();
  if (op == "<") return x < y;
  if (op == ">") return x > y;
  if (op == "<=") return x <= y;
  return x >= y;
}

static int32_t toInt32(double x) {
  if (!std::isfinite(x)) return 0;
  double m = std::fmod(std::trunc(x), 4294967296.0);
  if (m < 0) m += 4294967296.0;
  return (int32_t)(uint32_t)m;
}

static std::string repeatStr(const std::string &s, double n) {
  std::string r;
  for (long i = 0; i < (long)std::trunc(n); i++) r += s;
  return r;
}

Value binary(const std::string &op, const Value &a, const Value &b) {
  if (a.isShape() || b.isShape()) return shapeBinary(op, a, b);
  if (a.isExpr() || b.isExpr()) {
    auto ok = [](const Value &x) { return x.isExpr() || x.isNum(); };
    if (ok(a) && ok(b)) {
      if (op == "+" || op == "-" || op == "*" || op == "/" || op == "%" || op == "**") return sym(op, {a, b});
      if (op == "//") return sym("floor", {sym("/", {a, b})});
    }
    throw ScriptError("operação '" + op + "' não suportada entre " + typeName(a) + " e " + typeName(b), 0, TIME_HINT);
  }
  bool na = a.isNum() || a.isBool(), nb = b.isNum() || b.isBool();
  if (na && nb) {
    double x = a.isNum() ? a.n() : a.b(), y = b.isNum() ? b.n() : b.b();
    if (op == "+") return x + y;
    if (op == "-") return x - y;
    if (op == "*") return x * y;
    if (op == "/") {
      if (y == 0) throw ScriptError("divisão por zero");
      return x / y;
    }
    if (op == "//") {
      if (y == 0) throw ScriptError("divisão por zero");
      return std::floor(x / y);
    }
    if (op == "%") return std::fmod(std::fmod(x, y) + y, y);
    if (op == "**") return std::pow(x, y);
    if (op == "|") return double(toInt32(x) | toInt32(y));
    if (op == "&") return double(toInt32(x) & toInt32(y));
    if (op == "^") return double(toInt32(x) ^ toInt32(y));
  }
  if (op == "+" && a.isStr() && b.isStr()) return a.s() + b.s();
  if (op == "+" && a.isList() && b.isList()) {
    std::vector<Value> r = a.list()->items;
    r.insert(r.end(), b.list()->items.begin(), b.list()->items.end());
    return a.isTuple() ? tuple(r) : list(r);
  }
  if (op == "*" && (a.isStr() || a.isList()) && b.isNum()) {
    if (a.isStr()) return repeatStr(a.s(), std::max(0.0, b.n()));
    std::vector<Value> r;
    for (int i = 0; i < b.n(); i++) r.insert(r.end(), a.list()->items.begin(), a.list()->items.end());
    return a.isTuple() ? tuple(r) : list(r);
  }
  if (op == "%" && a.isStr()) {
    std::vector<Value> queue = b.isList() ? b.list()->items : std::vector<Value>{};
    size_t qi = 0;
    std::string out;
    const std::string &s = a.s();
    for (size_t i = 0; i < s.size(); i++) {
      if (s[i] == '%' && i + 1 < s.size() && (s[i + 1] == 's' || s[i + 1] == 'd' || s[i + 1] == 'f')) {
        out += str(b.isList() ? (qi < queue.size() ? queue[qi++] : Value()) : b);
        i++;
      } else out += s[i];
    }
    return out;
  }
  std::string hint;
  if (op == "+" && (a.isStr() || b.isStr())) hint = "use str(x) para converter números em texto, ou f\"...{x}...\"";
  if (a.isList() && b.isList()) hint = "tuplas não fazem conta de vetor; some cada componente separadamente";
  throw ScriptError("operação '" + op + "' não suportada entre " + typeName(a) + " e " + typeName(b), 0, hint);
}

static std::string formatSpec(const Value &v, const Node &p) {
  if (!p.hasSpec || p.spec.empty()) return str(v);
  static const std::regex fixed("^\\.(\\d+)f$");
  std::smatch m;
  if (std::regex_match(p.spec, m, fixed) && v.isNum()) {
    char buf[512];
    std::snprintf(buf, sizeof buf, "%.*f", std::stoi(m[1].str()), v.n());
    return buf;
  }
  return str(v);
}

// Number(texto) do JS
static double jsNumber(const std::string &s) {
  size_t a = s.find_first_not_of(" \t\n\r"), b = s.find_last_not_of(" \t\n\r");
  if (a == std::string::npos) return 0;
  std::string t = s.substr(a, b - a + 1);
  if (t == "Infinity" || t == "+Infinity") return INFINITY;
  if (t == "-Infinity") return -INFINITY;
  char *end = nullptr;
  double v = (t.size() > 2 && t[0] == '0' && (t[1] == 'x' || t[1] == 'X')) ? (double)std::strtoll(t.c_str() + 2, &end, 16) : std::strtod(t.c_str(), &end);
  if (end != t.c_str() + t.size()) return NAN;
  if (t.find_first_of("iInN") != std::string::npos) return NAN;  // strtod aceita "inf"/"nan", o JS não
  return v;
}

static std::string jsUpper(const std::string &s) {
  std::string r;
  for (size_t i = 0; i < s.size(); i++) {
    unsigned char c = s[i];
    if (c < 0x80) r += (char)std::toupper(c);
    else if (c == 0xC3 && i + 1 < s.size() && (unsigned char)s[i + 1] >= 0xA0 && (unsigned char)s[i + 1] <= 0xBE && (unsigned char)s[i + 1] != 0xB7) {
      r += (char)c;
      r += (char)((unsigned char)s[i + 1] - 0x20);
      i++;
    } else r += (char)c;
  }
  return r;
}

// ---------- interpretador ----------

Interp::Interp(long maxSteps) : maxSteps(maxSteps) {
  globals = std::make_shared<Scope>();
  for (auto &[name, v] : builtins()) globals->set(name, v);
  for (auto &[k, v] : globals->order) builtinNames.push_back(k);
}

double Interp::toNum(const Value &x, const std::string &what) {
  if (x.isNum()) return x.n();
  throw ScriptError(what + "() espera um número, recebeu " + typeName(x));
}

Builtins Interp::builtins() {
  Builtins b;
  auto add = [&](const std::string &name, Value v) {
    for (auto &[k, x] : b)
      if (k == name) { x = std::move(v); return; }
    b.emplace_back(name, std::move(v));
  };
  auto N = [&](const std::string &name, std::initializer_list<const char *> params, NativeFn fn) { add(name, native(name, params, std::move(fn))); };
  auto math1 = [&](const std::string &name, double (*f)(double)) {
    N(name, {"x"}, [this, name, f](const Args &a, const Node *) -> Value {
      const Value &x = a["x"];
      if (x.isExpr()) {
        if (std::find(EXPR_FUNCS.begin(), EXPR_FUNCS.end(), name) != EXPR_FUNCS.end()) return sym(name, {x});
        throw ScriptError(name + "() não funciona com time", 0, TIME_HINT);
      }
      return f(toNum(x, name));
    });
  };
  auto anyT = [](const std::vector<Value> &xs) { return std::any_of(xs.begin(), xs.end(), [](const Value &v) { return v.isExpr(); }); };

  add("pi", M_PI);
  add("tau", M_PI * 2);
  N("print", {"*values"}, [this](const Args &a, const Node *) {
    std::string line;
    bool first = true;
    for (auto &v : a["values"].list()->items) { line += (first ? "" : " ") + str(v); first = false; }
    logs.push_back(line);
    return Value();
  });
  N("range", {"a", "b=None", "step=1"}, [](const Args &a, const Node *) {
    Value start = 0.0, stop = a["a"];
    if (!a["b"].isNone()) { start = a["a"]; stop = a["b"]; }
    double step = val0(a["step"]);
    if (step == 0) throw ScriptError("range() com passo 0");
    std::vector<Value> out;
    double st = val0(start), sp = val0(stop);
    for (double i = st; step > 0 ? i < sp : i > sp; i += step) {
      out.push_back(i);
      if (out.size() > 100000) throw ScriptError("range() grande demais");
    }
    return list(out);
  });
  N("linspace", {"a", "b", "n"}, [](const Args &a, const Node *) {
    double x = val0(a["a"]), y = val0(a["b"]), n = std::floor(val0(a["n"]));
    std::vector<Value> out;
    for (int i = 0; i < n; i++) out.push_back(n == 1 ? x : x + ((y - x) * i) / (n - 1));
    return list(out);
  });
  N("len", {"x"}, [](const Args &a, const Node *) -> Value {
    const Value &x = a["x"];
    if (x.isList()) return x.size();
    if (x.isStr()) return codepoints(x.s()).size();
    if (x.isDict()) return x.dict()->items.size();
    throw ScriptError("len() não funciona com " + typeName(x));
  });
  math1("abs", [](double x) { return std::fabs(x); });
  math1("sqrt", [](double x) { return std::sqrt(x); });
  math1("sin", [](double x) { return std::sin(x); });
  math1("cos", [](double x) { return std::cos(x); });
  math1("tan", [](double x) { return std::tan(x); });
  math1("asin", [](double x) { return std::asin(x); });
  math1("acos", [](double x) { return std::acos(x); });
  math1("atan", [](double x) { return std::atan(x); });
  math1("exp", [](double x) { return std::exp(x); });
  math1("log", [](double x) { return std::log(x); });
  math1("floor", [](double x) { return std::floor(x); });
  math1("ceil", [](double x) { return std::ceil(x); });
  math1("radians", [](double x) { return (x * M_PI) / 180; });
  math1("degrees", [](double x) { return (x * 180) / M_PI; });
  N("atan2", {"y", "x"}, [](const Args &a, const Node *) -> Value {
    if (a["y"].isExpr() || a["x"].isExpr()) return sym("atan2", {a["y"], a["x"]});
    return std::atan2(val0(a["y"]), val0(a["x"]));
  });
  N("hypot", {"*xs"}, [anyT](const Args &a, const Node *) -> Value {
    auto xs = a["xs"].list()->items;
    if (anyT(xs)) return sym("hypot", xs);
    double s = 0;
    for (auto &x : xs) s += val0(x) * val0(x);
    return std::sqrt(s);
  });
  N("sign", {"x"}, [](const Args &a, const Node *) -> Value {
    if (a["x"].isExpr()) return sym("sign", {a["x"]});
    double x = val0(a["x"]);
    return x > 0 ? 1.0 : x < 0 ? -1.0 : x;
  });
  N("step", {"edge", "x"}, [](const Args &a, const Node *) -> Value {
    if (a["edge"].isExpr() || a["x"].isExpr()) return sym("step", {a["edge"], a["x"]});
    return val0(a["x"]) < val0(a["edge"]) ? 0.0 : 1.0;
  });
  N("implicit", {"f", "size=2", "lip=0.5"}, [this](const Args &a, const Node *node) -> Value {
    const Value &f = a["f"];
    if (!f.isFunc())
      throw ScriptError("implicit() espera uma função (x, y, z), por exemplo lambda x, y, z: sqrt(x*x + y*y + z*z) - 0.5");
    std::vector<Value> sz = a["size"].isList() ? a["size"].list()->items : std::vector<Value>{a["size"], a["size"], a["size"]};
    bool bad = sz.size() != 3 || std::any_of(sz.begin(), sz.end(), [](const Value &v) { return !v.isNum() || !(v.n() > 0); });
    if (bad) throw ScriptError("implicit(): size deve ser um número positivo ou (largura, altura, profundidade)");
    double k = toNum(a["lip"], "lip");
    if (!(k > 0 && k <= 1))
      throw ScriptError("implicit(): lip deve estar entre 0 (exclusivo) e 1", 0, "lip=0.5 é seguro; 1 só para campos que já são distâncias exatas");
    Value field = call(f, {POS_X, POS_Y, POS_Z}, {}, node);
    if (!field.isExpr() || !field.expr()->usesPosition())
      throw ScriptError("implicit(): a fórmula precisa depender de x, y ou z", 0,
                        "use funções como sqrt, sin, abs, min, max, clamp; comparações (<, >) não funcionam: use min/max/step");
    return mkShape("implicit", {{"f", field}, {"half", nums({sz[0].n() / 2, sz[1].n() / 2, sz[2].n() / 2})}, {"lip", k}});
  });
  N("round", {"x", "n=0"}, [](const Args &a, const Node *) -> Value {
    double p = std::pow(10, val0(a["n"]));
    return std::floor(val0(a["x"]) * p + 0.5) / p;
  });
  auto minmax = [anyT](const std::string &op) {
    return [anyT, op](const Args &a, const Node *) -> Value {
      auto xs = a["xs"].list()->items;
      std::vector<Value> v = xs.size() == 1 && xs[0].isList() ? xs[0].list()->items : xs;
      if (xs.size() == 1 && !xs[0].isList()) v = xs;
      if (anyT(v)) {
        Value acc = v[0];
        for (size_t i = 1; i < v.size(); i++) acc = sym(op, {acc, v[i]});
        return acc;
      }
      double r = op == "min" ? INFINITY : -INFINITY;
      for (auto &x : v) {
        double d = x.isNum() ? x.n() : x.isBool() ? double(x.b()) : NAN;
        if (std::isnan(d) || std::isnan(r)) r = NAN;
        else r = op == "min" ? std::min(r, d) : std::max(r, d);
      }
      return r;
    };
  };
  N("min", {"*xs"}, minmax("min"));
  N("max", {"*xs"}, minmax("max"));
  math1("fract", [](double x) { return x - std::floor(x); });
  N("smoothstep", {"e0", "e1", "x"}, [](const Args &a, const Node *) { return sym("smoothstep", {a["e0"], a["e1"], a["x"]}); });
  add("time", TIME);
  N("osc", {"a", "b", "period=2"}, [](const Args &a, const Node *) {
    Value A = a["a"], B = a["b"];
    double period = val0(a["period"]);
    return sym("+", {A, sym("*", {sym("-", {B, A}), sym("-", {0.5, sym("*", {0.5, sym("cos", {sym("*", {TIME, (2 * M_PI) / period})})})})})});
  });
  N("sum", {"xs", "start=0"}, [](const Args &a, const Node *) {
    Value acc = a["start"];
    for (auto &x : iterate(a["xs"])) acc = binary("+", acc, x);
    return acc;
  });
  N("clamp", {"x", "lo=0", "hi=1"}, [](const Args &a, const Node *) { return sym("clamp", {a["x"], a["lo"], a["hi"]}); });
  N("lerp", {"a", "b", "t"}, [](const Args &a, const Node *) { return sym("lerp", {a["a"], a["b"], a["t"]}); });
  N("mix", {"a", "b", "t=0.5"}, [](const Args &a, const Node *) -> Value {
    if (isColorLike(a["a"]) && isColorLike(a["b"]) && !a["a"].isNum()) {
      auto ca = toSrgb(a["a"]), cb = toSrgb(a["b"]);
      double t = val0(a["t"]);
      return tuple({ca[0] + (cb[0] - ca[0]) * t, ca[1] + (cb[1] - ca[1]) * t, ca[2] + (cb[2] - ca[2]) * t});
    }
    return sym("lerp", {a["a"], a["b"], a["t"]});
  });
  N("hsv", {"h", "s=1", "v=1"}, [](const Args &a, const Node *) {
    auto c = hsvToRgb(val0(a["h"]), val0(a["s"]), val0(a["v"]));
    return tuple({c[0], c[1], c[2]});
  });
  N("vary", {"color", "hue=0", "sat=0", "val=0"}, [this](const Args &a, const Node *) {
    auto hsv = rgbToHsv(toSrgb(a["color"]));
    auto j = [this](double r) { return (rng() * 2 - 1) * r; };
    double h = hsv[0] + j(val0(a["hue"]));
    double s = std::min(1.0, std::max(0.0, hsv[1] + j(val0(a["sat"]))));
    double v = std::min(1.0, std::max(0.0, hsv[2] + j(val0(a["val"]))));
    auto c = hsvToRgb(h, s, v);
    return tuple({c[0], c[1], c[2]});
  });
  N("int", {"x"}, [](const Args &a, const Node *) -> Value {
    const Value &x = a["x"];
    if (x.isStr()) {
      const char *s = x.s().c_str();
      while (*s == ' ' || *s == '\t' || *s == '\n') s++;
      char *end;
      long long v = std::strtoll(s, &end, 10);
      return end == s ? NAN : double(v);
    }
    return std::trunc(x.isBool() ? double(x.b()) : val0(x));
  });
  N("float", {"x"}, [](const Args &a, const Node *) -> Value {
    const Value &x = a["x"];
    if (x.isStr()) return jsNumber(x.s());
    if (x.isBool()) return double(x.b());
    if (x.isNone()) return 0.0;
    return x.isNum() ? x.n() : NAN;
  });
  N("str", {"x"}, [](const Args &a, const Node *) { return Value(str(a["x"])); });
  N("bool", {"x"}, [](const Args &a, const Node *) { return Value(truthy(a["x"])); });
  N("list", {"x=None"}, [](const Args &a, const Node *) { return list(a["x"].isNone() ? std::vector<Value>{} : iterate(a["x"])); });
  N("tuple", {"x=None"}, [](const Args &a, const Node *) { return tuple(a["x"].isNone() ? std::vector<Value>{} : iterate(a["x"])); });
  N("dict", {}, [](const Args &, const Node *) { return Value(std::make_shared<DictObj>()); });
  N("enumerate", {"xs", "start=0"}, [](const Args &a, const Node *) {
    std::vector<Value> out;
    auto xs = iterate(a["xs"]);
    for (size_t i = 0; i < xs.size(); i++) out.push_back(tuple({binary("+", (double)i, a["start"]), xs[i]}));
    return list(out);
  });
  N("zip", {"*lists"}, [](const Args &a, const Node *) {
    std::vector<std::vector<Value>> arrs;
    for (auto &l : a["lists"].list()->items) arrs.push_back(iterate(l));
    size_t n = arrs.empty() ? 0 : SIZE_MAX;
    for (auto &x : arrs) n = std::min(n, x.size());
    if (arrs.empty()) n = 0;
    std::vector<Value> out;
    for (size_t i = 0; i < n; i++) {
      std::vector<Value> t;
      for (auto &x : arrs) t.push_back(x[i]);
      out.push_back(tuple(t));
    }
    return list(out);
  });
  N("sorted", {"xs", "reverse=False"}, [](const Args &a, const Node *) {
    auto r = iterate(a["xs"]);
    std::stable_sort(r.begin(), r.end(), [](const Value &x, const Value &y) { return jsCmp(x, y) < 0; });
    if (truthy(a["reverse"])) std::reverse(r.begin(), r.end());
    return list(r);
  });
  N("reversed", {"xs"}, [](const Args &a, const Node *) {
    auto r = iterate(a["xs"]);
    std::reverse(r.begin(), r.end());
    return list(r);
  });
  N("any", {"xs"}, [](const Args &a, const Node *) {
    for (auto &x : iterate(a["xs"])) if (truthy(x)) return Value(true);
    return Value(false);
  });
  N("all", {"xs"}, [](const Args &a, const Node *) {
    for (auto &x : iterate(a["xs"])) if (!truthy(x)) return Value(false);
    return Value(true);
  });
  N("isinstance", {"x", "t"}, [](const Args &, const Node *) -> Value { throw ScriptError("isinstance() não é suportado"); });
  N("seed", {"n"}, [this](const Args &a, const Node *) { rng = Rng(val0(a["n"])); return Value(); });
  N("random", {}, [this](const Args &, const Node *) { return Value(rng()); });
  N("uniform", {"a", "b"}, [this](const Args &a, const Node *) { double x = val0(a["a"]); return Value(x + (val0(a["b"]) - x) * rng()); });
  N("randint", {"a", "b"}, [this](const Args &a, const Node *) {
    double x = val0(a["a"]);
    return Value(x + std::floor((val0(a["b"]) - x + 1) * rng()));
  });
  N("choice", {"xs"}, [this](const Args &a, const Node *) -> Value {
    auto xs = iterate(a["xs"]);
    size_t i = (size_t)std::floor(rng() * xs.size());
    return i < xs.size() ? xs[i] : Value();
  });

  registerExtraMethods();
  for (auto &[k, v] : shapeBuiltins(scene)) add(k, v);
  for (auto &[k, v] : rigBuiltins(*this)) add(k, v);
  for (auto &[k, v] : scopeBuiltins(*this)) add(k, v);
  for (auto &[k, v] : curveBuiltins(*this)) add(k, v);
  for (auto &[k, v] : libBuiltins(*this)) add(k, v);
  return b;
}

void Interp::tick(int line) {
  if (++steps > maxSteps) throw ScriptError("o script executou passos demais (loop infinito?)", line, "reduza o número de repetições");
}

Scene &Interp::run(const std::string &src) {
  Block program = parse(src);
  execBlock(program, globals);
  return scene;
}

void Interp::execBlock(const Block &b, const ScopeP &scope) {
  for (auto &s : b) exec(*s, scope);
}

void Interp::exec(const Node &s, const ScopeP &scope) {
  tick(s.line);
  try {
    switch (s.k) {
      case K::Expr: eval(*s.e, scope); return;
      case K::Pass: return;
      case K::Assign: {
        Value v = eval(*s.value, scope);
        for (auto &t : s.items) assign(*t, v, scope);
        return;
      }
      case K::Aug: {
        Value cur = eval(*s.target, scope);
        Value v = eval(*s.value, scope);
        if (s.s == "+" && cur.isList() && !cur.isTuple()) {
          if (v.isList()) {
            auto add = v.list()->items;  // cópia: x += x
            cur.list()->items.insert(cur.list()->items.end(), add.begin(), add.end());
          } else cur.list()->items.push_back(v);
          return;
        }
        assign(*s.target, binary(s.s, cur, v), scope);
        return;
      }
      case K::Def: {
        auto f = std::make_shared<UserFunc>();
        f->name = s.s;
        f->params = s.params;
        f->hasStar = s.hasStar;
        f->star = s.star;
        f->body = s.body;
        f->closure = scope;
        scope->set(s.s, Value(FuncP(f)));
        return;
      }
      case K::Return: throw ReturnSig{s.e ? eval(*s.e, scope) : Value()};
      case K::Break: throw BreakSig{};
      case K::Continue: throw ContinueSig{};
      case K::If: {
        for (auto &[cond, body] : s.tests)
          if (truthy(eval(*cond, scope))) { execBlock(body, scope); return; }
        if (s.hasOrelse) execBlock(s.orelse, scope);
        return;
      }
      case K::For: {
        auto items = iterate(eval(*s.iter, scope));
        for (auto &item : items) {
          bindTarget(s.tgt, item, scope, s.line);
          try {
            execBlock(s.body, scope);
          } catch (const BreakSig &) {
            break;
          } catch (const ContinueSig &) {
            continue;
          }
        }
        return;
      }
      case K::While: {
        while (truthy(eval(*s.cond, scope))) {
          tick(s.line);
          try {
            execBlock(s.body, scope);
          } catch (const BreakSig &) {
            break;
          } catch (const ContinueSig &) {
            continue;
          }
        }
        return;
      }
      default: throw ScriptError("comando desconhecido", s.line);
    }
  } catch (ScriptError &e) {
    if (!e.line) e.line = s.line;
    throw;
  }
}

void Interp::bindTarget(const Target &t, const Value &v, const ScopeP &scope, int line) {
  if (!t.tuple) { scope->set(t.name, v); return; }
  auto items = iterate(v);
  if (items.size() != t.items.size())
    throw ScriptError("esperava " + std::to_string(t.items.size()) + " valores para desempacotar, recebeu " + std::to_string(items.size()), line);
  for (size_t i = 0; i < items.size(); i++) bindTarget(t.items[i], items[i], scope, line);
}

void Interp::assign(const Node &t, const Value &v, const ScopeP &scope) {
  if (t.k == K::Name) {
    scope->set(t.s, v);
  } else if (t.k == K::Tuple || t.k == K::List) {
    auto items = iterate(v);
    int si = -1;
    for (size_t i = 0; i < t.items.size(); i++)
      if (t.items[i]->k == K::Starred) { si = (int)i; break; }
    size_t n = t.items.size();
    if (si < 0) {
      if (items.size() != n)
        throw ScriptError("esperava " + std::to_string(n) + " valores para desempacotar, recebeu " + std::to_string(items.size()), t.line);
      for (size_t i = 0; i < n; i++) assign(*t.items[i], items[i], scope);
      return;
    }
    size_t after = n - si - 1;
    if (items.size() < n - 1)
      throw ScriptError("esperava pelo menos " + std::to_string(n - 1) + " valores para desempacotar, recebeu " + std::to_string(items.size()), t.line);
    for (int i = 0; i < si; i++) assign(*t.items[i], items[i], scope);
    assign(*t.items[si]->e, list(std::vector<Value>(items.begin() + si, items.end() - after)), scope);
    for (size_t i = 0; i < after; i++) assign(*t.items[si + 1 + i], items[items.size() - after + i], scope);
  } else if (t.k == K::Index) {
    Value obj = eval(*t.obj, scope);
    Value idx = eval(*t.idx, scope);
    if (obj.isList()) {
      if (obj.isTuple()) throw ScriptError("tuplas não podem ser alteradas", t.line, "use uma lista [..]");
      obj.list()->items[normIndex(obj.size(), idx, t.line)] = v;
    } else if (obj.isDict()) obj.dict()->set(idx, v);
    else throw ScriptError("não é possível atribuir por índice em " + typeName(obj), t.line);
  } else {
    throw ScriptError("formas são imutáveis: não dá para atribuir atributos", t.line, "use os métodos, ex: mesa = mesa.at(1, 0, 0)");
  }
}

std::vector<Value> Interp::evalItems(const Block &items, const ScopeP &scope) {
  std::vector<Value> out;
  for (auto &x : items) {
    if (x->k == K::Starred) {
      auto v = iterate(eval(*x->e, scope));
      out.insert(out.end(), v.begin(), v.end());
    } else out.push_back(eval(*x, scope));
  }
  return out;
}

size_t Interp::normIndex(size_t len, const Value &idx, int line) {
  if (!idx.isNum() || !isInt(idx.n())) throw ScriptError("índice deve ser inteiro", line);
  double i = idx.n() < 0 ? len + idx.n() : idx.n();
  if (i < 0 || i >= len) throw ScriptError("índice " + fmtNum(idx.n()) + " fora da lista (tamanho " + std::to_string(len) + ")", line);
  return (size_t)i;
}

Value Interp::eval(const Node &e, const ScopeP &scope) {
  try {
    return evalInner(e, scope);
  } catch (ScriptError &err) {
    if (!err.line) err.line = e.line;
    throw;
  }
}

Value Interp::evalInner(const Node &e, const ScopeP &scope) {
  switch (e.k) {
    case K::Num: return e.num;
    case K::Str: return e.s;
    case K::Const: return e.cv == ConstV::True ? Value(true) : e.cv == ConstV::False ? Value(false) : Value();
    case K::Concat: {
      std::string out;
      for (auto &p : e.items) out += p->k == K::Fmt ? formatSpec(eval(*p->e, scope), *p) : str(eval(*p, scope));
      return out;
    }
    case K::Name: {
      Value *v = scope->find(e.s);
      if (!v) {
        std::string h = didYouMean(e.s, scope->names());
        throw ScriptError("'" + e.s + "' não está definido", e.line, h.empty() ? "defina a variável antes de usar" : h);
      }
      return *v;
    }
    case K::List: return list(evalItems(e.items, scope));
    case K::Tuple: return tuple(evalItems(e.items, scope));
    case K::Starred: throw ScriptError("'*' fora de lugar", e.line);
    case K::Dict: {
      auto m = std::make_shared<DictObj>();
      for (size_t i = 0; i < e.items.size(); i++) {
        Value k = eval(*e.items[i], scope);
        m->set(k, eval(*e.values[i], scope));
      }
      return Value(m);
    }
    case K::Unary: {
      Value v = eval(*e.e, scope);
      if (e.s == "-") {
        if (v.isNum()) return -v.n();
        if (v.isExpr()) return sym("neg", {v});
        throw ScriptError("não é possível negar " + typeName(v), e.line);
      }
      if (e.s == "+") return v;
      return double(~toInt32(v.isNum() ? v.n() : v.isBool() ? double(v.b()) : 0));
    }
    case K::Not: return !truthy(eval(*e.e, scope));
    case K::And: { Value a = eval(*e.a, scope); return truthy(a) ? eval(*e.b, scope) : a; }
    case K::Or: { Value a = eval(*e.a, scope); return truthy(a) ? a : eval(*e.b, scope); }
    case K::IfExp: return truthy(eval(*e.cond, scope)) ? eval(*e.a, scope) : eval(*e.b, scope);
    case K::Bin: {
      Value a = eval(*e.a, scope);
      return binary(e.s, a, eval(*e.b, scope));
    }
    case K::Cmp: {
      Value left = eval(*e.first, scope);
      for (size_t i = 0; i < e.ops.size(); i++) {
        Value right = eval(*e.items[i], scope);
        if (!compare(e.ops[i], left, right)) return false;
        left = right;
      }
      return true;
    }
    case K::Lambda: {
      auto f = std::make_shared<UserFunc>();
      f->name = "<lambda>";
      f->params = e.params;
      f->lambdaBody = e.body1;
      f->closure = scope;
      f->isLambda = true;
      return Value(FuncP(f));
    }
    case K::Comp: {
      std::vector<Value> out;
      auto inner = std::make_shared<Scope>(scope);
      std::function<void(size_t)> loop = [&](size_t ci) {
        if (ci == e.clauses.size()) { out.push_back(eval(*e.elt, inner)); return; }
        const Clause &c = e.clauses[ci];
        for (auto &item : iterate(eval(*c.iter, inner))) {
          tick(e.line);
          bindTarget(c.target, item, inner, e.line);
          bool ok = true;
          for (auto &cond : c.conds)
            if (!truthy(eval(*cond, inner))) { ok = false; break; }
          if (ok) loop(ci + 1);
        }
      };
      loop(0);
      return list(out);
    }
    case K::Attr: return getAttr(eval(*e.obj, scope), e.s);
    case K::Index: {
      Value obj = eval(*e.obj, scope);
      if (e.idx->k == K::Slice) {
        if (!obj.isList() && !obj.isStr()) throw ScriptError("não é possível fatiar " + typeName(obj), e.line);
        std::vector<Value> arr = obj.isList() ? obj.list()->items : iterate(obj);
        double n = (double)arr.size();
        auto g = [&](const NodeP &x, double d) {
          if (!x) return d;
          double v = val0(eval(*x, scope));
          return v < 0 ? std::max(0.0, n + v) : std::min(n, v);
        };
        double step = e.idx->step ? val0(eval(*e.idx->step, scope)) : 1;
        std::vector<Value> r;
        if (step != 1) {
          double st = g(e.idx->start, step > 0 ? 0 : n - 1), sp = g(e.idx->stop, step > 0 ? n : -1);
          for (double i = st; step > 0 ? i < sp : i > sp; i += step) r.push_back(i >= 0 && i < n ? arr[(size_t)i] : Value());
        } else {
          double a = std::trunc(g(e.idx->start, 0)), b = std::trunc(g(e.idx->stop, n));
          for (double i = a; i < b; i++) r.push_back(arr[(size_t)i]);
        }
        if (obj.isStr()) {
          std::string s;
          for (auto &x : r) s += x.isStr() ? x.s() : "";
          return s;
        }
        return list(r);  // slice do JS devolve lista, mesmo de tupla
      }
      Value idx = eval(*e.idx, scope);
      if (obj.isList()) return obj.list()->items[normIndex(obj.size(), idx, e.line)];
      if (obj.isStr()) { auto cp = codepoints(obj.s()); return cp[normIndex(cp.size(), idx, e.line)]; }
      if (obj.isDict()) {
        Value *v = obj.dict()->find(idx);
        if (!v) throw ScriptError("chave " + repr(idx) + " não existe no dict", e.line);
        return *v;
      }
      throw ScriptError("não é possível indexar " + typeName(obj), e.line);
    }
    case K::Call: {
      Value fn = eval(*e.fn, scope);
      std::vector<Value> args;
      std::vector<std::pair<std::string, Value>> kwargs;
      for (auto &a : e.args) {
        Value v = eval(*a.e, scope);
        if (a.star) { auto it = iterate(v); args.insert(args.end(), it.begin(), it.end()); }
        else if (!a.kw.empty()) kwargs.emplace_back(a.kw, v);
        else args.push_back(v);
      }
      return call(fn, args, kwargs, &e);
    }
    default: break;
  }
  throw ScriptError("expressão desconhecida", e.line);
}

Value Interp::call(const Value &fn, const std::vector<Value> &args, const std::vector<std::pair<std::string, Value>> &kwargs, const Node *node) {
  int line = node ? node->line : 0;
  if (fn.isFunc() && fn.func()->isNative()) {
    auto &f = static_cast<const Native &>(*fn.func());
    try {
      return f.fn(bindArgs(f, args, kwargs), node);
    } catch (ScriptError &err) {
      if (!err.line) err.line = line;
      throw;
    }
  }
  if (fn.isFunc()) {
    auto f = std::static_pointer_cast<UserFunc>(fn.func());
    if (++depth > 200) { depth--; throw ScriptError("recursão profunda demais", line); }
    struct Guard { int &d; ~Guard() { d--; } } guard{depth};
    auto local = std::make_shared<Scope>(f->closure);
    auto &ps = f->params;
    for (size_t i = 0; i < args.size() && i < ps.size(); i++) local->set(ps[i].name, args[i]);
    if (args.size() > ps.size() && !f->hasStar)
      throw ScriptError(f->name + "() recebeu " + std::to_string(args.size()) + " argumentos, aceita " + std::to_string(ps.size()), line);
    if (f->hasStar) local->set(f->star, list(args.size() > ps.size() ? std::vector<Value>(args.begin() + ps.size(), args.end()) : std::vector<Value>{}));
    for (auto &[k, v] : kwargs) {
      bool known = std::any_of(ps.begin(), ps.end(), [&](const Param &p) { return p.name == k; });
      if (!known) {
        std::vector<std::string> names;
        for (auto &p : ps) names.push_back(p.name);
        throw ScriptError(f->name + "() não tem o parâmetro '" + k + "'", line, didYouMean(k, names));
      }
      local->set(k, v);
    }
    for (auto &p : ps) {
      if (!local->hasOwn(p.name)) {
        if (!p.def) throw ScriptError(f->name + "() precisa do argumento '" + p.name + "'", line);
        local->set(p.name, eval(*p.def, f->closure));
      }
    }
    if (f->isLambda) return eval(*f->lambdaBody, local);
    try {
      execBlock(f->body, local);
    } catch (ReturnSig &r) {
      return r.v;
    }
    return Value();
  }
  std::string r = repr(fn);
  auto cp = codepoints(r);
  std::string cut;
  for (size_t i = 0; i < cp.size() && i < 30; i++) cut += cp[i];
  throw ScriptError(typeName(fn) + " " + cut + " não é uma função", line);
}

Value Interp::getAttr(const Value &obj, const std::string &name) {
  if (obj.isShape()) return getShapeAttr(obj.shape(), name);
  if (obj.isObj()) return obj.obj()->attr(name);
  using Methods = std::vector<std::pair<std::string, FuncP>>;
  auto pick = [&](const Methods &m, const std::string &what) -> Value {
    std::vector<std::string> names;
    for (auto &[k, f] : m) {
      if (k == name) return f;
      names.push_back(k);
    }
    throw ScriptError(what + " não tem o método '" + name + "'", 0, didYouMean(name, names));
  };
  auto mutableL = [](const ListP &l) {
    if (l->tuple) throw ScriptError("tuplas não podem ser alteradas", 0, "use uma lista [..]");
  };
  if (obj.isList()) {
    ListP l = obj.list();
    Methods m;
    m.emplace_back("append", native("append", {"x"}, [l, mutableL](const Args &a, const Node *) { mutableL(l); l->items.push_back(a["x"]); return Value(); }));
    m.emplace_back("extend", native("extend", {"xs"}, [l, mutableL](const Args &a, const Node *) {
      mutableL(l);
      auto xs = iterate(a["xs"]);
      l->items.insert(l->items.end(), xs.begin(), xs.end());
      return Value();
    }));
    m.emplace_back("insert", native("insert", {"i", "x"}, [l, mutableL](const Args &a, const Node *) {
      mutableL(l);
      double i = val0(a["i"]), n = (double)l->items.size();
      i = i < 0 ? std::max(0.0, n + i) : std::min(n, i);
      l->items.insert(l->items.begin() + (long)i, a["x"]);
      return Value();
    }));
    m.emplace_back("pop", native("pop", {"i=-1"}, [this, l, mutableL](const Args &a, const Node *) {
      mutableL(l);
      size_t i = normIndex(l->items.size(), a["i"], 0);
      Value v = l->items[i];
      l->items.erase(l->items.begin() + i);
      return v;
    }));
    m.emplace_back("reverse", native("reverse", {}, [l, mutableL](const Args &, const Node *) { mutableL(l); std::reverse(l->items.begin(), l->items.end()); return Value(); }));
    m.emplace_back("index", native("index", {"x"}, [l](const Args &a, const Node *) -> Value {
      for (size_t i = 0; i < l->items.size(); i++)
        if (eq(a["x"], l->items[i])) return i;
      throw ScriptError(repr(a["x"]) + " não está na lista");
    }));
    m.emplace_back("count", native("count", {"x"}, [l](const Args &a, const Node *) {
      return Value((double)std::count_if(l->items.begin(), l->items.end(), [&](const Value &y) { return eq(a["x"], y); }));
    }));
    return pick(m, "lista");
  }
  if (obj.isStr()) {
    std::string s = obj.s();
    Methods m;
    m.emplace_back("upper", native("upper", {}, [s](const Args &, const Node *) { return Value(jsUpper(s)); }));
    m.emplace_back("lower", native("lower", {}, [s](const Args &, const Node *) { return Value(jsLower(s)); }));
    m.emplace_back("join", native("join", {"xs"}, [s](const Args &a, const Node *) {
      std::string out;
      bool first = true;
      for (auto &x : iterate(a["xs"])) { out += (first ? "" : s) + str(x); first = false; }
      return Value(out);
    }));
    m.emplace_back("split", native("split", {"sep=None"}, [s](const Args &a, const Node *) {
      std::vector<Value> out;
      if (a["sep"].isNone()) {
        size_t i = 0;
        while (i < s.size()) {
          while (i < s.size() && std::isspace((unsigned char)s[i])) i++;
          if (i >= s.size()) break;
          size_t j = i;
          while (j < s.size() && !std::isspace((unsigned char)s[j])) j++;
          out.push_back(s.substr(i, j - i));
          i = j;
        }
        if (out.empty()) out.push_back("");
        return list(out);
      }
      std::string sep = str(a["sep"]);
      if (sep.empty()) { for (auto &c : codepoints(s)) out.push_back(c); return list(out); }
      size_t i = 0, j;
      while ((j = s.find(sep, i)) != std::string::npos) { out.push_back(s.substr(i, j - i)); i = j + sep.size(); }
      out.push_back(s.substr(i));
      return list(out);
    }));
    m.emplace_back("startswith", native("startswith", {"s"}, [s](const Args &a, const Node *) { std::string p = str(a["s"]); return Value(s.compare(0, p.size(), p) == 0); }));
    m.emplace_back("endswith", native("endswith", {"s"}, [s](const Args &a, const Node *) {
      std::string p = str(a["s"]);
      return Value(p.size() <= s.size() && s.compare(s.size() - p.size(), p.size(), p) == 0);
    }));
    m.emplace_back("replace", native("replace", {"a", "b"}, [s](const Args &a, const Node *) {
      std::string from = str(a["a"]), to = str(a["b"]), out;
      if (from.empty()) {
        auto cp = codepoints(s);
        for (size_t i = 0; i < cp.size(); i++) out += (i ? to : "") + cp[i];
        return Value(out);
      }
      size_t i = 0, j;
      while ((j = s.find(from, i)) != std::string::npos) { out += s.substr(i, j - i) + to; i = j + from.size(); }
      return Value(out + s.substr(i));
    }));
    m.emplace_back("format", native("format", {"*xs"}, [s](const Args &a, const Node *) {
      auto &xs = a["xs"].list()->items;
      std::string out;
      size_t k = 0;
      for (size_t i = 0; i < s.size(); i++) {
        if (s[i] == '{' && i + 1 < s.size() && s[i + 1] == '}') { out += str(k < xs.size() ? xs[k] : Value()); k++; i++; }
        else out += s[i];
      }
      return Value(out);
    }));
    return pick(m, "texto");
  }
  if (obj.isDict()) {
    DictP d = obj.dict();
    Methods m;
    m.emplace_back("get", native("get", {"k", "default=None"}, [d](const Args &a, const Node *) {
      Value *v = d->find(a["k"]);
      return v ? *v : a["default"];
    }));
    m.emplace_back("keys", native("keys", {}, [d](const Args &, const Node *) {
      std::vector<Value> out;
      for (auto &kv : d->items) out.push_back(kv.first);
      return list(out);
    }));
    m.emplace_back("values", native("values", {}, [d](const Args &, const Node *) {
      std::vector<Value> out;
      for (auto &kv : d->items) out.push_back(kv.second);
      return list(out);
    }));
    m.emplace_back("items", native("items", {}, [d](const Args &, const Node *) {
      std::vector<Value> out;
      for (auto &kv : d->items) out.push_back(tuple({kv.first, kv.second}));
      return list(out);
    }));
    return pick(m, "dict");
  }
  throw ScriptError(typeName(obj) + " não tem o atributo '" + name + "'");
}

RunResult runScript(const std::string &src, long maxSteps) {
  RunResult r;
  r.it = std::make_shared<Interp>(maxSteps);
  try {
    r.it->run(src);
    r.ok = true;
  } catch (const ScriptError &e) {
    r.error = e;
  } catch (const BreakSig &) {
    r.error = ScriptError("'break'/'continue' fora de um loop");
  } catch (const ContinueSig &) {
    r.error = ScriptError("'break'/'continue' fora de um loop");
  } catch (const ReturnSig &) {
    r.error = ScriptError("'return' fora de uma função");
  } catch (const std::exception &e) {
    r.error = ScriptError(std::string("erro interno: ") + e.what());
  }
  r.logs = r.it->logs;
  return r;
}

}  // namespace tdi
