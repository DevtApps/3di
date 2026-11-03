// SDF -> malha por dual contouring (port de mesh.js) e simplificação por erro quádrico (simplify.js).
#include "mesh.h"

#include <algorithm>
#include <cmath>
#include <stdexcept>
#include <unordered_map>

namespace tdi {

static const int K = 4;
static const double SHARP_COS = std::cos((40 * M_PI) / 180);

static int CORNER[8][3];
struct CellEdge { int axis; int o[3]; };
static CellEdge CELL_EDGES[12];
static bool tablesReady = [] {
  for (int c = 0; c < 8; c++) { CORNER[c][0] = c & 1; CORNER[c][1] = (c >> 1) & 1; CORNER[c][2] = (c >> 2) & 1; }
  int n = 0;
  for (int axis = 0; axis < 3; axis++) {
    int u = axis == 0 ? 1 : 0, v = axis == 2 ? 1 : 2;
    for (int du = 0; du < 2; du++)
      for (int dv = 0; dv < 2; dv++) {
        CellEdge e{axis, {0, 0, 0}};
        e.o[u] = du;
        e.o[v] = dv;
        CELL_EDGES[n++] = e;
      }
  }
  return true;
}();

static double jsign(double x) { return x > 0 ? 1 : x < 0 ? -1 : x; }

static void eigenSym3(const double a[6], double values[3], double vectors[3][3]) {
  double m[3][3] = {{a[0], a[1], a[2]}, {a[1], a[3], a[4]}, {a[2], a[4], a[5]}};
  double V[3][3] = {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}};
  static const int PQ[3][2] = {{0, 1}, {0, 2}, {1, 2}};
  for (int sweep = 0; sweep < 12; sweep++) {
    double off = std::fabs(m[0][1]) + std::fabs(m[0][2]) + std::fabs(m[1][2]);
    if (off < 1e-12) break;
    for (auto &pq : PQ) {
      int p = pq[0], q = pq[1];
      if (std::fabs(m[p][q]) < 1e-15) continue;
      double theta = (m[q][q] - m[p][p]) / (2 * m[p][q]);
      double t = jsign(theta != 0 ? theta : 1) / (std::fabs(theta) + std::sqrt(theta * theta + 1));
      double c = 1 / std::sqrt(t * t + 1), s = t * c;
      for (int k = 0; k < 3; k++) { double mkp = m[k][p], mkq = m[k][q]; m[k][p] = c * mkp - s * mkq; m[k][q] = s * mkp + c * mkq; }
      for (int k = 0; k < 3; k++) { double mpk = m[p][k], mqk = m[q][k]; m[p][k] = c * mpk - s * mqk; m[q][k] = s * mpk + c * mqk; }
      for (int k = 0; k < 3; k++) { double vkp = V[k][p], vkq = V[k][q]; V[k][p] = c * vkp - s * vkq; V[k][q] = s * vkp + c * vkq; }
    }
  }
  for (int i = 0; i < 3; i++) values[i] = m[i][i];
  for (int j = 0; j < 3; j++)
    for (int i = 0; i < 3; i++) vectors[j][i] = V[i][j];
}

std::optional<Mesh> meshSDF(const DistFn &dist, const BBox &bbox, const MeshOpts &opt) {
  V3 ext{bbox.max[0] - bbox.min[0], bbox.max[1] - bbox.min[1], bbox.max[2] - bbox.min[2]};
  V3 H = opt.cell ? *opt.cell : V3{std::max({ext[0], ext[1], ext[2]}) / opt.res, std::max({ext[0], ext[1], ext[2]}) / opt.res, std::max({ext[0], ext[1], ext[2]}) / opt.res};
  for (int i = 0; i < 3; i++)
    if (!std::isfinite(H[i]) || !(H[i] > 0) || !std::isfinite(ext[i]) || !(ext[i] >= 0)) throw std::runtime_error("grade deve ter dimensões finitas e células positivas");
  double hx = H[0], hy = H[1], hz = H[2];
  V3 origin{bbox.min[0] - 2 * hx, bbox.min[1] - 2 * hy, bbox.min[2] - 2 * hz};
  long nx = (long)std::ceil(ext[0] / hx) + 5, ny = (long)std::ceil(ext[1] / hy) + 5, nz = (long)std::ceil(ext[2] / hz) + 5;
  if ((double)nx * ny * nz > 40e6)
    throw std::runtime_error("grade grande demais (" + std::to_string(nx) + "x" + std::to_string(ny) + "x" + std::to_string(nz) + "); reduza a resolução");
  auto idx = [&](long i, long j, long k) { return i + nx * (j + ny * k); };
  auto pos = [&](long i, long j, long k) { return V3{origin[0] + i * hx, origin[1] + j * hy, origin[2] + k * hz}; };

  long cx = (long)std::ceil((nx - 1) / (double)K) + 1, cy = (long)std::ceil((ny - 1) / (double)K) + 1, cz = (long)std::ceil((nz - 1) / (double)K) + 1;
  auto fi = [](long c, long n) { return std::min(c * K, n - 1); };
  std::vector<float> coarse(cx * cy * cz);
  for (long k = 0; k < cz; k++)
    for (long j = 0; j < cy; j++)
      for (long i = 0; i < cx; i++) {
        V3 p = pos(fi(i, nx), fi(j, ny), fi(k, nz));
        coarse[i + cx * (j + cy * k)] = (float)dist(p[0], p[1], p[2]);
      }

  std::vector<float> vals(nx * ny * nz, NAN);
  double band = K * std::sqrt(hx * hx + hy * hy + hz * hz) * 1.1;
  for (long k = 0; k < cz - 1; k++)
    for (long j = 0; j < cy - 1; j++)
      for (long i = 0; i < cx - 1; i++) {
        double minAbs = INFINITY;
        for (int c = 0; c < 8; c++) {
          double v = coarse[(i + CORNER[c][0]) + cx * ((j + CORNER[c][1]) + cy * (k + CORNER[c][2]))];
          minAbs = std::min(minAbs, std::fabs(v));
        }
        if (minAbs > band) continue;
        for (long kk = fi(k, nz); kk <= fi(k + 1, nz); kk++)
          for (long jj = fi(j, ny); jj <= fi(j + 1, ny); jj++)
            for (long ii = fi(i, nx); ii <= fi(i + 1, nx); ii++) {
              long id = idx(ii, jj, kk);
              if (std::isnan(vals[id])) { V3 p = pos(ii, jj, kk); vals[id] = (float)dist(p[0], p[1], p[2]); }
            }
      }
  for (long k = 0; k < nz; k++)
    for (long j = 0; j < ny; j++)
      for (long i = 0; i < nx; i++) {
        long id = idx(i, j, k);
        if (!std::isnan(vals[id])) continue;
        double c = coarse[std::min(i / K, cx - 1) + cx * (std::min(j / K, cy - 1) + cy * std::min(k / K, cz - 1))];
        vals[id] = (float)(c < 0 ? -band : band);
      }

  double e = std::min({hx, hy, hz}) * 0.05;
  double hmax = std::max({hx, hy, hz});
  auto grad = [&](double x, double y, double z) {
    double gx = dist(x + e, y, z) - dist(x - e, y, z);
    double gy = dist(x, y + e, z) - dist(x, y - e, z);
    double gz = dist(x, y, z + e) - dist(x, y, z - e);
    double l = std::sqrt(gx * gx + gy * gy + gz * gz);
    if (l == 0) l = 1;
    return V3{gx / l, gy / l, gz / l};
  };

  struct Cross { V3 p, n; };
  std::unordered_map<long, Cross> edgeCache;
  auto crossing = [&](long i, long j, long k, int axis) -> const Cross & {
    long key = idx(i, j, k) * 3 + axis;
    auto hit = edgeCache.find(key);
    if (hit != edgeCache.end()) return hit->second;
    long s[3] = {0, 0, 0};
    s[axis] = 1;
    double va = vals[idx(i, j, k)], vb = vals[idx(i + s[0], j + s[1], k + s[2])];
    V3 p0 = pos(i, j, k);
    double t = va / (va - vb);
    auto at = [&](double tt) { V3 q = p0; q[axis] += tt * H[axis]; return q; };
    V3 q = at(t);
    double dm = dist(q[0], q[1], q[2]);
    if (dm != 0 && std::isfinite(dm)) t = (dm < 0) == (va < 0) ? t + (1 - t) * (dm / (dm - vb)) : t * (va / (va - dm));
    V3 p = at(std::min(1.0, std::max(0.0, t)));
    return edgeCache.emplace(key, Cross{p, grad(p[0], p[1], p[2])}).first->second;
  };

  std::vector<int> cellVert(nx * ny * nz, -1);
  std::vector<double> P;
  std::vector<bool> rank1;
  float v8[8];
  for (long k = 0; k < nz - 1; k++)
    for (long j = 0; j < ny - 1; j++)
      for (long i = 0; i < nx - 1; i++) {
        int mask = 0;
        for (int c = 0; c < 8; c++) {
          v8[c] = vals[idx(i + CORNER[c][0], j + CORNER[c][1], k + CORNER[c][2])];
          if (v8[c] < 0) mask |= 1 << c;
        }
        if (mask == 0 || mask == 255) continue;
        double ata[6] = {0, 0, 0, 0, 0, 0}, atb[3] = {0, 0, 0}, mass[3] = {0, 0, 0};
        std::vector<V3> normalsHere;
        int m = 0;
        for (auto &E : CELL_EDGES) {
          long a = idx(i + E.o[0], j + E.o[1], k + E.o[2]);
          long s[3] = {0, 0, 0};
          s[E.axis] = 1;
          long b = idx(i + E.o[0] + s[0], j + E.o[1] + s[1], k + E.o[2] + s[2]);
          if ((vals[a] < 0) == (vals[b] < 0)) continue;
          const Cross &cr = crossing(i + E.o[0], j + E.o[1], k + E.o[2], E.axis);
          const V3 &p = cr.p, &n = cr.n;
          double d = n[0] * p[0] + n[1] * p[1] + n[2] * p[2];
          ata[0] += n[0] * n[0]; ata[1] += n[0] * n[1]; ata[2] += n[0] * n[2];
          ata[3] += n[1] * n[1]; ata[4] += n[1] * n[2]; ata[5] += n[2] * n[2];
          atb[0] += n[0] * d; atb[1] += n[1] * d; atb[2] += n[2] * d;
          mass[0] += p[0]; mass[1] += p[1]; mass[2] += p[2];
          normalsHere.push_back(n);
          m++;
        }
        double minDot = 1;
        for (size_t a = 0; a < normalsHere.size(); a++)
          for (size_t b = a + 1; b < normalsHere.size(); b++) {
            const V3 &na = normalsHere[a], &nb = normalsHere[b];
            minDot = std::min(minDot, na[0] * nb[0] + na[1] * nb[1] + na[2] * nb[2]);
          }
        bool sharp = minDot < SHARP_COS;
        V3 c{mass[0] / m, mass[1] / m, mass[2] / m};
        double r[3] = {atb[0] - (ata[0] * c[0] + ata[1] * c[1] + ata[2] * c[2]), atb[1] - (ata[1] * c[0] + ata[3] * c[1] + ata[4] * c[2]),
                       atb[2] - (ata[2] * c[0] + ata[4] * c[1] + ata[5] * c[2])};
        double values[3], vectors[3][3];
        eigenSym3(ata, values, vectors);
        double lmax = std::max({values[0], values[1], values[2]});
        V3 x = c;
        int rank = 0;
        if (sharp)
          for (int q = 0; q < 3; q++) {
            if (values[q] <= lmax * 0.1) continue;
            rank++;
            const double *v = vectors[q];
            double coef = (v[0] * r[0] + v[1] * r[1] + v[2] * r[2]) / values[q];
            for (int a = 0; a < 3; a++) x[a] += v[a] * coef;
          }
        V3 lo = pos(i, j, k);
        bool inside = true;
        for (int a = 0; a < 3; a++) inside &= x[a] >= lo[a] - H[a] * 0.25 && x[a] <= lo[a] + H[a] * 1.25;
        if (rank >= 2 && (!inside || std::fabs(dist(x[0], x[1], x[2])) > std::min({hx, hy, hz}) * 0.08)) {
          x = c;
          rank = 1;
        } else if (!inside) {
          for (int a = 0; a < 3; a++) x[a] = std::min(lo[a] + H[a], std::max(lo[a], x[a]));
        }
        cellVert[idx(i, j, k)] = (int)(P.size() / 3);
        P.push_back(x[0]);
        P.push_back(x[1]);
        P.push_back(x[2]);
        rank1.push_back(rank <= 1);
      }
  if (P.empty()) return std::nullopt;

  std::vector<uint32_t> Iraw;
  auto quad = [&](int a, int b, int c, int d, bool flip) {
    if (a < 0 || b < 0 || c < 0 || d < 0) return;
    if (flip) Iraw.insert(Iraw.end(), {(uint32_t)a, (uint32_t)c, (uint32_t)b, (uint32_t)a, (uint32_t)d, (uint32_t)c});
    else Iraw.insert(Iraw.end(), {(uint32_t)a, (uint32_t)b, (uint32_t)c, (uint32_t)a, (uint32_t)c, (uint32_t)d});
  };
  auto cv = [&](long i, long j, long k) { return cellVert[idx(i, j, k)]; };
  for (long k = 0; k < nz; k++)
    for (long j = 0; j < ny; j++)
      for (long i = 0; i < nx; i++) {
        bool v0 = vals[idx(i, j, k)] < 0;
        if (i < nx - 1 && j > 0 && k > 0 && j < ny - 1 && k < nz - 1 && v0 != (vals[idx(i + 1, j, k)] < 0))
          quad(cv(i, j - 1, k - 1), cv(i, j, k - 1), cv(i, j, k), cv(i, j - 1, k), !v0);
        if (j < ny - 1 && i > 0 && k > 0 && i < nx - 1 && k < nz - 1 && v0 != (vals[idx(i, j + 1, k)] < 0))
          quad(cv(i - 1, j, k - 1), cv(i - 1, j, k), cv(i, j, k), cv(i, j, k - 1), !v0);
        if (k < nz - 1 && i > 0 && j > 0 && i < nx - 1 && j < ny - 1 && v0 != (vals[idx(i, j, k + 1)] < 0))
          quad(cv(i - 1, j - 1, k), cv(i, j - 1, k), cv(i, j, k), cv(i - 1, j, k), !v0);
      }

  size_t nv0 = P.size() / 3;
  std::vector<float> base(P.begin(), P.end());
  for (size_t v = 0; v < nv0; v++) {
    if (!rank1[v]) continue;
    double x = base[v * 3], y = base[v * 3 + 1], z = base[v * 3 + 2];
    V3 n = grad(x, y, z);
    double d = dist(x, y, z);
    if (std::fabs(d) < hmax) { x -= n[0] * d; y -= n[1] * d; z -= n[2] * d; }
    base[v * 3] = (float)x;
    base[v * 3 + 1] = (float)y;
    base[v * 3 + 2] = (float)z;
  }
  std::vector<uint32_t> I = Iraw;
  if (opt.simplify) {
    double cellMin = std::min({hx, hy, hz});
    auto sm = simplifyMesh(base, I, opt.tolerance > 0 ? opt.tolerance : cellMin * 0.15, opt.maxEdge, &dist, cellMin * 3);
    base = std::move(sm.positions);
    I = std::move(sm.indices);
  }
  size_t nv = base.size() / 3;
  std::vector<float> smoothN(nv * 3);
  for (size_t v = 0; v < nv; v++) {
    V3 g = grad(base[v * 3], base[v * 3 + 1], base[v * 3 + 2]);
    for (int a = 0; a < 3; a++) smoothN[v * 3 + a] = (float)g[a];
  }

  size_t nt = I.size() / 3;
  std::vector<float> faceN(nt * 3, 0.f);
  for (size_t t = 0; t < nt; t++) {
    size_t a = I[t * 3] * 3, b = I[t * 3 + 1] * 3, c = I[t * 3 + 2] * 3;
    double ux = base[b] - base[a], uy = base[b + 1] - base[a + 1], uz = base[b + 2] - base[a + 2];
    double wx = base[c] - base[a], wy = base[c + 1] - base[a + 1], wz = base[c + 2] - base[a + 2];
    double fx = uy * wz - uz * wy, fy = uz * wx - ux * wz, fz = ux * wy - uy * wx;
    double l = std::sqrt(fx * fx + fy * fy + fz * fz);
    if (l > 0) { faceN[t * 3] = (float)(fx / l); faceN[t * 3 + 1] = (float)(fy / l); faceN[t * 3 + 2] = (float)(fz / l); }
  }
  std::vector<int> count(nv + 1, 0);
  for (uint32_t v : I) count[v + 1]++;
  for (size_t v = 0; v < nv; v++) count[v + 1] += count[v];
  std::vector<int> fill(count.begin(), count.begin() + nv);
  std::vector<int> incident(I.size());
  for (size_t q = 0; q < I.size(); q++) incident[fill[I[q]]++] = (int)(q / 3);

  std::vector<float> outP, outN;
  std::vector<uint32_t> remap(I.size());
  for (size_t v = 0; v < nv; v++) {
    struct G { V3 ref, sum; std::vector<int> faces; bool hasRef; };
    std::vector<G> groups;
    std::vector<int> degenerate;
    for (int q = count[v]; q < count[v + 1]; q++) {
      int t = incident[q];
      V3 n{faceN[t * 3], faceN[t * 3 + 1], faceN[t * 3 + 2]};
      if (n[0] == 0 && n[1] == 0 && n[2] == 0) { degenerate.push_back(t); continue; }
      G *g = nullptr;
      for (auto &gr : groups)
        if (gr.ref[0] * n[0] + gr.ref[1] * n[1] + gr.ref[2] * n[2] > SHARP_COS) { g = &gr; break; }
      if (!g) { groups.push_back({n, {0, 0, 0}, {}, true}); g = &groups.back(); }
      g->faces.push_back(t);
      for (int a = 0; a < 3; a++) g->sum[a] += n[a];
    }
    if (groups.empty()) groups.push_back({{0, 0, 0}, {0, 0, 0}, {}, false});
    groups[0].faces.insert(groups[0].faces.end(), degenerate.begin(), degenerate.end());
    for (auto &g : groups) {
      uint32_t id = (uint32_t)(outP.size() / 3);
      outP.insert(outP.end(), {base[v * 3], base[v * 3 + 1], base[v * 3 + 2]});
      if (groups.size() > 1) {
        double l = std::sqrt(g.sum[0] * g.sum[0] + g.sum[1] * g.sum[1] + g.sum[2] * g.sum[2]);
        if (l == 0) l = 1;
        outN.insert(outN.end(), {(float)(g.sum[0] / l), (float)(g.sum[1] / l), (float)(g.sum[2] / l)});
      } else outN.insert(outN.end(), {smoothN[v * 3], smoothN[v * 3 + 1], smoothN[v * 3 + 2]});
      for (int t : g.faces)
        for (int q = t * 3; q < t * 3 + 3; q++)
          if (I[q] == v) remap[q] = id;
    }
  }
  Mesh out;
  out.positions = std::move(outP);
  out.normals = std::move(outN);
  if (opt.colorAt) {
    out.colors.resize(out.positions.size());
    for (size_t v = 0; v < out.positions.size() / 3; v++) {
      V3 c = opt.colorAt(out.positions[v * 3], out.positions[v * 3 + 1], out.positions[v * 3 + 2]);
      for (int a = 0; a < 3; a++) out.colors[v * 3 + a] = (float)c[a];
    }
  }
  out.indices = std::move(remap);
  return out;
}

// ---------- simplificação ----------

namespace {
struct EdgeE { int a, b, va, vb; double x, y, z; };
struct Heap {
  std::vector<double> cost;
  std::vector<EdgeE> data;
  size_t size() const { return cost.size(); }
  void push(double c, const EdgeE &d) {
    size_t i = cost.size();
    cost.push_back(c);
    data.push_back(d);
    while (i > 0) {
      size_t p = (i - 1) >> 1;
      if (cost[p] <= c) break;
      cost[i] = cost[p];
      data[i] = data[p];
      i = p;
    }
    cost[i] = c;
    data[i] = d;
  }
  EdgeE pop() {
    EdgeE top = data[0];
    size_t last = cost.size() - 1;
    double c = cost[last];
    EdgeE d = data[last];
    cost.pop_back();
    data.pop_back();
    if (last > 0) {
      size_t i = 0;
      for (;;) {
        size_t l = 2 * i + 1;
        if (l >= last) break;
        if (l + 1 < last && cost[l + 1] < cost[l]) l++;
        if (cost[l] >= c) break;
        cost[i] = cost[l];
        data[i] = data[l];
        i = l;
      }
      cost[i] = c;
      data[i] = d;
    }
    return top;
  }
};
}  // namespace

static const int MAX_VALENCE = 20;

Simplified simplifyMesh(const std::vector<float> &positions, const std::vector<uint32_t> &indices, double tolerance, double maxEdge, const DistFn *surfaceDist,
                        double checkEdge) {
  size_t nv = positions.size() / 3, nt = indices.size() / 3;
  if (nt < 8 || !(tolerance > 0)) return {positions, indices};
  std::vector<double> P(positions.begin(), positions.end());
  std::vector<int> F(indices.begin(), indices.end());
  std::vector<uint8_t> faceAlive(nt, 1), dead(nv, 0), locked(nv, 0);
  std::vector<double> Q(nv * 10, 0.0);
  std::vector<int> version(nv, 0);
  std::vector<std::vector<int>> adj(nv);
  for (size_t t = 0; t < nt; t++)
    for (int k = 0; k < 3; k++) adj[F[t * 3 + k]].push_back((int)t);

  auto faceNormal = [&](size_t t, double out[3]) {
    size_t a = F[t * 3] * 3, b = F[t * 3 + 1] * 3, c = F[t * 3 + 2] * 3;
    double ux = P[b] - P[a], uy = P[b + 1] - P[a + 1], uz = P[b + 2] - P[a + 2];
    double vx = P[c] - P[a], vy = P[c + 1] - P[a + 1], vz = P[c + 2] - P[a + 2];
    out[0] = uy * vz - uz * vy;
    out[1] = uz * vx - ux * vz;
    out[2] = ux * vy - uy * vx;
    return std::sqrt(out[0] * out[0] + out[1] * out[1] + out[2] * out[2]);
  };
  double n[3];
  for (size_t t = 0; t < nt; t++) {
    double len = faceNormal(t, n);
    if (len < 1e-18) continue;
    double a = n[0] / len, b = n[1] / len, c = n[2] / len;
    size_t v0 = F[t * 3] * 3;
    double d = -(a * P[v0] + b * P[v0 + 1] + c * P[v0 + 2]);
    double q[10] = {a * a, a * b, a * c, a * d, b * b, b * c, b * d, c * c, c * d, d * d};
    for (int k = 0; k < 3; k++) {
      size_t o = F[t * 3 + k] * 10;
      for (int j = 0; j < 10; j++) Q[o + j] += q[j];
    }
  }

  // contagem das arestas na ordem em que aparecem (como o Map do JS)
  std::vector<std::pair<long long, int>> edgeList;
  std::unordered_map<long long, size_t> edgeAt;
  auto key = [&](long long a, long long b) { return a < b ? a * (long long)nv + b : b * (long long)nv + a; };
  for (size_t t = 0; t < nt; t++)
    for (int k = 0; k < 3; k++) {
      long long kk = key(F[t * 3 + k], F[t * 3 + (k + 1) % 3]);
      auto it = edgeAt.find(kk);
      if (it == edgeAt.end()) { edgeAt[kk] = edgeList.size(); edgeList.push_back({kk, 1}); }
      else edgeList[it->second].second++;
    }
  for (auto &[kk, c] : edgeList)
    if (c != 2) { locked[kk / nv] = 1; locked[kk % nv] = 1; }

  auto qcost = [](const double *q, double x, double y, double z) {
    return q[0] * x * x + 2 * q[1] * x * y + 2 * q[2] * x * z + 2 * q[3] * x + q[4] * y * y + 2 * q[5] * y * z + 2 * q[6] * y + q[7] * z * z + 2 * q[8] * z + q[9];
  };
  double qsum[10], best[3];
  auto plan = [&](int a, int b) {
    for (int j = 0; j < 10; j++) qsum[j] = Q[a * 10 + j] + Q[b * 10 + j];
    const double *q = qsum;
    double ax = P[a * 3], ay = P[a * 3 + 1], az = P[a * 3 + 2];
    double bx = P[b * 3], by = P[b * 3 + 1], bz = P[b * 3 + 2];
    double mx = (ax + bx) / 2, my = (ay + by) / 2, mz = (az + bz) / 2;
    double bc = qcost(q, mx, my, mz);
    best[0] = mx; best[1] = my; best[2] = mz;
    double ca = qcost(q, ax, ay, az);
    if (ca < bc) { bc = ca; best[0] = ax; best[1] = ay; best[2] = az; }
    double cb = qcost(q, bx, by, bz);
    if (cb < bc) { bc = cb; best[0] = bx; best[1] = by; best[2] = bz; }
    double m00 = q[0], m01 = q[1], m02 = q[2], m11 = q[4], m12 = q[5], m22 = q[7];
    double c0 = m11 * m22 - m12 * m12, c1 = m01 * m22 - m12 * m02, c2 = m01 * m12 - m11 * m02;
    double det = m00 * c0 - m01 * c1 + m02 * c2;
    if (std::fabs(det) > 1e-12) {
      double r0 = -q[3], r1 = -q[6], r2 = -q[8];
      double x = (r0 * c0 - m01 * (r1 * m22 - m12 * r2) + m02 * (r1 * m12 - m11 * r2)) / det;
      double y = (m00 * (r1 * m22 - m12 * r2) - r0 * c1 + m02 * (m01 * r2 - r1 * m02)) / det;
      double z = (m00 * (m11 * r2 - r1 * m12) - m01 * (m01 * r2 - r1 * m02) + r0 * c2) / det;
      double elen2 = (bx - ax) * (bx - ax) + (by - ay) * (by - ay) + (bz - az) * (bz - az);
      if ((x - mx) * (x - mx) + (y - my) * (y - my) + (z - mz) * (z - mz) < elen2) {
        double cx = qcost(q, x, y, z);
        if (cx < bc) { bc = cx; best[0] = x; best[1] = y; best[2] = z; }
      }
    }
    return std::max(0.0, bc);
  };

  Heap heap;
  auto pushEdge = [&](int a, int b) {
    if (locked[a] || locked[b]) return;
    double cost = plan(a, b);
    heap.push(cost, {a, b, version[a], version[b], best[0], best[1], best[2]});
  };
  for (auto &[kk, c] : edgeList) pushEdge((int)(kk / nv), (int)(kk % nv));

  double tol2 = tolerance * tolerance;
  std::vector<int> markA(nv, 0), markB(nv, 0), markN(nv, 0);
  int stamp = 0, stampN = 0;
  double tri[9];
  auto normalMoved = [&](size_t t, int a, int b, double x, double y, double z, double out[3]) {
    int v0 = F[t * 3], v1 = F[t * 3 + 1], v2 = F[t * 3 + 2];
    bool m0 = v0 == a || v0 == b, m1 = v1 == a || v1 == b, m2 = v2 == a || v2 == b;
    double x0 = m0 ? x : P[v0 * 3], y0 = m0 ? y : P[v0 * 3 + 1], z0 = m0 ? z : P[v0 * 3 + 2];
    double x1 = m1 ? x : P[v1 * 3], y1 = m1 ? y : P[v1 * 3 + 1], z1 = m1 ? z : P[v1 * 3 + 2];
    double x2 = m2 ? x : P[v2 * 3], y2 = m2 ? y : P[v2 * 3 + 1], z2 = m2 ? z : P[v2 * 3 + 2];
    double tt[9] = {x0, y0, z0, x1, y1, z1, x2, y2, z2};
    std::copy(tt, tt + 9, tri);
    double ux = x1 - x0, uy = y1 - y0, uz = z1 - z0, vx = x2 - x0, vy = y2 - y0, vz = z2 - z0;
    out[0] = uy * vz - uz * vy;
    out[1] = uz * vx - ux * vz;
    out[2] = ux * vy - uy * vx;
    return std::sqrt(out[0] * out[0] + out[1] * out[1] + out[2] * out[2]);
  };
  double checkEdge2 = checkEdge * checkEdge, limit = tolerance * 1.5;
  auto nearSurface = [&]() {
    auto e = [&](int i, int j) { return (tri[i] - tri[j]) * (tri[i] - tri[j]) + (tri[i + 1] - tri[j + 1]) * (tri[i + 1] - tri[j + 1]) + (tri[i + 2] - tri[j + 2]) * (tri[i + 2] - tri[j + 2]); };
    if (std::max({e(0, 3), e(3, 6), e(6, 0)}) <= checkEdge2) return true;
    double pts[4][3] = {{(tri[0] + tri[3] + tri[6]) / 3, (tri[1] + tri[4] + tri[7]) / 3, (tri[2] + tri[5] + tri[8]) / 3},
                        {(tri[0] + tri[3]) / 2, (tri[1] + tri[4]) / 2, (tri[2] + tri[5]) / 2},
                        {(tri[3] + tri[6]) / 2, (tri[4] + tri[7]) / 2, (tri[5] + tri[8]) / 2},
                        {(tri[6] + tri[0]) / 2, (tri[7] + tri[1]) / 2, (tri[8] + tri[2]) / 2}};
    for (auto &q : pts)
      if (std::fabs((*surfaceDist)(q[0], q[1], q[2])) > limit) return false;
    return true;
  };
  double before[3], after[3];
  std::vector<int> neigh;
  auto neighborsOf = [&](int a, int b) {
    neigh.clear();
    stampN++;
    for (int v : {a, b})
      for (int t : adj[v]) {
        if (!faceAlive[t]) continue;
        for (int k = 0; k < 3; k++) {
          int w = F[t * 3 + k];
          if (w != a && w != b && markN[w] != stampN) { markN[w] = stampN; neigh.push_back(w); }
        }
      }
  };

  while (heap.size() && heap.cost[0] <= tol2) {
    EdgeE e = heap.pop();
    int a = e.a, b = e.b;
    if (dead[a] || dead[b] || version[a] != e.va || version[b] != e.vb) continue;
    stamp++;
    bool connected = false;
    for (int t : adj[a]) {
      if (!faceAlive[t]) continue;
      for (int k = 0; k < 3; k++) {
        int w = F[t * 3 + k];
        markA[w] = stamp;
        if (w == b) connected = true;
      }
    }
    if (!connected) continue;
    int common = 0;
    for (int t : adj[b]) {
      if (!faceAlive[t]) continue;
      for (int k = 0; k < 3; k++) {
        int w = F[t * 3 + k];
        if (w != a && w != b && markA[w] == stamp && markB[w] != stamp) { markB[w] = stamp; common++; }
      }
    }
    if (common != 2) continue;
    // a ordem dos vizinhos importa só para o "break" do comprimento: o gerador do JS para no primeiro longo
    int valence = 0;
    bool tooLong = false;
    double maxEdge2 = maxEdge * maxEdge;
    neighborsOf(a, b);
    for (int w : neigh) {
      valence++;
      if (std::isfinite(maxEdge2) &&
          (P[w * 3] - e.x) * (P[w * 3] - e.x) + (P[w * 3 + 1] - e.y) * (P[w * 3 + 1] - e.y) + (P[w * 3 + 2] - e.z) * (P[w * 3 + 2] - e.z) > maxEdge2) {
        tooLong = true;
        break;
      }
    }
    if (tooLong || valence > MAX_VALENCE) continue;
    bool ok = true;
    for (int v : {a, b}) {
      for (int t : adj[v]) {
        if (!faceAlive[t]) continue;
        int fa = F[t * 3], fb = F[t * 3 + 1], fc = F[t * 3 + 2];
        if ((fa == a || fb == a || fc == a) && (fa == b || fb == b || fc == b)) continue;
        double l0 = faceNormal(t, before);
        double l1 = normalMoved(t, a, b, e.x, e.y, e.z, after);
        if (l1 < l0 * 1e-3 || (before[0] * after[0] + before[1] * after[1] + before[2] * after[2]) < 0.3 * l0 * l1) { ok = false; break; }
        if (surfaceDist && !nearSurface()) { ok = false; break; }
      }
      if (!ok) break;
    }
    if (!ok) continue;
    P[a * 3] = e.x;
    P[a * 3 + 1] = e.y;
    P[a * 3 + 2] = e.z;
    for (int j = 0; j < 10; j++) Q[a * 10 + j] += Q[b * 10 + j];
    std::vector<int> keep;
    for (int t : adj[a])
      if (faceAlive[t]) keep.push_back(t);
    for (int t : adj[b]) {
      if (!faceAlive[t]) continue;
      bool hasA = false;
      for (int k = 0; k < 3; k++)
        if (F[t * 3 + k] == a) hasA = true;
      if (hasA) { faceAlive[t] = 0; continue; }
      for (int k = 0; k < 3; k++)
        if (F[t * 3 + k] == b) F[t * 3 + k] = a;
      keep.push_back(t);
    }
    adj[a].clear();
    for (int t : keep)
      if (faceAlive[t]) adj[a].push_back(t);
    adj[b].clear();
    dead[b] = 1;
    version[a]++;
    stamp++;
    for (int t : adj[a])
      for (int k = 0; k < 3; k++) {
        int w = F[t * 3 + k];
        if (w != a && markA[w] != stamp) { markA[w] = stamp; pushEdge(a, w); }
      }
  }

  std::vector<int> remap(nv, -1);
  Simplified out;
  for (size_t t = 0; t < nt; t++) {
    if (!faceAlive[t]) continue;
    for (int k = 0; k < 3; k++) {
      int v = F[t * 3 + k];
      if (remap[v] < 0) {
        remap[v] = (int)(out.positions.size() / 3);
        out.positions.insert(out.positions.end(), {(float)P[v * 3], (float)P[v * 3 + 1], (float)P[v * 3 + 2]});
      }
      out.indices.push_back((uint32_t)remap[v]);
    }
  }
  return out;
}

}  // namespace tdi
