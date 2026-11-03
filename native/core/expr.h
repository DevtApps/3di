// Expressões simbólicas (port de expr.js): `time` e as variáveis x, y, z de implicit() viram GLSL;
// para layout e caixas vale o valor em t = 0 (val0).
#pragma once
#include <array>
#include <functional>
#include <string>
#include <vector>

#include "value.h"

namespace tdi {

struct Expr {
  std::string op;
  std::vector<Value> args;  // números, Expr, ou o nome da variável em op == "var"

  std::string glsl() const;
  double eval(double t, const std::array<double, 3> *env = nullptr) const;
  std::string describe() const;
  bool usesTime() const;
  bool usesPosition() const;
  std::function<double(double, double, double, double)> compile() const;
  Json plain() const;
};

extern const std::vector<std::string> EXPR_FUNCS;
extern const ExprP TIME;
extern const ExprP POS_X, POS_Y, POS_Z;

double val0(const Value &x);           // valor em t = layoutTime
Value sym(const std::string &op, std::vector<Value> args);
std::string glslOf(const Value &x);
std::string glslNum(double x);         // fmt() do expr.js
double withTime(double t, const std::function<void()> &fn);  // roda fn com layoutTime = t

}  // namespace tdi
