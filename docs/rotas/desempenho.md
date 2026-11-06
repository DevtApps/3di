# Desempenho e limites

- O shader é compilado a cada mudança; o tempo cresce mais que linearmente com as primitivas **em código**
  (booleanas, `smooth`, `merge`, `paint`, deformações). Até ~100: menos de 1 s; ~250: ~6 s.
- Uniões simples de primitivas viram dados numa BVH (sem teto fixo de instâncias) e quase não pesam na compilação.
  Primitivas como código também não têm teto fixo; cenas complexas dependem do compilador da GPU.
- `mirror`, `repeat` e `polar` não custam primitivas: prefira-os a cópias.
- Ruído (`displace`, texturas), `twist`, `bend` e `implicit` são caros por pixel.
- Monte primeiro os volumes, confira, e só então acrescente detalhes; teste partes isoladas em cenas pequenas.

- `repeat()` não tem teto fixo de cópias; as contagens devem ser inteiros positivos com precisão segura.
- Exportação não reduz a resolução automaticamente nem limita curvas a 64 segmentos.
  A capacidade de memória e da GPU continua sendo finita: erros de capacidade são explícitos.
  A amostragem protege a memória com um orçamento de 40 milhões de células.

## Auto cull (só o que a câmera vê)

A cada vista, o preview testa a caixa de cada peça contra o campo de visão da câmera e o shader **nem avalia**
as que estão fora. Valem como peças: os filhos de `show()`, as cópias repetidas (instâncias de código) e as
primitivas da BVH. Uma peça fora do quadro cuja **sombra** cai na vista continua (a caixa é arrastada na direção
oposta ao sol até o chão), e uma margem nas bordas mantém a oclusão ambiente igual.

- Ganha mais com muitas peças pesadas perto da câmera e fora do quadro (câmera dentro de uma vila, de uma
  floresta, de um anel de objetos): num teste com 48 peças em volta da câmera, o quadro caiu ~28%.
- Vendo a cena inteira, não muda nada (tudo é visível).
- Peças animadas (posição, giro ou escala com `keys()`/`time`) também são cortadas: a caixa delas é a união das
  caixas em 120 instantes da duração da cena (mais os instantes das chaves), alargada pelo maior passo entre
  amostras. Num anel de 14 peças animadas em volta da câmera, o quadro caiu de ~71 ms para ~31 ms.
- Ficam de fora o chão infinito e as peças animadas de cenas **sem duração** (sem `timeline()`, chaves, roteiro
  nem sobreposições): ali o tempo corre sem fim e não há como cobrir o movimento todo.
- A imagem é a mesma; só os sulcos muito finos de padrões procedurais podem variar um pixel (o raio dá passos
  diferentes).
- Diagnóstico no console do editor: `tdi.cull()` devolve `{ on, visible, total }`; `tdi.cull(false)` desliga para
  comparar com `tdi.bench()`.
