#include "hull.h"

#include <algorithm>
#include <cmath>

namespace tdi {

static V3 sub(const V3 &a, const V3 &b) { return {a[0] - b[0], a[1] - b[1], a[2] - b[2]}; }
static double dot(const double *a, const V3 &b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }
static V3 cross(const double *a, const V3 &b) { return {a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]}; }

Hull convexHull(const std::vector<V3> &input, const std::string &what) {
  Hull h;
  double ext = 0;
  for (auto &p : input)
    for (auto &q : input) ext = std::max({ext, std::fabs(p[0] - q[0]), std::fabs(p[1] - q[1]), std::fabs(p[2] - q[2])});
  double eps = std::max(1e-9, ext * 1e-7);
  for (auto &p : input) {
    bool dup = std::any_of(h.pts.begin(), h.pts.end(), [&](const V3 &q) {
      return std::fabs(p[0] - q[0]) <= eps && std::fabs(p[1] - q[1]) <= eps && std::fabs(p[2] - q[2]) <= eps;
    });
    if (!dup) h.pts.push_back(p);
  }
  if (h.pts.size() < 4) throw ScriptError(what + " precisa de pelo menos 4 pontos diferentes");
  size_t n = h.pts.size();
  auto &pts = h.pts;
  auto same = [&](const std::array<double, 4> &a, const std::array<double, 4> &b) {
    return std::fabs(a[0] - b[0]) < 1e-6 && std::fabs(a[1] - b[1]) < 1e-6 && std::fabs(a[2] - b[2]) < 1e-6 && std::fabs(a[3] - b[3]) < eps * 10;
  };
  for (size_t i = 0; i < n; i++)
    for (size_t j = i + 1; j < n; j++)
      for (size_t k = j + 1; k < n; k++) {
        V3 u = sub(pts[j], pts[i]);
        V3 nn = cross(u.data(), sub(pts[k], pts[i]));
        double l = std::sqrt(nn[0] * nn[0] + nn[1] * nn[1] + nn[2] * nn[2]);
        if (l < eps * eps) continue;
        for (auto &v : nn) v /= l;
        double d = dot(nn.data(), pts[i]);
        bool above = false, below = false;
        for (auto &p : pts) {
          double s = dot(nn.data(), p) - d;
          if (s > eps) above = true;
          else if (s < -eps) below = true;
          if (above && below) break;
        }
        if (above && below) continue;
        std::array<double, 4> pl = below ? std::array<double, 4>{nn[0], nn[1], nn[2], d} : std::array<double, 4>{-nn[0], -nn[1], -nn[2], -d};
        if (!std::any_of(h.planes.begin(), h.planes.end(), [&](auto &q) { return same(q, pl); })) h.planes.push_back(pl);
      }
  if (h.planes.size() < 4) throw ScriptError(what + ": os pontos precisam formar um volume (não podem estar todos num plano)");
  for (auto &pl : h.planes) {
    std::vector<int> on;
    for (size_t i = 0; i < n; i++)
      if (std::fabs(dot(pl.data(), pts[i]) - pl[3]) <= eps) on.push_back((int)i);
    V3 c{0, 0, 0};
    for (int i : on)
      for (int a = 0; a < 3; a++) c[a] += pts[i][a];
    for (auto &v : c) v /= on.size();
    V3 ref = std::fabs(pl[0]) < 0.9 ? V3{1, 0, 0} : V3{0, 1, 0};
    V3 u = cross(pl.data(), ref);
    double ul = std::sqrt(u[0] * u[0] + u[1] * u[1] + u[2] * u[2]);
    for (auto &x : u) x /= ul;
    V3 v = cross(pl.data(), u);
    std::vector<std::pair<int, double>> ang;
    for (int i : on) {
      V3 d = sub(pts[i], c);
      ang.push_back({i, std::atan2(dot(d.data(), v), dot(d.data(), u))});
    }
    std::stable_sort(ang.begin(), ang.end(), [](auto &a, auto &b) { return a.second < b.second; });
    std::vector<int> f;
    for (auto &a : ang) f.push_back(a.first);
    h.faces.push_back(f);
  }
  return h;
}

std::vector<V3> ringPoints(double r, double y, int sides, double phase) {
  std::vector<V3> out;
  for (int i = 0; i < sides; i++) {
    double a = phase + (double(i) / sides) * 2 * M_PI;
    out.push_back({r * std::cos(a), y, r * std::sin(a)});
  }
  return out;
}

std::vector<V3> lowSphere(double r, int sides) {
  int rings = std::max(2, (int)std::floor(sides / 2.0 + 0.5));
  std::vector<V3> out{{0, -r, 0}, {0, r, 0}};
  for (int k = 1; k < rings; k++) {
    double t = -M_PI / 2 + (double(k) / rings) * M_PI;
    for (auto &p : ringPoints(r * std::cos(t), r * std::sin(t), sides, k % 2 ? 0 : M_PI / sides)) out.push_back(p);
  }
  return out;
}

std::vector<V3> chamferBoxPoints(const V3 &h, double c) {
  std::vector<V3> out;
  for (int sx : {-1, 1})
    for (int sy : {-1, 1})
      for (int sz : {-1, 1}) {
        out.push_back({sx * h[0], sy * (h[1] - c), sz * (h[2] - c)});
        out.push_back({sx * (h[0] - c), sy * h[1], sz * (h[2] - c)});
        out.push_back({sx * (h[0] - c), sy * (h[1] - c), sz * h[2]});
      }
  return out;
}

ShapeP hullShape(const std::vector<V3> &points, const std::string &what) {
  Hull h = convexHull(points, what);
  std::vector<Value> pts, planes, faces;
  for (auto &p : h.pts) pts.push_back(nums3(p));
  for (auto &q : h.planes) planes.push_back(nums({q[0], q[1], q[2], q[3]}));
  for (auto &f : h.faces) {
    std::vector<Value> ids(f.begin(), f.end());
    faces.push_back(list(ids));
  }
  return mkShape("hull", {{"pts", list(pts)}, {"planes", list(planes)}, {"faces", list(faces)}});
}

Hull hullOf(const Props &p) {
  Hull h;
  for (auto &v : p["pts"].list()->items) h.pts.push_back({v[0].n(), v[1].n(), v[2].n()});
  for (auto &v : p["planes"].list()->items) h.planes.push_back({v[0].n(), v[1].n(), v[2].n(), v[3].n()});
  for (auto &f : p["faces"].list()->items) {
    std::vector<int> ids;
    for (auto &i : f.list()->items) ids.push_back((int)i.n());
    h.faces.push_back(ids);
  }
  return h;
}

}  // namespace tdi
