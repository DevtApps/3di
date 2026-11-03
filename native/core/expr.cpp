#include "expr.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <map>

namespace tdi {

static double layoutTime = 0;

static double jsFn(const std::string &op, const std::vector<double> &a) {
  if (op == "sin") return std::sin(a[0]);
  if (op == "cos") return std::cos(a[0]);
  if (op == "tan") return std::tan(a[0]);
  if (op == "abs") return std::fabs(a[0]);
  if (op == "sqrt") return std::sqrt(a[0]);
  if (op == "floor") return std::floor(a[0]);
  if (op == "exp") return std::exp(a[0]);
  if (op == "min") { double m = INFINITY; for (double x : a) m = std::isnan(x) || std::isnan(m) ? NAN : std::min(m, x); return m; }
  if (op == "max") { double m = -INFINITY; for (double x : a) m = std::isnan(x) || std::isnan(m) ? NAN : std::max(m, x); return m; }
  if (op == "log") return std::log(a[0]);
  if (op == "ceil") return std::ceil(a[0]);
  if (op == "sign") return a[0] > 0 ? 1 : a[0] < 0 ? -1 : a[0];
  if (op == "atan2") return std::atan2(a[0], a[1]);
  if (op == "hypot") { double s = 0; for (double x : a) s += x * x; return std::sqrt(s); }
  if (op == "step") return a[1] < a[0] ? 0 : 1;
  if (op == "fract") return a[0] - std::floor(a[0]);
  if (op == "clamp") return std::min(a[2], std::max(a[1], a[0]));
  if (op == "lerp") return a[0] + (a[1] - a[0]) * a[2];
  if (op == "smoothstep") {
    double t = std::min(1.0, std::max(0.0, (a[2] - a[0]) / (a[1] - a[0])));
    return t * t * (3 - 2 * t);
  }
  throw ScriptError("função desconhecida " + op);
}

const std::vector<std::string> EXPR_FUNCS = {"sin", "cos", "tan", "abs", "sqrt", "floor", "exp", "min", "max", "log", "ceil",
                                             "sign", "atan2", "hypot", "step", "fract", "clamp", "lerp", "smoothstep"};

static ExprP mkE(std::string op, std::vector<Value> args) {
  auto e = std::make_shared<Expr>();
  e->op = std::move(op);
  e->args = std::move(args);
  return e;
}
const ExprP TIME = mkE("time", {});
const ExprP POS_X = mkE("var", {"x"}), POS_Y = mkE("var", {"y"}), POS_Z = mkE("var", {"z"});

std::string glslNum(double x) {
  char buf[64];
  std::snprintf(buf, sizeof buf, "%.6f", x);
  std::string s = jsNum(std::strtod(buf, nullptr));
  if (s == "-0") s = "0";
  return s.find_first_of(".e") == std::string::npos ? s + ".0" : s;
}

std::string glslOf(const Value &x) { return x.isExpr() ? x.expr()->glsl() : glslNum(x.n()); }

std::string Expr::glsl() const {
  if (op == "var") return "ip." + args[0].s();
  std::vector<std::string> a;
  for (auto &x : args) a.push_back(glslOf(x));
  if (op == "time") return "uTime";
  if (op == "hypot") {
    std::string s;
    for (size_t i = 0; i < a.size(); i++) s += (i ? " + " : "") + a[i] + " * " + a[i];
    return "sqrt(" + s + ")";
  }
  if (op == "+" || op == "-" || op == "*" || op == "/") return "(" + a[0] + " " + op + " " + a[1] + ")";
  if (op == "%") return "mod(" + a[0] + ", " + a[1] + ")";
  if (op == "**") return "pow(" + a[0] + ", " + a[1] + ")";
  if (op == "neg") return "(-" + a[0] + ")";
  std::string fn = op == "lerp" ? "mix" : op == "atan2" ? "atan" : op;
  std::string s;
  for (size_t i = 0; i < a.size(); i++) s += (i ? ", " : "") + a[i];
  return fn + "(" + s + ")";
}

double Expr::eval(double t, const std::array<double, 3> *env) const {
  if (op == "var") {
    if (!env) return NAN;
    char c = args[0].s()[0];
    return (*env)[c - 'x'];
  }
  if (op == "time") return t;
  std::vector<double> a;
  for (auto &x : args) a.push_back(x.isExpr() ? x.expr()->eval(t, env) : x.isNum() ? x.n() : x.isBool() ? double(x.b()) : NAN);
  if (op == "+") return a[0] + a[1];
  if (op == "-") return a[0] - a[1];
  if (op == "*") return a[0] * a[1];
  if (op == "/") return a[0] / a[1];
  if (op == "%") return a[0] - a[1] * std::floor(a[0] / a[1]);
  if (op == "**") return std::pow(a[0], a[1]);
  if (op == "neg") return -a[0];
  return jsFn(op, a);
}

std::string Expr::describe() const {
  std::string g = glsl(), out;
  for (size_t i = 0; i < g.size();) {
    if (g.compare(i, 5, "uTime") == 0) { out += "time"; i += 5; }
    else if (g.compare(i, 3, "ip.") == 0) i += 3;
    else out += g[i++];
  }
  return "<expressão: " + out + ">";
}

bool Expr::usesTime() const {
  if (op == "time") return true;
  return std::any_of(args.begin(), args.end(), [](const Value &x) { return x.isExpr() && x.expr()->usesTime(); });
}
bool Expr::usesPosition() const {
  if (op == "var") return true;
  return std::any_of(args.begin(), args.end(), [](const Value &x) { return x.isExpr() && x.expr()->usesPosition(); });
}

std::function<double(double, double, double, double)> Expr::compile() const {
  auto self = std::make_shared<Expr>(*this);
  return [self](double x, double y, double z, double t) {
    std::array<double, 3> env{x, y, z};
    return self->eval(t, &env);
  };
}

Json Expr::plain() const {
  Json o = Json::object();
  o.set("$", "Expr");
  Json a = Json::array();
  for (auto &x : args) a.push(tdi::plain(x));
  o.set("args", std::move(a));
  o.set("op", op);
  return o;
}

double val0(const Value &x) { return x.isExpr() ? x.expr()->eval(layoutTime) : x.isNum() ? x.n() : NAN; }

double withTime(double t, const std::function<void()> &fn) {
  double prev = layoutTime;
  layoutTime = t;
  try { fn(); } catch (...) { layoutTime = prev; throw; }
  layoutTime = prev;
  return t;
}

Value sym(const std::string &op, std::vector<Value> args) {
  bool any = std::any_of(args.begin(), args.end(), [](const Value &x) { return x.isExpr(); });
  if (!any) {
    if (op == "neg") return -(args[0].isNum() ? args[0].n() : NAN);
    return mkE(op, args)->eval(0);
  }
  auto isN = [](const Value &v, double k) { return v.isNum() && v.n() == k; };
  if (op == "+" && isN(args[1], 0)) return args[0];
  if (op == "+" && isN(args[0], 0)) return args[1];
  if (op == "*" && isN(args[0], 1)) return args[1];
  if (op == "*" && isN(args[1], 1)) return args[0];
  return mkE(op, std::move(args));
}

}  // namespace tdi
