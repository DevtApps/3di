// Curvas spline/bezier, sweep e along (port de curve.js).
#include <algorithm>
#include <cmath>

#include "interp.h"

namespace tdi {

static const int SAMPLES = 64;
using CurveFn = std::function<V3(double)>;

static V3 sub(const V3 &a, const V3 &b) { return {a[0] - b[0], a[1] - b[1], a[2] - b[2]}; }
static V3 add(const V3 &a, const V3 &b) { return {a[0] + b[0], a[1] + b[1], a[2] + b[2]}; }
static V3 mulS(const V3 &a, double k) { return {a[0] * k, a[1] * k, a[2] * k}; }
static double len(const V3 &a) { return std::sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]); }
static V3 normV(const V3 &a) { double l = len(a); return l > 1e-12 ? mulS(a, 1 / l) : V3{1, 0, 0}; }
static V3 cross(const V3 &a, const V3 &b) { return {a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]}; }

static V3 vec3c(const Value &v, const std::string &what) {
  if (!v.isList() || (v.size() != 3 && v.size() != 2)) throw ScriptError(what + ": espera um ponto (x, y, z), recebeu " + typeName(v));
  if (v.size() == 2) return {num(v[0], what), num(v[1], what), 0};
  return {num(v[0], what), num(v[1], what), num(v[2], what)};
}

static double fixN(double v, int n) {
  char buf[64];
  std::snprintf(buf, sizeof buf, "%.*f", n, v);
  return std::strtod(buf, nullptr);
}

struct Curve : Object {
  CurveFn f;
  std::string label;
  std::vector<double> us, ls;
  double length = 0;

  Curve(CurveFn fn, double spans, std::string lab) : f(std::move(fn)), label(std::move(lab)) {
    int n = (int)(std::max(1.0, spans) * SAMPLES);
    V3 prev = f(0);
    double total = 0;
    for (int i = 0; i <= n; i++) {
      double u = double(i) / n;
      V3 p = f(u);
      total += len(sub(p, prev));
      prev = p;
      us.push_back(u);
      ls.push_back(total);
    }
    length = total;
  }
  double param(double s) const {
    double L = std::min(1.0, std::max(0.0, s)) * length;
    size_t lo = 0, hi = ls.size() - 1;
    while (hi - lo > 1) {
      size_t mid = (lo + hi) >> 1;
      if (ls[mid] < L) lo = mid; else hi = mid;
    }
    double span = ls[hi] - ls[lo];
    double k = span > 1e-12 ? (L - ls[lo]) / span : 0;
    return us[lo] + (us[hi] - us[lo]) * k;
  }
  V3 pointAt(double s) const { return f(param(s)); }
  V3 tangentAt(double s) const {
    double u = param(s), e = 1e-4;
    return normV(sub(f(std::min(1.0, u + e)), f(std::max(0.0, u - e))));
  }
  std::vector<V3> sample(int n) const {
    std::vector<V3> out;
    for (int i = 0; i <= n; i++) out.push_back(pointAt(double(i) / n));
    return out;
  }
  std::string describe() const override {
    V3 a = f(0), b = f(1);
    return "<curva " + label + " " + fmtNum(fixN(length, 3)) + " m de (" + fmtNum(a[0]) + ", " + fmtNum(a[1]) + ", " + fmtNum(a[2]) + ") até (" +
           fmtNum(b[0]) + ", " + fmtNum(b[1]) + ", " + fmtNum(b[2]) + ")>";
  }
  Value attr(const std::string &name) override;
  Json plain() const override {
    Json o = Json::object();
    o.set("$", "Curve");
    o.set("label", label);
    o.set("length", round9(length));
    return o;
  }
};

static Value t3(const V3 &p) { return tuple({fixN(p[0], 9), fixN(p[1], 9), fixN(p[2], 9)}); }

Value Curve::attr(const std::string &name) {
  auto self = std::static_pointer_cast<Curve>(shared_from_this());
  if (name == "length") return length;
  if (name == "start") return t3(f(0));
  if (name == "end") return t3(f(1));
  if (name == "point") return native("point", {"t"}, [self](const Args &a, const Node *) { return t3(self->pointAt(num(a["t"], "t"))); });
  if (name == "tangent") return native("tangent", {"t"}, [self](const Args &a, const Node *) { return t3(self->tangentAt(num(a["t"], "t"))); });
  if (name == "points")
    return native("points", {"n=16"}, [self](const Args &a, const Node *) {
      double k = std::floor(num(a["n"], "n") + 0.5);
      if (!(k >= 1 && k <= 4096)) throw ScriptError("points(): n deve ser um inteiro de 1 a 4096");
      std::vector<Value> out;
      for (auto &p : self->sample((int)k)) out.push_back(t3(p));
      return list(out);
    });
  if (name == "offset")
    return native("offset", {"x=0", "y=0", "z=0"}, [self](const Args &a, const Node *) {
      V3 d = a["x"].isList() ? vec3c(a["x"], "offset") : V3{num(a["x"], "offset"), num(a["y"], "offset"), num(a["z"], "offset")};
      CurveFn g = self->f;
      return Value(std::make_shared<Curve>([g, d](double u) { return add(g(u), d); }, double(self->us.size()) / SAMPLES, self->label));
    });
  if (name == "reverse")
    return native("reverse", {}, [self](const Args &, const Node *) {
      CurveFn g = self->f;
      return Value(std::make_shared<Curve>([g](double u) { return g(1 - u); }, double(self->us.size()) / SAMPLES, self->label));
    });
  throw ScriptError("curva não tem o atributo '" + name + "'", 0, "atributos: length, start, end, point(t), tangent(t), points(n), offset(x, y, z), reverse()");
}

static std::pair<CurveFn, int> catmullRom(const std::vector<V3> &pts, bool closed) {
  std::vector<V3> P = pts;
  if (closed) P.push_back(pts[0]);
  int n = (int)P.size() - 1;
  auto get = [pts, P, n, closed](int i) -> V3 {
    if (closed) { int m = (int)pts.size(); return pts[((i % m) + m) % m]; }
    if (i < 0) return add(P[0], sub(P[0], P[1]));
    if (i > n) return add(P[n], sub(P[n], P[n - 1]));
    return P[i];
  };
  CurveFn f = [get, n](double u) -> V3 {
    double x = std::min((double)n, std::max(0.0, u * n));
    int i = std::min(n - 1, (int)std::floor(x));
    double t = x - i;
    V3 p0 = get(i - 1), p1 = get(i), p2 = get(i + 1), p3 = get(i + 2);
    if (t == 0) return p1;
    if (t == 1) return p2;
    auto tj = [](double ti, const V3 &a, const V3 &b) { return ti + std::max(1e-6, std::sqrt(len(sub(b, a)))); };
    double t0 = 0, t1 = tj(t0, p0, p1), t2 = tj(t1, p1, p2), t3 = tj(t2, p2, p3);
    double tt = t1 + (t2 - t1) * t;
    auto lerp = [tt](const V3 &a, const V3 &b, double ta, double tb) { return add(mulS(a, (tb - tt) / (tb - ta)), mulS(b, (tt - ta) / (tb - ta))); };
    V3 A1 = lerp(p0, p1, t0, t1), A2 = lerp(p1, p2, t1, t2), A3 = lerp(p2, p3, t2, t3);
    V3 B1 = lerp(A1, A2, t0, t2), B2 = lerp(A2, A3, t1, t3);
    return lerp(B1, B2, t1, t2);
  };
  return {f, n};
}

static CurveFn bezierFn(std::vector<V3> c) {
  return [c](double u) {
    std::vector<V3> q = c;
    while (q.size() > 1) {
      std::vector<V3> r;
      for (size_t i = 0; i + 1 < q.size(); i++) r.push_back(add(mulS(q[i], 1 - u), mulS(q[i + 1], u)));
      q = r;
    }
    return q[0];
  };
}

static std::shared_ptr<Curve> asCurve(const Value &v, const std::string &what) {
  if (auto c = v.as<Curve>()) return c;
  if (v.isList() && v.size() >= 2 && std::all_of(v.list()->items.begin(), v.list()->items.end(), [](const Value &p) { return p.isList(); })) {
    std::vector<V3> pts;
    for (size_t i = 0; i < v.size(); i++) pts.push_back(vec3c(v[i], what + " ponto " + std::to_string(i)));
    auto [f, n] = catmullRom(pts, false);
    return std::make_shared<Curve>(f, n, "spline");
  }
  throw ScriptError(what + " espera uma curva (spline/bezier) ou uma lista de pontos, recebeu " + typeName(v));
}

static M3 frame(const V3 &T, const V3 &up = {0, 1, 0}) {
  V3 S = cross(up, T);
  if (len(S) < 1e-6) S = cross({0, 0, 1}, T);
  S = normV(S);
  V3 N = cross(T, S);
  return {S[0], N[0], T[0], S[1], N[1], T[1], S[2], N[2], T[2]};
}

static std::array<double, 2> rangeOf(const Value &v, const std::string &what) {
  if (v.isList()) {
    if (v.size() != 2) throw ScriptError(what + " deve ser um número ou (início, fim)");
    return {num(v[0], what), num(v[1], what)};
  }
  double x = num(v, what);
  return {x, x};
}

static Value sweep(const Args &a) {
  auto c = asCurve(a["path"], "sweep()");
  if (!(c->length > 1e-9)) throw ScriptError("sweep(): a curva tem comprimento zero");
  const Value &prof = a["profile"];
  std::string kind;
  double r0 = 0, r1 = 0, w = 0, h = 0;
  Value pts;
  bool two = prof.isList() && prof.size() == 2 && prof[0].isNum() && prof[1].isNum();
  if (prof.isNum() || two) {
    kind = "round";
    auto r = rangeOf(prof, "sweep() profile");
    r0 = r[0]; r1 = r[1];
    if (!(r0 > 0 && r1 > 0)) throw ScriptError("sweep(): o raio deve ser maior que zero");
  } else if (prof.isList() && prof.size() > 0 && prof[0].isStr() && prof[0].s() == "box") {
    kind = "box";
    w = num(prof.size() > 1 ? prof[1] : Value(), "largura");
    h = num(prof.size() > 2 ? prof[2] : (prof.size() > 1 ? prof[1] : Value()), "altura");
    if (!(w > 0 && h > 0)) throw ScriptError("sweep(): (\"box\", largura, altura) deve ter tamanhos positivos");
  } else if (prof.isList() && prof.size() >= 3 && std::all_of(prof.list()->items.begin(), prof.list()->items.end(), [](const Value &p) { return p.isList() && p.size() == 2; })) {
    kind = "poly";
    std::vector<Value> out;
    for (auto &p : prof.list()->items) out.push_back(list({num(p[0], "perfil"), num(p[1], "perfil")}));
    pts = list(out);
  } else {
    throw ScriptError("sweep(): profile inválido (" + typeName(prof) + ")", 0,
                      "use um raio (0.05), (raio_início, raio_fim), (\"box\", largura, altura) ou uma lista de pontos (x, y)");
  }
  double sz = kind == "round" ? std::min(r0, r1) : kind == "box" ? std::min(w, h) : 0.05;
  double n = a["steps"].isNone() ? std::floor(c->length / std::max(sz * 1.5, c->length / 48) + 0.5) : std::floor(num(a["steps"], "steps") + 0.5);
  int N = (int)std::max(1.0, std::min(256.0, n));
  auto P = c->sample(N);
  std::vector<ShapeP> segs;
  for (int i = 0; i < N; i++) {
    V3 A = P[i], B = P[i + 1];
    if (kind == "round") {
      segs.push_back(r0 == r1 ? segmentShape(A, B, r0) : roundCone(A, B, r0 + ((r1 - r0) * i) / N, r0 + ((r1 - r0) * (i + 1)) / N));
      continue;
    }
    double d = len(sub(B, A));
    if (d < 1e-9) continue;
    V3 T = normV(sub(B, A));
    double ext = d + sz * 0.5;
    ShapeP piece = kind == "box" ? mkShape("box", {{"size", nums({w, h, ext})}, {"r", 0}})
                                 : mkShape("extrude", {{"pts", pts}, {"h", ext}, {"axis", "z"}, {"r", 0}});
    segs.push_back(translate(mkShape("rotate", {{"m", nums9(frame(T))}}, {piece}), mulS(add(A, B), 0.5)));
  }
  return unionOf(segs, num(a["smooth"], "smooth"));
}

static Value along(const ShapeP &s, const Args &a) {
  auto c = asCurve(a["path"], "along()");
  double s0 = num(a["start"], "start"), s1 = num(a["end"], "end");
  if (!(s0 >= 0 && s1 <= 1 && s0 <= s1)) throw ScriptError("along(): start e end devem ficar entre 0 e 1, com start <= end");
  double span = (s1 - s0) * c->length;
  double n;
  if (!a["count"].isNone()) n = std::floor(num(a["count"], "count") + 0.5);
  else if (!a["spacing"].isNone()) {
    double sp = num(a["spacing"], "spacing");
    if (!(sp > 0)) throw ScriptError("along(): spacing deve ser maior que zero");
    n = std::floor(span / sp + 1e-9) + 1;
  } else throw ScriptError("along(): diga count= (quantas cópias) ou spacing= (distância em metros)");
  if (!(n >= 1 && n <= 4096)) throw ScriptError("along(): de 1 a 4096 cópias");
  std::string orient = jsLower(str(a["orient"]));
  if (orient != "yaw" && orient != "full" && orient != "none") throw ScriptError("along(): orient deve ser \"yaw\", \"full\" ou \"none\"");
  bool closed = len(sub(c->f(0), c->f(1))) < 1e-6;
  std::vector<ShapeP> copies;
  for (int i = 0; i < n; i++) {
    double k = n == 1 ? 0.5 : closed && s0 == 0 && s1 == 1 ? i / n : i / (n - 1);
    double t = s0 + (s1 - s0) * k;
    V3 p = c->pointAt(t), T = c->tangentAt(t);
    ShapeP q = s;
    if (orient == "yaw" && std::hypot(T[0], T[2]) > 1e-6) {
      double ang = std::atan2(-T[2], T[0]);
      double C = std::cos(ang), S = std::sin(ang);
      q = mkShape("rotate", {{"m", nums({C, 0, S, 0, 1, 0, -S, 0, C})}}, {q});
    } else if (orient == "full") {
      M3 F = frame(T);
      V3 Sd{F[0], F[3], F[6]}, Nd{F[1], F[4], F[7]};
      q = mkShape("rotate", {{"m", nums({T[0], Nd[0], -Sd[0], T[1], Nd[1], -Sd[1], T[2], Nd[2], -Sd[2]})}}, {q});
    }
    copies.push_back(translate(q, p));
  }
  return unionOf(copies);
}

Builtins curveBuiltins(Interp &) {
  addMethod("along", {"path", "count=None", "spacing=None", "orient=\"yaw\"", "start=0", "end=1"}, along);
  Builtins b;
  b.emplace_back("spline", native("spline", {"points", "closed=False"}, [](const Args &a, const Node *) {
    const Value &P = a["points"];
    if (!P.isList() || P.size() < 2 || P.size() > 256) throw ScriptError("spline(): points deve ser uma lista de 2 a 256 pontos (x, y, z)");
    std::vector<V3> pts;
    for (size_t i = 0; i < P.size(); i++) pts.push_back(vec3c(P[i], "spline() ponto " + std::to_string(i)));
    bool closed = truthy(a["closed"]);
    if (closed && pts.size() < 3) throw ScriptError("spline(closed=True) precisa de pelo menos 3 pontos");
    auto [f, n] = catmullRom(pts, closed);
    return Value(std::make_shared<Curve>(f, n, closed ? "spline fechada" : "spline"));
  }));
  b.emplace_back("bezier", native("bezier", {"*points"}, [](const Args &a, const Node *) {
    auto &pts = a["points"].list()->items;
    std::vector<Value> raw = pts.size() == 1 && pts[0].isList() && pts[0].size() > 0 && pts[0][0].isList() ? pts[0].list()->items : pts;
    if (raw.size() < 2 || raw.size() > 16) throw ScriptError("bezier(): de 2 a 16 pontos de controle (início, controles..., fim)");
    std::vector<V3> c;
    for (size_t i = 0; i < raw.size(); i++) c.push_back(vec3c(raw[i], "bezier() ponto " + std::to_string(i)));
    return Value(std::make_shared<Curve>(bezierFn(c), std::max(1, (int)c.size() - 2), "bézier"));
  }));
  b.emplace_back("sweep", native("sweep", {"profile", "path", "steps=None", "smooth=0"}, [](const Args &a, const Node *) { return sweep(a); }));
  return b;
}

}  // namespace tdi
