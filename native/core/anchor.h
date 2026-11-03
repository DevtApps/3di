#pragma once
#include "shape.h"

namespace tdi {

struct Anchor {
  V3 p, n;
};
const std::vector<std::pair<std::string, Anchor>> &declaredAnchors(const ShapeP &s);
Anchor resolveAnchor(const Value &x, const Value &name, const std::string &what);
void registerAnchorMethods();
M3 inv3(const M3 &m);

}  // namespace tdi
