# Cenários, arquitetura e dioramas

- **Funções reutilizáveis** para cada elemento (`pilar(h)`, `grade(comprimento, eixo)`, `pinheiro(h, cor)`,
  `lapide()`, `lampiao()`), posicionadas depois com `.at()`. Varie com parâmetros e `seed()`/`uniform()`.
- **Grades sem custo:** lajotas, cercas, telhas e janelas com `repeat`; simetrias com `mirror`; peças radiais com `polar`.
- **Recortes:** portas e janelas com `-`; o cortador atravessa a parede com folga. Batentes e caixilhos
  compartilham centro e nível com o recorte.
- **Telhados:** `prism(w, h, d)` (duas águas, cumeeira em z); textura `bricks` com `bump` vira telhas.
  A caixa do telhado não descreve a altura de cada água: meça na posição real.
- **Base de diorama:** bloco com `bevel`, lajotas em `repeat` com `bevel` pequeno e textura `mottle`/`noise`.
- **Vegetação estilizada:** cones empilhados + `facets()`; árvores secas com `chain` (tronco e galhos).
- **Orçamento:** acima de ~200 primitivas o shader passa de alguns segundos para compilar (rota `desempenho`).

Exemplo completo: `cemiterio.3di` (muro com grade, portão em arco, cripta, pinheiros, abóboras com `polar`,
caveiras pintadas, lápides, lampiões). Também `templo.3di`, `castelo.3di`, `vila.3di`.
