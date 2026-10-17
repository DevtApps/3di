# Combinar formas

| | |
|---|---|
| `a + b`, `group(a, b, ..., smooth=0)` | união; `smooth` funde tudo o que estiver perto e mistura as cores |
| `a - b`, `subtract(a, b, ..., smooth=0)` | recorta b de a |
| `a & b`, `intersect(a, b, smooth=0)` | interseção |
| `merge(a, b, ..., r=0.03, profile="round", colors="sharp", seam=None, seam_width=None)` | **junção com acabamento só na linha de contato** |

Também como métodos: `a.union(b, smooth=)`, `a.subtract(...)`, `a.intersect(...)`, `a.merge(b, r=...)`.

## `merge`: junções reais

- `profile="round"`: filete (a peça "nasce" da outra: alça de caneca, galho no tronco).
- `profile="chamfer"`: chanfro a 45° na junção (peças de máquina).
- `profile="groove"`: sulco ao longo do contato (peças montadas: braço no ombro, tampa na caixa).
- `colors="sharp"`: cada forma mantém sua cor até o contato; `"blend"`: mistura no filete.
- `seam="#222"`: pinta a emenda com uma cor numa faixa de `seam_width` (padrão `r`).

Use `merge` em vez de `group(smooth=)` quando as partes não devem engordar nem misturar cor.
`group(smooth=)` é o certo para corpos orgânicos (rota `organico`).

## Repetir sem custo

| | |
|---|---|
| `.mirror("x")` | duplica espelhando no plano x = 0 (`"xz"` = 4 cópias) |
| `.repeat(x=1, y=1, z=1, spacing=None)` | grade de cópias centrada na forma |
| `.polar(count)` | cópias em volta do eixo y; afaste a peça do eixo antes, mova o conjunto depois |

Essas três **não acrescentam primitivas**: use para grades, cercas, telhas, gomos, raios de roda.
Todas as cópias têm a mesma cor e material.
