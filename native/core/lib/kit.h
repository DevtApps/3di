// Kit de formas para os geradores (port de lib/kit.js, lib/util.js, lib/style.js e lib/rand.js).
// ATENÇÃO à ordem do aleatório: em C++ a ordem de avaliação dos argumentos de uma chamada não é
// garantida. Cada u() que aparece junto com outro numa mesma chamada/expressão vai antes para uma
// variável (ou para uma lista entre chaves, que é avaliada da esquerda para a direita).
#pragma once
#include <cmath>
#include <optional>

#include "../color.h"
#include "../expr.h"
#include "../interp.h"

namespace tdi::kit {

using C3 = std::array<double, 3>;

inline Args args(std::initializer_list<std::pair<const char *, Value>> l) {
  Args a;
  for (auto &[k, v] : l) a.set(k, v);
  return a;
}
inline ShapeP M(const char *name, const ShapeP &s, const Args &a) { return callMethod(name, s, a).shape(); }
inline Value col(const C3 &c) { return nums({c[0], c[1], c[2]}); }

// ---------- primitivas ----------
inline ShapeP box(double w, double h, double d, double round = 0) {
  return mkShape("box", {{"size", nums({w, h, d})}, {"r", std::min(round, std::min({w, h, d}) / 2)}});
}
inline ShapeP box(double w) { return box(w, w, w); }
inline ShapeP sphere(double r) { return mkShape("sphere", {{"r", r}}); }
inline ShapeP cyl(double r, double h, double round = 0) { return mkShape("cylinder", {{"r", r}, {"h", h}, {"round", std::min({round, r, h / 2})}}); }
inline ShapeP cone(double r, double h, double top = 0) { return mkShape("cone", {{"r", r}, {"h", h}, {"top", top}}); }
inline ShapeP pyramid(double w, double h) { return mkShape("pyramid", {{"w", w}, {"h", h}}); }
inline ShapeP prism(double w, double h, double d) { return mkShape("prism", {{"w", w}, {"h", h}, {"d", d}}); }
inline ShapeP ellipsoid(double x, double y, double z) { return mkShape("ellipsoid", {{"radii", nums({x, y, z})}}); }
inline ShapeP capsule(double r, double h) { return mkShape("capsule", {{"r", r}, {"h", std::max(h, 2 * r)}}); }
inline ShapeP torus(double R, double r) { return mkShape("torus", {{"R", R}, {"r", r}}); }
inline ShapeP plane() { return mkShape("plane"); }
inline ShapeP segment(const V3 &a, const V3 &b, double r) { return segmentShape(a, b, r); }

// ---------- transformações ----------
inline ShapeP at(const ShapeP &s, Value x = 0.0, Value y = 0.0, Value z = 0.0) { return M("at", s, args({{"x", x}, {"y", y}, {"z", z}})); }
inline ShapeP move(const ShapeP &s, const V3 &v) { return at(s, v[0], v[1], v[2]); }
inline ShapeP rot(const ShapeP &s, Value x = 0.0, Value y = 0.0, Value z = 0.0, std::optional<V3> pivot = std::nullopt) {
  return M("rotate", s, args({{"x", x}, {"y", y}, {"z", z}, {"pivot", pivot ? nums3(*pivot) : Value()}}));
}
inline const V3 O{0, 0, 0};  // pivô na origem
inline ShapeP scale(const ShapeP &s, const V3 &f, std::optional<V3> pivot = std::nullopt) {
  return M("scale", s, args({{"s", nums3(f)}, {"pivot", pivot ? nums3(*pivot) : Value()}}));
}
inline ShapeP scale(const ShapeP &s, double f, std::optional<V3> pivot = std::nullopt) {
  return M("scale", s, args({{"s", f}, {"pivot", pivot ? nums3(*pivot) : Value()}}));
}
inline ShapeP ground(const ShapeP &s) { return M("ground", s, {}); }
inline ShapeP mirror(const ShapeP &s, const char *axes = "x") { return M("mirror", s, args({{"axes", axes}})); }
inline ShapeP repeat(const ShapeP &s, double x, double y, double z, Value spacing = Value()) {
  return M("repeat", s, args({{"x", x}, {"y", y}, {"z", z}, {"spacing", spacing}}));
}
inline ShapeP displace(const ShapeP &s, double amount, double size) { return M("displace", s, args({{"amount", amount}, {"size", size}})); }

// ---------- materiais ----------
inline ShapeP color(const ShapeP &s, const Value &c) { return M("color", s, args({{"c", c}})); }
inline ShapeP color(const ShapeP &s, const C3 &c) { return color(s, col(c)); }
struct Mat {
  Value color, rough, metal, glow;
};
inline ShapeP material(const ShapeP &s, const Mat &m) {
  return M("material", s, args({{"color", m.color}, {"rough", m.rough}, {"metal", m.metal}, {"glow", m.glow}, {"coat", Value()}}));
}
struct Tex {
  Value color2, size;
  const char *axis = "y";
  double bump = 0;
  bool triplanar = false;
  Value range;
};
inline ShapeP texture(const ShapeP &s, const char *kind, const Tex &t = {}) {
  return M("texture", s, args({{"kind", kind}, {"color2", t.color2}, {"size", t.size}, {"axis", t.axis}, {"bump", t.bump}, {"triplanar", t.triplanar}, {"range", t.range}}));
}
inline ShapeP named(const ShapeP &s, const std::string &label) { return M("name", s, args({{"label", label}})); }

// ---------- combinar ----------
inline ShapeP group(const std::vector<ShapeP> &list, double smooth = 0) {
  std::vector<ShapeP> l;
  for (auto &s : list) if (s) l.push_back(s);
  return unionOf(l, smooth);
}
inline ShapeP subtract(const ShapeP &a, const std::vector<ShapeP> &cutters, double smooth = 0) {
  return mkShape("subtract", {{"k", smooth}}, {a, unionOf(cutters)});
}
inline ShapeP intersect(const ShapeP &a, const ShapeP &b) { return shapeBinary("&", a, b).shape(); }

// ---------- geometria ----------
inline V3 tipOf(double len, double ax = 0, double ay = 0, double az = 0) { return mulMV(rotMatrix(ax, ay, az), {0, len, 0}); }
inline ShapeP taper(const V3 &from, const V3 &to, double r0, double r1) {
  V3 d{to[0] - from[0], to[1] - from[1], to[2] - from[2]};
  double len = std::sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
  auto body = cone(r0, std::max(len, 1e-4), r1);
  double L = len ? len : 1;
  V3 n{d[0] / L, d[1] / L, d[2] / L};
  double ax = std::asin(std::max(-1.0, std::min(1.0, n[2]))) * 180 / M_PI;
  double az = std::atan2(-n[0], n[1]) * 180 / M_PI;
  auto rotated = rot(body, ax, 0.0, az, O);
  return at(rotated, from[0] + d[0] / 2, from[1] + d[1] / 2, from[2] + d[2] / 2);
}

// ---------- util.js ----------
inline double rad(double d) { return d * M_PI / 180; }
inline C3 mixc(const C3 &a, const C3 &b, double t) { return {a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t}; }
inline V3 addv(const V3 &a, const V3 &b) { return {a[0] + b[0], a[1] + b[1], a[2] + b[2]}; }
inline V3 scalev(const V3 &a, double k) { return {a[0] * k, a[1] * k, a[2] * k}; }

// aleatório de um gerador: u(a, b) uniforme, pick(lista), chance(p), int(a, b)
struct RT {
  RngFn rng;
  double u(double a = 0, double b = 1) const { return a + (b - a) * rng(); }
  template <class T> const T &pick(const std::vector<T> &xs) const { return xs[(size_t)std::floor(rng() * xs.size())]; }
  bool chance(double p) const { return rng() < p; }
  double integer(double a, double b) const { return a + std::floor((b - a + 1) * rng()); }
};
inline RT rngFor(Interp &it, const Value &seed) {
  if (seed.isNone()) return {[&it] { return it.rng(); }};
  auto r = std::make_shared<Rng>(std::floor(val0(seed)));
  return {[r] { return (*r)(); }};
}

inline C3 jitter(const C3 &c, const RT &R, double hue, double sat, double val) {
  auto hsv = rgbToHsv(c);
  double jh = (R.rng() * 2 - 1) * hue;
  double js = (R.rng() * 2 - 1) * sat;
  double jv = (R.rng() * 2 - 1) * val;
  return hsvToRgb(hsv[0] + jh, std::min(1.0, std::max(0.0, hsv[1] + js)), std::min(1.0, std::max(0.0, hsv[2] + jv)));
}
inline V3 dirVec(double yaw, double tilt) {
  double t = rad(tilt), y = rad(yaw);
  return {std::sin(t) * std::cos(y), std::cos(t), std::sin(t) * std::sin(y)};
}
struct Ribbon {
  ShapeP shape;
  V3 tip;
};
inline Ribbon ribbon(double len, double w, const std::vector<double> &tilts, double flat = 0.15) {
  size_t n = tilts.size();
  std::vector<ShapeP> parts;
  V3 pos{0, 0, 0};
  for (size_t k = 0; k < n; k++) {
    double l = len / n;
    double r0 = (w / 2) * (1 - (double(k) / n) * 0.85), r1 = (w / 2) * std::max(0.04, 1 - (double(k + 1) / n) * 0.97);
    auto piece = at(scale(cone(r0, l, r1), V3{1, 1, flat}), 0.0, l / 2, 0.0);
    piece = move(rot(piece, tilts[k], 0.0, 0.0, O), pos);
    parts.push_back(piece);
    pos = addv(pos, tipOf(l, tilts[k]));
  }
  return {group(parts), pos};
}
inline Ribbon placedRibbon(const V3 &atp, double yaw, double len, double w, const std::vector<double> &tilts, double flat = 0.15) {
  Ribbon r = ribbon(len, w, tilts, flat);
  return {move(rot(r.shape, 0.0, yaw, 0.0, O), atp), addv(mulMV(rotMatrix(0, yaw, 0), r.tip), atp)};
}

// ---------- style.js ----------
struct Style {
  std::string name;
  double detail, vary, bump, rough, round;
  bool facets, gradient, mottle;
};
Style resolveStyle(const Value &name, const std::string &what);
extern const std::vector<std::string> STYLE_NAMES;

inline ShapeP paintStyle(const ShapeP &shape, const Style &S, const C3 &base, const C3 &tip, double size = 0.2) {
  auto c = color(shape, base);
  if (S.mottle) return texture(c, "mottle", {col(tip), size, "y", S.bump * 0.6});
  if (S.gradient) return texture(c, "gradient", {col(tip)});
  return c;
}
inline ShapeP boxSeg(const V3 &from, const V3 &to, double w, std::optional<double> d0 = std::nullopt) {
  double d = d0 ? *d0 : w * 0.8;
  V3 v{to[0] - from[0], to[1] - from[1], to[2] - from[2]};
  double len = std::sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
  double L = len ? len : 1;
  V3 n{v[0] / L, v[1] / L, v[2] / L};
  double ax = std::asin(std::max(-1.0, std::min(1.0, n[2]))) * 180 / M_PI;
  double az = std::atan2(-n[0], n[1]) * 180 / M_PI;
  auto body = rot(box(w, std::max(len, 1e-4), d), ax, 0.0, az, O);
  return at(body, from[0] + v[0] / 2, from[1] + v[1] / 2, from[2] + v[2] / 2);
}
inline V3 limbDir(double alpha, double beta, double side) {
  double a = rad(alpha), b = rad(beta);
  return {side * std::sin(b), -std::cos(a) * std::cos(b), std::sin(a) * std::cos(b)};
}

}  // namespace tdi::kit
