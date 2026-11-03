// Esqueleto de ossos e partes presas a eles (port de rig.js).
#pragma once
#include "interp.h"

namespace tdi {

struct Skeleton;
struct Bone : Object {
  Skeleton *skel;
  std::string name;
  V3 head;
  bool hasTail = false;
  V3 tailSpec{};
  std::shared_ptr<Bone> parent;
  std::vector<Bone *> children;
  std::vector<Value> angles{0.0, 0.0, 0.0}, offset{0.0, 0.0, 0.0};

  V3 tail() const;
  bool animated() const;
  std::string describe() const override;
  Value attr(const std::string &name) override;
  Json plain() const override;
};

struct Skeleton : Object {
  std::string name;
  std::vector<std::shared_ptr<Bone>> bones;
  std::shared_ptr<Bone> find(const std::string &n) const;
  std::string describe() const override;
  ShapeP debugShape(const Value &color, const Value &r);
  Value attr(const std::string &name) override;
};

std::vector<ShapeP> resolveRig(const std::vector<ShapeP> &shapes);
std::vector<std::shared_ptr<Bone>> collectBones(const std::vector<ShapeP> &shapes);

}  // namespace tdi
