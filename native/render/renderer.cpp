#include "renderer.h"

#include <SDL3/SDL_timer.h>

#include <cmath>
#include <stdexcept>

namespace tdi {

#include "frag.inc"

using namespace gl;

static const char *VERT = R"(#version 330 core
void main() {
  vec2 p = vec2(gl_VertexID == 1 ? 3.0 : -1.0, gl_VertexID == 2 ? 3.0 : -1.0);
  gl_Position = vec4(p, 0.0, 1.0);
}
)";

static const char *UNIFORMS[] = {"uRes", "uRo", "uTa", "uFov", "uFog", "uMaxDist", "uSun", "uSunCol", "uSky", "uTime", "uZero", "uShadowSteps", "uLight", "uRimCol"};

std::string fragSource(const std::string &sceneGlsl) {
  // o shader é o mesmo do WebGL2; no desktop só muda a versão (330 aceita precision e o resto)
  std::string head = FRAG_HEAD;
  const std::string es = "#version 300 es";
  if (head.compare(0, es.size(), es) == 0) head = "#version 330 core" + head.substr(es.size());
  return head + sceneGlsl + FRAG_TAIL;
}

bool Renderer::init(std::string &err) {
  (void)err;
  glGenVertexArrays(1, &vao_);
  GenTextures(3, tex_);
  return true;
}

void Renderer::setScene(const std::string &glsl, const SceneData &data, bool hasData) {
  if (pending_) { glDeleteProgram(pending_); pending_ = 0; }
  if (glsl == glsl_ && program_) {
    if (hasData) uploadData(data);
    return;
  }
  std::string fs = fragSource(glsl);
  pendingStart_ = SDL_GetTicksNS();  // sem a extensão, a compilação acontece (bloqueando) aqui dentro
  pending_ = programStart(VERT, fs.c_str());
  pendingGlsl_ = glsl;
  pendingData_ = data;
  pendingHasData_ = hasData;
}

bool Renderer::poll(std::string &err, double &compileMs) {
  if (!pending_ || !programReady(pending_)) return false;
  GLuint p = pending_;
  pending_ = 0;
  if (!programFinish(p, err)) {
    glDeleteProgram(p);
    return false;
  }
  compileMs = (SDL_GetTicksNS() - pendingStart_) * 1e-6;
  use(p);
  glsl_ = pendingGlsl_;
  if (pendingHasData_) uploadData(pendingData_);
  pendingData_ = {};
  return true;
}

void Renderer::use(GLuint prog) {
  if (program_) glDeleteProgram(program_);
  program_ = prog;
  for (int i = 0; i < 14; i++) loc_[i] = glGetUniformLocation(prog, UNIFORMS[i]);
}

// registros consecutivos distribuídos nas duas dimensões (packDataTexture do JS)
static void putTexture(GLuint prog, int unit, GLuint tex, const std::vector<float> &values, int recordWidth, int maxSize, const char *name) {
  size_t texels = values.size() / 4;
  if ((double)texels > (double)maxSize * maxSize)
    throw std::runtime_error("Os dados da cena excedem a capacidade de textura desta GPU (" + std::to_string(maxSize) + " × " + std::to_string(maxSize) + ")");
  int width = std::min(maxSize, std::max(recordWidth, (int)std::ceil(std::sqrt((double)texels))));
  int height = std::max(1, (int)std::ceil((double)texels / width));
  std::vector<float> pixels((size_t)width * height * 4, 0.f);
  std::copy(values.begin(), values.end(), pixels.begin());
  ActiveTexture(GL_TEXTURE0 + unit);
  BindTexture(GL_TEXTURE_2D, tex);
  TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  TexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, width, height, 0, GL_RGBA, GL_FLOAT, pixels.data());
  if (GetError() != GL_NO_ERROR) throw std::runtime_error("Não foi possível carregar a cena na GPU");
  glUniform1i(glGetUniformLocation(prog, name), unit);
}

void Renderer::uploadData(const SceneData &d) {
  GLint max = 4096;
  GetIntegerv(GL_MAX_TEXTURE_SIZE, &max);
  glUseProgram(program_);
  if (!d.inst.empty()) {
    putTexture(program_, 0, tex_[0], d.inst, d.instW, max, "uInst");
    putTexture(program_, 1, tex_[1], d.bvh, d.bvhW, max, "uBvh");
  }
  if (!d.code.empty()) putTexture(program_, 2, tex_[2], d.code, d.codeW, max, "uCode");
}

void Renderer::render(const View &v, int w, int h) {
  if (!program_) return;
  Viewport(0, 0, w, h);
  glUseProgram(program_);
  glUniform2f(loc_[0], (float)w, (float)h);
  glUniform3f(loc_[1], (float)v.eye[0], (float)v.eye[1], (float)v.eye[2]);
  glUniform3f(loc_[2], (float)v.target[0], (float)v.target[1], (float)v.target[2]);
  glUniform1f(loc_[3], (float)v.fov);
  glUniform1f(loc_[4], (float)v.fog);
  glUniform1f(loc_[5], (float)v.maxDist);
  glUniform3f(loc_[6], (float)v.sun[0], (float)v.sun[1], (float)v.sun[2]);
  glUniform3f(loc_[7], (float)v.sunColor[0], (float)v.sunColor[1], (float)v.sunColor[2]);
  glUniform3f(loc_[8], (float)v.sky[0], (float)v.sky[1], (float)v.sky[2]);
  glUniform1f(loc_[9], (float)v.time);
  glUniform1i(loc_[10], 0);
  glUniform1i(loc_[11], v.shadowSteps);
  glUniform3f(loc_[12], (float)v.light.rim, (float)v.light.fill, (float)v.light.ao);
  glUniform3f(loc_[13], (float)v.light.rimColor[0], (float)v.light.rimColor[1], (float)v.light.rimColor[2]);
  glBindVertexArray(vao_);
  DrawArrays(GL_TRIANGLES, 0, 3);
}

void Renderer::renderToTarget(const View &v, int w, int h) {
  if (!fbo_) { glGenFramebuffers(1, &fbo_); GenTextures(1, &fboTex_); }
  if (w != fboW_ || h != fboH_) {
    BindTexture(GL_TEXTURE_2D, fboTex_);
    TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    TexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo_);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, fboTex_, 0);
    fboW_ = w;
    fboH_ = h;
  }
  glBindFramebuffer(GL_FRAMEBUFFER, fbo_);
  render(v, w, h);
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

void Renderer::blitToScreen(int sw, int sh) {
  if (!fbo_) return;
  glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo_);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
  glBlitFramebuffer(0, 0, fboW_, fboH_, 0, 0, sw, sh, GL_COLOR_BUFFER_BIT, fboW_ == sw && fboH_ == sh ? GL_NEAREST : GL_LINEAR);
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

std::vector<unsigned char> Renderer::renderOffscreen(const View &v, int w, int h) {
  GLuint fbo, tex;
  glGenFramebuffers(1, &fbo);
  GenTextures(1, &tex);
  BindTexture(GL_TEXTURE_2D, tex);
  TexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
  glBindFramebuffer(GL_FRAMEBUFFER, fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
  render(v, w, h);
  std::vector<unsigned char> px((size_t)w * h * 4), out(px.size());
  ReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, px.data());
  for (int y = 0; y < h; y++) std::copy_n(px.begin() + (size_t)(h - 1 - y) * w * 4, (size_t)w * 4, out.begin() + (size_t)y * w * 4);
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glDeleteFramebuffers(1, &fbo);
  DeleteTextures(1, &tex);
  return out;
}

}  // namespace tdi
