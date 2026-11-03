// Fase 9: exportação GLB igual à do JS em estrutura (partes, malhas, texturas, esqueleto, animação) e
// com triângulos dentro de 2% no total e 5% por peça (a simplificação desempata custos quase iguais pelo
// último bit do float, que difere do JS porque sin/cos da libm não são os do V8).
#include <doctest/doctest.h>

#include <cmath>
#include <filesystem>
#include <fstream>
#include <sstream>

#include "export.h"
#include "interp.h"

namespace fs = std::filesystem;
using namespace tdi;

static std::string slurp(const fs::path &p) {
  std::ifstream f(p, std::ios::binary);
  std::stringstream ss;
  ss << f.rdbuf();
  return ss.str();
}
static int count(const Json &j, const char *k) { return j.get(k) ? (int)j[k].a.size() : 0; }
static bool near(double a, double b, double tol = 0.02) { return std::fabs(a - b) <= std::max(2.0, tol * std::fabs(b)); }

TEST_CASE("exportação GLB igual à do JS") {
  fs::path root = TDI_ROOT;
  Json cases = Json::parse(slurp(root / "tests/golden/_export.json"));
  for (auto &want : cases.a) {
    std::string name = want["name"].s;
    RunResult r = runScript(slurp(root / "examples" / (name + ".3di")));
    REQUIRE_MESSAGE(r.ok, name, ": ", r.error.str());
    ExportOpts o;
    o.res = 40;
    o.palette = want["palette"].b;
    ExportResult ex = exportGLB(r.it->scene, o);
    auto &st = ex.stats;
    CHECK_MESSAGE(st.parts == (int)want["parts"].n, name, ": partes");
    CHECK_MESSAGE(st.paletteColors == (int)want["paletteColors"].n, name, ": cores da paleta");
    CHECK_MESSAGE(st.bones == (int)want["bones"].n, name, ": ossos");
    CHECK_MESSAGE(st.animated == want["animated"].b, name, ": animado");
    CHECK_MESSAGE(near(st.triangles, want["triangles"].n), name, ": triângulos ", st.triangles, " != ", want["triangles"].n);
    CHECK_MESSAGE(near(st.vertices, want["vertices"].n), name, ": vértices ", st.vertices, " != ", want["vertices"].n);
    CHECK_MESSAGE(st.warnings.size() == want["warnings"].a.size(), name, ": avisos");
    auto &reps = want["partReports"].a;
    REQUIRE(st.partReports.size() == reps.size());
    for (size_t i = 0; i < reps.size(); i++) {
      auto &a = st.partReports[i];
      auto &b = reps[i];
      CHECK_MESSAGE(a.name == b["name"].s, name, ": nome da parte ", i);
      CHECK_MESSAGE(a.empty == b["empty"].b, name, ": parte vazia ", a.name);
      CHECK_MESSAGE(a.textured == b["textured"].b, name, ": textura em ", a.name);
      if (!b["method"].isNull()) CHECK_MESSAGE(a.method == b["method"].s, name, ": método de ", a.name, " ", a.method);
      CHECK_MESSAGE(near(a.triangles, b["triangles"].n, 0.05), name, ": triângulos de ", a.name, " ", a.triangles, " != ", b["triangles"].n);
    }
    const Json &g = want["gltf"];
    CHECK_MESSAGE(count(ex.gltf, "nodes") == (int)g["nodes"].n, name, ": nós");
    CHECK_MESSAGE(count(ex.gltf, "meshes") == (int)g["meshes"].n, name, ": malhas");
    CHECK_MESSAGE(count(ex.gltf, "materials") == (int)g["materials"].n, name, ": materiais");
    CHECK_MESSAGE(count(ex.gltf, "images") == (int)g["images"].n, name, ": imagens");
    CHECK_MESSAGE(count(ex.gltf, "skins") == (int)g["skins"].n, name, ": skins");
    int ch = ex.gltf.get("animations") ? (int)ex.gltf["animations"].a[0]["channels"].a.size() : 0;
    CHECK_MESSAGE(ch == (int)g["channels"].n, name, ": canais de animação");
    // GLB bem formado: cabeçalho e tamanho
    REQUIRE(ex.glb.size() > 20);
    uint32_t magic = ex.glb[0] | ex.glb[1] << 8 | ex.glb[2] << 16 | (uint32_t)ex.glb[3] << 24;
    uint32_t total = ex.glb[8] | ex.glb[9] << 8 | ex.glb[10] << 16 | (uint32_t)ex.glb[11] << 24;
    CHECK(magic == 0x46546c67);
    CHECK(total == ex.glb.size());
  }
}
