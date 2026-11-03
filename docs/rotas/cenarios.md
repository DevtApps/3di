# Cenários, arquitetura e dioramas

- **Funções reutilizáveis** para cada elemento (`pilar(h)`, `grade(comprimento, eixo)`, `pinheiro(h, cor)`,
  `lapide()`, `lampiao()`), posicionadas depois com `.at()`. Varie com parâmetros e `seed()`/`uniform()`.
- **Fachadas e móveis por divisão:** `space(w, h, d)` (ou `forma.space()`) e depois `split("y", [0.4, "~", 0.3])`,
  `tile("x", 0.3, f, gap=0.01)` e `fill(cor | forma | função)`: base, paredes, vãos, tábuas e janelas sem
  coordenadas. `inset` recua (molduras, folhas de porta). Exemplo: `casa-longa.3di`.
- **Componentes com encaixe:** a função devolve a peça com âncoras (`.anchor("porta", "front", y=0)`);
  quem usa cola outras peças com `.attach(casa, "porta", to="back", align="bottom")`, mesmo depois de girar a casa.
- **Curvas:** `spline(pontos)`/`bezier(...)` descrevem caminhos; `sweep(raio | ("box", w, h), curva)` faz canos,
  cordas, vigas curvas, corrimãos e faixas de caminho; `forma.along(curva, spacing=...)` planta postes, estacas e
  tábuas. `curva.offset(...)` dá corrimão e bordas paralelas. Exemplo: `curvas.3di`.
- **Tábuas, telhas e pedras sem custo de peças:** `.planks(largura, length=...)`, `.shingles()` e `.masonry()`
  afundam juntas reais (silhueta, sombra e GLB). Aplique antes de girar a peça; melhor em caixas e prismas.
- **Grades sem custo:** lajotas, cercas, telhas e janelas com `repeat`; simetrias com `mirror`; peças radiais com `polar`.
- **Recortes:** portas e janelas com `-`; o cortador atravessa a parede com folga. Batentes e caixilhos
  compartilham centro e nível com o recorte.
- **Telhados:** `prism(w, h, d)` (duas águas, cumeeira em z) com `.shingles()` (telhas de verdade, fileiras sobrepostas).
  A caixa do telhado não descreve a altura de cada água: meça na posição real.
- **Base de diorama:** bloco com `bevel`, lajotas em `repeat` com `bevel` pequeno e textura `mottle`/`noise`.
- **Vegetação estilizada:** cones empilhados + `facets()`; árvores secas com `chain` (tronco e galhos).
- **Orçamento:** acima de ~200 primitivas o shader passa de alguns segundos para compilar (rota `desempenho`).

Exemplo completo: `cemiterio.3di` (muro com grade, portão em arco, cripta, pinheiros, abóboras com `polar`,
caveiras pintadas, lápides, lampiões). Também `templo.3di`, `castelo.3di` e `vila.3di` (cenário grande: veja abaixo).

## Cenários grandes (vila, cidade)

Lições da `vila.3di` (fiorde com 7 casas, paliçada, floresta, píer e navio):

- **Repetição em círculo ou grade com `polar`/`repeat`** custa zero primitivas: a paliçada inteira
  (256 estacas) e uma floresta de 5 anéis de pinheiros saem por ~20 primitivas. Use contagens primas entre si
  (37, 41, 43...) e alturas diferentes por anel para não parecer fileira. Recorte com `&` uma caixa.
- **`mirror` vira código no shader**; em peças simples repetidas muitas vezes (postes de casa, chifres),
  prefira uma lista de cópias explícitas: elas vão para a BVH.
- **`sweep` afinando** (`(r0, r1)`) vira cones arredondados em código; em cenas grandes use raio constante.
- **Padrões (`planks`, `shingles`, `masonry`)**: cada uso copia a função no shader. Reserve para paredes,
  telhados e bases; peças pequenas (portas, barris) ficam bem com `texture("wood")`.
- **Casas iguais compilam uma vez** (instâncias de código): monte poucos modelos (`MODELOS = [casa(...), casa(...)]`)
  e espalhe-os com `.rotate()`/`.place()`. O `check.mjs` mostra "N cópias de G peça(s) repetida(s)". Numa cena de 30
  casas, compilar caiu de ~9 s para ~2,7 s e o quadro de ~105 ms para ~37 ms. Variar cor ou tamanho por cópia cria
  outro modelo.
- **Fundo distante** (montanhas a 60 m+) e `fog` dão escala, mas as quatro vistas do `render.mjs` enquadram
  a cena toda e ficam lavadas: confira a vila com a câmera da cena no editor.

