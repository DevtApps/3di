# Peças duras (brinquedos, robôs, máquinas, móveis)

| necessidade | ferramenta genérica |
|---|---|
| placas e blocos com quina facetada | `box(..., bevel=0.04, round=0.02)` |
| peça que nasce de outra (sem emenda) | `merge(a, b, r=0.03)` (filete) |
| peças montadas, com emenda visível | `merge(a, b, r=0.02, profile="groove")` |
| encontro chanfrado | `merge(..., profile="chamfer")` |
| faixa, cinto, joelheira, botão em relevo | `paint(regiao.color(c), relief=0.012)` |
| vinco, emenda entre cores, gravação | `paint(box fina, relief=-0.006)` |
| duas cores por lado | `paint(box(4, 4, 4).at(2, 0, 0).color(c2))` |
| plástico com brilho | `material(rough=0.4, coat=0.6)` + `light(rim=0.6, fill=0.4)` |
| logos e emblemas | `extrude(pontos, h=0.03)` colado na superfície |

Escreva as funções do seu objeto no script (`metades(forma, c1, c2)`, `faixa(forma, y, h, cor)`,
`membro(pontos, raios, cor)`, `braco(lado)`) e reutilize. Veja `robo.3di`.

Cuidados: o relevo exige borda com rampa (`blend` vira pelo menos 1,5 x relevo automaticamente);
cortadores devem atravessar a peça; um `merge` só age onde as formas se tocam.
