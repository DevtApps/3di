// Fase 2: o AST do parser em C++ deve ser igual ao do parser.js (tests/golden/<exemplo>.json) e os
// erros de sintaxe devem ter a mesma mensagem (tests/golden/_parse-errors.json).
#include <doctest/doctest.h>

#include <filesystem>
#include <fstream>
#include <sstream>

#include "error.h"
#include "parser.h"

namespace fs = std::filesystem;
using namespace tdi;

static std::string slurp(const fs::path &p) {
  std::ifstream f(p, std::ios::binary);
  std::stringstream ss;
  ss << f.rdbuf();
  return ss.str();
}

TEST_CASE("AST igual ao golden em todos os exemplos") {
  fs::path root = TDI_ROOT;
  int n = 0;
  for (auto &ent : fs::directory_iterator(root / "examples")) {
    if (ent.path().extension() != ".3di") continue;
    fs::path g = root / "tests/golden" / (ent.path().stem().string() + ".json");
    REQUIRE_MESSAGE(fs::exists(g), "sem golden: ", g.string(), " (rode npm run golden)");
    Json want = Json::parse(slurp(g));
    Json got;
    try {
      got = toJson(parse(slurp(ent.path())));
    } catch (const ScriptError &e) {
      FAIL_CHECK(ent.path().filename().string(), ": ", e.str());
      continue;
    }
    std::string d = jsonDiff(got, want["ast"]);
    CHECK_MESSAGE(d.empty(), ent.path().filename().string(), ": ", d);
    n++;
  }
  CHECK(n >= 30);
}

TEST_CASE("erros de sintaxe iguais aos do JS") {
  Json cases = Json::parse(slurp(fs::path(TDI_ROOT) / "tests/golden/_parse-errors.json"));
  for (auto &c : cases.a) {
    std::string got = "(sem erro)";
    try {
      parse(c["src"].s);
    } catch (const ScriptError &e) {
      got = e.str();
    }
    CHECK_MESSAGE(got == (c.get("error") ? c["error"].s : "(sem erro)"), "fonte: ", c["src"].s);
  }
}
