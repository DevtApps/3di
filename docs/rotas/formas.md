# Formas

## Primitivas (centradas na origem)

| função | |
|---|---|
| `box(w=1, h=w, d=w, round=0, bevel=0)` | caixa; `round` arredonda, `bevel` chanfra as arestas a 45° |
| `cube(size=1, round=0)` | cubo |
| `sphere(r=0.5)` | esfera |
| `ellipsoid(x, y, z)` | elipsoide (raios) |
| `cylinder(r=0.5, h=1, round=0)` | cilindro em pé |
| `cone(r=0.5, h=1, top=0)` | cone; `top > 0` = tronco de cone |
| `capsule(r=0.25, h=1)` | cápsula em pé (h total) |
| `torus(radius=0.5, thickness=0.1)` | rosca deitada (plano xz) |
| `pyramid(w=1, h=1)`, `prism(w, h, d)`, `wedge(w, h, d)` | pirâmide, prisma triangular (telhado), rampa |
| `hemisphere(r)`, `tube(r, thickness, h)` | cúpula, cano oco |
| `polygon(sides, r, h, round)`, `star(points, r, inner, h, round)` | pilar poligonal, estrela extrudada |
| `segment(a, b, r=0.05, r2=None)` | cápsula ligando os pontos a e b; com `r2` afina de r até r2 |
| `chain(points, r=0.05, smooth=0, curve=0)` | segmentos que afinam passando pelos pontos (rota `organico`) |
| `plane()` | chão infinito em y = 0 |

## Perfis

- `extrude(points, h=1, axis="z", round=0)`: polígono qualquer (3 a 128 pontos, côncavo vale).
  `axis="z"`: pontos `(x, y)` vistos de frente, `h` = profundidade. `axis="y"`: pontos `(x, z)` no chão, `h` = altura.
  As coordenadas valem como escritas: finalize com `.place()` / `.ground()`.
- `lathe(profile, smooth=0)`: gira um perfil `(raio, altura)` de baixo para cima em volta de y
  (vasos, colunas, rodas). Termine em raio 0 para fechar. `smooth` 1 a 8 arredonda.

## Por fórmula

`implicit(f, size=2, lip=0.5)`: `f(x, y, z)` negativo dentro, zero na superfície, recortado pela caixa `size`.
Use `hypot abs min max step clamp smoothstep sin cos exp ...` e `time`; comparações e `if` sobre x/y/z não
funcionam. O campo deve parecer uma distância; `lip` (0..1) encurta o passo para campos íngremes.
Prefira compor distâncias a polinômios de grau alto (cascas e buracos).

**Recortes rentes deixam película:** o cortador deve atravessar a superfície com folga.
