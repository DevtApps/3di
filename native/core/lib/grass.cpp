// Gerador de grama (port de lib/grass.js).
#include "../expr.h"
#include "kit.h"

namespace tdi::kit {

struct GrassKind {
  const char *name;
  double h, w, lean0, lean1, curve;
  int layers;
  const char *base, *tip;
};
static const GrassKind KINDS[] = {
    {"lawn", 0.1, 0.05, 6, 18, 0.25, 8, "#17501a", "#7fd042"},   {"meadow", 0.17, 0.09, 10, 24, 0.3, 9, "#1d5a18", "#8fd24a"},
    {"tall", 0.5, 0.06, 5, 16, 0.7, 7, "#2a5518", "#b2c94e"},    {"dry", 0.3, 0.05, 10, 30, 0.8, 8, "#6a5a24", "#e6c872"},
    {"tufts", 0.3, 0.05, 14, 34, 0.6, 3, "#1a521b", "#8ccf45"},  {"wheat", 0.55, 0.03, 2, 10, 0.25, 5, "#7a6a2a", "#e8c25a"},
    {"clover", 0.07, 0.05, 6, 16, 0.2, 6, "#1a5a22", "#6fc760"},
};
static const C3 FLOWERS[] = {{1, 1, 0.95}, {1, 0.85, 0.2}, {0.82, 0.5, 0.95}, {1, 0.55, 0.7}, {0.98, 0.45, 0.3}};

struct GStyle {
  Style st;
  int pieces;
  double flat;
};

static Ribbon blade(const GStyle &S, double h, double w, double lean, double yaw, double curve, double flat) {
  ShapeP shape;
  V3 tip;
  if (S.st.facets || S.pieces == 1) {
    shape = ground(scale(pyramid(w, h), V3{1, 1, flat}));
    shape = rot(shape, lean, 0.0, 0.0, O);
    tip = tipOf(h, lean);
  } else {
    int n = S.pieces;
    std::vector<ShapeP> parts;
    V3 pos{0, 0, 0};
    for (int k = 0; k < n; k++) {
      double tilt = lean * (1 + curve * (double(k) / std::max(1, n - 1)) * 1.5);
      double len = h / n;
      double r0 = (w / 2) * (1 - double(k) / n * 0.85), r1 = (w / 2) * std::max(0.04, 1 - double(k + 1) / n * 0.97);
      auto piece = at(scale(cone(r0, len, r1), V3{1, 1, flat}), 0.0, len / 2, 0.0);
      piece = move(rot(piece, tilt, 0.0, 0.0, O), pos);
      parts.push_back(piece);
      pos = addv(pos, tipOf(len, tilt));
    }
    shape = group(parts);
    tip = pos;
  }
  return {rot(shape, 0.0, yaw, 0.0, O), mulMV(rotMatrix(0, yaw, 0), tip)};
}

static ShapeP paint(const ShapeP &unit, const GStyle &S, const C3 &base, const C3 &tip, double t) {
  if (S.st.gradient) return texture(color(unit, base), "gradient", {col(tip)});
  return color(unit, mixc(base, tip, 0.25 + 0.6 * t));
}

Builtins grassBuiltins(Interp &it) {
  Interp *ip = &it;
  return {{"grass", native("grass", {"width=2", "depth=None", "kind=\"meadow\"", "style=\"stylized\"", "height=None", "density=1", "color=None", "tip=None", "flowers=0", "sway=0", "soil=None", "seed=None"},
                           [ip](const Args &a, const Node *) -> Value {
    double W = num(a["width"], "width");
    double D = a["depth"].isNone() ? W : num(a["depth"], "depth");
    if (!(W > 0) || !(D > 0)) throw ScriptError("grass(): largura e fundo devem ser maiores que zero");
    std::string kindName = jsLower(str(a["kind"]));
    const GrassKind *kind = nullptr;
    std::vector<std::string> names;
    for (auto &k : KINDS) { names.push_back(k.name); if (kindName == k.name) kind = &k; }
    if (!kind) {
      std::string h = didYouMean(kindName, names);
      throw ScriptError("grass(): tipo desconhecido '" + str(a["kind"]) + "'", 0, h.empty() ? "use lawn, meadow, tall, dry, tufts, wheat, clover" : h);
    }
    Style style = resolveStyle(a["style"], "grass()");
    double density = num(a["density"], "density");
    if (!(density > 0)) throw ScriptError("grass(): density deve ser maior que zero", 0, "density=1 é o normal; 0.5 é ralo, 2 é denso");
    double H = a["height"].isNone() ? kind->h : num(a["height"], "height");
    double flowerAmount = std::max(0.0, num(a["flowers"], "flowers")) + (kindName == "clover" ? 0.35 : 0);
    double sway = num(a["sway"], "sway");
    RT R = rngFor(*ip, a["seed"]);
    auto u = [&R](double x, double y) { return R.u(x, y); };
    C3 base = toSrgb(a["color"].isNone() ? Value(kind->base) : a["color"]);
    C3 tip = toSrgb(a["tip"].isNone() ? Value(kind->tip) : a["tip"]);

    int gl;
    double flat, wScale;
    int pieces;
    if (style.name == "lowpoly") { pieces = 1; gl = 4; flat = 0.5; wScale = 1.7; }
    else if (style.name == "stylized") { pieces = 1; gl = kind->layers; flat = 0.16; wScale = 1.15; }
    else { pieces = 2; gl = (int)std::floor(kind->layers * 1.5 + 0.5); flat = 0.1; wScale = 0.55; }
    GStyle S{style, pieces, flat};
    int layers = std::max(2, std::min(28, (int)std::floor(gl * density + 0.5)));

    std::vector<ShapeP> layerShapes;
    double gW = W + D * 0.22, gD = D + W * 0.22;
    const double maxCells = 9000;

    auto addGrid = [&](const ShapeP &unit, int layerIndex, const C3 &c) {
      const BBox &ub = unit->bbox();
      double w = ub.max[0] - ub.min[0], d = ub.max[2] - ub.min[2];
      double swayExtra = sway > 0 ? (ub.max[1] - ub.min[1]) * std::sin(rad(sway)) * 2 : 0;
      double esp = (std::max(w, d) + swayExtra) * 1.04;
      double cells = (gW / esp) * (gD / esp);
      int tiles = cells > maxCells ? (int)std::ceil(std::sqrt(cells / maxCells)) : 1;
      double tW = W / tiles, tD = D / tiles;
      double gtW = tW + tD * 0.22, gtD = tD + tW * 0.22;
      double nx = std::max(1.0, std::floor(gtW / esp)), nz = std::max(1.0, std::floor(gtD / esp));
      for (int ix = 0; ix < tiles; ix++)
        for (int iz = 0; iz < tiles; iz++) {
          auto g = repeat(unit, nx, 1, nz, esp);
          g = at(g, layerIndex * 0.017, 0.0, layerIndex * 0.029);
          g = rot(g, 0.0, layerIndex * 5 - 12, 0.0, O);
          double cx = -W / 2 + tW * (ix + 0.5), cz = -D / 2 + tD * (iz + 0.5);
          g = at(g, cx, 0.0, cz);
          auto bx = at(ground(box(tW, 4, tD)), cx, 0.0, cz);
          layerShapes.push_back(color(intersect(g, bx), c));
        }
    };

    for (int l = 0; l < layers; l++) {
      double t = layers == 1 ? 1 : double(l) / (layers - 1);
      double hl = H * (0.55 + 0.7 * t) * u(0.9, 1.1);
      double wl = kind->w * wScale * u(0.85, 1.25);
      double lean = u(kind->lean0, kind->lean1);
      double yaw = l * 47 + u(-15, 15);
      C3 bl = jitter(base, R, 4, style.vary, style.vary * 0.8);
      C3 tp = jitter(tip, R, 6, style.vary, style.vary * 0.8);
      ShapeP unit;
      if (kindName == "tufts") {
        int n = std::min(9, std::max(4, (int)std::floor(7 * std::max(0.6, style.detail) + 0.5)));
        std::vector<ShapeP> blades;
        for (int i = 0; i < n; i++) {
          double bh = hl * u(0.65, 1.15);
          double bw = wl * u(0.9, 1.4);
          double bl2 = lean * u(0.6, 1.4);
          double by = (i * 360.0) / n + u(-22, 22);
          blades.push_back(blade(S, bh, bw, bl2, by, kind->curve, flat).shape);
        }
        unit = paint(group(blades), S, bl, tp, t);
      } else if (kindName == "wheat") {
        Ribbon b = blade(S, hl, wl, lean, yaw, kind->curve, 1);
        auto head = at(rot(ellipsoid(0.022, 0.07, 0.022), lean * 1.6, yaw, 0.0, O), b.tip[0], b.tip[1] + 0.03, b.tip[2]);
        unit = group({paint(b.shape, S, bl, tp, t), color(head, mixc({0.8, 0.6, 0.18}, {0.95, 0.78, 0.36}, t))});
      } else {
        Ribbon b = blade(S, hl, wl, lean, yaw, kind->curve, flat);
        unit = paint(b.shape, S, bl, tp, t);
      }
      if (sway > 0) {
        Value ang = sym("*", {sym("sin", {sym("+", {sym("*", {TIME, 1.6}), l * 1.3})}), sway});
        unit = rot(unit, 0.0, 0.0, ang, O);
      }
      addGrid(unit, l, mixc(base, tip, 0.2));
    }

    if (flowerAmount > 0) {
      int kinds = std::min(5, 3 + (int)std::floor(flowerAmount * 2));
      for (int f = 0; f < kinds; f++) {
        double stemH = H * u(1.0, 1.6) + 0.04;
        auto head = at(sphere(u(0.022, 0.034)), 0.0, stemH, 0.0);
        auto eye = color(at(sphere(0.012), 0.0, stemH + 0.026, 0.0), C3{1, 0.82, 0.15});
        auto stem = color(segment({0, 0, 0}, {0, stemH, 0}, 0.004), mixc(base, tip, 0.3));
        auto unit = group({stem, color(head, FLOWERS[f % 5]), eye});
        double spacing = (0.34 + f * 0.043) / std::sqrt(flowerAmount);
        double nx = std::max(1.0, std::floor(W / spacing)), nz = std::max(1.0, std::floor(D / spacing));
        if (nx * nz > maxCells) continue;
        auto g = repeat(unit, nx, 1, nz, spacing);
        double ox = u(-0.05, 0.05);
        double oz = u(-0.05, 0.05);
        layerShapes.push_back(at(g, ox, 0.0, oz));
      }
    }

    auto out = group(layerShapes);
    if (!a["soil"].isNone()) out = group({out, color(at(box(W, 0.04, D), 0.0, -0.02, 0.0), a["soil"])});
    return named(out, "grama-" + kindName);
  })}};
}

}  // namespace tdi::kit
