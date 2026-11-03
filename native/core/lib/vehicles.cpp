// Gerador de veículos (port de lib/vehicles.js).
#include "kit.h"

namespace tdi::kit {

struct Car {
  const char *name;
  double L, W, bh, cl, ch, cz, c, wr;
  bool bed;
};
static const Car CARS[] = {
    {"car", 4.5, 1.8, 0.68, 2.3, 0.62, -0.1, 0.17, 0.33, false},   {"hatch", 3.9, 1.75, 0.66, 2.3, 0.66, -0.25, 0.17, 0.31, false},
    {"suv", 4.7, 1.9, 0.8, 3.1, 0.68, -0.45, 0.26, 0.38, false},   {"pickup", 5.3, 1.9, 0.85, 1.55, 0.66, 0.95, 0.27, 0.4, true},
    {"van", 5.0, 1.95, 0.9, 3.9, 0.9, -0.2, 0.22, 0.36, false},
};
static const std::vector<std::string> KINDS = {"car", "hatch", "suv", "pickup", "van", "bus", "truck", "tractor", "bike", "motorbike"};
static const std::vector<std::string> PAINTS = {"#c8372d", "#2d5fc8", "#e8e8e2", "#2a2f35", "#d8a21a", "#3a9a5a", "#8a8d92", "#e07a2a"};
static const C3 GLASS = {0.07, 0.12, 0.17};
static const C3 DARK = {0.09, 0.09, 0.1};

static bool isZero(const Value &v) { return v.isNum() && v.n() == 0; }

struct VK {
  Style S;
  C3 paint;
  bool lowpoly, real;
  ShapeP body(const ShapeP &s) const { return material(color(s, paint), {Value(), lowpoly ? 0.85 : 0.28, lowpoly ? 0.0 : 0.55, Value()}); }
  ShapeP dark(const ShapeP &s, const C3 &c = DARK) const { return material(color(s, c), {Value(), 0.7, 0.0, Value()}); }
  ShapeP glass(const ShapeP &s) const { return material(color(s, GLASS), {Value(), 0.05, 0.3, Value()}); }
  ShapeP glow(const ShapeP &s, const C3 &c, double g = 0.9) const { return material(color(s, c), {Value(), 0.2, Value(), g}); }
  ShapeP rbox(double w, double h, double d, double rf) const { return box(w, h, d, lowpoly ? 0 : rf * std::min({w, h, d})); }
  ShapeP wheel(double r, double w, double x, double z, const Value &spin, const C3 &rimCol = {0.78, 0.8, 0.84}) const {
    std::vector<ShapeP> parts{color(rot(cyl(r, w, lowpoly ? 0 : w * 0.3), 0.0, 0.0, 90.0), C3{0.05, 0.05, 0.055})};
    double rr = r * 0.62;
    if (lowpoly) parts.push_back(color(box(w * 1.05, rr * 1.6, rr * 0.35), rimCol));
    else {
      parts.push_back(material(color(rot(cyl(rr, w * 1.04), 0.0, 0.0, 90.0), rimCol), {Value(), 0.3, 0.8, Value()}));
      int spokes = real ? 5 : 1;
      for (int i = 0; i < spokes; i++) {
        auto sp = color(box(w * 1.1, rr * 0.28, rr * 1.7), real ? C3{0.5, 0.52, 0.56} : C3{0.25, 0.25, 0.28});
        parts.push_back(rot(sp, (i * 180.0) / spokes, 0.0, 0.0));
      }
    }
    auto g = group(parts);
    if (!isZero(spin)) g = rot(g, spin, 0.0, 0.0);
    return at(g, x, r, z);
  }
  ShapeP light(double w, double h, double d, double x, double y, double z, const C3 &c, double g) const {
    return lowpoly ? glow(at(box(w, h, d), x, y, z), c, g) : glow(at(ellipsoid(w / 2, h / 2, d / 2), x, y, z), c, g);
  }
};
static VK kitOf(const Style &S, const C3 &paint) { return {S, paint, S.facets, S.name == "realistic"}; }

struct Built {
  std::vector<ShapeP> parts;
  double height;
};

static Built carFamily(const Car &P, const Style &S, const C3 &paint, const Value &spin) {
  VK k = kitOf(S, paint);
  double L = P.L, bh = P.bh, cl = P.cl, ch = P.ch, cz = P.cz, c = P.c, wr = P.wr, W = P.W;
  double Wb = W * 0.93;
  std::vector<ShapeP> parts;
  double r = k.lowpoly ? 0 : 0.28;
  parts.push_back(k.body(at(k.rbox(Wb, bh, L, r * 0.9), 0.0, c + bh / 2, 0.0)));
  double cw = Wb * (P.bed ? 0.92 : 0.9);
  parts.push_back(k.body(at(k.rbox(cw, ch, cl, r), 0.0, c + bh + ch / 2 - 0.02, cz)));
  double gy = c + bh + ch * 0.5;
  for (int sx : {-1, 1}) parts.push_back(k.glass(at(box(0.03, ch * 0.62, cl * 0.84), sx * (cw / 2 + 0.005), gy, cz)));
  double slope = P.bed ? 22 : 28;
  parts.push_back(k.glass(at(rot(box(cw * 0.9, ch * 0.78, 0.03), -slope, 0.0, 0.0), 0.0, gy - 0.02, cz + cl / 2 + 0.01)));
  std::string nm = P.name;
  double back = nm == "hatch" || nm == "suv" || nm == "van" ? 12 : slope;
  parts.push_back(k.glass(at(rot(box(cw * 0.9, ch * 0.78, 0.03), back, 0.0, 0.0), 0.0, gy - 0.02, cz - cl / 2 - 0.01)));
  if (P.bed) {
    double zb = -L / 2 + (cz - cl / 2 + L / 2) / 2;
    double bl = cz - cl / 2 + L / 2;
    parts.push_back(k.dark(at(box(Wb * 0.92, 0.04, bl), 0.0, c + bh + 0.01, zb), {0.12, 0.12, 0.13}));
    for (int sx : {-1, 1}) parts.push_back(k.body(at(k.rbox(0.07, 0.3, bl, 0.2), sx * (Wb / 2 - 0.035), c + bh + 0.15, zb)));
    parts.push_back(k.body(at(k.rbox(Wb * 0.92, 0.3, 0.07, 0.2), 0.0, c + bh + 0.15, -L / 2 + 0.035)));
    parts.push_back(k.body(at(k.rbox(Wb * 0.92, 0.3, 0.07, 0.2), 0.0, c + bh + 0.15, cz - cl / 2 - 0.04)));
  }
  double wb = L * 0.58, tw = k.lowpoly ? 0.24 : 0.26;
  for (int sx : {-1, 1})
    for (int sz : {-1, 1}) {
      parts.push_back(k.wheel(wr, tw, sx * (W / 2 - tw / 2), sz * wb / 2, spin));
      if (k.real) parts.push_back(k.dark(at(rot(cyl(wr * 1.12, 0.04), 0.0, 0.0, 90.0), sx * (Wb / 2 + 0.002), wr, sz * wb / 2)));
    }
  double ly = c + bh * 0.68;
  for (int sx : {-1, 1}) {
    parts.push_back(k.light(0.3, 0.14, 0.06, sx * Wb * 0.32, ly, L / 2 + 0.005, {1, 0.95, 0.75}, 0.8));
    parts.push_back(k.light(0.26, 0.12, 0.05, sx * Wb * 0.34, ly, -L / 2 - 0.005, {0.9, 0.08, 0.06}, 0.7));
  }
  if (k.real || S.name == "stylized") {
    parts.push_back(k.dark(at(box(Wb * 1.0, 0.16, 0.2), 0.0, c + 0.12, L / 2 - 0.05)));
    parts.push_back(k.dark(at(box(Wb * 1.0, 0.16, 0.2), 0.0, c + 0.12, -L / 2 + 0.05)));
  }
  if (k.real) {
    parts.push_back(k.dark(at(box(Wb * 0.42, 0.14, 0.04), 0.0, c + bh * 0.6, L / 2 + 0.01)));
    for (int sx : {-1, 1}) parts.push_back(k.body(at(box(0.14, 0.09, 0.1), sx * (cw / 2 + 0.1), gy + ch * 0.12, cz + cl / 2 - 0.2)));
  }
  return {parts, c + bh + ch};
}

static Built bus(const Style &S, const C3 &paint, const Value &spin) {
  VK k = kitOf(S, paint);
  double L = 11, W = 2.5, H = 3.1, c = 0.3, wr = 0.5, Wb = W * 0.94;
  std::vector<ShapeP> parts{k.body(at(k.rbox(Wb, H - c, L, 0.12), 0.0, c + (H - c) / 2, 0.0))};
  parts.push_back(k.body(color(at(k.rbox(Wb * 1.002, 0.55, L * 1.002, 0.1), 0.0, c + 0.3, 0.0), mixc(paint, {0, 0, 0}, 0.35))));
  for (int sx : {-1, 1}) {
    parts.push_back(k.glass(at(box(0.04, 0.95, L * 0.8), sx * (Wb / 2 + 0.005), 2.05, -0.5)));
    parts.push_back(k.dark(at(box(0.05, 1.7, 1.0), sx * (Wb / 2 + 0.006), 1.15, L * 0.34)));
  }
  parts.push_back(k.glass(at(box(W * 0.9, 1.2, 0.04), 0.0, 1.95, L / 2 + 0.005)));
  parts.push_back(k.glass(at(box(W * 0.7, 0.7, 0.04), 0.0, 2.0, -L / 2 - 0.005)));
  for (int sx : {-1, 1})
    for (double z : {L * 0.3, -L * 0.28}) {
      parts.push_back(k.wheel(wr, 0.32, sx * (W / 2 - 0.16), z, spin));
      if (k.real) parts.push_back(k.dark(at(rot(cyl(wr * 1.1, 0.04), 0.0, 0.0, 90.0), sx * (Wb / 2 + 0.002), wr, z)));
    }
  for (int sx : {-1, 1}) {
    parts.push_back(k.light(0.32, 0.16, 0.06, sx * W * 0.36, 0.75, L / 2 + 0.005, {1, 0.95, 0.75}, 0.8));
    parts.push_back(k.light(0.28, 0.14, 0.05, sx * W * 0.36, 0.75, -L / 2 - 0.005, {0.9, 0.08, 0.06}, 0.7));
  }
  return {parts, H};
}

static Built truck(const Style &S, const C3 &paint, const Value &spin) {
  VK k = kitOf(S, paint);
  double L = 7.5, W = 2.5, c = 0.5, wr = 0.5, cabL = 2.0, cabH = 2.0, boxL = 5.2, boxH = 2.6, Wb = W * 0.94;
  std::vector<ShapeP> parts{k.dark(at(box(W * 0.8, 0.3, L), 0.0, c + 0.1, 0.0), {0.14, 0.14, 0.15})};
  parts.push_back(k.body(at(k.rbox(Wb, cabH, cabL, 0.14), 0.0, c + 0.25 + cabH / 2, L / 2 - cabL / 2)));
  parts.push_back(k.glass(at(rot(box(W * 0.88, 0.85, 0.04), -8.0, 0.0, 0.0), 0.0, c + 0.25 + cabH * 0.68, L / 2 + 0.005)));
  for (int sx : {-1, 1}) parts.push_back(k.glass(at(box(0.04, 0.8, cabL * 0.55), sx * (Wb / 2 + 0.005), c + 0.25 + cabH * 0.68, L / 2 - cabL * 0.42)));
  parts.push_back(material(color(at(k.rbox(Wb * 0.98, boxH, boxL, 0.05), 0.0, c + 0.25 + boxH / 2, -L / 2 + boxL / 2), C3{0.93, 0.93, 0.9}), {Value(), 0.7, 0.0, Value()}));
  for (int sx : {-1, 1})
    for (double z : {L / 2 - 1.2, -L / 2 + 1.3, -L / 2 + 2.45}) {
      parts.push_back(k.wheel(wr, 0.3, sx * (W / 2 - 0.15), z, spin));
      if (k.real) parts.push_back(k.dark(at(rot(cyl(wr * 1.1, 0.04), 0.0, 0.0, 90.0), sx * (W / 2 + 0.002), wr, z)));
    }
  for (int sx : {-1, 1}) {
    parts.push_back(k.light(0.3, 0.16, 0.06, sx * W * 0.34, c + 0.7, L / 2 + 0.005, {1, 0.95, 0.75}, 0.8));
    parts.push_back(k.light(0.26, 0.14, 0.05, sx * W * 0.38, c + 0.7, -L / 2 - 0.005, {0.9, 0.08, 0.06}, 0.7));
  }
  return {parts, c + 0.25 + boxH};
}

static Built tractor(const Style &S, const C3 &paint, const Value &spin) {
  VK k = kitOf(S, paint);
  double W = 1.9, wrB = 0.78, wrF = 0.46;
  std::vector<ShapeP> parts{k.body(at(k.rbox(0.9, 0.85, 2.0, 0.2), 0.0, 0.95, 0.85))};
  parts.push_back(k.dark(at(k.rbox(0.7, 0.55, 0.3, 0.2), 0.0, 1.0, 1.9), {0.12, 0.12, 0.13}));
  parts.push_back(k.dark(at(box(1.1, 0.35, 2.4), 0.0, 0.55, 0.3), {0.2, 0.2, 0.22}));
  for (int sx : {-1, 1})
    for (int sz : {-1, 1}) parts.push_back(k.body(at(box(0.07, 1.25, 0.07), sx * 0.62, 1.95, -0.55 + sz * 0.5)));
  parts.push_back(k.body(at(k.rbox(1.45, 0.09, 1.25, 0.3), 0.0, 2.6, -0.55)));
  parts.push_back(k.glass(at(box(1.2, 0.8, 0.03), 0.0, 2.0, -1.05)));
  parts.push_back(k.dark(at(box(0.5, 0.12, 0.5), 0.0, 1.35, -0.55), {0.15, 0.12, 0.1}));
  parts.push_back(k.dark(at(cyl(0.05, 0.9), 0.35, 1.9, 1.4), {0.3, 0.3, 0.32}));
  for (int sx : {-1, 1}) {
    parts.push_back(k.wheel(wrB, 0.42, sx * (W / 2 - 0.2), -0.7, spin));
    parts.push_back(k.wheel(wrF, 0.26, sx * (W / 2 - 0.5), 1.3, spin));
  }
  for (int sx : {-1, 1}) parts.push_back(k.light(0.2, 0.16, 0.06, sx * 0.3, 1.1, 1.92, {1, 0.95, 0.75}, 0.8));
  return {parts, 2.65};
}

static Built bike(const Style &S, const C3 &paint, const Value &spin) {
  bool lowpoly = S.facets, real = S.name == "realistic";
  auto frame = [&](const V3 &a, const V3 &b, double r) { return material(color(segment(a, b, r), paint), {Value(), 0.35, 0.6, Value()}); };
  double wr = 0.34, wb = 1.0;
  std::vector<ShapeP> parts;
  auto wheelB = [&](double z) {
    auto tire = color(rot(torus(wr - 0.02, lowpoly ? 0.03 : 0.022), 0.0, 0.0, 90.0), C3{0.05, 0.05, 0.055});
    auto spokes = color(group({segment({0, -(wr - 0.03), 0}, {0, wr - 0.03, 0}, 0.004), segment({0, 0, -(wr - 0.03)}, {0, 0, wr - 0.03}, 0.004)}), C3{0.7, 0.72, 0.75});
    auto g = group(real ? std::vector<ShapeP>{tire, spokes, color(rot(cyl(0.03, 0.05), 0.0, 0.0, 90.0), C3{0.5, 0.5, 0.54})} : std::vector<ShapeP>{tire, spokes});
    if (!isZero(spin)) g = rot(g, spin, 0.0, 0.0);
    return at(g, 0.0, wr, z);
  };
  parts.push_back(wheelB(wb / 2));
  parts.push_back(wheelB(-wb / 2));
  V3 bb{0, 0.3, -0.05}, seat{0, 0.86, -0.3}, head{0, 0.9, 0.34};
  parts.push_back(frame(bb, seat, 0.017));
  parts.push_back(frame(bb, head, 0.019));
  parts.push_back(frame(seat, head, 0.016));
  parts.push_back(frame(bb, {0, wr, -wb / 2}, 0.014));
  parts.push_back(frame(seat, {0, wr, -wb / 2}, 0.012));
  parts.push_back(frame(head, {0, wr, wb / 2}, 0.016));
  parts.push_back(color(segment({-0.22, 1.0, 0.36}, {0.22, 1.0, 0.36}, 0.013), C3{0.12, 0.12, 0.13}));
  parts.push_back(color(at(ellipsoid(0.07, 0.025, 0.13), 0.0, 0.89, -0.32), C3{0.1, 0.1, 0.11}));
  if (!lowpoly) {
    parts.push_back(color(segment({-0.15, 0.3, -0.05}, {0.15, 0.3, -0.05}, 0.01), C3{0.3, 0.3, 0.32}));
    parts.push_back(color(at(rot(cyl(0.08, 0.01), 0.0, 0.0, 90.0), 0.02, 0.3, -0.05), C3{0.6, 0.6, 0.64}));
  }
  return {parts, 1.05};
}

static Built motorbike(const Style &S, const C3 &paint, const Value &spin) {
  bool lowpoly = S.facets, real = S.name == "realistic";
  auto body = [&](const ShapeP &s) { return material(color(s, paint), {Value(), 0.3, lowpoly ? 0.0 : 0.55, Value()}); };
  double wr = 0.32, wb = 1.35;
  std::vector<ShapeP> parts;
  for (double z : {wb / 2, -wb / 2}) {
    auto g = group({color(rot(torus(wr - 0.06, 0.075), 0.0, 0.0, 90.0), C3{0.05, 0.05, 0.055}),
                    material(color(rot(cyl(wr * 0.6, 0.1), 0.0, 0.0, 90.0), C3{0.7, 0.72, 0.76}), {Value(), 0.3, 0.8, Value()}),
                    color(box(0.12, 0.05, wr * 1.2), C3{0.3, 0.3, 0.33})});
    if (!isZero(spin)) g = rot(g, spin, 0.0, 0.0);
    parts.push_back(at(g, 0.0, wr, z));
  }
  parts.push_back(color(at(box(0.28, 0.34, 0.55, lowpoly ? 0 : 0.05), 0.0, 0.5, 0.0), C3{0.22, 0.22, 0.25}));
  parts.push_back(body(at(lowpoly ? box(0.3, 0.26, 0.55) : ellipsoid(0.17, 0.14, 0.3), 0.0, 0.88, 0.22)));
  parts.push_back(color(at(box(0.24, 0.1, 0.6, lowpoly ? 0 : 0.04), 0.0, 0.82, -0.32), C3{0.1, 0.1, 0.11}));
  parts.push_back(color(segment({0, 0.95, wb / 2 - 0.1}, {0, wr, wb / 2}, 0.025), C3{0.7, 0.72, 0.76}));
  parts.push_back(color(segment({-0.3, 1.02, wb / 2 - 0.15}, {0.3, 1.02, wb / 2 - 0.15}, 0.016), C3{0.12, 0.12, 0.13}));
  parts.push_back(material(color(at(sphere(0.09), 0.0, 0.98, wb / 2 + 0.02), C3{1, 0.95, 0.75}), {Value(), 0.2, Value(), 0.8}));
  parts.push_back(color(segment({0.16, 0.38, 0.2}, {0.18, 0.3, -0.75}, 0.04), C3{0.55, 0.57, 0.6}));
  parts.push_back(color(segment({0, 0.5, -0.2}, {0, wr, -wb / 2}, 0.03), C3{0.25, 0.25, 0.28}));
  if (real) parts.push_back(body(at(ellipsoid(0.15, 0.1, 0.24), 0.0, 0.68, -0.52)));
  return {parts, 1.15};
}

Builtins vehicleBuiltins(Interp &it) {
  Interp *ip = &it;
  return {{"vehicle", native("vehicle", {"kind=\"car\"", "style=\"stylized\"", "length=None", "color=None", "wheels_angle=0", "seed=None"}, [ip](const Args &a, const Node *) -> Value {
    std::string kindName = jsLower(str(a["kind"]));
    if (std::find(KINDS.begin(), KINDS.end(), kindName) == KINDS.end()) {
      std::string h = didYouMean(kindName, KINDS);
      throw ScriptError("vehicle(): tipo desconhecido '" + str(a["kind"]) + "'", 0, h.empty() ? "use car, hatch, suv, pickup, van, bus, truck, tractor, bike, motorbike" : h);
    }
    Style S = resolveStyle(a["style"], "vehicle()");
    RT R = rngFor(*ip, a["seed"]);
    C3 paint = toSrgb(a["color"].isNone() ? Value(R.pick(PAINTS)) : a["color"]);
    Value spin = a["wheels_angle"].isExpr() ? a["wheels_angle"] : Value(num(a["wheels_angle"], "wheels_angle"));
    Built built;
    const Car *car = nullptr;
    for (auto &c : CARS) if (kindName == c.name) car = &c;
    if (car) built = carFamily(*car, S, paint, spin);
    else if (kindName == "bus") built = bus(S, paint, spin);
    else if (kindName == "truck") built = truck(S, paint, spin);
    else if (kindName == "tractor") built = tractor(S, paint, spin);
    else if (kindName == "bike") built = bike(S, paint, spin);
    else built = motorbike(S, paint, spin);
    auto out = group(built.parts);
    if (!a["length"].isNone()) {
      double len = num(a["length"], "length");
      if (!(len > 0)) throw ScriptError("vehicle(): length deve ser maior que zero");
      const BBox &b = out->bbox();
      out = scale(out, len / (b.max[2] - b.min[2]));
    }
    return named(ground(out), "veiculo-" + kindName);
  })}};
}

}  // namespace tdi::kit
