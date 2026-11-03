#include "kit.h"

namespace tdi::kit {

const std::vector<std::string> STYLE_NAMES = {"lowpoly", "stylized", "realistic"};

Style resolveStyle(const Value &name, const std::string &what) {
  static const std::vector<std::pair<std::string, std::string>> ALIASES = {
      {"low_poly", "lowpoly"}, {"low-poly", "lowpoly"}, {"poly", "lowpoly"}, {"cartoon", "stylized"},
      {"estilizado", "stylized"}, {"realista", "realistic"}, {"real", "realistic"}};
  std::string key = jsLower(str(name));
  for (auto &[a, k] : ALIASES)
    if (a == key) { key = k; break; }
  if (key == "lowpoly") return {key, 0.5, 0.05, 0, 0.85, 0, true, false, false};
  if (key == "stylized") return {key, 1, 0.1, 0, 0.7, 1, false, true, false};
  if (key == "realistic") return {key, 1.8, 0.18, 0.35, 0.6, 1, false, true, true};
  std::vector<std::string> names = STYLE_NAMES;
  for (auto &[a, k] : ALIASES) names.push_back(a);
  std::string h = didYouMean(str(name), names);
  throw ScriptError(what + ": estilo desconhecido '" + str(name) + "'", 0, h.empty() ? "use lowpoly, stylized, realistic" : h);
}

}  // namespace tdi::kit
