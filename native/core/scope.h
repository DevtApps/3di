#pragma once
#include "shape.h"

namespace tdi {

struct FillOpts {
  std::string fit = "stretch", align = "bottom";
  Value round = 0.0, bevel = 0.0;
  int index = -1;
};

struct ScopeBox : Object {
  V3 min, max;
  ScopeBox(V3 mn, V3 mx);
  static std::shared_ptr<ScopeBox> of(const Value &s, const std::string &what);
  V3 size() const;
  V3 center() const;
  std::string describe() const override;
  std::shared_ptr<ScopeBox> with(int i, double lo, double hi) const;
  Value split(const Value &axis, Value sizes) const;
  Value tile(const Value &axis, const Value &size, const Value &f, const Value &gap) const;
  Value inset(const Args &a) const;
  Value fill(const Value &x, const FillOpts &o) const;
  Value fit(const ShapeP &s, const std::string &fit, const std::string &align) const;
  Value attr(const std::string &name) override;
  Json plain() const override;
};

}  // namespace tdi
