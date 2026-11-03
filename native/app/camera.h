// Câmera orbital e enquadramento (port da câmera de src/main.js).
#pragma once
#include <string>
#include <vector>

#include "shape.h"

namespace tdi {

struct Camera {
  V3 target{0, 0.5, 0};
  double yaw = 0.6, pitch = 0.35, dist = 4, fov = 45;

  V3 eye() const;
  void orbit(float dx, float dy);  // em pixels
  void pan(float dx, float dy, float viewH);
  void zoom(float wheel);
};

double radiusOf(const BBox &b);
// caixa da cena para enquadrar: com chão, ignora o que fica abaixo dele
BBox sceneBox(const BBox &b, bool hasPlane);
// enquadra a caixa b; preset: front, back, right, left, top, perspective (ou "" para manter o ângulo)
void frameBox(Camera &cam, const BBox &b, const std::string &preset = "perspective");
// camera(pos=, look=, fov=) do script
void applyScriptCamera(Camera &cam, const V3 &pos, const V3 *look, double fov, const BBox &sceneBB);

struct ViewCam {
  std::string label, axes;
  double yaw, pitch, dist, fov;
  V3 target;
};
std::vector<ViewCam> viewCameras(const BBox &b);  // frente, lado, topo, perspectiva

}  // namespace tdi
