// Utilitários de cor da linguagem (port de color.js) e o gerador aleatório (lib/rand.js).
#pragma once
#include <array>
#include <cstdint>
#include <functional>

#include "value.h"

namespace tdi {

std::array<double, 3> toSrgb(const Value &v);
std::array<double, 3> hsvToRgb(double h, double s, double v);
std::array<double, 3> rgbToHsv(const std::array<double, 3> &c);
bool isColorLike(const Value &v);

// mulberry32: o mesmo seed gera sempre a mesma cena
struct Rng {
  uint32_t s;
  explicit Rng(double seed = 1);
  double operator()();
};
using RngFn = std::function<double()>;

}  // namespace tdi
