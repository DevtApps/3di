// Renderizador OpenGL (port de renderer.js): um triângulo de tela cheia + raymarching do SDF gerado.
#pragma once
#include <array>
#include <string>
#include <vector>

#include "compiler.h"
#include "gl.h"

namespace tdi {

struct Light {
  double rim = 0, fill = 0, ao = 1;
  V3 rimColor{1, 1, 1};
};

struct View {
  V3 eye, target;
  double fov = 45, fog = 0, maxDist = 100;
  V3 sun{0.6, 1, 0.4}, sunColor{1, 0.95, 0.88}, sky{0.3, 0.5, 0.82};
  Light light;
  double time = 0;
  int shadowSteps = 80;
};

std::string fragSource(const std::string &sceneGlsl);

class Renderer {
 public:
  bool init(std::string &err);
  // começa a compilar o shader de uma cena (a anterior continua na tela até a nova ficar pronta)
  void setScene(const std::string &glsl, const SceneData &data, bool hasData);
  // avança a compilação pendente; devolve true quando trocou de cena. err recebe erros de compilação
  bool poll(std::string &err, double &compileMs);
  bool ready() const { return program_ != 0; }
  bool compiling() const { return pending_ != 0; }
  void render(const View &v, int w, int h);
  // desenha a cena num framebuffer próprio (w x h) e copia para a tela (sw x sh), esticando
  void renderToTarget(const View &v, int w, int h);
  void blitToScreen(int sw, int sh);
  // desenha num framebuffer w x h e devolve os pixels RGBA (linhas de cima para baixo)
  std::vector<unsigned char> renderOffscreen(const View &v, int w, int h);
  std::string glslLoaded() const { return glsl_; }

 private:
  void use(GLuint prog);
  void uploadData(const SceneData &d);
  GLuint vao_ = 0, program_ = 0, pending_ = 0;
  std::string glsl_, pendingGlsl_;
  SceneData pendingData_;
  bool pendingHasData_ = false;
  unsigned long long pendingStart_ = 0;
  GLuint tex_[3] = {0, 0, 0};
  GLint loc_[16];
  GLuint fbo_ = 0, fboTex_ = 0;
  int fboW_ = 0, fboH_ = 0;
};

}  // namespace tdi
