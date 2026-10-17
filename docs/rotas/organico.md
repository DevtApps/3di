# Personagens e criaturas (formas orgânicas)

Receita genérica (vale para gato, cachorro, pássaro, monstro, pessoa estilizada):

1. **Corpo:** elipsoides (quadril, peito, cabeça, bochechas, focinho) numa só `group(..., smooth=0.03)`.
2. **Membros, caudas, pescoços, orelhas:** `chain(points, r=(início, fim), curve=2..3)`
   ou `segment(a, b, r, r2)` para um trecho que afina. Orelha achatada: segmento + `.scale((1, 1, 0.4))`.
3. **Pelagem:** `paint()` sobre o corpo já fundido: focinho, peito, patas (`box` baixa no chão), ponta da cauda,
   listras (`repeat` de caixas finas), interior das orelhas.
4. **Low poly (opcional):** `.facets(0.08, 0.15)` no corpo pintado.
5. **Olhos e detalhes lisos** fora do grupo facetado: esfera do olho + `paint` da pupila e do brilho
   (`material(glow=)` no brilho), contorno escuro (esfera um pouco maior atrás). Bigodes: `segment` finos.

```python
def olho(lado):
    g = sphere(0.06).color("#7fb33a").material(rough=0.15)
    g = g.paint(ellipsoid(0.024, 0.05, 0.03).at(0, 0, 0.05).color("#101010"))
    g = g.paint(sphere(0.014).at(0.014, 0.026, 0.053).color("white").material(glow=0.6))
    return group(sphere(0.069).at(0, 0, -0.01).color("#2a1a10"), g).at(0.1 * lado, 0.98, 0.27)

corpo = group(ellipsoid(0.27, 0.25, 0.3), ellipsoid(0.25, 0.22, 0.22).at(0, 0.7, 0.1),
              chain([(-0.1, 0, -0.3), (-0.4, 0.2, -0.1), (-0.3, 0.6, 0)], r=(0.06, 0.05), curve=3),
              smooth=0.035).color("#d8762a")
pelo = corpo.paint(ellipsoid(0.12, 0.25, 0.1).at(0, 0.3, 0.22).color("#f5dcae"), blend=0.02)
show(group(pelo.facets(0.1, 0.18), olho(1), olho(-1)))
```

Defina partes como funções (`perna(lado)`, `orelha(lado)`) e use `lado = ±1` para simetria
com variação; `mirror("x")` serve para pares idênticos já posicionados.
Veja `gato.3di`, `cachorro.3di`, `pinguim.3di`.
