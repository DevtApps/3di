// Compila a árvore de formas numa função GLSL de distância e material (port de compiler.js).
#pragma once
#include <optional>
#include <string>
#include <vector>

#include "shape.h"

namespace tdi {

extern const int INSTANCE_THRESHOLD;
extern const std::string GLSL_LIB;

// material acumulado ao descer pela cena (o objeto `mat` do JS)
struct TexFrame {
  M3 m;
  V3 t;
};
struct MatCtx {
  Props p;                          // color, rough, metal, glow, tex, facet, coat (só os definidos)
  std::optional<TexFrame> texFrame;  // walkScene
  std::optional<std::string> texP;   // Gen (GLSL)
};

struct Occ {
  ShapeP s;
  M3 m;
  V3 t;
  double ds;
  MatCtx mat;
};

struct Split {
  std::vector<Occ> instances;
  std::vector<ShapeP> residual;
  std::vector<std::vector<Occ>> groups;
};
Split splitScene(const std::vector<ShapeP> &shapes, bool instancing = false);
bool isHeavy(const Shape &s);
ShapeP wrapNode(const ShapeP &s, const M3 &m, const V3 &t, double ds, const MatCtx &mat);
double facetCode(const Value &fc, const Value &coat);
std::string glslF(const Value &x);  // f() do compilador

struct SceneData {
  std::vector<float> inst, bvh, code;
  int instCount = 0, nodeCount = 0, codeCount = 0;
  int instW = 11, bvhW = 2, codeW = 5;
  bool any() const { return !inst.empty() || !code.empty(); }
};

struct Compiled {
  std::string glsl;
  SceneData data;
  bool hasData = false;
  BBox bbox;
  bool hasPlane = false, animated = false;
  int leaves = 0, codeLeaves = 0, instances = 0;
  std::vector<int> codeGroups;
  std::vector<Part> parts;
};
Compiled compileScene(const Scene &scene);

}  // namespace tdi
