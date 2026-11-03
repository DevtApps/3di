// Perfis 2D para extrude, polygon, star, wedge e lathe (port de profile.js).
#pragma once
#include <array>
#include <string>
#include <vector>

#include "value.h"

namespace tdi {

using P2 = std::array<double, 2>;
std::vector<P2> parsePoints(const Value &v, const std::string &what, int min = 3, int max = 128);
std::vector<P2> regularPolygon(int sides, double r);
std::vector<P2> starPoints(int n, double r, double inner);
std::vector<P2> smoothOpen(const std::vector<P2> &pts, int n);
std::vector<P2> lathePolygon(const std::vector<P2> &profile);
struct Bounds2 { double minX, maxX, minY, maxY; };
Bounds2 boundsOf(const std::vector<P2> &pts);
double polygonSDF(const std::vector<P2> &pts, double px, double py);
std::string polygonGlsl(const std::string &name, const std::vector<P2> &pts);
double extrudeDist(double d2, double hz, double half, double r);
Value pointsValue(const std::vector<P2> &pts);
std::vector<P2> pointsOf(const Value &v);

}  // namespace tdi
