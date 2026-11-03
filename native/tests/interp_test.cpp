// Fase 3: rodar cada exemplo deve dar a mesma árvore de formas, os mesmos prints e o mesmo erro do JS.
#include <doctest/doctest.h>

#include <filesystem>
#include <fstream>
#include <map>
#include <sstream>

#include "interp.h"

namespace fs = std::filesystem;
using namespace tdi;

static std::string slurp(const fs::path &p) {
  std::ifstream f(p, std::ios::binary);
  std::stringstream ss;
  ss << f.rdbuf();
  return ss.str();
}

// mesma tabela de nós do dag() do golden.mjs
static Json dag(const std::vector<ShapeP> &shapes) {
  std::map<const Shape *, int> ids;
  Json nodes = Json::array();
  std::function<int(const ShapeP &)> id = [&](const ShapeP &s) -> int {
    auto it = ids.find(s.get());
    if (it != ids.end()) return it->second;
    Json kids = Json::array();
    for (auto &c : s->children) kids.push(id(c));
    Props props = s->props;
    if (props.has("bone") && !props["bone"].isNone()) {
      Value name;
      try { name = props["bone"].obj()->attr("name"); } catch (...) {}
      props.set("bone", name.isStr() ? name : Value("<osso>"));
    }
    int n = (int)nodes.a.size();
    ids[s.get()] = n;
    Json node = Json::array();
    node.push(s->kind);
    node.push(props.plain());
    node.push(std::move(kids));
    nodes.push(std::move(node));
    return n;
  };
  Json roots = Json::array();
  for (auto &s : shapes) roots.push(id(s));
  Json o = Json::object();
  o.set("roots", std::move(roots));
  o.set("nodes", std::move(nodes));
  return o;
}

// exemplos que dependem de módulos ainda não portados (rig, escopos, curvas, bibliotecas)
static bool pending(const std::string &src) {
  for (const char *w : {"tree(", "person(", "vehicle(", "grass(", "plant(", "skeleton(", "space(", "spline(", "bezier(", "sweep(",
                        ".along(", ".anchor(", ".attach(", ".planks(", ".shingles(", ".masonry("})
    if (src.find(w) != std::string::npos) return true;
  return false;
}

TEST_CASE("formas iguais ao golden") {
  fs::path root = TDI_ROOT;
  int ok = 0, skipped = 0;
  for (auto &ent : fs::directory_iterator(root / "examples")) {
    if (ent.path().extension() != ".3di") continue;
    std::string name = ent.path().filename().string(), src = slurp(ent.path());
    if (pending(src)) { skipped++; continue; }
    Json want = Json::parse(slurp(root / "tests/golden" / (ent.path().stem().string() + ".json")));
    RunResult r = runScript(src);
    Json logs = Json::array();
    for (auto &l : r.logs) logs.push(l);
    CHECK_MESSAGE(jsonDiff(logs, want["logs"]).empty(), name, ": prints diferem");
    if (!r.ok) {
      CHECK_MESSAGE(want.get("error"), name, ": ", r.error.str());
      if (want.get("error")) CHECK_MESSAGE(r.error.str() == want["error"].s, name, ": erro ", r.error.str());
      continue;
    }
    REQUIRE_MESSAGE(!want.get("error"), name, ": o JS deu erro ", want["error"].s);
    std::string d = jsonDiff(dag(r.it->scene.shapes), want["shapes"], 1e-6);
    CHECK_MESSAGE(d.empty(), name, ": ", d);
    if (d.empty()) ok++;
  }
  MESSAGE(ok, " exemplos iguais, ", skipped, " pendentes de módulos");
}
