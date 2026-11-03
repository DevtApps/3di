// Port de compiler.js. O GLSL gerado precisa sair byte a byte igual ao do JS (tests/golden/*.glsl).
#include "compiler.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <functional>
#include <map>
#include <set>
#include <unordered_map>

#include "anchor.h"
#include "error.h"
#include "expr.h"
#include "pattern.h"
#include "profile.h"
#include "rig.h"

namespace tdi {

#include "glsl_lib.inc"

const int INSTANCE_THRESHOLD = 40;
static const int CODE_W = 5;
const std::string GLSL_LIB = GLSL_LIB_SRC;

std::string glslF(const Value &x) {
  if (x.isExpr()) return glslOf(x);
  return glslNum(x.isNum() ? x.n() : x.isBool() ? double(x.b()) : NAN);
}
static std::string f(double x) { return glslNum(x); }
static std::string v3(const std::vector<Value> &v) {
  std::string s = "vec3(";
  for (size_t i = 0; i < v.size(); i++) s += (i ? ", " : "") + glslF(v[i]);
  return s + ")";
}
static std::string v3(const V3 &v) { return "vec3(" + f(v[0]) + ", " + f(v[1]) + ", " + f(v[2]) + ")"; }
static std::string v3(const Value &v) { return v3(v.list()->items); }
static std::string v4(const std::array<double, 4> &v) { return "vec4(" + f(v[0]) + ", " + f(v[1]) + ", " + f(v[2]) + ", " + f(v[3]) + ")"; }

static const char *M_FAR = "M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0)";
static const char *MAT_KEYS[] = {"color", "rough", "metal", "glow", "tex", "facet", "coat"};

static double jsRound(double x) { return std::floor(x + 0.5); }

double facetCode(const Value &fc, const Value &coat) {
  double a = 0;
  if (!fc.isNone()) {
    auto r = fc.as<Rec>();
    a = r->f.num("size") + 16 * jsRound(r->f.num("vary") * 100);
  }
  double c = coat.isNone() ? 0 : val0(coat);
  return a + 1024 * jsRound(std::min(1.0, std::max(0.0, c)) * 10);
}

static double texSize(int k) {
  switch (k) {
    case 1: return 0.25; case 2: return 0.06; case 3: return 0.3; case 4: return 0.1; case 5: return 0.25;
    case 6: return 0.25; case 7: return 1; case 8: return 0.3; case 9: return 0.1;
  }
  return NAN;
}

struct TexP {
  V3 c2;
  std::array<double, 4> tx;
};
static TexP texParams(const Value &texV, const V3 &color) {
  if (texV.isNone()) return {{0, 0, 0}, {0, 1, 1, 0}};
  auto tex = texV.as<Rec>();
  int k = (int)tex->f.num("kind");
  V3 c2;
  if (!tex->f["c2"].isNone()) c2 = tex->f.v3("c2");
  else if (k == 9) c2 = color;
  else if (k == 6) c2 = {0.69, 0.65, 0.58};
  else if (k == 8) c2 = {color[0] * 0.55, color[1] * 0.55, color[2] * 0.55};
  else if (k == 7) for (int i = 0; i < 3; i++) c2[i] = std::min(1.0, color[i] * 1.6 + 0.04);
  else {
    double m = k == 3 ? 0.25 : k == 5 || k == 4 ? 0.35 : 0.5;
    c2 = {color[0] * m, color[1] * m, color[2] * m};
  }
  const Value &sz = tex->f["size"];
  return {c2, {double(k), sz.isNone() ? texSize(k) : val0(sz), tex->f.num("axis"), tex->f["bump"].isNone() ? 0 : tex->f.num("bump")}};
}

// ---------- caches por forma (no JS ficam em campos _heavy, _code, _skey) ----------

static const std::set<std::string> HEAVY = {"displace", "pattern", "repeat", "twist", "bend", "taper", "polar", "extrude", "lathe", "implicit"};
static std::map<const Shape *, bool> &heavyCache() { static std::map<const Shape *, bool> c; return c; }

bool isHeavy(const Shape &s) {
  if (HEAVY.count(s.kind)) return true;
  for (auto &c : s.children)
    if (isHeavy(*c)) return true;
  return false;
}

// ---------- Gen ----------

namespace {
struct Gen {
  std::vector<std::string> lines, funcs;
  int n = 0, indent = 1;
  std::string tag;
  explicit Gen(std::string tag = "") : tag(std::move(tag)) {}

  std::string fn(const std::string &prefix, const std::function<std::string(const std::string &)> &make) {
    std::string name = prefix + tag + std::to_string(n++);
    funcs.push_back(make(name));
    return name;
  }
  void line(const std::string &s) {
    std::string pad;
    for (int i = 0; i < indent; i++) pad += "  ";
    lines.push_back(pad + s);
  }
  std::string tmp(const std::string &prefix) { return prefix + std::to_string(n++); }
  std::string vec(const std::string &expr) {
    std::string q = tmp("q");
    line("vec3 " + q + " = " + expr + ";");
    return q;
  }

  std::string leaf(const std::string &expr, const MatCtx &mat) {
    std::string m = tmp("m");
    const Props &P = mat.p;
    V3 color = P["color"].isNone() ? V3{0.6, 0.6, 0.62} : P.v3("color");
    Value rough = P["rough"].isNone() ? Value(0.6) : P["rough"];
    Value metal = P["metal"].isNone() ? Value(0.0) : P["metal"];
    Value glow = P["glow"].isNone() ? Value(0.0) : P["glow"];
    const Value &tex = P["tex"];
    TexP tp = texParams(tex, color);
    std::string texP = !tex.isNone() ? (mat.texP ? *mat.texP : "undefined") : "vec3(0.0)";
    line("M " + m + " = M(" + expr + ", " + v3(color) + ", " + v3(std::vector<Value>{rough, metal, glow}) + ", " + v3(tp.c2) + ", " + v4(tp.tx) + ", " +
         texP + ", " + f(facetCode(P["facet"], P["coat"].isNone() ? Value(0.0) : P["coat"])) + ");");
    return m;
  }

  std::string mapDist(const std::string &r, const std::function<std::string(const std::string &)> &fnd) {
    std::string m = tmp("m");
    line("M " + m + " = " + r + "; " + m + ".d = " + fnd(r + ".d") + ";");
    return m;
  }

  std::string combine(const std::string &a, const std::string &b, char op, double k) {
    std::string out = tmp("m");
    std::string fnm = std::string(op == 'u' ? "mU" : op == 's' ? "mS" : "mI") + (k ? "s" : "");
    line("M " + out + " = " + fnm + "(" + a + ", " + b + (k ? ", " + f(k) : "") + ");");
    return out;
  }

  std::string emit(const Shape &s, const std::string &p, const MatCtx &mat) {
    const Props &P = s.props;
    const std::string &k = s.kind;
    const Shape *c0 = s.children.empty() ? nullptr : s.children[0].get();
    auto num = [&](const char *key) { return P.num(key); };
    if (k == "box") {
      V3 sz = P.v3("size");
      double r = num("r");
      V3 h{sz[0] / 2 - r, sz[1] / 2 - r, sz[2] / 2 - r};
      return leaf(r ? "sdBox(" + p + ", " + v3(h) + ") - " + f(r) : "sdBox(" + p + ", " + v3(h) + ")", mat);
    }
    if (k == "sphere") return leaf("length(" + p + ") - " + f(num("r")), mat);
    if (k == "cbox") {
      V3 sz = P.v3("size");
      double r = num("r");
      V3 h{sz[0] / 2 - r, sz[1] / 2 - r, sz[2] / 2 - r};
      return leaf("sdCBox(" + p + ", " + v3(h) + ", " + f(std::max(0.0, num("c") - r)) + ")" + (r ? " - " + f(r) : ""), mat);
    }
    if (k == "cylinder") {
      double rr = num("round");
      return leaf("sdCyl(" + p + ", " + f(num("r") - rr) + ", " + f(num("h") / 2 - rr) + ")" + (rr ? " - " + f(rr) : ""), mat);
    }
    if (k == "cone") return leaf("sdCone(" + p + ", " + f(num("h") / 2) + ", " + f(num("r")) + ", " + f(num("top")) + ")", mat);
    if (k == "torus") return leaf("sdTorus(" + p + ", " + f(num("R")) + ", " + f(num("r")) + ")", mat);
    if (k == "capsule") return leaf("sdCapsule(" + p + ", " + f(num("r")) + ", " + f(num("h") / 2 - num("r")) + ")", mat);
    if (k == "ellipsoid") return leaf("sdEllipsoid(" + p + ", " + v3(P["radii"]) + ")", mat);
    if (k == "pyramid")
      return leaf("sdPyramid((" + p + " + vec3(0.0, " + f(num("h") / 2) + ", 0.0)) / " + f(num("w")) + ", " + f(num("h") / num("w")) + ") * " + f(num("w")), mat);
    if (k == "prism") return leaf("sdPrism(" + p + ", " + f(num("w") / 2) + ", " + f(num("h")) + ", " + f(num("d") / 2) + ")", mat);
    if (k == "plane") return leaf(p + ".y", mat);
    if (k == "roundcone") return leaf("sdRoundCone(" + p + ", " + v3(P["a"]) + ", " + v3(P["b"]) + ", " + f(num("r1")) + ", " + f(num("r2")) + ")", mat);
    if (k == "affine") {
      M3 mi = P.m3("minv");
      std::string cols;
      for (int c = 0; c < 3; c++)
        for (int r = 0; r < 3; r++) cols += (cols.empty() ? "" : ", ") + f(mi[r * 3 + c]);
      std::string r = emit(*c0, vec("mat3(" + cols + ") * (" + p + " - " + v3(P["t"]) + ")"), mat);
      double ds = num("ds");
      return ds == 1 ? r : mapDist(r, [&](const std::string &d) { return d + " * " + f(ds); });
    }
    if (k == "translate") return emit(*c0, vec(p + " - " + v3(P["v"])), mat);
    if (k == "rotate") {
      if (P.has("angles")) return emit(*c0, vec(p + " * rotEuler(" + v3(P["angles"]) + ")"), mat);
      M3 m = P.m3("m");
      std::string cols;
      for (int c = 0; c < 3; c++)
        for (int r = 0; r < 3; r++) cols += (cols.empty() ? "" : ", ") + f(m[r * 3 + c]);
      return emit(*c0, vec(p + " * mat3(" + cols + ")"), mat);
    }
    if (k == "scale") {
      std::string r = emit(*c0, vec(p + " / " + v3(P["s"])), mat);
      auto &sv = P["s"].list()->items;
      Value smin;
      if (std::any_of(sv.begin(), sv.end(), [](const Value &x) { return x.isExpr(); })) smin = sv[0];
      else smin = std::min({sv[0].n(), sv[1].n(), sv[2].n()});
      return mapDist(r, [&](const std::string &d) { return d + " * " + glslF(smin); });
    }
    if (k == "mirror") {
      std::string q = vec(p);
      V3 c = center(c0->bbox());
      for (int i = 0; i < 3; i++) {
        if (!P["axes"][i].b()) continue;
        std::string comp(1, "xyz"[i]);
        line(q + "." + comp + " = " + (c[i] < 0 ? "-" : "") + "abs(" + q + "." + comp + ");");
      }
      return emit(*c0, q, mat);
    }
    if (k == "repeat") {
      V3 n3 = P.v3("n"), s3 = P.v3("s"), sp, h, nm1;
      for (int i = 0; i < 3; i++) { sp[i] = n3[i] > 1 ? s3[i] : 1; h[i] = (n3[i] - 1) / 2; nm1[i] = n3[i] - 1; }
      std::string id = tmp("id");
      line("vec3 " + id + " = clamp(round(" + p + " / " + v3(sp) + " + " + v3(h) + "), vec3(0.0), " + v3(nm1) + ");");
      return emit(*c0, vec(p + " - " + v3(sp) + " * (" + id + " - " + v3(h) + ")"), mat);
    }
    if (k == "twist") {
      std::string c = tmp("c"), sn = tmp("s");
      double kk = num("k");
      line("float " + c + " = cos(" + f(kk) + " * " + p + ".y), " + sn + " = sin(" + f(kk) + " * " + p + ".y);");
      std::string q = vec("vec3(" + c + " * " + p + ".x - " + sn + " * " + p + ".z, " + p + ".y, " + sn + " * " + p + ".x + " + c + " * " + p + ".z)");
      const BBox &b = c0->bbox();
      double R = std::max({std::fabs(b.min[0]), std::fabs(b.max[0]), std::fabs(b.min[2]), std::fabs(b.max[2])}) * M_SQRT2;
      double lip = 1 / std::sqrt(1 + (kk * R) * (kk * R));
      std::string r = emit(*c0, q, mat);
      return mapDist(r, [&](const std::string &d) { return d + " * " + f(lip); });
    }
    if (k == "taper") {
      int ax = (int)num("axis");
      const char *X = "xyz";
      std::string t = tmp("tp"), sc = tmp("sc");
      double lo = num("lo"), hi = num("hi"), top = num("top"), bottom = num("bottom");
      line("float " + t + " = clamp((" + p + "." + X[ax] + " - " + f(lo) + ") / " + f(std::max(1e-6, hi - lo)) + ", 0.0, 1.0);");
      line("float " + sc + " = mix(" + f(bottom) + ", " + f(top) + ", " + t + ");");
      std::string parts;
      for (int i = 0; i < 3; i++) parts += (i ? ", " : "") + (i == ax ? p + "." + X[i] : p + "." + X[i] + " / " + sc);
      std::string q = vec("vec3(" + parts + ")");
      const BBox &b = c0->bbox();
      double R = -INFINITY;
      for (int i = 0; i < 3; i++)
        if (i != ax) R = std::max(R, std::max(std::fabs(b.min[i]), std::fabs(b.max[i])));
      R *= M_SQRT2;
      double smin = std::min(top, bottom), slope = std::fabs(top - bottom) / std::max(1e-6, hi - lo);
      double lip = smin / std::sqrt(1 + ((slope * R) / smin) * ((slope * R) / smin));
      return mapDist(emit(*c0, q, mat), [&](const std::string &d) { return d + " * " + f(lip); });
    }
    if (k == "bend") {
      const char *X = "xyz";
      std::string c = tmp("c"), sn = tmp("s");
      int axis = (int)num("axis"), toward = (int)num("toward");
      double pivot = num("pivot"), kk = num("k");
      std::string u = "(" + p + "." + X[axis] + " - " + f(pivot) + ")", v = p + "." + X[toward];
      line("float " + c + " = cos(" + f(kk) + " * " + u + "), " + sn + " = sin(" + f(kk) + " * " + u + ");");
      std::string parts;
      for (int i = 0; i < 3; i++)
        parts += (i ? ", " : "") + (i == axis ? c + " * " + u + " - " + sn + " * " + v + " + " + f(pivot) : i == toward ? sn + " * " + u + " + " + c + " * " + v : p + "." + X[i]);
      std::string q = vec("vec3(" + parts + ")");
      const BBox &b = c0->bbox();
      double R = std::hypot(std::max(std::fabs(b.min[axis] - pivot), std::fabs(b.max[axis] - pivot)), std::max(std::fabs(b.min[toward]), std::fabs(b.max[toward])));
      return mapDist(emit(*c0, q, mat), [&](const std::string &d) { return d + " / sqrt(1.0 + " + f((kk * R) * (kk * R)) + ")"; });
    }
    if (k == "shear") {
      double sx = num("sx"), sz = num("sz"), y0 = num("y0");
      std::string q = vec("vec3(" + p + ".x - " + f(sx) + " * (" + p + ".y - " + f(y0) + "), " + p + ".y, " + p + ".z - " + f(sz) + " * (" + p + ".y - " + f(y0) + "))");
      return mapDist(emit(*c0, q, mat), [&](const std::string &d) { return d + " / sqrt(" + f(1 + sx * sx + sz * sz) + ")"; });
    }
    if (k == "polar") {
      std::string sec = tmp("sec"), an = tmp("an"), rr = tmp("rr");
      line("float " + sec + " = " + f((2 * M_PI) / num("n")) + ", " + rr + " = length(" + p + ".xz);");
      line("float " + an + " = mod(atan(" + p + ".z, " + p + ".x) + 0.5 * " + sec + ", " + sec + ") - 0.5 * " + sec + ";");
      return emit(*c0, vec("vec3(" + rr + " * cos(" + an + "), " + p + ".y, " + rr + " * sin(" + an + "))"), mat);
    }
    if (k == "elongate") {
      std::string hv = v3(P["h"]);
      return emit(*c0, vec(p + " - clamp(" + p + ", -" + hv + ", " + hv + ")"), mat);
    }
    if (k == "extrude") {
      auto pts = pointsOf(P["pts"]);
      std::string name = fn("sdPoly", [&](const std::string &nm) { return polygonGlsl(nm, pts); });
      bool z = P["axis"].s() == "z";
      std::string d2 = z ? name + "(" + p + ".xy)" : name + "(" + p + ".xz)";
      return leaf("sdExt(" + d2 + ", " + (z ? p + ".z" : p + ".y") + ", " + f(num("h") / 2) + ", " + f(num("r")) + ")", mat);
    }
    if (k == "implicit") {
      std::string body = glslOf(P["f"]);
      std::string name = fn("sdImpl", [&](const std::string &nm) { return "float " + nm + "(vec3 ip) {\n  return " + body + ";\n}"; });
      return leaf("max(" + name + "(" + p + ") * " + f(num("lip")) + ", sdBox(" + p + ", " + v3(P["half"]) + "))", mat);
    }
    if (k == "lathe") {
      auto pts = pointsOf(P["pts"]);
      std::string name = fn("sdPoly", [&](const std::string &nm) { return polygonGlsl(nm, pts); });
      return leaf(name + "(vec2(length(" + p + ".xz), " + p + ".y))", mat);
    }
    if (k == "round") return mapDist(emit(*c0, p, mat), [&](const std::string &d) { return d + " - " + f(num("r")); });
    if (k == "shell") return mapDist(emit(*c0, p, mat), [&](const std::string &d) { return "abs(" + d + ") - " + f(num("t") / 2); });
    if (k == "displace") {
      double amt = num("amt"), size = num("size");
      double lip = 1 / (1 + (2.5 * amt) / size);
      return mapDist(emit(*c0, p, mat), [&](const std::string &d) {
        return "(" + d + " + " + f(amt) + " * (fbm(" + p + " / " + f(size) + ") * 2.0 - 1.0)) * " + f(lip);
      });
    }
    if (k == "pattern") {
      auto pp = patternOf(P);
      std::string call = "patG(" + p + ", " + v3(P["bmin"]) + ", " + v3(P["bc"]) + ", " + v3(P["hf"]) + ", " + std::to_string(pp.kind) + ", vec2(" + f(pp.sz[0]) + ", " +
                         f(pp.sz[1]) + "), " + f(pp.gap) + ", " + std::to_string(pp.ax) + ", " + f(pp.vary) + ")";
      return mapDist(emit(*c0, p, mat), [&](const std::string &d) { return "(" + d + " + " + f(pp.depth) + " * " + call + ") * " + f(patternLip(pp)); });
    }
    if (k == "material") {
      MatCtx merged = mat;
      for (const char *key : MAT_KEYS)
        if (!P[key].isNone()) merged.p.set(key, P[key]);
      if (!P["tex"].isNone()) {
        auto tex = P["tex"].as<Rec>();
        double off = tex->f["off"].isNone() ? 0 : tex->f.num("off");
        if (off) {
          V3 o{0, 0, 0};
          o[(int)tex->f.num("offAxis")] = off;
          merged.texP = "(" + p + " - " + v3(o) + ")";
        } else merged.texP = p;
      }
      return emit(*c0, p, merged);
    }
    if (k == "label") return emit(*c0, p, mat);
    if (k == "paint") {
      std::string a = emit(*c0, p, mat);
      std::string w = tmp("w");
      double kk = num("k"), relief = P["relief"].isNone() ? 0 : num("relief");
      line("if (" + a + ".d < " + f(kk + 0.06 + 2 * std::fabs(relief)) + ") {");
      indent++;
      std::string r = emit(*s.children[1], p, mat);
      line("float " + w + " = 1.0 - smoothstep(" + f(-kk) + ", " + f(kk + 1e-5) + ", " + r + ".d);");
      if (relief) line(a + ".d -= " + f(relief) + " * " + w + ";");
      line(a + ".c = mix(" + a + ".c, " + r + ".c, " + w + "); " + a + ".m = mix(" + a + ".m, " + r + ".m, " + w + ");");
      line("if (" + w + " > 0.5) { " + a + ".c2 = " + r + ".c2; " + a + ".tx = " + r + ".tx; " + a + ".tp = " + r + ".tp; " + a + ".fc = " + r + ".fc; }");
      indent--;
      line("}");
      return a;
    }
    if (k == "union") return emitUnion(s, p, mat);
    if (k == "merge") {
      std::string acc = emit(*s.children[0], p, mat);
      std::string prof = P["profile"].s() == "round" ? "0" : P["profile"].s() == "chamfer" ? "1" : "2";
      bool seam = !P["seam"].isNone();
      for (size_t i = 1; i < s.children.size(); i++) {
        std::string b = emit(*s.children[i], p, mat);
        std::string out = tmp("m");
        line("M " + out + " = mMerge(" + acc + ", " + b + ", " + f(num("r")) + ", " + prof + ", " + (P["colors"].s() == "blend" ? "1" : "0") + ", " +
             (seam ? v3(P["seam"]) : v3(V3{0, 0, 0})) + ", " + f(seam ? num("seamWidth") : 0) + ");");
        acc = out;
      }
      return acc;
    }
    if (k == "subtract") {
      std::string a = emit(*s.children[0], p, mat);
      std::string b = emit(*s.children[1], p, mat);
      return combine(a, b, 's', num("k"));
    }
    if (k == "intersect") {
      std::string acc = emit(*s.children[0], p, mat);
      for (size_t i = 1; i < s.children.size(); i++) acc = combine(acc, emit(*s.children[i], p, mat), 'i', num("k"));
      return acc;
    }
    throw std::runtime_error("compilador: tipo desconhecido " + k);
  }

  std::string emitUnion(const Shape &s, const std::string &p, const MatCtx &mat) {
    double k = s.props.num("k");
    if (k) {
      std::string acc = emit(*s.children[0], p, mat);
      for (size_t i = 1; i < s.children.size(); i++) acc = combine(acc, emit(*s.children[i], p, mat), 'u', k);
      return acc;
    }
    std::string acc = tmp("u");
    line("M " + acc + " = " + M_FAR + ";");
    for (auto &c : s.children) {
      const BBox &b = c->bbox();
      bool bounded = (c->leaves() >= 3 || isHeavy(*c)) && isFiniteBB(b) && !c->animated();
      if (bounded) {
        V3 sz = size(b), half{sz[0] / 2 + 0.01, sz[1] / 2 + 0.01, sz[2] / 2 + 0.01};
        line("if (sdBox(" + p + " - " + v3(center(b)) + ", " + v3(half) + ") < " + acc + ".d) {");
      } else line("{");
      indent++;
      std::string d = emit(*c, p, mat);
      line(acc + " = mU(" + acc + ", " + d + ");");
      indent--;
      line("}");
    }
    return acc;
  }
};
}  // namespace

// ---------- primitivas como dados (BVH) ----------

static int primId(const std::string &k) {
  static const std::map<std::string, int> P = {{"box", 1}, {"sphere", 2}, {"cylinder", 3}, {"cone", 4}, {"torus", 5}, {"capsule", 6}, {"ellipsoid", 7}, {"pyramid", 8}, {"prism", 9}};
  auto it = P.find(k);
  return it == P.end() ? 0 : it->second;
}

static std::array<double, 4> primParams(const Shape &s) {
  const Props &P = s.props;
  const std::string &k = s.kind;
  if (k == "box") { V3 z = P.v3("size"); double r = P.num("r"); return {z[0] / 2 - r, z[1] / 2 - r, z[2] / 2 - r, r}; }
  if (k == "sphere") return {P.num("r"), 0, 0, 0};
  if (k == "cylinder") return {P.num("r") - P.num("round"), P.num("h") / 2 - P.num("round"), P.num("round"), 0};
  if (k == "cone") return {P.num("h") / 2, P.num("r"), P.num("top"), 0};
  if (k == "torus") return {P.num("R"), P.num("r"), 0, 0};
  if (k == "capsule") return {P.num("r"), P.num("h") / 2 - P.num("r"), 0, 0};
  if (k == "ellipsoid") { V3 r = P.v3("radii"); return {r[0], r[1], r[2], 0}; }
  if (k == "pyramid") return {P.num("w"), P.num("h"), 0, 0};
  return {P.num("w") / 2, P.num("h"), P.num("d") / 2, 0};
}

static MatCtx mergeMat(const MatCtx &mat, const Props &P) {
  MatCtx out = mat;
  for (const char *k : MAT_KEYS)
    if (!P[k].isNone()) out.p.set(k, P[k]);
  return out;
}

using StopFn = std::function<bool(const ShapeP &, const M3 &, const V3 &, double, const MatCtx &)>;
using LeafFn = std::function<void(const ShapeP &, const M3 &, const V3 &, double, const MatCtx &)>;

static void walkScene(const std::vector<ShapeP> &shapes, const StopFn &stop, const LeafFn &leaf) {
  std::function<void(const ShapeP &, const M3 &, const V3 &, double, const MatCtx &)> visit = [&](const ShapeP &s, const M3 &m, const V3 &t, double ds, const MatCtx &mat) {
    if (stop(s, m, t, ds, mat)) return;
    const ShapeP &c0 = s->children.empty() ? s : s->children[0];
    std::string k = s->selfAnimated() ? "animated" : s->kind;
    if (k == "translate") {
      V3 mv = mulMV(m, s->props.v3("v"));
      visit(c0, m, {t[0] + mv[0], t[1] + mv[1], t[2] + mv[2]}, ds, mat);
      return;
    }
    if (k == "rotate") { visit(c0, mul3(m, s->props.m3("m")), t, ds, mat); return; }
    if (k == "scale") {
      V3 S = s->props.v3("s");
      visit(c0, mul3(m, {S[0], 0, 0, 0, S[1], 0, 0, 0, S[2]}), t, ds * std::min({S[0], S[1], S[2]}), mat);
      return;
    }
    if (k == "material") {
      MatCtx merged = mergeMat(mat, s->props);
      if (!s->props["tex"].isNone()) {
        auto tex = s->props["tex"].as<Rec>();
        double off = tex->f["off"].isNone() ? 0 : tex->f.num("off");
        V3 tt = t;
        if (off) {
          V3 o{0, 0, 0};
          o[(int)tex->f.num("offAxis")] = off;
          V3 shift = mulMV(m, o);
          tt = {t[0] + shift[0], t[1] + shift[1], t[2] + shift[2]};
        }
        merged.texFrame = TexFrame{m, tt};
      }
      visit(c0, m, t, ds, merged);
      return;
    }
    if (k == "label") { visit(c0, m, t, ds, mat); return; }
    if (k == "union" && !s->props.num("k")) {
      for (auto &c : s->children) visit(c, m, t, ds, mat);
      return;
    }
    leaf(s, m, t, ds, mat);
  };
  for (auto &s : shapes) visit(s, IDENT, {0, 0, 0}, 1, MatCtx{});
}

ShapeP wrapNode(const ShapeP &s, const M3 &m, const V3 &t, double ds, const MatCtx &mat) {
  ShapeP node = s;
  if (!mat.p.kv.empty()) {
    Props p{{"color", Value()}, {"rough", Value()}, {"metal", Value()}, {"glow", Value()}, {"tex", Value()}, {"facet", Value()}, {"coat", Value()}};
    for (auto &[k, v] : mat.p.kv) p.set(k, v);
    node = mkShape("material", p, {node});
  }
  bool ident = true;
  for (int i = 0; i < 9; i++) ident &= std::fabs(m[i] - IDENT[i]) < 1e-12;
  ident &= t[0] == 0 && t[1] == 0 && t[2] == 0;
  if (!ident) node = mkShape("affine", {{"m", nums9(m)}, {"t", nums3(t)}, {"minv", nums9(inv3(m))}, {"ds", ds}}, {node});
  return node;
}

// ---------- instâncias de código ----------

static const std::set<std::string> FLAT = {"translate", "rotate", "scale", "material", "label"};

static bool needsCode(const Shape &s, std::unordered_map<const Shape *, bool> &memo) {
  auto it = memo.find(&s);
  if (it != memo.end()) return it->second;
  bool r;
  if (s.selfAnimated()) r = true;
  else if (primId(s.kind)) r = false;
  else if (FLAT.count(s.kind) || (s.kind == "union" && !s.props.num("k"))) {
    r = false;
    for (auto &c : s.children) r = r || needsCode(*c, memo);
  } else r = true;
  return memo[&s] = r;
}

// JSON.stringify do JS (ordem de inserção das chaves; números como String(x))
static void jsonJS(const Value &v, std::string &out) {
  if (v.isNone()) out += "null";
  else if (v.isBool()) out += v.b() ? "true" : "false";
  else if (v.isNum()) out += std::isfinite(v.n()) ? jsNum(v.n()) : "null";
  else if (v.isStr()) out += Json(v.s()).dump();
  else if (v.isList()) {
    out += '[';
    for (size_t i = 0; i < v.size(); i++) {
      if (i) out += ',';
      if (v[i].isFunc()) out += "null";
      else jsonJS(v[i], out);
    }
    out += ']';
  } else if (v.isExpr()) {
    out += "{\"op\":" + Json(v.expr()->op).dump() + ",\"args\":";
    jsonJS(list(v.expr()->args), out);
    out += '}';
  } else if (auto r = v.as<Rec>()) {
    out += '{';
    bool first = true;
    for (auto &[k, x] : r->f.kv) {
      if (x.isFunc()) continue;
      out += (first ? "" : ",") + Json(k).dump() + ":";
      jsonJS(x, out);
      first = false;
    }
    out += '}';
  } else out += "{}";
}
static std::string propsJS(const Props &p) {
  std::string out = "{";
  bool first = true;
  for (auto &[k, x] : p.kv) {
    if (x.isFunc()) continue;
    out += (first ? "" : ",") + Json(k).dump() + ":";
    jsonJS(x, out);
    first = false;
  }
  return out + "}";
}

namespace {
struct Keys {
  std::unordered_map<std::string, int> ids;
  std::unordered_map<const Shape *, int> skey;  // -1: nulo
  std::unordered_map<const Shape *, bool> code;
  int structKey(const Shape &s) {
    auto it = skey.find(&s);
    if (it != skey.end()) return it->second;
    int key = -1;
    if (s.kind != "bound") {
      std::string kids;
      bool ok = true;
      for (size_t i = 0; i < s.children.size(); i++) {
        int c = structKey(*s.children[i]);
        if (c < 0) { ok = false; break; }
        kids += (i ? "," : "") + std::to_string(c);
      }
      if (ok) {
        std::string str = s.kind + "|" + propsJS(s.props) + "|" + kids;
        auto f = ids.find(str);
        if (f == ids.end()) f = ids.emplace(str, (int)ids.size()).first;
        key = f->second;
      }
    }
    return skey[&s] = key;
  }
  std::optional<std::string> instanceKey(const Shape &s, const MatCtx &mat) {
    if (FLAT.count(s.kind) || s.animated() || !needsCode(s, code) || !(s.leaves() >= 3 || isHeavy(s))) return std::nullopt;
    int k = structKey(s);
    if (k < 0) return std::nullopt;
    return std::to_string(k) + "|" + propsJS(mat.p);
  }
};
}  // namespace

Split splitScene(const std::vector<ShapeP> &shapes, bool instancing) {
  Split out;
  Keys keys;
  std::unordered_map<std::string, int> counts;
  std::vector<std::string> order;
  std::unordered_map<std::string, std::vector<Occ>> groups;
  if (instancing) {
    walkScene(
        shapes,
        [&](const ShapeP &s, const M3 &, const V3 &, double, const MatCtx &mat) {
          auto k = keys.instanceKey(*s, mat);
          if (k) counts[*k]++;
          return false;
        },
        [](const ShapeP &, const M3 &, const V3 &, double, const MatCtx &) {});
  }
  walkScene(
      shapes,
      [&](const ShapeP &s, const M3 &m, const V3 &t, double ds, const MatCtx &mat) {
        if (!instancing) return false;
        auto k = keys.instanceKey(*s, mat);
        if (!k) return false;
        int n = counts[*k];
        if (n < 2 || (n * s->leaves() < 12 && !isHeavy(*s))) return false;
        if (!groups.count(*k)) order.push_back(*k);
        groups[*k].push_back({s, m, t, ds, mat});
        return true;
      },
      [&](const ShapeP &s, const M3 &m, const V3 &t, double ds, const MatCtx &mat) {
        if (primId(s->kind)) out.instances.push_back({s, m, t, ds, mat});
        else out.residual.push_back(wrapNode(s, m, t, ds, mat));
      });
  for (auto &k : order) {
    auto &occ = groups[k];
    if (occ.size() < 2) {
      for (auto &o : occ) out.residual.push_back(wrapNode(o.s, o.m, o.t, o.ds, o.mat));
    } else out.groups.push_back(occ);
  }
  return out;
}

static const int INST_W = 11, BVH_W = 2, LEAF_SIZE = 4;

static std::vector<float> packInstances(const std::vector<const Occ *> &list) {
  std::vector<float> data(list.size() * INST_W * 4);
  for (size_t n = 0; n < list.size(); n++) {
    const Occ &it = *list[n];
    size_t o = n * INST_W * 4;
    auto put = [&](size_t at, std::initializer_list<double> v) {
      size_t i = at;
      for (double x : v) data[i++] = (float)x;
    };
    auto pr = primParams(*it.s);
    M3 mi = inv3(it.m);
    V3 mt = mulMV(mi, it.t);
    const Props &P = it.mat.p;
    V3 color = P["color"].isNone() ? V3{0.6, 0.6, 0.62} : P.v3("color");
    double rough = P["rough"].isNone() ? 0.6 : P.num("rough"), metal = P["metal"].isNone() ? 0 : P.num("metal");
    double glow = P["glow"].isNone() ? 0 : P.num("glow");
    TexP tp = texParams(P["tex"], color);
    put(o, {double(primId(it.s->kind)), pr[0], pr[1], pr[2]});
    put(o + 4, {pr[3], it.ds, tp.tx[3], facetCode(P["facet"], P["coat"].isNone() ? Value(0.0) : P["coat"])});
    for (int r = 0; r < 3; r++) put(o + 8 + r * 4, {mi[r * 3], mi[r * 3 + 1], mi[r * 3 + 2], -mt[r]});
    put(o + 20, {color[0], color[1], color[2], rough});
    put(o + 24, {metal, glow, tp.tx[0], tp.tx[1]});
    put(o + 28, {tp.c2[0], tp.c2[1], tp.c2[2], tp.tx[2]});
    TexFrame tf = it.mat.texFrame ? *it.mat.texFrame : TexFrame{IDENT, {0, 0, 0}};
    M3 ti = inv3(tf.m);
    V3 tt = mulMV(ti, tf.t);
    for (int r = 0; r < 3; r++) put(o + 32 + r * 4, {ti[r * 3], ti[r * 3 + 1], ti[r * 3 + 2], -tt[r]});
  }
  return data;
}

static BBox worldBox(const Shape &s, const M3 &m, const V3 &t) {
  std::vector<V3> pts;
  for (auto &c : corners(s.bbox())) {
    V3 q = mulMV(m, c);
    pts.push_back({q[0] + t[0], q[1] + t[1], q[2] + t[2]});
  }
  return fromPoints(pts);
}

struct BvhOut {
  std::vector<float> bvh;
  int nodeCount;
  std::vector<int> order;
};
static BvhOut buildBVH(const std::vector<Occ> &instances) {
  struct Item { BBox b; V3 c; int idx; };
  struct NodeB { BBox b; int a, count; };
  std::vector<Item> items;
  for (size_t i = 0; i < instances.size(); i++) {
    BBox b = worldBox(*instances[i].s, instances[i].m, instances[i].t);
    items.push_back({b, center(b), (int)i});
  }
  std::vector<NodeB> nodes;
  std::vector<int> order;
  std::function<int(std::vector<Item>)> build = [&](std::vector<Item> list) -> int {
    int ni = (int)nodes.size();
    nodes.push_back({});
    std::vector<BBox> bs;
    for (auto &x : list) bs.push_back(x.b);
    BBox b = unionBB(bs);
    if (list.size() <= (size_t)LEAF_SIZE) {
      nodes[ni] = {b, (int)order.size(), (int)list.size()};
      for (auto &x : list) order.push_back(x.idx);
      return ni;
    }
    std::vector<V3> cs;
    for (auto &x : list) cs.push_back(x.c);
    V3 ext = size(fromPoints(cs));
    int axis = 0;
    for (int i = 1; i < 3; i++)
      if (ext[i] > ext[axis]) axis = i;
    std::stable_sort(list.begin(), list.end(), [axis](const Item &p, const Item &q) { return p.c[axis] < q.c[axis]; });
    size_t mid = list.size() >> 1;
    build(std::vector<Item>(list.begin(), list.begin() + mid));
    int right = build(std::vector<Item>(list.begin() + mid, list.end()));
    nodes[ni] = {b, right, 0};
    return ni;
  };
  build(items);
  std::vector<float> data(nodes.size() * BVH_W * 4);
  for (size_t i = 0; i < nodes.size(); i++) {
    auto &n = nodes[i];
    float v[8] = {(float)n.b.min[0], (float)n.b.min[1], (float)n.b.min[2], (float)n.a, (float)n.b.max[0], (float)n.b.max[1], (float)n.b.max[2], (float)n.count};
    std::copy(v, v + 8, data.begin() + i * 8);
  }
  return {data, (int)nodes.size(), order};
}

Compiled compileScene(const Scene &scene) {
  auto shapes = resolveRig(scene.shapes);
  if (shapes.empty()) throw ScriptError("nada para mostrar", 0, "termine o script com show(forma1, forma2, ...)");
  Split sp = splitScene(shapes, true);
  auto &instances = sp.instances;
  auto &residual = sp.residual;
  auto &groups = sp.groups;
  bool useBVH = instances.size() >= (size_t)INSTANCE_THRESHOLD;
  ShapeP codeRoot;
  if (useBVH) codeRoot = residual.empty() ? nullptr : unionOf(residual);
  else if (!groups.empty()) {
    std::vector<ShapeP> l;
    for (auto &o : instances) l.push_back(wrapNode(o.s, o.m, o.t, o.ds, o.mat));
    l.insert(l.end(), residual.begin(), residual.end());
    codeRoot = l.empty() ? nullptr : unionOf(l);
  } else codeRoot = unionOf(shapes);
  bool emptyRoot = !useBVH && !groups.empty() && instances.empty() && residual.empty();
  int groupFirst = 0, groupLeaves = 0;
  for (auto &g : groups) { groupFirst += g[0].s->leaves(); groupLeaves += (int)g.size() * g[0].s->leaves(); }
  int rootLeaves = codeRoot && !emptyRoot ? codeRoot->leaves() : 0;

  Compiled out;
  std::string mBody = std::string("  return ") + M_FAR + ";";
  std::string funcs;
  std::vector<std::array<double, 4>> codeRows;
  if (codeRoot || !groups.empty()) {
    Gen Mg;
    std::string mOut;
    if (codeRoot && !emptyRoot) mOut = Mg.emit(*codeRoot, "p", MatCtx{});
    else { mOut = Mg.tmp("m"); Mg.line("M " + mOut + " = " + M_FAR + ";"); }
    std::vector<std::string> extra;
    if (!groups.empty())
      extra.push_back("uniform highp sampler2D uCode;\nvec4 codeFetch(int col, int row) {\n  int index = row * " + std::to_string(CODE_W) +
                      " + col;\n  int width = textureSize(uCode, 0).x;\n  return texelFetch(uCode, ivec2(index % width, index / width), 0);\n}");
    for (size_t gi = 0; gi < groups.size(); gi++) {
      auto &occ = groups[gi];
      size_t base = codeRows.size() / CODE_W;
      Gen G("_i" + std::to_string(gi) + "_");
      std::string r = G.emit(*wrapNode(occ[0].s, IDENT, {0, 0, 0}, 1, occ[0].mat), "p", MatCtx{});
      extra.insert(extra.end(), G.funcs.begin(), G.funcs.end());
      std::string body;
      for (size_t i = 0; i < G.lines.size(); i++) body += (i ? "\n" : "") + G.lines[i];
      extra.push_back("M ci" + std::to_string(gi) + "(vec3 p) {\n" + body + "\n  return " + r + ";\n}");
      std::vector<std::array<double, 4>> rows;
      for (auto &o : occ) {
        M3 mi = inv3(o.m);
        V3 off = mulMV(mi, o.t);
        BBox wb = worldBox(*o.s, o.m, o.t);
        V3 sz = size(wb), c = center(wb);
        rows.push_back({mi[0], mi[1], mi[2], -off[0]});
        rows.push_back({mi[3], mi[4], mi[5], -off[1]});
        rows.push_back({mi[6], mi[7], mi[8], -off[2]});
        rows.push_back({c[0], c[1], c[2], o.ds});
        rows.push_back({sz[0] / 2 + 0.01, sz[1] / 2 + 0.01, sz[2] / 2 + 0.01, 0});
      }
      codeRows.insert(codeRows.end(), rows.begin(), rows.end());
      size_t nm = (occ.size() + 31) / 32;
      std::vector<std::string> mk;
      for (size_t i = 0; i < nm; i++) mk.push_back(Mg.tmp("mk"));
      std::string decl;
      for (size_t i = 0; i < nm; i++) decl += (i ? ", " : "") + mk[i] + " = 0";
      Mg.line("int " + decl + ";");
      for (size_t i = 0; i < occ.size(); i++) {
        auto &r3 = rows[i * CODE_W + 3], &r4 = rows[i * CODE_W + 4];
        Mg.line("if (sdBox(p - " + v3(V3{r3[0], r3[1], r3[2]}) + ", " + v3(V3{r4[0], r4[1], r4[2]}) + ") < " + mOut + ".d) " + mk[i >> 5] + " |= " +
                std::to_string((int32_t)(1u << (i & 31))) + ";");
      }
      for (size_t w = 0; w < nm; w++) {
        Mg.line("for (int b = uZero, bits = " + mk[w] + "; bits != 0; b++, bits = int(uint(bits) >> 1u)) {");
        Mg.indent++;
        Mg.line("if ((bits & 1) == 0) continue;");
        Mg.line("int i = " + std::to_string(base + w * 32) + " + b;");
        Mg.line("vec4 bc = codeFetch(3, i);");
        Mg.line("if (sdBox(p - bc.xyz, codeFetch(4, i).xyz) >= " + mOut + ".d) continue;");
        Mg.line("vec4 r0 = codeFetch(0, i), r1 = codeFetch(1, i), r2 = codeFetch(2, i);");
        Mg.line("M ri = ci" + std::to_string(gi) + "(vec3(dot(r0.xyz, p) + r0.w, dot(r1.xyz, p) + r1.w, dot(r2.xyz, p) + r2.w));");
        Mg.line("ri.d *= bc.w;");
        Mg.line(mOut + " = mU(" + mOut + ", ri);");
        Mg.indent--;
        Mg.line("}");
      }
    }
    mBody.clear();
    for (size_t i = 0; i < Mg.lines.size(); i++) mBody += (i ? "\n" : "") + Mg.lines[i];
    mBody += "\n  return " + mOut + ";";
    std::vector<std::string> all = Mg.funcs;
    all.insert(all.end(), extra.begin(), extra.end());
    if (!all.empty()) {
      funcs = "\n";
      for (size_t i = 0; i < all.size(); i++) funcs += (i ? "\n" : "") + all[i];
      funcs += "\n";
    }
    if (!codeRows.empty()) {
      for (auto &r : codeRows)
        for (double x : r) out.data.code.push_back((float)x);
      out.data.codeCount = (int)(codeRows.size() / CODE_W);
      out.hasData = true;
    }
  }

  if (useBVH) {
    BvhOut b = buildBVH(instances);
    std::vector<const Occ *> ord;
    for (int i : b.order) ord.push_back(&instances[i]);
    out.data.inst = packInstances(ord);
    out.data.instCount = (int)instances.size();
    out.data.bvh = b.bvh;
    out.data.nodeCount = b.nodeCount;
    out.hasData = true;
    out.glsl = GLSL_LIB + GLSL_BVH_SRC + funcs + "\nM codeM(vec3 p) {\n" + mBody +
               "\n}\nM mapAll(vec3 p, bool wantMat) {\n  M r = codeM(p);\n  int hit;\n  r.d = bvhD(p, r.d, hit);\n  if (hit >= 0 && wantMat) {\n"
               "    vec4 bb = instFetch(1, hit);\n    vec4 c = instFetch(5, hit);\n    vec4 e = instFetch(6, hit);\n    vec4 c2 = instFetch(7, hit);\n"
               "    vec4 t0 = instFetch(8, hit), t1 = instFetch(9, hit), t2 = instFetch(10, hit);\n"
               "    vec3 tp = vec3(dot(t0.xyz, p) + t0.w, dot(t1.xyz, p) + t1.w, dot(t2.xyz, p) + t2.w);\n"
               "    r = M(r.d, c.rgb, vec3(c.a, e.x, e.y), c2.rgb, vec4(e.z, e.w, c2.a, bb.z), tp, bb.w);\n  }\n  return r;\n}\n";
  } else {
    out.glsl = GLSL_LIB + funcs + "\nM mapAll(vec3 p, bool wantMat) {\n" + mBody + "\n}\n";
  }

  std::vector<BBox> finite;
  for (auto &s : shapes)
    if (isFiniteBB(s->bbox())) finite.push_back(s->bbox());
  out.bbox = finite.empty() ? BBox{{-1, 0, -1}, {1, 1, 1}} : unionBB(finite);
  out.hasPlane = std::any_of(shapes.begin(), shapes.end(), [](auto &s) { return !isFiniteBB(s->bbox()); });
  out.animated = out.glsl.find("uTime") != std::string::npos;
  out.leaves = rootLeaves + groupLeaves + (useBVH ? (int)instances.size() : 0);
  out.codeLeaves = rootLeaves + groupFirst;
  out.instances = useBVH ? (int)instances.size() : 0;
  for (auto &g : groups) out.codeGroups.push_back((int)g.size());
  out.parts = collectParts(shapes);
  return out;
}

}  // namespace tdi
