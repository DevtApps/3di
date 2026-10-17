# Exportar GLB

`export_glb(code=None, path="out/cena.glb", res=128)` grava glTF binário com malhas, cores, texturas
assadas em PNG embutido, esqueleto e animação. `check_glb(res, style, mode)` exporta e mostra o resultado
num motor padrão (three.js) ao lado do shader, com relatório por peça (triângulos, desvio em mm, volume).

Como a conversão funciona (para modelar pensando no GLB):
- **Peças:** cada filho de uma união simples (até 24 filhos) vira uma malha, com resolução própria:
  `res` células na maior dimensão **da peça**. Agrupe a cena em subgrupos nomeados.
- **Malha direta:** peças só de primitivas posicionadas/repetidas viram triângulos exatos.
  Subtrações, `smooth`, `merge`, deformações, fórmulas, `paint` e `facets` vão por amostragem.
- **Pintura e texturas** viram atlas PNG (cores nítidas); `bump` vira normal map.
- **Facetas** viram low poly de verdade: malha simplificada no tamanho da faceta, faces chapadas.
- Partes mais finas que a célula somem: o relatório acusa volume perdido. Suba `res` ou engrosse.

Fluxo: `check_glb(res=64)` para revisar, depois aumente. Não declare a exportação boa só pelo preview.
