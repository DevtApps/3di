#include "value.h"

#include <algorithm>
#include <charconv>
#include <cmath>
#include <cstdio>
#include <cstdlib>

#include "expr.h"
#include "shape.h"

namespace tdi {

bool Value::isTuple() const { return isList() && list()->tuple; }
size_t Value::size() const { return list()->items.size(); }
const Value &Value::operator[](size_t i) const { return list()->items[i]; }

ListP newList(std::vector<Value> items) { auto l = std::make_shared<ListObj>(); l->items = std::move(items); return l; }
ListP newTuple(std::vector<Value> items) { auto l = newList(std::move(items)); l->tuple = true; return l; }
Value list(std::vector<Value> items) { return Value(newList(std::move(items))); }
Value tuple(std::vector<Value> items) { return Value(newTuple(std::move(items))); }
Value tuple3(const std::array<double, 3> &v) { return tuple({v[0], v[1], v[2]}); }

// SameValueZero do Map: números e textos por valor, None/bool por valor, o resto por identidade
static bool mapKeyEq(const Value &a, const Value &b) {
  if (a.v.index() != b.v.index()) return false;
  if (a.isNum()) return a.n() == b.n() || (std::isnan(a.n()) && std::isnan(b.n()));
  return same(a, b);
}
Value *DictObj::find(const Value &k) {
  for (auto &[key, val] : items)
    if (mapKeyEq(key, k)) return &val;
  return nullptr;
}
void DictObj::set(const Value &k, Value v) {
  if (Value *p = find(k)) *p = std::move(v);
  else items.emplace_back(k, std::move(v));
}

Value Object::attr(const std::string &name) {
  throw ScriptError("objeto não tem o atributo '" + name + "'");
}
Json Object::plain() const { return Json::object(); }

// ---------- argumentos ----------

const Value &Args::operator[](const std::string &k) const {
  static const Value none;
  for (auto &x : a)
    if (x.name == k) return x.v;
  return none;
}
bool Args::has(const std::string &k) const {
  return std::any_of(a.begin(), a.end(), [&](const Arg2 &x) { return x.name == k; });
}
void Args::set(const std::string &k, Value v) {
  for (auto &x : a)
    if (x.name == k) { x.v = std::move(v); return; }
  a.push_back({k, std::move(v)});
}

static Param2 parseParam(const std::string &spec) {
  size_t eq = spec.find('=');
  if (eq == std::string::npos) return {spec, true, {}};
  std::string raw = spec.substr(eq + 1);
  Value def;
  if (raw == "None") def = Value();
  else if (raw == "True") def = true;
  else if (raw == "False") def = false;
  else if (!raw.empty() && (raw[0] == '"' || raw[0] == '\'')) def = raw.substr(1, raw.size() - 2);
  else def = std::strtod(raw.c_str(), nullptr);
  return {spec.substr(0, eq), false, def};
}

FuncP native(const std::string &name, const std::vector<std::string> &params, NativeFn fn) {
  auto f = std::make_shared<Native>();
  f->name = name;
  f->fn = std::move(fn);
  for (auto &p : params) {
    if (!p.empty() && p[0] == '*') f->star = p.substr(1);
    else f->params.push_back(parseParam(p));
  }
  return f;
}
FuncP native(const std::string &name, std::initializer_list<const char *> params, NativeFn fn) {
  std::vector<std::string> ps(params.begin(), params.end());
  return native(name, ps, std::move(fn));
}

std::string Native::signature() const {
  std::vector<std::string> ps;
  size_t req = 0;
  for (auto &p : params) {
    ps.push_back(p.required ? p.name : p.name + "=" + repr(p.def));
    req += p.required;
  }
  if (!star.empty()) ps.insert(ps.begin() + req, "*" + star);
  std::string out = name + "(";
  for (size_t i = 0; i < ps.size(); i++) out += (i ? ", " : "") + ps[i];
  return out + ")";
}

Args bindArgs(const Native &f, const std::vector<Value> &args, const std::vector<std::pair<std::string, Value>> &kwargs) {
  Args out;
  const auto &ps = f.params;
  size_t req = std::count_if(ps.begin(), ps.end(), [](const Param2 &p) { return p.required; });
  std::vector<Value> extra;
  for (size_t i = 0; i < args.size(); i++) {
    if (i < ps.size() && !(!f.star.empty() && i >= req)) out.set(ps[i].name, args[i]);
    else extra.push_back(args[i]);
  }
  if (!extra.empty() && f.star.empty())
    throw ScriptError(f.name + "() recebeu argumentos demais (" + std::to_string(args.size()) + ")", 0, "assinatura: " + f.signature());
  if (!f.star.empty()) out.set(f.star, list(extra));
  for (auto &[k, v] : kwargs) {
    auto p = std::find_if(ps.begin(), ps.end(), [&](const Param2 &q) { return q.name == k; });
    if (p == ps.end()) {
      std::vector<std::string> names;
      for (auto &q : ps) names.push_back(q.name);
      std::string h = didYouMean(k, names);
      throw ScriptError(f.name + "() não tem o parâmetro '" + k + "'", 0, h.empty() ? "assinatura: " + f.signature() : h);
    }
    if (out.has(k)) throw ScriptError(f.name + "() recebeu '" + k + "' duas vezes");
    out.set(k, v);
  }
  for (auto &p : ps) {
    if (!out.has(p.name)) {
      if (p.required) throw ScriptError(f.name + "() precisa do argumento '" + p.name + "'", 0, "assinatura: " + f.signature());
      out.set(p.name, p.def);
    }
  }
  return out;
}

// ---------- texto ----------

std::vector<std::string> codepoints(const std::string &s) {
  std::vector<std::string> out;
  for (size_t i = 0; i < s.size();) {
    unsigned char c = s[i];
    size_t n = c >= 0xF0 ? 4 : c >= 0xE0 ? 3 : c >= 0xC0 ? 2 : 1;
    out.push_back(s.substr(i, n));
    i += n;
  }
  return out;
}

static std::string lower(const std::string &s) {
  std::string r = s;
  for (auto &c : r) c = (char)std::tolower((unsigned char)c);
  return r;
}

int levenshtein(const std::string &a0, const std::string &b0) {
  auto a = codepoints(a0), b = codepoints(b0);
  size_t m = a.size(), n = b.size();
  std::vector<std::vector<int>> d(m + 1, std::vector<int>(n + 1));
  for (size_t i = 0; i <= m; i++) d[i][0] = (int)i;
  for (size_t j = 0; j <= n; j++) d[0][j] = (int)j;
  for (size_t i = 1; i <= m; i++)
    for (size_t j = 1; j <= n; j++)
      d[i][j] = std::min({d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)});
  return d[m][n];
}

std::string didYouMean(const std::string &word, const std::vector<std::string> &options) {
  const std::string *best = nullptr;
  int bestD = 1 << 30;
  std::string w = lower(word);
  for (auto &o : options) {
    int d = levenshtein(w, lower(o));
    if (d < bestD) { bestD = d; best = &o; }
  }
  int lim = std::max(2, (int)codepoints(word).size() / 3);
  return best && bestD <= lim ? "você quis dizer '" + *best + "'?" : "";
}

bool isInt(double x) { return std::isfinite(x) && std::floor(x) == x; }

// String(x) do JavaScript (menor representação que volta ao mesmo double)
std::string jsNum(double x) {
  if (std::isnan(x)) return "NaN";
  if (std::isinf(x)) return x > 0 ? "Infinity" : "-Infinity";
  if (x == 0) return "0";
  char buf[64];
  auto r = std::to_chars(buf, buf + sizeof buf, x, std::chars_format::scientific);
  std::string sci(buf, r.ptr);  // d.ddde±XX
  bool neg = sci[0] == '-';
  if (neg) sci = sci.substr(1);
  size_t e = sci.find('e');
  std::string digits = sci.substr(0, e);
  digits.erase(std::remove(digits.begin(), digits.end(), '.'), digits.end());
  int exp10 = std::atoi(sci.c_str() + e + 1);
  int k = (int)digits.size(), n = exp10 + 1;  // valor = 0.digits * 10^n
  std::string out;
  if (k <= n && n <= 21) out = digits + std::string(n - k, '0');
  else if (0 < n && n <= 21) out = digits.substr(0, n) + "." + digits.substr(n);
  else if (-6 < n && n <= 0) out = "0." + std::string(-n, '0') + digits;
  else {
    out = digits.substr(0, 1);
    if (k > 1) out += "." + digits.substr(1);
    out += std::string("e") + (n - 1 >= 0 ? "+" : "-") + std::to_string(std::abs(n - 1));
  }
  return neg ? "-" + out : out;
}

std::string fmtNum(double x) {
  if (isInt(x)) return jsNum(x);
  return jsNum(std::floor(x * 1e6 + 0.5) / 1e6);
}

std::string typeName(const Value &v) {
  if (v.isNone()) return "None";
  if (v.isNum()) return "número";
  if (v.isStr()) return "texto";
  if (v.isBool()) return "bool";
  if (v.isList()) return "lista";
  if (v.isDict()) return "dict";
  if (v.isShape()) return "forma";
  if (v.isExpr()) return "expressão animada";
  if (v.isFunc()) return "função";
  return "objeto";
}

std::string repr(const Value &v) {
  if (v.isNone()) return "None";
  if (v.isBool()) return v.b() ? "True" : "False";
  if (v.isNum()) return fmtNum(v.n());
  if (v.isStr()) return "'" + v.s() + "'";
  if (v.isList()) {
    auto &l = *v.list();
    std::string s;
    for (size_t i = 0; i < l.items.size(); i++) s += (i ? ", " : "") + repr(l.items[i]);
    if (l.tuple) return "(" + s + (l.items.size() == 1 ? "," : "") + ")";
    return "[" + s + "]";
  }
  if (v.isDict()) {
    std::string s;
    bool first = true;
    for (auto &[k, x] : v.dict()->items) { s += (first ? "" : ", ") + repr(k) + ": " + repr(x); first = false; }
    return "{" + s + "}";
  }
  if (v.isShape()) return v.shape()->describe();
  if (v.isExpr()) return v.expr()->describe();
  if (v.isFunc()) return "<função " + v.func()->name + ">";
  return v.obj()->describe();
}

std::string str(const Value &v) { return v.isStr() ? v.s() : repr(v); }

static std::string typeTag(const Value &v) {
  std::string t = typeName(v);
  if (t == "None") return "None";
  auto cp = codepoints(repr(v));
  std::string r;
  for (size_t i = 0; i < cp.size() && i < 30; i++) r += cp[i];
  return t + " " + r;
}

double num(const Value &v, const std::string &what) {
  if (v.isNum() && std::isfinite(v.n())) return v.n();
  if (v.isExpr())
    throw ScriptError(what + " não aceita valores animados (time)", 0, "time funciona em at/move, rotate, scale (uniforme) e no glow de material()");
  if (v.isBool()) return v.b() ? 1 : 0;
  throw ScriptError(what + " deve ser um número, recebeu " + typeTag(v));
}

Value numT(const Value &v, const std::string &what) { return v.isExpr() ? v : Value(num(v, what)); }

std::array<double, 2> vec2(const Value &v, const std::string &what) {
  if (v.isList() && v.size() == 2) return {num(v[0], what + "[0]"), num(v[1], what + "[1]")};
  throw ScriptError(what + " deve ser uma tupla (a, b), recebeu " + typeTag(v));
}

std::array<double, 3> vec3(const Value &v, const std::string &what) {
  if (v.isList() && v.size() == 3) return {num(v[0], what + "[0]"), num(v[1], what + "[1]"), num(v[2], what + "[2]")};
  throw ScriptError(what + " deve ser uma tupla (x, y, z), recebeu " + typeTag(v));
}

std::vector<Value> iterate(const Value &v) {
  if (v.isList()) return v.list()->items;
  if (v.isStr()) {
    std::vector<Value> out;
    for (auto &c : codepoints(v.s())) out.push_back(c);
    return out;
  }
  if (v.isDict()) {
    std::vector<Value> out;
    for (auto &kv : v.dict()->items) out.push_back(kv.first);
    return out;
  }
  throw ScriptError("não é possível percorrer " + typeName(v) + " com for", 0, "use uma lista ou range(n)");
}

static const char *TIME_HINT = "para variar com o tempo (ou numa fórmula de implicit) use contas e funções: sin, cos, abs, min, max, clamp, lerp, smoothstep, step, osc";

bool truthy(const Value &v) {
  if (v.isExpr()) throw ScriptError("valores com time não podem ser usados em if/while/and/or", 0, TIME_HINT);
  if (v.isNone()) return false;
  if (v.isBool()) return v.b();
  if (v.isNum()) return v.n() != 0;  // NaN é verdadeiro, como no JS
  if (v.isStr()) return !v.s().empty();
  if (v.isList()) return !v.list()->items.empty();
  if (v.isDict()) return !v.dict()->items.empty();
  return true;
}

bool same(const Value &a, const Value &b) {
  if (a.v.index() != b.v.index()) return false;
  switch (a.v.index()) {
    case 0: return true;
    case 1: return a.b() == b.b();
    case 2: return a.n() == b.n();
    case 3: return a.s() == b.s();
    case 4: return a.list() == b.list();
    case 5: return a.dict() == b.dict();
    case 6: return a.func() == b.func();
    case 7: return a.shape() == b.shape();
    case 8: return a.expr() == b.expr();
    default: return a.obj() == b.obj();
  }
}

bool eq(const Value &a, const Value &b) {
  if (a.isList() && b.isList()) {
    auto &x = a.list()->items, &y = b.list()->items;
    if (x.size() != y.size()) return false;
    for (size_t i = 0; i < x.size(); i++)
      if (!eq(x[i], y[i])) return false;
    return true;
  }
  return same(a, b);
}

double round9(double x) {
  if (!std::isfinite(x) || x == 0) return x;
  char buf[40];
  std::snprintf(buf, sizeof buf, "%.8e", x);
  return std::strtod(buf, nullptr);
}

Json plain(const Value &v) {
  if (v.isNone()) return Json();
  if (v.isBool()) return Json(v.b());
  if (v.isNum()) return std::isfinite(v.n()) ? Json(round9(v.n())) : Json(jsNum(v.n()));
  if (v.isStr()) return Json(v.s());
  if (v.isFunc()) return Json("<fn>");
  if (v.isList()) {
    Json a = Json::array();
    for (auto &x : v.list()->items) a.push(plain(x));
    return a;
  }
  if (v.isDict()) { Json o = Json::object(); o.set("$", "Map"); return o; }
  if (v.isShape()) return v.shape()->plainTree();
  if (v.isExpr()) return v.expr()->plain();
  return v.obj()->plain();
}

}  // namespace tdi
