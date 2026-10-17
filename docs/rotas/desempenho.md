# Desempenho e limites

- O shader é compilado a cada mudança; o tempo cresce mais que linearmente com as primitivas **em código**
  (booleanas, `smooth`, `merge`, `paint`, deformações). Até ~100: menos de 1 s; ~250: ~6 s.
- Uniões simples de primitivas viram dados numa BVH (até 16000 instâncias) e quase não pesam na compilação.
  Limite de 2000 primitivas como código.
- `mirror`, `repeat` e `polar` não custam primitivas: prefira-os a cópias.
- Ruído (`displace`, texturas), `twist`, `bend` e `implicit` são caros por pixel.
- Monte primeiro os volumes, confira, e só então acrescente detalhes; teste partes isoladas em cenas pequenas.
