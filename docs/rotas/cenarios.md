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
caveiras pintadas, lápides, lampiões). Também `templo.3di`, `castelo.3di`, `vila.3di`.
