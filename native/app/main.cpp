// 3DI nativo: abre uma cena .3di, roda e compila em segundo plano e renderiza com o mesmo shader do
// editor web. Recarrega quando o arquivo muda (use o seu editor de texto favorito).
//   3di [cena.3di]                      janela interativa
//   3di cena.3di --views saida.png      4 vistas (frente, lado, topo, perspectiva) e sai, como render.mjs
//        [--size 512] [--t segundos]
//   3di [cena.3di] --frames N [--shot quadro.png]   desenha N quadros e sai (teste de fumaça)
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>
#include <imgui.h>
#include <imgui_impl_opengl3.h>
#include <imgui_impl_sdl3.h>

#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <future>
#include <mutex>
#include <sstream>
#include <string>

#include "camera.h"
#include "compiler.h"
#include "expr.h"
#include "gl.h"
#include "interp.h"
#include "renderer.h"

using namespace tdi;
using namespace gl;
namespace fs = std::filesystem;

// ---------- cena: script -> formas -> GLSL (numa thread) ----------

struct Built {
  bool ok = false;
  std::string error;
  std::vector<std::string> logs;
  Compiled out;
  Scene scene;
  std::shared_ptr<Interp> it;  // dono dos objetos da cena
  double ms = 0;
};

static Built build(const std::string &src, double layoutT) {
  Built b;
  Uint64 t0 = SDL_GetTicksNS();
  withTime(layoutT, [&] {
    RunResult r = runScript(src);
    b.logs = r.logs;
    b.it = r.it;
    if (!r.ok) { b.error = r.error.str(); return; }
    try {
      b.out = compileScene(r.it->scene);
      b.scene = r.it->scene;
      b.ok = true;
    } catch (const ScriptError &e) {
      b.error = e.str();
    } catch (const std::exception &e) {
      b.error = std::string("erro interno: ") + e.what();
    }
  });
  b.ms = (SDL_GetTicksNS() - t0) * 1e-6;
  return b;
}

static std::string slurp(const fs::path &p, bool &ok) {
  std::ifstream f(p, std::ios::binary);
  ok = (bool)f;
  std::stringstream ss;
  ss << f.rdbuf();
  return ss.str();
}

static V3 v3of(const Value &v, V3 def) {
  if (!v.isList() || v.size() != 3) return def;
  return {val0(v[0]), val0(v[1]), val0(v[2])};
}

// parâmetros de luz e névoa da cena (como draw() em main.js)
static View viewFor(const Built &b, const V3 &eye, const V3 &target, double fov, double time, int shadowSteps) {
  View v;
  v.eye = eye;
  v.target = target;
  v.fov = fov;
  double r = radiusOf(b.out.bbox);
  double dist = std::sqrt(std::pow(eye[0] - target[0], 2) + std::pow(eye[1] - target[1], 2) + std::pow(eye[2] - target[2], 2));
  const Scene &sc = b.scene;
  v.fog = !sc.fog.isNone() ? sc.fog.n() : (b.out.hasPlane ? 1 / (std::max({dist, r, 1.0}) * 14) : 0);
  v.maxDist = b.out.hasPlane ? std::max(80.0, dist * 30) : dist + r * 4;
  if (auto s = sc.sun.as<Rec>()) {
    v.sun = v3of(s->f["dir"], v.sun);
    v.sunColor = v3of(s->f["color"], v.sunColor);
  }
  v.sky = v3of(sc.sky, v.sky);
  if (auto l = sc.light.as<Rec>()) v.light = {l->f.num("rim"), l->f.num("fill"), l->f.num("ao"), v3of(l->f["rimColor"], {1, 1, 1})};
  v.time = time;
  v.shadowSteps = shadowSteps;
  return v;
}

static bool savePNG(const char *path, const std::vector<unsigned char> &rgba, int w, int h) {
  SDL_Surface *s = SDL_CreateSurfaceFrom(w, h, SDL_PIXELFORMAT_ABGR8888, const_cast<unsigned char *>(rgba.data()), w * 4);
  if (!s) return false;
  std::string p = path;
  bool ok = p.size() > 4 && p.substr(p.size() - 4) == ".bmp" ? SDL_SaveBMP(s, path) : SDL_SavePNG(s, path);
  SDL_DestroySurface(s);
  return ok;
}

static int fail(const char *what, const std::string &msg) {
  std::fprintf(stderr, "ERRO %s: %s\n", what, msg.c_str());
  return 1;
}

// as 4 vistas numa imagem 2x2 com rótulos (desenhados pelo ImGui num framebuffer)
static std::vector<unsigned char> renderViews(Renderer &R, const Built &b, int size, double time) {
  BBox bb = sceneBox(b.out.bbox, b.out.hasPlane);
  auto cams = viewCameras(bb);
  int W = size * 2;
  std::vector<unsigned char> img((size_t)W * W * 4);
  for (int i = 0; i < 4; i++) {
    Camera c;
    c.target = cams[i].target;
    c.yaw = cams[i].yaw;
    c.pitch = cams[i].pitch;
    c.dist = cams[i].dist;
    c.fov = cams[i].fov;
    auto px = R.renderOffscreen(viewFor(b, c.eye(), c.target, c.fov, time, 80), size, size);
    int ox = (i % 2) * size, oy = (i / 2) * size;
    for (int y = 0; y < size; y++) std::copy_n(px.begin() + (size_t)y * size * 4, (size_t)size * 4, img.begin() + ((size_t)(oy + y) * W + ox) * 4);
  }
  // rótulos: uma passada do ImGui sobre a imagem
  GLuint fbo, tex;
  glGenFramebuffers(1, &fbo);
  GenTextures(1, &tex);
  BindTexture(GL_TEXTURE_2D, tex);
  std::vector<unsigned char> flipped(img.size());
  for (int y = 0; y < W; y++) std::copy_n(img.begin() + (size_t)(W - 1 - y) * W * 4, (size_t)W * 4, flipped.begin() + (size_t)y * W * 4);
  TexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, W, W, 0, GL_RGBA, GL_UNSIGNED_BYTE, flipped.data());
  glBindFramebuffer(GL_FRAMEBUFFER, fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
  ImGuiIO &io = ImGui::GetIO();
  ImVec2 savedSize = io.DisplaySize, savedScale = io.DisplayFramebufferScale;
  io.DisplaySize = ImVec2((float)W, (float)W);
  io.DisplayFramebufferScale = ImVec2(1, 1);
  ImGui_ImplOpenGL3_NewFrame();
  ImGui::NewFrame();
  ImDrawList *dl = ImGui::GetForegroundDrawList();
  float fsz = std::max(13.f, size / 30.f);
  auto tag = [&](const std::string &text, float x, float y) {
    ImVec2 t = ImGui::GetFont()->CalcTextSizeA(fsz, 1e9f, 0, text.c_str());
    dl->AddRectFilled(ImVec2(x, y), ImVec2(x + t.x + fsz, y + fsz * 1.7f), IM_COL32(15, 17, 22, 184));
    dl->AddText(ImGui::GetFont(), fsz, ImVec2(x + fsz / 2, y + fsz * 0.35f), IM_COL32_WHITE, text.c_str());
  };
  for (int i = 0; i < 4; i++) {
    float x = (float)(i % 2) * size, y = (float)(i / 2) * size;
    tag(cams[i].label, x + 8, y + 8);
    if (!cams[i].axes.empty()) tag(cams[i].axes, x + 8, y + size - fsz * 1.7f - 8);
  }
  // tamanho da cena no canto da perspectiva (como no editor)
  {
    V3 s = tdi::size(bb);
    char buf[128];
    std::snprintf(buf, sizeof buf, "bbox %s × %s × %s m", fmtNum(std::round(s[0] * 1000) / 1000).c_str(), fmtNum(std::round(s[1] * 1000) / 1000).c_str(),
                  fmtNum(std::round(s[2] * 1000) / 1000).c_str());
    ImVec2 t = ImGui::GetFont()->CalcTextSizeA(fsz, 1e9f, 0, buf);
    tag(buf, (float)W - t.x - fsz - 8, (float)W - fsz * 1.7f - 8);
  }
  ImGui::Render();
  Viewport(0, 0, W, W);
  ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
  io.DisplaySize = savedSize;
  io.DisplayFramebufferScale = savedScale;
  std::vector<unsigned char> px((size_t)W * W * 4);
  ReadPixels(0, 0, W, W, GL_RGBA, GL_UNSIGNED_BYTE, px.data());
  for (int y = 0; y < W; y++) std::copy_n(px.begin() + (size_t)(W - 1 - y) * W * 4, (size_t)W * 4, img.begin() + (size_t)y * W * 4);
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glDeleteFramebuffers(1, &fbo);
  DeleteTextures(1, &tex);
  return img;
}

int main(int argc, char **argv) {
  std::string file, viewsOut, shot;
  int frames = -1, size = 512;
  double tArg = -1;
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    if (a == "--frames" && i + 1 < argc) frames = std::atoi(argv[++i]);
    else if (a == "--shot" && i + 1 < argc) shot = argv[++i];
    else if (a == "--views" && i + 1 < argc) viewsOut = argv[++i];
    else if (a == "--size" && i + 1 < argc) size = std::clamp(std::atoi(argv[++i]), 64, 2048);
    else if (a == "--t" && i + 1 < argc) tArg = std::atof(argv[++i]);
    else if (a == "-h" || a == "--help") {
      std::printf("uso: 3di [cena.3di] [--views saida.png [--size px] [--t s]] [--frames N [--shot quadro.png]]\n");
      return 0;
    } else file = a;
  }
  bool headless = !viewsOut.empty();

  if (!SDL_Init(SDL_INIT_VIDEO)) return fail("SDL_Init", SDL_GetError());
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
  SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
  SDL_WindowFlags flags = SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY | (headless ? SDL_WINDOW_HIDDEN : 0);
  SDL_Window *win = SDL_CreateWindow("3DI", 1280, 800, flags);
  if (!win) return fail("SDL_CreateWindow", SDL_GetError());
  SDL_GLContext ctx = SDL_GL_CreateContext(win);
  if (!ctx) return fail("SDL_GL_CreateContext", SDL_GetError());
  SDL_GL_MakeCurrent(win, ctx);
  SDL_GL_SetSwapInterval(frames < 0 ? 1 : 0);
  std::string err;
  if (!load(err)) return fail("OpenGL", err);
  Renderer R;
  R.init(err);

  IMGUI_CHECKVERSION();
  ImGui::CreateContext();
  ImGui::GetIO().IniFilename = nullptr;
  ImGui::StyleColorsDark();
  // fonte do sistema com acentos e setas (a padrão do ImGui só tem ASCII); o ImGui 1.92 carrega os
  // glifos sob demanda
  for (const char *f : {"/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/TTF/DejaVuSans.ttf",
                        "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf", "/usr/share/fonts/noto/NotoSans-Regular.ttf",
                        "C:\\Windows\\Fonts\\segoeui.ttf", "/System/Library/Fonts/Supplemental/Arial.ttf", "/Library/Fonts/Arial.ttf"})
    if (fs::exists(f) && ImGui::GetIO().Fonts->AddFontFromFileTTF(f, 15.0f)) break;
  ImGui_ImplSDL3_InitForOpenGL(win, ctx);
  ImGui_ImplOpenGL3_Init("#version 330 core");

  // ---------- estado ----------
  Camera cam;
  std::shared_ptr<Built> cur;  // cena na tela
  std::future<Built> job;
  bool jobRunning = false, reloadQueued = false;
  std::string status = file.empty() ? "abra uma cena .3di (arraste o arquivo para a janela)" : "carregando...";
  bool statusErr = false;
  fs::file_time_type mtime{};
  std::string cameraKey;
  double compileMs = 0, buildMs = 0, frameMs = 0;
  Uint64 t0 = SDL_GetTicksNS(), last = t0;
  bool playing = true;
  double animT = tArg >= 0 ? tArg : 0;
  std::mutex dropMx;
  std::string dropped;

  auto startBuild = [&]() {
    if (file.empty()) return;
    if (jobRunning) { reloadQueued = true; return; }
    bool ok;
    std::string src = slurp(file, ok);
    if (!ok) { status = "não foi possível abrir " + file; statusErr = true; return; }
    std::error_code ec;
    mtime = fs::last_write_time(file, ec);
    job = std::async(std::launch::async, build, src, tArg > 0 ? tArg : 0.0);
    jobRunning = true;
  };
  auto openFile = [&](const std::string &p) {
    file = p;
    cameraKey.clear();
    SDL_SetWindowTitle(win, ("3DI — " + fs::path(p).filename().string()).c_str());
    startBuild();
  };
  if (!file.empty()) openFile(file);

  auto onBuilt = [&](Built b) {
    buildMs = b.ms;
    for (auto &l : b.logs) std::printf("print: %s\n", l.c_str());
    if (!b.ok) {
      status = b.error;
      statusErr = true;
      if (headless) std::fprintf(stderr, "ERRO %s\n", b.error.c_str());
      return;
    }
    auto nb = std::make_shared<Built>(std::move(b));
    R.setScene(nb->out.glsl, nb->out.data, nb->out.hasData);
    // a câmera do script (ou o enquadramento) só é aplicada quando ela muda
    std::string key;
    if (auto c = nb->scene.camera.as<Rec>()) key = repr(c->f["pos"]) + repr(c->f["look"]) + repr(c->f["fov"]);
    else key = "frame";
    if (key != cameraKey) {
      cameraKey = key;
      if (auto c = nb->scene.camera.as<Rec>()) {
        V3 look = v3of(c->f["look"], {0, 0, 0});
        applyScriptCamera(cam, v3of(c->f["pos"], {0, 0, 0}), c->f["look"].isNone() ? nullptr : &look, c->f.num("fov"), nb->out.bbox);
      } else frameBox(cam, sceneBox(nb->out.bbox, nb->out.hasPlane));
    }
    cur = nb;
    char buf[256];
    std::snprintf(buf, sizeof buf, "ok: %d primitivas (%d na BVH, %d como código), compilado em %.0f ms", cur->out.leaves, cur->out.instances, cur->out.codeLeaves, buildMs);
    status = buf;
    statusErr = false;
  };

  // ---------- modo sem janela: 4 vistas ----------
  if (headless) {
    if (file.empty()) return fail("--views", "falta o arquivo .3di");
    onBuilt(job.get());
    jobRunning = false;
    if (!cur) return 1;
    while (R.compiling()) {
      double ms;
      if (R.poll(err, ms)) compileMs = ms;
      if (!err.empty()) return fail("shader", err);
      SDL_Delay(5);
    }
    auto img = renderViews(R, *cur, size, animT);
    if (!savePNG(viewsOut.c_str(), img, size * 2, size * 2)) return fail("salvar", SDL_GetError());
    std::printf("%s (shader compilado em %.0f ms)\n", status.c_str(), compileMs);
    std::printf("vistas: %s\n", viewsOut.c_str());
    return 0;
  }

  // ---------- janela ----------
  GLuint viewTex[4] = {0, 0, 0, 0};
  // resolução adaptativa (como adaptiveScale em main.js): degraus fixos, só durante a interação
  const double LEVELS[] = {1, 0.75, 0.5, 0.35};
  int level = 0;
  double renderMs = 0, sinceChange = 0;
  Uint64 lastInput = 0;
  bool dirty = true;
  struct { V3 eye, target; double fov; } lastCam{};
  bool showViews = false, viewsDirty = true;
  bool run = true;
  for (int n = 0; run && n != frames; n++) {
    SDL_Event e;
    while (SDL_PollEvent(&e)) {
      ImGui_ImplSDL3_ProcessEvent(&e);
      if (e.type == SDL_EVENT_QUIT || (e.type == SDL_EVENT_KEY_DOWN && e.key.key == SDLK_ESCAPE && !ImGui::GetIO().WantCaptureKeyboard)) run = false;
      if (e.type == SDL_EVENT_DROP_FILE && e.drop.data) openFile(e.drop.data);
      if (e.type == SDL_EVENT_KEY_DOWN && !ImGui::GetIO().WantCaptureKeyboard) {
        if (e.key.key == SDLK_R) startBuild();
        if (e.key.key == SDLK_F && cur) frameBox(cam, sceneBox(cur->out.bbox, cur->out.hasPlane));
      }
      if (ImGui::GetIO().WantCaptureMouse) continue;
      if (e.type == SDL_EVENT_MOUSE_MOTION) {
        bool pan = (e.motion.state & SDL_BUTTON_RMASK) || ((e.motion.state & SDL_BUTTON_LMASK) && (SDL_GetModState() & SDL_KMOD_SHIFT));
        int h;
        SDL_GetWindowSize(win, nullptr, &h);
        if (pan) cam.pan(e.motion.xrel, e.motion.yrel, (float)h);
        else if (e.motion.state & SDL_BUTTON_LMASK) cam.orbit(e.motion.xrel, e.motion.yrel);
      }
      if (e.type == SDL_EVENT_MOUSE_WHEEL) cam.zoom(e.wheel.y);
      if (e.type == SDL_EVENT_MOUSE_MOTION || e.type == SDL_EVENT_MOUSE_WHEEL) lastInput = SDL_GetTicksNS();
      if (e.type == SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED || e.type == SDL_EVENT_WINDOW_EXPOSED) dirty = true;
    }
    {
      std::lock_guard<std::mutex> lk(dropMx);
      if (!dropped.empty()) { openFile(dropped); dropped.clear(); }
    }

    // recarrega quando o arquivo muda
    if (!file.empty() && n % 30 == 0) {
      std::error_code ec;
      auto t = fs::last_write_time(file, ec);
      if (!ec && t != mtime) startBuild();
    }
    if (jobRunning && job.wait_for(std::chrono::seconds(0)) == std::future_status::ready) {
      jobRunning = false;
      onBuilt(job.get());
      viewsDirty = true;
      dirty = true;
      if (reloadQueued) { reloadQueued = false; startBuild(); }
    }
    {
      std::string e2;
      double ms;
      if (R.poll(e2, ms)) { compileMs = ms; viewsDirty = true; dirty = true; }
      if (!e2.empty()) { status = "erro ao compilar shader:\n" + e2; statusErr = true; }
    }

    Uint64 now = SDL_GetTicksNS();
    double dt = (now - last) * 1e-9;
    bool animated = cur && cur->out.animated;
    if (animated && playing && tArg < 0) {
      double dur = 0;
      if (auto a = cur->scene.anim.as<Rec>()) dur = a->f.num("duration");
      animT += dt;
      if (dur > 0) animT = std::fmod(animT, dur);
    }

    int w, h;
    SDL_GetWindowSizeInPixels(win, &w, &h);
    Viewport(0, 0, w, h);
    ClearColor(0.12f, 0.13f, 0.16f, 1);
    Clear(GL_COLOR_BUFFER_BIT);
    if (cur && R.ready()) {
      V3 eye = cam.eye();
      if (eye != lastCam.eye || cam.target != lastCam.target || cam.fov != lastCam.fov) { dirty = true; lastCam = {eye, cam.target, cam.fov}; }
      bool interacting = (now - lastInput) < 250000000ull;
      if (animated && playing) dirty = true;
      // sem interação, volta à resolução cheia; durante ela, ajusta o degrau pela média do tempo de quadro
      int want = interacting ? level : 0;
      if (dirty || want != level || (!interacting && level != 0)) {
        if (!interacting) level = 0;
        int rw = std::max(1, (int)(w * LEVELS[level])), rh = std::max(1, (int)(h * LEVELS[level]));
        Uint64 r0 = SDL_GetTicksNS();
        R.renderToTarget(viewFor(*cur, eye, cam.target, cam.fov, animT, interacting ? 28 : 80), rw, rh);
        Finish();
        double ms = (SDL_GetTicksNS() - r0) * 1e-6;
        renderMs = renderMs ? renderMs * 0.8 + ms * 0.2 : ms;
        sinceChange += dt;
        if (interacting && sinceChange > 0.5) {
          double up = level > 0 ? renderMs * std::pow(LEVELS[level - 1] / LEVELS[level], 2) : 1e9;
          if (renderMs > 40 && level < 3) { level++; sinceChange = 0; renderMs = 0; }
          else if (up < 28) { level--; sinceChange = 0; renderMs = 0; }
        }
        dirty = false;
      }
      R.blitToScreen(w, h);
    }

    if (showViews && cur && R.ready() && viewsDirty) {
      BBox bb = sceneBox(cur->out.bbox, cur->out.hasPlane);
      auto cams = viewCameras(bb);
      for (int i = 0; i < 4; i++) {
        Camera c;
        c.target = cams[i].target; c.yaw = cams[i].yaw; c.pitch = cams[i].pitch; c.dist = cams[i].dist; c.fov = cams[i].fov;
        auto px = R.renderOffscreen(viewFor(*cur, c.eye(), c.target, c.fov, animT, 80), 384, 384);
        if (!viewTex[i]) GenTextures(1, &viewTex[i]);
        BindTexture(GL_TEXTURE_2D, viewTex[i]);
        TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        TexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 384, 384, 0, GL_RGBA, GL_UNSIGNED_BYTE, px.data());
      }
      viewsDirty = false;
      Viewport(0, 0, w, h);
    }

    ImGui_ImplOpenGL3_NewFrame();
    ImGui_ImplSDL3_NewFrame();
    ImGui::NewFrame();
    ImGui::SetNextWindowPos({10, 10}, ImGuiCond_FirstUseEver);
    ImGui::SetNextWindowSizeConstraints({320, 0}, {560, 2000});
    ImGui::Begin("3DI", nullptr, ImGuiWindowFlags_AlwaysAutoResize);
    if (ImGui::Button("Abrir...")) {
      static const SDL_DialogFileFilter filt[] = {{"cenas 3DI", "3di"}};
      SDL_ShowOpenFileDialog(
          [](void *ud, const char *const *list, int) {
            auto *st = static_cast<std::pair<std::mutex *, std::string *> *>(ud);
            if (list && list[0]) { std::lock_guard<std::mutex> lk(*st->first); *st->second = list[0]; }
          },
          new std::pair<std::mutex *, std::string *>(&dropMx, &dropped), win, filt, 1, nullptr, false);
    }
    ImGui::SameLine();
    ImGui::BeginDisabled(file.empty());
    if (ImGui::Button("Recarregar (R)")) startBuild();
    ImGui::SameLine();
    if (ImGui::Button("Enquadrar (F)") && cur) frameBox(cam, sceneBox(cur->out.bbox, cur->out.hasPlane));
    ImGui::EndDisabled();
    ImGui::TextDisabled("%s", file.empty() ? "(nenhum arquivo)" : file.c_str());
    ImGui::Separator();
    if (statusErr) ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(255, 120, 110, 255));
    ImGui::PushTextWrapPos(520);
    ImGui::TextUnformatted(status.c_str());
    ImGui::PopTextWrapPos();
    if (statusErr) ImGui::PopStyleColor();
    if (jobRunning) ImGui::TextDisabled("rodando o script...");
    if (R.compiling()) ImGui::TextDisabled("compilando o shader...");
    if (cur) {
      ImGui::Text("shader: %.0f ms   render: %.1f ms   resolução %.0f%%", compileMs, renderMs, LEVELS[level] * 100);
      if (!cur->out.codeGroups.empty()) {
        int c = 0;
        for (int g : cur->out.codeGroups) c += g;
        ImGui::TextDisabled("%d cópias de %zu peça(s) repetida(s)", c, cur->out.codeGroups.size());
      }
      if (cur->out.animated) {
        ImGui::Checkbox("animar", &playing);
        ImGui::SameLine();
        float t = (float)animT;
        if (ImGui::SliderFloat("t", &t, 0, 10, "%.2f s")) { animT = t; playing = false; }
      }
      ImGui::Separator();
      const char *names[] = {"front", "back", "right", "left", "top", "perspective"};
      const char *labels[] = {"frente", "trás", "direita", "esquerda", "topo", "perspectiva"};
      for (int i = 0; i < 6; i++) {
        if (i) ImGui::SameLine();
        if (ImGui::SmallButton(labels[i])) frameBox(cam, sceneBox(cur->out.bbox, cur->out.hasPlane), names[i]);
      }
      if (ImGui::Checkbox("Vistas", &showViews)) viewsDirty = true;
      if (!cur->out.parts.empty() && ImGui::TreeNode("Peças")) {
        for (auto &p : cur->out.parts) {
          V3 s = tdi::size(p.bbox);
          if (ImGui::Selectable((p.name + "  " + fmtNum(s[0]) + " x " + fmtNum(s[1]) + " x " + fmtNum(s[2])).c_str())) frameBox(cam, p.bbox, "");
        }
        ImGui::TreePop();
      }
      if (!cur->logs.empty() && ImGui::TreeNode("print")) {
        for (auto &l : cur->logs) ImGui::TextUnformatted(l.c_str());
        ImGui::TreePop();
      }
    }
    ImGui::TextDisabled("arrastar: girar | direito/shift: mover | roda: zoom");
    ImGui::End();
    if (showViews && cur && viewTex[0]) {
      ImGui::SetNextWindowPos({(float)w / ImGui::GetIO().DisplayFramebufferScale.x - 790, 10}, ImGuiCond_FirstUseEver);
      ImGui::Begin("Vistas", &showViews, ImGuiWindowFlags_AlwaysAutoResize);
      auto cams = viewCameras(sceneBox(cur->out.bbox, cur->out.hasPlane));
      for (int i = 0; i < 4; i++) {
        if (i % 2) ImGui::SameLine();
        ImGui::BeginGroup();
        ImGui::Image((ImTextureID)(intptr_t)viewTex[i], {384, 384});
        ImGui::TextDisabled("%s %s", cams[i].label.c_str(), cams[i].axes.c_str());
        ImGui::EndGroup();
      }
      if (ImGui::Button("Salvar PNG ao lado da cena")) {
        fs::path out = fs::path(file).replace_extension("").string() + "-vistas.png";
        auto img = renderViews(R, *cur, 512, animT);
        savePNG(out.string().c_str(), img, 1024, 1024);
        status = "vistas salvas em " + out.string();
        statusErr = false;
      }
      ImGui::End();
    }
    ImGui::Render();
    Viewport(0, 0, w, h);
    ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
    if (!shot.empty() && n + 1 == frames) {
      std::vector<unsigned char> px((size_t)w * h * 4), out(px.size());
      ReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, px.data());
      for (int y = 0; y < h; y++) std::copy_n(px.begin() + (size_t)(h - 1 - y) * w * 4, (size_t)w * 4, out.begin() + (size_t)y * w * 4);
      savePNG(shot.c_str(), out, w, h);
    }
    SDL_GL_SwapWindow(win);
    // no teste de fumaça, os quadros só contam depois que a cena está na tela (com erro, conta já)
    if (frames > 0 && !file.empty() && !statusErr && !(cur && R.ready()) && (SDL_GetTicksNS() - t0) < 120000000000ull) n--;
    now = SDL_GetTicksNS();
    frameMs = frameMs * 0.9 + (now - last) * 1e-6 * 0.1;
    last = now;
  }
  if (frames > 0) std::printf("ok: %d quadros, %.2f ms/quadro em média; %s\n", frames, (SDL_GetTicksNS() - t0) * 1e-6 / frames, status.c_str());
  if (jobRunning) job.wait();

  ImGui_ImplOpenGL3_Shutdown();
  ImGui_ImplSDL3_Shutdown();
  ImGui::DestroyContext();
  SDL_GL_DestroyContext(ctx);
  SDL_DestroyWindow(win);
  SDL_Quit();
  return 0;
}
