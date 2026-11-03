// 3DI nativo, fase 1 (docs/plano-cpp-sdl3.md): janela SDL3 + OpenGL 3.3 core, um shader SDF fixo de
// teste no lugar do mapAll gerado, câmera orbital e painel ImGui. O compilador .3di entra na fase 6.
// Uso: 3di [--frames N] [--shot arquivo.bmp]
//   --frames: desenha N quadros, imprime o tempo médio e sai (teste de fumaça)
//   --shot: grava o último quadro em BMP
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>
#include <imgui.h>
#include <imgui_impl_opengl3.h>
#include <imgui_impl_sdl3.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include "camera.h"
#include "gl.h"

using namespace gl;

static const char *VS = R"(#version 330 core
out vec2 vUv;
void main() {
  vec2 p = vec2(gl_VertexID == 1 ? 3.0 : -1.0, gl_VertexID == 2 ? 3.0 : -1.0);
  vUv = p;
  gl_Position = vec4(p, 0.0, 1.0);
}
)";

// cena de teste no mesmo formato do GLSL gerado: map devolve (distância, material)
static const char *FS = R"(#version 330 core
in vec2 vUv;
out vec4 frag;
uniform vec2 uRes;
uniform vec3 uEye, uTarget;
uniform float uTime;

float sdBox(vec3 p, vec3 b) { vec3 q = abs(p) - b; return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0); }
vec2 mU(vec2 a, vec2 b) { return a.x < b.x ? a : b; }
vec2 mapAll(vec3 p) {
  vec2 m = vec2(p.y, 0.0);
  m = mU(m, vec2(length(p - vec3(0.0, 1.0 + 0.15 * sin(uTime), 0.0)) - 0.8, 1.0));
  m = mU(m, vec2(sdBox(p - vec3(-2.0, 0.5, 0.5), vec3(0.5)) - 0.05, 2.0));
  vec3 q = p - vec3(2.0, 0.6, -0.4);
  m = mU(m, vec2(length(vec2(length(q.xz) - 0.6, q.y)) - 0.2, 3.0));
  return m;
}
vec3 normalAt(vec3 p) {
  vec2 e = vec2(1e-3, 0.0);
  return normalize(vec3(mapAll(p + e.xyy).x - mapAll(p - e.xyy).x, mapAll(p + e.yxy).x - mapAll(p - e.yxy).x,
                        mapAll(p + e.yyx).x - mapAll(p - e.yyx).x));
}
vec3 albedo(float id, vec3 p) {
  if (id < 0.5) return mix(vec3(0.42, 0.5, 0.33), vec3(0.36, 0.44, 0.28), mod(floor(p.x) + floor(p.z), 2.0));
  return id < 1.5 ? vec3(0.8, 0.3, 0.2) : id < 2.5 ? vec3(0.3, 0.45, 0.75) : vec3(0.85, 0.7, 0.3);
}
void main() {
  vec3 fw = normalize(uTarget - uEye), rt = normalize(cross(fw, vec3(0, 1, 0))), up = cross(rt, fw);
  vec2 uv = vUv * vec2(uRes.x / uRes.y, 1.0);
  vec3 rd = normalize(fw * 1.8 + rt * uv.x + up * uv.y), sky = vec3(0.66, 0.73, 0.78);
  float t = 0.0; vec2 m = vec2(1e9, -1.0);
  for (int i = 0; i < 160 && t < 200.0; i++) { m = mapAll(uEye + rd * t); if (m.x < 1e-3 * t) break; t += m.x; }
  vec3 col = sky;
  if (t < 200.0) {
    vec3 p = uEye + rd * t, n = normalAt(p), L = normalize(vec3(0.5, 0.8, 0.4));
    float sh = 1.0, s = 0.02;
    for (int i = 0; i < 48 && s < 20.0; i++) { float h = mapAll(p + n * 2e-3 + L * s).x; sh = min(sh, 10.0 * h / s); if (h < 1e-4) break; s += h; }
    float dif = max(dot(n, L), 0.0) * clamp(sh, 0.0, 1.0);
    col = albedo(m.y, p) * (0.25 + 0.2 * n.y + vec3(1.0, 0.9, 0.78) * dif);
    col = mix(col, sky, 1.0 - exp(-0.004 * t));
  }
  frag = vec4(pow(col, vec3(1.0 / 2.2)), 1.0);
}
)";

static int fail(const char *what, const std::string &msg) {
  std::fprintf(stderr, "ERRO %s: %s\n", what, msg.c_str());
  SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, "3DI", (std::string(what) + ": " + msg).c_str(), nullptr);
  return 1;
}

// lê o back buffer (de baixo para cima no GL) e grava BMP
static void save(const char *path, int w, int h) {
  SDL_Surface *s = SDL_CreateSurface(w, h, SDL_PIXELFORMAT_ABGR8888);
  if (!s) return;
  ReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, s->pixels);
  SDL_FlipSurface(s, SDL_FLIP_VERTICAL);
  if (!SDL_SaveBMP(s, path)) std::fprintf(stderr, "ERRO --shot: %s\n", SDL_GetError());
  SDL_DestroySurface(s);
}

int main(int argc, char **argv) {
  int frames = -1;  // -1: interativo
  const char *shot = nullptr;
  for (int i = 1; i < argc; i++) {
    if (!std::strcmp(argv[i], "--frames") && i + 1 < argc) frames = std::atoi(argv[++i]);
    else if (!std::strcmp(argv[i], "--shot") && i + 1 < argc) shot = argv[++i];
  }

  if (!SDL_Init(SDL_INIT_VIDEO)) return fail("SDL_Init", SDL_GetError());
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
  SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
  SDL_Window *win = SDL_CreateWindow("3DI", 1280, 800, SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY);
  if (!win) return fail("SDL_CreateWindow", SDL_GetError());
  SDL_GLContext ctx = SDL_GL_CreateContext(win);
  if (!ctx) return fail("SDL_GL_CreateContext", SDL_GetError());
  SDL_GL_MakeCurrent(win, ctx);
  SDL_GL_SetSwapInterval(frames < 0 ? 1 : 0);

  std::string err;
  if (!load(err)) return fail("OpenGL", err);
  GLuint prog = program(VS, FS, err);
  if (!prog) return fail("shader", err);
  GLuint vao;
  glGenVertexArrays(1, &vao);
  GLint uRes = glGetUniformLocation(prog, "uRes"), uEye = glGetUniformLocation(prog, "uEye"),
        uTarget = glGetUniformLocation(prog, "uTarget"), uTime = glGetUniformLocation(prog, "uTime");

  IMGUI_CHECKVERSION();
  ImGui::CreateContext();
  ImGui::GetIO().IniFilename = nullptr;
  ImGui::StyleColorsDark();
  ImGui_ImplSDL3_InitForOpenGL(win, ctx);
  ImGui_ImplOpenGL3_Init("#version 330 core");

  Camera cam;
  cam.lookAt({5, 3, 6}, {0, 0.8f, 0});
  const auto *glVer = reinterpret_cast<const char *>(GetString(GL_VERSION));
  const auto *glRen = reinterpret_cast<const char *>(GetString(GL_RENDERER));
  Uint64 t0 = SDL_GetTicksNS(), last = t0;
  double frameMs = 0;
  bool run = true;
  for (int n = 0; run && n != frames; n++) {
    SDL_Event e;
    while (SDL_PollEvent(&e)) {
      ImGui_ImplSDL3_ProcessEvent(&e);
      if (e.type == SDL_EVENT_QUIT || (e.type == SDL_EVENT_KEY_DOWN && e.key.key == SDLK_ESCAPE)) run = false;
      if (ImGui::GetIO().WantCaptureMouse) continue;
      if (e.type == SDL_EVENT_MOUSE_MOTION) {
        bool pan = (e.motion.state & SDL_BUTTON_RMASK) || ((e.motion.state & SDL_BUTTON_LMASK) && (SDL_GetModState() & SDL_KMOD_SHIFT));
        int h;
        SDL_GetWindowSize(win, nullptr, &h);
        if (pan) cam.pan(e.motion.xrel, e.motion.yrel, (float)h);
        else if (e.motion.state & SDL_BUTTON_LMASK) cam.orbit(e.motion.xrel, e.motion.yrel);
      }
      if (e.type == SDL_EVENT_MOUSE_WHEEL) cam.zoom(e.wheel.y);
    }

    int w, h;
    SDL_GetWindowSizeInPixels(win, &w, &h);
    Viewport(0, 0, w, h);
    ClearColor(0, 0, 0, 1);
    Clear(GL_COLOR_BUFFER_BIT);
    glUseProgram(prog);
    auto eye = cam.eye();
    glUniform2f(uRes, (float)w, (float)h);
    glUniform3f(uEye, eye[0], eye[1], eye[2]);
    glUniform3f(uTarget, cam.target[0], cam.target[1], cam.target[2]);
    glUniform1f(uTime, (float)((SDL_GetTicksNS() - t0) * 1e-9));
    glBindVertexArray(vao);
    DrawArrays(GL_TRIANGLES, 0, 3);

    ImGui_ImplOpenGL3_NewFrame();
    ImGui_ImplSDL3_NewFrame();
    ImGui::NewFrame();
    ImGui::SetNextWindowPos({10, 10}, ImGuiCond_FirstUseEver);
    ImGui::Begin("3DI", nullptr, ImGuiWindowFlags_AlwaysAutoResize);
    ImGui::Text("%s", glRen ? glRen : "?");
    ImGui::Text("OpenGL %s", glVer ? glVer : "?");
    ImGui::Text("%.2f ms/quadro (%d x %d)", frameMs, w, h);
    ImGui::Separator();
    ImGui::Text("alvo (%.2f, %.2f, %.2f)  dist %.2f", cam.target[0], cam.target[1], cam.target[2], cam.dist);
    if (ImGui::Button("Reiniciar câmera")) cam.lookAt({5, 3, 6}, {0, 0.8f, 0});
    ImGui::TextDisabled("arrastar: girar  |  direito/shift: mover  |  roda: zoom");
    ImGui::End();
    ImGui::Render();
    ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
    if (shot && n + 1 == frames) save(shot, w, h);
    SDL_GL_SwapWindow(win);

    Uint64 now = SDL_GetTicksNS();
    frameMs = frameMs * 0.9 + (now - last) * 1e-6 * 0.1;
    last = now;
  }
  if (frames > 0) std::printf("ok: %d quadros, %.2f ms/quadro em média\n", frames, (SDL_GetTicksNS() - t0) * 1e-6 / frames);

  ImGui_ImplOpenGL3_Shutdown();
  ImGui_ImplSDL3_Shutdown();
  ImGui::DestroyContext();
  glDeleteVertexArrays(1, &vao);
  glDeleteProgram(prog);
  SDL_GL_DestroyContext(ctx);
  SDL_DestroyWindow(win);
  SDL_Quit();
  return 0;
}
