// Heróis low poly (estilo chibi) e equipamento (port de lib/heroes.js).
#include <cmath>

#include "kit.h"

namespace tdi::kit {

static const char *STEEL = "#c9ced6", *STEEL_D = "#8d949e", *LEATHER = "#7a4a2a", *GOLD = "#e2b33c", *DARK = "#2a2320", *WOOD = "#8a5a34";
static const char *SKINS[] = {"#f0c39a", "#d9a172", "#a86f47", "#6e4529"};
static const char *HAIRS[] = {"#6b4423", "#2b1d14", "#d9b46a", "#a8432a"};

struct HeroKind { const char *name, *main, *dark; double wide; };
static const HeroKind KINDS[] = {
    {"knight", "#3f6fb5", "#2b4c80", 1}, {"barbarian", "#8a3a2a", "#5a2a1e", 1.18}, {"rogue", "#3d5a3a", "#263826", 0.95},
    {"mage", "#6a4bb0", "#45307a", 1}, {"ranger", "#4f7a3a", "#6b4a2a", 1},
};
static const std::vector<std::string> HERO_KINDS = {"knight", "barbarian", "rogue", "mage", "ranger"};
static const std::vector<std::string> GEAR_KINDS = {"sword", "dagger", "axe", "hammer", "staff", "wand", "bow", "shield", "round_shield", "book", "mug", "quiver"};

struct HeroO { Value color, skin, hair; bool helmet; int variant; };

static ShapeP c(const ShapeP &s, const Value &col) { return color(s, col); }
static std::vector<V3> chRing(double y, double hw, double hd) { return {{-hw, y, -hd}, {hw, y, -hd}, {-hw, y, hd}, {hw, y, hd}}; }
static std::vector<V3> cat(std::initializer_list<std::vector<V3>> l) {
  std::vector<V3> out;
  for (auto &v : l) out.insert(out.end(), v.begin(), v.end());
  return out;
}

static ShapeP hero(const HeroKind &P, const HeroO &o) {
  std::string kind = P.name;
  double W = P.wide;
  Value main = o.color.isNone() ? Value(P.main) : o.color, dark = Value(P.dark);
  Value skin = o.skin.isNone() ? Value(SKINS[o.variant % 4]) : o.skin, hair = o.hair.isNone() ? Value(HAIRS[o.variant % 4]) : o.hair;
  std::vector<ShapeP> parts;
  Value armor = kind == "knight" ? Value(STEEL) : kind == "barbarian" ? skin : main;
  for (double x : {0.09, -0.09}) {
    parts.push_back(c(place(cbox(0.15 * W, 0.24, 0.17, 0.03), x * W, 0.12, 0), kind == "barbarian" ? Value(LEATHER) : dark));
    parts.push_back(c(place(cbox(0.18 * W, 0.13, 0.24, 0.035), x * W, 0, 0.02), kind == "mage" ? dark : Value(LEATHER)));
  }
  parts.push_back(c(place(hullShape(cat({chRing(0, 0.2 * W, 0.13), chRing(0.3, 0.25 * W, 0.15), chRing(0.36, 0.18 * W, 0.11)})), 0, 0.4, 0), armor));
  parts.push_back(c(place(cbox(0.42 * W, 0.06, 0.28, 0.015), 0, 0.36, 0), LEATHER));
  parts.push_back(c(place(cbox(0.07, 0.06, 0.02, 0.01), 0, 0.36, 0.145), GOLD));
  if (kind == "knight") {
    parts.push_back(c(place(cbox(0.3, 0.28, 0.02, 0.01), 0, 0.44, 0.15), main));
    parts.push_back(c(at(hullShape({{0, 0.08, 0}, {0.06, 0, 0}, {0, -0.08, 0}, {-0.06, 0, 0}, {0, 0, 0.02}}), 0.0, 0.6, 0.165), GOLD));
    parts.push_back(c(place(lpCone(0.23, 0.12, 0.21, 8), 0, 0.26, 0), STEEL_D));
  } else if (kind == "mage") {
    parts.push_back(c(place(lpCone(0.3, 0.36, 0.2, 8), 0, 0.02, 0), main));
    parts.push_back(c(place(cbox(0.08, 0.3, 0.02, 0.01), 0, 0.42, 0.15), GOLD));
  } else if (kind == "barbarian") {
    parts.push_back(c(place(lpCone(0.25 * W, 0.12, 0.22 * W, 8), 0, 0.26, 0), "#6b4a2a"));
    parts.push_back(c(at(hullShape({{-0.12, 0, 0}, {0.12, 0, 0}, {0, 0.1, 0}, {0, 0.05, 0.03}}), 0.0, 0.55, 0.14), LEATHER));
  } else {
    parts.push_back(c(place(lpCone(0.23, 0.12, 0.21, 8), 0, 0.26, 0), dark));
  }
  for (int side : {1, -1}) {
    double x = side * 0.3 * W;
    bool bare = kind == "barbarian";
    Value shoulder = kind == "knight" ? Value(STEEL) : kind == "barbarian" ? Value("#c9b48f") : kind == "mage" ? main : dark;
    parts.push_back(c(at(scale(ball(0.11 * W, 6), V3{1, 0.75, 1}), x, 0.72, 0.0), shoulder));
    parts.push_back(c(place(cbox(0.11 * W, 0.26, 0.12, 0.025), x, 0.42, 0), bare ? skin : kind == "knight" ? dark : main));
    parts.push_back(c(place(cbox(0.13 * W, 0.11, 0.13, 0.03), x, 0.33, 0), bare ? Value(LEATHER) : kind == "mage" ? skin : Value(LEATHER)));
  }
  parts.push_back(c(place(cbox(0.38, 0.34, 0.34, 0.07), 0, 0.78, 0), skin));
  parts.push_back(c(mirror(at(box(0.04, 0.05, 0.02), 0.07, 0.86, 0.172), "x"), DARK));
  auto hullAt = [&](const std::vector<V3> &pts, double x, double y, double z, const Value &col) { return c(place(hullShape(pts), x, y, z), col); };
  auto dome = [&](double hw, double hd, double h) { return cat({chRing(0, hw, hd), chRing(h * 0.68, hw * 0.92, hd * 0.92), chRing(h, hw * 0.48, hd * 0.52)}); };
  if (kind == "knight" && o.helmet) {
    parts.push_back(hullAt(dome(0.22, 0.2, 0.32), 0, 0.9, 0, STEEL));
    parts.push_back(c(at(box(0.3, 0.05, 0.03), 0.0, 0.98, 0.205), "#20242b"));
    parts.push_back(c(at(hullShape({{0, 0, -0.14}, {0, 0, 0.12}, {0, 0.12, -0.06}, {0.02, 0.04, 0}, {-0.02, 0.04, 0}}), 0.0, 1.21, 0.0), main));
  } else if (kind == "barbarian" && o.helmet) {
    parts.push_back(hullAt(dome(0.21, 0.19, 0.18), 0, 0.95, 0, STEEL_D));
    for (int s : {1, -1}) parts.push_back(c(at(rot(lpCone(0.05, 0.22, 0, 6), 0.0, 0.0, -s * 55.0, O), s * 0.27, 1.08, 0.0), "#efe6d2"));
    parts.push_back(c(at(hullShape({{-0.14, 0, 0}, {0.14, 0, 0}, {0, -0.16, 0.02}, {0, -0.04, 0.05}}), 0.0, 0.74, 0.17), hair));
  } else if (kind == "rogue") {
    parts.push_back(hullAt(cat({chRing(0, 0.22, 0.2), chRing(0.2, 0.2, 0.19), chRing(0.3, 0.1, 0.12), {{0, 0.18, -0.26}}}), 0, 0.9, -0.025, main));
    parts.push_back(c(at(box(0.32, 0.07, 0.03), 0.0, 0.97, 0.18), main));
    parts.push_back(c(at(cbox(0.36, 0.1, 0.05, 0.02), 0.0, 0.71, 0.155), dark));
  } else if (kind == "mage") {
    parts.push_back(c(place(lpPrism(0.3, 0.03, 10), 0, 0.92, 0), main));
    parts.push_back(c(at(rot(lpCone(0.17, 0.42, 0, 8), -12.0, 0.0, 0.0, V3{0, -0.21, 0}), 0.0, 1.16, -0.02), main));
    parts.push_back(c(place(lpPrism(0.18, 0.04, 8), 0, 0.93, 0), GOLD));
    parts.push_back(c(at(hullShape({{-0.13, 0, 0}, {0.13, 0, 0}, {0, -0.2, 0.04}, {0, -0.02, 0.05}}), 0.0, 0.73, 0.17), o.hair.isNone() ? Value("#e8e4da") : o.hair));
  } else if (kind == "ranger") {
    parts.push_back(hullAt(cat({chRing(0, 0.21, 0.19), chRing(0.1, 0.19, 0.17), {{0, 0.2, -0.12}, {0, 0.16, 0.1}}}), 0, 0.92, 0, main));
    parts.push_back(c(at(rot(hullShape({{0, 0, 0}, {0.02, 0.18, 0}, {-0.02, 0.18, 0}, {0, 0.1, 0.03}}), 0.0, 0.0, -25.0, O), 0.14, 1.0, -0.05), "#c8382b"));
    parts.push_back(c(place(cbox(0.42, 0.5, 0.03, 0.01), 0, 0.28, -0.17), dark));
  }
  if (kind != "rogue" && !(kind == "knight" && o.helmet) && kind != "ranger" && kind != "mage" && !(kind == "barbarian" && o.helmet))
    parts.push_back(hullAt(dome(0.2, 0.18, 0.12), 0, 0.92, -0.01, hair));
  ShapeP body = named(group(parts), "heroi-" + kind);
  double hx = 0.3 * W;
  body = anchorAt(body, "mao_dir", {hx, 0.33, 0.04}, {0, 1, 0});
  body = anchorAt(body, "mao_esq", {-hx, 0.33, 0.04}, {0, 1, 0});
  body = anchorAt(body, "braco_esq", {-hx - 0.06 * W, 0.42, 0}, {-1, 0, 0});
  body = anchorAt(body, "costas", {0, 0.55, -0.16}, {0, 0, -1});
  body = anchorAt(body, "cabeca", {0, kind == "mage" ? 1.37 : 1.1, 0}, {0, 1, 0});
  body = anchorAt(body, "cintura", {0.2 * W, 0.36, 0.06}, {1, 0, 0});
  return body;
}

static ShapeP blade(double w, double t, double len, double tip) {
  return hullShape({{w, 0, 0}, {-w, 0, 0}, {0, 0, t}, {0, 0, -t}, {w * 0.85, len, 0}, {-w * 0.85, len, 0}, {0, len, t * 0.8}, {0, len, -t * 0.8}, {0, len + tip, 0}});
}

static ShapeP gear(const std::string &kind, const Value &col) {
  Value metal = col.isNone() ? Value(STEEL) : col;
  std::vector<ShapeP> parts;
  V3 grip{0, 0, 0};
  if (kind == "sword") {
    parts = {c(at(blade(0.035, 0.012, 0.5, 0.08), 0.0, 0.075, 0.0), metal), c(at(cbox(0.18, 0.035, 0.05, 0.012), 0.0, 0.06, 0.0), GOLD),
             c(lpPrism(0.018, 0.12, 6), LEATHER), c(at(ball(0.028, 6), 0.0, -0.07, 0.0), GOLD)};
  } else if (kind == "dagger") {
    parts = {c(at(blade(0.025, 0.009, 0.2, 0.05), 0.0, 0.055, 0.0), metal), c(at(cbox(0.1, 0.025, 0.035, 0.008), 0.0, 0.045, 0.0), GOLD), c(lpPrism(0.014, 0.08, 6), LEATHER)};
  } else if (kind == "axe") {
    parts = {c(at(lpPrism(0.02, 0.6, 6), 0.0, 0.22, 0.0), WOOD),
             c(at(hullShape({{0, -0.07, 0.012}, {0, 0.07, 0.012}, {0, -0.07, -0.012}, {0, 0.07, -0.012}, {0.16, -0.12, 0.004}, {0.16, 0.12, 0.004}, {0.16, -0.12, -0.004}, {0.16, 0.12, -0.004}, {0.19, 0, 0}}), 0.01, 0.43, 0.0), metal)};
  } else if (kind == "hammer") {
    parts = {c(at(lpPrism(0.02, 0.5, 6), 0.0, 0.17, 0.0), WOOD), c(at(cbox(0.2, 0.11, 0.11, 0.025), 0.0, 0.44, 0.0), metal), c(at(cbox(0.06, 0.13, 0.13, 0.02), 0.0, 0.44, 0.0), GOLD)};
  } else if (kind == "staff") {
    parts = {c(at(lpPrism(0.022, 1.1, 6), 0.0, 0.25, 0.0), WOOD), c(at(rot(lpCone(0.05, 0.12, 0.02, 6), 180.0, 0.0, 0.0, O), 0.0, 0.82, 0.0), WOOD),
             material(color(at(ball(0.06, 6), 0.0, 0.89, 0.0), col.isNone() ? Value("#5ad1e6") : col), {Value(), Value(), Value(), 0.8})};
  } else if (kind == "wand") {
    parts = {c(at(lpCone(0.016, 0.32, 0.009, 6), 0.0, 0.08, 0.0), WOOD), material(color(at(ball(0.025, 6), 0.0, 0.25, 0.0), col.isNone() ? Value("#f2c53d") : col), {Value(), Value(), Value(), 0.8})};
  } else if (kind == "bow") {
    std::vector<V3> arcPts;
    for (int i = 0; i <= 6; i++) {
      double a = ((i / 6.0) - 0.5) * 2.2;
      arcPts.push_back({0, std::sin(a) * 0.4, std::cos(a) * 0.18 - 0.12});
    }
    for (int i = 0; i < 6; i++) parts.push_back(c(segment(arcPts[i], arcPts[i + 1], 0.016), WOOD));
    parts.push_back(c(segment(arcPts[0], arcPts[6], 0.004), "#efe6d2"));
    parts.push_back(c(at(cbox(0.04, 0.09, 0.04, 0.01), 0.0, 0.0, 0.06), LEATHER));
    grip = {0, 0, 0.06};
  } else if (kind == "shield") {
    parts = {c(hullShape({{-0.2, 0.22, 0}, {0.2, 0.22, 0}, {-0.2, 0.22, 0.04}, {0.2, 0.22, 0.04}, {-0.18, -0.08, 0}, {0.18, -0.08, 0}, {-0.18, -0.08, 0.04}, {0.18, -0.08, 0.04}, {0, -0.3, 0}, {0, -0.3, 0.04}}),
               col.isNone() ? Value("#3f6fb5") : col),
             c(at(hullShape({{0, 0.1, 0}, {0.07, 0, 0}, {0, -0.1, 0}, {-0.07, 0, 0}, {0, 0, 0.03}}), 0.0, 0.0, 0.04), GOLD)};
  } else if (kind == "round_shield") {
    parts = {c(rot(lpPrism(0.2, 0.04, 8), 90.0, 0.0, 0.0, O), col.isNone() ? Value(WOOD) : col), c(at(rot(lpPrism(0.215, 0.03, 8), 90.0, 0.0, 0.0, O), 0.0, 0.0, -0.008), STEEL_D),
             c(at(ball(0.06, 6), 0.0, 0.0, 0.02), GOLD)};
  } else if (kind == "book") {
    parts = {c(cbox(0.16, 0.22, 0.05, 0.01), col.isNone() ? Value("#8a3a2a") : col), c(at(box(0.15, 0.2, 0.04), 0.008, 0.0, 0.0), "#efe6d2"), c(at(cbox(0.05, 0.05, 0.01, 0.005), 0.0, 0.03, 0.026), GOLD)};
  } else if (kind == "mug") {
    parts = {c(lpPrism(0.05, 0.11, 8), WOOD), c(at(lpPrism(0.052, 0.015, 8), 0.0, 0.03, 0.0), STEEL_D), c(at(lpPrism(0.044, 0.01, 8), 0.0, 0.055, 0.0), "#f2e2b0"),
             c(at(cbox(0.03, 0.07, 0.02, 0.008), 0.065, 0.0, 0.0), WOOD)};
  } else {  // quiver
    parts = {c(lpCone(0.06, 0.34, 0.07, 6), LEATHER), c(at(lpPrism(0.072, 0.03, 6), 0.0, 0.15, 0.0), STEEL_D)};
    for (auto xz : {std::array<double, 2>{0.02, 0.01}, {-0.02, 0.02}, {0, -0.02}}) {
      double x = xz[0], z = xz[1];
      parts.push_back(c(segment({x, 0.15, z}, {x, 0.3, z}, 0.005), WOOD));
      parts.push_back(c(at(hullShape({{x, 0.3, z - 0.02}, {x, 0.3, z + 0.02}, {x, 0.36, z}, {x + 0.003, 0.32, z}, {x - 0.003, 0.32, z}}), 0.0, 0.0, 0.0), "#c8382b"));
    }
    grip = {0, 0, -0.065};
  }
  return anchorAt(named(group(parts), "equip-" + kind), "punho", grip, {0, -1, 0});
}

static std::string pickKind(const std::string &what, const Value &v, const std::vector<std::string> &list) {
  std::string k = jsLower(str(v));
  if (std::find(list.begin(), list.end(), k) == list.end()) {
    std::string all;
    for (auto &x : list) all += (all.empty() ? "" : ", ") + x;
    std::string h = didYouMean(k, list);
    throw ScriptError(what + ": tipo desconhecido '" + str(v) + "'", 0, h.empty() ? "use " + all : h);
  }
  return k;
}

Builtins heroBuiltins(Interp &) {
  return {
      {"hero", native("hero", {"kind=\"knight\"", "color=None", "skin=None", "hair=None", "helmet=True", "variant=0"}, [](const Args &a, const Node *) -> Value {
         std::string kind = pickKind("hero()", a["kind"], HERO_KINDS);
         double variant = num(a["variant"], "variant");
         if (!isInt(variant) || variant < 0) throw ScriptError("hero(): variant deve ser um inteiro >= 0");
         for (auto &k : KINDS)
           if (kind == k.name) return hero(k, {a["color"], a["skin"], a["hair"], truthy(a["helmet"]), (int)variant});
         return Value();
       })},
      {"gear", native("gear", {"kind=\"sword\"", "color=None"}, [](const Args &a, const Node *) -> Value { return gear(pickKind("gear()", a["kind"], GEAR_KINDS), a["color"]); })},
  };
}

}  // namespace tdi::kit
