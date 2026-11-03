// Escopos: caixas para montar estruturas sem calcular coordenadas (port de scope.js).
#include <algorithm>
#include <cmath>
#include <regex>

#include "expr.h"
#include "interp.h"
#include "scope.h"

namespace tdi {

static const double EPS = 1e-6;
static Interp *caller = nullptr;  // o interpretador que chama as funções do script em fill(f)

static std::string jsonStr(const Value &v) {
  if (v.isStr()) return Json(v.s()).dump();
  if (v.isNum()) return jsNum(v.n());
  if (v.isNone()) return "null";
  if (v.isBool()) return v.b() ? "true" : "false";
  return "?";
}

static int axisOf(const Value &v, const std::string &what) {
  std::string s = jsLower(str(v));
  if (s == "x") return 0;
  if (s == "y") return 1;
  if (s == "z") return 2;
  throw ScriptError(what + ": eixo deve ser \"x\", \"y\" ou \"z\", recebeu " + jsonStr(v));
}

struct SizeSpec { bool isFr; double v; };

static SizeSpec parseSize(const Value &v, double total, const std::string &what) {
  if (v.isNum()) {
    if (!(v.n() >= 0)) throw ScriptError(what + ": tamanhos não podem ser negativos");
    return {false, v.n()};
  }
  if (v.isStr()) {
    std::string s = v.s();
    size_t a = s.find_first_not_of(" \t\n"), b = s.find_last_not_of(" \t\n");
    s = a == std::string::npos ? "" : jsLower(s.substr(a, b - a + 1));
    if (s == "~") return {true, 1};
    static const std::regex fr("^(\\d*\\.?\\d+)\\s*fr$"), pct("^(\\d*\\.?\\d+)\\s*%$");
    std::smatch m;
    if (std::regex_match(s, m, fr)) return {true, std::stod(m[1].str())};
    if (std::regex_match(s, m, pct)) return {false, (total * std::stod(m[1].str())) / 100};
  }
  throw ScriptError(what + ": tamanho inválido " + (v.isStr() ? "'" + v.s() + "'" : typeName(v)), 0,
                    "use metros (0.4), \"~\" (o que sobrar), \"2fr\" (partes do que sobrar) ou \"30%\"");
}

ScopeBox::ScopeBox(V3 mn, V3 mx) : min(mn), max(mx) {}

std::shared_ptr<ScopeBox> ScopeBox::of(const Value &s, const std::string &what) {
  if (auto sc = s.as<ScopeBox>()) return sc;
  if (s.isShape()) {
    const BBox &b = s.shape()->bbox();
    for (int i = 0; i < 3; i++)
      if (!(b.min[i] > -1e3) || !(b.max[i] < 1e3)) throw ScriptError(what + ": a forma é infinita");
    return std::make_shared<ScopeBox>(b.min, b.max);
  }
  throw ScriptError(what + " espera uma forma ou um escopo, recebeu " + tdi::typeName(s));
}

V3 ScopeBox::size() const { return {max[0] - min[0], max[1] - min[1], max[2] - min[2]}; }
V3 ScopeBox::center() const { return {(min[0] + max[0]) / 2, (min[1] + max[1]) / 2, (min[2] + max[2]) / 2}; }

std::string ScopeBox::describe() const {
  V3 s = size(), c = center();
  return "<escopo " + fmtNum(s[0]) + " x " + fmtNum(s[1]) + " x " + fmtNum(s[2]) + " centro (" + fmtNum(c[0]) + ", " + fmtNum(c[1]) + ", " + fmtNum(c[2]) + ")>";
}

std::shared_ptr<ScopeBox> ScopeBox::with(int i, double lo, double hi) const {
  V3 mn = min, mx = max;
  mn[i] = lo;
  mx[i] = hi;
  return std::make_shared<ScopeBox>(mn, mx);
}

Value ScopeBox::split(const Value &axis, Value sizes) const {
  int i = axisOf(axis, "split()");
  double L = size()[i];
  if (sizes.isNum()) {
    double n = std::floor(sizes.n() + 0.5);
    if (!(n >= 1) || n != sizes.n()) throw ScriptError("split(): o número de partes deve ser um inteiro >= 1");
    sizes = list(std::vector<Value>((size_t)n, Value("~")));
  }
  if (!sizes.isList() || sizes.size() == 0) throw ScriptError("split() espera uma lista de tamanhos", 0, "ex.: parede.split(\"y\", [0.4, \"~\", 0.5])");
  std::vector<SizeSpec> parts;
  for (auto &v : sizes.list()->items) parts.push_back(parseSize(v, L, "split()"));
  double fixed = 0, frs = 0;
  for (auto &p : parts) (p.isFr ? frs : fixed) += p.v;
  double left = L - fixed;
  std::string ax = str(axis);
  if (left < -EPS) throw ScriptError("split(): os tamanhos fixos somam " + fmtNum(fixed) + " m, mais que os " + fmtNum(L) + " m do eixo " + ax);
  if (frs == 0 && std::fabs(left) > EPS)
    throw ScriptError("split(): os tamanhos somam " + fmtNum(fixed) + " m mas o eixo " + ax + " tem " + fmtNum(L) + " m", 0,
                      "use \"~\" numa das partes para ela ocupar o que sobrar");
  double at = min[i];
  std::vector<Value> out;
  for (auto &p : parts) {
    double len = p.isFr ? (left * p.v) / frs : p.v;
    out.push_back(Value(with(i, at, at + len)));
    at += len;
  }
  return list(out);
}

// junta resultados de fill (formas, listas aninhadas, None) numa forma, ou None se vazio
static Value groupOf(const Value &items, const std::string &what) {
  std::vector<ShapeP> out;
  std::function<void(const Value &)> walk = [&](const Value &v) {
    if (v.isNone()) return;
    if (v.isList()) { for (auto &x : v.list()->items) walk(x); return; }
    if (v.isShape()) { out.push_back(v.shape()); return; }
    throw ScriptError(what + ": a função deve devolver formas (ou None), devolveu " + typeName(v));
  };
  walk(items);
  if (out.empty()) return Value();
  return out.size() == 1 ? Value(out[0]) : Value(unionOf(out));
}

Value ScopeBox::tile(const Value &axis, const Value &sizeV, const Value &f, const Value &gap) const {
  int i = axisOf(axis, "tile()");
  double L = size()[i];
  double sz = num(sizeV, "size"), g = num(gap, "gap");
  if (!(sz > 0)) throw ScriptError("tile(): size deve ser maior que zero");
  if (g < 0) throw ScriptError("tile(): gap não pode ser negativo");
  int n = std::max(1, (int)std::floor((L + g) / (sz + g) + 0.5));
  double len = (L - g * (n - 1)) / n;
  if (!(len > 0)) throw ScriptError("tile(): o gap não deixa espaço para as cópias");
  std::vector<std::shared_ptr<ScopeBox>> cells;
  for (int k = 0; k < n; k++) cells.push_back(with(i, min[i] + k * (len + g), min[i] + k * (len + g) + len));
  std::vector<Value> out;
  if (f.isNone()) {
    for (auto &c : cells) out.push_back(Value(c));
    return list(out);
  }
  FillOpts o;
  for (int k = 0; k < n; k++) { o.index = k; out.push_back(cells[k]->fill(f, o)); }
  return groupOf(list(out), "tile()");
}

Value ScopeBox::inset(const Args &a) const {
  V3 d;
  if (a["x"].isList()) {
    auto &l = a["x"].list()->items;
    for (int i = 0; i < 3; i++) d[i] = num(i < (int)l.size() ? l[i] : Value(), "inset");
  } else if (a["y"].isNone() && a["z"].isNone()) {
    for (int i = 0; i < 3; i++) d[i] = num(a["x"], "inset");
  } else {
    d = {num(a["x"], "inset"), a["y"].isNone() ? 0 : num(a["y"], "inset"), a["z"].isNone() ? 0 : num(a["z"], "inset")};
  }
  V3 mn, mx;
  for (int i = 0; i < 3; i++) { mn[i] = min[i] + d[i]; mx[i] = max[i] - d[i]; }
  for (int i = 0; i < 3; i++)
    if (mn[i] > mx[i] + EPS) throw ScriptError("inset(): o recuo é maior que o escopo");
  for (int i = 0; i < 3; i++) mx[i] = std::max(mx[i], mn[i]);
  return Value(std::make_shared<ScopeBox>(mn, mx));
}

static bool isCallable(const Value &v) { return v.isFunc(); }

Value ScopeBox::fill(const Value &x, const FillOpts &o) const {
  if (x.isNone()) return Value();
  if (isCallable(x)) {
    if (!caller) throw ScriptError("fill(): funções não disponíveis aqui");
    auto &f = *x.func();
    size_t nArgs = f.isNative() ? static_cast<const Native &>(f).params.size() : static_cast<const UserFunc &>(f).params.size();
    auto self = std::const_pointer_cast<ScopeBox>(std::static_pointer_cast<const ScopeBox>(shared_from_this()));
    std::vector<Value> args{Value(self)};
    if (o.index >= 0 && nArgs >= 2) args.push_back(o.index);
    Value r = caller->call(x, args, {}, nullptr);
    return r.isNone() ? Value() : groupOf(list({r}), "fill()");
  }
  if (x.isShape()) return fit(x.shape(), o.fit, o.align);
  if (x.isList() && std::any_of(x.list()->items.begin(), x.list()->items.end(), [](const Value &v) { return v.isShape() || v.isFunc(); })) {
    std::vector<Value> out;
    for (auto &v : x.list()->items) out.push_back(fill(v, o));
    return groupOf(list(out), "fill()");
  }
  V3 s = size();
  if (s[0] <= EPS || s[1] <= EPS || s[2] <= EPS) return Value();
  double mn = std::min({s[0], s[1], s[2]});
  double r = std::min(num(o.round, "round"), mn / 2);
  double c = std::min(num(o.bevel, "bevel"), mn / 2);
  ShapeP box = c > 0 ? mkShape("cbox", {{"size", nums3(s)}, {"c", c}, {"r", r}}) : mkShape("box", {{"size", nums3(s)}, {"r", r}});
  Args ma;
  ma.set("color", x);
  box = material(box, ma);
  return Value(translate(box, center()));
}

Value ScopeBox::fit(const ShapeP &s, const std::string &fitMode, const std::string &align) const {
  const BBox &b = s->bbox();
  V3 ss = tdi::size(b);
  for (double v : ss)
    if (!(v < 1e3)) throw ScriptError("fill(): a forma é infinita");
  V3 sz = size(), k;
  if (fitMode == "stretch") for (int i = 0; i < 3; i++) k[i] = ss[i] > EPS && sz[i] > EPS ? sz[i] / ss[i] : 1;
  else if (fitMode == "contain") {
    double u = INFINITY;
    for (int i = 0; i < 3; i++) u = std::min(u, ss[i] > EPS ? sz[i] / ss[i] : INFINITY);
    k = {u, u, u};
  } else if (fitMode == "none") k = {1, 1, 1};
  else throw ScriptError("fill(): fit deve ser \"stretch\", \"contain\" ou \"none\", recebeu '" + fitMode + "'");
  ShapeP out = s;
  if (std::fabs(k[0] - 1) > EPS || std::fabs(k[1] - 1) > EPS || std::fabs(k[2] - 1) > EPS) {
    if (k[0] <= 0 || k[1] <= 0 || k[2] <= 0) throw ScriptError("scale() deve ser positivo", 0, "para inverter use mirror()");
    V3 c = isFiniteBB(s->bbox()) ? tdi::center(s->bbox()) : V3{0, 0, 0};
    out = aroundPivot(s, c, [&](const ShapeP &q) { return mkShape("scale", {{"s", nums3(k)}}, {q}); });
  }
  const BBox &ob = out->bbox();
  V3 oc = tdi::center(ob), c = center();
  double dy = align == "center" || fitMode == "stretch" ? c[1] - oc[1] : min[1] - ob.min[1];
  if (align != "bottom" && align != "center") throw ScriptError("fill(): align deve ser \"bottom\" ou \"center\"");
  return Value(translate(out, V3{c[0] - oc[0], dy, c[2] - oc[2]}));
}

Value ScopeBox::attr(const std::string &name) {
  V3 sz = size(), c = center();
  if (name == "__box__") return list({min[0], min[1], min[2], max[0], max[1], max[2]});
  if (name == "w" || name == "width") return sz[0];
  if (name == "h" || name == "height") return sz[1];
  if (name == "d" || name == "depth") return sz[2];
  if (name == "size") return tuple3(sz);
  if (name == "center") return tuple3(c);
  if (name == "x") return c[0];
  if (name == "y") return c[1];
  if (name == "z") return c[2];
  if (name == "left") return min[0];
  if (name == "right") return max[0];
  if (name == "bottom") return min[1];
  if (name == "top") return max[1];
  if (name == "back") return min[2];
  if (name == "front") return max[2];
  if (name == "min") return tuple3(min);
  if (name == "max") return tuple3(max);
  auto self = std::static_pointer_cast<ScopeBox>(shared_from_this());
  if (name == "split") return native("split", {"axis", "sizes"}, [self](const Args &a, const Node *) { return self->split(a["axis"], a["sizes"]); });
  if (name == "tile")
    return native("tile", {"axis", "size", "f=None", "gap=0"}, [self](const Args &a, const Node *) { return self->tile(a["axis"], a["size"], a["f"], a["gap"]); });
  if (name == "fill")
    return native("fill", {"what", "fit=\"stretch\"", "round=0", "bevel=0", "align=\"bottom\""}, [self](const Args &a, const Node *) {
      FillOpts o;
      o.fit = str(a["fit"]);
      o.round = a["round"];
      o.bevel = a["bevel"];
      o.align = str(a["align"]);
      return self->fill(a["what"], o);
    });
  if (name == "inset") return native("inset", {"x", "y=None", "z=None"}, [self](const Args &a, const Node *) { return self->inset(a); });
  throw ScriptError("escopo não tem o atributo '" + name + "'", 0,
                    "atributos: w, h, d, size, center, x, y, z, left, right, bottom, top, back, front, min, max, split, tile, fill, inset");
}

Json ScopeBox::plain() const {
  Json o = Json::object();
  o.set("$", "Scope");
  o.set("isScope", true);
  Json mn = Json::array(), mx = Json::array();
  for (int i = 0; i < 3; i++) { mn.push(round9(min[i])); mx.push(round9(max[i])); }
  o.set("max", std::move(mx));
  o.set("min", std::move(mn));
  return o;
}

Builtins scopeBuiltins(Interp &it) {
  caller = &it;
  addMethod("space", {}, [](const ShapeP &s, const Args &) { return Value(ScopeBox::of(Value(s), "space()")); });
  addMethod("split", {"axis", "sizes"}, [](const ShapeP &s, const Args &a) { return ScopeBox::of(Value(s), "split()")->split(a["axis"], a["sizes"]); });
  addMethod("tile", {"axis", "size", "f=None", "gap=0"},
            [](const ShapeP &s, const Args &a) { return ScopeBox::of(Value(s), "tile()")->tile(a["axis"], a["size"], a["f"], a["gap"]); });
  return {{"space", native("space", {"w=1", "h=None", "d=None"}, [](const Args &a, const Node *) {
             double w = num(a["w"], "w"), h = a["h"].isNone() ? w : num(a["h"], "h"), d = a["d"].isNone() ? w : num(a["d"], "d");
             if (!(w > 0 && h > 0 && d > 0)) throw ScriptError("space(): tamanhos devem ser positivos");
             return Value(std::make_shared<ScopeBox>(V3{-w / 2, 0, -d / 2}, V3{w / 2, h, d / 2}));
           })}};
}

}  // namespace tdi
