// Gerador de plantas pequenas (port de lib/plants.js).
#include "kit.h"

namespace tdi::kit {

struct PlantKind {
  const char *name;
  double h;
  const char *color, *leaf;
};
static const PlantKind KINDS[] = {
    {"flower", 0.35, nullptr, "#2f7a2a"}, {"daisy", 0.3, "#fafaf2", "#3a8a30"}, {"lavender", 0.5, "#8a5cc8", "#5f8a4a"},
    {"fern", 0.5, "#2f8a3a", "#2f8a3a"},  {"bush", 0.9, "#3a7d2c", "#3a7d2c"},  {"cactus", 1.4, "#3f8f4a", "#3f8f4a"},
    {"mushroom", 0.18, "#c8382b", "#e8dcc2"},
};
static const std::vector<C3> PETALS = {{0.95, 0.4, 0.6}, {1, 0.85, 0.2}, {0.65, 0.4, 0.9}, {0.95, 0.3, 0.25}, {1, 0.6, 0.2}, {0.98, 0.98, 0.95}};

struct B_ {
  Style S;
  RT R;
  double H, density;
  C3 accent, leaf;
  double u(double a, double b) const { return R.u(a, b); }
};
template <class T> static T lvl(const Style &S, T a, T b, T c) { return S.name == "lowpoly" ? a : S.name == "stylized" ? b : c; }

static std::vector<V3> clump(int n, double radius, const B_ &B) {
  std::vector<V3> out{{0, 0, 0}};
  for (int i = 1; i < n; i++) {
    double a = rad(((i - 1) * 360.0) / std::max(1, n - 1) + B.u(-30, 30));
    double r = radius * B.u(0.7, 1.2);
    out.push_back({std::cos(a) * r, 0, std::sin(a) * r});
  }
  return out;
}

struct Stem {
  ShapeP shape;
  V3 top;
};
static Stem stem(const B_ &B, const V3 &atp, double h, double r) {
  int pieces = lvl(B.S, 1, 2, 2);
  std::vector<ShapeP> parts;
  V3 pos = atp;
  double yaw = B.u(0, 360);
  double bend = B.u(2, 9);
  for (int k = 0; k < pieces; k++) {
    V3 next = addv(pos, scalev(dirVec(yaw, bend * (k + 1)), h / pieces));
    parts.push_back(taper(pos, next, r * (1 - 0.3 * (double(k) / pieces)), r * (1 - 0.3 * (double(k + 1) / pieces))));
    pos = next;
  }
  return {color(group(parts), mixc(B.leaf, {0, 0.1, 0}, 0.15)), pos};
}

struct BloomO {
  double size, pl, pw, tilt, eye;
  int petals;  // 0: padrão do estilo
  C3 petal, center;
};

static std::vector<ShapeP> bloom(const B_ &B, const V3 &atp, const BloomO &o) {
  const Style &S = B.S;
  double H = B.H;
  double h = H * o.size * B.u(0.85, 1.1);
  Stem st = stem(B, atp, h, H * 0.018);
  std::vector<ShapeP> parts{st.shape};
  int n = o.petals ? o.petals : lvl(S, 5, 6, 8);
  double pl = H * o.pl * o.size, pw = H * o.pw * o.size;
  for (int i = 0; i < n; i++) {
    ShapeP p = S.facets ? scale(pyramid(pw * 2, pl * 2), V3{1, 1, 0.3}) : ellipsoid(pw, pl, pw * 0.3);
    p = S.facets ? ground(p) : at(p, 0.0, pl, 0.0);
    p = rot(p, o.tilt + B.u(-6, 6), 0.0, 0.0, O);
    double y = (i * 360.0) / n + B.u(-8, 8);
    p = move(rot(p, 0.0, y, 0.0, O), addv(st.top, {0, H * 0.012 * o.size, 0}));
    parts.push_back(paintStyle(p, S, mixc(o.petal, {1, 1, 1}, 0.05), mixc(o.petal, {1, 1, 0.9}, 0.25), pl));
  }
  V3 c = addv(st.top, {0, H * 0.02 * o.size, 0});
  parts.push_back(color(at(sphere(H * o.eye * o.size), c[0], c[1], c[2]), o.center));
  if (S.name != "lowpoly") {
    for (int l = 0; l < 2; l++) {
      V3 at2 = addv(atp, {0, h * (0.2 + 0.2 * l), 0});
      double yaw = l * 180 + B.u(-30, 30);
      Ribbon r = placedRibbon(at2, yaw, H * 0.35 * o.size, H * 0.09, {50, 90}, 0.12);
      parts.push_back(paintStyle(r.shape, S, B.leaf, mixc(B.leaf, {0.7, 1, 0.4}, 0.35), H * 0.2));
    }
  }
  return parts;
}

static std::vector<ShapeP> flowerLike(const B_ &B, const BloomO &o) {
  int n = std::max(1, std::min(6, (int)std::floor(B.density + 0.5)));
  int budget = std::max(1, (int)std::floor(70.0 / lvl(B.S, 8, 13, 17)));
  std::vector<ShapeP> out;
  for (auto &p : clump(std::min(n, budget), B.H * 0.45, B)) {
    auto b = bloom(B, p, o);
    out.insert(out.end(), b.begin(), b.end());
  }
  return out;
}

static std::vector<ShapeP> lavender(const B_ &B) {
  const Style &S = B.S;
  double H = B.H;
  int n = std::min(14, std::max(2, (int)std::floor(lvl(S, 3, 5, 8) * B.density + 0.5)));
  std::vector<ShapeP> parts;
  for (int i = 0; i < n; i++) {
    double ax = B.u(-0.12, 0.12) * H;
    double az = B.u(-0.12, 0.12) * H;
    V3 atp{ax, 0, az};
    double yaw = B.u(0, 360);
    double lean = B.u(4, 22);
    double h = H * B.u(0.75, 1);
    Ribbon r = placedRibbon(atp, yaw, h, H * 0.025, {lean, lean + 6}, 1);
    parts.push_back(color(r.shape, B.leaf));
    V3 dir = dirVec(yaw + 90, lean + 4);
    double spikeLen = H * B.u(0.2, 0.28);
    for (int k = 0; k < (S.name == "lowpoly" ? 1 : 2); k++) {
      V3 c = addv(r.tip, scalev(dir, spikeLen * (0.3 + k * 0.45)));
      auto e = rot(ellipsoid(H * 0.035, spikeLen * (k ? 0.32 : 0.4), H * 0.035), lean + 4, yaw + 90, 0.0);
      C3 base = jitter(B.accent, B.R, 8, S.vary, S.vary * 0.6);
      parts.push_back(paintStyle(move(e, c), S, base, mixc(B.accent, {1, 0.85, 1}, 0.35), spikeLen));
    }
  }
  return parts;
}

static std::vector<ShapeP> fern(const B_ &B) {
  const Style &S = B.S;
  double H = B.H;
  int n = std::min(20, (int)std::floor(lvl(S, 6, 9, 13) * B.density + 0.5));
  std::vector<ShapeP> parts;
  for (int i = 0; i < n; i++) {
    double yaw = (i * 360.0) / n + B.u(-14, 14);
    std::vector<double> tilts;
    if (S.name == "lowpoly") tilts = {32, 84};
    else {
      double t0 = 26 + B.u(-4, 6);
      double t2 = 86 + B.u(0, 12);
      tilts = {t0, 56, t2};
    }
    double len = H * B.u(0.85, 1.15);
    Ribbon r = placedRibbon({0, 0, 0}, yaw, len, H * 0.2, tilts, 0.1);
    C3 base = jitter(B.accent, B.R, 5, S.vary, S.vary * 0.6);
    parts.push_back(paintStyle(r.shape, S, base, mixc(B.accent, {0.7, 1, 0.45}, 0.4), H * 0.2));
  }
  return parts;
}

static std::vector<ShapeP> bush(const B_ &B) {
  const Style &S = B.S;
  double H = B.H;
  int n = std::min(14, (int)std::floor(lvl(S, 4, 6, 9) * B.density + 0.5));
  std::vector<ShapeP> parts;
  for (int i = 0; i < n; i++) {
    double a = rad((i * 360.0) / n + B.u(-20, 20));
    double d = H * 0.42 * (i == 0 ? 0 : B.u(0.6, 1));
    double r = H * B.u(0.26, 0.4) * (i == 0 ? 1.15 : 1);
    ShapeP s;
    if (S.facets) {
      double rx = B.u(-15, 15);
      double ry = B.u(0, 90);
      double rz = B.u(-15, 15);
      s = rot(box(r * 1.5, r * 1.3, r * 1.5), rx, ry, rz);
    } else s = scale(sphere(r), V3{1, 0.85, 1});
    if (S.name == "realistic") s = displace(s, r * 0.25, r * 0.7);
    C3 base = jitter(B.accent, B.R, 6, S.vary, S.vary * 0.8);
    parts.push_back(move(paintStyle(s, S, base, mixc(base, {0.75, 1, 0.45}, 0.4), r), {std::cos(a) * d, r * 0.82, std::sin(a) * d}));
  }
  return parts;
}

static std::vector<ShapeP> cactus(const B_ &B) {
  const Style &S = B.S;
  double H = B.H;
  double r = H * 0.1, armR = H * 0.07;
  auto paint = [&](const ShapeP &s) {
    auto c = color(s, B.accent);
    if (S.name == "realistic") return texture(c, "relief", {Value(), H * 0.05, "y", S.bump});
    if (S.gradient) return texture(c, "gradient", {col(mixc(B.accent, {0.8, 1, 0.5}, 0.3))});
    return c;
  };
  std::vector<ShapeP> parts{paint(at(capsule(r, H), 0.0, H / 2, 0.0))};
  int arms = lvl(S, 1, 2, 2);
  for (int i = 0; i < arms; i++) {
    double side = i % 2 ? -1 : 1;
    double y = H * (0.42 + 0.14 * i) * B.u(0.92, 1.08);
    double reach = r + H * B.u(0.16, 0.22);
    parts.push_back(paint(segment({side * r * 0.4, y, 0}, {side * reach, y, 0}, armR)));
    double up = H * B.u(0.22, 0.32);
    parts.push_back(paint(segment({side * reach, y, 0}, {side * reach, y + up, 0}, armR)));
  }
  if (S.name == "realistic") parts.push_back(color(at(sphere(H * 0.035), 0.0, H * 1.01, 0.0), C3{0.95, 0.4, 0.55}));
  return parts;
}

static std::vector<ShapeP> mushroom(const B_ &B) {
  const Style &S = B.S;
  double H = B.H;
  int n = std::min(5, std::max(1, (int)std::floor(B.density * 1.5 + 0.5)));
  std::vector<ShapeP> parts;
  for (auto &p : clump(n, H * 0.9, B)) {
    double sz = H * B.u(0.6, 1.1);
    auto stemS = color(taper(p, addv(p, {0, sz * 0.8, 0}), sz * 0.14, sz * 0.1), B.leaf);
    double rx = sz * 0.48, ry = sz * 0.27;
    ShapeP cap = S.facets ? pyramid(sz * 0.75, sz * 0.4) : ellipsoid(rx, ry, rx);
    cap = S.facets ? at(cap, 0.0, sz * 0.2, 0.0) : cap;
    V3 top = addv(p, {0, sz * 0.85, 0});
    std::vector<ShapeP> parts2{color(cap, jitter(B.accent, B.R, 6, S.vary, S.vary * 0.6))};
    int spots = lvl(S, 0, 4, 6);
    for (int k = 0; k < spots; k++) {
      double th = rad(B.u(15, 62));
      double ph = rad(B.u(0, 360));
      V3 q{rx * std::sin(th) * std::cos(ph), ry * std::cos(th), rx * std::sin(th) * std::sin(ph)};
      auto spot = scale(sphere(sz * B.u(0.045, 0.07)), V3{1, 0.35, 1});
      parts2.push_back(color(move(spot, scalev(q, 1.02)), C3{0.97, 0.95, 0.9}));
    }
    parts.push_back(stemS);
    parts.push_back(move(group(parts2), top));
  }
  return parts;
}

Builtins plantBuiltins(Interp &it) {
  Interp *ip = &it;
  return {{"plant", native("plant", {"kind=\"flower\"", "style=\"stylized\"", "height=None", "color=None", "density=1", "seed=None"}, [ip](const Args &a, const Node *) -> Value {
    std::string kindName = jsLower(str(a["kind"]));
    const PlantKind *kind = nullptr;
    std::vector<std::string> names;
    for (auto &k : KINDS) { names.push_back(k.name); if (kindName == k.name) kind = &k; }
    if (!kind) {
      std::string h = didYouMean(kindName, names);
      throw ScriptError("plant(): tipo desconhecido '" + str(a["kind"]) + "'", 0, h.empty() ? "use flower, daisy, lavender, fern, bush, cactus, mushroom" : h);
    }
    Style S = resolveStyle(a["style"], "plant()");
    double H = a["height"].isNone() ? kind->h : num(a["height"], "height");
    if (!(H > 0)) throw ScriptError("plant(): height deve ser maior que zero");
    double density = num(a["density"], "density");
    if (!(density > 0)) throw ScriptError("plant(): density deve ser maior que zero", 0, "density=1 é uma planta; 3 é uma touceira");
    RT R = rngFor(*ip, a["seed"]);
    C3 accent = !a["color"].isNone() ? toSrgb(a["color"]) : kind->color ? toSrgb(Value(kind->color)) : toSrgb(nums({0, 0, 0})) ;
    if (a["color"].isNone() && !kind->color) {
      C3 p = R.pick(PETALS);
      accent = toSrgb(col(p));
    }
    B_ B{S, R, H, density, accent, toSrgb(Value(kind->leaf))};
    if (kindName == "fern" || kindName == "bush" || kindName == "cactus") B.accent = toSrgb(a["color"].isNone() ? Value(kind->color) : a["color"]);
    std::vector<ShapeP> parts;
    if (kindName == "flower") parts = flowerLike(B, {1, 0.1, 0.045, 78, 0.04, 0, accent, {0.95, 0.75, 0.15}});
    else if (kindName == "daisy") parts = flowerLike(B, {0.9, 0.1, 0.018, 84, 0.06, lvl(S, 8, 12, 16), accent, {0.98, 0.8, 0.12}});
    else if (kindName == "lavender") parts = lavender(B);
    else if (kindName == "fern") parts = fern(B);
    else if (kindName == "bush") parts = bush(B);
    else if (kindName == "cactus") parts = cactus(B);
    else parts = mushroom(B);
    return named(group(parts), "planta-" + kindName);
  })}};
}

}  // namespace tdi::kit
