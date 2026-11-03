#include "camera.h"

#include <algorithm>
#include <cmath>

namespace tdi {

V3 Camera::eye() const {
  double cp = std::cos(pitch);
  return {target[0] + dist * cp * std::sin(yaw), target[1] + dist * std::sin(pitch), target[2] + dist * cp * std::cos(yaw)};
}

void Camera::orbit(float dx, float dy) {
  yaw -= dx * 0.008;
  pitch = std::clamp(pitch + dy * 0.008, -1.55, 1.55);
}

void Camera::pan(float dx, float dy, float viewH) {
  double k = dist * 1.1 / std::max(viewH, 1.f);
  V3 right{std::cos(yaw), 0, -std::sin(yaw)};
  V3 up{-std::sin(pitch) * std::sin(yaw), std::cos(pitch), -std::sin(pitch) * std::cos(yaw)};
  for (int i = 0; i < 3; i++) target[i] += (-dx * right[i] + dy * up[i]) * k;
}

void Camera::zoom(float wheel) { dist = std::clamp(dist * std::pow(0.88, wheel), 0.02, 5000.0); }

double radiusOf(const BBox &b) {
  return std::max(0.05, 0.5 * std::sqrt(std::pow(b.max[0] - b.min[0], 2) + std::pow(b.max[1] - b.min[1], 2) + std::pow(b.max[2] - b.min[2], 2)));
}

BBox sceneBox(const BBox &b, bool hasPlane) {
  if (hasPlane && b.max[1] > 0.05) return {{b.min[0], std::max(0.0, b.min[1]), b.min[2]}, b.max};
  return b;
}

void frameBox(Camera &cam, const BBox &b, const std::string &preset) {
  struct P { const char *name; double yaw, pitch; };
  static const P PRESETS[] = {{"front", 0, 0.1}, {"back", M_PI, 0.1}, {"right", M_PI / 2, 0.1}, {"left", -M_PI / 2, 0.1}, {"top", 0, 1.5}, {"perspective", 0.6, 0.38}};
  cam.target = center(b);
  cam.dist = (radiusOf(b) / std::sin((cam.fov * M_PI) / 360)) * 1.05;
  for (auto &p : PRESETS)
    if (preset == p.name) { cam.yaw = p.yaw; cam.pitch = p.pitch; }
}

void applyScriptCamera(Camera &cam, const V3 &pos, const V3 *look, double fov, const BBox &b) {
  V3 l = look ? *look : center(b);
  V3 d{pos[0] - l[0], pos[1] - l[1], pos[2] - l[2]};
  cam.target = l;
  cam.dist = std::max(0.01, std::sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]));
  cam.yaw = std::atan2(d[0], d[2]);
  cam.pitch = std::asin(std::clamp(d[1] / cam.dist, -1.0, 1.0));
  cam.fov = fov;
}

std::vector<ViewCam> viewCameras(const BBox &b) {
  const double AXIS_FOV = 30;
  V3 c = center(b), s;
  for (int i = 0; i < 3; i++) s[i] = std::max(0.05, b.max[i] - b.min[i]);
  auto fit = [&](double w, double h, double depth) { return depth / 2 + (std::max(w, h) / 2) * 1.15 / std::tan((AXIS_FOV * M_PI) / 360); };
  return {
      {"FRENTE (de +z)", "→ +x   ↑ +y", 0, 0, fit(s[0], s[1], s[2]), AXIS_FOV, c},
      {"LADO (de +x)", "→ −z   ↑ +y", M_PI / 2, 0, fit(s[2], s[1], s[0]), AXIS_FOV, c},
      {"TOPO (de +y)", "→ +x   ↓ +z", 0, M_PI / 2, fit(s[0], s[2], s[1]), AXIS_FOV, c},
      {"PERSPECTIVA", "", 0.6, 0.38, (radiusOf(b) / std::sin((45 * M_PI) / 360)) * 1.05, 45, c},
  };
}

}  // namespace tdi
