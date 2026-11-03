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

add_executable(3di app/main.cpp app/gl.cpp app/camera.cpp)
target_link_libraries(3di PRIVATE SDL3::SDL3 imgui)
if(MSVC)
  target_compile_options(3di PRIVATE /W4)
else()
  target_compile_options(3di PRIVATE -Wall -Wextra)
endif()
