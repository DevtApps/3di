# 3DI nativo (C++20 + SDL3)

Port em andamento do 3DI para um executável nativo. O plano completo está em
[`docs/plano-cpp-sdl3.md`](../docs/plano-cpp-sdl3.md).

- **Fase 0, pronta:** os golden files em `tests/golden/` são gerados pela versão JS com
  `npm run golden` e conferidos pelo `npm test`. Para cada exemplo há AST, árvore de formas,
  resumo da compilação, hash dos dados da BVH, amostras de `sdf(p)` e o GLSL.
- **Fase 1, pronta:** janela SDL3 com OpenGL 3.3 core, um shader SDF de teste no formato do
  `mapAll`, câmera orbital e painel ImGui.

- **Fase 2, pronta:** `core/lexer`, `core/parser` e `core/ast` são o port do `parser.js`. O AST de
  todos os exemplos e as mensagens dos erros de sintaxe são iguais aos do JS (`native/build/tdi_tests`).

- **Fases 3 e 4, prontas:** interpretador, valores, expressões com `time`, formas, escopos, âncoras,
  curvas, padrões, rig e os geradores (grama, plantas, árvores, pessoas e veículos). Os 30 exemplos
  dão a mesma árvore de formas e os mesmos prints do JS, com o mesmo aleatório. 37 erros de
  execução dão a mesma mensagem, linha e dica.

- **Fases 5 e 6, prontas:** SDF na CPU (`core/sdf`) e compilador GLSL (`core/compiler`), com BVH e
  instâncias de código. O GLSL dos 30 exemplos sai byte a byte igual ao do JS. Os dados da BVH batem
  até 1e-5 (o `sin`/`cos` da libm difere do V8 na última casa). `3di-cli check arquivo.3di` dá a mesma
  saída do `scripts/check.mjs`.

- **Fases 7 e 8, prontas:** renderizador OpenGL (`render/`) com o mesmo shader do editor web, extraído de
  `renderer.js` e conferido por `tests/golden/_frag.glsl`. O app (`app/`) abre um `.3di` pela linha de
  comando, pelo botão Abrir ou arrastando o arquivo para a janela, e recarrega quando o arquivo muda.
  Ele roda e compila a cena em segundo plano, e o shader compila em paralelo quando o driver tem
  `KHR_parallel_shader_compile`. Mostra erros e prints, tem câmeras prontas, a lista de peças e as 4
  vistas, desenha a cena só quando algo muda e baixa a resolução enquanto a câmera se move.
  `3di cena.3di --views saida.png` faz o mesmo que `scripts/render.mjs`, sem Chrome: na vila, a diferença
  média contra o render do Chrome foi de 1,7 em 255.

## Compilar

As dependências (SDL 3.4 e Dear ImGui) são baixadas pelo CMake. Se houver um SDL3 instalado no
sistema, ele é usado no lugar.

```bash
cmake -S native -B native/build -G Ninja && cmake --build native/build
```

```bash
native/build/3di
```

Abrir uma cena, ou gerar as 4 vistas sem abrir janela:

```bash
native/build/3di examples/vila.3di
```

```bash
native/build/3di examples/vila.3di --views vila.png --size 512
```

Validar e medir uma cena sem GPU (como `scripts/check.mjs`):

```bash
native/build/3di-cli check examples/vila.3di
```

Controles da câmera:

- arrastar com o botão esquerdo gira;
- arrastar com o botão direito, ou com Shift, move o alvo;
- a roda aproxima;
- R recarrega, F enquadra e Esc sai.

Testes do núcleo:

```bash
native/build/tdi_tests
```

Teste de fumaça sem interação: o comando abaixo desenha 120 quadros, grava o último em BMP e
imprime o tempo médio por quadro.

```bash
native/build/3di --frames 120 --shot quadro.bmp
```
