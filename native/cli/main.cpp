// 3di-cli: valida e compila um .3di sem janela (port de scripts/check.mjs).
//   3di-cli check arquivo.3di [--glsl]   mostra primitivas, peças e medidas (e o GLSL)
//   3di-cli export arquivo.3di [saida.glb] [--res 128] [--sample] [--palette] [--merge]   glTF binário (como scripts/export.mjs)
//   3di-cli dump arquivo.3di N           primeiros N floats dos dados de instância (depuração)
#include <cstdio>
#include <cstring>
#include <fstream>
#include <sstream>

#include "compiler.h"
#include "export.h"
#include "interp.h"
#include "rig.h"

using namespace tdi;

static std::string slurp(const char *p) {
  std::ifstream f(p, std::ios::binary);
  if (!f) { std::fprintf(stderr, "não foi possível abrir %s\n", p); std::exit(2); }
  std::stringstream ss;
  ss << f.rdbuf();
  return ss.str();
}
static std::string v(const V3 &a) { return "(" + fmtNum(a[0]) + ", " + fmtNum(a[1]) + ", " + fmtNum(a[2]) + ")"; }

int main(int argc, char **argv) {
  if (argc < 3) {
    std::fprintf(stderr, "uso: 3di-cli check arquivo.3di [--glsl] | 3di-cli dump arquivo.3di N\n");
    return 2;
  }
  std::string cmd = argv[1];
  RunResult r = runScript(slurp(argv[2]));
  for (auto &l : r.logs) std::printf("print: %s\n", l.c_str());
  if (!r.ok) { std::fprintf(stderr, "ERRO %s\n", r.error.str().c_str()); return 1; }
  if (cmd == "export") {
    std::string outPath, file = argv[2];
    int res = 128;
    std::string method = "auto";
    bool palette = false, merge = false;
    for (int i = 3; i < argc; i++) {
      if (!std::strcmp(argv[i], "--res") && i + 1 < argc) res = std::atoi(argv[++i]);
      else if (!std::strcmp(argv[i], "--sample")) method = "sample";
      else if (!std::strcmp(argv[i], "--palette")) palette = true;
      else if (!std::strcmp(argv[i], "--merge")) merge = true;
      else outPath = argv[i];
    }
    if (outPath.empty()) outPath = (file.size() > 4 && file.substr(file.size() - 4) == ".3di" ? file.substr(0, file.size() - 4) : file) + ".glb";
    ExportResult ex;
    try {
      ExportOpts o;
      o.res = res;
      o.method = method;
      o.palette = palette;
      o.merge = merge;
      o.onProgress = [](int i, int n) { std::fprintf(stderr, "\rmalha %d/%d", i + 1, n); };
      ex = exportGLB(r.it->scene, o);
    } catch (const std::exception &e) {
      std::fprintf(stderr, "\nERRO %s\n", e.what());
      return 1;
    }
    std::fprintf(stderr, "\n");
    std::ofstream f(outPath, std::ios::binary);
    f.write(reinterpret_cast<const char *>(ex.glb.data()), (std::streamsize)ex.glb.size());
    auto &st = ex.stats;
    std::printf("ok: %s (%zu KB) · %d partes · %d vértices · %d triângulos%s%s · %.1f s\n", outPath.c_str(), st.bytes / 1024, st.parts, st.vertices, st.triangles,
                st.bones ? (" · " + std::to_string(st.bones) + " ossos").c_str() : "", st.animated ? " · animado" : "", st.ms / 1000);
    if (st.paletteColors) std::printf("paleta: %d cores numa textura\n", st.paletteColors);
    for (auto &w : st.warnings) std::printf("aviso: %s\n", w.c_str());
    return 0;
  }
  Compiled out;
  try {
    out = compileScene(r.it->scene);
  } catch (const ScriptError &e) {
    std::fprintf(stderr, "ERRO %s\n", e.str().c_str());
    return 1;
  }
  if (cmd == "dump") {
    int n = argc > 3 ? std::atoi(argv[3]) : 44;
    for (int i = 0; i < n && i < (int)out.data.inst.size(); i++) std::printf("%.8g%s", out.data.inst[i], i % 4 == 3 ? "\n" : " ");
    return 0;
  }
  int groups = 0;
  for (int g : out.codeGroups) groups += g;
  std::string copias = out.codeGroups.empty() ? "" : "; " + std::to_string(groups) + " cópias de " + std::to_string(out.codeGroups.size()) + " peça(s) repetida(s) compilam uma vez cada";
  std::string extra = out.instances || !copias.empty()
                          ? " (" + std::to_string(out.instances) + " como dados na BVH, " + std::to_string(out.codeLeaves) + " como código" + copias + ")"
                          : "";
  std::printf("ok: %d primitivas%s, %zu formas mostradas%s\n", out.leaves, extra.c_str(), r.it->scene.shapes.size(), out.hasPlane ? " + chão" : "");
  std::printf("cena: de %s até %s\n", v(out.bbox.min).c_str(), v(out.bbox.max).c_str());
  for (auto &p : out.parts) std::printf("  %s: tamanho %s, de %s até %s\n", p.name.c_str(), v(size(p.bbox)).c_str(), v(p.bbox.min).c_str(), v(p.bbox.max).c_str());
  auto bones = collectBones(r.it->scene.shapes);
  if (!bones.empty()) {
    bool anim = false;
    for (auto &b : bones) anim |= b->animated();
    std::printf("esqueleto %s: %zu ossos%s\n", bones[0]->skel->name.c_str(), bones.size(), anim ? " (animados)" : "");
    for (auto &b : bones) std::printf("  %s: cabeça %s%s\n", b->name.c_str(), v(b->head).c_str(), b->parent ? (", pai " + b->parent->name).c_str() : "");
  }
  for (int i = 3; i < argc; i++)
    if (!std::strcmp(argv[i], "--glsl")) std::printf("%s", out.glsl.c_str());
  return 0;
}
