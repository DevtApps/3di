// Exportação da cena para glTF binário (.glb) (port de export.js e gltf.js).
#pragma once
#include <cstdint>
#include <functional>
#include <string>
#include <vector>

#include "json.h"
#include "shape.h"

namespace tdi {

struct PartReport {
  std::string name, kind, method, status, reason;
  bool empty = false, textured = false;
  int triangles = 0;
  double maxError = 0, meanError = 0, faceError = 0, cell = 0, size = 0, volumeRatio = -1;
};

struct ExportStats {
  int parts = 0, vertices = 0, triangles = 0, bones = 0;
  bool animated = false;
  int paletteColors = 0;
  size_t bytes = 0;
  double ms = 0;
  std::vector<PartReport> partReports;
  std::vector<std::string> warnings;
};

struct ExportOpts {
  int res = 128;
  std::string method = "auto";  // "auto" ou "sample"
  int threads = 0;               // 0: um por núcleo
  bool palette = false;          // cores numa textura de paleta compartilhada (estilo KayKit)
  bool merge = false;            // uma malha por forma mostrada
  std::function<void(int, int)> onProgress;
};

struct ExportResult {
  std::vector<uint8_t> glb;
  Json gltf;  // o JSON do glTF (para testes e relatórios)
  ExportStats stats;
};
ExportResult exportGLB(const Scene &scene, const ExportOpts &opts = {});

}  // namespace tdi
