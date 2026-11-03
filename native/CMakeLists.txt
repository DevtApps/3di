# 3DI nativo (docs/plano-cpp-sdl3.md). Fase 1: janela SDL3 + OpenGL 3.3, shader de teste, câmera
# orbital e painel ImGui. Dependências baixadas pelo FetchContent (ou SDL3 do sistema, se houver).
#   cmake -S native -B native/build -G Ninja && cmake --build native/build && native/build/3di
cmake_minimum_required(VERSION 3.24)
project(tdi LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE RelWithDebInfo)
endif()

include(FetchContent)
set(FETCHCONTENT_QUIET OFF)

find_package(SDL3 3.4 QUIET CONFIG)
if(NOT SDL3_FOUND)
  set(SDL_SHARED OFF CACHE BOOL "" FORCE)
  set(SDL_STATIC ON CACHE BOOL "" FORCE)
  set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
  set(SDL_X11_XSCRNSAVER OFF CACHE BOOL "" FORCE)  # libxss-dev costuma faltar; só serve para inibir o protetor de tela
  FetchContent_Declare(SDL3 GIT_REPOSITORY https://github.com/libsdl-org/SDL.git GIT_TAG release-3.4.20 GIT_SHALLOW ON)
  FetchContent_MakeAvailable(SDL3)
endif()

FetchContent_Declare(imgui GIT_REPOSITORY https://github.com/ocornut/imgui.git GIT_TAG v1.92.9b-docking GIT_SHALLOW ON)
FetchContent_MakeAvailable(imgui)
add_library(imgui STATIC
  ${imgui_SOURCE_DIR}/imgui.cpp ${imgui_SOURCE_DIR}/imgui_draw.cpp ${imgui_SOURCE_DIR}/imgui_tables.cpp
  ${imgui_SOURCE_DIR}/imgui_widgets.cpp ${imgui_SOURCE_DIR}/imgui_demo.cpp
  ${imgui_SOURCE_DIR}/backends/imgui_impl_sdl3.cpp ${imgui_SOURCE_DIR}/backends/imgui_impl_opengl3.cpp)
target_include_directories(imgui PUBLIC ${imgui_SOURCE_DIR} ${imgui_SOURCE_DIR}/backends)
target_link_libraries(imgui PUBLIC SDL3::SDL3)

# stb_image_write: PNG das texturas assadas na exportação (só o cabeçalho)
FetchContent_Declare(stb GIT_REPOSITORY https://github.com/nothings/stb.git GIT_TAG d14d46f6b44456eb88beac58cba833a4135d4c89)
FetchContent_MakeAvailable(stb)

# núcleo sem janela (parser, interpretador, compilador...): usado pelo app, pelo CLI e pelos testes
add_library(tdi_core STATIC core/json.cpp core/lexer.cpp core/parser.cpp core/ast.cpp core/value.cpp core/expr.cpp
  core/shape.cpp core/profile.cpp core/color.cpp core/interp.cpp core/scope.cpp core/anchor.cpp
  core/curve.cpp core/pattern.cpp core/rig.cpp core/modules.cpp core/lib/style.cpp core/lib/grass.cpp core/lib/plants.cpp
  core/lib/trees.cpp core/lib/people.cpp core/lib/vehicles.cpp
  core/compiler.cpp core/sdf.cpp core/sha256.cpp core/mesh.cpp core/nativemesh.cpp core/export.cpp)
target_include_directories(tdi_core PUBLIC core PRIVATE ${stb_SOURCE_DIR})
find_package(Threads REQUIRED)
target_link_libraries(tdi_core PUBLIC Threads::Threads)
if(MSVC)
  target_compile_options(tdi_core PRIVATE /W4 /utf-8)
else()
  target_compile_options(tdi_core PRIVATE -Wall -Wextra)
endif()

FetchContent_Declare(doctest GIT_REPOSITORY https://github.com/doctest/doctest.git GIT_TAG v2.5.3 GIT_SHALLOW ON)
FetchContent_MakeAvailable(doctest)
enable_testing()
add_executable(tdi_tests tests/main.cpp tests/parser_test.cpp tests/interp_test.cpp tests/compiler_test.cpp tests/export_test.cpp)
target_link_libraries(tdi_tests PRIVATE tdi_core doctest::doctest)
target_compile_definitions(tdi_tests PRIVATE TDI_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/..")
add_test(NAME tdi_tests COMMAND tdi_tests)

add_executable(3di-cli cli/main.cpp)
target_link_libraries(3di-cli PRIVATE tdi_core)

add_executable(3di app/main.cpp app/camera.cpp render/gl.cpp render/renderer.cpp)
target_include_directories(3di PRIVATE render app)
target_link_libraries(3di PRIVATE tdi_core SDL3::SDL3 imgui)
if(MSVC)
  target_compile_options(3di PRIVATE /W4)
else()
  target_compile_options(3di PRIVATE -Wall -Wextra)
endif()
