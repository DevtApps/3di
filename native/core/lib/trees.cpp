// Gerador de árvores (port de lib/trees.js).
#include "kit.h"

namespace tdi::kit {

struct TreeKind {
  const char *name;
  double h;
  const char *trunk, *leaves, *top;
};
static const TreeKind KINDS[] = {
    {"oak", 5, "#6b4a2b", "#3a7d2c", "#86c64a"},     {"pine", 6, "#5a3e24", "#1f5a34", "#4f9a5a"},
    {"birch", 5, "#e8e4da", "#6fa83a", "#c3e06a"},   {"palm", 6, "#8a6a42", "#2f8a3a", "#8fd25a"},
    {"willow", 5.5, "#5e4a30", "#5a9a3a", "#b4d86a"}, {"dead", 4, "#4a3b2e", "#000000", "#000000"},
    {"round", 3, "#6b4a2b", "#3f9a3a", "#9be05a"},   {"bonsai", 0.5, "#5b3f2a", "#2f7a3a", "#7cc14a"},
};

struct Broad {
  double trunkH, trunkR;
  int nb[3];
  double tilt[2], len[2], blobR[2], crown, lift, squash;
  int strands[3];  // 0: sem ramos pendentes
};
static const std::pair<const char *, Broad> BROADLEAF[] = {
    {"oak", {0.4, 0.05, {3, 4, 6}, {38, 62}, {0.22, 0.32}, {0.17, 0.23}, 0.27, 0.14, 0.82, {0, 0, 0}}},
    {"birch", {0.55, 0.026, {3, 4, 5}, {14, 34}, {0.18, 0.27}, {0.1, 0.14}, 0.15, 0.1, 1.15, {0, 0, 0}}},
    {"willow", {0.42, 0.06, {3, 4, 5}, {50, 75}, {0.2, 0.3}, {0.16, 0.21}, 0.24, 0.1, 0.8, {6, 10, 14}}},
    {"round", {0.5, 0.035, {0, 0, 2}, {30, 50}, {0.1, 0.16}, {0.12, 0.16}, 0.3, 0.18, 0.95, {0, 0, 0}}},
};

struct TB {
  Style S;
  RT R;
  double H;
  C3 trunk, leaf, leafTop;
  double u(double a, double b) const { return R.u(a, b); }
};
static int lvl(const Style &S, const int a[3]) { return a[S.name == "lowpoly" ? 0 : S.name == "stylized" ? 1 : 2]; }
static int lvl(const Style &S, int a, int b, int c) { int x[3] = {a, b, c}; return lvl(S, x); }

static ShapeP blob(const TB &B, const V3 &pos, double r, double squash = 0.85) {
  const Style &S = B.S;
  ShapeP s;
  if (S.facets) {
    double x = B.u(-18, 18);
    double y = B.u(0, 90);
    double z = B.u(-18, 18);
    s = rot(box(r * 1.55, r * 1.35 * squash, r * 1.55), x, y, z);
  } else s = scale(sphere(r), V3{1, squash, 1});
  if (S.name == "realistic") s = displace(s, r * 0.26, r * 0.75);
  C3 base = jitter(B.leaf, B.R, 6, S.vary, S.vary * 0.8);
  C3 tip = jitter(B.leafTop, B.R, 8, S.vary, S.vary * 0.8);
  return move(paintStyle(s, S, base, tip, r * 0.9), pos);
}

static ShapeP bark(const TB &B, const ShapeP &shape, bool birch = false) {
  const Style &S = B.S;
  auto c = color(shape, B.trunk);
  if (birch && S.name != "lowpoly") return texture(c, "stripes", {col({0.16, 0.14, 0.13}), B.H * 0.045, "y", S.bump * 0.5});
  if (S.name == "realistic") return texture(c, "wood", {col(mixc(B.trunk, {0, 0, 0}, 0.55)), B.H * 0.012, "y", S.bump});
  if (S.gradient) return texture(c, "gradient", {col(mixc(B.trunk, {1, 0.95, 0.85}, 0.2))});
  return c;
}

struct Chain {
  std::vector<ShapeP> parts;
  V3 top;
};
static Chain trunkChain(const TB &B, int pieces, double height, double r0, double r1, double bend) {
  Chain c;
  V3 pos{0, 0, 0};
  double yaw = B.u(0, 360);
  for (int k = 0; k < pieces; k++) {
    V3 next = addv(pos, scalev(dirVec(yaw + k * 70, bend * (k + 1)), height / pieces));
    c.parts.push_back(taper(pos, next, r0 + (r1 - r0) * (double(k) / pieces), r0 + (r1 - r0) * (double(k + 1) / pieces)));
    pos = next;
  }
  c.top = pos;
  return c;
}

static std::vector<ShapeP> broadleaf(const TB &B, const Broad &P, const std::string &kind) {
  const Style &S = B.S;
  double H = B.H;
  int pieces = lvl(S, 1, 2, 3);
  int nb = lvl(S, P.nb);
  double tH = H * P.trunkH, r0 = H * P.trunkR;
  double bend = B.u(2, 7) * (S.name == "lowpoly" ? 0.5 : 1);
  Chain tr = trunkChain(B, pieces, tH, r0, r0 * 0.6, bend);
  V3 top = tr.top;
  std::vector<ShapeP> wood{bark(B, group(tr.parts), kind == "birch")};
  std::vector<ShapeP> leaves, branches;
  for (int i = 0; i < nb; i++) {
    double yaw = (i * 360.0) / nb + B.u(-25, 25);
    double tilt = B.u(P.tilt[0], P.tilt[1]);
    double len = H * B.u(P.len[0], P.len[1]);
    V3 from = addv(top, {0, -tH * B.u(0, 0.15), 0});
    V3 to = addv(from, scalev(dirVec(yaw, tilt), len));
    branches.push_back(taper(from, to, r0 * 0.5, r0 * 0.2));
    double br = H * B.u(P.blobR[0], P.blobR[1]);
    leaves.push_back(blob(B, addv(to, {0, H * 0.03, 0}), br, P.squash));
    if (S.name == "realistic") {
      double dy = B.u(-60, 60);
      leaves.push_back(blob(B, addv(to, scalev(dirVec(yaw + dy, tilt + 25), len * 0.4)), H * P.blobR[0] * 0.65, P.squash));
    }
  }
  if (!branches.empty()) wood.push_back(color(group(branches), mixc(B.trunk, {0, 0, 0}, 0.15)));
  leaves.push_back(blob(B, addv(top, {0, H * P.lift, 0}), H * P.crown, P.squash));
  if (P.strands[0]) {
    int n = lvl(S, P.strands);
    double rim = H * 0.2, y0 = top[1] + H * P.lift * 0.8;
    for (int i = 0; i < n; i++) {
      double yaw = (i * 360.0) / n + B.u(-14, 14);
      V3 atp = addv(top, {std::cos((yaw * M_PI) / 180) * rim, y0 - top[1], std::sin((yaw * M_PI) / 180) * rim});
      double len = H * B.u(0.3, 0.42);
      Ribbon r = placedRibbon(atp, yaw + 90, len, H * 0.035, {168, 176}, 0.25);
      C3 base = jitter(B.leaf, B.R, 6, S.vary, S.vary);
      leaves.push_back(paintStyle(r.shape, S, base, B.leafTop, H * 0.2));
    }
  }
  wood.insert(wood.end(), leaves.begin(), leaves.end());
  return wood;
}

static std::vector<ShapeP> pine(const TB &B) {
  const Style &S = B.S;
  double H = B.H;
  int n = lvl(S, 4, 6, 8);
  std::vector<ShapeP> parts{color(taper({0, 0, 0}, {0, H * 0.9, 0}, H * 0.03, H * 0.008), B.trunk)};
  for (int i = 0; i < n; i++) {
    double t = n == 1 ? 0 : double(i) / (n - 1);
    double r = H * 0.23 * (1 - 0.82 * t), hh = H * 0.3 * (1 - 0.25 * t), y0 = H * 0.16 + t * H * 0.7;
    ShapeP tier;
    if (S.facets) {
      double ry = B.u(0, 90);
      tier = rot(at(pyramid(r * 2, hh), 0.0, y0 + hh / 2, 0.0), 0.0, ry, 0.0, V3{0, y0, 0});
    } else tier = at(cone(r, hh), 0.0, y0 + hh / 2, 0.0);
    if (S.name == "realistic") tier = displace(tier, r * 0.13, r * 0.5);
    C3 base = jitter(mixc(B.leaf, B.leafTop, t * 0.5), B.R, 4, S.vary, S.vary * 0.7);
    parts.push_back(paintStyle(tier, S, base, mixc(base, B.leafTop, 0.45), r * 0.7));
  }
  return parts;
}

static std::vector<ShapeP> palm(const TB &B) {
  const Style &S = B.S;
  double H = B.H;
  int pieces = lvl(S, 2, 3, 4);
  Chain tr = trunkChain(B, pieces, H * 0.78, H * 0.035, H * 0.022, 6);
  auto trunk = color(group(tr.parts), B.trunk);
  if (S.name != "lowpoly") trunk = texture(trunk, "stripes", {col(mixc(B.trunk, {0, 0, 0}, 0.4)), H * 0.035, "y", S.bump * 0.6});
  std::vector<ShapeP> parts{trunk};
  int n = lvl(S, 5, 7, 10);
  for (int i = 0; i < n; i++) {
    double yaw = (i * 360.0) / n + B.u(-14, 14);
    std::vector<double> tilts;
    if (S.name == "lowpoly") tilts = {70, 118};
    else {
      double t0 = 48 + B.u(-8, 8);
      double t2 = 112 + B.u(0, 14);
      tilts = {t0, 82, t2};
    }
    double len = H * B.u(0.46, 0.58);
    Ribbon r = placedRibbon(tr.top, yaw, len, H * 0.11, tilts, 0.14);
    C3 base = jitter(B.leaf, B.R, 5, S.vary, S.vary * 0.6);
    parts.push_back(paintStyle(r.shape, S, base, B.leafTop, H * 0.2));
  }
  for (int i = 0; i < 3; i++) {
    double ox = B.u(-0.12, 0.12) * H * 0.4;
    double oz = B.u(-0.12, 0.12) * H * 0.4;
    V3 c = addv(tr.top, {ox, -H * 0.03, oz});
    parts.push_back(color(at(sphere(H * 0.028), c[0], c[1], c[2]), C3{0.42, 0.28, 0.12}));
  }
  return parts;
}

static std::vector<ShapeP> dead(const TB &B) {
  const Style &S = B.S;
  double H = B.H;
  int depth = lvl(S, 2, 3, 3);
  std::vector<ShapeP> out;
  std::function<void(V3, double, double, double, double, int)> grow = [&](V3 pos, double yaw, double tilt, double len, double r, int d) {
    V3 to = addv(pos, scalev(dirVec(yaw, tilt), len));
    out.push_back(taper(pos, to, r, r * 0.62));
    if (d == 0) return;
    int kids = d == depth ? 3 : 2;
    for (int k = 0; k < kids; k++) {
      double y = yaw + (k * 360.0) / kids + B.u(-40, 40);
      double t = std::min(85.0, tilt + B.u(18, 40));
      double l = len * B.u(0.6, 0.78);
      grow(to, y, t, l, r * 0.6, d - 1);
    }
  };
  double y0 = B.u(0, 360);
  grow({0, 0, 0}, y0, 3, H * 0.4, H * 0.05, depth);
  return {bark(B, group(out))};
}

static std::vector<ShapeP> bonsai(const TB &B) {
  const Style &S = B.S;
  double H = B.H;
  auto pot = color(at(box(H * 0.55, H * 0.2, H * 0.4, H * 0.02), 0.0, H * 0.1, 0.0), C3{0.55, 0.3, 0.2});
  auto soil = color(at(box(H * 0.5, H * 0.02, H * 0.35), 0.0, H * 0.205, 0.0), C3{0.2, 0.13, 0.09});
  V3 base{0, H * 0.2, 0};
  std::vector<ShapeP> parts{pot, soil}, tr;
  V3 pos = base;
  int n = lvl(S, 2, 3, 3);
  for (int k = 0; k < n; k++) {
    V3 next = addv(pos, scalev(dirVec(k % 2 ? 40 : 220, 22 + k * 6), H * 0.55 / n));
    tr.push_back(taper(pos, next, H * 0.04 * (1 - k * 0.2), H * 0.04 * (1 - (k + 1) * 0.2)));
    pos = next;
  }
  parts.push_back(bark(B, group(tr)));
  int discs = lvl(S, 2, 3, 3);
  for (int i = 0; i < discs; i++) {
    V3 c = addv(pos, {(i % 2 ? 1 : -1) * H * 0.18 * (i > 0 ? 1 : 0), -H * 0.12 * i, B.u(-0.04, 0.04) * H});
    parts.push_back(blob(B, c, H * (i == 0 ? 0.24 : 0.19), 0.5));
  }
  return parts;
}

Builtins treeBuiltins(Interp &it) {
  Interp *ip = &it;
  return {{"tree", native("tree", {"kind=\"oak\"", "style=\"stylized\"", "height=None", "trunk=None", "leaves=None", "seed=None"}, [ip](const Args &a, const Node *) -> Value {
    std::string kindName = jsLower(str(a["kind"]));
    const TreeKind *kind = nullptr;
    std::vector<std::string> names;
    for (auto &k : KINDS) { names.push_back(k.name); if (kindName == k.name) kind = &k; }
    if (!kind) {
      std::string h = didYouMean(kindName, names);
      throw ScriptError("tree(): tipo desconhecido '" + str(a["kind"]) + "'", 0, h.empty() ? "use oak, pine, birch, palm, willow, dead, round, bonsai" : h);
    }
    Style S = resolveStyle(a["style"], "tree()");
    double H = a["height"].isNone() ? kind->h : num(a["height"], "height");
    if (!(H > 0)) throw ScriptError("tree(): height deve ser maior que zero");
    RT R = rngFor(*ip, a["seed"]);
    C3 leaf = toSrgb(a["leaves"].isNone() ? Value(kind->leaves) : a["leaves"]);
    TB B{S, R, H, toSrgb(a["trunk"].isNone() ? Value(kind->trunk) : a["trunk"]), leaf,
         a["leaves"].isNone() ? toSrgb(Value(kind->top)) : mixc(leaf, {0.95, 1, 0.5}, 0.45)};
    std::vector<ShapeP> parts;
    if (kindName == "pine") parts = pine(B);
    else if (kindName == "palm") parts = palm(B);
    else if (kindName == "dead") parts = dead(B);
    else if (kindName == "bonsai") parts = bonsai(B);
    else
      for (auto &[k, P] : BROADLEAF)
        if (kindName == k) parts = broadleaf(B, P, kindName);
    return named(group(parts), "arvore-" + kindName);
  })}};
}

}  // namespace tdi::kit
