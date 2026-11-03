// Malha direta: árvore de primitivas -> triângulos exatos, sem amostrar a distância (port de nativemesh.js).
#include <algorithm>
#include <cmath>
#include <map>
#include <stdexcept>

#include "anchor.h"
#include "expr.h"
#include "mesh.h"
#include "profile.h"

namespace tdi {

static const double SHARP_COS = std::cos((40 * M_PI) / 180);
struct Unsupported {};

namespace {
struct LMesh {
  std::vector<double> P, N;
  std::vector<int> I;
  bool hasScale = false;
  V3 scale{1, 1, 1};
};
}  // namespace

using P2v = std::array<double, 2>;

static int addVertex(LMesh &M, const V3 &p, const V3 &n) {
  M.P.insert(M.P.end(), {p[0], p[1], p[2]});
  M.N.insert(M.N.end(), {n[0], n[1], n[2]});
  return (int)(M.P.size() / 3) - 1;
}
static V3 faceNormal(const V3 &a, const V3 &b, const V3 &c) {
  V3 u{b[0] - a[0], b[1] - a[1], b[2] - a[2]}, v{c[0] - a[0], c[1] - a[1], c[2] - a[2]};
  V3 n{u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]};
  double l = std::sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
  if (l == 0) l = 1;
  return {n[0] / l, n[1] / l, n[2] / l};
}
static void addFlat(LMesh &M, const std::vector<V3> &pts) {
  V3 n = faceNormal(pts[0], pts[1], pts[2]);
  std::vector<int> ids;
  for (auto &p : pts) ids.push_back(addVertex(M, p, n));
  for (size_t k = 1; k + 1 < ids.size(); k++) M.I.insert(M.I.end(), {ids[0], ids[k], ids[k + 1]});
}

static void revolve(LMesh &M, const std::vector<P2v> &profile, int seg) {
  std::vector<P2v> pts;
  for (size_t i = 0; i < profile.size(); i++)
    if (i == 0 || std::hypot(profile[i][0] - profile[i - 1][0], profile[i][1] - profile[i - 1][1]) > 1e-12) pts.push_back(profile[i]);
  int nSeg = (int)pts.size() - 1;
  if (nSeg < 1) return;
  std::vector<P2v> segN;
  for (int i = 0; i < nSeg; i++) {
    double dr = pts[i + 1][0] - pts[i][0], dy = pts[i + 1][1] - pts[i][1], l = std::hypot(dr, dy);
    if (l == 0) l = 1;
    segN.push_back({dy / l, -dr / l});
  }
  auto endN = [&](int i, bool end) -> P2v {
    P2v n = segN[i];
    int j = end ? i + 1 : i - 1;
    if (j < 0 || j >= nSeg) return n;
    P2v m = segN[j];
    if (n[0] * m[0] + n[1] * m[1] < SHARP_COS) return n;
    P2v s{n[0] + m[0], n[1] + m[1]};
    double l = std::hypot(s[0], s[1]);
    if (l == 0) l = 1;
    return {s[0] / l, s[1] / l};
  };
  for (int i = 0; i < nSeg; i++) {
    double r0 = pts[i][0], y0 = pts[i][1], r1 = pts[i + 1][0], y1 = pts[i + 1][1];
    P2v n0 = endN(i, false), n1 = endN(i, true);
    std::vector<int> ring0, ring1;
    for (int j = 0; j <= seg; j++) {
      double a = (double(j) / seg) * 2 * M_PI, c = std::cos(a), s = std::sin(a);
      ring0.push_back(addVertex(M, {r0 * c, y0, r0 * s}, {n0[0] * c, n0[1], n0[0] * s}));
      ring1.push_back(addVertex(M, {r1 * c, y1, r1 * s}, {n1[0] * c, n1[1], n1[0] * s}));
    }
    for (int j = 0; j < seg; j++) {
      int a = ring0[j], b = ring0[j + 1], c = ring1[j + 1], d = ring1[j];
      if (r0 > 1e-12) M.I.insert(M.I.end(), {a, d, b});
      if (r1 > 1e-12) M.I.insert(M.I.end(), {b, d, c});
    }
  }
}

static std::vector<P2v> arc(double cx, double cy, double r, double a0, double a1, int steps) {
  std::vector<P2v> out;
  for (int k = 0; k <= steps; k++) {
    double a = a0 + ((a1 - a0) * k) / steps;
    out.push_back({cx + r * std::cos(a), cy + r * std::sin(a)});
  }
  return out;
}

static std::vector<std::array<int, 3>> triangulate(const std::vector<P2v> &poly) {
  int n = (int)poly.size();
  double area = 0;
  for (int i = 0; i < n; i++) { auto &a = poly[i], &b = poly[(i + 1) % n]; area += a[0] * b[1] - b[0] * a[1]; }
  std::vector<int> idx(n);
  for (int i = 0; i < n; i++) idx[i] = i;
  if (area < 0) std::reverse(idx.begin(), idx.end());
  std::vector<std::array<int, 3>> tris;
  auto cross = [](const P2v &a, const P2v &b, const P2v &c) { return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]); };
  auto inside = [&](const P2v &p, const P2v &a, const P2v &b, const P2v &c) { return cross(a, b, p) > 1e-14 && cross(b, c, p) > 1e-14 && cross(c, a, p) > 1e-14; };
  int guard = 0;
  while (idx.size() > 3 && guard++ < n * n) {
    bool cut = false;
    for (size_t k = 0; k < idx.size(); k++) {
      int i0 = idx[(k + idx.size() - 1) % idx.size()], i1 = idx[k], i2 = idx[(k + 1) % idx.size()];
      const P2v &a = poly[i0], &b = poly[i1], &c = poly[i2];
      if (cross(a, b, c) <= 1e-14) continue;
      bool any = false;
      for (int j : idx)
        if (j != i0 && j != i1 && j != i2 && inside(poly[j], a, b, c)) { any = true; break; }
      if (any) continue;
      tris.push_back({i0, i1, i2});
      idx.erase(idx.begin() + k);
      cut = true;
      break;
    }
    if (!cut) break;
  }
  if (idx.size() == 3) tris.push_back({idx[0], idx[1], idx[2]});
  return tris;
}

static LMesh roundedBox(const V3 &h, double r, int seg) {
  LMesh M;
  int q = std::max(3, (int)std::ceil(seg / 8.0));
  auto samples = [&](double e) {
    double inner = std::max(0.0, e - r);
    std::vector<double> out;
    for (int k = q; k >= 1; k--) out.push_back(-(inner + r * std::sin((double(k) / q) * M_PI / 2)));
    out.push_back(-inner);
    if (inner > 1e-9) out.push_back(inner);
    for (int k = 1; k <= q; k++) out.push_back(inner + r * std::sin((double(k) / q) * M_PI / 2));
    return out;
  };
  std::vector<double> S[3] = {samples(h[0]), samples(h[1]), samples(h[2])};
  V3 core{std::max(0.0, h[0] - r), std::max(0.0, h[1] - r), std::max(0.0, h[2] - r)};
  auto place = [&](const V3 &p, V3 &pos, V3 &n) {
    V3 c, d;
    for (int i = 0; i < 3; i++) { c[i] = std::max(-core[i], std::min(core[i], p[i])); d[i] = p[i] - c[i]; }
    double l = std::sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
    if (l == 0) l = 1;
    for (int i = 0; i < 3; i++) { n[i] = d[i] / l; pos[i] = c[i] + n[i] * r; }
  };
  static const int AX[3][3] = {{0, 1, 2}, {1, 2, 0}, {2, 0, 1}};
  for (auto &axs : AX)
    for (int sg : {1, -1}) {
      int a = axs[0], u = axs[1], v = axs[2];
      std::vector<std::vector<int>> ids;
      for (size_t i = 0; i < S[u].size(); i++) {
        ids.emplace_back();
        for (size_t j = 0; j < S[v].size(); j++) {
          V3 p{0, 0, 0};
          p[a] = sg * h[a];
          p[u] = S[u][i];
          p[v] = S[v][j];
          V3 pos, n;
          place(p, pos, n);
          ids[i].push_back(addVertex(M, pos, n));
        }
      }
      for (size_t i = 0; i + 1 < S[u].size(); i++)
        for (size_t j = 0; j + 1 < S[v].size(); j++) {
          int A = ids[i][j], B = ids[i + 1][j], C = ids[i + 1][j + 1], D = ids[i][j + 1];
          if (sg > 0) M.I.insert(M.I.end(), {A, B, C, A, C, D});
          else M.I.insert(M.I.end(), {A, C, B, A, D, C});
        }
    }
  return M;
}

static LMesh primitive(const Shape &s, int seg) {
  const Props &P = s.props;
  LMesh M;
  const std::string &k = s.kind;
  if (k == "box") {
    V3 sz = P.v3("size");
    double r = P.num("r");
    if (r > 1e-9) return roundedBox({sz[0] / 2, sz[1] / 2, sz[2] / 2}, r, seg);
    double x = sz[0] / 2, y = sz[1] / 2, z = sz[2] / 2;
    auto c = [&](double sx, double sy, double sz2) { return V3{sx * x, sy * y, sz2 * z}; };
    addFlat(M, {c(1, -1, -1), c(1, 1, -1), c(1, 1, 1), c(1, -1, 1)});
    addFlat(M, {c(-1, -1, 1), c(-1, 1, 1), c(-1, 1, -1), c(-1, -1, -1)});
    addFlat(M, {c(-1, 1, -1), c(-1, 1, 1), c(1, 1, 1), c(1, 1, -1)});
    addFlat(M, {c(-1, -1, 1), c(-1, -1, -1), c(1, -1, -1), c(1, -1, 1)});
    addFlat(M, {c(-1, -1, 1), c(1, -1, 1), c(1, 1, 1), c(-1, 1, 1)});
    addFlat(M, {c(1, -1, -1), c(-1, -1, -1), c(-1, 1, -1), c(1, 1, -1)});
    return M;
  }
  if (k == "pyramid") {
    double w = P.num("w") / 2, y0 = -P.num("h") / 2;
    V3 apex{0, P.num("h") / 2, 0};
    V3 b[4] = {{-w, y0, -w}, {w, y0, -w}, {w, y0, w}, {-w, y0, w}};
    for (int i = 0; i < 4; i++) addFlat(M, {b[(i + 1) % 4], b[i], apex});
    addFlat(M, {b[0], b[1], b[2], b[3]});
    return M;
  }
  if (k == "prism") {
    double w = P.num("w") / 2, h = P.num("h") / 2, d = P.num("d") / 2;
    V3 f[3] = {{-w, -h, d}, {w, -h, d}, {0, h, d}}, kk[3] = {{-w, -h, -d}, {w, -h, -d}, {0, h, -d}};
    addFlat(M, {f[0], f[1], f[2]});
    addFlat(M, {kk[0], kk[2], kk[1]});
    addFlat(M, {kk[0], kk[1], f[1], f[0]});
    addFlat(M, {f[1], kk[1], kk[2], f[2]});
    addFlat(M, {kk[0], f[0], f[2], kk[2]});
    return M;
  }
  if (k == "sphere") { revolve(M, arc(0, 0, P.num("r"), -M_PI / 2, M_PI / 2, (int)std::ceil(seg / 2.0)), seg); return M; }
  if (k == "ellipsoid") {
    revolve(M, arc(0, 0, 1, -M_PI / 2, M_PI / 2, (int)std::ceil(seg / 2.0)), seg);
    M.hasScale = true;
    M.scale = P.v3("radii");
    return M;
  }
  if (k == "cylinder") {
    double h = P.num("h") / 2, r = P.num("r"), rr = std::min({P.num("round"), r, h});
    if (rr > 1e-9) {
      int q = std::max(3, (int)std::ceil(seg / 8.0));
      std::vector<P2v> prof{{0, -h}};
      for (auto &p : arc(r - rr, -h + rr, rr, -M_PI / 2, 0, q)) prof.push_back(p);
      for (auto &p : arc(r - rr, h - rr, rr, 0, M_PI / 2, q)) prof.push_back(p);
      prof.push_back({0, h});
      revolve(M, prof, seg);
    } else revolve(M, {{0, -h}, {r, -h}, {r, h}, {0, h}}, seg);
    return M;
  }
  if (k == "cone") {
    double h = P.num("h") / 2, top = P.num("top");
    std::vector<P2v> prof{{0, -h}, {P.num("r"), -h}, {top, h}};
    if (top > 1e-9) prof.push_back({0, h});
    revolve(M, prof, seg);
    return M;
  }
  if (k == "capsule") {
    double r = P.num("r"), a = P.num("h") / 2 - r;
    int q = (int)std::ceil(seg / 4.0);
    std::vector<P2v> prof = arc(0, -a, r, -M_PI / 2, 0, q);
    for (auto &p : arc(0, a, r, 0, M_PI / 2, q)) prof.push_back(p);
    revolve(M, prof, seg);
    return M;
  }
  if (k == "torus") {
    double R = P.num("R"), r = P.num("r");
    int ns = seg, nt = std::max(8, (int)std::ceil(seg / 2.0));
    std::vector<std::vector<int>> id;
    for (int i = 0; i <= ns; i++) {
      double u = (double(i) / ns) * 2 * M_PI, cu = std::cos(u), su = std::sin(u);
      id.emplace_back();
      for (int j = 0; j <= nt; j++) {
        double v = (double(j) / nt) * 2 * M_PI, cv = std::cos(v), sv = std::sin(v);
        id[i].push_back(addVertex(M, {(R + r * cv) * cu, r * sv, (R + r * cv) * su}, {cv * cu, sv, cv * su}));
      }
    }
    for (int i = 0; i < ns; i++)
      for (int j = 0; j < nt; j++) M.I.insert(M.I.end(), {id[i][j], id[i][j + 1], id[i + 1][j], id[i + 1][j], id[i][j + 1], id[i + 1][j + 1]});
    return M;
  }
  if (k == "extrude") {
    if (P.num("r") > 1e-9) throw Unsupported{};
    double h = P.num("h") / 2;
    bool zAxis = P["axis"].s() == "z";
    auto at = [&](const P2v &q, double side) { return zAxis ? V3{q[0], q[1], side * h} : V3{q[0], side * h, q[1]}; };
    auto poly0 = pointsOf(P["pts"]);
    std::vector<P2v> poly(poly0.begin(), poly0.end());
    double area = 0;
    for (size_t i = 0; i < poly.size(); i++) { auto &a = poly[i], &b = poly[(i + 1) % poly.size()]; area += a[0] * b[1] - b[0] * a[1]; }
    std::vector<P2v> ccw = poly;
    if (!(area > 0)) std::reverse(ccw.begin(), ccw.end());
    bool flip = !zAxis;
    for (auto &t : triangulate(ccw)) {
      std::vector<V3> top{at(ccw[t[0]], 1), at(ccw[t[1]], 1), at(ccw[t[2]], 1)}, bot{at(ccw[t[0]], -1), at(ccw[t[2]], -1), at(ccw[t[1]], -1)};
      addFlat(M, flip ? std::vector<V3>{top[0], top[2], top[1]} : top);
      addFlat(M, flip ? std::vector<V3>{bot[0], bot[2], bot[1]} : bot);
    }
    for (size_t i = 0; i < ccw.size(); i++) {
      const P2v &a = ccw[i], &b = ccw[(i + 1) % ccw.size()];
      std::vector<V3> quad{at(a, -1), at(b, -1), at(b, 1), at(a, 1)};
      addFlat(M, flip ? std::vector<V3>{quad[0], quad[3], quad[2], quad[1]} : quad);
    }
    return M;
  }
  if (k == "lathe") {
    if (P["profile"].isNone()) throw Unsupported{};
    auto prof0 = pointsOf(P["profile"]);
    std::vector<P2v> full;
    if (prof0[0][0] > 1e-9) full.push_back({0, prof0[0][1]});
    for (auto &p : prof0) full.push_back(p);
    if (prof0.back()[0] > 1e-9) full.push_back({0, prof0.back()[1]});
    revolve(M, full, seg);
    return M;
  }
  throw Unsupported{};
}

static double det3(const M3 &m) { return m[0] * (m[4] * m[8] - m[5] * m[7]) - m[1] * (m[3] * m[8] - m[5] * m[6]) + m[2] * (m[3] * m[7] - m[4] * m[6]); }

namespace {
struct Item { const Shape *s; M3 m; V3 t; };
}

static void collect(const Shape &s, const M3 &m, const V3 &t, std::vector<Item> &out) {
  const Props &P = s.props;
  const std::string &k = s.kind;
  const Shape *c0 = s.children.empty() ? nullptr : s.children[0].get();
  auto addT = [&](const V3 &mv) { return V3{t[0] + mv[0], t[1] + mv[1], t[2] + mv[2]}; };
  if (k == "translate") { collect(*c0, m, addT(mulMV(m, P.v3("v"))), out); return; }
  if (k == "rotate") {
    M3 r;
    if (P.has("angles")) { auto a = P.vec("angles"); r = rotMatrix(a[0], a[1], a[2]); }
    else r = P.m3("m");
    collect(*c0, mul3(m, r), t, out);
    return;
  }
  if (k == "scale") { V3 S = P.v3("s"); collect(*c0, mul3(m, {S[0], 0, 0, 0, S[1], 0, 0, 0, S[2]}), t, out); return; }
  if (k == "affine") { collect(*c0, mul3(m, P.m3("m")), addT(mulMV(m, P.v3("t"))), out); return; }
  if (k == "paint") {
    if (!P["relief"].isNone() && P.num("relief")) throw Unsupported{};
    collect(*c0, m, t, out);
    return;
  }
  if (k == "material" || k == "label" || k == "bound") { collect(*c0, m, t, out); return; }
  if (k == "union") {
    if (P.num("k")) throw Unsupported{};
    for (auto &c : s.children) collect(*c, m, t, out);
    return;
  }
  if (k == "repeat") {
    V3 n = P.v3("n"), s3 = P.v3("s"), sp, h;
    for (int i = 0; i < 3; i++) { sp[i] = n[i] > 1 ? s3[i] : 1; h[i] = (n[i] - 1) / 2; }
    for (int i = 0; i < n[0]; i++)
      for (int j = 0; j < n[1]; j++)
        for (int q = 0; q < n[2]; q++) collect(*c0, m, addT(mulMV(m, {(i - h[0]) * sp[0], (j - h[1]) * sp[1], (q - h[2]) * sp[2]})), out);
    return;
  }
  if (k == "mirror") {
    const BBox &b = c0->bbox();
    bool ax[3] = {P["axes"][0].b(), P["axes"][1].b(), P["axes"][2].b()};
    for (int a = 0; a < 3; a++)
      if (ax[a] && b.min[a] < -1e-6 && b.max[a] > 1e-6) throw Unsupported{};
    std::vector<V3> flips{{1, 1, 1}};
    for (int a = 0; a < 3; a++)
      if (ax[a]) {
        auto cur = flips;
        for (auto f : cur) { f[a] = -1; flips.push_back(f); }
      }
    for (auto &f : flips) collect(*c0, mul3(m, {f[0], 0, 0, 0, f[1], 0, 0, 0, f[2]}), t, out);
    return;
  }
  if (k == "polar") {
    const BBox &b = c0->bbox();
    double n = P.num("n"), sec = (2 * M_PI) / n;
    double mx = 0;
    for (auto &xz : {std::array<double, 2>{b.min[0], b.min[2]}, {b.max[0], b.min[2]}, {b.min[0], b.max[2]}, {b.max[0], b.max[2]}})
      mx = std::max(mx, std::fabs(std::atan2(xz[1], xz[0])));
    if (b.min[0] <= 0 || mx > sec / 2 + 1e-6) throw Unsupported{};
    for (int q = 0; q < n; q++) collect(*c0, mul3(m, rotMatrix(0, (-q * 360) / n, 0)), t, out);
    return;
  }
  if (k == "intersect") {
    if (P.num("k")) throw Unsupported{};
    size_t start = out.size();
    collect(*c0, m, t, out);
    std::vector<DistFn> clips;
    for (size_t i = 1; i < s.children.size(); i++) clips.push_back(buildDist(s.children[i]));
    M3 mi = inv3(m);
    std::vector<Item> kept;
    for (size_t i = start; i < out.size(); i++) {
      auto &it = out[i];
      V3 cl = center(it.s->bbox());
      V3 w = mulMV(it.m, cl);
      for (int a = 0; a < 3; a++) w[a] += it.t[a] - t[a];
      V3 local = mulMV(mi, w);
      bool ok = true;
      for (auto &d : clips)
        if (!(d(local[0], local[1], local[2]) <= 0)) { ok = false; break; }
      if (ok) kept.push_back(it);
    }
    out.resize(start);
    out.insert(out.end(), kept.begin(), kept.end());
    return;
  }
  if (!s.children.empty()) throw Unsupported{};
  out.push_back({&s, m, t});
}

std::optional<Mesh> nativeMesh(const ShapeP &shape, int seg) {
  std::vector<Item> items;
  try {
    collect(*shape, IDENT, {0, 0, 0}, items);
  } catch (const Unsupported &) {
    return std::nullopt;
  }
  if (items.empty()) return std::nullopt;
  std::map<const Shape *, LMesh> cache;
  size_t tris = 0, nv = 0;
  std::vector<const LMesh *> geoms;
  for (auto &it : items) {
    auto f = cache.find(it.s);
    if (f == cache.end()) {
      try {
        f = cache.emplace(it.s, primitive(*it.s, seg)).first;
      } catch (const Unsupported &) {
        return std::nullopt;
      }
    }
    tris += f->second.I.size() / 3;
    nv += f->second.P.size() / 3;
    geoms.push_back(&f->second);
  }
  Mesh out;
  out.positions.resize(nv * 3);
  out.normals.resize(nv * 3);
  out.indices.resize(tris * 3);
  size_t vo = 0, io = 0;
  for (size_t k = 0; k < items.size(); k++) {
    const LMesh &g = *geoms[k];
    const Item &it = items[k];
    M3 m = g.hasScale ? mul3(it.m, {g.scale[0], 0, 0, 0, g.scale[1], 0, 0, 0, g.scale[2]}) : it.m;
    M3 mi = inv3(m);
    bool flip = det3(m) < 0;
    size_t base = vo;
    for (size_t v = 0; v < g.P.size(); v += 3) {
      V3 p = mulMV(m, {g.P[v], g.P[v + 1], g.P[v + 2]});
      for (int a = 0; a < 3; a++) out.positions[vo * 3 + a] = (float)(p[a] + it.t[a]);
      V3 n{g.N[v], g.N[v + 1], g.N[v + 2]};
      V3 nn{mi[0] * n[0] + mi[3] * n[1] + mi[6] * n[2], mi[1] * n[0] + mi[4] * n[1] + mi[7] * n[2], mi[2] * n[0] + mi[5] * n[1] + mi[8] * n[2]};
      double l = std::sqrt(nn[0] * nn[0] + nn[1] * nn[1] + nn[2] * nn[2]);
      if (l == 0) l = 1;
      for (int a = 0; a < 3; a++) out.normals[vo * 3 + a] = (float)(nn[a] / l);
      vo++;
    }
    for (size_t i = 0; i < g.I.size(); i += 3) {
      out.indices[io++] = (uint32_t)(base + g.I[i]);
      out.indices[io++] = (uint32_t)(base + (flip ? g.I[i + 2] : g.I[i + 1]));
      out.indices[io++] = (uint32_t)(base + (flip ? g.I[i + 1] : g.I[i + 2]));
    }
  }
  out.instances = (int)items.size();
  return out;
}

}  // namespace tdi
