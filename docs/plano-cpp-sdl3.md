# Plano: refatorar o 3DI para C++ com SDL3

## Objetivo

Ter um executável nativo, `3di`, que abre uma cena `.3di`, compila o GLSL e renderiza em tempo real.
Ele deve ter recarga ao salvar, câmera orbital e exportação de malha. Também deve carregar menos
coisas que o app Electron atual: sem Chromium, sem Node e sem WebGL.

O app web e o servidor MCP continuam funcionando durante toda a migração. O núcleo em C++ só
substitui o JS quando a saída dele for idêntica (golden tests).

## SDL2 ou SDL3?

**Escolha: SDL3** (3.2+), com um contexto **OpenGL 3.3 core / GLES 3.0**.

- O compilador já gera GLSL ES 3.0 (`mapAll`, BVH em textura, `uInst`/`uBvh`/`uCode`). Com OpenGL,
  esse GLSL passa quase sem mudança: basta trocar o cabeçalho `#version 300 es` por `#version 330`
  no desktop.
- O SDL3 tem API melhor que o SDL2:
  - janelas com DPI alto;
  - `SDL_main` com callbacks, que facilitam o Emscripten;
  - diálogos de arquivo nativos (`SDL_ShowOpenFileDialog`);
  - `SDL_GetBasePath`;
  - `SDL_IOStream`.
  O SDL2 está em manutenção.
- **SDL_GPU** (Vulkan/Metal/D3D12) fica para depois. Usar a SDL_GPU exigiria compilar o GLSL para
  SPIR-V/MSL em tempo de execução (SDL_shadercross + glslang) a cada edição da cena. Hoje o gargalo
  é o tempo de compilação do shader (veja "Cenários grandes"), e essa etapa extra pioraria o
  problema.

## Arquitetura alvo

```
3di/
  core/            # biblioteca sem dependência de janela (testável, usada por CLI e app)
    lexer, parser  # subconjunto Python  -> AST        (parser.js)
    interp         # AST -> valores/Shapes             (interp.js, runtime.js, expr.js)
    shapes         # Shape, bbox, METHODS              (shapes.js, scope.js, anchor.js,
                   #                                     curve.js, pattern.js, rig.js, profile.js)
    sdf            # avaliação na CPU                  (sdf.js)
    compiler       # Shapes -> GLSL + dados BVH/código (compiler.js)
    mesh           # marching cubes / simplificação    (mesh.js, simplify.js, nativemesh.js)
    export         # glTF/OBJ/STL                      (export.js, gltf.js)
  render/          # OpenGL: shader, texturas de dados, pós  (renderer.js)
  app/             # SDL3: janela, input, câmera, hot-reload, Dear ImGui (editor/painéis)
  cli/             # 3di check | render | export  (substitui scripts/check.mjs, render.mjs)
  tests/           # doctest + golden files gerados pela versão JS
```

- **Build:** CMake ≥ 3.24, C++20, `FetchContent` para SDL3, glad (GL 3.3), Dear ImGui (docking),
  doctest, cgltf/fastgltf e stb_image_write.
- **Valores do interpretador:** `std::variant<None, bool, double, std::string, List, Dict, Func,
  ShapeRef, Curve, Scope…>`. Shapes ficam imutáveis em `std::shared_ptr<const Shape>` e são
  compartilhadas entre cópias, como no JS.
- **Erros:** `ScriptError` com linha e coluna, e as mensagens em pt-BR são mantidas.
- **Paralelismo:** `parallel-node/web.js` dá lugar a um pool de `std::jthread` na malha e no
  `sdf` da CPU.

## Fases

| # | Fase | Entrega | Critério de pronto |
|---|------|---------|--------------------|
| 0 | **Base de testes golden** ✅ | Script JS que, para cada `examples/*.3di`, grava o AST em JSON, a árvore de Shapes em JSON, o GLSL, os dados da BVH e amostras de `sdf(p)` | Arquivos em `tests/golden/` versionados |
| 1 | **Esqueleto CMake + SDL3** ✅ | Janela, contexto GL, um shader fixo de teste, câmera orbital, ImGui | Roda em Linux; CI compila Linux/Windows |
| 2 | **Lexer + parser** ✅ | Port de `parser.js` | AST idêntico ao golden em todos os exemplos |
| 3 | **Interpretador + runtime** | `interp.js`, `runtime.js`, `expr.js`, `seed/uniform/choice` com o mesmo PRNG | Árvore de Shapes idêntica ao golden; mesmo `seed` dá a mesma vila |
| 4 | **Shapes e módulos** | primitivas, CSG, transform, `scope`, `anchor`, `curve`, `pattern`, `rig`/`person` | Os testes de `regression.test.mjs` passam portados para doctest |
| 5 | **SDF na CPU** | `sdf.js` e `PATTERN_GLSL` espelhado | Amostras de `sdf(p)` iguais ao golden com erro abaixo de 1e-5 |
| 6 | **Compilador GLSL** | `compiler.js`, incluindo BVH, `splitScene`, instâncias de código e `CODE_W` | GLSL byte a byte igual ao golden (fora o cabeçalho `#version`) |
| 7 | **Renderizador** | Port de `renderer.js`: texturas `uInst`/`uBvh`/`uCode`, acumulação, pós, `tdi.bench` | Diferença de pixel menor que 0,1% contra `scripts/render.mjs` |
| 8 | **App** | Editor de texto em ImGui, ou só um observador de arquivo com recarga; painel de erros; botão "Vistas" (4 vistas) | Abrir `vila.3di`, editar e ver a cena recarregar |
| 9 | **CLI e exportação** | `3di check`, `3di render --views`, `3di export cena.glb` (malha, simplificação, glTF) | Substitui `check.mjs`/`render.mjs` no fluxo e nos testes |
| 10 | **Integração** | O servidor MCP chama o binário `3di` em vez de Chromium headless; Emscripten opcional para a web | `npm test` usa o CLI nativo; o Electron fica opcional |

Ordem: as fases 0 a 6 dão um núcleo testável sem janela. A fase 1 corre em paralelo e é a única
que depende de SDL.

## Riscos e decisões

- **Paridade numérica:** o JS usa `double` e o PRNG atual. O PRNG precisa ser portado bit a bit.
  Também é preciso evitar `-ffast-math` no core.
- **Tempo de compilação do shader:** continua dependendo do driver. Duas ações ajudam:
  - cache de binário com `glGetProgramBinary`, guardado pelo hash do GLSL, que elimina a
    recompilação de cenas que não mudaram;
  - compilar numa thread com contexto compartilhado (ou `GL_KHR_parallel_shader_compile`),
    para a janela não travar.
- **Editor:** o Monaco não vai para o app nativo. Há três caminhos:
  - ImGuiColorTextEdit, básico;
  - observar o arquivo e deixar o usuário usar o editor dele, que é o mais simples e a recomendação
    para a primeira versão;
  - manter o editor web falando com o núcleo nativo.
- **Escopo:** manter as mesmas mensagens e a mesma documentação (`docs/language.md`, `langinfo.js`).
  `langinfo` pode virar um JSON compartilhado entre as duas versões.
- **Web:** um build Emscripten do mesmo código (SDL3 + WebGL2) poderia, no futuro, substituir o
  núcleo JS do `index.html`.

## Primeiro passo sugerido

A fase 0 (golden files a partir do JS) e a fase 1 (esqueleto CMake + SDL3 com câmera orbital) podem
ser feitas em paralelo e não mexem no código atual.
