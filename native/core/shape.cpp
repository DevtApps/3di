// Port de shapes.js. As props guardam os mesmos campos (e na mesma forma) que no JS, para os golden
// files baterem e para o compilador/SDF portados lerem as mesmas chaves.
#include "shape.h"

#include <algorithm>
#include <cmath>
#include <regex>

#include "expr.h"
#include "hull.h"
#include "profile.h"

namespace tdi {

const M3 IDENT = {1, 0, 0, 0, 1, 0, 0, 0, 1};

// ---------- Props ----------

const Value &Props::operator[](const std::string &k) const {
  static const Value none;
  for (auto &[key, v] : kv)
    if (key == k) return v;
  return none;
}
bool Props::has(const std::string &k) const {
  return std::any_of(kv.begin(), kv.end(), [&](auto &p) { return p.first == k; });
}
Props &Props::set(const std::string &k, Value v) {
  for (auto &[key, x] : kv)
    if (key == k) { x = std::move(v); return *this; }
  kv.emplace_back(k, std::move(v));
  return *this;
}
double Props::num(const std::string &k) const { return val0((*this)[k]); }
std::vector<double> Props::vec(const std::string &k) const { return toVec((*this)[k]); }
V3 Props::v3(const std::string &k) const { auto v = vec(k); return {v[0], v[1], v[2]}; }
M3 Props::m3(const std::string &k) const { auto v = vec(k); M3 m; std::copy_n(v.begin(), 9, m.begin()); return m; }
Json Props::plain() const {
  Json o = Json::object();
  for (auto &[k, v] : kv)
    if (k.empty() || k[0] != '_') o.set(k, tdi::plain(v));
  return o;
}

Value Rec::attr(const std::string &name) {
  if (f.has(name)) return f[name];
  return Object::attr(name);
}

Value nums(const std::vector<double> &v) {
  std::vector<Value> out(v.begin(), v.end());
  return list(out);
}
Value nums3(const V3 &v) { return nums({v[0], v[1], v[2]}); }
Value nums9(const M3 &m) { return nums(std::vector<double>(m.begin(), m.end())); }
std::vector<double> toVec(const Value &v) {
  std::vector<double> out;
  if (!v.isList()) return out;
  for (auto &x : v.list()->items) out.push_back(val0(x));
  return out;
}

// ---------- Shape ----------

static BBox computeBBox(const Shape &s);

const BBox &Shape::bbox() const {
  if (!bb_) bb_ = computeBBox(*this);
  return *bb_;
}

bool Shape::selfAnimated() const {
  auto anyE = [&](const char *k) {
    const Value &a = props[k];
    if (!a.isList()) return false;
    return std::any_of(a.list()->items.begin(), a.list()->items.end(), [](const Value &x) { return x.isExpr(); });
  };
  const Value &f = props["f"];
  return anyE("v") || anyE("angles") || anyE("s") || props["glow"].isExpr() || (f.isExpr() && f.expr()->usesTime());
}

bool Shape::animated() const {
  if (anim_ < 0) anim_ = selfAnimated() || std::any_of(children.begin(), children.end(), [](auto &c) { return c->animated(); });
  return anim_ == 1;
}

int Shape::leaves() const {
  if (leaves_ < 0) {
    int n = 0;
    for (auto &c : children) n += c->leaves();
    leaves_ = children.empty() ? 1 : n;
  }
  return leaves_;
}

std::string Shape::describe() const {
  const BBox &b = bbox();
  std::string name = kind == "label" ? props["name"].s() : "";
  if (!isFiniteBB(b)) return "<forma " + name + (name.empty() ? "" : " ") + "infinita>";
  V3 sz = size(b), c = center(b);
  return "<forma " + name + (name.empty() ? "" : " ") + fmtNum(sz[0]) + " x " + fmtNum(sz[1]) + " x " + fmtNum(sz[2]) + " centro (" +
         fmtNum(c[0]) + ", " + fmtNum(c[1]) + ", " + fmtNum(c[2]) + ")>";
}

Json Shape::plainTree() const {
  Json o = Json::object();
  Json ch = Json::array();
  for (auto &c : children) ch.push(c->plainTree());
  o.set("children", std::move(ch));
  o.set("kind", kind);
  o.set("props", props.plain());
  return o;
}

// ---------- caixas ----------

static BBox bb(V3 a, V3 b) { return {a, b}; }
bool isFiniteBB(const BBox &b) {
  for (int i = 0; i < 3; i++)
    if (!(b.min[i] > -INF / 2) || !(b.max[i] < INF / 2)) return false;
  return true;
}
V3 center(const BBox &b) { return {(b.min[0] + b.max[0]) / 2, (b.min[1] + b.max[1]) / 2, (b.min[2] + b.max[2]) / 2}; }
V3 size(const BBox &b) { return {b.max[0] - b.min[0], b.max[1] - b.min[1], b.max[2] - b.min[2]}; }
static BBox symB(double x, double y, double z) { return bb({-x, -y, -z}, {x, y, z}); }
static BBox expand(const BBox &b, double r) {
  return bb({b.min[0] - r, b.min[1] - r, b.min[2] - r}, {b.max[0] + r, b.max[1] + r, b.max[2] + r});
}

std::array<V3, 8> corners(const BBox &b) {
  std::array<V3, 8> out;
  for (int i = 0; i < 8; i++) out[i] = {i & 1 ? b.max[0] : b.min[0], i & 2 ? b.max[1] : b.min[1], i & 4 ? b.max[2] : b.min[2]};
  return out;
}

BBox fromPoints(const std::vector<V3> &pts) {
  BBox b{{INFINITY, INFINITY, INFINITY}, {-INFINITY, -INFINITY, -INFINITY}};
  for (auto &p : pts)
    for (int i = 0; i < 3; i++) { b.min[i] = std::min(b.min[i], p[i]); b.max[i] = std::max(b.max[i], p[i]); }
  return b;
}

BBox unionBB(const std::vector<BBox> &list) {
  BBox b{{INFINITY, INFINITY, INFINITY}, {-INFINITY, -INFINITY, -INFINITY}};
  for (auto &x : list)
    for (int i = 0; i < 3; i++) { b.min[i] = std::min(b.min[i], x.min[i]); b.max[i] = std::max(b.max[i], x.max[i]); }
  return b;
}

V3 mulMV(const M3 &m, const V3 &v) {
  V3 r;
  for (int i = 0; i < 3; i++) r[i] = m[i * 3] * v[0] + m[i * 3 + 1] * v[1] + m[i * 3 + 2] * v[2];
  return r;
}

M3 mul3(const M3 &a, const M3 &b) {
  M3 r{};
  for (int i = 0; i < 3; i++)
    for (int j = 0; j < 3; j++)
      for (int k = 0; k < 3; k++) r[i * 3 + j] += a[i * 3 + k] * b[k * 3 + j];
  return r;
}

static V3 add(const V3 &a, const V3 &b) { return {a[0] + b[0], a[1] + b[1], a[2] + b[2]}; }

BBox transformedBBox(const Shape &s, const M3 &m, const V3 &t) {
  const std::string &k = s.kind;
  const Props &p = s.props;
  if (k == "translate") return transformedBBox(*s.children[0], m, add(t, mulMV(m, p.v3("v"))));
  if (k == "rotate") return transformedBBox(*s.children[0], mul3(m, p.m3("m")), t);
  if (k == "scale") {
    V3 S = p.v3("s");
    return transformedBBox(*s.children[0], mul3(m, {S[0], 0, 0, 0, S[1], 0, 0, 0, S[2]}), t);
  }
  if (k == "affine") return transformedBBox(*s.children[0], mul3(m, p.m3("m")), add(t, mulMV(m, p.v3("t"))));
  if (k == "union" || k == "merge") {
    std::vector<BBox> bs;
    for (auto &c : s.children) bs.push_back(transformedBBox(*c, m, t));
    return unionBB(bs);
  }
  if (k == "subtract" || k == "material" || k == "label" || k == "bound") return transformedBBox(*s.children[0], m, t);
  if (k == "paint") {
    BBox b = transformedBBox(*s.children[0], m, t);
    double e = std::max(0.0, p["relief"].isNum() ? p.num("relief") : 0.0) * 1.01;
    return e ? expand(b, e) : b;
  }
  std::vector<V3> pts;
  for (auto &c : corners(s.bbox())) pts.push_back(add(mulMV(m, c), t));
  return fromPoints(pts);
}

static BBox clampInf(const BBox &b) {
  BBox r = b;
  for (int i = 0; i < 3; i++) { r.min[i] = std::max(b.min[i], -INF); r.max[i] = std::min(b.max[i], INF); }
  return r;
}

static double maxRadiusXZ(const BBox &b) {
  double R = -INFINITY;
  for (auto &c : corners(b)) R = std::max(R, std::hypot(c[0], c[2]));
  return R;
}

static BBox computeBBox(const Shape &s) {
  const Props &p = s.props;
  const std::string &k = s.kind;
  const Shape *c0 = s.children.empty() ? nullptr : s.children[0].get();
  if (k == "box" || k == "cbox") { V3 z = p.v3("size"); return symB(z[0] / 2, z[1] / 2, z[2] / 2); }
  if (k == "sphere") { double r = p.num("r"); return symB(r, r, r); }
  if (k == "cylinder" || k == "capsule") return symB(p.num("r"), p.num("h") / 2, p.num("r"));
  if (k == "cone") { double r = std::max(p.num("r"), p.num("top")); return symB(r, p.num("h") / 2, r); }
  if (k == "torus") { double R = p.num("R") + p.num("r"); return symB(R, p.num("r"), R); }
  if (k == "ellipsoid") { V3 r = p.v3("radii"); return symB(r[0], r[1], r[2]); }
  if (k == "pyramid") return symB(p.num("w") / 2, p.num("h") / 2, p.num("w") / 2);
  if (k == "prism") return symB(p.num("w") / 2, p.num("h") / 2, p.num("d") / 2);
  if (k == "plane") return bb({-INF, -INF, -INF}, {INF, 0, INF});
  if (k == "affine") return transformedBBox(*c0, p.m3("m"), p.v3("t"));
  if (k == "union" || k == "merge") {
    std::vector<BBox> bs;
    for (auto &c : s.children) bs.push_back(c->bbox());
    return unionBB(bs);
  }
  if (k == "subtract" || k == "pattern" || k == "material" || k == "label" || k == "bound") return c0->bbox();
  if (k == "intersect") {
    BBox b{{-INFINITY, -INFINITY, -INFINITY}, {INFINITY, INFINITY, INFINITY}};
    for (auto &c : s.children)
      for (int i = 0; i < 3; i++) { b.min[i] = std::max(b.min[i], c->bbox().min[i]); b.max[i] = std::min(b.max[i], c->bbox().max[i]); }
    return b;
  }
  if (k == "translate") {
    V3 v = p.v3("v");
    const BBox &b = c0->bbox();
    return clampInf(bb(add(b.min, v), add(b.max, v)));
  }
  if (k == "rotate") {
    if (!isFiniteBB(c0->bbox())) return bb({-INF, -INF, -INF}, {INF, INF, INF});
    return transformedBBox(*c0, p.m3("m"), {0, 0, 0});
  }
  if (k == "scale") {
    V3 S = p.v3("s");
    const BBox &b = c0->bbox();
    return clampInf(bb({b.min[0] * S[0], b.min[1] * S[1], b.min[2] * S[2]}, {b.max[0] * S[0], b.max[1] * S[1], b.max[2] * S[2]}));
  }
  if (k == "displace") return expand(c0->bbox(), p.num("amt"));
  if (k == "mirror") {
    BBox b = c0->bbox(), r = b;
    for (int i = 0; i < 3; i++) {
      if (!p["axes"][i].b()) continue;
      r.min[i] = std::min(b.min[i], -b.max[i]);
      r.max[i] = std::max(b.max[i], -b.min[i]);
    }
    return r;
  }
  if (k == "round") return expand(c0->bbox(), p.num("r"));
  if (k == "shell") return expand(c0->bbox(), p.num("t") / 2);
  if (k == "twist" || k == "polar") {
    const BBox &b = c0->bbox();
    double R = maxRadiusXZ(b);
    return bb({-R, b.min[1], -R}, {R, b.max[1], R});
  }
  if (k == "taper") {
    double f = std::max(p.num("top"), p.num("bottom"));
    int ax = (int)p.num("axis");
    BBox b = c0->bbox();
    for (int i = 0; i < 3; i++)
      if (i != ax) { b.min[i] *= f; b.max[i] *= f; }
    return b;
  }
  if (k == "bend") {
    BBox b = c0->bbox();
    double d = std::fabs(p.num("k")) * p.num("len") * p.num("len") * 0.5 * 1.15;
    int ax = (int)p.num("axis"), tw = (int)p.num("toward");
    for (int i = 0; i < 3; i++)
      if (i == ax || i == tw) { b.min[i] -= d; b.max[i] += d; }
    return b;
  }
  if (k == "shear") {
    const BBox &b = c0->bbox();
    V3 sh{p.num("sx"), 0, p.num("sz")};
    double lo = b.min[1] - p.num("y0"), hi = b.max[1] - p.num("y0");
    BBox r;
    for (int i = 0; i < 3; i++) {
      r.min[i] = b.min[i] + std::min(sh[i] * lo, sh[i] * hi);
      r.max[i] = b.max[i] + std::max(sh[i] * lo, sh[i] * hi);
    }
    return r;
  }
  if (k == "elongate") {
    V3 h = p.v3("h");
    const BBox &b = c0->bbox();
    return bb({b.min[0] - h[0], b.min[1] - h[1], b.min[2] - h[2]}, {b.max[0] + h[0], b.max[1] + h[1], b.max[2] + h[2]});
  }
  if (k == "extrude") {
    Bounds2 b = boundsOf(pointsOf(p["pts"]));
    double h = p.num("h");
    if (p["axis"].s() == "z") return bb({b.minX, b.minY, -h / 2}, {b.maxX, b.maxY, h / 2});
    return bb({b.minX, -h / 2, b.minY}, {b.maxX, h / 2, b.maxY});
  }
  if (k == "lathe") { double R = p.num("rmax"); return bb({-R, p.num("y0"), -R}, {R, p.num("y1"), R}); }
  if (k == "implicit") { V3 h = p.v3("half"); return symB(h[0], h[1], h[2]); }
  if (k == "repeat") {
    const BBox &b = c0->bbox();
    V3 n = p.v3("n"), sp = p.v3("s");
    BBox r;
    for (int i = 0; i < 3; i++) {
      double e = ((n[i] - 1) * sp[i]) / 2;
      r.min[i] = b.min[i] - e;
      r.max[i] = b.max[i] + e;
    }
    return r;
  }
  if (k == "paint") { double rel = p.num("relief"); return rel > 0 ? expand(c0->bbox(), rel * 1.01) : c0->bbox(); }
  if (k == "hull") {
    std::vector<V3> pts;
    for (auto &v : p["pts"].list()->items) pts.push_back({v[0].n(), v[1].n(), v[2].n()});
    return fromPoints(pts);
  }
  if (k == "loft") {
    std::vector<V3> pts;
    for (auto &r : p["rings"].list()->items)
      for (auto &v : r.list()->items) pts.push_back({v[0].n(), v[1].n(), v[2].n()});
    return fromPoints(pts);
  }
  if (k == "roundcone") {
    V3 a = p.v3("a"), b = p.v3("b");
    double r1 = p.num("r1"), r2 = p.num("r2");
    BBox r;
    for (int i = 0; i < 3; i++) { r.min[i] = std::min(a[i] - r1, b[i] - r2); r.max[i] = std::max(a[i] + r1, b[i] + r2); }
    return r;
  }
  throw std::runtime_error("bbox: tipo desconhecido " + k);
}

// ---------- construtores ----------

ShapeP translate(const ShapeP &s, std::vector<Value> v) {
  bool zero = std::all_of(v.begin(), v.end(), [](const Value &x) { return x.isNum() && std::fabs(x.n()) < 1e-9; });
  if (zero) return s;
  if (s->kind == "translate" && !s->props.has("anchors")) {
    const Value &pv = s->props["v"];
    std::vector<Value> sum;
    for (int i = 0; i < 3; i++) sum.push_back(sym("+", {v[i], pv[i]}));
    return translate(s->children[0], sum);
  }
  return mkShape("translate", {{"v", list(v)}}, {s});
}
ShapeP translate(const ShapeP &s, const V3 &v) { return translate(s, std::vector<Value>{v[0], v[1], v[2]}); }

M3 rotMatrix(double ax, double ay, double az) {
  double x = ax * M_PI / 180, y = ay * M_PI / 180, z = az * M_PI / 180;
  double cx = std::cos(x), sx = std::sin(x), cy = std::cos(y), sy = std::sin(y), cz = std::cos(z), sz = std::sin(z);
  M3 Rx = {1, 0, 0, 0, cx, -sx, 0, sx, cx};
  M3 Ry = {cy, 0, sy, 0, 1, 0, -sy, 0, cy};
  M3 Rz = {cz, -sz, 0, sz, cz, 0, 0, 0, 1};
  return mul3(Rz, mul3(Ry, Rx));
}

static V3 pivotOf(const Shape &s, const Value &pivot) {
  if (!pivot.isNone()) return vec3(pivot, "pivot");
  return isFiniteBB(s.bbox()) ? center(s.bbox()) : V3{0, 0, 0};
}

ShapeP aroundPivot(const ShapeP &s, const V3 &c, const std::function<ShapeP(const ShapeP &)> &wrap) {
  return translate(wrap(translate(s, V3{-c[0], -c[1], -c[2]})), c);
}

ShapeP segmentShape(const V3 &a, const V3 &b, double r) {
  V3 d{b[0] - a[0], b[1] - a[1], b[2] - a[2]};
  double len = std::sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
  V3 mid{(a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2};
  if (len < 1e-9) return translate(mkShape("sphere", {{"r", r}}), mid);
  V3 n{d[0] / len, d[1] / len, d[2] / len};
  double ax = std::asin(std::max(-1.0, std::min(1.0, n[2]))) * 180 / M_PI;
  double az = std::atan2(-n[0], n[1]) * 180 / M_PI;
  auto cap = mkShape("capsule", {{"r", r}, {"h", len + 2 * r}});
  return translate(mkShape("rotate", {{"m", nums9(rotMatrix(ax, 0, az))}}, {cap}), mid);
}

ShapeP roundCone(const V3 &a, const V3 &b, double r1, double r2) {
  if (std::hypot(b[0] - a[0], b[1] - a[1], b[2] - a[2]) < 1e-9) return translate(mkShape("sphere", {{"r", std::max(r1, r2)}}), a);
  return mkShape("roundcone", {{"a", nums3(a)}, {"b", nums3(b)}, {"r1", r1}, {"r2", r2}});
}

static void catmull(const std::vector<V3> &pts, const std::vector<double> &radii, int k, std::vector<V3> &P, std::vector<double> &R) {
  int n = (int)pts.size();
  auto g = [&](int i) { return pts[std::max(0, std::min(n - 1, i))]; };
  for (int i = 0; i + 1 < n; i++) {
    for (int j = 0; j < k; j++) {
      double t = double(j) / k, t2 = t * t, t3 = t2 * t;
      V3 p0 = g(i - 1), p1 = g(i), p2 = g(i + 1), p3 = g(i + 2), q;
      for (int c = 0; c < 3; c++)
        q[c] = 0.5 * (2 * p1[c] + (-p0[c] + p2[c]) * t + (2 * p0[c] - 5 * p1[c] + 4 * p2[c] - p3[c]) * t2 + (-p0[c] + 3 * p1[c] - 3 * p2[c] + p3[c]) * t3);
      P.push_back(q);
      R.push_back(radii[i] + (radii[i + 1] - radii[i]) * t);
    }
  }
  P.push_back(pts[n - 1]);
  R.push_back(radii[n - 1]);
}

ShapeP unionOf(const std::vector<ShapeP> &list, double k) {
  if (list.size() == 1) return list[0];
  return mkShape("union", {{"k", k}}, list);
}

static void flattenInto(const std::vector<Value> &values, const std::string &what, std::vector<ShapeP> &out) {
  for (auto &v : values) {
    if (v.isNone()) continue;
    if (v.isList()) flattenInto(v.list()->items, what, out);
    else if (v.isShape()) out.push_back(v.shape());
    else throw ScriptError(what + " espera formas, recebeu " + typeName(v), 0, v.isNum() ? "para posicionar use .at(x, y, z)" : "");
  }
}
std::vector<ShapeP> flatten(const std::vector<Value> &values, const std::string &what) {
  std::vector<ShapeP> out;
  flattenInto(values, what, out);
  return out;
}

void needFinite(const Shape &s, const std::string &what) {
  if (!isFiniteBB(s.bbox()))
    throw ScriptError(what + " não funciona com formas infinitas (plane)", 0, "mostre o plane separadamente: show(plane(), objeto)");
}

static V3 xyzArgs(const Args &a, const std::string &what) {
  if (a["x"].isList()) return vec3(a["x"], what);
  return {num(a["x"], what + " x"), num(a["y"], what + " y"), num(a["z"], what + " z")};
}

static std::vector<Value> xyzArgsT(const Args &a, const std::string &what) {
  std::vector<Value> v = a["x"].isList() ? a["x"].list()->items : std::vector<Value>{a["x"], a["y"], a["z"]};
  if (v.size() != 3) throw ScriptError(what + " espera (x, y, z)");
  for (int i = 0; i < 3; i++) v[i] = numT(v[i], what + " " + "xyz"[i]);
  return v;
}

// ---------- cores e materiais ----------

const std::vector<std::pair<std::string, std::string>> COLORS = {
    {"red", "#d63c3c"}, {"vermelho", "#d63c3c"}, {"green", "#4caf50"}, {"verde", "#4caf50"}, {"blue", "#3b6fd6"}, {"azul", "#3b6fd6"},
    {"yellow", "#f2c53d"}, {"amarelo", "#f2c53d"}, {"orange", "#ee8a2e"}, {"laranja", "#ee8a2e"}, {"purple", "#8e5ad6"}, {"roxo", "#8e5ad6"},
    {"pink", "#ec7fb0"}, {"rosa", "#ec7fb0"}, {"cyan", "#3cc8d6"}, {"ciano", "#3cc8d6"}, {"white", "#f2f2f2"}, {"branco", "#f2f2f2"},
    {"black", "#1c1c1c"}, {"preto", "#1c1c1c"}, {"gray", "#8a8a8a"}, {"grey", "#8a8a8a"}, {"cinza", "#8a8a8a"},
    {"lightgray", "#c8c8c8"}, {"darkgray", "#444444"}, {"brown", "#7a4e2d"}, {"marrom", "#7a4e2d"}, {"wood", "#a0703f"},
    {"madeira", "#a0703f"}, {"darkwood", "#5c3a1e"}, {"gold", "#e0b040"}, {"ouro", "#e0b040"}, {"silver", "#c0c4c8"},
    {"prata", "#c0c4c8"}, {"copper", "#c47a4a"}, {"cobre", "#c47a4a"}, {"grass", "#5d9b3a"}, {"grama", "#5d9b3a"},
    {"leaf", "#3f8a35"}, {"folha", "#3f8a35"}, {"stone", "#9a968e"}, {"pedra", "#9a968e"}, {"brick", "#a8503a"},
    {"tijolo", "#a8503a"}, {"sand", "#dcc79a"}, {"areia", "#dcc79a"}, {"water", "#3a8fc4"}, {"agua", "#3a8fc4"},
    {"água", "#3a8fc4"}, {"skin", "#e8b996"}, {"pele", "#e8b996"}, {"concrete", "#b5b2aa"}, {"concreto", "#b5b2aa"},
    {"snow", "#fbfbff"}, {"neve", "#fbfbff"},
};

static double srgbToLinear(double c) { return c <= 0.04045 ? c / 12.92 : std::pow((c + 0.055) / 1.055, 2.4); }

// toLowerCase do JS para o que aparece em nomes de cor/textura (ASCII e Latin-1 em UTF-8)
std::string jsLower(const std::string &s) {
  std::string r;
  for (size_t i = 0; i < s.size(); i++) {
    unsigned char c = s[i];
    if (c < 0x80) r += (char)std::tolower(c);
    else if (c == 0xC3 && i + 1 < s.size() && (unsigned char)s[i + 1] >= 0x80 && (unsigned char)s[i + 1] <= 0x9E && (unsigned char)s[i + 1] != 0x97) {
      r += (char)c;
      r += (char)((unsigned char)s[i + 1] + 0x20);
      i++;
    } else r += (char)c;
  }
  return r;
}

static std::vector<std::string> keysOf(const std::vector<std::pair<std::string, std::string>> &m) {
  std::vector<std::string> out;
  for (auto &p : m) out.push_back(p.first);
  return out;
}

std::array<double, 3> parseColor(const Value &v) {
  if (v.isList() && v.size() == 3) {
    V3 c = vec3(v, "cor");
    double scale = (c[0] > 1 || c[1] > 1 || c[2] > 1) ? 255 : 1;
    for (auto &x : c) x = srgbToLinear(std::min(1.0, std::max(0.0, x / scale)));
    return c;
  }
  if (v.isStr()) {
    std::string hex = v.s(), low = jsLower(v.s());
    for (auto &[k, h] : COLORS)
      if (k == low) { hex = h; break; }
    static const std::regex short3("^#?([0-9a-fA-F])([0-9a-fA-F])([0-9a-fA-F])$");
    static const std::regex full("^#?([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$");
    std::smatch m;
    if (std::regex_match(hex, m, short3)) hex = "#" + std::string(2, m[1].str()[0]) + std::string(2, m[2].str()[0]) + std::string(2, m[3].str()[0]);
    if (std::regex_match(hex, m, full)) {
      std::array<double, 3> c;
      for (int i = 0; i < 3; i++) c[i] = srgbToLinear(std::stoi(m[i + 1].str(), nullptr, 16) / 255.0);
      return c;
    }
    std::string h = didYouMean(v.s(), keysOf(COLORS));
    throw ScriptError("cor desconhecida '" + v.s() + "'", 0, h.empty() ? "use um nome (red, wood...), \"#rrggbb\" ou (r, g, b)" : h);
  }
  throw ScriptError("cor inválida: " + typeName(v), 0, "use um nome (red, wood...), \"#rrggbb\" ou (r, g, b)");
}

static Value colorValue(const std::array<double, 3> &c) { return nums({c[0], c[1], c[2]}); }

ShapeP material(const ShapeP &s, const Args &a) {
  Props p;
  p.set("facet", a["facet"]);
  p.set("coat", a["coat"].isNone() ? Value() : Value(std::min(1.0, std::max(0.0, num(a["coat"], "coat")))));
  p.set("color", a["color"].isNone() ? Value() : colorValue(parseColor(a["color"])));
  p.set("rough", a["rough"].isNone() ? Value() : Value(num(a["rough"], "rough")));
  p.set("metal", a["metal"].isNone() ? Value() : Value(num(a["metal"], "metal")));
  p.set("glow", a["glow"].isNone() ? Value() : numT(a["glow"], "glow"));
  p.set("tex", a["tex"]);
  return mkShape("material", p, {s});
}
static ShapeP materialKV(const ShapeP &s, const char *k, Value v) {
  Args a;
  a.set(k, std::move(v));
  return material(s, a);
}

const std::vector<std::pair<std::string, int>> TEXTURES = {
    {"noise", 1}, {"ruido", 1}, {"ruído", 1}, {"wood", 2}, {"madeira", 2}, {"marble", 3}, {"marmore", 3}, {"mármore", 3},
    {"stripes", 4}, {"listras", 4}, {"checker", 5}, {"xadrez", 5}, {"bricks", 6}, {"tijolos", 6}, {"gradient", 7},
    {"degradê", 7}, {"degrade", 7}, {"mottle", 8}, {"manchas", 8}, {"relief", 9}, {"relevo", 9},
};

struct Side { int axis, dir; };
static const std::vector<std::pair<std::string, Side>> SIDES = {
    {"right", {0, 1}}, {"direita", {0, 1}}, {"+x", {0, 1}}, {"left", {0, -1}}, {"esquerda", {0, -1}}, {"-x", {0, -1}},
    {"front", {2, 1}}, {"frente", {2, 1}}, {"+z", {2, 1}}, {"back", {2, -1}}, {"trás", {2, -1}}, {"tras", {2, -1}}, {"-z", {2, -1}},
};

static V3 bottomCenter(const BBox &b) { V3 c = center(b); return {c[0], b.min[1], c[2]}; }

int axisIndex(const Value &v, const std::string &what) {
  std::string s = jsLower(str(v));
  if (s == "x") return 0;
  if (s == "y") return 1;
  if (s == "z") return 2;
  throw ScriptError(what + "(): eixo inválido '" + str(v) + "'", 0, "use \"x\", \"y\" ou \"z\"");
}

Boxed asShape(const Value &v, const std::string &what) {
  if (v.isShape()) return {v.shape(), v.shape()->bbox()};
  // escopos (space(), split...) servem de alvo para o layout: só a caixa importa
  if (v.isObj() && (what == "on()" || what == "under()" || what == "beside()")) {
    Value isScope;
    try { isScope = v.obj()->attr("__box__"); } catch (const ScriptError &) {}
    if (isScope.isList()) return {nullptr, {{isScope[0].n(), isScope[1].n(), isScope[2].n()}, {isScope[3].n(), isScope[4].n(), isScope[5].n()}}};
  }
  throw ScriptError(what + " espera uma forma, recebeu " + typeName(v));
}

static ShapeP stack(const ShapeP &s, const Args &a, int dir) {
  Boxed t = asShape(a["target"], dir > 0 ? "on()" : "under()");
  needFinite(*s, dir > 0 ? "on()" : "under()");
  const BBox &sb = s->bbox(), &tb = t.bb;
  V3 sc = center(sb);
  double gap = num(a["gap"], "gap");
  double dy = dir > 0 ? tb.max[1] + gap - sb.min[1] : tb.min[1] - gap - sb.max[1];
  double dx, dz;
  if (isFiniteBB(tb)) {
    V3 tc = center(tb);
    dx = tc[0] + (a["x"].isNone() ? 0 : num(a["x"], "x")) - sc[0];
    dz = tc[2] + (a["z"].isNone() ? 0 : num(a["z"], "z")) - sc[2];
  } else {
    dx = a["x"].isNone() ? 0 : num(a["x"], "x") - sc[0];
    dz = a["z"].isNone() ? 0 : num(a["z"], "z") - sc[2];
  }
  return translate(s, V3{dx, dy, dz});
}

static ShapeP mergeShapes(const std::vector<ShapeP> &list, const Args &a) {
  if (list.empty()) throw ScriptError("merge() vazio");
  if (list.size() == 1) return list[0];
  double r = num(a["r"], "r");
  if (!(r > 0)) throw ScriptError("merge(): r deve ser maior que zero", 0, "r é o raio do filete (ou largura do chanfro/sulco) em metros");
  std::string profile = jsLower(str(a["profile"]));
  if (profile != "round" && profile != "chamfer" && profile != "groove")
    throw ScriptError("merge(): profile desconhecido '" + str(a["profile"]) + "'", 0, "use \"round\" (filete), \"chamfer\" (chanfro) ou \"groove\" (sulco)");
  std::string colors = jsLower(str(a["colors"]));
  if (colors != "sharp" && colors != "blend") throw ScriptError("merge(): colors deve ser \"sharp\" ou \"blend\"");
  Value seam = a["seam"].isNone() ? Value() : colorValue(parseColor(a["seam"]));
  double seamWidth = a["seam_width"].isNone() ? r : num(a["seam_width"], "seam_width");
  return mkShape("merge", {{"r", r}, {"profile", profile}, {"colors", colors}, {"seam", seam}, {"seamWidth", seamWidth}}, list);
}

ShapeP subtractOf(const ShapeP &a, const std::vector<ShapeP> &others, const Value &smooth) {
  if (others.empty()) return a;
  return mkShape("subtract", {{"k", num(smooth, "smooth")}}, {a, unionOf(others)});
}

ShapeP intersectOf(const std::vector<ShapeP> &list, const Value &smooth) {
  if (list.size() == 1) return list[0];
  return mkShape("intersect", {{"k", num(smooth, "smooth")}}, list);
}

std::vector<std::pair<std::string, MethodDef>> &shapeMethods() {
  static std::vector<std::pair<std::string, MethodDef>> m;
  return m;
}
void addMethod(const std::string &name, std::vector<std::string> params, ShapeMethod fn) {
  for (auto &[k, d] : shapeMethods())
    if (k == name) { d = {std::move(params), std::move(fn)}; return; }
  shapeMethods().push_back({name, {std::move(params), std::move(fn)}});
}
std::vector<std::pair<std::string, std::function<Value(const ShapeP &)>>> &shapeAttrs() {
  static std::vector<std::pair<std::string, std::function<Value(const ShapeP &)>>> m;
  return m;
}

static std::vector<Value> shapes2values(const std::vector<ShapeP> &v) { return std::vector<Value>(v.begin(), v.end()); }

static void registerCoreMethods() {
  addMethod("at", {"x=0", "y=0", "z=0"}, [](const ShapeP &s, const Args &a) { return translate(s, xyzArgsT(a, "at")); });
  addMethod("move", {"x=0", "y=0", "z=0"}, [](const ShapeP &s, const Args &a) { return translate(s, xyzArgsT(a, "move")); });
  addMethod("place", {"x=0", "y=0", "z=0"}, [](const ShapeP &s, const Args &a) {
    needFinite(*s, "place()");
    V3 target = xyzArgs(a, "place"), cur = bottomCenter(s->bbox());
    return translate(s, V3{target[0] - cur[0], target[1] - cur[1], target[2] - cur[2]});
  });
  addMethod("ground", {}, [](const ShapeP &s, const Args &) {
    needFinite(*s, "ground()");
    return translate(s, V3{0, -s->bbox().min[1], 0});
  });
  addMethod("on", {"target", "x=None", "z=None", "gap=0"}, [](const ShapeP &s, const Args &a) { return stack(s, a, +1); });
  addMethod("under", {"target", "x=None", "z=None", "gap=0"}, [](const ShapeP &s, const Args &a) { return stack(s, a, -1); });
  addMethod("beside", {"target", "side=\"right\"", "gap=0"}, [](const ShapeP &s, const Args &a) {
    Boxed t = asShape(a["target"], "beside()");
    needFinite(*s, "beside()");
    if (t.shape) needFinite(*t.shape, "beside()");
    std::string sd = jsLower(str(a["side"]));
    const Side *side = nullptr;
    for (auto &[k, v] : SIDES)
      if (k == sd) side = &v;
    if (!side) throw ScriptError("lado desconhecido '" + str(a["side"]) + "'", 0, "use 'right', 'left', 'front' ou 'back'");
    const BBox &sb = s->bbox(), &tb = t.bb;
    V3 tc = center(tb), sc = center(sb);
    V3 d{tc[0] - sc[0], tb.min[1] - sb.min[1], tc[2] - sc[2]};
    int ax = side->axis;
    d[ax] = side->dir > 0 ? tb.max[ax] + num(a["gap"], "gap") - sb.min[ax] : tb.min[ax] - num(a["gap"], "gap") - sb.max[ax];
    return translate(s, d);
  });
  addMethod("rotate", {"x=0", "y=0", "z=0", "pivot=None"}, [](const ShapeP &s, const Args &a) -> Value {
    auto ang = xyzArgsT(a, "rotate");
    if (std::all_of(ang.begin(), ang.end(), [](const Value &v) { return v.isNum() && v.n() == 0; })) return s;
    M3 m = rotMatrix(val0(ang[0]), val0(ang[1]), val0(ang[2]));
    Props props{{"m", nums9(m)}};
    if (std::any_of(ang.begin(), ang.end(), [](const Value &v) { return v.isExpr(); })) props.set("angles", list(ang));
    return aroundPivot(s, pivotOf(*s, a["pivot"]), [&](const ShapeP &q) { return mkShape("rotate", props, {q}); });
  });
  addMethod("scale", {"s", "pivot=None"}, [](const ShapeP &s, const Args &a) {
    std::vector<Value> f;
    if (a["s"].isList()) { V3 v = vec3(a["s"], "scale"); f = {v[0], v[1], v[2]}; }
    else for (int i = 0; i < 3; i++) f.push_back(numT(a["s"], "scale"));
    if (std::any_of(f.begin(), f.end(), [](const Value &v) { return val0(v) <= 0; }))
      throw ScriptError("scale() deve ser positivo", 0, "para inverter use mirror()");
    return aroundPivot(s, pivotOf(*s, a["pivot"]), [&](const ShapeP &q) { return mkShape("scale", {{"s", list(f)}}, {q}); });
  });
  addMethod("mirror", {"axes=\"x\""}, [](const ShapeP &s, const Args &a) {
    std::string ax = jsLower(str(a["axes"]));
    if (ax.empty() || ax.find_first_not_of("xyz") != std::string::npos)
      throw ScriptError("eixos inválidos '" + str(a["axes"]) + "'", 0, "use \"x\", \"z\", \"xz\"...");
    return mkShape("mirror", {{"axes", list({ax.find('x') != std::string::npos, ax.find('y') != std::string::npos, ax.find('z') != std::string::npos})}}, {s});
  });
  addMethod("repeat", {"x=1", "y=1", "z=1", "spacing=None"}, [](const ShapeP &s, const Args &a) {
    needFinite(*s, "repeat()");
    V3 n;
    const char *xyz[] = {"x", "y", "z"};
    for (int i = 0; i < 3; i++) {
      double k = num(a[xyz[i]], xyz[i]);
      if (!isInt(k) || std::fabs(k) > 9007199254740991.0 || k < 1)
        throw ScriptError("repeat() precisa de quantidades inteiras >= 1 representáveis com precisão");
      n[i] = k;
    }
    if (n[0] * n[1] * n[2] > 9007199254740991.0) throw ScriptError("repeat(): quantidade de cópias excede a precisão numérica");
    V3 sz = size(s->bbox()), sp;
    if (a["spacing"].isNone()) for (int i = 0; i < 3; i++) sp[i] = sz[i] > 0 ? sz[i] * 1.5 : 1;
    else if (a["spacing"].isList()) sp = vec3(a["spacing"], "spacing");
    else for (int i = 0; i < 3; i++) sp[i] = num(a["spacing"], "spacing");
    bool fits = true;
    for (int i = 0; i < 3; i++) fits &= n[i] == 1 || sz[i] <= sp[i] + 1e-6;
    V3 c = center(s->bbox());
    if (fits) return aroundPivot(s, c, [&](const ShapeP &q) { return mkShape("repeat", {{"n", nums3(n)}, {"s", nums3(sp)}}, {q}); });
    if (n[0] * n[1] * n[2] > 64)
      throw ScriptError("repeat(): as cópias se sobrepõem e são muitas para desenrolar", 0, "aumente spacing para ser maior que o tamanho da forma");
    std::vector<ShapeP> copies;
    for (int i = 0; i < n[0]; i++)
      for (int j = 0; j < n[1]; j++)
        for (int k = 0; k < n[2]; k++)
          copies.push_back(translate(s, V3{(i - (n[0] - 1) / 2) * sp[0], (j - (n[1] - 1) / 2) * sp[1], (k - (n[2] - 1) / 2) * sp[2]}));
    return unionOf(copies);
  });
  addMethod("round", {"r"}, [](const ShapeP &s, const Args &a) { return mkShape("round", {{"r", num(a["r"], "round")}}, {s}); });
  addMethod("shell", {"thickness"}, [](const ShapeP &s, const Args &a) { return mkShape("shell", {{"t", num(a["thickness"], "shell")}}, {s}); });
  addMethod("twist", {"degrees"}, [](const ShapeP &s, const Args &a) {
    needFinite(*s, "twist()");
    double h = size(s->bbox())[1];
    if (h == 0) h = 1;
    double k = (num(a["degrees"], "twist") * M_PI) / 180 / h;
    return aroundPivot(s, center(s->bbox()), [&](const ShapeP &q) { return mkShape("twist", {{"k", k}}, {q}); });
  });
  addMethod("taper", {"top=0.5", "bottom=1", "axis=\"y\""}, [](const ShapeP &s, const Args &a) {
    needFinite(*s, "taper()");
    int axis = axisIndex(a["axis"], "taper");
    double top = num(a["top"], "top"), bottom = num(a["bottom"], "bottom");
    if (!(top > 0) || !(bottom > 0))
      throw ScriptError("taper(): top e bottom devem ser maiores que zero", 0, "top=0.5 afina a ponta pela metade; top=2 alarga");
    return mkShape("taper", {{"top", top}, {"bottom", bottom}, {"axis", axis}, {"lo", s->bbox().min[axis]}, {"hi", s->bbox().max[axis]}}, {s});
  });
  addMethod("bend", {"angle", "axis=\"y\"", "toward=None", "pivot=None"}, [](const ShapeP &s, const Args &a) {
    needFinite(*s, "bend()");
    int axis = axisIndex(a["axis"], "bend");
    int toward = a["toward"].isNone() ? (axis == 0 ? 1 : 0) : axisIndex(a["toward"], "bend");
    if (toward == axis) throw ScriptError("bend(): toward deve ser outro eixo que axis", 0, "ex.: bend(60, axis=\"y\", toward=\"x\")");
    double pivot = a["pivot"].isNone() ? s->bbox().min[axis] : num(a["pivot"], "pivot");
    double len = std::max(1e-6, s->bbox().max[axis] - pivot);
    double k = -(num(a["angle"], "angle") * M_PI) / 180 / len;
    return mkShape("bend", {{"k", k}, {"axis", axis}, {"toward", toward}, {"pivot", pivot}, {"len", len}}, {s});
  });
  addMethod("shear", {"x=0", "z=0"}, [](const ShapeP &s, const Args &a) {
    needFinite(*s, "shear()");
    return mkShape("shear", {{"sx", num(a["x"], "x")}, {"sz", num(a["z"], "z")}, {"y0", s->bbox().min[1]}}, {s});
  });
  addMethod("polar", {"count"}, [](const ShapeP &s, const Args &a) {
    needFinite(*s, "polar()");
    double n = num(a["count"], "count");
    if (!isInt(n) || n < 2 || n > 256)
      throw ScriptError("polar() precisa de um inteiro de 2 a 256", 0, "a forma deve ficar afastada do eixo y; polar(6) faz 6 cópias em volta dele");
    return mkShape("polar", {{"n", n}}, {s});
  });
  addMethod("elongate", {"x=0", "y=0", "z=0"}, [](const ShapeP &s, const Args &a) {
    needFinite(*s, "elongate()");
    V3 h{num(a["x"], "x"), num(a["y"], "y"), num(a["z"], "z")};
    if (h[0] < 0 || h[1] < 0 || h[2] < 0) throw ScriptError("elongate() não aceita valores negativos");
    return mkShape("elongate", {{"h", nums({h[0] / 2, h[1] / 2, h[2] / 2})}}, {s});
  });
  addMethod("color", {"c"}, [](const ShapeP &s, const Args &a) { return materialKV(s, "color", a["c"]); });
  addMethod("material", {"color=None", "rough=None", "metal=None", "glow=None", "coat=None"},
            [](const ShapeP &s, const Args &a) { return material(s, a); });
  addMethod("name", {"label"}, [](const ShapeP &s, const Args &a) { return mkShape("label", {{"name", str(a["label"])}}, {s}); });
  addMethod("facets", {"size=0.05", "vary=0.1"}, [](const ShapeP &s, const Args &a) {
    double sz = num(a["size"], "size"), vary = num(a["vary"], "vary");
    if (!(sz > 0) || sz >= 16)
      throw ScriptError("facets(): size deve ser maior que zero (em metros, menor que 16)", 0, "facets(0.04) dá facetas de uns 4 cm");
    if (vary < 0 || vary > 0.5) throw ScriptError("facets(): vary vai de 0 a 0.5", 0, "vary=0.1 varia o tom de cada faceta em 10%");
    return materialKV(s, "facet", rec({{"size", sz}, {"vary", vary}}));
  });
  addMethod("paint", {"region", "blend=0.005", "relief=0"}, [](const ShapeP &s, const Args &a) {
    Boxed region = asShape(a["region"], "paint()");
    double relief = num(a["relief"], "relief");
    double k = std::max(num(a["blend"], "blend"), 1.5 * std::fabs(relief));
    if (k < 0) throw ScriptError("paint(): blend não pode ser negativo");
    if (std::fabs(relief) > 0.2) throw ScriptError("paint(): relief vai de -0.2 a 0.2 metros", 0, "para peças maiores, some uma forma de verdade");
    return mkShape("paint", {{"k", k}, {"relief", relief}}, {s, region.shape});
  });
  addMethod("bind", {"bone"}, [](const ShapeP &s, const Args &a) -> Value {
    Value isBone;
    if (a["bone"].isObj()) try { isBone = a["bone"].obj()->attr("__bone__"); } catch (const ScriptError &) {}
    if (!truthy(isBone))
      throw ScriptError("bind() espera um osso", 0, "crie com esq = skeleton(); osso = esq.bone(\"nome\", head=(x, y, z))");
    return mkShape("bound", {{"bone", a["bone"]}}, {s});
  });
  addMethod("texture", {"kind", "color2=None", "size=None", "axis=\"y\"", "bump=0", "triplanar=False", "range=None"}, [](const ShapeP &s, const Args &a) {
    std::string kname = jsLower(str(a["kind"]));
    int kind = 0;
    for (auto &[k, v] : TEXTURES)
      if (k == kname) kind = v;
    if (!kind) {
      std::vector<std::string> names;
      for (auto &[k, v] : TEXTURES) names.push_back(k);
      std::string h = didYouMean(str(a["kind"]), names);
      throw ScriptError("textura desconhecida '" + str(a["kind"]) + "'", 0,
                        h.empty() ? "use noise, wood, marble, stripes, checker, bricks, gradient, mottle, relief" : h);
    }
    std::string axs = jsLower(str(a["axis"]));
    int axis = axs == "x" ? 0 : axs == "y" ? 1 : axs == "z" ? 2 : -1;
    if (axis < 0) throw ScriptError("eixo inválido '" + str(a["axis"]) + "'", 0, "use \"x\", \"y\" ou \"z\"");
    Value sz = a["size"].isNone() ? Value() : Value(num(a["size"], "size"));
    if (!sz.isNone() && sz.n() <= 0) throw ScriptError("size da textura deve ser maior que zero");
    double bump = num(a["bump"], "bump");
    if (bump < 0) throw ScriptError("bump deve ser 0 ou maior", 0, "bump=0.3 já dá um relevo bem visível");
    double off = 0;
    if (kind == 7) {
      needFinite(*s, "texture(\"gradient\")");
      double lo = s->bbox().min[axis], hi = s->bbox().max[axis];
      if (!a["range"].isNone()) { auto r = vec2(a["range"], "range"); lo = r[0]; hi = r[1]; }
      else if (!sz.isNone()) hi = lo + sz.n();
      if (!(hi > lo)) throw ScriptError("o degradê precisa de extensão positiva", 0, "use range=(de, até) com até > de");
      off = lo;
      sz = hi - lo;
    }
    Value tex = rec({{"kind", kind}, {"c2", a["color2"].isNone() ? Value() : colorValue(parseColor(a["color2"]))}, {"size", sz},
                     {"axis", truthy(a["triplanar"]) ? 3 : axis}, {"bump", bump}, {"off", off}, {"offAxis", axis}});
    return materialKV(s, "tex", tex);
  });
  addMethod("displace", {"amount=0.05", "size=0.3"}, [](const ShapeP &s, const Args &a) {
    double amt = num(a["amount"], "amount"), sz = num(a["size"], "size");
    if (sz <= 0) throw ScriptError("size deve ser maior que zero");
    return mkShape("displace", {{"amt", amt}, {"size", sz}}, {s});
  });
  addMethod("union", {"*others", "smooth=0"}, [](const ShapeP &s, const Args &a) {
    auto l = flatten(a["others"].list()->items, "union()");
    l.insert(l.begin(), s);
    return unionOf(l, num(a["smooth"], "smooth"));
  });
  addMethod("merge", {"*others", "r=0.03", "profile=\"round\"", "colors=\"sharp\"", "seam=None", "seam_width=None"}, [](const ShapeP &s, const Args &a) {
    auto l = flatten(a["others"].list()->items, "merge()");
    l.insert(l.begin(), s);
    return mergeShapes(l, a);
  });
  addMethod("subtract", {"*others", "smooth=0"}, [](const ShapeP &s, const Args &a) {
    return subtractOf(s, flatten(a["others"].list()->items, "subtract()"), a["smooth"]);
  });
  addMethod("intersect", {"*others", "smooth=0"}, [](const ShapeP &s, const Args &a) {
    auto l = flatten(a["others"].list()->items, "intersect()");
    l.insert(l.begin(), s);
    return intersectOf(l, a["smooth"]);
  });
}

static const std::vector<std::pair<std::string, std::function<Value(const BBox &)>>> &bboxProps() {
  static const std::vector<std::pair<std::string, std::function<Value(const BBox &)>>> P = {
      {"top", [](const BBox &b) { return Value(b.max[1]); }}, {"bottom", [](const BBox &b) { return Value(b.min[1]); }},
      {"left", [](const BBox &b) { return Value(b.min[0]); }}, {"right", [](const BBox &b) { return Value(b.max[0]); }},
      {"back", [](const BBox &b) { return Value(b.min[2]); }}, {"front", [](const BBox &b) { return Value(b.max[2]); }},
      {"width", [](const BBox &b) { return Value(size(b)[0]); }}, {"height", [](const BBox &b) { return Value(size(b)[1]); }},
      {"depth", [](const BBox &b) { return Value(size(b)[2]); }}, {"size", [](const BBox &b) { return tuple3(size(b)); }},
      {"center", [](const BBox &b) { return tuple3(center(b)); }}, {"x", [](const BBox &b) { return Value(center(b)[0]); }},
      {"y", [](const BBox &b) { return Value(center(b)[1]); }}, {"z", [](const BBox &b) { return Value(center(b)[2]); }},
  };
  return P;
}

static void ensureMethods() {
  static bool done = false;
  if (!done) { done = true; registerCoreMethods(); }
}

Value getShapeAttr(const ShapeP &s, const std::string &name) {
  ensureMethods();
  for (auto &[k, f] : bboxProps())
    if (k == name) return f(s->bbox());
  for (auto &[k, f] : shapeAttrs())
    if (k == name) return f(s);
  for (auto &[k, d] : shapeMethods())
    if (k == name) {
      ShapeMethod fn = d.fn;
      return native(name, d.params, [s, fn](const Args &a, const Node *) { return fn(s, a); });
    }
  std::vector<std::string> names;
  std::string all;
  for (auto &[k, d] : shapeMethods()) { names.push_back(k); all += (all.empty() ? "" : ", ") + k; }
  for (auto &[k, f] : bboxProps()) names.push_back(k);
  for (auto &[k, f] : shapeAttrs()) names.push_back(k);
  std::string h = didYouMean(name, names);
  throw ScriptError("forma não tem o método/atributo '" + name + "'", 0, h.empty() ? "métodos: " + all : h);
}

Value callMethod(const std::string &name, const ShapeP &s, const Args &a) {
  ensureMethods();
  for (auto &[k, d] : shapeMethods())
    if (k == name) return d.fn(s, a);
  throw std::runtime_error("método desconhecido " + name);
}

Value shapeBinary(const std::string &op, const Value &a, const Value &b) {
  if (a.isShape() && b.isShape()) {
    if (op == "+" || op == "|") return unionOf({a.shape(), b.shape()});
    if (op == "-") return subtractOf(a.shape(), {b.shape()});
    if (op == "&") return intersectOf({a.shape(), b.shape()});
  }
  throw ScriptError("operação '" + op + "' não suportada entre " + typeName(a) + " e " + typeName(b), 0,
                    "formas aceitam a + b (união), a - b (subtração) e a & b (interseção); para mover use .at(x, y, z)");
}

// ---------- funções globais ----------

static double positive(const Value &v, const std::string &what) {
  double x = num(v, what);
  if (x <= 0) throw ScriptError(what + " deve ser maior que zero");
  return x;
}

static int sidesOf(const Value &v, const std::string &what) {
  if (v.isNone()) return 0;
  double n = num(v, "sides");
  if (!isInt(n) || n < 3 || n > 64)
    throw ScriptError(what + ": sides deve ser um inteiro de 3 a 64", 0, "sides=6 dá um prisma hexagonal; None (padrão) deixa a forma lisa");
  return (int)n;
}

static double smoothArg(const Value &v, const std::string &what) {
  double x = num(v, "smooth");
  if (x < 0 || x > 180) throw ScriptError(what + ": smooth é um ângulo de 0 a 180 graus", 0, "smooth=40 suaviza curvas e mantém quinas vivas");
  return x;
}

static ShapeP extrudeShape(const std::vector<P2> &pts, double h, const std::string &axis, double round, const std::string &what) {
  if (axis != "z" && axis != "y") throw ScriptError(what + ": axis deve ser \"z\" (perfil em x,y) ou \"y\" (perfil em x,z)");
  if (round < 0) throw ScriptError(what + ": round não pode ser negativo");
  return mkShape("extrude", {{"pts", pointsValue(pts)}, {"h", h}, {"axis", axis}, {"r", std::min(round, h / 2)}});
}

Builtins shapeBuiltins(Scene &scene) {
  ensureMethods();
  Builtins b;
  auto N = [&](const char *name, std::initializer_list<const char *> params, std::function<Value(const Args &)> fn) {
    b.emplace_back(name, native(name, params, [fn](const Args &a, const Node *) { return fn(a); }));
  };
  N("box", {"w=1", "h=None", "d=None", "round=0", "bevel=0"}, [](const Args &a) {
    double w = positive(a["w"], "w");
    V3 s3{w, a["h"].isNone() ? w : positive(a["h"], "h"), a["d"].isNone() ? w : positive(a["d"], "d")};
    double mn = std::min({s3[0], s3[1], s3[2]});
    double r = std::min(num(a["round"], "round"), mn / 2);
    double bevel = num(a["bevel"], "bevel");
    if (bevel < 0) throw ScriptError("box(): bevel não pode ser negativo");
    if (bevel > 0) return mkShape("cbox", {{"size", nums3(s3)}, {"c", std::min(bevel, mn / 2)}, {"r", r}});
    return mkShape("box", {{"size", nums3(s3)}, {"r", r}});
  });
  N("cube", {"size=1", "round=0"}, [](const Args &a) {
    double s = positive(a["size"], "size");
    return mkShape("box", {{"size", nums({s, s, s})}, {"r", std::min(num(a["round"], "round"), s / 2)}});
  });
  N("sphere", {"r=0.5", "sides=None", "smooth=0"}, [](const Args &a) {
    double r = positive(a["r"], "r");
    int n = sidesOf(a["sides"], "sphere()");
    return n ? hullShape(lowSphere(r, n), "sphere()", 0, smoothArg(a["smooth"], "sphere()")) : mkShape("sphere", {{"r", r}});
  });
  N("cylinder", {"r=0.5", "h=1", "round=0", "sides=None", "smooth=0"}, [](const Args &a) {
    double r = positive(a["r"], "r"), h = positive(a["h"], "h");
    int n = sidesOf(a["sides"], "cylinder()");
    if (n) {
      auto pts = ringPoints(r, -h / 2, n);
      for (auto &p : ringPoints(r, h / 2, n)) pts.push_back(p);
      return hullShape(pts, "cylinder()", 0, smoothArg(a["smooth"], "cylinder()"));
    }
    return mkShape("cylinder", {{"r", r}, {"h", h}, {"round", std::min({num(a["round"], "round"), r, h / 2})}});
  });
  N("cone", {"r=0.5", "h=1", "top=0", "sides=None", "smooth=0"}, [](const Args &a) {
    double r = positive(a["r"], "r"), h = positive(a["h"], "h"), top = num(a["top"], "top");
    int n = sidesOf(a["sides"], "cone()");
    if (n) {
      auto pts = ringPoints(r, -h / 2, n);
      if (top > 1e-9) for (auto &p : ringPoints(top, h / 2, n)) pts.push_back(p);
      else pts.push_back({0, h / 2, 0});
      return hullShape(pts, "cone()", 0, smoothArg(a["smooth"], "cone()"));
    }
    return mkShape("cone", {{"r", r}, {"h", h}, {"top", top}});
  });
  N("hull", {"points", "bevel=0", "smooth=0"}, [](const Args &a) {
    const Value &P0 = a["points"];
    if (!P0.isList() || P0.size() < 4 || P0.size() > 64) throw ScriptError("hull(): points deve ser uma lista de 4 a 64 pontos (x, y, z)");
    std::vector<V3> pts;
    for (size_t i = 0; i < P0.size(); i++) pts.push_back(vec3(P0[i], "points[" + std::to_string(i) + "]"));
    double bevel = num(a["bevel"], "bevel");
    if (bevel < 0) throw ScriptError("hull(): bevel não pode ser negativo");
    return hullShape(pts, "hull()", bevel, smoothArg(a["smooth"], "hull()"));
  });
  N("loft", {"points", "r=0.1", "sides=8", "smooth=45", "caps=True"}, [](const Args &a) {
    const Value &P0 = a["points"];
    if (!P0.isList() || P0.size() < 2 || P0.size() > 32) throw ScriptError("loft(): points deve ser uma lista de 2 a 32 pontos (x, y, z)");
    std::vector<V3> path;
    for (size_t i = 0; i < P0.size(); i++) path.push_back(vec3(P0[i], "points[" + std::to_string(i) + "]"));
    auto one = [](const Value &v) -> std::array<double, 2> {
      if (v.isList() && v.size() == 2) return {num(v[0], "r"), num(v[1], "r")};
      double x = num(v, "r");
      return {x, x};
    };
    const Value &r = a["r"];
    std::vector<std::array<double, 2>> radii;
    bool allNum = r.isList() && std::all_of(r.list()->items.begin(), r.list()->items.end(), [](const Value &v) { return v.isNum(); });
    if (r.isList() && r.size() == path.size() && !(path.size() == 2 && allNum)) for (auto &v : r.list()->items) radii.push_back(one(v));
    else if (r.isList() && r.size() == 2 && allNum)
      for (size_t i = 0; i < path.size(); i++) {
        double t = double(i) / (path.size() - 1), x = r[0].n() + (r[1].n() - r[0].n()) * t;
        radii.push_back({x, x});
      }
    else for (size_t i = 0; i < path.size(); i++) radii.push_back(one(r));
    for (auto &q : radii)
      if (q[0] < 0 || q[1] < 0) throw ScriptError("loft(): os raios não podem ser negativos");
    int n = sidesOf(a["sides"], "loft()");
    return loftShape(path, radii, n, smoothArg(a["smooth"], "loft()"), truthy(a["caps"]));
  });
  N("torus", {"radius=0.5", "thickness=0.1"}, [](const Args &a) {
    return mkShape("torus", {{"R", positive(a["radius"], "radius")}, {"r", positive(a["thickness"], "thickness")}});
  });
  N("capsule", {"r=0.25", "h=1"}, [](const Args &a) {
    double r = positive(a["r"], "r");
    return mkShape("capsule", {{"r", r}, {"h", std::max(positive(a["h"], "h"), 2 * r)}});
  });
  N("ellipsoid", {"x=0.5", "y=0.3", "z=0.5"}, [](const Args &a) {
    return mkShape("ellipsoid", {{"radii", nums({positive(a["x"], "x"), positive(a["y"], "y"), positive(a["z"], "z")})}});
  });
  N("pyramid", {"w=1", "h=1"}, [](const Args &a) { return mkShape("pyramid", {{"w", positive(a["w"], "w")}, {"h", positive(a["h"], "h")}}); });
  N("prism", {"w=1", "h=0.5", "d=1"}, [](const Args &a) {
    return mkShape("prism", {{"w", positive(a["w"], "w")}, {"h", positive(a["h"], "h")}, {"d", positive(a["d"], "d")}});
  });
  N("plane", {}, [](const Args &) { return mkShape("plane"); });
  N("extrude", {"points", "h=1", "axis=\"z\"", "round=0"}, [](const Args &a) {
    auto pts = parsePoints(a["points"], "extrude()");
    return extrudeShape(pts, positive(a["h"], "h"), jsLower(str(a["axis"])), num(a["round"], "round"), "extrude()");
  });
  N("polygon", {"sides=6", "r=0.5", "h=1", "round=0"}, [](const Args &a) {
    double n = num(a["sides"], "sides");
    if (!isInt(n) || n < 3 || n > 64) throw ScriptError("polygon(): sides deve ser um inteiro de 3 a 64");
    return extrudeShape(regularPolygon((int)n, positive(a["r"], "r")), positive(a["h"], "h"), "y", num(a["round"], "round"), "polygon()");
  });
  N("star", {"points=5", "r=0.5", "inner=None", "h=0.2", "round=0"}, [](const Args &a) {
    double n = num(a["points"], "points");
    if (!isInt(n) || n < 3 || n > 32) throw ScriptError("star(): points deve ser um inteiro de 3 a 32");
    double r = positive(a["r"], "r");
    double inner = a["inner"].isNone() ? r * 0.45 : positive(a["inner"], "inner");
    return extrudeShape(starPoints((int)n, r, inner), positive(a["h"], "h"), "y", num(a["round"], "round"), "star()");
  });
  N("wedge", {"w=1", "h=1", "d=1"}, [](const Args &a) {
    double w = positive(a["w"], "w"), h = positive(a["h"], "h");
    return extrudeShape({{-w / 2, -h / 2}, {w / 2, -h / 2}, {w / 2, h / 2}}, positive(a["d"], "d"), "z", 0, "wedge()");
  });
  N("lathe", {"profile", "smooth=0"}, [](const Args &a) {
    auto prof = parsePoints(a["profile"], "lathe()", 2, 64);
    for (auto &p : prof)
      if (p[0] < 0)
        throw ScriptError("lathe(): o raio (primeiro valor de cada ponto) não pode ser negativo", 0, "perfil de (raio, altura), de baixo para cima");
    double sm = num(a["smooth"], "smooth");
    if (!isInt(sm) || sm < 0 || sm > 8) throw ScriptError("lathe(): smooth deve ser um inteiro de 0 a 8", 0, "smooth=4 arredonda o perfil");
    prof = smoothOpen(prof, (int)sm);
    for (auto &p : prof) p[0] = std::max(0.0, p[0]);
    auto pts = lathePolygon(prof);
    if (pts.size() > 128) throw ScriptError("lathe(): perfil com pontos demais depois de suavizar", 0, "use menos pontos ou um smooth menor");
    Bounds2 bb = boundsOf(prof);
    if (!(bb.maxX > 0)) throw ScriptError("lathe(): o perfil precisa ter algum raio maior que zero");
    return mkShape("lathe", {{"pts", pointsValue(pts)}, {"profile", pointsValue(prof)}, {"rmax", bb.maxX}, {"y0", bb.minY}, {"y1", bb.maxY}});
  });
  N("hemisphere", {"r=0.5"}, [](const Args &a) {
    double r = positive(a["r"], "r");
    auto cap = intersectOf({mkShape("sphere", {{"r", r}}), translate(mkShape("box", {{"size", nums({2 * r + 0.01, r, 2 * r + 0.01})}, {"r", 0}}), V3{0, r / 2, 0})});
    return translate(cap, V3{0, -r / 2, 0});
  });
  N("tube", {"r=0.5", "thickness=0.1", "h=1"}, [](const Args &a) {
    double r = positive(a["r"], "r"), t = positive(a["thickness"], "thickness"), h = positive(a["h"], "h");
    if (t >= r) throw ScriptError("tube(): thickness deve ser menor que r");
    return subtractOf(mkShape("cylinder", {{"r", r}, {"h", h}, {"round", 0}}), {mkShape("cylinder", {{"r", r - t}, {"h", h + 0.02}, {"round", 0}})});
  });
  N("segment", {"a", "b", "r=0.05", "r2=None"}, [](const Args &a) {
    V3 p0 = vec3(a["a"], "a"), p1 = vec3(a["b"], "b");
    double r = positive(a["r"], "r");
    if (a["r2"].isNone()) return segmentShape(p0, p1, r);
    return roundCone(p0, p1, r, positive(a["r2"], "r2"));
  });
  N("chain", {"points", "r=0.05", "smooth=0", "curve=0"}, [](const Args &a) {
    const Value &P0 = a["points"];
    if (!P0.isList() || P0.size() < 2 || P0.size() > 64) throw ScriptError("chain(): points deve ser uma lista de 2 a 64 pontos (x, y, z)");
    std::vector<V3> pts;
    for (size_t i = 0; i < P0.size(); i++) pts.push_back(vec3(P0[i], "points[" + std::to_string(i) + "]"));
    size_t n = pts.size();
    std::vector<double> radii;
    const Value &r = a["r"];
    if (r.isList() && r.size() == n && n != 2) for (auto &v : r.list()->items) radii.push_back(positive(v, "r"));
    else if (r.isList() && r.size() == 2) {
      double r0 = positive(r[0], "r"), r1 = positive(r[1], "r");
      for (size_t i = 0; i < n; i++) radii.push_back(r0 + ((r1 - r0) * i) / (n - 1));
    } else if (r.isList()) throw ScriptError("chain(): r deve ser um número, (início, fim) ou um raio por ponto");
    else for (size_t i = 0; i < n; i++) radii.push_back(positive(r, "r"));
    double sub = num(a["curve"], "curve");
    if (!isInt(sub) || sub < 0 || sub > 8) throw ScriptError("chain(): curve deve ser um inteiro de 0 a 8", 0, "curve=3 arredonda a curva entre os pontos");
    std::vector<V3> P = pts;
    std::vector<double> R = radii;
    if (sub) { P.clear(); R.clear(); catmull(pts, radii, (int)sub + 1, P, R); }
    std::vector<ShapeP> segs;
    for (size_t i = 0; i + 1 < P.size(); i++) segs.push_back(roundCone(P[i], P[i + 1], R[i], R[i + 1]));
    return unionOf(segs, num(a["smooth"], "smooth"));
  });
  N("merge", {"*shapes", "r=0.03", "profile=\"round\"", "colors=\"sharp\"", "seam=None", "seam_width=None"},
    [](const Args &a) { return mergeShapes(flatten(a["shapes"].list()->items, "merge()"), a); });
  N("group", {"*shapes", "smooth=0"}, [](const Args &a) {
    auto l = flatten(a["shapes"].list()->items, "group()");
    if (l.empty()) throw ScriptError("group() vazio");
    return unionOf(l, num(a["smooth"], "smooth"));
  });
  N("union", {"*shapes", "smooth=0"}, [](const Args &a) {
    auto l = flatten(a["shapes"].list()->items, "union()");
    if (l.empty()) throw ScriptError("union() vazio");
    return unionOf(l, num(a["smooth"], "smooth"));
  });
  N("subtract", {"base", "*cutters", "smooth=0"}, [](const Args &a) {
    Boxed base = asShape(a["base"], "subtract()");
    return subtractOf(base.shape, flatten(a["cutters"].list()->items, "subtract()"), a["smooth"]);
  });
  N("intersect", {"*shapes", "smooth=0"}, [](const Args &a) {
    auto l = flatten(a["shapes"].list()->items, "intersect()");
    if (l.empty()) throw ScriptError("intersect() vazio");
    return intersectOf(l, a["smooth"]);
  });
  Scene *sc = &scene;
  N("show", {"*shapes"}, [sc](const Args &a) {
    for (auto &s : flatten(a["shapes"].list()->items, "show()")) sc->shapes.push_back(s);
    return Value();
  });
  N("camera", {"pos", "look=None", "fov=45"}, [sc](const Args &a) {
    sc->camera = rec({{"pos", nums3(vec3(a["pos"], "pos"))}, {"look", a["look"].isNone() ? Value() : nums3(vec3(a["look"], "look"))}, {"fov", num(a["fov"], "fov")}});
    return Value();
  });
  N("sun", {"x=0.6", "y=1", "z=0.4", "color=None"}, [sc](const Args &a) {
    sc->sun = rec({{"dir", nums({num(a["x"], "x"), num(a["y"], "y"), num(a["z"], "z")})}, {"color", a["color"].isNone() ? Value() : colorValue(parseColor(a["color"]))}});
    return Value();
  });
  N("sky", {"color"}, [sc](const Args &a) { sc->sky = colorValue(parseColor(a["color"])); return Value(); });
  N("fog", {"density=0.02"}, [sc](const Args &a) { sc->fog = num(a["density"], "fog"); return Value(); });
  N("light", {"rim=0.6", "fill=0.4", "ao=1", "rim_color=None"}, [sc](const Args &a) {
    double v[3] = {num(a["rim"], "rim"), num(a["fill"], "fill"), num(a["ao"], "ao")};
    for (double x : v)
      if (x < 0 || x > 4) throw ScriptError("light(): rim, fill e ao vão de 0 a 4");
    sc->light = rec({{"rim", v[0]}, {"fill", v[1]}, {"ao", v[2]}, {"rimColor", a["rim_color"].isNone() ? nums({1, 1, 1}) : colorValue(parseColor(a["rim_color"]))}});
    return Value();
  });
  return b;
}

std::vector<Part> collectParts(const std::vector<ShapeP> &shapes) {
  std::vector<Part> parts;
  std::function<void(const Shape &, const M3 &, const V3 &)> visit = [&](const Shape &s, const M3 &m, const V3 &t) {
    if (s.kind == "translate") { visit(*s.children[0], m, add(t, mulMV(m, s.props.v3("v")))); return; }
    if (s.kind == "rotate") { visit(*s.children[0], mul3(m, s.props.m3("m")), t); return; }
    if (s.kind == "scale") {
      V3 sv = s.props.v3("s");
      visit(*s.children[0], mul3(m, {sv[0], 0, 0, 0, sv[1], 0, 0, 0, sv[2]}), t);
      return;
    }
    if (s.kind == "label") parts.push_back({s.props["name"].s(), isFiniteBB(s.bbox()) ? transformedBBox(s, m, t) : s.bbox()});
    for (auto &c : s.children) visit(*c, m, t);
  };
  for (auto &s : shapes) visit(*s, IDENT, {0, 0, 0});
  return parts;
}

}  // namespace tdi
