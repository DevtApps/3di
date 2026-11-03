// Fases 5 e 6: GLSL byte a byte igual ao do JS, mesmos dados da BVH (hash), mesmo resumo da
// compilação e amostras de sdf(p) na CPU iguais às do JS.
#include <doctest/doctest.h>

#include <algorithm>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <sstream>

#include "compiler.h"
#include "interp.h"
#include "sdf.h"
#include "sha256.h"

namespace fs = std::filesystem;
using namespace tdi;

static std::string slurp(const fs::path &p) {
  std::ifstream f(p, std::ios::binary);
  std::stringstream ss;
  ss << f.rdbuf();
  return ss.str();
}
static std::string sha16(const std::string &s) { return sha256hex(s.data(), s.size()).substr(0, 16); }
static Json f32(const std::vector<float> &v) {
  Json o = Json::object();
  o.set("f32", (double)v.size());
  std::vector<int32_t> q;
  for (float x : v) q.push_back((int32_t)std::floor((double)x * 1e5 + 0.5));
  o.set("q", sha256hex(q.data(), q.size() * sizeof(int32_t)).substr(0, 16));
  return o;
}

TEST_CASE("GLSL, dados e sdf iguais ao golden") {
  fs::path root = TDI_ROOT;
  int glslOk = 0, n = 0;
  for (auto &ent : fs::directory_iterator(root / "examples")) {
    if (ent.path().extension() != ".3di") continue;
    std::string name = ent.path().stem().string();
    Json want = Json::parse(slurp(root / "tests/golden" / (name + ".json")));
    RunResult r = runScript(slurp(ent.path()));
    if (!r.ok) continue;
    n++;
    Compiled out = compileScene(r.it->scene);
    std::string wantGlsl = slurp(root / "tests/golden" / (name + ".glsl"));
    bool same = out.glsl == wantGlsl;
    if (!same) {
      size_t i = 0;
      while (i < out.glsl.size() && i < wantGlsl.size() && out.glsl[i] == wantGlsl[i]) i++;
      size_t a = i > 80 ? i - 80 : 0;
      FAIL_CHECK(name, ": GLSL difere no byte ", i, "\n  obtido:   ...", out.glsl.substr(a, 160), "\n  esperado: ...", wantGlsl.substr(a, 160));
    } else glslOk++;
    const Json &c = want["compile"];
    CHECK_MESSAGE(out.leaves == (int)c["leaves"].n, name, ": leaves ", out.leaves, " != ", c["leaves"].n);
    CHECK_MESSAGE(out.codeLeaves == (int)c["codeLeaves"].n, name, ": codeLeaves");
    CHECK_MESSAGE(out.instances == (int)c["instances"].n, name, ": instances");
    CHECK_MESSAGE(out.hasPlane == c["hasPlane"].b, name, ": hasPlane");
    CHECK_MESSAGE(out.animated == c["animated"].b, name, ": animated");
    CHECK_MESSAGE(sha16(out.glsl) == c["glslSha"].s, name, ": glslSha");
    Json groups = Json::array();
    for (int g : out.codeGroups) groups.push(g);
    CHECK_MESSAGE(jsonDiff(groups, c["codeGroups"]).empty(), name, ": codeGroups");
    Json bb = Json::object(), mn = Json::array(), mx = Json::array();
    for (int i = 0; i < 3; i++) { mn.push(out.bbox.min[i]); mx.push(out.bbox.max[i]); }
    bb.set("max", mx);
    bb.set("min", mn);
    CHECK_MESSAGE(jsonDiff(bb, c["bbox"], 1e-6).empty(), name, ": bbox ", jsonDiff(bb, c["bbox"], 1e-6));
    // dados: mesmos campos e mesmos bytes
    Json data;
    if (out.hasData) {
      data = Json::object();
      if (!out.data.inst.empty()) {
        data.set("inst", f32(out.data.inst));
        data.set("instCount", out.data.instCount);
        data.set("bvh", f32(out.data.bvh));
        data.set("nodeCount", out.data.nodeCount);
        data.set("instW", out.data.instW);
        data.set("bvhW", out.data.bvhW);
      }
      if (!out.data.code.empty()) {
        data.set("code", f32(out.data.code));
        data.set("codeCount", out.data.codeCount);
        data.set("codeW", out.data.codeW);
      }
    }
    // compara tudo menos o hash exato dos bytes (sha), que depende do último bit de sin/cos
    Json wantData = c["data"];
    for (auto &[k, v] : wantData.o)
      if (v.t == Json::Obj) v.o.erase(std::remove_if(v.o.begin(), v.o.end(), [](auto &p) { return p.first == "sha"; }), v.o.end());
    CHECK_MESSAGE(jsonDiff(data, wantData).empty(), name, ": dados ", jsonDiff(data, wantData));
    // sdf na CPU nas mesmas amostras
    auto fns = buildSceneFns(unionOf(r.it->scene.shapes));
    for (auto &smp : want["sdf"].a) {
      double x = smp.a[0].n, y = smp.a[1].n, z = smp.a[2].n, d = smp.a[3].n;
      double got = fns.dist(x, y, z);
      CHECK_MESSAGE(std::fabs(got - d) <= 1e-6 * std::max(1.0, std::fabs(d)), name, ": sdf(", x, ", ", y, ", ", z, ") = ", got, ", esperado ", d);
    }
  }
  MESSAGE(glslOk, " de ", n, " GLSL iguais");
}
