# Materiais, pintura e luz

A cor mais interna vence: em `group(a.color("red"), b).color("gray")`, `a` continua vermelho.

| | |
|---|---|
| `.color(c)` | cor |
| `.material(color=None, rough=None, metal=None, glow=None, coat=None)` | rugosidade 0..1, metal 0..1, brilho próprio (aceita `time`), `coat` = verniz 0..1 (plástico, carro, cerâmica) |
| `.texture(kind, color2=None, size=None, axis="y", bump=0, triplanar=False, range=None)` | `noise wood marble stripes checker bricks gradient mottle relief`; `bump` = relevo (normal map); `triplanar` projeta nos 3 eixos; `gradient` usa `range=(de, até)` |
| `.paint(region, blend=0.005, relief=0)` | pinta onde a forma está dentro de `region` (cor e material vêm da região); `relief` levanta (> 0) ou afunda (< 0) a superfície ali, de -0.2 a 0.2 m |
| `.facets(size=0.05, vary=0.1)` | visual low poly: facetas planas de ~size m, tom variando `vary` (0..0.5) |

## `paint`: o pincel genérico

A região é qualquer forma (esfera, caixa, elipsoide, grupo), no mesmo sistema de coordenadas da forma pintada.
Serve para: manchas de pelagem, olhos (pupila e brilho sobre a esfera), carinhas, metade de uma cor
(`box(4, 4, 4).at(2, 0, 0)` pinta todo o lado +x), faixas e listras, e com `relief` para
frisos, faixas em relevo, vincos, emendas e gravações sem modelar peças.
Pinte depois de fundir/juntar o corpo, para a pintura seguir as emendas.

## Luz e céu

- `sun(x, y, z, color=None)`: direção do sol. `sky(cor)`, `fog(density)`.
- `light(rim=0.6, fill=0.4, ao=1, rim_color=None)`: luz de contorno na silhueta, preenchimento do lado
  da câmera (sem sombra) e força da oclusão. Sem `light()` a cena tem só sol e céu.
