// Poliedros convexos de faces planas (port de hull.js).
#pragma once
#include <vector>

#include "shape.h"

namespace tdi {

struct Hull {
  std::vector<V3> pts;
  std::vector<std::array<double, 4>> planes;
  std::vector<std::vector<int>> faces;
};
Hull convexHull(const std::vector<V3> &input, const std::string &what = "hull()");
std::vector<V3> ringPoints(double r, double y, int sides, double phase = 0);
std::vector<V3> lowSphere(double r, int sides);
std::vector<V3> chamferBoxPoints(const V3 &h, double c);
ShapeP hullShape(const std::vector<V3> &points, const std::string &what = "hull()");
Hull hullOf(const Props &p);  // de volta a partir das props de uma forma 'hull'

}  // namespace tdi
