#include "color.h"

#include <algorithm>
#include <cmath>

#include "shape.h"

namespace tdi {

static double linearToSrgb(double c) { return c <= 0.0031308 ? 12.92 * c : 1.055 * std::pow(c, 1 / 2.4) - 0.055; }

std::array<double, 3> toSrgb(const Value &v) {
  auto c = parseColor(v);
  for (auto &x : c) x = std::min(1.0, std::max(0.0, linearToSrgb(x)));
  return c;
}

std::array<double, 3> hsvToRgb(double h, double s, double v) {
  double hh = std::fmod(std::fmod(h, 360) + 360, 360) / 60;
  int i = (int)std::floor(hh);
  double f = hh - i;
  double p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f));
  std::array<std::array<double, 3>, 6> tab = {{{v, t, p}, {q, v, p}, {p, v, t}, {p, q, v}, {t, p, v}, {v, p, q}}};
  return tab[((i % 6) + 6) % 6];
}

std::array<double, 3> rgbToHsv(const std::array<double, 3> &c) {
  double r = c[0], g = c[1], b = c[2];
  double mx = std::max({r, g, b}), mn = std::min({r, g, b}), d = mx - mn;
  double h = 0;
  if (d > 1e-9) {
    if (mx == r) h = std::fmod((g - b) / d, 6);
    else if (mx == g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h *= 60;
    if (h < 0) h += 360;
  }
  return {h, mx <= 0 ? 0 : d / mx, mx};
}

bool isColorLike(const Value &v) {
  if (v.isStr()) return true;
  if (!v.isList() || v.size() != 3) return false;
  for (auto &x : v.list()->items)
    if (!x.isNum()) return false;
  return true;
}

// seed >>> 0 do JS: ToUint32
static uint32_t toUint32(double x) {
  if (!std::isfinite(x)) return 0;
  double t = std::trunc(x);
  double m = std::fmod(t, 4294967296.0);
  if (m < 0) m += 4294967296.0;
  return (uint32_t)m;
}

Rng::Rng(double seed) : s(toUint32(seed)) {}

double Rng::operator()() {
  s = s + 0x6d2b79f5u;
  uint32_t t = s;
  t = (t ^ (t >> 15)) * (t | 1u);
  t ^= t + (t ^ (t >> 7)) * (t | 61u);
  return double(t ^ (t >> 14)) / 4294967296.0;
}

}  // namespace tdi
