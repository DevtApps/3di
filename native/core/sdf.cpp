// Port de sdf.js.
#include "sdf.h"

#include <algorithm>
#include <cmath>

#include "anchor.h"
#include "compiler.h"
#include "expr.h"
#include "pattern.h"
#include "profile.h"

namespace tdi {

static double at(const Value &v, double t) { return v.isExpr() ? v.expr()->eval(t) : v.n(); }
static double clampd(double x, double a, double b) { return std::min(b, std::max(a, x)); }
static double mixd(double a, double b, double h) { return a + (b - a) * h; }
static double fract(double x) { return x - std::floor(x); }
static double len3(double x, double y, double z) { return std::sqrt(x * x + y * y + z * z); }
static double sgn(double x) { return x > 0 ? 1 : x < 0 ? -1 : x; }

// ---------- primitivas ----------
static double sdBox(double px, double py, double pz, double bx, double by, double bz) {
  double qx = std::fabs(px) - bx, qy = std::fabs(py) - by, qz = std::fabs(pz) - bz;
  return len3(std::max(qx, 0.0), std::max(qy, 0.0), std::max(qz, 0.0)) + std::min(std::max({qx, qy, qz}), 0.0);
}
static double sdCyl(double px, double py, double pz, double r, double h) {
  double dx = std::hypot(px, pz) - r, dy = std::fabs(py) - h;
  return std::min(std::max(dx, dy), 0.0) + std::hypot(std::max(dx, 0.0), std::max(dy, 0.0));
}
static double sdCone(double px, double py, double pz, double h, double r1, double r2) {
  double qx = std::hypot(px, pz), qy = py;
  double k1x = r2, k1y = h, k2x = r2 - r1, k2y = 2 * h;
  double cax = qx - std::min(qx, qy < 0 ? r1 : r2), cay = std::fabs(qy) - h;
  double tt = clampd(((k1x - qx) * k2x + (k1y - qy) * k2y) / (k2x * k2x + k2y * k2y), 0, 1);
  double cbx = qx - k1x + k2x * tt, cby = qy - k1y + k2y * tt;
  double s = cbx < 0 && cay < 0 ? -1 : 1;
  return s * std::sqrt(std::min(cax * cax + cay * cay, cbx * cbx + cby * cby));
}
static double sdTorus(double px, double py, double pz, double R, double r) { return std::hypot(std::hypot(px, pz) - R, py) - r; }
static double sdCapsule(double px, double py, double pz, double r, double a) { return len3(px, py - clampd(py, -a, a), pz) - r; }

struct MergeP { double r, sw; int profile; bool blend, seam; V3 seamC; };
static double mergeD(double a, double b, const MergeP &P) {
  double r = P.r;
  if (P.profile == 0) { double h = clampd(0.5 + (0.5 * (b - a)) / r, 0, 1); return mixd(b, a, h) - r * h * (1 - h); }
  if (P.profile == 1) return std::min({a, b, (a + b - r) * M_SQRT1_2});
  return std::max(std::min(a, b), r * 0.5 - std::hypot(a, b));
}
static double sdRoundCone(double x, double y, double z, const V3 &a, const V3 &b, double r1, double r2) {
  double bx = b[0] - a[0], by = b[1] - a[1], bz = b[2] - a[2];
  double l2 = bx * bx + by * by + bz * bz, rr = r1 - r2, a2 = l2 - rr * rr, il2 = 1 / l2;
  double px = x - a[0], py = y - a[1], pz = z - a[2];
  double yy = px * bx + py * by + pz * bz, zz = yy - l2;
  double ex = px * l2 - bx * yy, ey = py * l2 - by * yy, ez = pz * l2 - bz * yy;
  double xx = ex * ex + ey * ey + ez * ez;
  double y2 = yy * yy * l2, z2 = zz * zz * l2, k = sgn(rr) * rr * rr * xx;
  if (sgn(zz) * a2 * z2 > k) return std::sqrt(xx + z2) * il2 - r2;
  if (sgn(yy) * a2 * y2 < k) return std::sqrt(xx + y2) * il2 - r1;
  return (std::sqrt(xx * a2 * il2) + yy * rr) * il2 - r1;
}
static double sdEllipsoid(double px, double py, double pz, double rx, double ry, double rz) {
  double k0 = len3(px / rx, py / ry, pz / rz), k1 = len3(px / (rx * rx), py / (ry * ry), pz / (rz * rz));
  return k1 > 0 ? (k0 * (k0 - 1)) / k1 : -std::min({rx, ry, rz});
}
static double sdPyramid(double px, double py, double pz, double h) {
  double m2 = h * h + 0.25;
  px = std::fabs(px);
  pz = std::fabs(pz);
  if (pz > px) std::swap(px, pz);
  px -= 0.5;
  pz -= 0.5;
  double qx = pz, qy = h * py - 0.5 * px, qz = h * px + 0.5 * py;
  double s = std::max(-qx, 0.0);
  double t = clampd((qy - 0.5 * pz) / (m2 + 0.25), 0, 1);
  double a = m2 * (qx + s) * (qx + s) + qy * qy;
  double b = m2 * (qx + 0.5 * t) * (qx + 0.5 * t) + (qy - m2 * t) * (qy - m2 * t);
  double d2 = std::min(qy, -qx * m2 - qy * 0.5) > 0 ? 0 : std::min(a, b);
  return std::sqrt((d2 + qz * qz) / m2) * sgn(std::max(qz, -py));
}
static double sdTriIso(double px, double py, double qx, double qy) {
  px = std::fabs(px);
  double ta = clampd((px * qx + py * qy) / (qx * qx + qy * qy), 0, 1);
  double ax = px - qx * ta, ay = py - qy * ta;
  double tb = clampd(px / qx, 0, 1);
  double bx = px - qx * tb, by = py - qy;
  double s = -sgn(qy);
  double dx = std::min(ax * ax + ay * ay, bx * bx + by * by);
  double dy = std::min(s * (px * qy - py * qx), s * (py - qy));
  return -std::sqrt(dx) * sgn(dy);
}
static double sdPrism(double px, double py, double pz, double hw, double h, double hd) {
  double wx = sdTriIso(px, h * 0.5 - py, hw, h), wy = std::fabs(pz) - hd;
  return std::min(std::max(wx, wy), 0.0) + std::hypot(std::max(wx, 0.0), std::max(wy, 0.0));
}
static double smin(double a, double b, double k) { double h = clampd(0.5 + (0.5 * (b - a)) / k, 0, 1); return mixd(b, a, h) - k * h * (1 - h); }
static double smax(double a, double b, double k) { return -smin(-a, -b, k); }

// ---------- ruído e texturas ----------
static double hash31(double x, double y, double z) {
  x = fract(x * 0.3183099 + 0.1) * 17;
  y = fract(y * 0.3183099 + 0.2) * 17;
  z = fract(z * 0.3183099 + 0.3) * 17;
  return fract(x * y * z * (x + y + z));
}
static double vnoise(double x, double y, double z) {
  double ix = std::floor(x), iy = std::floor(y), iz = std::floor(z);
  double fx = x - ix, fy = y - iy, fz = z - iz;
  fx = fx * fx * (3 - 2 * fx);
  fy = fy * fy * (3 - 2 * fy);
  fz = fz * fz * (3 - 2 * fz);
  auto h = [&](double a, double b, double c) { return hash31(ix + a, iy + b, iz + c); };
  return mixd(mixd(mixd(h(0, 0, 0), h(1, 0, 0), fx), mixd(h(0, 1, 0), h(1, 1, 0), fx), fy),
              mixd(mixd(h(0, 0, 1), h(1, 0, 1), fx), mixd(h(0, 1, 1), h(1, 1, 1), fx), fy), fz);
}
double fbm(double x, double y, double z) {
  double a = 0.5, s = 0;
  for (int i = 0; i < 5; i++) {
    s += a * vnoise(x, y, z);
    x = x * 2.02 + 1.7;
    y = y * 2.02 + 9.2;
    z = z * 2.02 + 3.1;
    a *= 0.5;
  }
  return s / 0.96875;
}
static double smoothstep(double e0, double e1, double x) { double t = clampd((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t); }
static V3 mix3(const V3 &a, const V3 &b, double h) { return {mixd(a[0], b[0], h), mixd(a[1], b[1], h), mixd(a[2], b[2], h)}; }
static double jmod(double a, double b) { return std::fmod(std::fmod(a, b) + b, b); }

static std::array<double, 2> planar(int k, double gx, double gy, double s) {
  if (k == 4) return {fract(gy / s) >= 0.5 ? 1.0 : 0.0, 0};
  if (k == 5) return {jmod(std::floor(gx / s + 0.5) + std::floor(gy / s + 0.5), 2), 0};
  double bh = s * 0.4;
  double row = std::floor(gy / bh + 0.02);
  double u = gx / s + 0.5 * jmod(row, 2);
  double cx = fract(u) * s, cy = fract(gy / bh + 0.02) * bh;
  double mortar = std::min(s, bh) * 0.08;
  return {cx >= mortar && cy >= mortar ? 0.0 : 1.0, hash31(std::floor(u), row, 3)};
}

static std::array<double, 2> texField(const V3 &p, int k, double s, double axis, const V3 *n) {
  V3 q = axis < 0.5 ? V3{p[1], p[0], p[2]} : axis < 1.5 ? p : V3{p[0], p[2], p[1]};
  if (k == 1) return {smoothstep(0.3, 0.75, fbm(p[0] / s, p[1] / s, p[2] / s)), 0};
  if (k == 2) {
    double nx = fbm(q[0] / s, (q[1] * 0.08) / s, q[2] / s) - 0.5;
    double nz = fbm(q[0] / s + 7, (q[1] * 0.08) / s + 7, q[2] / s + 7) - 0.5;
    double r = std::hypot(q[0] + nx * s * 3, q[2] + nz * s * 3) / s;
    double ring = std::pow(fract(r), 4);
    double grain = fbm((q[0] * 25) / s, q[1] / s, (q[2] * 25) / s);
    return {clampd(ring * 0.75 + (grain - 0.5) * 0.5 + 0.1, 0, 1), 0};
  }
  if (k == 3) {
    double nz = fbm(p[0] / s, p[1] / s, p[2] / s);
    double v = std::fabs(std::sin(((p[0] + p[1] * 0.6 + p[2] * 0.3) / s) * 1.4 + nz * 7));
    double vein = 1 - smoothstep(0, 0.14, v);
    double soft = smoothstep(0.4, 0.9, fbm((p[0] / s) * 2.3 + 3, (p[1] / s) * 2.3 + 3, (p[2] / s) * 2.3 + 3));
    return {clampd(vein * 0.9 + soft * 0.2, 0, 1), 0};
  }
  if (k == 4 || k == 5 || k == 6) {
    if (axis > 2.5) {
      V3 nn = n ? *n : V3{0, 1, 0};
      V3 w{std::pow(std::fabs(nn[0]), 6), std::pow(std::fabs(nn[1]), 6), std::pow(std::fabs(nn[2]), 6)};
      double sum = w[0] + w[1] + w[2] + 1e-6;
      std::array<double, 2> f{0, 0};
      auto add = [&](std::array<double, 2> r, double wt) { f[0] += r[0] * wt / sum; f[1] += r[1] * wt / sum; };
      if (w[0] / sum > 0.02) add(planar(k, p[2], p[1], s), w[0]);
      if (w[1] / sum > 0.02) add(planar(k, p[0], p[2], s), w[1]);
      if (w[2] / sum > 0.02) add(planar(k, p[0], p[1], s), w[2]);
      return f;
    }
    if (k == 4) return planar(4, 0, q[1], s);
    if (k == 5) return {jmod(std::floor(p[0] / s + 0.5) + std::floor(p[1] / s + 0.5) + std::floor(p[2] / s + 0.5), 2), 0};
    return planar(6, p[0] + p[2], p[1], s);
  }
  if (k == 7) return {clampd(q[1] / s, 0, 1), 0};
  if (k == 8 || k == 9) return {fbm(p[0] / s, p[1] / s, p[2] / s), 0};
  return {0, 0};
}

static V3 texColor(const V3 &p, const V3 &c1, const V3 &c2, const std::array<double, 4> &tx, const V3 *n) {
  int k = (int)tx[0];
  double s = tx[1];
  auto f = texField(p, k, s, tx[2], n);
  if (k == 6) {
    double v = (0.75 + 0.4 * f[1]) * (0.85 + 0.3 * vnoise((p[0] * 40) / s, (p[1] * 40) / s, (p[2] * 40) / s));
    return mix3({c1[0] * v, c1[1] * v, c1[2] * v}, c2, f[0]);
  }
  return mix3(c1, c2, f[0]);
}

double texHeight(const V3 &p, const std::array<double, 4> &tx, const V3 *n) {
  int k = (int)tx[0];
  if (k == 0 || !(tx[3] > 0) || k == 7) return 0;
  auto f = texField(p, k, tx[1], tx[2], n);
  if (k == 6) return 1 - f[0] + 0.12 * f[1];
  if (k == 3) return 1 - f[0];
  return f[0];
}

static double texSizeOf(int k) {
  static const double T[] = {NAN, 0.25, 0.06, 0.3, 0.1, 0.25, 0.25, 1, 0.3, 0.1};
  return k >= 1 && k <= 9 ? T[k] : NAN;
}
static V3 texC2(const Rec &tex, const V3 &color) {
  if (!tex.f["c2"].isNone()) return tex.f.v3("c2");
  int k = (int)tex.f.num("kind");
  if (k == 9) return color;
  if (k == 8) return {color[0] * 0.55, color[1] * 0.55, color[2] * 0.55};
  if (k == 7) return {std::min(1.0, color[0] * 1.6 + 0.04), std::min(1.0, color[1] * 1.6 + 0.04), std::min(1.0, color[2] * 1.6 + 0.04)};
  if (k == 6) return {0.69, 0.65, 0.58};
  double m = k == 3 ? 0.25 : k == 5 || k == 4 ? 0.35 : 0.5;
  return {color[0] * m, color[1] * m, color[2] * m};
}
static std::array<double, 4> texTx(const Rec &tex) {
  int k = (int)tex.f.num("kind");
  return {double(k), tex.f["size"].isNone() ? texSizeOf(k) : tex.f.num("size"), tex.f.num("axis"), tex.f["bump"].isNone() ? 0 : tex.f.num("bump")};
}

// ---------- transformações ----------

using PMap = std::function<V3(double, double, double)>;
static bool pointMap(const Shape &s, double t, PMap &map, double &k) {
  const Props &P = s.props;
  const std::string &kind = s.kind;
  k = 1;
  if (kind == "translate") {
    auto &vv = P["v"].list()->items;
    V3 v{at(vv[0], t), at(vv[1], t), at(vv[2], t)};
    map = [v](double x, double y, double z) { return V3{x - v[0], y - v[1], z - v[2]}; };
    return true;
  }
  if (kind == "rotate") {
    M3 m;
    if (P.has("angles")) {
      auto &a = P["angles"].list()->items;
      m = rotMatrix(at(a[0], t), at(a[1], t), at(a[2], t));
    } else m = P.m3("m");
    map = [m](double x, double y, double z) { return V3{m[0] * x + m[3] * y + m[6] * z, m[1] * x + m[4] * y + m[7] * z, m[2] * x + m[5] * y + m[8] * z}; };
    return true;
  }
  if (kind == "scale") {
    auto &sv0 = P["s"].list()->items;
    V3 sv{at(sv0[0], t), at(sv0[1], t), at(sv0[2], t)};
    map = [sv](double x, double y, double z) { return V3{x / sv[0], y / sv[1], z / sv[2]}; };
    k = std::min({sv[0], sv[1], sv[2]});
    return true;
  }
  if (kind == "affine") {
    M3 mi = P.m3("minv");
    V3 tv = P.v3("t");
    map = [mi, tv](double x, double y, double z) {
      double a = x - tv[0], b = y - tv[1], c = z - tv[2];
      return V3{mi[0] * a + mi[1] * b + mi[2] * c, mi[3] * a + mi[4] * b + mi[5] * c, mi[6] * a + mi[7] * b + mi[8] * c};
    };
    k = P.num("ds");
    return true;
  }
  if (kind == "mirror") {
    V3 c = center(s.children[0]->bbox());
    V3 sg{c[0] < 0 ? -1.0 : 1.0, c[1] < 0 ? -1.0 : 1.0, c[2] < 0 ? -1.0 : 1.0};
    bool ax[3] = {P["axes"][0].b(), P["axes"][1].b(), P["axes"][2].b()};
    map = [sg, ax](double x, double y, double z) {
      return V3{ax[0] ? sg[0] * std::fabs(x) : x, ax[1] ? sg[1] * std::fabs(y) : y, ax[2] ? sg[2] * std::fabs(z) : z};
    };
    return true;
  }
  if (kind == "repeat") {
    V3 n = P.v3("n"), s3 = P.v3("s"), sp, h;
    for (int i = 0; i < 3; i++) { sp[i] = n[i] > 1 ? s3[i] : 1; h[i] = (n[i] - 1) / 2; }
    map = [n, sp, h](double x, double y, double z) {
      auto rep = [&](double v, int i) { return v - sp[i] * (clampd(std::floor(v / sp[i] + h[i] + 0.5), 0, n[i] - 1) - h[i]); };
      return V3{rep(x, 0), rep(y, 1), rep(z, 2)};
    };
    return true;
  }
  if (kind == "taper") {
    int axis = (int)P.num("axis");
    double top = P.num("top"), bottom = P.num("bottom"), lo = P.num("lo"), hi = P.num("hi");
    const BBox &b = s.children[0]->bbox();
    double R = -INFINITY;
    for (int i = 0; i < 3; i++)
      if (i != axis) R = std::max(R, std::max(std::fabs(b.min[i]), std::fabs(b.max[i])));
    R *= M_SQRT2;
    double sm = std::min(top, bottom), slope = std::fabs(top - bottom) / std::max(1e-6, hi - lo);
    map = [=](double x, double y, double z) {
      V3 c{x, y, z};
      double tt = clampd((c[axis] - lo) / std::max(1e-6, hi - lo), 0, 1);
      double sc = mixd(bottom, top, tt);
      for (int i = 0; i < 3; i++)
        if (i != axis) c[i] /= sc;
      return c;
    };
    k = sm / std::sqrt(1 + std::pow((slope * R) / sm, 2));
    return true;
  }
  if (kind == "bend") {
    double kk = P.num("k"), pivot = P.num("pivot");
    int axis = (int)P.num("axis"), toward = (int)P.num("toward");
    const BBox &b = s.children[0]->bbox();
    double R = std::hypot(std::max(std::fabs(b.min[axis] - pivot), std::fabs(b.max[axis] - pivot)), std::max(std::fabs(b.min[toward]), std::fabs(b.max[toward])));
    map = [=](double x, double y, double z) {
      V3 c{x, y, z};
      double u = c[axis] - pivot, v = c[toward];
      double co = std::cos(kk * u), sn = std::sin(kk * u);
      V3 out = c;
      out[axis] = co * u - sn * v + pivot;
      out[toward] = sn * u + co * v;
      return out;
    };
    k = 1 / std::sqrt(1 + (kk * R) * (kk * R));
    return true;
  }
  if (kind == "shear") {
    double sx = P.num("sx"), sz = P.num("sz"), y0 = P.num("y0");
    map = [=](double x, double y, double z) { return V3{x - sx * (y - y0), y, z - sz * (y - y0)}; };
    k = 1 / std::sqrt(1 + sx * sx + sz * sz);
    return true;
  }
  if (kind == "polar") {
    double sec = (2 * M_PI) / P.num("n");
    map = [sec](double x, double y, double z) {
      double r = std::hypot(x, z);
      double a = jmod(std::atan2(z, x) + 0.5 * sec, sec) - 0.5 * sec;
      return V3{r * std::cos(a), y, r * std::sin(a)};
    };
    return true;
  }
  if (kind == "elongate") {
    V3 h = P.v3("h");
    map = [h](double x, double y, double z) { return V3{x - clampd(x, -h[0], h[0]), y - clampd(y, -h[1], h[1]), z - clampd(z, -h[2], h[2])}; };
    return true;
  }
  if (kind == "twist") {
    const BBox &b = s.children[0]->bbox();
    double R = std::max({std::fabs(b.min[0]), std::fabs(b.max[0]), std::fabs(b.min[2]), std::fabs(b.max[2])}) * M_SQRT2;
    double kk = P.num("k");
    map = [kk](double x, double y, double z) {
      double c = std::cos(kk * y), sn = std::sin(kk * y);
      return V3{c * x - sn * z, y, sn * x + c * z};
    };
    k = 1 / std::sqrt(1 + (kk * R) * (kk * R));
    return true;
  }
  return false;
}

static DistFn primDist(const Shape &s) {
  const Props &P = s.props;
  const std::string &k = s.kind;
  if (k == "box") {
    V3 sz = P.v3("size");
    double r = P.num("r");
    V3 h{sz[0] / 2 - r, sz[1] / 2 - r, sz[2] / 2 - r};
    return [h, r](double x, double y, double z) { return sdBox(x, y, z, h[0], h[1], h[2]) - r; };
  }
  if (k == "sphere") { double r = P.num("r"); return [r](double x, double y, double z) { return len3(x, y, z) - r; }; }
  if (k == "cylinder") {
    double r = P.num("r"), h = P.num("h"), ro = P.num("round");
    return [=](double x, double y, double z) { return sdCyl(x, y, z, r - ro, h / 2 - ro) - ro; };
  }
  if (k == "cone") { double h = P.num("h"), r = P.num("r"), top = P.num("top"); return [=](double x, double y, double z) { return sdCone(x, y, z, h / 2, r, top); }; }
  if (k == "torus") { double R = P.num("R"), r = P.num("r"); return [=](double x, double y, double z) { return sdTorus(x, y, z, R, r); }; }
  if (k == "capsule") { double r = P.num("r"), h = P.num("h"); return [=](double x, double y, double z) { return sdCapsule(x, y, z, r, h / 2 - r); }; }
  if (k == "ellipsoid") { V3 r = P.v3("radii"); return [r](double x, double y, double z) { return sdEllipsoid(x, y, z, r[0], r[1], r[2]); }; }
  if (k == "pyramid") {
    double w = P.num("w"), h = P.num("h");
    return [=](double x, double y, double z) { return sdPyramid(x / w, (y + h / 2) / w, z / w, h / w) * w; };
  }
  if (k == "prism") { double w = P.num("w"), h = P.num("h"), d = P.num("d"); return [=](double x, double y, double z) { return sdPrism(x, y, z, w / 2, h, d / 2); }; }
  if (k == "plane") return [](double, double y, double) { return y; };
  if (k == "cbox") {
    V3 sz = P.v3("size");
    double r = P.num("r");
    V3 h{sz[0] / 2 - r, sz[1] / 2 - r, sz[2] / 2 - r};
    double c = std::max(0.0, P.num("c") - r);
    return [=](double x, double y, double z) {
      double qx = std::fabs(x) - h[0], qy = std::fabs(y) - h[1], qz = std::fabs(z) - h[2];
      double d = sdBox(x, y, z, h[0], h[1], h[2]);
      double e = (std::max({qx + qy, qy + qz, qz + qx}) + c) * M_SQRT1_2;
      return std::max(d, e) - r;
    };
  }
  if (k == "roundcone") {
    V3 a = P.v3("a"), b = P.v3("b");
    double r1 = P.num("r1"), r2 = P.num("r2");
    return [=](double x, double y, double z) { return sdRoundCone(x, y, z, a, b, r1, r2); };
  }
  if (k == "loft") {
    std::vector<std::vector<std::array<double, 4>>> segs;
    for (auto &sg : P["segs"].list()->items) {
      std::vector<std::array<double, 4>> pl;
      for (auto &v : sg.list()->items) pl.push_back({v[0].n(), v[1].n(), v[2].n(), v[3].n()});
      segs.push_back(pl);
    }
    return [segs](double x, double y, double z) {
      double best = INFINITY;
      for (auto &pl : segs) {
        double d = -INFINITY;
        for (auto &q : pl) d = std::max(d, q[0] * x + q[1] * y + q[2] * z - q[3]);
        best = std::min(best, d);
      }
      return best;
    };
  }
  if (k == "hull") {
    std::vector<std::array<double, 4>> pl;
    for (auto &v : P["planes"].list()->items) pl.push_back({v[0].n(), v[1].n(), v[2].n(), v[3].n()});
    return [pl](double x, double y, double z) {
      double d = -INFINITY;
      for (auto &q : pl) d = std::max(d, q[0] * x + q[1] * y + q[2] * z - q[3]);
      return d;
    };
  }
  if (k == "extrude") {
    auto pts = pointsOf(P["pts"]);
    double half = P.num("h") / 2, r = P.num("r");
    if (P["axis"].s() == "z") return [=](double x, double y, double z) { return extrudeDist(polygonSDF(pts, x, y), z, half, r); };
    return [=](double x, double y, double z) { return extrudeDist(polygonSDF(pts, x, z), y, half, r); };
  }
  if (k == "implicit") {
    auto f = P["f"].expr()->compile();
    V3 h = P.v3("half");
    double kk = P.num("lip");
    return [=](double x, double y, double z) { return std::max(f(x, y, z, 0) * kk, sdBox(x, y, z, h[0], h[1], h[2])); };
  }
  if (k == "lathe") {
    auto pts = pointsOf(P["pts"]);
    return [pts](double x, double y, double z) { return polygonSDF(pts, std::hypot(x, z), y); };
  }
  return nullptr;
}

static DistFn bboxDist(const BBox &b) {
  V3 c = center(b), h;
  for (int i = 0; i < 3; i++) h[i] = (b.max[i] - b.min[i]) / 2 + 0.01;
  return [c, h](double x, double y, double z) { return sdBox(x - c[0], y - c[1], z - c[2], h[0], h[1], h[2]); };
}
static DistFn cullBox(const Shape &c) {
  const BBox &b = c.bbox();
  bool finite = true;
  for (int i = 0; i < 3; i++) finite &= b.max[i] < 5e3 && b.min[i] > -5e3;
  return finite && (c.leaves() >= 3 || isHeavy(c)) ? bboxDist(b) : nullptr;
}

DistFn buildDist(const ShapeP &sp, double t) {
  const Shape &s = *sp;
  if (auto prim = primDist(s)) return prim;
  const Props &P = s.props;
  if (s.kind == "paint") {
    DistFn base = buildDist(s.children[0], t);
    double relief = P["relief"].isNone() ? 0 : P.num("relief");
    if (!relief) return base;
    DistFn reg = buildDist(s.children[1], t);
    double kk = P.num("k"), reach = kk + 0.06 + 2 * std::fabs(relief);
    return [=](double x, double y, double z) {
      double d = base(x, y, z);
      if (d >= reach) return d;
      return d - relief * (1 - smoothstep(-kk, kk + 1e-5, reg(x, y, z)));
    };
  }
  std::vector<DistFn> kids;
  for (auto &c : s.children) kids.push_back(buildDist(c, t));
  if (kids.size() == 1) {
    PMap map;
    double k;
    if (pointMap(s, t, map, k)) {
      DistFn c = kids[0];
      if (k == 1) return [map, c](double x, double y, double z) { V3 q = map(x, y, z); return c(q[0], q[1], q[2]); };
      return [map, c, k](double x, double y, double z) { V3 q = map(x, y, z); return c(q[0], q[1], q[2]) * k; };
    }
  }
  DistFn c0 = kids.empty() ? nullptr : kids[0];
  const std::string &k = s.kind;
  if (k == "material" || k == "label" || k == "bound") return c0;
  if (k == "round") { double r = P.num("r"); return [c0, r](double x, double y, double z) { return c0(x, y, z) - r; }; }
  if (k == "shell") { double th = P.num("t"); return [c0, th](double x, double y, double z) { return std::fabs(c0(x, y, z)) - th / 2; }; }
  if (k == "displace") {
    double amt = P.num("amt"), sz = P.num("size");
    double lip = 1 / (1 + (2.5 * amt) / sz);
    return [=](double x, double y, double z) { return (c0(x, y, z) + amt * (fbm(x / sz, y / sz, z / sz) * 2 - 1)) * lip; };
  }
  if (k == "pattern") {
    auto pp = patternOf(P);
    double lip = patternLip(pp);
    return [=](double x, double y, double z) { return (c0(x, y, z) + pp.depth * patternG({x, y, z}, pp)) * lip; };
  }
  if (k == "union") {
    double kk = P.num("k");
    if (kk) return [kids, kk](double x, double y, double z) {
        double a = 0;
        for (size_t i = 0; i < kids.size(); i++) a = i ? smin(a, kids[i](x, y, z), kk) : kids[i](x, y, z);
        return a;
      };
    std::vector<DistFn> bounds;
    for (auto &c : s.children) bounds.push_back(cullBox(*c));
    return [kids, bounds](double x, double y, double z) {
      double best = 1e10;
      for (size_t i = 0; i < kids.size(); i++) {
        if (bounds[i] && bounds[i](x, y, z) >= best) continue;
        double d = kids[i](x, y, z);
        if (d < best) best = d;
      }
      return best;
    };
  }
  if (k == "merge") {
    MergeP mp{P.num("r"), 0, P["profile"].s() == "round" ? 0 : P["profile"].s() == "chamfer" ? 1 : 2, false, false, {}};
    return [kids, mp](double x, double y, double z) {
      double acc = 0;
      for (size_t i = 0; i < kids.size(); i++) acc = i ? mergeD(acc, kids[i](x, y, z), mp) : kids[i](x, y, z);
      return acc;
    };
  }
  if (k == "subtract") {
    DistFn a = kids[0], b = kids[1];
    double kk = P.num("k");
    if (kk) return [=](double x, double y, double z) { return smax(a(x, y, z), -b(x, y, z), kk); };
    return [=](double x, double y, double z) { return std::max(a(x, y, z), -b(x, y, z)); };
  }
  if (k == "intersect") {
    double kk = P.num("k");
    return [kids, kk](double x, double y, double z) {
      double acc = 0;
      for (size_t i = 0; i < kids.size(); i++) {
        double d = kids[i](x, y, z);
        acc = i == 0 ? d : kk ? smax(acc, d, kk) : std::max(acc, d);
      }
      return acc;
    };
  }
  throw std::runtime_error("sdf: tipo desconhecido " + k);
}

// material acumulado: as chaves do DEFAULT do JS
struct MatIn {
  Value color, rough, metal, glow, tex, facet, coat;
};
static const char *MKEYS[] = {"color", "rough", "metal", "glow", "tex", "facet", "coat"};
static Value &slot(MatIn &m, int i) {
  Value *s[] = {&m.color, &m.rough, &m.metal, &m.glow, &m.tex, &m.facet, &m.coat};
  return *s[i];
}

static MatFn buildMatIn(const ShapeP &sp, double t, const MatIn &mat) {
  const Shape &s = *sp;
  const Props &P = s.props;
  if (auto prim = primDist(s)) {
    MatR base;
    if (!mat.color.isNone()) base.c = V3{val0(mat.color[0]), val0(mat.color[1]), val0(mat.color[2])};
    if (!mat.rough.isNone()) base.rough = val0(mat.rough);
    if (!mat.metal.isNone()) base.metal = val0(mat.metal);
    base.glow = mat.glow.isNone() ? 0 : at(mat.glow, t);
    base.facet = mat.facet;
    base.coat = mat.coat.isNone() ? 0 : val0(mat.coat);
    if (!mat.tex.isNone()) {
      auto tex = mat.tex.as<Rec>();
      base.hasTex = true;
      base.tx = texTx(*tex);
      base.c2 = texC2(*tex, base.c);
    }
    return [prim, base](double x, double y, double z, const V3 *tp) {
      MatR r = base;
      r.d = prim(x, y, z);
      if (tp) { r.hasTp = true; r.tp = *tp; }
      return r;
    };
  }
  if (s.kind == "material") {
    MatIn merged = mat;
    for (int i = 0; i < 7; i++)
      if (!P[MKEYS[i]].isNone()) slot(merged, i) = P[MKEYS[i]];
    MatFn c = buildMatIn(s.children[0], t, merged);
    if (P["tex"].isNone()) return c;
    auto tex = P["tex"].as<Rec>();
    double off = tex->f["off"].isNone() ? 0 : tex->f.num("off");
    V3 o{0, 0, 0};
    if (off) o[(int)tex->f.num("offAxis")] = off;
    return [c, o, off](double x, double y, double z, const V3 *tp) {
      V3 q = tp ? *tp : V3{x, y, z};
      if (off) q = {q[0] - o[0], q[1] - o[1], q[2] - o[2]};
      return c(x, y, z, &q);
    };
  }
  std::vector<MatFn> kids;
  for (auto &c : s.children) kids.push_back(buildMatIn(c, t, mat));
  PMap map;
  double k;
  if (pointMap(s, t, map, k)) {
    MatFn c = kids[0];
    return [map, c, k](double x, double y, double z, const V3 *tp) {
      V3 q = map(x, y, z);
      MatR r = c(q[0], q[1], q[2], tp ? tp : &q);
      if (k != 1) r.d *= k;
      return r;
    };
  }
  MatFn c0 = kids.empty() ? nullptr : kids[0];
  const std::string &kind = s.kind;
  if (kind == "label" || kind == "bound") return c0;
  if (kind == "paint") {
    MatFn reg = kids[1];
    double kk = P.num("k"), relief = P["relief"].isNone() ? 0 : P.num("relief"), reach = kk + 0.06 + 2 * std::fabs(relief);
    return [=](double x, double y, double z, const V3 *tp) {
      MatR r = c0(x, y, z, tp);
      if (r.d >= reach) return r;
      MatR g = reg(x, y, z, tp);
      double w = 1 - smoothstep(-kk, kk + 1e-5, g.d);
      if (w <= 0) return r;
      MatR out = r;
      out.d = r.d - relief * w;
      out.c = mix3(r.c, g.c, w);
      out.rough = mixd(r.rough, g.rough, w);
      out.metal = mixd(r.metal, g.metal, w);
      if (w > 0.5) { out.hasTex = g.hasTex; out.c2 = g.c2; out.tx = g.tx; out.hasTp = g.hasTp; out.tp = g.tp; out.facet = g.facet; }
      return out;
    };
  }
  if (kind == "round") { double r0 = P.num("r"); return [c0, r0](double x, double y, double z, const V3 *tp) { MatR r = c0(x, y, z, tp); r.d -= r0; return r; }; }
  if (kind == "shell") { double th = P.num("t"); return [c0, th](double x, double y, double z, const V3 *tp) { MatR r = c0(x, y, z, tp); r.d = std::fabs(r.d) - th / 2; return r; }; }
  if (kind == "displace") {
    double amt = P.num("amt"), sz = P.num("size"), lip = 1 / (1 + (2.5 * amt) / sz);
    return [=](double x, double y, double z, const V3 *tp) {
      MatR r = c0(x, y, z, tp);
      r.d = (r.d + amt * (fbm(x / sz, y / sz, z / sz) * 2 - 1)) * lip;
      return r;
    };
  }
  if (kind == "pattern") {
    auto pp = patternOf(P);
    double lip = patternLip(pp);
    return [=](double x, double y, double z, const V3 *tp) {
      MatR r = c0(x, y, z, tp);
      r.d = (r.d + pp.depth * patternG({x, y, z}, pp)) * lip;
      return r;
    };
  }
  if (kind == "union") {
    double kk = P.num("k");
    if (kk)
      return [kids, kk](double x, double y, double z, const V3 *tp) {
        MatR a;
        for (size_t i = 0; i < kids.size(); i++) {
          MatR r = kids[i](x, y, z, tp);
          if (i == 0) { a = r; continue; }
          double h = clampd(0.5 + (0.5 * (r.d - a.d)) / kk, 0, 1);
          MatR o = h > 0.5 ? a : r;
          o.d = mixd(r.d, a.d, h) - kk * h * (1 - h);
          o.c = mix3(r.c, a.c, h);
          a = o;
        }
        return a;
      };
    std::vector<DistFn> bounds;
    for (auto &c : s.children) bounds.push_back(cullBox(*c));
    return [kids, bounds](double x, double y, double z, const V3 *tp) {
      bool have = false;
      MatR best;
      for (size_t i = 0; i < kids.size(); i++) {
        if (have && bounds[i] && bounds[i](x, y, z) >= best.d) continue;
        MatR r = kids[i](x, y, z, tp);
        if (!have || r.d < best.d) { best = r; have = true; }
      }
      return best;
    };
  }
  if (kind == "merge") {
    MergeP mp{P.num("r"), P["seamWidth"].isNone() ? 0 : P.num("seamWidth"), P["profile"].s() == "round" ? 0 : P["profile"].s() == "chamfer" ? 1 : 2,
              P["colors"].s() == "blend", !P["seam"].isNone(), P["seam"].isNone() ? V3{0, 0, 0} : P.v3("seam")};
    return [kids, mp](double x, double y, double z, const V3 *tp) {
      MatR acc;
      for (size_t i = 0; i < kids.size(); i++) {
        MatR r = kids[i](x, y, z, tp);
        if (!i) { acc = r; continue; }
        MatR out = acc.d < r.d ? acc : r;
        out.d = mergeD(acc.d, r.d, mp);
        if (mp.blend) {
          double h = clampd(0.5 + (0.5 * (r.d - acc.d)) / mp.r, 0, 1);
          out.c = mix3(r.c, acc.c, h);
        }
        if (mp.seam) {
          double l = std::hypot(acc.d, r.d);
          out.c = mix3(out.c, mp.seamC, 1 - smoothstep(mp.sw * 0.5, mp.sw, l));
        }
        acc = out;
      }
      return acc;
    };
  }
  if (kind == "subtract") {
    MatFn a = kids[0], b = kids[1];
    double kk = P.num("k");
    return [=](double x, double y, double z, const V3 *tp) {
      MatR ra = a(x, y, z, tp);
      double db = b(x, y, z, tp).d;
      ra.d = kk ? smax(ra.d, -db, kk) : std::max(ra.d, -db);
      return ra;
    };
  }
  if (kind == "intersect") {
    double kk = P.num("k");
    return [kids, kk](double x, double y, double z, const V3 *tp) {
      MatR acc;
      for (size_t i = 0; i < kids.size(); i++) {
        MatR r = kids[i](x, y, z, tp);
        if (i == 0) { acc = r; continue; }
        acc.d = kk ? smax(acc.d, r.d, kk) : std::max(acc.d, r.d);
      }
      return acc;
    };
  }
  throw std::runtime_error("sdf: tipo desconhecido " + kind);
}

MatFn buildMat(const ShapeP &s, double t) { return buildMatIn(s, t, MatIn{}); }

V3 surfaceColor(const MatR &r, const V3 *n) {
  if (!r.hasTex || !r.hasTp) return r.c;
  return texColor(r.tp, r.c, r.c2, r.tx, n);
}

// ---------- BVH na CPU ----------

static double boxDistArr(const V3 &mn, const V3 &mx, double x, double y, double z) {
  return sdBox(x - (mn[0] + mx[0]) / 2, y - (mn[1] + mx[1]) / 2, z - (mn[2] + mx[2]) / 2, (mx[0] - mn[0]) / 2 + 0.005, (mx[1] - mn[1]) / 2 + 0.005,
               (mx[2] - mn[2]) / 2 + 0.005);
}

namespace {
struct Inst {
  DistFn d;
  std::function<MatR(double, double, double, double)> mat;
  V3 min, max, c;
};
struct TreeN {
  V3 min, max;
  std::vector<const Inst *> items;
  std::unique_ptr<TreeN> left, right;
};
}  // namespace

static Inst makeInstance(const Occ &it) {
  M3 mi = inv3(it.m);
  V3 tt = it.t;
  DistFn prim = primDist(*it.s);
  double ds = it.ds;
  Inst out;
  out.d = [=](double x, double y, double z) {
    double a = x - tt[0], b = y - tt[1], c = z - tt[2];
    return prim(mi[0] * a + mi[1] * b + mi[2] * c, mi[3] * a + mi[4] * b + mi[5] * c, mi[6] * a + mi[7] * b + mi[8] * c) * ds;
  };
  std::vector<V3> pts;
  for (auto &p : corners(it.s->bbox())) {
    V3 q = mulMV(it.m, p);
    pts.push_back({q[0] + tt[0], q[1] + tt[1], q[2] + tt[2]});
  }
  BBox b = fromPoints(pts);
  out.min = b.min;
  out.max = b.max;
  out.c = center(b);
  const Props &P = it.mat.p;
  MatR base;
  if (!P["color"].isNone()) base.c = P.v3("color");
  if (!P["rough"].isNone()) base.rough = P.num("rough");
  if (!P["metal"].isNone()) base.metal = P.num("metal");
  base.glow = P["glow"].isNone() ? 0 : at(P["glow"], 0);
  base.facet = P["facet"];
  base.coat = P["coat"].isNone() ? 0 : P.num("coat");
  bool hasTex = !P["tex"].isNone();
  if (hasTex) {
    auto tex = P["tex"].as<Rec>();
    base.hasTex = true;
    base.c2 = texC2(*tex, base.c);
    base.tx = texTx(*tex);
  }
  TexFrame tf = it.mat.texFrame ? *it.mat.texFrame : TexFrame{IDENT, {0, 0, 0}};
  M3 ti = inv3(tf.m);
  out.mat = [base, hasTex, tf, ti](double x, double y, double z, double dd) {
    MatR r = base;
    r.d = dd;
    if (hasTex) {
      double a = x - tf.t[0], b = y - tf.t[1], c = z - tf.t[2];
      r.hasTp = true;
      r.tp = {ti[0] * a + ti[1] * b + ti[2] * c, ti[3] * a + ti[4] * b + ti[5] * c, ti[6] * a + ti[7] * b + ti[8] * c};
    }
    return r;
  };
  return out;
}

static std::unique_ptr<TreeN> buildTree(std::vector<const Inst *> items) {
  auto n = std::make_unique<TreeN>();
  n->min = {INFINITY, INFINITY, INFINITY};
  n->max = {-INFINITY, -INFINITY, -INFINITY};
  for (auto *x : items)
    for (int i = 0; i < 3; i++) { n->min[i] = std::min(n->min[i], x->min[i]); n->max[i] = std::max(n->max[i], x->max[i]); }
  if (items.size() <= 4) { n->items = items; return n; }
  V3 cmin{INFINITY, INFINITY, INFINITY}, cmax{-INFINITY, -INFINITY, -INFINITY};
  for (auto *x : items)
    for (int i = 0; i < 3; i++) { cmin[i] = std::min(cmin[i], x->c[i]); cmax[i] = std::max(cmax[i], x->c[i]); }
  int axis = 0;
  for (int i = 1; i < 3; i++)
    if (cmax[i] - cmin[i] > cmax[axis] - cmin[axis]) axis = i;
  std::stable_sort(items.begin(), items.end(), [axis](const Inst *a, const Inst *b) { return a->c[axis] < b->c[axis]; });
  size_t mid = items.size() >> 1;
  n->left = buildTree(std::vector<const Inst *>(items.begin(), items.begin() + mid));
  n->right = buildTree(std::vector<const Inst *>(items.begin() + mid, items.end()));
  return n;
}

SceneFns buildSceneFns(const ShapeP &shape) {
  Split sp = splitScene({shape});
  if (sp.instances.size() < 16) {
    MatFn mat = buildMat(shape);
    return {buildDist(shape), [mat](double x, double y, double z) {
              V3 p{x, y, z};
              return mat(x, y, z, &p);
            }};
  }
  auto inst = std::make_shared<std::vector<Inst>>();
  for (auto &o : sp.instances) inst->push_back(makeInstance(o));
  std::vector<const Inst *> ptrs;
  for (auto &i : *inst) ptrs.push_back(&i);
  std::shared_ptr<TreeN> root = buildTree(ptrs);
  std::vector<DistFn> resD;
  std::vector<MatFn> resM;
  for (auto &r : sp.residual) { resD.push_back(buildDist(r)); resM.push_back(buildMat(r)); }
  struct Trav {
    static double go(const TreeN &n, double x, double y, double z, double best, const Inst *&hit) {
      if (n.left == nullptr) {
        for (auto *it : n.items) {
          double d = it->d(x, y, z);
          if (d < best) { best = d; hit = it; }
        }
        return best;
      }
      double dl = boxDistArr(n.left->min, n.left->max, x, y, z), dr = boxDistArr(n.right->min, n.right->max, x, y, z);
      const TreeN *a = dl < dr ? n.left.get() : n.right.get(), *b = dl < dr ? n.right.get() : n.left.get();
      double da = dl < dr ? dl : dr, db = dl < dr ? dr : dl;
      if (da < best) best = go(*a, x, y, z, best, hit);
      if (db < best) best = go(*b, x, y, z, best, hit);
      return best;
    }
  };
  DistFn dist = [inst, root, resD](double x, double y, double z) {
    double best = 1e10;
    for (auto &f : resD) { double d = f(x, y, z); if (d < best) best = d; }
    const Inst *hit = nullptr;
    if (boxDistArr(root->min, root->max, x, y, z) < best) best = Trav::go(*root, x, y, z, best, hit);
    return best;
  };
  auto mat = [inst, root, resM](double x, double y, double z) {
    bool have = false;
    MatR best;
    for (auto &f : resM) {
      MatR r = f(x, y, z, nullptr);
      if (!have || r.d < best.d) { best = r; have = true; }
    }
    const Inst *hit = nullptr;
    double d = Trav::go(*root, x, y, z, have ? best.d : 1e10, hit);
    return hit ? hit->mat(x, y, z, d) : best;
  };
  return {dist, mat};
}

}  // namespace tdi
