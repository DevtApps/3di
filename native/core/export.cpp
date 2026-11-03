// Port de export.js e gltf.js.
#include "export.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstring>
#include <map>
#include <mutex>
#include <set>
#include <stdexcept>
#include <thread>

#include "anchor.h"
#include "compiler.h"
#include "expr.h"
#include "mesh.h"
#include "rig.h"
#include "sdf.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STB_IMAGE_WRITE_STATIC
#include "stb_image_write.h"

namespace tdi {

static const size_t EXPORT_CHUNK_TRIANGLES = 8192;
static const int MAX_PARTS = 64, SPLIT_MAX_CHILDREN = 24;

static std::vector<uint8_t> encodePng(int w, int h, const std::vector<uint8_t> &rgba) {
  int len = 0;
  unsigned char *png = stbi_write_png_to_mem(rgba.data(), w * 4, w, h, 4, &len);
  if (!png) throw std::runtime_error("não foi possível codificar o PNG");
  std::vector<uint8_t> out(png, png + len);
  STBIW_FREE(png);
  return out;
}

static int linearToSrgb(double x) {
  double v = std::max(0.0, std::min(1.0, x));
  return (int)std::floor(255 * (v <= 0.0031308 ? 12.92 * v : 1.055 * std::pow(v, 1 / 2.4) - 0.055) + 0.5);
}
static V3 sub3(const V3 &a, const V3 &b) { return {a[0] - b[0], a[1] - b[1], a[2] - b[2]}; }
static double dot3(const V3 &a, const V3 &b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }
static V3 cross3(const V3 &a, const V3 &b) { return {a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]}; }
static V3 norm3(const V3 &a) {
  double l = std::sqrt(dot3(a, a));
  if (l == 0) l = 1;
  return {a[0] / l, a[1] / l, a[2] / l};
}
static int jround(double x) { return (int)std::floor(x + 0.5); }

struct Height { double h, amp, e; };
struct Atlas {
  std::vector<float> uv;
  std::vector<uint8_t> png, normalPng;
};

static Atlas bakeTextureAtlas(const std::vector<float> &positions, const std::function<V3(double, double, double, const V3 &)> &sampleColor,
                             const std::function<Height(double, double, double, const V3 &)> *heightAt, const std::vector<float> &normals, int content) {
  int TILE = content + 2;
  size_t triangleCount = positions.size() / 9;
  int grid = (int)std::ceil(std::sqrt((double)triangleCount));
  int width = 1 << (int)std::ceil(std::log2((double)grid * TILE));
  Atlas out;
  out.uv.resize(triangleCount * 6);
  std::vector<uint8_t> rgba((size_t)width * width * 4, 0), nrgba(heightAt ? (size_t)width * width * 4 : 0, 0);
  auto coords = [&](int corner, int left, int top, float *dst) {
    double x0 = (left + 1.5) / width, x1 = (left + content + 0.5) / width;
    double v0 = (top + content + 0.5) / width, v1 = (top + 1.5) / width;
    if (corner == 0) { dst[0] = (float)x0; dst[1] = (float)v0; }
    else if (corner == 1) { dst[0] = (float)x1; dst[1] = (float)v0; }
    else { dst[0] = (float)x0; dst[1] = (float)v1; }
  };
  for (size_t tri = 0; tri < triangleCount; tri++) {
    int tileX = (int)(tri % grid) * TILE, tileY = (int)(tri / grid) * TILE;
    V3 pts[3];
    for (int c = 0; c < 3; c++) pts[c] = {positions[tri * 9 + c * 3], positions[tri * 9 + c * 3 + 1], positions[tri * 9 + c * 3 + 2]};
    for (int c = 0; c < 3; c++) coords(c, tileX, tileY, &out.uv[(tri * 3 + c) * 2]);
    V3 nf = norm3(cross3(sub3(pts[1], pts[0]), sub3(pts[2], pts[0])));
    if (!normals.empty()) {
      V3 vn{normals[tri * 9], normals[tri * 9 + 1], normals[tri * 9 + 2]};
      if (dot3(nf, vn) < 0) nf = {-nf[0], -nf[1], -nf[2]};
    }
    V3 T = norm3(sub3(pts[1], pts[0]));
    V3 e2 = sub3(pts[2], pts[0]);
    double te = dot3(e2, T);
    V3 B = norm3({e2[0] - T[0] * te, e2[1] - T[1] * te, e2[2] - T[2] * te});
    for (int py = 0; py < TILE; py++)
      for (int px = 0; px < TILE; px++) {
        double sx = std::max(-0.15, std::min(1.15, (px - 1) / double(content - 1)));
        double sy = std::max(-0.15, std::min(1.15, 1 - (py - 1) / double(content - 1)));
        double w[3] = {1 - sx - sy, sx, sy};
        V3 p{0, 0, 0};
        for (int a = 0; a < 3; a++)
          for (int i = 0; i < 3; i++) p[a] += pts[i][a] * w[i];
        V3 col = sampleColor(p[0], p[1], p[2], nf);
        size_t at = ((size_t)(tileY + py) * width + tileX + px) * 4;
        rgba[at] = (uint8_t)linearToSrgb(col[0]);
        rgba[at + 1] = (uint8_t)linearToSrgb(col[1]);
        rgba[at + 2] = (uint8_t)linearToSrgb(col[2]);
        rgba[at + 3] = 255;
        if (heightAt) {
          Height h0 = (*heightAt)(p[0], p[1], p[2], nf);
          double nx = 0, ny = 0;
          if (h0.amp > 0) {
            double e = h0.e;
            double gT = ((*heightAt)(p[0] + T[0] * e, p[1] + T[1] * e, p[2] + T[2] * e, nf).h - h0.h) / e;
            double gB = ((*heightAt)(p[0] + B[0] * e, p[1] + B[1] * e, p[2] + B[2] * e, nf).h - h0.h) / e;
            nx = std::max(-4.0, std::min(4.0, -h0.amp * gT));
            ny = std::max(-4.0, std::min(4.0, -h0.amp * gB));
          }
          double nl = std::sqrt(nx * nx + ny * ny + 1);
          nrgba[at] = (uint8_t)jround(((nx / nl) * 0.5 + 0.5) * 255);
          nrgba[at + 1] = (uint8_t)jround(((ny / nl) * 0.5 + 0.5) * 255);
          nrgba[at + 2] = (uint8_t)jround(((1 / nl) * 0.5 + 0.5) * 255);
          nrgba[at + 3] = 255;
        }
      }
  }
  out.png = encodePng(width, width, rgba);
  if (heightAt) out.normalPng = encodePng(width, width, nrgba);
  return out;
}

// ---------- análise da forma ----------

static double minScale(const Shape &s) {
  auto v = s.props.vec("s");
  return std::min({std::fabs(v[0]), std::fabs(v[1]), std::fabs(v[2])});
}

static double texDefault(int k) {
  static const double T[] = {0.25, 0.25, 0.06, 0.3, 0.1, 0.25, 0.25, 1, 0.3, 0.1};
  return k >= 1 && k <= 9 ? T[k] : 0.25;
}

static double smallestTexture(const Shape &s, double k = 1) {
  double m = INFINITY;
  if (s.kind == "material" && !s.props["tex"].isNone()) {
    auto t = s.props["tex"].as<Rec>();
    int kind = (int)t->f.num("kind");
    double sz = t->f["size"].isNone() ? texDefault(kind) : t->f.num("size");
    m = sz * k * (kind == 7 ? 0.5 : 1);
  }
  double kk = s.kind == "scale" ? k * minScale(s) : k;
  for (auto &c : s.children) m = std::min(m, smallestTexture(*c, kk));
  return m;
}

struct Facet { double size, vary; };
static std::optional<Facet> smallestFacet(const Shape &s, double k = 1) {
  std::optional<Facet> best;
  if (s.kind == "material" && !s.props["facet"].isNone()) {
    auto fc = s.props["facet"].as<Rec>();
    best = Facet{fc->f.num("size") * k, fc->f.num("vary")};
  }
  double kk = s.kind == "scale" ? k * minScale(s) : k;
  for (auto &c : s.children) {
    auto f = smallestFacet(*c, kk);
    if (f && (!best || f->size < best->size)) best = f;
  }
  return best;
}

static Mesh flatShade(const Mesh &mesh, double vary) {
  const auto &P = mesh.positions, &C = mesh.colors;
  const auto &I = mesh.indices;
  size_t n = I.size();
  Mesh out = mesh;
  out.positions.assign(n * 3, 0);
  out.normals.assign(n * 3, 0);
  out.colors.assign(C.empty() ? 0 : n * 3, 0);
  out.indices.resize(n);
  for (size_t t = 0; t < n; t += 3) {
    size_t a = I[t] * 3, b = I[t + 1] * 3, c = I[t + 2] * 3;
    double ux = P[b] - P[a], uy = P[b + 1] - P[a + 1], uz = P[b + 2] - P[a + 2];
    double vx = P[c] - P[a], vy = P[c + 1] - P[a + 1], vz = P[c + 2] - P[a + 2];
    double nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    double l = std::sqrt(nx * nx + ny * ny + nz * nz);
    if (l == 0) l = 1;
    nx /= l; ny /= l; nz /= l;
    double cx = (P[a] + P[b] + P[c]) / 3, cy = (P[a + 1] + P[b + 1] + P[c + 1]) / 3, cz = (P[a + 2] + P[b + 2] + P[c + 2]) / 3;
    double h = std::fmod(std::fabs(std::sin(cx * 127.1 + cy * 311.7 + cz * 74.7) * 43758.5453), 1);
    double tone = 1 + vary * (2 * h - 1);
    for (int k = 0; k < 3; k++) {
      size_t src = I[t + k] * 3, dst = (t + k) * 3;
      for (int q = 0; q < 3; q++) out.positions[dst + q] = P[src + q];
      out.normals[dst] = (float)nx; out.normals[dst + 1] = (float)ny; out.normals[dst + 2] = (float)nz;
      if (!C.empty())
        for (int q = 0; q < 3; q++) out.colors[dst + q] = (float)std::min(1.0, ((C[a + q] + C[b + q] + C[c + q]) / 3.0) * tone);
      out.indices[t + k] = (uint32_t)(t + k);
    }
  }
  return out;
}

static void fillets(const Shape &s, double k, std::vector<double> &out) {
  const Props &P = s.props;
  if ((s.kind == "box" || s.kind == "extrude" || s.kind == "round") && P.num("r") > 0) out.push_back(P.num("r") * k);
  if (s.kind == "cylinder" && P.num("round") > 0) out.push_back(P.num("round") * k);
  double kk = s.kind == "scale" ? k * minScale(s) : k;
  for (auto &c : s.children) fillets(*c, kk, out);
}

static bool hasPaint(const Shape &s) {
  if (s.kind == "paint" || (s.kind == "merge" && !s.props["seam"].isNone())) return true;
  for (auto &c : s.children)
    if (hasPaint(*c)) return true;
  return false;
}
static bool hasBound(const Shape &s) {
  if (s.kind == "bound") return true;
  for (auto &c : s.children)
    if (hasBound(*c)) return true;
  return false;
}
static bool isIdent(const M3 &m, const V3 &t) {
  for (int i = 0; i < 9; i++)
    if (std::fabs(m[i] - IDENT[i]) >= 1e-12) return false;
  return std::fabs(t[0]) < 1e-12 && std::fabs(t[1]) < 1e-12 && std::fabs(t[2]) < 1e-12;
}

static ShapeP wrap(const ShapeP &s, const M3 &m, const V3 &t, double ds, const Props &mat) {
  ShapeP node = s;
  if (!mat.kv.empty()) {
    Props p{{"color", Value()}, {"rough", Value()}, {"metal", Value()}, {"glow", Value()}, {"tex", Value()}, {"facet", Value()}, {"coat", Value()}};
    for (auto &[k, v] : mat.kv) p.set(k, v);
    node = mkShape("material", p, {node});
  }
  if (!isIdent(m, t)) node = mkShape("affine", {{"m", nums9(m)}, {"t", nums3(t)}, {"minv", nums9(inv3(m))}, {"ds", ds}}, {node});
  return node;
}

static void facetKinds(const Shape &s, const std::string &cur, std::set<std::string> &out) {
  std::string here = cur;
  if (s.kind == "material" && !s.props["facet"].isNone()) {
    auto fc = s.props["facet"].as<Rec>();
    here = jsNum(fc->f.num("size")) + "/" + jsNum(fc->f.num("vary"));
  }
  if (s.children.empty()) out.insert(here);
  size_t n = s.kind == "paint" ? std::min<size_t>(1, s.children.size()) : s.children.size();
  for (size_t i = 0; i < n; i++) facetKinds(*s.children[i], here, out);
}
static bool mixedFacets(const Shape &s) {
  if (s.kind != "union" || s.props.num("k")) return false;
  std::set<std::string> k;
  facetKinds(s, "-", k);
  return k.size() > 1;
}
static bool splittable(const Shape &s) { return s.kind == "union" && !s.props.num("k") && (mixedFacets(s) || s.children.size() <= (size_t)SPLIT_MAX_CHILDREN); }
static bool needsSplit(const Shape &s) {
  if (splittable(s)) return true;
  static const std::set<std::string> T = {"translate", "rotate", "scale", "material", "label"};
  return T.count(s.kind) && needsSplit(*s.children[0]);
}

namespace {
struct ExpPart {
  std::string kind;  // static, skin
  ShapeP shape;
  std::shared_ptr<Bone> bone;
  M3 outerM = IDENT;
  V3 outerT{0, 0, 0};
  bool hasName = false;
  std::string name;
  int root = 0;
};
}  // namespace

static Props mergeMatP(const Props &mat, const Props &P) {
  Props out = mat;
  for (const char *k : {"color", "rough", "metal", "glow", "tex", "facet", "coat"})
    if (!P[k].isNone()) out.set(k, P[k]);
  return out;
}

static std::vector<ExpPart> splitParts(const std::vector<ShapeP> &shapes) {
  std::vector<ExpPart> parts;
  int curRoot = 0;
  std::function<void(const ShapeP &, const M3 &, const V3 &, double, const Props &, const std::string *)> visit =
      [&](const ShapeP &s, const M3 &m, const V3 &t, double ds, const Props &mat, const std::string *name) {
        auto push = [&](ExpPart p) {
          p.root = curRoot;
          if (name) { p.hasName = true; p.name = *name; }
          parts.push_back(std::move(p));
        };
        if (!hasBound(*s) && (!needsSplit(*s) || (int)parts.size() >= MAX_PARTS)) {
          push({"static", wrap(s, m, t, ds, mat)});
          return;
        }
        const ShapeP &c0 = s->children.empty() ? s : s->children[0];
        const std::string &k = s->kind;
        if (k == "bound") {
          ExpPart p{"skin", wrap(resolveRig({c0})[0], m, t, ds, mat), s->props["bone"].as<Bone>(), m, t};
          p.root = curRoot;
          p.hasName = true;
          p.name = name ? *name + "/" + p.bone->name : p.bone->name;
          parts.push_back(p);
          return;
        }
        if (k == "translate") {
          V3 mv = mulMV(m, s->props.v3("v"));
          visit(c0, m, {t[0] + mv[0], t[1] + mv[1], t[2] + mv[2]}, ds, mat, name);
          return;
        }
        if (k == "rotate") { visit(c0, mul3(m, s->props.m3("m")), t, ds, mat, name); return; }
        if (k == "scale") {
          V3 S = s->props.v3("s");
          visit(c0, mul3(m, {S[0], 0, 0, 0, S[1], 0, 0, 0, S[2]}), t, ds * std::min({S[0], S[1], S[2]}), mat, name);
          return;
        }
        if (k == "material") { visit(c0, m, t, ds, mergeMatP(mat, s->props), name); return; }
        if (k == "label") {
          std::string nm = s->props["name"].s();
          visit(c0, m, t, ds, mat, &nm);
          return;
        }
        if (k == "union") {
          for (auto &c : s->children) visit(c, m, t, ds, mat, name);
          return;
        }
        push({"static", wrap(resolveRig({s})[0], m, t, ds, mat)});
      };
  for (size_t i = 0; i < shapes.size(); i++) {
    curRoot = (int)i;
    visit(shapes[i], IDENT, {0, 0, 0}, 1, Props{}, nullptr);
  }
  return parts;
}

namespace {
struct Chunk {
  std::vector<float> positions, normals, colors, uv;
  std::vector<uint32_t> indices;
  std::vector<uint8_t> png, normalPng;
};
struct Geom {
  std::string name, kind;
  bool empty = false;
  Json materialProps;
  PartReport quality;
  int triangles = 0, vertices = 0;
  std::vector<Chunk> chunks;
};
struct Ctx {
  int res;
  BBox sceneBB;
  double sceneMax;
  std::string method;
};
}  // namespace

static PartReport meshQuality(const Mesh &mesh, const DistFn &dist, const V3 &cell, const V3 &dims, const BBox *bbox) {
  const auto &P = mesh.positions;
  const auto &I = mesh.indices;
  size_t nv = P.size() / 3, nt = I.size() / 3;
  size_t stride = std::max<size_t>(1, nv / 4000);
  double mx = 0, sum = 0;
  int n = 0;
  for (size_t v = 0; v < nv; v += stride) {
    double d = std::fabs(dist(P[v * 3], P[v * 3 + 1], P[v * 3 + 2]));
    mx = std::max(mx, d);
    sum += d;
    n++;
  }
  size_t ts = std::max<size_t>(1, nt / 4000);
  double faceMax = 0;
  for (size_t t = 0; t < nt; t += ts) {
    size_t a = I[t * 3] * 3, b = I[t * 3 + 1] * 3, c = I[t * 3 + 2] * 3;
    double d = std::fabs(dist((P[a] + P[b] + P[c]) / 3.0, (P[a + 1] + P[b + 1] + P[c + 1]) / 3.0, (P[a + 2] + P[b + 2] + P[c + 2]) / 3.0));
    faceMax = std::max(faceMax, d);
  }
  double cellMin = std::min({cell[0], cell[1], cell[2]});
  double volumeRatio = -1;
  std::string reason;
  if (bbox) {
    double vm = 0;
    for (size_t t = 0; t < nt; t++) {
      size_t a = I[t * 3] * 3, b = I[t * 3 + 1] * 3, c = I[t * 3 + 2] * 3;
      vm += (double)P[a] * ((double)P[b + 1] * P[c + 2] - (double)P[b + 2] * P[c + 1]) - (double)P[a + 1] * ((double)P[b] * P[c + 2] - (double)P[b + 2] * P[c]) +
            (double)P[a + 2] * ((double)P[b] * P[c + 1] - (double)P[b + 1] * P[c]);
    }
    vm = std::fabs(vm / 6);
    V3 ext = size(*bbox);
    uint32_t seed = 123456789u;
    auto rnd = [&] { seed = seed * 1664525u + 1013904223u; return seed / 4294967296.0; };
    const int N = 24000;
    int inside = 0;
    for (int i = 0; i < N; i++) {
      double x = bbox->min[0] + rnd() * ext[0];
      double y = bbox->min[1] + rnd() * ext[1];
      double z = bbox->min[2] + rnd() * ext[2];
      if (dist(x, y, z) < 0) inside++;
    }
    if (inside >= 150) volumeRatio = vm / ((double(inside) / N) * ext[0] * ext[1] * ext[2]);
  }
  auto rank = [](const std::string &s) { return s == "ok" ? 0 : s == "atenção" ? 1 : 2; };
  double worst = std::max(mx, faceMax);
  std::string status = worst <= cellMin * 0.6 ? "ok" : worst <= cellMin ? "atenção" : "ruim";
  if (status != "ok") reason = "desvio";
  if (volumeRatio >= 0) {
    double lost = 1 - volumeRatio;
    std::string vs = lost > 0.3 ? "ruim" : lost > 0.12 ? "atenção" : "ok";
    if (rank(vs) > rank(status)) { status = vs; reason = "volume"; }
  }
  PartReport r;
  r.maxError = mx;
  r.meanError = n ? sum / n : 0;
  r.faceError = faceMax;
  r.cell = cellMin;
  r.size = std::max({dims[0], dims[1], dims[2]});
  r.volumeRatio = volumeRatio;
  r.status = status;
  r.reason = reason;
  return r;
}

static Geom partGeometry(const ExpPart &p, int pi, const Ctx &ctx) {
  BBox bb = p.shape->bbox();
  bool infinite = !isFiniteBB(bb);
  if (infinite) {
    double margin = std::max(3.0, ctx.sceneMax * 0.25);
    bb = {{ctx.sceneBB.min[0] - margin, std::max(bb.min[1], -0.25), ctx.sceneBB.min[2] - margin},
          {ctx.sceneBB.max[0] + margin, std::min(bb.max[1], 0.25), ctx.sceneBB.max[2] + margin}};
  }
  V3 dims = size(bb);
  double partMax = std::max({dims[0], dims[1], dims[2]});
  double base = partMax / ctx.res;
  std::vector<double> fl;
  fillets(*p.shape, 1, fl);
  double fillet = INFINITY;
  for (double r : fl)
    if (r >= partMax / 60) fillet = std::min(fillet, r);
  double featureCell = std::isfinite(fillet) ? std::max(fillet * 0.6, partMax / 160) : INFINITY;
  V3 cell;
  for (int i = 0; i < 3; i++) cell[i] = infinite ? partMax / ctx.res : std::min({base, featureCell, std::max(dims[i], 1e-4) / 6});
  SceneFns fns = buildSceneFns(p.shape);
  bool painted = hasPaint(*p.shape);
  bool textured = painted, bumped = false;
  auto colorAt = [&](double x, double y, double z) {
    MatR r = fns.mat(x, y, z);
    if (r.hasTex) { textured = true; if (r.tx[3] > 0) bumped = true; }
    return surfaceColor(r, nullptr);
  };
  std::function<Height(double, double, double, const V3 &)> heightAt = [&](double x, double y, double z, const V3 &n) -> Height {
    MatR r = fns.mat(x, y, z);
    if (!r.hasTex || !(r.tx[3] > 0) || !r.hasTp) return {0, 0, 1};
    return {texHeight(r.tp, r.tx, &n), r.tx[3] * r.tx[1], r.tx[1] * 0.02};
  };
  double texSz = smallestTexture(*p.shape);
  double cellMin = std::min({cell[0], cell[1], cell[2]});
  MeshOpts mo;
  mo.colorAt = colorAt;
  mo.tolerance = cellMin * 0.35;
  mo.maxEdge = std::isfinite(texSz) ? texSz * 0.5 : painted ? cellMin * 8 : INFINITY;
  auto facet = smallestFacet(*p.shape);
  if (facet) {
    mo.tolerance = std::max(mo.tolerance, facet->size * 0.12);
    mo.maxEdge = std::min(mo.maxEdge, facet->size * 1.3);
  }
  std::optional<Mesh> mesh;
  std::string how = "amostragem";
  if (ctx.method != "sample" && !infinite && !facet && !painted) {
    mesh = nativeMesh(p.shape, std::max(12, jround(ctx.res / 4.0)));
    if (mesh) {
      how = "direta";
      mesh->colors.resize(mesh->positions.size());
      for (size_t v = 0; v < mesh->positions.size(); v += 3) {
        V3 c = colorAt(mesh->positions[v], mesh->positions[v + 1], mesh->positions[v + 2]);
        for (int a = 0; a < 3; a++) mesh->colors[v + a] = (float)c[a];
      }
    }
  }
  if (!mesh) { mo.cell = cell; mesh = meshSDF(fns.dist, bb, mo); }
  for (int tries = 0; !mesh && tries < 3; tries++) {
    for (auto &c : cell) c /= 2;
    mo.cell = cell;
    mesh = meshSDF(fns.dist, bb, mo);
  }
  Geom g;
  g.name = p.hasName ? p.name : "parte" + std::to_string(pi);
  if (!mesh) { g.empty = true; return g; }
  if (facet) mesh = flatShade(*mesh, facet->vary);
  if (how == "direta") {
    g.quality.status = "ok";
    g.quality.cell = std::min({cell[0], cell[1], cell[2]});
    g.quality.size = partMax;
  } else g.quality = meshQuality(*mesh, fns.dist, cell, dims, infinite ? nullptr : &bb);
  g.quality.method = how;
  if (facet) {
    g.quality.status = "ok";
    g.quality.reason = "facetas de " + std::to_string(jround(facet->size * 100)) + " cm (low poly)";
    g.quality.method = "facetas";
  }
  MatR m0 = fns.mat(mesh->positions[0], mesh->positions[1], mesh->positions[2]);
  double glow = std::min(1.0, std::max(0.0, m0.glow));
  Json mp = Json::object();
  mp.set("name", p.hasName ? p.name : "material" + std::to_string(pi));
  Json pbr = Json::object();
  Json bcf = Json::array();
  for (int i = 0; i < 4; i++) bcf.push(1);
  pbr.set("baseColorFactor", bcf);
  pbr.set("metallicFactor", m0.metal);
  pbr.set("roughnessFactor", std::max(0.03, m0.rough));
  mp.set("pbrMetallicRoughness", pbr);
  if (glow > 0) {
    Json ef = Json::array();
    for (int i = 0; i < 3; i++) ef.push(std::min(1.0, m0.c[i] * glow * 2));
    mp.set("emissiveFactor", ef);
  }
  g.materialProps = mp;
  g.kind = p.kind;
  g.triangles = (int)(mesh->indices.size() / 3);
  if (!textured) {
    g.vertices = (int)(mesh->positions.size() / 3);
    g.chunks.push_back({mesh->positions, mesh->normals, mesh->colors, {}, mesh->indices, {}, {}});
    return g;
  }
  int texelsPerTriangle = painted && !std::isfinite(texSz) ? std::max(6, std::min(12, jround(12 * std::sqrt(8000.0 / std::max(1, g.triangles)))))
                                                           : std::max(3, std::min(8, jround(8 * std::sqrt(6000.0 / std::max(1, g.triangles)))));
  auto sample = [&](double x, double y, double z, const V3 &n) { return surfaceColor(fns.mat(x, y, z), &n); };
  for (size_t first = 0; first < mesh->indices.size(); first += EXPORT_CHUNK_TRIANGLES * 3) {
    size_t last = std::min(first + EXPORT_CHUNK_TRIANGLES * 3, mesh->indices.size());
    size_t vc = last - first;
    Chunk ch;
    ch.positions.resize(vc * 3);
    ch.normals.resize(vc * 3);
    for (size_t i = 0; i < vc; i++) {
      size_t src = mesh->indices[first + i] * 3;
      for (int a = 0; a < 3; a++) { ch.positions[i * 3 + a] = mesh->positions[src + a]; ch.normals[i * 3 + a] = mesh->normals[src + a]; }
    }
    Atlas atlas = bakeTextureAtlas(ch.positions, sample, bumped ? &heightAt : nullptr, ch.normals, texelsPerTriangle);
    ch.uv = std::move(atlas.uv);
    ch.png = std::move(atlas.png);
    ch.normalPng = std::move(atlas.normalPng);
    g.chunks.push_back(std::move(ch));
  }
  g.vertices = (int)mesh->indices.size();
  return g;
}

// ---------- glTF ----------

namespace {
const int FLOAT = 5126, UINT = 5125, USHORT = 5123, UBYTE = 5121, ARRAY_BUFFER = 34962, ELEMENT_ARRAY_BUFFER = 34963;
struct Gltf {
  Json json = Json::object();
  std::vector<uint8_t> bin;
  Gltf() {
    Json asset = Json::object();
    asset.set("version", "2.0");
    asset.set("generator", "3DI");
    json.set("asset", asset);
    json.set("scene", 0);
    Json scenes = Json::array(), sc = Json::object();
    sc.set("nodes", Json::array());
    scenes.push(sc);
    json.set("scenes", scenes);
    for (const char *k : {"nodes", "meshes", "materials", "accessors", "bufferViews"}) json.set(k, Json::array());
    Json bufs = Json::array(), b = Json::object();
    b.set("byteLength", 0);
    bufs.push(b);
    json.set("buffers", bufs);
  }
  Json &arr(const std::string &k) {
    if (!json.get(k)) json.set(k, Json::array());
    for (auto &[key, v] : json.o)
      if (key == k) return v;
    throw std::logic_error(k);
  }
  int add(const std::string &kind, Json obj) {
    Json &a = arr(kind);
    a.push(std::move(obj));
    return (int)a.a.size() - 1;
  }
  int bufferView(const void *data, size_t len, int target = 0) {
    while (bin.size() % 4) bin.push_back(0);
    Json v = Json::object();
    v.set("buffer", 0);
    v.set("byteOffset", (double)bin.size());
    v.set("byteLength", (double)len);
    if (target) v.set("target", target);
    const uint8_t *p = static_cast<const uint8_t *>(data);
    bin.insert(bin.end(), p, p + len);
    return add("bufferViews", v);
  }
  template <class T>
  int accessor(const std::vector<T> &arr, int componentType, const char *type, int target = 0, bool minmax = false) {
    int n = !std::strcmp(type, "SCALAR") ? 1 : !std::strcmp(type, "VEC2") ? 2 : !std::strcmp(type, "VEC3") ? 3 : !std::strcmp(type, "VEC4") ? 4 : 16;
    Json acc = Json::object();
    acc.set("bufferView", bufferView(arr.data(), arr.size() * sizeof(T), target));
    acc.set("componentType", componentType);
    acc.set("count", (double)(arr.size() / n));
    acc.set("type", type);
    if (minmax) {
      std::vector<double> mn(n, INFINITY), mx(n, -INFINITY);
      for (size_t i = 0; i < arr.size(); i++) { mn[i % n] = std::min(mn[i % n], (double)arr[i]); mx[i % n] = std::max(mx[i % n], (double)arr[i]); }
      Json a = Json::array(), b = Json::array();
      for (int i = 0; i < n; i++) { a.push(mn[i]); b.push(mx[i]); }
      acc.set("min", a);
      acc.set("max", b);
    }
    return add("accessors", acc);
  }
  std::vector<uint8_t> toGLB() {
    for (auto &[k, v] : json.o)
      if (k == "buffers") v.a[0].set("byteLength", (double)bin.size());
    json.o.erase(std::remove_if(json.o.begin(), json.o.end(),
                                [](auto &kv) { return (kv.first == "meshes" || kv.first == "materials" || kv.first == "accessors" || kv.first == "bufferViews") && kv.second.a.empty(); }),
                 json.o.end());
    std::string js = json.dump();
    while (js.size() % 4) js += ' ';
    while (bin.size() % 4) bin.push_back(0);
    uint32_t total = (uint32_t)(12 + 8 + js.size() + 8 + bin.size());
    std::vector<uint8_t> out;
    auto u32 = [&](uint32_t v) { for (int i = 0; i < 4; i++) out.push_back((uint8_t)(v >> (8 * i))); };
    u32(0x46546c67);
    u32(2);
    u32(total);
    u32((uint32_t)js.size());
    u32(0x4e4f534a);
    out.insert(out.end(), js.begin(), js.end());
    u32((uint32_t)bin.size());
    u32(0x004e4942);
    out.insert(out.end(), bin.begin(), bin.end());
    return out;
  }
};

using M4 = std::array<double, 16>;
M4 mat4FromAffine(const M3 &m3, const V3 &t) { return {m3[0], m3[3], m3[6], 0, m3[1], m3[4], m3[7], 0, m3[2], m3[5], m3[8], 0, t[0], t[1], t[2], 1}; }
M4 mat4Mul(const M4 &a, const M4 &b) {
  M4 r{};
  for (int c = 0; c < 4; c++)
    for (int rr = 0; rr < 4; rr++)
      for (int k = 0; k < 4; k++) r[c * 4 + rr] += a[k * 4 + rr] * b[c * 4 + k];
  return r;
}
M4 mat4Translate(const V3 &t) { return {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, t[0], t[1], t[2], 1}; }
M4 mat4Invert(const M4 &m) {
  M4 inv;
  inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] + m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10];
  inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] - m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10];
  inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] + m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9];
  inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] - m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9];
  inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] - m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10];
  inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] + m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10];
  inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] - m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9];
  inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] + m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9];
  inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] + m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6];
  inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] - m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6];
  inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] + m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5];
  inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] - m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5];
  inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] - m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6];
  inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] + m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6];
  inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] - m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5];
  inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] + m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5];
  double det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];
  for (auto &v : inv) v /= det;
  return inv;
}
std::array<double, 4> eulerToQuat(double ax, double ay, double az) {
  double h = M_PI / 360;
  double sx = std::sin(ax * h), cx = std::cos(ax * h), sy = std::sin(ay * h), cy = std::cos(ay * h), sz = std::sin(az * h), cz = std::cos(az * h);
  return {cz * cy * sx - sz * sy * cx, cz * sy * cx + sz * cy * sx, sz * cy * cx - cz * sy * sx, cz * cy * cx + sz * sy * sx};
}
}  // namespace

// formas são imutáveis mas guardam caches (caixa, folhas): calcula tudo antes das threads
static void prewarm(const Shape &s, std::set<const Shape *> &seen) {
  if (!seen.insert(&s).second) return;
  s.bbox();
  s.leaves();
  s.animated();
  for (auto &c : s.children) prewarm(*c, seen);
}

// Paleta com degradê: cada cor vira uma faixa de tons (claro em cima), escolhidos pela altura na peça
static const int PALETTE_CELL = 4, PALETTE_SHADES = 8, PALETTE_MAX = 4096;
static double shadeOf(int k) { return 1.12 - (0.32 * k) / (PALETTE_SHADES - 1); }
namespace {
struct Palette {
  std::vector<uint8_t> png;
  int width = 0, height = 0, grid = 0, colors = 0;
  std::map<int, int> index;
  std::vector<float> uvOf(const std::vector<float> &colors, const std::vector<float> &positions, std::vector<size_t> pieces = {}) const {
    if (pieces.empty()) pieces.push_back(positions.size() / 3);
    std::vector<float> uv(colors.size() / 3 * 2);
    size_t start = 0;
    for (size_t count : pieces) {
    double lo = INFINITY, hi = -INFINITY;
    for (size_t q = start; q < start + count; q++) { lo = std::min(lo, (double)positions[q * 3 + 1]); hi = std::max(hi, (double)positions[q * 3 + 1]); }
    double span = std::max(hi - lo, 1e-9);
    for (size_t q = start; q < start + count; q++) {
      size_t v = q * 3, k = q * 2;
      int key = linearToSrgb(colors[v]) << 16 | linearToSrgb(colors[v + 1]) << 8 | linearToSrgb(colors[v + 2]);
      int i = index.at(key);
      int shade = jround((1 - (positions[v + 1] - lo) / span) * (PALETTE_SHADES - 1));
      uv[k] = (float)(((i % grid) * PALETTE_CELL + PALETTE_CELL / 2.0) / width);
      uv[k + 1] = (float)(((i / grid) * PALETTE_CELL * PALETTE_SHADES + shade * PALETTE_CELL + PALETTE_CELL / 2.0) / height);
    }
    start += count;
    }
    return uv;
  }
};
}  // namespace
static std::optional<Palette> buildPalette(const std::vector<Geom> &geoms) {
  Palette p;
  std::vector<std::array<float, 3>> list;
  for (auto &g : geoms)
    for (auto &c : g.chunks) {
      if (!c.uv.empty() || c.colors.empty()) continue;
      for (size_t v = 0; v < c.colors.size(); v += 3) {
        int key = linearToSrgb(c.colors[v]) << 16 | linearToSrgb(c.colors[v + 1]) << 8 | linearToSrgb(c.colors[v + 2]);
        if (!p.index.count(key)) {
          if ((int)list.size() >= PALETTE_MAX) return std::nullopt;
          p.index[key] = (int)list.size();
          list.push_back({c.colors[v], c.colors[v + 1], c.colors[v + 2]});
        }
      }
    }
  if (list.empty()) return std::nullopt;
  p.grid = (int)std::ceil(std::sqrt((double)list.size()));
  p.width = std::max(16, 1 << (int)std::ceil(std::log2((double)p.grid * PALETTE_CELL)));
  int rows = (int)std::ceil((double)list.size() / p.grid);
  p.height = std::max(16, 1 << (int)std::ceil(std::log2((double)rows * PALETTE_CELL * PALETTE_SHADES)));
  std::vector<uint8_t> rgba((size_t)p.width * p.height * 4, 0);
  for (size_t i = 0; i < list.size(); i++) {
    int x0 = (int)(i % p.grid) * PALETTE_CELL, y0 = (int)(i / p.grid) * PALETTE_CELL * PALETTE_SHADES;
    for (int k = 0; k < PALETTE_SHADES; k++) {
      double f = shadeOf(k);
      int rgb[3] = {linearToSrgb(list[i][0] * f), linearToSrgb(list[i][1] * f), linearToSrgb(list[i][2] * f)};
      for (int y = 0; y < PALETTE_CELL; y++)
        for (int x = 0; x < PALETTE_CELL; x++) {
          size_t at = ((size_t)(y0 + k * PALETTE_CELL + y) * p.width + x0 + x) * 4;
          rgba[at] = (uint8_t)rgb[0]; rgba[at + 1] = (uint8_t)rgb[1]; rgba[at + 2] = (uint8_t)rgb[2]; rgba[at + 3] = 255;
        }
    }
  }
  p.png = encodePng(p.width, p.height, rgba);
  p.colors = (int)list.size();
  return p;
}

ExportResult exportGLB(const Scene &scene, const ExportOpts &opts) {
  if (opts.res < 1) throw std::runtime_error("res deve ser um inteiro positivo");
  double duration = 4, fps = 30;
  if (auto a = scene.anim.as<Rec>()) { duration = a->f.num("duration"); fps = a->f.num("fps"); }
  if (!std::isfinite(duration) || duration <= 0 || !std::isfinite(fps) || fps <= 0 || duration * fps > 100000)
    throw std::runtime_error("animação deve ter duration e fps positivos e no máximo 100000 amostras");
  if (opts.method != "auto" && opts.method != "sample") throw std::runtime_error("method deve ser 'auto' ou 'sample'");
  auto t0 = std::chrono::steady_clock::now();
  ExportResult res;
  auto &warnings = res.stats.warnings;
  auto parts = splitParts(scene.shapes);
  std::vector<BBox> finite;
  for (auto &p : parts)
    if (isFiniteBB(p.shape->bbox())) finite.push_back(p.shape->bbox());
  Ctx ctx;
  ctx.res = opts.res;
  ctx.sceneBB = finite.empty() ? BBox{{-1, 0, -1}, {1, 1, 1}} : unionBB(finite);
  V3 ss = size(ctx.sceneBB);
  ctx.sceneMax = std::max({ss[0], ss[1], ss[2], 0.01});
  ctx.method = opts.method;
  for (auto &p : parts)
    if (p.kind == "static" && p.shape->animated()) { warnings.push_back("partes animadas com time fora de ossos foram exportadas paradas (t = 0)"); break; }

  // peças em paralelo, uma por núcleo
  std::set<const Shape *> seen;
  for (auto &p : parts) prewarm(*p.shape, seen);
  std::vector<Geom> geoms(parts.size());
  std::atomic<size_t> next{0};
  std::atomic<int> done{0};
  std::mutex mx;
  std::string firstError;
  int nThreads = opts.threads > 0 ? opts.threads : (int)std::max(1u, std::thread::hardware_concurrency());
  nThreads = std::min<int>(nThreads, (int)parts.size());
  auto worker = [&] {
    for (size_t i; (i = next++) < parts.size();) {
      try {
        geoms[i] = partGeometry(parts[i], (int)i, ctx);
      } catch (const std::exception &e) {
        std::lock_guard<std::mutex> lk(mx);
        if (firstError.empty()) firstError = e.what();
      }
      int d = ++done;
      if (opts.onProgress) { std::lock_guard<std::mutex> lk(mx); opts.onProgress(d - 1, (int)parts.size()); }
    }
  };
  std::vector<std::thread> pool;
  for (int i = 1; i < nThreads; i++) pool.emplace_back(worker);
  worker();
  for (auto &t : pool) t.join();
  if (!firstError.empty()) throw std::runtime_error(firstError);

  Gltf g;
  std::optional<Palette> pal;
  if (opts.palette) {
    pal = buildPalette(geoms);
    if (!pal) warnings.push_back("paleta não gerada: cores demais (degradês contínuos); usando cores de vértice");
  }
  int palTexture = -1;
  if (pal) {
    Json img = Json::object();
    img.set("name", "paleta.png");
    img.set("bufferView", g.bufferView(pal->png.data(), pal->png.size()));
    img.set("mimeType", "image/png");
    int image = g.add("images", img);
    Json smp = Json::object();
    smp.set("magFilter", 9728);
    smp.set("minFilter", 9728);
    smp.set("wrapS", 33071);
    smp.set("wrapT", 33071);
    int sampler = g.add("samplers", smp);
    Json tx = Json::object();
    tx.set("sampler", sampler);
    tx.set("source", image);
    palTexture = g.add("textures", tx);
  }
  auto bones = collectBones(scene.shapes);
  std::map<const Bone *, int> jointIndex;
  for (size_t i = 0; i < bones.size(); i++) jointIndex[bones[i].get()] = (int)i;
  std::vector<const ExpPart *> skinParts;
  for (auto &p : parts)
    if (p.kind == "skin") skinParts.push_back(&p);
  int vertices = 0, triangles = 0;

  // nós de saída: uma peça cada, ou (merge) uma forma mostrada cada
  struct Entry { const Chunk *chunk; int ji; Json materialProps; std::string matName; };
  struct Out { std::string name, kind; std::vector<Entry> entries; };
  std::vector<Out> outs;
  std::map<std::string, size_t> outOf;
  for (size_t pi = 0; pi < parts.size(); pi++) {
    const ExpPart &p = parts[pi];
    Geom &geom = geoms[pi];
    if (geom.empty) {
      warnings.push_back("parte " + (p.hasName ? p.name : std::to_string(pi)) + " não tem superfície");
      PartReport r;
      r.name = geom.name;
      r.empty = true;
      res.stats.partReports.push_back(r);
      continue;
    }
    PartReport r = geom.quality;
    r.name = geom.name;
    r.kind = geom.kind;
    r.triangles = geom.triangles;
    r.textured = !geom.chunks.empty() && !geom.chunks[0].uv.empty();
    res.stats.partReports.push_back(r);
    triangles += geom.triangles;
    vertices += geom.vertices;
    std::string key = opts.merge ? std::to_string(p.root) + "|" + p.kind : "p" + std::to_string(pi);
    auto it = outOf.find(key);
    if (it == outOf.end()) {
      std::string nm = p.hasName ? p.name : "";
      if (nm.empty() && opts.merge)
        for (const Shape *q = p.shape.get(); q; q = q->children.size() == 1 ? q->children[0].get() : nullptr)
          if (q->kind == "label") { nm = q->props["name"].s(); break; }
      if (nm.empty()) nm = "parte" + std::to_string(pi);
      it = outOf.emplace(key, outs.size()).first;
      outs.push_back({nm, p.kind, {}});
    }
    int ji = p.kind == "skin" ? jointIndex[p.bone.get()] : 0;
    for (auto &ch : geom.chunks) outs[it->second].entries.push_back({&ch, ji, geom.materialProps, p.hasName ? p.name : "material" + std::to_string(pi)});
  }
  bool big = bones.size() > 255;
  auto skinAttrs = [&](Json &attrs, const std::string &kind, const std::vector<int> &jis) {
    if (kind != "skin") return;
    size_t n = jis.size();
    std::vector<float> weights(n * 4, 0.f);
    for (size_t v = 0; v < n; v++) weights[v * 4] = 1;
    if (big) {
      std::vector<uint16_t> j(n * 4, 0);
      for (size_t v = 0; v < n; v++) j[v * 4] = (uint16_t)jis[v];
      attrs.set("JOINTS_0", g.accessor(j, USHORT, "VEC4", ARRAY_BUFFER));
    } else {
      std::vector<uint8_t> j(n * 4, 0);
      for (size_t v = 0; v < n; v++) j[v * 4] = (uint8_t)jis[v];
      attrs.set("JOINTS_0", g.accessor(j, UBYTE, "VEC4", ARRAY_BUFFER));
    }
    attrs.set("WEIGHTS_0", g.accessor(weights, FLOAT, "VEC4", ARRAY_BUFFER));
  };
  for (auto &o : outs) {
    Json primitives = Json::array();
    struct Bucket { Json materialProps; std::vector<const Entry *> items; };
    std::vector<Bucket> buckets;
    std::map<std::string, size_t> bucketOf;
    for (auto &e : o.entries) {
      const Chunk &ch = *e.chunk;
      if (!ch.uv.empty()) {
        size_t vc = ch.positions.size() / 3;
        Json img = Json::object();
        img.set("name", e.matName + "-" + std::to_string(primitives.a.size()) + ".png");
        img.set("bufferView", g.bufferView(ch.png.data(), ch.png.size()));
        img.set("mimeType", "image/png");
        int image = g.add("images", img);
        Json smp = Json::object();
        smp.set("magFilter", 9729);
        smp.set("minFilter", 9729);
        smp.set("wrapS", 33071);
        smp.set("wrapT", 33071);
        int sampler = g.add("samplers", smp);
        Json tx = Json::object();
        tx.set("sampler", sampler);
        tx.set("source", image);
        int texture = g.add("textures", tx);
        Json mat = e.materialProps;
        if (!ch.normalPng.empty()) {
          Json nimg = Json::object();
          nimg.set("name", e.matName + "-" + std::to_string(primitives.a.size()) + "-normal.png");
          nimg.set("bufferView", g.bufferView(ch.normalPng.data(), ch.normalPng.size()));
          nimg.set("mimeType", "image/png");
          int ni = g.add("images", nimg);
          Json ntx = Json::object();
          ntx.set("sampler", sampler);
          ntx.set("source", ni);
          Json nt = Json::object();
          nt.set("index", g.add("textures", ntx));
          nt.set("texCoord", 0);
          mat.set("normalTexture", nt);
        }
        Json pbr = mat["pbrMetallicRoughness"];
        Json bct = Json::object();
        bct.set("index", texture);
        bct.set("texCoord", 0);
        pbr.set("baseColorTexture", bct);
        mat.set("pbrMetallicRoughness", pbr);
        Json attrs = Json::object(), prim = Json::object();
        prim.set("material", g.add("materials", mat));
        attrs.set("POSITION", g.accessor(ch.positions, FLOAT, "VEC3", ARRAY_BUFFER, true));
        attrs.set("NORMAL", g.accessor(ch.normals, FLOAT, "VEC3", ARRAY_BUFFER));
        attrs.set("TEXCOORD_0", g.accessor(ch.uv, FLOAT, "VEC2", ARRAY_BUFFER));
        skinAttrs(attrs, o.kind, std::vector<int>(vc, e.ji));
        int indices;
        if (vc < 65536) {
          std::vector<uint16_t> ix(vc);
          for (size_t i = 0; i < vc; i++) ix[i] = (uint16_t)i;
          indices = g.accessor(ix, USHORT, "SCALAR", ELEMENT_ARRAY_BUFFER);
        } else {
          std::vector<uint32_t> ix(vc);
          for (size_t i = 0; i < vc; i++) ix[i] = (uint32_t)i;
          indices = g.accessor(ix, UINT, "SCALAR", ELEMENT_ARRAY_BUFFER);
        }
        prim.set("attributes", attrs);
        prim.set("indices", indices);
        primitives.push(prim);
        continue;
      }
      std::string mk;
      if (opts.merge) {
        Json rest = e.materialProps;
        rest.o.erase(std::remove_if(rest.o.begin(), rest.o.end(), [](auto &kv) { return kv.first == "name"; }), rest.o.end());
        mk = rest.dump();
      } else mk = std::to_string(buckets.size());
      auto bi = bucketOf.find(mk);
      if (bi == bucketOf.end()) { bi = bucketOf.emplace(mk, buckets.size()).first; buckets.push_back({e.materialProps, {}}); }
      buckets[bi->second].items.push_back(&e);
    }
    for (auto &bk : buckets) {
      std::vector<float> pos, nor, col;
      std::vector<uint32_t> idx;
      std::vector<int> jis;
      std::vector<size_t> pieces;
      for (auto *e : bk.items) {
        const Chunk &c = *e->chunk;
        uint32_t vo = (uint32_t)(pos.size() / 3);
        pos.insert(pos.end(), c.positions.begin(), c.positions.end());
        nor.insert(nor.end(), c.normals.begin(), c.normals.end());
        col.insert(col.end(), c.colors.begin(), c.colors.end());
        for (uint32_t i : c.indices) idx.push_back(i + vo);
        size_t n = c.positions.size() / 3;
        jis.insert(jis.end(), n, e->ji);
        pieces.push_back(n);
      }
      size_t nv = pos.size() / 3;
      Json mat = bk.materialProps;
      if (opts.merge) mat.set("name", o.name);
      if (pal) {
        Json pbr = mat["pbrMetallicRoughness"];
        Json bct = Json::object();
        bct.set("index", palTexture);
        bct.set("texCoord", 0);
        pbr.set("baseColorTexture", bct);
        mat.set("pbrMetallicRoughness", pbr);
      }
      Json attrs = Json::object(), prim = Json::object();
      prim.set("material", g.add("materials", mat));
      attrs.set("POSITION", g.accessor(pos, FLOAT, "VEC3", ARRAY_BUFFER, true));
      attrs.set("NORMAL", g.accessor(nor, FLOAT, "VEC3", ARRAY_BUFFER));
      if (pal) attrs.set("TEXCOORD_0", g.accessor(pal->uvOf(col, pos, pieces), FLOAT, "VEC2", ARRAY_BUFFER));
      else attrs.set("COLOR_0", g.accessor(col, FLOAT, "VEC3", ARRAY_BUFFER));
      skinAttrs(attrs, o.kind, jis);
      int indices;
      if (nv < 65536) {
        std::vector<uint16_t> ix(idx.begin(), idx.end());
        indices = g.accessor(ix, USHORT, "SCALAR", ELEMENT_ARRAY_BUFFER);
      } else indices = g.accessor(idx, UINT, "SCALAR", ELEMENT_ARRAY_BUFFER);
      prim.set("attributes", attrs);
      prim.set("indices", indices);
      primitives.push(prim);
    }
    Json mesh = Json::object();
    mesh.set("name", o.name);
    mesh.set("primitives", primitives);
    int meshIndex = g.add("meshes", mesh);
    Json node = Json::object();
    node.set("name", o.name);
    node.set("mesh", meshIndex);
    if (o.kind == "skin") node.set("skin", 0);
    int ni = g.add("nodes", node);
    for (auto &[k, v] : g.json.o)
      if (k == "scenes") v.a[0].o[0].second.push(ni);
  }

  bool animated = false;
  if (!bones.empty() && !skinParts.empty()) {
    const ExpPart &outer = *skinParts[0];
    for (auto *p : skinParts) {
      bool diff = false;
      for (int i = 0; i < 9; i++) diff |= std::fabs(p->outerM[i] - outer.outerM[i]) > 1e-9;
      for (int i = 0; i < 3; i++) diff |= std::fabs(p->outerT[i] - outer.outerT[i]) > 1e-9;
      if (diff) { warnings.push_back("partes do mesmo esqueleto com transformações externas diferentes: usando a da primeira"); break; }
    }
    M4 outer4 = mat4FromAffine(outer.outerM, outer.outerT);
    Json armature = Json::object();
    armature.set("name", bones[0]->skel->name);
    armature.set("children", Json::array());
    if (!isIdent(outer.outerM, outer.outerT)) {
      Json m = Json::array();
      for (double v : outer4) m.push(v);
      armature.set("matrix", m);
    }
    int armatureIndex = g.add("nodes", armature);
    for (auto &[k, v] : g.json.o)
      if (k == "scenes") v.a[0].o[0].second.push(armatureIndex);
    auto baseOf = [](const Bone &b) {
      V3 h = b.head;
      if (b.parent) for (int i = 0; i < 3; i++) h[i] -= b.parent->head[i];
      return h;
    };
    std::map<const Bone *, int> nodeOf;
    auto nodeRef = [&](int i) -> Json & { return g.arr("nodes").a[i]; };
    for (auto &b : bones) {
      Json n = Json::object();
      n.set("name", b->name);
      V3 bt = baseOf(*b);
      Json tr = Json::array();
      for (int i = 0; i < 3; i++) tr.push(bt[i] + val0(b->offset[i]));
      n.set("translation", tr);
      V3 ang{val0(b->angles[0]), val0(b->angles[1]), val0(b->angles[2])};
      if (ang[0] != 0 || ang[1] != 0 || ang[2] != 0) {
        auto q = eulerToQuat(ang[0], ang[1], ang[2]);
        Json r = Json::array();
        for (double v : q) r.push(v);
        n.set("rotation", r);
      }
      int ni = g.add("nodes", n);
      nodeOf[b.get()] = ni;
      Json &parentNode = b->parent ? nodeRef(nodeOf[b->parent.get()]) : nodeRef(armatureIndex);
      if (!parentNode.get("children")) parentNode.set("children", Json::array());
      for (auto &[k, v] : parentNode.o)
        if (k == "children") v.push(ni);
    }
    std::vector<float> ibm(bones.size() * 16);
    for (size_t i = 0; i < bones.size(); i++) {
      M4 m = mat4Invert(mat4Mul(outer4, mat4Translate(bones[i]->head)));
      for (int k = 0; k < 16; k++) ibm[i * 16 + k] = (float)m[k];
    }
    Json skin = Json::object();
    skin.set("name", bones[0]->skel->name);
    Json joints = Json::array();
    for (auto &b : bones) joints.push(nodeOf[b.get()]);
    skin.set("joints", joints);
    skin.set("skeleton", armatureIndex);
    skin.set("inverseBindMatrices", g.accessor(ibm, FLOAT, "MAT4"));
    g.add("skins", skin);

    std::vector<std::shared_ptr<Bone>> animBones;
    for (auto &b : bones)
      if (b->animated()) animBones.push_back(b);
    if (!animBones.empty()) {
      animated = true;
      int n = std::max(2, jround(duration * fps) + 1);
      std::vector<float> times(n);
      for (int i = 0; i < n; i++) times[i] = (float)((i * duration) / (n - 1));
      int input = g.accessor(times, FLOAT, "SCALAR", 0, true);
      Json samplers = Json::array(), channels = Json::array();
      auto channel = [&](int sampler, int node, const char *path) {
        Json c = Json::object(), t = Json::object();
        c.set("sampler", sampler);
        t.set("node", node);
        t.set("path", path);
        c.set("target", t);
        channels.push(c);
      };
      for (auto &b : animBones) {
        bool angAnim = std::any_of(b->angles.begin(), b->angles.end(), [](const Value &a) { return !a.isNum(); });
        bool offAnim = std::any_of(b->offset.begin(), b->offset.end(), [](const Value &a) { return !a.isNum(); });
        if (angAnim) {
          std::vector<float> q(n * 4);
          std::array<double, 4> prev{};
          bool hasPrev = false;
          for (int i = 0; i < n; i++) {
            double tt = times[i];
            auto at = [&](const Value &v) { return v.isExpr() ? v.expr()->eval(tt) : v.n(); };
            auto r = eulerToQuat(at(b->angles[0]), at(b->angles[1]), at(b->angles[2]));
            if (hasPrev && r[0] * prev[0] + r[1] * prev[1] + r[2] * prev[2] + r[3] * prev[3] < 0)
              for (auto &v : r) v = -v;
            for (int k = 0; k < 4; k++) q[i * 4 + k] = (float)r[k];
            prev = r;
            hasPrev = true;
          }
          Json s = Json::object();
          s.set("input", input);
          s.set("output", g.accessor(q, FLOAT, "VEC4"));
          s.set("interpolation", "LINEAR");
          samplers.push(s);
          channel((int)samplers.a.size() - 1, nodeOf[b.get()], "rotation");
        }
        if (offAnim) {
          std::vector<float> tr(n * 3);
          V3 bt = baseOf(*b);
          for (int i = 0; i < n; i++) {
            double tt = times[i];
            for (int k = 0; k < 3; k++) {
              const Value &v = b->offset[k];
              tr[i * 3 + k] = (float)((v.isExpr() ? v.expr()->eval(tt) : v.n()) + bt[k]);
            }
          }
          Json s = Json::object();
          s.set("input", input);
          s.set("output", g.accessor(tr, FLOAT, "VEC3"));
          s.set("interpolation", "LINEAR");
          samplers.push(s);
          channel((int)samplers.a.size() - 1, nodeOf[b.get()], "translation");
        }
      }
      Json anim = Json::object();
      anim.set("name", "anim");
      anim.set("samplers", samplers);
      anim.set("channels", channels);
      g.add("animations", anim);
    }
  }

  res.glb = g.toGLB();
  res.gltf = g.json;
  res.stats.parts = (int)parts.size();
  res.stats.vertices = vertices;
  res.stats.triangles = triangles;
  res.stats.bones = (int)bones.size();
  res.stats.animated = animated;
  res.stats.paletteColors = pal ? pal->colors : 0;
  res.stats.bytes = res.glb.size();
  res.stats.ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
  return res;
}

}  // namespace tdi
