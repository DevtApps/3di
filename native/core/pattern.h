#pragma once
#include "shape.h"

namespace tdi {

extern const char *PATTERN_GLSL;
struct PatternP {
  V3 bmin, bc, hf;
  int kind = 1, ax = 1;
  std::array<double, 2> sz;
  double gap = 0, depth = 0, vary = 0;
};
PatternP patternOf(const Props &P);
double patternG(const V3 &p, const PatternP &P);
double patternLip(const PatternP &P);
void registerPatternMethods();

}  // namespace tdi
