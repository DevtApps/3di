// Padrões de superfície: planks, shingles e masonry (port de pattern.js).
#include <cmath>

#include "pattern.h"

namespace tdi {

static double fract(double x) { return x - std::floor(x); }
static double smooth(double a, double b, double x) {
  double t = std::min(1.0, std::max(0.0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
}
static double hash(double x, double y) { return fract(std::sin(x * 127.1 + y * 311.7) * 43758.5453); }

const char *PATTERN_GLSL = R"(
float patHash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float patG(vec3 p, vec3 bmin, vec3 bc, vec3 hf, int kind, vec2 sz, float gap, int ax, float vary) {
  vec3 q = abs(p - bc) / max(hf, vec3(1e-4));
  int n = q.x > q.y ? (q.x > q.z ? 0 : 2) : (q.y > q.z ? 1 : 2);
  vec3 r = p - bmin;
  int iu, iv;
  if (kind == 1) { iu = ax != n ? ax : (n == 1 ? 0 : 1); iv = 3 - n - iu; }
  else { iv = n == 1 ? 2 : 1; iu = 3 - n - iv; }
  float u = r[iu], v = r[iv];
  float H = sz.y, L = sz.x;
  float row = floor(v / H), fv = v / H - row;
  float shift = kind == 3 ? 0.5 * mod(row, 2.0) : patHash(vec2(row, 7.0));
  float uu = L > 0.0 ? u / L + shift : 0.5;
  float col = L > 0.0 ? floor(uu) : 0.0, fu = L > 0.0 ? uu - col : 0.5;
  float e = min(min(fv, 1.0 - fv) * H, L > 0.0 ? min(fu, 1.0 - fu) * L : 1e3);
  float soft = kind == 3 ? 0.25 * min(L, H) : 0.5 * gap;
  float groove = 1.0 - smoothstep(0.5 * gap, 0.5 * gap + soft, e);
  if (kind == 2) {
    // telhas: cada fileira é mais grossa embaixo (cobre a de baixo) e afina até o topo
    float slope = fv * (1.0 - smoothstep(1.0 - gap / H, 1.0, fv));
    float side = L > 0.0 ? 1.0 - smoothstep(0.5 * gap, gap, min(fu, 1.0 - fu) * L) : 0.0;
    groove = max(slope, side);
  }
  float h = vary * patHash(vec2(col, row) + 0.37);
  return groove + h * (1.0 - groove);
}
)";

PatternP patternOf(const Props &P) {
  PatternP r;
  V3 bmin = P.v3("bmin"), bc = P.v3("bc"), hf = P.v3("hf");
  auto sz = P.vec("sz");
  r.bmin = bmin; r.bc = bc; r.hf = hf;
  r.kind = (int)P.num("kind");
  r.sz = {sz[0], sz[1]};
  r.gap = P.num("gap");
  r.depth = P.num("depth");
  r.ax = (int)P.num("ax");
  r.vary = P.num("vary");
  return r;
}

double patternG(const V3 &p, const PatternP &P) {
  double q[3];
  for (int i = 0; i < 3; i++) q[i] = std::fabs(p[i] - P.bc[i]) / std::max(P.hf[i], 1e-4);
  int n = q[0] > q[1] ? (q[0] > q[2] ? 0 : 2) : (q[1] > q[2] ? 1 : 2);
  int iu, iv;
  if (P.kind == 1) { iu = P.ax != n ? P.ax : (n == 1 ? 0 : 1); iv = 3 - n - iu; }
  else { iv = n == 1 ? 2 : 1; iu = 3 - n - iv; }
  double u = p[iu] - P.bmin[iu], v = p[iv] - P.bmin[iv];
  double L = P.sz[0], H = P.sz[1];
  double row = std::floor(v / H), fv = v / H - row;
  double shift = P.kind == 3 ? 0.5 * std::fmod(std::fmod(row, 2) + 2, 2) : hash(row, 7);
  double uu = L > 0 ? u / L + shift : 0.5;
  double col = L > 0 ? std::floor(uu) : 0, fu = L > 0 ? uu - col : 0.5;
  double e = std::min(std::min(fv, 1 - fv) * H, L > 0 ? std::min(fu, 1 - fu) * L : 1e3);
  double soft = P.kind == 3 ? 0.25 * std::min(L, H) : 0.5 * P.gap;
  double groove = 1 - smooth(0.5 * P.gap, 0.5 * P.gap + soft, e);
  if (P.kind == 2) {
    double slope = fv * (1 - smooth(1 - P.gap / H, 1, fv));
    double side = L > 0 ? 1 - smooth(0.5 * P.gap, P.gap, std::min(fu, 1 - fu) * L) : 0;
    groove = std::max(slope, side);
  }
  double h = P.vary * hash(col + 0.37, row + 0.37);
  return groove + h * (1 - groove);
}

double patternLip(const PatternP &P) { return 1 / (1 + (2 * P.depth) / std::max(P.gap, 1e-4)); }

static Value make(const ShapeP &s, int kind, const Value &L, const Value &H, const Value &gap, const Value &depth, const Value &vary,
                  const Value &axis, const std::string &what) {
  const BBox &b = s->bbox();
  for (int i = 0; i < 3; i++)
    if (!(b.min[i] > -1e3) || !(b.max[i] < 1e3)) throw ScriptError(what + " não funciona com formas infinitas (plane)");
  auto pos = [&](const Value &v, const std::string &n) {
    double x = num(v, n);
    if (!(x > 0)) throw ScriptError(what + ": " + n + " deve ser maior que zero");
    return x;
  };
  double sz0 = L.isNone() ? 0 : pos(L, "length");
  double sz1 = pos(H, kind == 1 ? "width" : "height");
  double g = pos(gap, "gap"), d = pos(depth, "depth"), va = num(vary, "vary");
  if (va < 0 || va > 1) throw ScriptError(what + ": vary deve ficar entre 0 e 1");
  std::string ax = jsLower(str(axis));
  int axi = ax == "x" ? 0 : ax == "y" ? 1 : ax == "z" ? 2 : -1;
  if (axi < 0) throw ScriptError(what + ": axis deve ser \"x\", \"y\" ou \"z\"");
  V3 bc, hf;
  for (int i = 0; i < 3; i++) { bc[i] = (b.min[i] + b.max[i]) / 2; hf[i] = (b.max[i] - b.min[i]) / 2; }
  return mkShape("pattern", {{"kind", kind}, {"sz", nums({sz0, sz1})}, {"gap", g}, {"depth", d}, {"vary", va}, {"ax", axi},
                             {"bmin", nums3(b.min)}, {"bc", nums3(bc)}, {"hf", nums3(hf)}}, {s});
}

void registerPatternMethods() {
  addMethod("planks", {"width=0.2", "length=None", "axis=\"y\"", "gap=0.008", "depth=0.012", "vary=0.25"}, [](const ShapeP &s, const Args &a) {
    return make(s, 1, a["length"], a["width"], a["gap"], a["depth"], a["vary"], a["axis"], "planks()");
  });
  addMethod("shingles", {"width=0.25", "height=0.18", "gap=0.01", "depth=0.025", "vary=0.3"}, [](const ShapeP &s, const Args &a) {
    return make(s, 2, a["width"], a["height"], a["gap"], a["depth"], a["vary"], "y", "shingles()");
  });
  addMethod("masonry", {"length=0.4", "height=0.2", "gap=0.015", "depth=0.02", "vary=0.4"}, [](const ShapeP &s, const Args &a) {
    return make(s, 3, a["length"], a["height"], a["gap"], a["depth"], a["vary"], "y", "masonry()");
  });
}

}  // namespace tdi
