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
