#include "profile.h"

#include <algorithm>
#include <cmath>

#include "expr.h"

namespace tdi {

std::vector<P2> parsePoints(const Value &v, const std::string &what, int min, int max) {
  bool ok = v.isList();
  if (ok)
    for (auto &p : v.list()->items) ok &= p.isList() && p.size() == 2;
  if (!ok) throw ScriptError(what + " espera uma lista de pontos (x, y), por exemplo [(0, 0), (1, 0), (0.5, 1)]");
  std::vector<P2> pts;
  for (size_t i = 0; i < v.size(); i++) {
    auto &p = v[i];
    P2 q{num(p[0], what + "[" + std::to_string(i) + "][0]"), num(p[1], what + "[" + std::to_string(i) + "][1]")};
    if (pts.empty() || std::hypot(q[0] - pts.back()[0], q[1] - pts.back()[1]) > 1e-9) pts.push_back(q);
  }
  if (pts.size() > 1 && std::hypot(pts[0][0] - pts.back()[0], pts[0][1] - pts.back()[1]) < 1e-9) pts.pop_back();
  if ((int)pts.size() < min) throw ScriptError(what + " precisa de pelo menos " + std::to_string(min) + " pontos diferentes");
  if ((int)pts.size() > max)
    throw ScriptError(what + " aceita no máximo " + std::to_string(max) + " pontos (recebeu " + std::to_string(pts.size()) + ")", 0, "use menos pontos ou suavize com smooth=");
  return pts;
}

std::vector<P2> regularPolygon(int sides, double r) {
  std::vector<P2> out;
  for (int i = 0; i < sides; i++) {
    double a = (double(i) / sides) * 2 * M_PI;
    out.push_back({r * std::cos(a), r * std::sin(a)});
  }
  return out;
}

std::vector<P2> starPoints(int n, double r, double inner) {
  std::vector<P2> out;
  for (int i = 0; i < n * 2; i++) {
    double a = (double(i) / (n * 2)) * 2 * M_PI, rr = i % 2 ? inner : r;
    out.push_back({rr * std::cos(a), rr * std::sin(a)});
  }
  return out;
}

std::vector<P2> smoothOpen(const std::vector<P2> &pts, int n) {
  if (n < 1 || pts.size() < 3) return pts;
  std::vector<P2> out{pts[0]};
  int N = (int)pts.size();
  auto P = [&](int i) { return pts[std::max(0, std::min(N - 1, i))]; };
  for (int i = 0; i < N - 1; i++) {
    P2 p0 = P(i - 1), p1 = P(i), p2 = P(i + 1), p3 = P(i + 2);
    for (int k = 1; k <= n; k++) {
      double t = double(k) / n, t2 = t * t, t3 = t2 * t;
      P2 q;
      for (int c = 0; c < 2; c++)
        q[c] = 0.5 * (2 * p1[c] + (-p0[c] + p2[c]) * t + (2 * p0[c] - 5 * p1[c] + 4 * p2[c] - p3[c]) * t2 + (-p0[c] + 3 * p1[c] - 3 * p2[c] + p3[c]) * t3);
      out.push_back(q);
    }
  }
  return out;
}

std::vector<P2> lathePolygon(const std::vector<P2> &profile) {
  std::vector<P2> all;
  for (auto &p : profile) all.push_back({std::max(0.0, p[0]), p[1]});
  for (int i = (int)profile.size() - 1; i >= 0; i--) all.push_back({-std::max(0.0, profile[i][0]), profile[i][1]});
  std::vector<P2> dedup;
  for (auto &p : all)
    if (dedup.empty() || std::hypot(p[0] - dedup.back()[0], p[1] - dedup.back()[1]) > 1e-9) dedup.push_back(p);
  while (dedup.size() > 1 && std::hypot(dedup[0][0] - dedup.back()[0], dedup[0][1] - dedup.back()[1]) < 1e-9) dedup.pop_back();
  return dedup;
}

Bounds2 boundsOf(const std::vector<P2> &pts) {
  Bounds2 b{INFINITY, -INFINITY, INFINITY, -INFINITY};
  for (auto &p : pts) {
    b.minX = std::min(b.minX, p[0]); b.maxX = std::max(b.maxX, p[0]);
    b.minY = std::min(b.minY, p[1]); b.maxY = std::max(b.maxY, p[1]);
  }
  return b;
}

double polygonSDF(const std::vector<P2> &pts, double px, double py) {
  size_t n = pts.size();
  double d = (px - pts[0][0]) * (px - pts[0][0]) + (py - pts[0][1]) * (py - pts[0][1]);
  double s = 1;
  for (size_t i = 0, j = n - 1; i < n; j = i, i++) {
    double ex = pts[j][0] - pts[i][0], ey = pts[j][1] - pts[i][1];
    double wx = px - pts[i][0], wy = py - pts[i][1];
    double t = std::max(0.0, std::min(1.0, (wx * ex + wy * ey) / (ex * ex + ey * ey)));
    double bx = wx - ex * t, by = wy - ey * t;
    d = std::min(d, bx * bx + by * by);
    bool c1 = py >= pts[i][1], c2 = py < pts[j][1], c3 = ex * wy > ey * wx;
    if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) s = -s;
  }
  return s * std::sqrt(d);
}

std::string polygonGlsl(const std::string &name, const std::vector<P2> &pts) {
  size_t n = pts.size();
  std::string vs;
  for (size_t i = 0; i < n; i++) vs += (i ? ", " : "") + std::string("vec2(") + glslNum(pts[i][0]) + ", " + glslNum(pts[i][1]) + ")";
  std::string N = std::to_string(n), N1 = std::to_string(n - 1);
  return "float " + name + "(vec2 p) {\n  const vec2 v[" + N + "] = vec2[" + N + "](" + vs + ");\n"
         "  float d = dot(p - v[0], p - v[0]);\n  float s = 1.0;\n  for (int i = 0, j = " + N1 + "; i < " + N + "; j = i, i++) {\n"
         "    vec2 e = v[j] - v[i];\n    vec2 w = p - v[i];\n    vec2 b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);\n"
         "    d = min(d, dot(b, b));\n    bvec3 c = bvec3(p.y >= v[i].y, p.y < v[j].y, e.x * w.y > e.y * w.x);\n"
         "    if (all(c) || all(not(c))) s = -s;\n  }\n  return s * sqrt(d);\n}";
}

double extrudeDist(double d2, double hz, double half, double r) {
  double wx = d2 + r, wy = std::fabs(hz) - (half - r);
  return std::min(std::max(wx, wy), 0.0) + std::hypot(std::max(wx, 0.0), std::max(wy, 0.0)) - r;
}

Value pointsValue(const std::vector<P2> &pts) {
  std::vector<Value> out;
  for (auto &p : pts) out.push_back(list({p[0], p[1]}));
  return list(out);
}

std::vector<P2> pointsOf(const Value &v) {
  std::vector<P2> out;
  for (auto &p : v.list()->items) out.push_back({p[0].n(), p[1].n()});
  return out;
}

}  // namespace tdi
