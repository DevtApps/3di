#include "gl.h"

#include <SDL3/SDL_video.h>
#include <vector>

namespace gl {
#define TDI_DEF(T, n) T n = nullptr;
TDI_GL_FUNCS(TDI_DEF)
#undef TDI_DEF
void(APIENTRY *Viewport)(GLint, GLint, GLsizei, GLsizei) = nullptr;
void(APIENTRY *ClearColor)(GLfloat, GLfloat, GLfloat, GLfloat) = nullptr;
void(APIENTRY *Clear)(GLbitfield) = nullptr;
void(APIENTRY *DrawArrays)(GLenum, GLint, GLsizei) = nullptr;
const GLubyte *(APIENTRY *GetString)(GLenum) = nullptr;
void(APIENTRY *ReadPixels)(GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void *) = nullptr;

template <class T> static bool get(T &fn, const char *name, std::string &err) {
  fn = reinterpret_cast<T>(SDL_GL_GetProcAddress(name));
  if (!fn) err += std::string(name) + " ";
  return fn != nullptr;
}

bool load(std::string &err) {
  bool ok = true;
#define TDI_LOAD(T, n) ok &= get(n, #n, err);
  TDI_GL_FUNCS(TDI_LOAD)
#undef TDI_LOAD
  ok &= get(Viewport, "glViewport", err);
  ok &= get(ClearColor, "glClearColor", err);
  ok &= get(Clear, "glClear", err);
  ok &= get(DrawArrays, "glDrawArrays", err);
  ok &= get(GetString, "glGetString", err);
  ok &= get(ReadPixels, "glReadPixels", err);
  if (!ok) err = "funções OpenGL ausentes: " + err;
  return ok;
}

static GLuint shader(GLenum type, const char *src, std::string &err) {
  GLuint s = glCreateShader(type);
  glShaderSource(s, 1, &src, nullptr);
  glCompileShader(s);
  GLint ok = 0, len = 0;
  glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
  if (!ok) {
    glGetShaderiv(s, GL_INFO_LOG_LENGTH, &len);
    std::vector<char> log(len > 1 ? len : 1);
    glGetShaderInfoLog(s, (GLsizei)log.size(), nullptr, log.data());
    err = log.data();
    glDeleteShader(s);
    return 0;
  }
  return s;
}

GLuint program(const char *vs, const char *fs, std::string &err) {
  GLuint v = shader(GL_VERTEX_SHADER, vs, err);
  if (!v) return 0;
  GLuint f = shader(GL_FRAGMENT_SHADER, fs, err);
  if (!f) { glDeleteShader(v); return 0; }
  GLuint p = glCreateProgram();
  glAttachShader(p, v);
  glAttachShader(p, f);
  glLinkProgram(p);
  glDeleteShader(v);
  glDeleteShader(f);
  GLint ok = 0, len = 0;
  glGetProgramiv(p, GL_LINK_STATUS, &ok);
  if (!ok) {
    glGetProgramiv(p, GL_INFO_LOG_LENGTH, &len);
    std::vector<char> log(len > 1 ? len : 1);
    glGetProgramInfoLog(p, (GLsizei)log.size(), nullptr, log.data());
    err = log.data();
    glDeleteProgram(p);
    return 0;
  }
  return p;
}
}  // namespace gl
