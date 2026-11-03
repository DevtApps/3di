// Âncoras e encaixe de componentes (port de anchor.js).
#include <algorithm>
#include <cmath>
#include <map>

#include "anchor.h"
#include "expr.h"
#include "scope.h"

namespace tdi {

static const std::vector<std::pair<std::string, V3>> DIRS = {
    {"top", {0, 1, 0}}, {"topo", {0, 1, 0}}, {"up", {0, 1, 0}}, {"cima", {0, 1, 0}}, {"+y", {0, 1, 0}},
    {"bottom", {0, -1, 0}}, {"base", {0, -1, 0}}, {"down", {0, -1, 0}}, {"baixo", {0, -1, 0}}, {"-y", {0, -1, 0}},
    {"right", {1, 0, 0}}, {"direita", {1, 0, 0}}, {"+x", {1, 0, 0}},
    {"left", {-1, 0, 0}}, {"esquerda", {-1, 0, 0}}, {"-x", {-1, 0, 0}},
    {"front", {0, 0, 1}}, {"frente", {0, 0, 1}}, {"+z", {0, 0, 1}},
    {"back", {0, 0, -1}}, {"trás", {0, 0, -1}}, {"tras", {0, 0, -1}}, {"-z", {0, 0, -1}},
};
static const char *FACES[] = {"top", "bottom", "right", "left", "front", "back"};

static const V3 *dirOf(const std::string &k) {
  for (auto &[n, v] : DIRS)
    if (n == k) return &v;
  return nullptr;
}
static V3 normV(const V3 &v) {
  double l = std::sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
  return l > 1e-12 ? V3{v[0] / l, v[1] / l, v[2] / l} : V3{0, 1, 0};
}
static double dot(const V3 &a, const V3 &b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }
static V3 cross(const V3 &a, const V3 &b) { return {a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]}; }

M3 inv3(const M3 &m) {
  double a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], g = m[5], h = m[6], i = m[7], k = m[8];
  double A = e * k - g * i, B = -(d * k - g * h), C = d * i - e * h;
  double det = a * A + b * B + c * C;
  M3 r = {A, -(b * k - c * i), b * g - c * e, B, a * k - c * h, -(a * g - c * d), C, -(a * i - b * h), a * e - b * d};
  for (auto &x : r) x /= det;
  return r;
}
static M3 transpose(const M3 &m) { return {m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]}; }

static bool boxOf(const Value &x, BBox &b) {
  if (x.isShape()) { b = x.shape()->bbox(); return true; }
  if (auto s = x.as<ScopeBox>()) { b = {s->min, s->max}; return true; }
  return false;
}

static bool faceAnchor(const BBox &b, const std::string &name, Anchor &out) {
  V3 c = center(b);
  if (name == "center" || name == "centro") { out = {c, {0, 1, 0}}; return true; }
  // só os nomes de face em inglês (no JS os apelidos são outros arrays e não passam no ===)
  bool isFace = false;
  for (auto f : FACES) isFace |= name == f;
  if (!isFace) return false;
  const V3 *n = dirOf(name);
  V3 p = c;
  int i = (*n)[0] != 0 ? 0 : (*n)[1] != 0 ? 1 : 2;
  p[i] = (*n)[i] > 0 ? b.max[i] : b.min[i];
  out = {p, *n};
  return true;
}

// cache das âncoras por forma (as formas são imutáveis)
static std::map<const Shape *, std::pair<std::weak_ptr<const Shape>, std::vector<std::pair<std::string, Anchor>>>> &cache() {
  static std::map<const Shape *, std::pair<std::weak_ptr<const Shape>, std::vector<std::pair<std::string, Anchor>>>> c;
  return c;
}

const std::vector<std::pair<std::string, Anchor>> &declaredAnchors(const ShapeP &s) {
  auto &c = cache();
  auto it = c.find(s.get());
  if (it != c.end() && !it->second.first.expired()) return it->second.second;
  std::vector<std::pair<std::string, Anchor>> out;
  std::function<void(const Shape &, const M3 &, const V3 &)> visit = [&](const Shape &q, const M3 &m, const V3 &t) {
    const Props &P = q.props;
    if (q.kind == "translate" && P.has("anchors")) {
      M3 nm = transpose(inv3(m));
      for (auto &av : P["anchors"].list()->items) {
        auto r = av.as<Rec>();
        std::string name = r->f["name"].s();
        if (std::any_of(out.begin(), out.end(), [&](auto &x) { return x.first == name; })) continue;
        V3 p = mulMV(m, r->f.v3("p"));
        for (int i = 0; i < 3; i++) p[i] += t[i];
        out.push_back({name, {p, normV(mulMV(nm, r->f.v3("n")))}});
      }
    }
    if (q.kind == "translate") {
      V3 mv = mulMV(m, P.v3("v"));
      visit(*q.children[0], m, {t[0] + mv[0], t[1] + mv[1], t[2] + mv[2]});
      return;
    }
    if (q.kind == "rotate") { visit(*q.children[0], mul3(m, P.m3("m")), t); return; }
    if (q.kind == "scale") {
      V3 sv = P.v3("s");
      visit(*q.children[0], mul3(m, {sv[0], 0, 0, 0, sv[1], 0, 0, 0, sv[2]}), t);
      return;
    }
    if (q.kind == "subtract") { visit(*q.children[0], m, t); return; }
    for (auto &ch : q.children) visit(*ch, m, t);
  };
  visit(*s, IDENT, {0, 0, 0});
  auto &slot = c[s.get()];
  slot = {s, std::move(out)};
  return slot.second;
}

Anchor resolveAnchor(const Value &x, const Value &nameV, const std::string &what) {
  std::string key = str(nameV);
  if (x.isShape())
    for (auto &[k, a] : declaredAnchors(x.shape()))
      if (k == key) return a;
  BBox b;
  if (!boxOf(x, b)) throw ScriptError(what + " espera uma forma ou um escopo, recebeu " + typeName(x));
  if (!isFiniteBB(b)) throw ScriptError(what + ": a forma é infinita");
  Anchor f;
  if (faceAnchor(b, jsLower(key), f)) return f;
  std::string names;
  if (x.isShape())
    for (auto &[k, a] : declaredAnchors(x.shape())) names += (names.empty() ? "" : ", ") + k;
  for (auto fc : FACES) names += (names.empty() ? "" : ", ") + std::string(fc);
  names += ", center";
  throw ScriptError(what + ": âncora '" + key + "' não existe", 0, "âncoras disponíveis: " + names);
}

static V3 vecOf(const Value &v, const std::string &what) {
  if (v.isStr()) {
    const V3 *d = dirOf(jsLower(v.s()));
    if (!d) throw ScriptError(what + ": direção desconhecida '" + v.s() + "'", 0, "use \"up\", \"down\", \"front\", \"back\", \"left\", \"right\" ou (x, y, z)");
    return *d;
  }
  if (v.isList() && v.size() == 3) return {num(v[0], what), num(v[1], what), num(v[2], what)};
  throw ScriptError(what + " espera um ponto/direção (x, y, z), recebeu " + typeName(v));
}

static Value anchorMethod(const ShapeP &s, const Args &a) {
  std::string name = str(a["name"]);
  if (name.empty()) throw ScriptError("anchor(): o nome não pode ser vazio");
  V3 p, n{0, 1, 0};
  const Value &at = a["at"];
  if (at.isNone()) {
    if (!isFiniteBB(s->bbox())) throw ScriptError("anchor(): a forma é infinita; passe at=(x, y, z)");
    p = center(s->bbox());
  } else if (at.isStr()) {
    Anchor r = resolveAnchor(Value(s), at, "anchor()");
    p = r.p;
    n = r.n;
  } else if (at.isShape() || at.as<ScopeBox>()) {
    BBox b;
    boxOf(at, b);
    if (!isFiniteBB(b)) throw ScriptError("anchor(): at é infinito");
    p = center(b);
  } else p = vecOf(at, "anchor() at");
  const char *ks[] = {"x", "y", "z"};
  for (int i = 0; i < 3; i++)
    if (!a[ks[i]].isNone()) p[i] = num(a[ks[i]], std::string("anchor() ") + ks[i]);
  if (!a["dir"].isNone()) n = normV(vecOf(a["dir"], "anchor() dir"));
  Value anc = rec({{"name", name}, {"p", nums3(p)}, {"n", nums3(n)}});
  return mkShape("translate", {{"v", nums({0, 0, 0})}, {"anchors", list({anc})}}, {s});
}

static bool rotationTo(const V3 &u, const V3 &v, M3 &R) {
  double c = dot(u, v);
  V3 k = cross(u, v);
  double sn = std::sqrt(dot(k, k));
  if (sn < 1e-9) {
    if (c > 0) return false;
    k = std::fabs(u[1]) > 0.9 ? V3{1, 0, 0} : V3{0, 1, 0};
    sn = 0;
  } else k = {k[0] / sn, k[1] / sn, k[2] / sn};
  double ang = std::atan2(sn, c);
  double x = k[0], y = k[1], z = k[2], C = std::cos(ang), S = std::sin(ang), T = 1 - C;
  R = {T * x * x + C, T * x * y - S * z, T * x * z + S * y, T * x * y + S * z, T * y * y + C, T * y * z - S * x, T * x * z - S * y, T * y * z + S * x, T * z * z + C};
  return true;
}

static Value attachMethod(const ShapeP &s, const Args &a) {
  Anchor A = resolveAnchor(a["target"], a["at"], "attach()");
  double gap = num(a["gap"], "gap");
  V3 off = a["offset"].isNone() ? V3{0, 0, 0} : vecOf(a["offset"], "attach() offset");
  ShapeP piece = s;
  Anchor B;
  if (a["to"].isNone()) {
    V3 want{-A.n[0], -A.n[1], -A.n[2]};
    const char *face = FACES[0];
    for (auto f : FACES)
      if (dot(*dirOf(f), want) > dot(*dirOf(face), want)) face = f;
    B = resolveAnchor(Value(piece), face, "attach()");
  } else {
    B = resolveAnchor(Value(piece), a["to"], "attach()");
    if (truthy(a["turn"])) {
      M3 R;
      if (rotationTo(B.n, {-A.n[0], -A.n[1], -A.n[2]}, R)) {
        piece = aroundPivot(piece, B.p, [&](const ShapeP &q) { return mkShape("rotate", {{"m", nums9(R)}}, {q}); });
        B = {B.p, mulMV(R, B.n)};
      }
    }
  }
  V3 dest, move;
  for (int i = 0; i < 3; i++) { dest[i] = A.p[i] + A.n[i] * gap + off[i]; move[i] = dest[i] - B.p[i]; }
  std::string align = jsLower(str(a["align"]));
  if (align == "bottom" || align == "top") {
    const BBox &b = piece->bbox();
    move[1] = dest[1] - (align == "bottom" ? b.min[1] : b.max[1]);
  } else if (align != "center") {
    throw ScriptError("attach(): align deve ser \"center\", \"bottom\" ou \"top\", recebeu '" + str(a["align"]) + "'");
  }
  return translate(piece, move);
}

static double fix12(double v) {
  char buf[64];
  std::snprintf(buf, sizeof buf, "%.12f", v);
  return std::strtod(buf, nullptr);
}

void registerAnchorMethods() {
  addMethod("anchor", {"name", "at=None", "dir=None", "x=None", "y=None", "z=None"}, anchorMethod);
  addMethod("attach", {"target", "at", "to=None", "gap=0", "offset=None", "turn=True", "align=\"center\""}, attachMethod);
  addMethod("point", {"name"}, [](const ShapeP &s, const Args &a) { return tuple3(resolveAnchor(Value(s), a["name"], "point()").p); });
  addMethod("facing", {"name"}, [](const ShapeP &s, const Args &a) {
    V3 n = resolveAnchor(Value(s), a["name"], "facing()").n;
    return tuple({fix12(n[0]), fix12(n[1]), fix12(n[2])});
  });
  for (auto &[k, f] : shapeAttrs())
    if (k == "anchors") return;
  shapeAttrs().push_back({"anchors", [](const ShapeP &s) {
                            std::vector<Value> out;
                            for (auto &[k, a] : declaredAnchors(s)) out.push_back(k);
                            return list(out);
                          }});
}

}  // namespace tdi
