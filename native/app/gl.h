// Carregador mínimo de OpenGL 3.3 core via SDL_GL_GetProcAddress (sem glad): só as funções usadas.
#pragma once
#include <SDL3/SDL_opengl.h>
#include <string>

#define TDI_GL_FUNCS(X)                                                                              \
  X(PFNGLCREATESHADERPROC, glCreateShader) X(PFNGLSHADERSOURCEPROC, glShaderSource)                  \
  X(PFNGLCOMPILESHADERPROC, glCompileShader) X(PFNGLGETSHADERIVPROC, glGetShaderiv)                  \
  X(PFNGLGETSHADERINFOLOGPROC, glGetShaderInfoLog) X(PFNGLDELETESHADERPROC, glDeleteShader)          \
  X(PFNGLCREATEPROGRAMPROC, glCreateProgram) X(PFNGLATTACHSHADERPROC, glAttachShader)                \
  X(PFNGLLINKPROGRAMPROC, glLinkProgram) X(PFNGLGETPROGRAMIVPROC, glGetProgramiv)                    \
  X(PFNGLGETPROGRAMINFOLOGPROC, glGetProgramInfoLog) X(PFNGLDELETEPROGRAMPROC, glDeleteProgram)      \
  X(PFNGLUSEPROGRAMPROC, glUseProgram) X(PFNGLGETUNIFORMLOCATIONPROC, glGetUniformLocation)          \
  X(PFNGLUNIFORM1FPROC, glUniform1f) X(PFNGLUNIFORM2FPROC, glUniform2f)                              \
  X(PFNGLUNIFORM3FPROC, glUniform3f) X(PFNGLGENVERTEXARRAYSPROC, glGenVertexArrays)                  \
  X(PFNGLBINDVERTEXARRAYPROC, glBindVertexArray) X(PFNGLDELETEVERTEXARRAYSPROC, glDeleteVertexArrays)

namespace gl {
#define TDI_DECL(T, n) extern T n;
TDI_GL_FUNCS(TDI_DECL)
#undef TDI_DECL
// funções do GL 1.1 também vêm do carregador (no Windows a opengl32 não as dá pelo wglGetProcAddress)
extern void(APIENTRY *Viewport)(GLint, GLint, GLsizei, GLsizei);
extern void(APIENTRY *ClearColor)(GLfloat, GLfloat, GLfloat, GLfloat);
extern void(APIENTRY *Clear)(GLbitfield);
extern void(APIENTRY *DrawArrays)(GLenum, GLint, GLsizei);
extern const GLubyte *(APIENTRY *GetString)(GLenum);
extern void(APIENTRY *ReadPixels)(GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void *);

bool load(std::string &err);
// compila vertex + fragment; em erro devolve 0 e o log do driver em err
GLuint program(const char *vs, const char *fs, std::string &err);
}  // namespace gl
