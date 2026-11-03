// Avaliador do SDF na CPU (port de sdf.js): espelho do GLSL gerado, usado na exportação de malhas.
#pragma once
#include <functional>
#include <optional>

#include "shape.h"

namespace tdi {

using DistFn = std::function<double(double, double, double)>;

// resultado com material (o objeto { d, c, rough, metal, glow, c2, tx, tp, facet, coat } do JS)
struct MatR {
  double d = 1e10;
  V3 c{0.6, 0.6, 0.62};
  double rough = 0.6, metal = 0, glow = 0, coat = 0;
  bool hasTex = false;
  V3 c2{0, 0, 0};
  std::array<double, 4> tx{0, 0, 0, 0};
  bool hasTp = false;
  V3 tp{0, 0, 0};
  Value facet;
};
using MatFn = std::function<MatR(double, double, double, const V3 *tp)>;

DistFn buildDist(const ShapeP &s, double t = 0);
MatFn buildMat(const ShapeP &s, double t = 0);
V3 surfaceColor(const MatR &r, const V3 *n);
double fbm(double x, double y, double z);
double texHeight(const V3 &p, const std::array<double, 4> &tx, const V3 *n);

struct SceneFns {
  DistFn dist;
  std::function<MatR(double, double, double)> mat;
};
SceneFns buildSceneFns(const ShapeP &shape);

}  // namespace tdi
