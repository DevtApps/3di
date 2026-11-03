// Câmera orbital: arrastar com o botão esquerdo gira, o direito (ou shift) desloca o alvo, a roda aproxima.
#pragma once
#include <array>

struct Camera {
  std::array<float, 3> target{0, 0.8f, 0};
  float yaw = 0.7f, pitch = 0.35f, dist = 7.f;

  std::array<float, 3> eye() const;
  void orbit(float dx, float dy);  // em pixels
  void pan(float dx, float dy, float viewH);
  void zoom(float wheel);
  void lookAt(const std::array<float, 3> &pos, const std::array<float, 3> &look);  // como camera(pos=, look=)
};
