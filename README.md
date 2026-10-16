# 3DI

Linguagem para criar cenas 3D com código, feita para ser escrita por IA (e por gente).
A sintaxe é um subconjunto de Python. A cena é compilada para **um único shader GLSL**
(SDF + raymarching) e renderizada no navegador, sem malhas e sem dependências.

```python
mesa = box(1.2, 0.05, 0.8, round=0.01).place(y=0.7).color("wood")
perna = cylinder(0.03, 0.7).place(0.52, 0, 0.32).mirror("xz").color("wood")
caneca = cylinder(0.045, 0.1).color("red").on(mesa, x=0.2)
show(plane(), mesa, perna, caneca)
```

## Rodar

```bash
python3 tools/serve.py
```

Abra http://localhost:8317. O editor recompila enquanto você digita (Ctrl+Enter força).

Para validar um script sem navegador (útil para agentes de IA):

```bash
node tools/check.mjs examples/mesa.3di
```

Esse comando mostra os erros com linha e dica, ou então o tamanho e a posição de cada peça nomeada com `.name()`.

## Convenções

- Unidades em **metros**. **y é para cima**, +x é a direita, +z é a frente.
- Toda forma nasce **centrada na origem**.
- Formas são imutáveis: cada método devolve uma nova forma (`a = a.at(1, 0, 0)`).
- No final do script, chame `show(...)` com o que deve aparecer. Listas são aceitas.

## Primitivas

| função | descrição |
|---|---|
| `box(w=1, h=w, d=w, round=0)` | caixa (largura x, altura y, profundidade z) |
| `cube(size=1, round=0)` | cubo |
| `sphere(r=0.5)` | esfera |
| `cylinder(r=0.5, h=1, round=0)` | cilindro em pé |
| `cone(r=0.5, h=1, top=0)` | cone em pé; `top>0` faz um tronco de cone |
| `torus(radius=0.5, thickness=0.1)` | rosca deitada (no plano xz) |
| `capsule(r=0.25, h=1)` | cápsula em pé (h é a altura total) |
| `ellipsoid(x=0.5, y=0.3, z=0.5)` | elipsoide (raios) |
| `pyramid(w=1, h=1)` | pirâmide de base quadrada |
| `prism(w=1, h=0.5, d=1)` | prisma triangular (telhado de duas águas): triângulo de base w e altura h, estendido em z |
| `plane()` | chão infinito em y=0 |

## Combinar

| | |
|---|---|
| `a + b` ou `group(a, b, ...)` | união |
| `a - b` ou `subtract(a, b, ...)` | subtração (recorta b de a) |
| `a & b` ou `intersect(a, b)` | interseção |
| `group(..., smooth=0.1)` | união suave (as formas se fundem), também em `subtract`/`intersect` |

## Posicionar

| método | o que faz |
|---|---|
| `.at(x, y, z)` / `.move(...)` | desloca a forma |
| `.place(x=0, y=0, z=0)` | coloca a **base** da forma (centro de baixo) no ponto |
| `.ground()` | apoia a forma no chão (y=0), sem mudar x/z |
| `.on(alvo, x=None, z=None, gap=0)` | apoia em cima do alvo, centrada nele (x/z são deslocamentos a partir do centro do alvo) |
| `.under(alvo, ...)` | coloca embaixo do alvo |
| `.beside(alvo, side="right", gap=0)` | encosta ao lado (`right`, `left`, `front`, `back`), com as bases alinhadas |
| `.rotate(x=0, y=0, z=0, pivot=None)` | gira em graus, em volta do próprio centro (ou do `pivot`) |
| `.scale(s, pivot=None)` | escala (número ou `(sx, sy, sz)`) |
| `.mirror("x")` | duplica espelhando no plano x=0 (`"xz"` gera 4 cópias). **Custa 0 primitivas extras** |
| `.repeat(x=1, y=1, z=1, spacing=None)` | grade de cópias centrada na forma. **Custa 0 primitivas extras** |

`.on()` com `plane()` como alvo mantém o x/z da forma.

## Modificar e pintar

| método | |
|---|---|
| `.round(r)` | arredonda (e engorda) a forma em r |
| `.shell(espessura)` | deixa oca (aparece quando recortada) |
| `.twist(graus)` | torce em volta do eixo vertical, de baixo até em cima |
| `.color(c)` | nome (`"red"`, `"wood"`, `"stone"`, `"vermelho"`…), `"#rrggbb"` ou `(r, g, b)` |
| `.material(color, rough, metal, glow)` | rugosidade 0..1, metal 0..1, brilho próprio |
| `.name("texto")` | nomeia a peça (aparece no painel Peças e no `check.mjs`) |

**Atenção com recortes rentes:** se a face do recorte coincide com a face da forma, sobra uma película
invisível na abertura. Faça o recorte atravessar a superfície (ex.: janela com profundidade maior e
deslocada alguns centímetros para fora).

## Texturas e deformação

| método | |
|---|---|
| `.texture(tipo, color2=None, size=None, axis="y")` | textura procedural: `noise`, `wood`, `marble`, `stripes`, `checker`, `bricks` (também em português: `madeira`, `mármore`, `tijolos`...) |
| `.displace(amount=0.05, size=0.3)` | deforma a superfície com ruído (rochas, terreno orgânico) |

A textura mistura a cor da forma com `color2` (padrão: um tom mais escuro; nos tijolos é a argamassa).
`size` é o tamanho do padrão em metros (anéis da madeira, casas do xadrez, comprimento do tijolo).
`axis` orienta madeira e listras: para uma tábua comprida em x, use `axis="x"`.
A textura acompanha o objeto: mover ou girar a forma não faz o padrão "escorregar".

```python
mesa = box(1.6, 0.06, 0.8).color("#b07a45").texture("wood", axis="x")
rocha = sphere(0.4).displace(0.14, 0.28).color("stone").texture("noise")
```

A cor mais interna vence: em `group(a.color("red"), b).color("gray")`, `a` continua vermelho e só `b` fica cinza.

## Animação

`time` é o tempo em segundos. Ele pode entrar em `at`/`move`, `rotate`, `scale` (uniforme) e no
`glow` de `material()`, e funciona com contas e com `sin`, `cos`, `abs`, `min`, `max`, `clamp`,
`lerp`, `fract` e `smoothstep`. `osc(a, b, period=2)` vai de `a` até `b` e volta, suavemente.

```python
helice = pas.rotate(z=time * 60)                          # 60° por segundo
bola = sphere(0.3).at(0, 0.3, 0).move(y=abs(sin(time * 3)))  # quicando
gema = gema.material(glow=osc(0.2, 1.5, period=1.5))       # pulsando
planeta = sphere(0.1).move(x=cos(time) * 2, z=sin(time) * 2)  # órbita
```

O script roda uma vez só: `time` vira código no shader e a GPU anima a cena. Por isso `time` não pode
entrar em `if`, `while` ou comparações (use `clamp`, `min`, `max` ou `smoothstep`), nem em tamanhos de
primitivas. O layout (`on`, `place`...) usa a posição em t = 0. O botão ⏸ do editor pausa a animação.

## Medir

Toda forma tem estas propriedades, calculadas pela caixa envolvente: `top`, `bottom`, `left`, `right`, `front`, `back`, `width`, `height`, `depth`, `size`, `center`, `x`, `y`, `z`.

```python
mesa = box(1.2, 0.05, 0.8).place(y=0.7)
vaso = cylinder(0.05, 0.2).place(mesa.right - 0.1, mesa.top, 0)
```

## Cena

`show(*formas)`, `camera(pos=(x,y,z), look=None, fov=45)`, `sun(x, y, z, color=None)`, `sky(cor)`, `fog(densidade)`.

## Python suportado

`def` com valores padrão e `*args`, `return`, `if/elif/else`, `for`, `while`, `break`, `continue`, listas e list comprehensions, tuplas, dicts, `lambda`, f-strings (`{x:.2f}`) e expressões `a if c else b`.

Funções disponíveis: `range`, `len`, `enumerate`, `zip`, `min`, `max`, `sum`, `abs`, `round`, `sqrt`, `sin`, `cos`, `tan`, `atan2`, `radians`, `degrees`, `floor`, `ceil`, `pi`, `lerp`, `clamp`, `linspace`, `print`, `random`, `uniform`, `randint`, `choice` e `seed` (aleatório determinístico).

Desempacotamento com `*` também funciona (`porta, *janelas = lista`, `[*a, *b]`).
Não há `import`, classes nem arquivos.

## Dicas para IA

- Prefira o layout semântico (`on`, `beside`, `place`, `mirror`) a fazer contas de coordenadas.
- Use `.mirror()` e `.repeat()` para simetrias e cópias, porque não pesam nada.
- Cópias feitas com loop custam uma primitiva cada. Quando são simples (formas posicionadas, giradas,
  coloridas e agrupadas com `group()`), elas vão para a BVH e cabem aos milhares (até 16.000).
- Subtrações, `smooth`, `mirror`, `repeat`, `twist`, `round` e `shell` viram código no shader. Até
  2.000 primitivas dentro delas; o shader demora mais para compilar quanto mais código houver
  (a vila, com 78, leva ~0,6 s). A compilação roda em segundo plano, sem travar o editor.
- Dê `.name()` às peças principais e rode `node tools/check.mjs` para conferir tamanhos e posições.
- Os erros dizem a linha e trazem uma dica do tipo "você quis dizer 'sphere'?".

## Exemplos

| arquivo | mostra |
|---|---|
| `vila.3di` | geração procedural: casas aleatórias, recortes com `repeat`, bosque, postes |
| `pinguim.3di` | personagem com uniões suaves, `mirror`, materiais |
| `arvore.3di` | recursão: árvore fractal com 600 primitivas (BVH) |
| `mesa.3di`, `castelo.3di`, `templo.3di` | layout semântico, booleanas, `repeat` |
| `basico.3di`, `organico.3di` | todas as primitivas, `smooth`, `twist` |
| `materiais.3di` | todas as texturas e `displace` |
| `animacao.3di` | moinho girando, bola quicando, gema pulsando, órbitas |

## Arquitetura

```
src/parser.js    lexer + parser (subconjunto de Python) → AST
src/interp.js    interpretador → árvore de formas
src/shapes.js    formas, transformações, layout e caixas envolventes
src/compiler.js  árvore → GLSL (mapD: distância, mapM: material) + BVH
                 primitivas simples viram dados numa textura (BVH percorrida no shader);
                 só o que é complexo (booleanas, smooth, mirror...) vira código
src/expr.js      expressões simbólicas com `time` (viram GLSL)
src/renderer.js  WebGL2: raymarching, sombras suaves, AO, PBR simples, texturas.
                 O main é uma máquina de estados que chama a cena em um único ponto: o
                 compilador da GPU copia a função da cena em cada chamada, então isso
                 mantém a compilação rápida. Compila em segundo plano (KHR_parallel_shader_compile).
src/main.js      editor + câmera orbital
```
