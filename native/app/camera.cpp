#include "camera.h"

#include <algorithm>
#include <cmath>

std::array<float, 3> Camera::eye() const {
  float c = std::cos(pitch);
  return {target[0] + dist * c * std::sin(yaw), target[1] + dist * std::sin(pitch), target[2] + dist * c * std::cos(yaw)};
}

void Camera::orbit(float dx, float dy) {
  yaw -= dx * 0.008f;
  pitch = std::clamp(pitch + dy * 0.008f, -1.5f, 1.5f);
}

void Camera::pan(float dx, float dy, float viewH) {
  // desloca no plano da tela, proporcional à distância (o ponto sob o mouse acompanha o cursor)
  float k = dist * 1.1f / std::max(viewH, 1.f);
  float right[3] = {std::cos(yaw), 0, -std::sin(yaw)};
  float up[3] = {-std::sin(pitch) * std::sin(yaw), std::cos(pitch), -std::sin(pitch) * std::cos(yaw)};
  for (int i = 0; i < 3; i++) target[i] += (-dx * right[i] + dy * up[i]) * k;
}

void Camera::zoom(float wheel) { dist = std::clamp(dist * std::pow(0.88f, wheel), 0.2f, 500.f); }

void Camera::lookAt(const std::array<float, 3> &pos, const std::array<float, 3> &look) {
  target = look;
  float d[3] = {pos[0] - look[0], pos[1] - look[1], pos[2] - look[2]};
  dist = std::max(std::sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]), 0.2f);
  pitch = std::asin(std::clamp(d[1] / dist, -1.f, 1.f));
  yaw = std::atan2(d[0], d[2]);
}
