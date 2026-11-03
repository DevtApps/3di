// Gerador de pessoas (port de lib/people.js).
#include <map>

#include "kit.h"

namespace tdi::kit {

struct Build {
  const char *name;
  double legL, torso, neck, head, sh, chest, hip, limb, belly, lean;
};
static const Build BUILDS[] = {
    {"average", 0.52, 0.3, 0.04, 0.14, 0.125, 1, 1, 1, 0, 0},     {"slim", 0.53, 0.3, 0.045, 0.125, 0.11, 0.85, 0.85, 0.8, 0, 0},
    {"stocky", 0.5, 0.3, 0.03, 0.17, 0.15, 1.25, 1.2, 1.3, 0.03, 0}, {"child", 0.44, 0.3, 0.03, 0.23, 0.11, 0.95, 0.95, 0.9, 0.015, 0},
    {"elder", 0.51, 0.3, 0.04, 0.15, 0.12, 1, 1, 0.95, 0.015, 9},
};
static const std::vector<std::string> BUILD_NAMES = {"average", "slim", "stocky", "child", "elder"};
static const std::vector<std::string> POSE_NAMES = {"stand", "walk", "sit", "arms_up"};
static const std::vector<std::string> HAIR_NAMES = {"short", "long", "bald", "ponytail", "curly", "bun"};
static const std::vector<std::string> OUTFITS = {"casual", "suit", "sport", "dress", "uniform"};
static const std::vector<std::string> SKINS = {"#f1c9a5", "#e0ac86", "#c68b5c", "#a5683c", "#7a4a2a", "#52331f"};
static const std::vector<std::string> HAIRS = {"#1a1410", "#3b2415", "#6b4423", "#b8864b", "#d9b46a", "#8a3a1e"};
static const std::vector<std::string> SHIRTS = {"#d94f4f", "#3f7fd0", "#e8c43a", "#4fb06a", "#e8e8e2", "#8a5cc8", "#e0803a", "#2f2f35"};
static const std::vector<std::string> PANTS = {"#2f4a7a", "#3b3b44", "#6b5a3a", "#4a5a3a", "#7a7a80"};

struct Pose {
  double armL[3], armR[3], legL[3], legR[3];
  bool sit;
};
static const std::map<std::string, Pose> POSES = {
    {"stand", {{4, 9, 8}, {4, 9, 8}, {0, 3, 0}, {0, 3, 0}, false}},
    {"walk", {{-28, 6, 10}, {30, 6, 30}, {26, 2, 6}, {-24, 2, 30}, false}},
    {"sit", {{28, 6, 70}, {28, 6, 70}, {88, 6, 0}, {88, 6, 0}, true}},
    {"arms_up", {{172, 14, 8}, {172, 14, 8}, {0, 4, 0}, {0, 4, 0}, false}},
};

static std::string pickOf(const std::string &what, const Value &value, const std::vector<std::string> &list) {
  std::string v = jsLower(str(value));
  if (std::find(list.begin(), list.end(), v) == list.end()) {
    std::string all;
    for (auto &x : list) all += (all.empty() ? "" : ", ") + x;
    std::string h = didYouMean(v, list);
    throw ScriptError("person(): " + what + " desconhecido '" + str(value) + "'", 0, h.empty() ? "use " + all : h);
  }
  return v;
}

using Paint = std::function<ShapeP(const ShapeP &)>;

Builtins peopleBuiltins(Interp &it) {
  Interp *ip = &it;
  return {{"person", native("person", {"style=\"stylized\"", "height=None", "build=\"average\"", "skin=None", "hair=None", "outfit=\"casual\"", "pose=\"stand\"", "seed=None"},
                            [ip](const Args &a, const Node *) -> Value {
    Style S = resolveStyle(a["style"], "person()");
    std::string buildName = pickOf("build", a["build"], BUILD_NAMES);
    double H = a["height"].isNone() ? (buildName == "child" ? 1.1 : buildName == "elder" ? 1.65 : 1.75) : num(a["height"], "height");
    if (!(H > 0)) throw ScriptError("person(): height deve ser maior que zero");
    std::string outfit = pickOf("outfit", a["outfit"], OUTFITS);
    std::string poseName = pickOf("pose", a["pose"], POSE_NAMES);
    std::string hairName = a["hair"].isNone() ? "" : pickOf("hair", a["hair"], HAIR_NAMES);
    RT R = rngFor(*ip, a["seed"]);
    const Build *Bd = nullptr;
    for (auto &b : BUILDS) if (buildName == b.name) Bd = &b;
    const Pose &pose = POSES.at(poseName);

    C3 skin = toSrgb(a["skin"].isNone() ? Value(R.pick(SKINS)) : a["skin"]);
    C3 hairCol = toSrgb(Value(buildName == "elder" && a["hair"].isNone() ? std::string("#cfcfcf") : R.pick(HAIRS)));
    std::string hairStyle = !hairName.empty() ? hairName
                            : buildName == "child" ? R.pick(std::vector<std::string>{"short", "ponytail", "curly"})
                                                   : R.pick(std::vector<std::string>{"short", "long", "bald", "ponytail", "curly", "bun"});
    C3 shirt = toSrgb(Value(outfit == "suit" ? R.pick(std::vector<std::string>{"#2a2f45", "#3a3a40", "#4a4036"}) : outfit == "uniform" ? std::string("#8fb4d8") : R.pick(SHIRTS)));
    C3 pants = outfit == "suit" ? toSrgb(col(shirt))
               : toSrgb(Value(outfit == "uniform" ? std::string("#2a3350")
                              : outfit == "sport" ? R.pick(std::vector<std::string>{"#2a2f45", "#d94f4f", "#2f2f35"})
                                                  : R.pick(PANTS)));
    C3 shoes = toSrgb(Value(outfit == "suit" ? std::string("#1a1612") : R.pick(std::vector<std::string>{"#f0f0ec", "#2f2f35", "#8a4a2a", "#d94f4f"})));
    bool sleeveLong = outfit == "suit" || (outfit == "casual" && R.u() < 0.4);
    bool sleeveless = outfit == "dress";
    bool shortsOnly = outfit == "sport";

    double Hh = H;
    double legL = Bd->legL * Hh, torso = Bd->torso * Hh, neckL = Bd->neck * Hh, headH = Bd->head * Hh;
    double shHalf = Bd->sh * Hh * (outfit == "suit" ? 1.05 : 1);
    double ankle = 0.04 * Hh;
    double Lt = (legL - ankle) / 2, Ls = Lt;
    double Lu = 0.165 * Hh * (buildName == "child" ? 0.85 : 1), Lf = 0.15 * Hh * (buildName == "child" ? 0.85 : 1);
    double rU = 0.03 * Hh * Bd->limb, rF = 0.023 * Hh * Bd->limb, rW = 0.016 * Hh * Bd->limb;
    double rT = 0.052 * Hh * Bd->limb, rK = 0.036 * Hh * Bd->limb, rA = 0.024 * Hh * Bd->limb;
    double hipX = 0.055 * Hh * Bd->hip;
    double pelvisY = pose.sit ? ankle + Ls : legL;
    double shoulderY = pelvisY + torso;
    double headCy = shoulderY + neckL + headH / 2;
    double ry = headH / 2, rx = ry * 0.82, rz = ry * 0.9;

    bool lowpoly = S.facets, real = S.name == "realistic";
    auto cloth = [&](const ShapeP &shape, const C3 &c) {
      auto s = color(shape, c);
      return real ? texture(s, "mottle", {col(mixc(c, {0, 0, 0}, 0.18)), Hh * 0.09, "y", S.bump * 0.12}) : s;
    };
    Paint sk = [&](const ShapeP &shape) {
      return real ? texture(color(shape, skin), "mottle", {col(mixc(skin, {0.8, 0.3, 0.3}, 0.2)), Hh * 0.05, "y", 0.05}) : color(shape, skin);
    };
    auto limbSeg = [&](const V3 &from, const V3 &to, double r0, double r1, const Paint &paint) {
      return paint(lowpoly ? boxSeg(from, to, (r0 + r1) * 1.15, (r0 + r1) * 1.0) : taper(from, to, r0, r1));
    };
    auto blob = [&](const V3 &rr, const V3 &p, const Paint &paint) {
      return paint(at(lowpoly ? box(rr[0] * 1.6, rr[1] * 1.6, rr[2] * 1.6) : ellipsoid(rr[0], rr[1], rr[2]), p[0], p[1], p[2]));
    };
    auto atv = [](const ShapeP &s, const V3 &p) { return at(s, p[0], p[1], p[2]); };

    std::vector<ShapeP> head, torsoP, armL, armR, legLp, legRp;

    for (int side : {1, -1}) {
      auto &dst = side == 1 ? legLp : legRp;
      const double *lg = side == 1 ? pose.legL : pose.legR;
      double al = lg[0], be = lg[1], bend = lg[2];
      V3 hip{side * hipX, pelvisY, 0};
      V3 knee = addv(hip, scalev(limbDir(al, be, side), Lt));
      V3 ank = addv(knee, scalev(limbDir(al - bend, be * 0.4, side), Ls));
      Paint thighPaint = shortsOnly ? Paint([&](const ShapeP &s) { return cloth(s, pants); })
                                    : Paint([&](const ShapeP &s) { return outfit == "dress" ? sk(s) : cloth(s, pants); });
      Paint shinPaint = shortsOnly || outfit == "dress" ? sk : Paint([&](const ShapeP &s) { return cloth(s, pants); });
      dst.push_back(limbSeg(hip, knee, rT, rK, thighPaint));
      dst.push_back(limbSeg(knee, ank, rK, rA, shinPaint));
      if (real && !lowpoly) dst.push_back(color(atv(sphere(rK * 1.02), knee), outfit == "dress" || shortsOnly ? skin : pants));
      double fl = 0.07 * Hh * Bd->limb;
      V3 footC = addv(ank, {0, -0.018 * Hh, fl * 0.55});
      if (lowpoly) dst.push_back(color(atv(box(rA * 2.2, 0.04 * Hh, fl * 2), footC), shoes));
      else if (real) {
        dst.push_back(color(atv(box(rA * 2.3, 0.032 * Hh, fl * 2.1, 0.012 * Hh), footC), shoes));
        dst.push_back(color(at(box(rA * 2.4, 0.008 * Hh, fl * 2.15), footC[0], footC[1] - 0.02 * Hh, footC[2]), C3{0.12, 0.1, 0.09}));
      } else dst.push_back(color(atv(ellipsoid(rA * 1.3, 0.024 * Hh, fl), footC), shoes));
    }

    double bw = Bd->chest;
    bool dressC = outfit == "dress";
    Paint torsoPaint = [&](const ShapeP &s) { return cloth(s, shirt); };
    V3 chestC{0, pelvisY + torso * 0.66, 0}, waistC{0, pelvisY + torso * 0.3, 0}, pelvC{0, pelvisY + 0.01 * Hh, 0};
    auto block = [&](double w, double h, double d, const V3 &c, const Paint &paint, double round) {
      return paint(atv(box(w, h, d, lowpoly ? 0 : round), c));
    };
    torsoP.push_back(block(shHalf * 2 * bw * 0.96, torso * 0.62, 0.15 * Hh * bw, chestC, torsoPaint, 0.045 * Hh));
    torsoP.push_back(block(0.19 * Hh * bw * (1 + Bd->belly * 2), torso * 0.52, 0.125 * Hh * (1 + Bd->belly * 6), waistC, torsoPaint, 0.04 * Hh));
    torsoP.push_back(blob({0.105 * Hh * Bd->hip, 0.06 * Hh, 0.072 * Hh}, pelvC, [&](const ShapeP &s) { return dressC ? cloth(s, shirt) : cloth(s, pants); }));
    if (outfit == "dress") {
      double hem = pelvisY - Lt * 0.9;
      auto sk2 = lowpoly ? pyramid(0.34 * Hh, pelvisY - hem + 0.05 * Hh) : cone(0.19 * Hh, pelvisY - hem + 0.05 * Hh, 0.085 * Hh);
      torsoP.push_back(color(at(sk2, 0.0, (pelvisY + hem) / 2 + 0.025 * Hh, 0.0), shirt));
    }
    if (outfit == "suit" && !lowpoly)
      torsoP.push_back(color(at(ellipsoid(0.012 * Hh, 0.09 * Hh, 0.01 * Hh), 0.0, chestC[1] - 0.03 * Hh, 0.078 * Hh * bw), C3{0.75, 0.15, 0.2}));
    if (outfit == "uniform" && !lowpoly)
      torsoP.push_back(color(at(box(0.2 * Hh * Bd->hip, 0.018 * Hh, 0.15 * Hh), 0.0, pelvisY + 0.045 * Hh, 0.0), C3{0.15, 0.13, 0.12}));

    head.push_back(limbSeg({0, shoulderY - 0.02 * Hh, 0}, {0, shoulderY + neckL + 0.01 * Hh, 0}, 0.03 * Hh * Bd->limb, 0.027 * Hh * Bd->limb, sk));
    auto headShape = lowpoly ? box(rx * 2, ry * 2, rz * 2.1) : ellipsoid(rx, ry, rz);
    head.push_back(sk(at(headShape, 0.0, headCy, 0.0)));
    auto front = [&](double x, double y) {
      return lowpoly ? rz * 1.05 + ry * 0.03 : rz * std::sqrt(std::max(0.05, 1 - (x / rx) * (x / rx) - (y / ry) * (y / ry))) * 0.97;
    };
    for (int sx : {-1, 1}) {
      double ex = sx * rx * 0.42, ey = ry * 0.08;
      if (real) {
        head.push_back(color(at(sphere(ry * 0.09), ex, headCy + ey, front(ex, ey)), C3{0.96, 0.96, 0.96}));
        head.push_back(color(at(sphere(ry * 0.055), ex, headCy + ey, front(ex, ey) + ry * 0.05), C3{0.18, 0.12, 0.08}));
        head.push_back(sk(at(ellipsoid(rx * 0.12, ry * 0.2, ry * 0.12), sx * rx * 0.98, headCy, 0.0)));
      } else head.push_back(color(at(sphere(ry * 0.075), ex, headCy + ey, front(ex, ey)), C3{0.1, 0.09, 0.09}));
    }
    if (real) {
      head.push_back(sk(at(ellipsoid(ry * 0.09, ry * 0.15, ry * 0.12), 0.0, headCy - ry * 0.12, front(0, -ry * 0.12) + ry * 0.03)));
      head.push_back(color(at(ellipsoid(ry * 0.28, ry * 0.04, ry * 0.05), 0.0, headCy - ry * 0.45, front(0, -ry * 0.45)), mixc(skin, {0.7, 0.2, 0.25}, 0.5)));
    }

    C3 hc = jitter(hairCol, R, 4, S.vary * 0.6, S.vary * 0.5);
    Paint hairPaint = [&](const ShapeP &s) {
      return real ? texture(color(s, hc), "mottle", {col(mixc(hc, {0, 0, 0}, 0.35)), ry * 0.25, "y", S.bump * 0.5}) : color(s, hc);
    };
    Paint same = [](const ShapeP &s) { return s; };
    if (hairStyle != "bald") {
      auto capShape = lowpoly ? box(rx * 2.15, ry * 1.1, rz * 2.2) : ellipsoid(rx * 1.08, ry * 0.82, rz * 1.1);
      head.push_back(hairPaint(at(capShape, 0.0, headCy + ry * (lowpoly ? 0.72 : 0.3), -rz * 0.08)));
      if (hairStyle == "long") head.push_back(hairPaint(limbSeg({0, headCy + ry * 0.3, -rz * 0.75}, {0, shoulderY - 0.02 * Hh, -rz * 0.7}, rx * 0.95, rx * 0.8, same)));
      if (hairStyle == "ponytail") head.push_back(hairPaint(limbSeg({0, headCy + ry * 0.35, -rz * 0.95}, {0, headCy - ry * 0.7, -rz * 1.6}, rx * 0.3, rx * 0.16, same)));
      if (hairStyle == "bun") head.push_back(hairPaint(at(sphere(rx * 0.45), 0.0, headCy + ry * 1.05, -rz * 0.2)));
      if (hairStyle == "curly") {
        int n = S.name == "lowpoly" ? 4 : S.name == "stylized" ? 6 : 8;
        for (int i = 0; i < n; i++) {
          double a2 = rad((i * 360.0) / n + R.u(-15, 15));
          double y = headCy + ry * (0.35 + 0.35 * R.u());
          head.push_back(hairPaint(at(sphere(rx * 0.42), std::cos(a2) * rx * 0.85, y, std::sin(a2) * rz * 0.8 - rz * 0.1)));
        }
      }
    }

    for (int side : {1, -1}) {
      auto &dst = side == 1 ? armL : armR;
      const double *ar = side == 1 ? pose.armL : pose.armR;
      double al = ar[0], be = ar[1], bend = ar[2];
      V3 sh{side * shHalf, shoulderY - 0.025 * Hh, 0};
      V3 elbow = addv(sh, scalev(limbDir(al, be, side), Lu));
      V3 wrist = addv(elbow, scalev(limbDir(al + bend, be * 0.5, side), Lf));
      Paint upperPaint = sleeveless ? sk : Paint([&](const ShapeP &s) { return cloth(s, shirt); });
      Paint lowerPaint = sleeveLong ? Paint([&](const ShapeP &s) { return cloth(s, shirt); }) : sk;
      dst.push_back(limbSeg(sh, elbow, rU, rF, upperPaint));
      dst.push_back(limbSeg(elbow, wrist, rF, rW, lowerPaint));
      if (!lowpoly) dst.push_back(color(atv(sphere(rU * 1.12), sh), sleeveless ? skin : shirt));
      V3 hd = scalev(limbDir(al + bend, be * 0.5, side), rW * 1.8);
      V3 handC = addv(wrist, hd);
      dst.push_back(lowpoly ? sk(atv(box(rW * 2.4, rW * 2.8, rW * 1.8), handC)) : sk(atv(ellipsoid(rW * 1.2, rW * (real ? 1.9 : 1.4), rW * 0.8), handC)));
      if (real) dst.push_back(sk(at(ellipsoid(rW * 0.4, rW * 1.1, rW * 0.5), handC[0] + side * rW * 0.9, handC[1] + rW * 0.4, handC[2] + rW * 0.7)));
    }

    std::vector<ShapeP> up;
    for (auto *v : {&head, &torsoP, &armL, &armR}) up.insert(up.end(), v->begin(), v->end());
    auto upper = group(up);
    auto upperLean = Bd->lean ? rot(upper, Bd->lean, 0.0, 0.0, V3{0, pelvisY, 0}) : upper;
    auto body = group({named(group(legLp), "perna-esq"), named(group(legRp), "perna-dir"), named(upperLean, "tronco-e-cabeca")});
    return named(ground(body), "pessoa-" + buildName);
  })}};
}

}  // namespace tdi::kit
