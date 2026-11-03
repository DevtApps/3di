// SDF -> malha (dual contouring) e simplificação por erro quádrico (port de mesh.js e simplify.js).
#pragma once
#include <cstdint>
#include <functional>
#include <limits>
#include <optional>
#include <vector>

#include "sdf.h"

namespace tdi {

struct Mesh {
  std::vector<float> positions, normals, colors, uv;
  std::vector<uint32_t> indices;
  int instances = 0;
};

struct MeshOpts {
  double res = 128;
  std::optional<V3> cell;
  std::function<V3(double, double, double)> colorAt;
  bool simplify = true;
  double tolerance = 0;  // 0: padrão (15% da célula)
  double maxEdge = std::numeric_limits<double>::infinity();
};
std::optional<Mesh> meshSDF(const DistFn &dist, const BBox &bbox, const MeshOpts &opt);

struct Simplified {
  std::vector<float> positions;
  std::vector<uint32_t> indices;
};
Simplified simplifyMesh(const std::vector<float> &positions, const std::vector<uint32_t> &indices, double tolerance,
                        double maxEdge = std::numeric_limits<double>::infinity(), const DistFn *surfaceDist = nullptr,
                        double checkEdge = std::numeric_limits<double>::infinity());

// malha direta das primitivas (port de nativemesh.js); nullopt se a árvore tem algo sem tesselação direta
std::optional<Mesh> nativeMesh(const ShapeP &shape, int seg = 32);

}  // namespace tdi
