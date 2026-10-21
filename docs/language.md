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
python3 scripts/serve.py
```

Abra http://localhost:8327. O editor recompila enquanto você digita (Ctrl+Enter força).

Para exportar para glTF: `node scripts/export.mjs cena.3di` (veja "Exportar glTF / GLB").

Para validar um script sem navegador (útil para agentes de IA):

```bash
node scripts/check.mjs examples/mesa.3di
```

Esse comando mostra os erros com linha e dica, ou então o tamanho e a posição de cada peça nomeada com `.name()`.

Para **ver** a cena sem abrir o editor (também útil para agentes de IA conferirem o que montaram):

```bash
node scripts/render.mjs examples/mesa.3di mesa.png
node scripts/render.mjs examples/boneco.3di boneco.png --t 1.5
```

Gera um PNG com 4 vistas numa grade 2x2: **frente** (de +z), **lado** (de +x), **topo** (de +y) e
**perspectiva**, cada uma enquadrada pela caixa envolvente da cena e com rótulo e direção dos eixos;
no canto vai o tamanho da caixa (e o `t` em cenas animadas). Opções: `--t segundos` congela a
animação nesse instante (padrão 0; o enquadramento acompanha a cena naquele instante), `--size px`
é o lado de cada quadro (padrão 512) e `--cpu` força a renderização por software.
Erros de script saem como no `check.mjs`, com código de saída 1.
Precisa de Chrome ou Chromium instalado (ou do Chromium do Playwright em `~/.cache/ms-playwright`;
outro caminho vai em `CHROME=/caminho/do/chrome`). Usa a GPU e, se ela não tiver WebGL2 no modo
headless, cai para o SwiftShader, que funciona em qualquer máquina mas é bem mais lento.
No editor, o botão **Vistas** mostra as mesmas 4 vistas sobre a cena (clique ou Esc fecha).

## Convenções

- Unidades em **metros**. **y é para cima**, +x é a direita, +z é a frente.
- Toda forma nasce **centrada na origem**.
- Formas são imutáveis: cada método devolve uma nova forma (`a = a.at(1, 0, 0)`).
- No final do script, chame `show(...)` com o que deve aparecer. Listas são aceitas.

## Primitivas

| função | descrição |
|---|---|
| `box(w=1, h=w, d=w, round=0, bevel=0)` | caixa (largura x, altura y, profundidade z); `bevel` chanfra as arestas a 45° (placas, armaduras, móveis) |
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
| `segment(a, b, r=0.05, r2=None)` | cápsula ligando os pontos a e b (membros, canos, galhos); com `r2` afina de `r` até `r2` |
| `chain(points, r=0.05, smooth=0, curve=0)` | corrente de segmentos que afinam pelos pontos (caudas, pernas, orelhas; veja "Personagens e criaturas") |
| `polygon(sides=6, r=0.5, h=1, round=0)` | pilar de base poligonal regular (3 a 64 lados), em pé |
| `star(points=5, r=0.5, inner=None, h=0.2, round=0)` | estrela extrudada deitada, de 3 a 32 pontas em `r`; vales em `inner` (padrão `0.45*r`) |
| `wedge(w=1, h=1, d=1)` | rampa: sobe de -x até +x, com profundidade d em z |
| `extrude(points, h=1, axis="z", round=0)` | polígono qualquer extrudado (veja "Formas por perfil") |
| `lathe(profile, smooth=0)` | sólido de revolução a partir de um perfil (veja "Formas por perfil") |
| `hemisphere(r=0.5)` | meia esfera (cúpula), centrada como as outras formas |
| `tube(r=0.5, thickness=0.1, h=1)` | cano: cilindro oco atravessado |
| `implicit(f, size=2, lip=0.5)` | forma definida por fórmula (veja "Formas por fórmula") |

## Combinar

| | |
|---|---|
| `a + b` ou `group(a, b, ...)` | união |
| `a - b` ou `subtract(a, b, ...)` | subtração (recorta b de a) |
| `a & b` ou `intersect(a, b)` | interseção |
| `group(..., smooth=0.1)` | união suave (as formas se fundem), também em `subtract`/`intersect` |

| `merge(a, b, ..., r=0.03, profile="round", colors="sharp", seam=None, seam_width=None)` | junção com acabamento **só na linha de contato**: `profile` `round` (filete, a peça "nasce" da outra), `chamfer` (chanfro a 45°) ou `groove` (sulco, a emenda entre duas peças montadas). `colors="sharp"` mantém a cor de cada forma até o contato, `"blend"` mistura no filete; `seam` pinta a emenda com uma cor numa faixa de `seam_width` (padrão `r`). Também como método: `a.merge(b, r=...)` |

Diferente de `group(smooth=)`, que engorda tudo o que estiver perto e mistura as cores, o `merge`
mexe só onde as formas se encontram e cada uma continua com a sua cor: braço e ombro com sulco,
caneca e alça com filete, peças de máquina com chanfro.

`union(a, b, ...)` é um alias de `group`. Também há métodos encadeáveis:
`a.union(b, smooth=0)`, `a.subtract(b, smooth=0)` e `a.intersect(b, smooth=0)`.

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
| `.taper(top=0.5, bottom=1, axis="y")` | afunila: a seção vai de `bottom` (na base) até `top` (no topo) vezes o tamanho original |
| `.bend(angle, axis="y", toward=None, pivot=None)` | curva a forma: a ponta se inclina `angle` graus para o lado + de `toward`, com a base fixa em `pivot` (veja limites abaixo) |
| `.shear(x=0, z=0)` | inclina como um baralho: desloca x e z em metros por metro de altura |
| `.polar(count)` | repete em volta do eixo y (`count` cópias); a forma deve ficar afastada do eixo. Não custa primitivas |
| `.elongate(x=0, y=0, z=0)` | estica a forma sem deformá-la: acrescenta esse comprimento no meio (esfera vira cápsula) |
| `.color(c)` | nome (`"red"`, `"wood"`, `"stone"`, `"vermelho"`…), `"#rrggbb"` ou `(r, g, b)` |
| `.material(color, rough, metal, glow)` | rugosidade 0..1, metal 0..1, brilho próprio |
| `.name("texto")` | nomeia a peça (aparece no painel Peças e no `check.mjs`) |

## Personagens e criaturas

Bichos e personagens saem bem de **formas fundidas** (`group(..., smooth=)`), **manchas pintadas**
e, para o visual low poly, **facetas**:

| | |
|---|---|
| `chain(points, r=0.05, smooth=0, curve=0)` | segmentos que afinam passando pelos pontos. `r`: um raio, `(início, fim)` ou um raio por ponto. `curve` (0 a 8) arredonda a linha (Catmull-Rom, passa pelos pontos); `smooth` funde os trechos |
| `segment(a, b, r, r2)` | um trecho só, afinando de `r` (em a) até `r2` (em b): orelhas, garras, chifres, dedos |
| `.paint(region, blend=0.005, relief=0)` | pinta a forma onde ela está dentro de `region`: focinho, peito, patas, ponta da cauda, listras. A cor e o material vêm da região; `blend` suaviza a borda. `relief` (metros, -0.2 a 0.2) levanta (> 0: faixas, placas, joelheiras) ou afunda (< 0: vincos, emendas, gravações) a superfície na região |
| `.facets(size=0.05, vary=0.1)` | visual low poly: a superfície vira facetas planas (triângulos) de ~`size` metros, com o tom de cada uma variando `vary` (0 a 0.5) |

Receita: monte o corpo com elipsoides e `chain()` numa só `group(..., smooth=0.03)`, pinte as
manchas sobre o corpo já fundido com `paint()` (assim elas seguem as emendas) e aplique `facets()`
por último. Olhos, nariz e bigodes ficam fora do grupo facetado, lisos e brilhantes; pupila e brilho
do olho também são `paint()` sobre a esfera do olho.

```python
corpo = group(ellipsoid(0.27, 0.25, 0.3), cabeca, perna(1), perna(-1),
              chain([(-0.1, 0.1, -0.3), (-0.4, 0.3, -0.1), (-0.3, 0.7, 0)], r=(0.06, 0.05), curve=3),
              smooth=0.035).color("#d8762a")
pelo = corpo.paint(ellipsoid(0.12, 0.3, 0.12).at(0, 0.55, 0.2).color("#f5dcae"), blend=0.02)
gato = group(pelo.facets(0.11, 0.2), olho(1), olho(-1), bigodes)
```

As facetas vêm de uma grade de tetraedros: cada tetraedro que corta a superfície vira uma face
plana, como numa malha de marching tetrahedra. No preview são só sombreamento (a silhueta continua
lisa); no **GLB** a peça facetada é simplificada até triângulos do tamanho da faceta e sai com faces
chapadas e uma cor por face, um modelo low poly de verdade. Partes lisas e facetadas da mesma união
viram malhas separadas, para o olho não ser achatado nem o corpo refinado pelo detalhe do nariz.
A grade de facetas é fixa no espaço: numa peça que se move (animação), as facetas deslizam.

Veja `gato.3di` e `cachorro.3di`.

### Luz de estúdio e verniz

`light(rim=0.6, fill=0.4, ao=1, rim_color=None)` acrescenta ao sol uma luz de contorno (`rim`:
realça a silhueta, como nos renders de jogo) e uma de preenchimento vinda do lado da câmera
(`fill`, sem sombra); `ao` regula a oclusão de ambiente. Sem `light()`, a cena fica só com sol e céu.
`.material(coat=0.8)` põe uma camada de verniz por cima (reflexo nítido de plástico, carro, cerâmica).

### Modelar a partir de uma imagem

O botão **Referência** da IDE (ou arrastar uma imagem para a vista) põe a imagem por cima da cena,
com opacidade, escala, deslocamento e modo lado a lado; ela fica salva no navegador. Pelo MCP,
`set_reference(path, opacity, scale, x, y, side)` coloca a imagem e `compare_reference` devolve
referência | cena | sobreposição na vista atual: ajuste a câmera até a silhueta bater e corrija
proporções e cores comparando as três.

## Formas por perfil

`extrude(points, h=1, axis="z", round=0)` extruda um polígono qualquer (3 a 128 pontos, côncavo vale). Com
`axis="z"` os pontos `(x, y)` são o perfil visto de frente e `h` a profundidade; com `axis="y"` os pontos
`(x, z)` ficam no chão e `h` é a altura. `round` arredonda as quinas. As coordenadas dos pontos valem como
escritas: use `.place()` ou `.ground()` para posicionar.

`lathe(profile, smooth=0)` gira em volta do eixo y um perfil de pontos `(raio, altura)`, de baixo para cima
(vasos, colunas, taças, peças de xadrez, rodas). Termine em raio 0 para fechar; senão a ponta vira uma tampa
plana. `smooth` de 1 a 8 arredonda o perfil com uma curva suave.
Aceita 2 a 64 pontos com raios não negativos; após suavizar, o perfil fechado deve
ter no máximo 128 pontos. Reduza pontos ou `smooth` se exceder esse limite.

As deformações `taper`, `bend`, `shear`, `polar` e `elongate` exigem uma forma finita.
`taper.top` e `bottom` devem ser positivos; `elongate` aceita comprimentos não negativos.
Em `bend`, `axis` e `toward` devem ser diferentes: `toward` é x por padrão, exceto
quando `axis="x"`, caso em que é y. `pivot` é uma coordenada numérica ao longo de
`axis`, por padrão a base nesse eixo. Em `polar`, `count` é inteiro de 2 a 256:
desloque a peça para longe do eixo y antes de repetir e mova o conjunto depois.
Em `tube`, `thickness` deve ser positiva e menor que `r`.

```python
vaso = lathe([(0, 0), (0.35, 0), (0.45, 0.25), (0.3, 0.6), (0.18, 0.85), (0.26, 1.0), (0, 1.05)], smooth=4)
seta = extrude([(0, 0), (0.7, 0), (0.7, 0.35), (1, 0.35), (0.35, 1), (-0.3, 0.35), (0, 0.35)], h=0.25)
coluna = cylinder(0.25, 2).taper(top=0.7).twist(30)
```

## Formas por fórmula

`implicit(f, size=2, lip=0.5)` cria uma forma a partir de uma função de posição. `f(x, y, z)` devolve um
campo: negativo dentro, positivo fora, zero na superfície. O resultado é recortado pela caixa `size` (um
número ou `(largura, altura, profundidade)`). Dentro de `f` valem contas, `**`, `sqrt`, `sin`, `cos`, `tan`,
`abs`, `min`, `max`, `exp`, `log`, `hypot`, `atan2`, `sign`, `step`, `clamp`, `lerp`, `smoothstep`, `floor`,
`fract` e `time` (a forma anima). Comparações (`<`, `>`) e `if` não funcionam, porque `x`, `y` e `z` são
expressões e não números: use `min`, `max` e `step`.

O campo deve se parecer com uma distância (inclinação perto de 1 na superfície). `lip` multiplica o campo para
encurtar o passo do raio: `lip=1` só para distâncias exatas, `0.5` é um padrão seguro, `0.2` para campos que
crescem rápido (giroide). Polinômios de grau alto são quase planos perto da superfície e aparecem com cascas
ou buracos: componha distâncias (`hypot`, `abs`, `min`, `max`) em vez de equações algébricas.

```python
giroide = implicit(lambda x, y, z: abs(sin(x*7)*cos(y*7) + sin(y*7)*cos(z*7) + sin(z*7)*cos(x*7)) - 0.4, size=1.2, lip=0.25)
furada = implicit(lambda x, y, z: max(hypot(x, y, z) - 0.5, -(hypot(x, z) - 0.17)), size=1.1, lip=0.9)
```

Veja `formas.3di` (todas as primitivas e modificadores novos) e `formulas.3di`.

**Atenção com recortes rentes:** se a face do recorte coincide com a face da forma, sobra uma película
invisível na abertura. Faça o recorte atravessar a superfície (ex.: janela com profundidade maior e
deslocada alguns centímetros para fora).

## Texturas e deformação

| método | |
|---|---|
| `.texture(tipo, color2=None, size=None, axis="y", bump=0, triplanar=False, range=None)` | textura procedural: `noise`, `wood`, `marble`, `stripes`, `checker`, `bricks`, `gradient`, `mottle`, `relief` (também em português: `madeira`, `mármore`, `tijolos`, `degradê`, `manchas`, `relevo`...) |
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

### Cores: degradê, manchas, relevo (normal map) e triplanar

- **`gradient` (degradê)**: vai da cor da forma até `color2` ao longo de `axis`, cobrindo a caixa da forma
  (ou `range=(de, até)` em metros). Base escura e ponta clara: `cylinder(0.2, 1).color("#1d6b2a").texture("gradient", color2="#c8e26a")`.
- **`mottle` (manchas)**: variação orgânica suave entre a cor e `color2`, boa para pedra, terra e folhagem.
- **`relief`**: só relevo, sem mudar a cor (pele de laranja, casca, pedra áspera).
- **`bump=0.3`**: dá relevo (normal map) usando a própria textura: sulcos nos tijolos, anéis da madeira, veios do mármore.
  Valores de 0.1 (sutil) a 1 (forte). Na tela é calculado por pixel; no `.glb` vira um normal map de verdade.
- **`triplanar=True`**: projeta `stripes`, `checker` e `bricks` nos três eixos e mistura pela normal, então o
  padrão aparece em qualquer face (o topo de um bloco de tijolos ganha tijolos em vez de listras).

Para montar paletas: `mix(a, b, t)` mistura duas cores, `hsv(matiz, sat, brilho)` cria uma cor e
`vary(cor, hue=15, sat=0.1, val=0.15)` sorteia uma variação (reprodutível com `seed()`).

```python
tijolo = box(1).color("#a8553a").texture("bricks", size=0.3, bump=0.6, triplanar=True)
folha = hsv(110, 0.7, 0.55)
folha2 = vary(folha, hue=12, val=0.12)
```

## Geradores (grama, plantas, árvores, pessoas e veículos)

Funções prontas que montam objetos complexos com poucas primitivas. Todas aceitam `style` (do `"lowpoly"`
ao `"realistic"`, passando por `"stylized"`) e `seed` (reprodutível); sem `seed`, usam o `seed()` da cena.

`grass(width=2, depth=None, kind="meadow", style="stylized", height=None, density=1, color=None, tip=None, flowers=0, sway=0, soil=None, seed=None)`
monta um canteiro de grama. Os dois eixos são independentes:

| `kind` (que grama) | |
|---|---|
| `lawn` | gramado curto de jardim |
| `meadow` | campo de grama média |
| `tall` | capim alto que pende |
| `dry` | grama seca de savana |
| `tufts` | touceiras de folhas arqueadas |
| `wheat` | trigo: hastes finas com espigas |
| `clover` | trevo baixo salpicado de flores |

| `style` (como é desenhada) | |
|---|---|
| `lowpoly` | poucas lâminas grandes e facetadas, cores chapadas |
| `stylized` | lâminas limpas com degradê da base para a ponta |
| `realistic` | lâminas finas e arqueadas, mais camadas, variação natural de cor |

`density` (1 normal, 0.5 ralo, 2 denso), `height` (m), `color`/`tip` (base e ponta), `flowers` (0 a 2),
`sway` (graus de balanço animado pelo vento) e `soil` (cor de uma camada de terra embaixo) ajustam o resultado.
Veja `gramas.3di` (todos os tipos) e `gramas-estilos.3di` (os três estilos lado a lado).

`plant(kind="flower", style="stylized", height=None, color=None, density=1, seed=None)` — `kind`:
`flower`, `daisy`, `lavender`, `fern`, `bush`, `cactus`, `mushroom`. `color` é a cor de destaque (pétalas, chapéu,
espigas) ou a da folhagem; `density` faz touceiras (mais flores, hastes, frondes ou blocos de folhas).
Veja `plantas.3di` (todos os tipos nos três estilos).

`tree(kind="oak", style="stylized", height=None, trunk=None, leaves=None, seed=None)` — `kind`: `oak`, `pine`,
`birch`, `palm`, `willow`, `dead`, `round` (pirulito), `bonsai`. No `lowpoly` as copas são blocos facetados de
cor chapada; no `stylized`, blocos lisos com degradê; no `realistic`, mais galhos, copas rugosas com manchas
e casca com relevo. Veja `arvores.3di` (os oito tipos) e `arvores-estilos.3di` (os três estilos).

```python
bosque = [tree(kind="pine", style="lowpoly", seed=i).at(i * 3, 0, 0) for i in range(5)]
jardim = [plant(kind="daisy", density=4, seed=1), plant(kind="fern", style="realistic").at(1, 0, 0)]
```

`person(style="stylized", height=None, build="average", skin=None, hair=None, outfit="casual", pose="stand", seed=None)`
— `build`: `slim`, `average`, `stocky`, `child`, `elder` (altura padrão 1,75 / 1,75 / 1,75 / 1,1 / 1,65 m); `hair`: `short`,
`long`, `bald`, `ponytail`, `curly`, `bun`; `outfit`: `casual`, `suit`, `sport`, `dress`, `uniform`; `pose`: `stand`,
`walk`, `sit` (sem cadeira: ponha uma caixa embaixo), `arms_up`. Pele, cabelo e roupa saem do `seed`; `skin` aceita uma cor.
`lowpoly` monta o corpo em caixas; `stylized` em formas lisas; `realistic` ganha pescoço, orelhas, nariz, mãos,
sapatos com sola e tecido com relevo. Veja `pessoas.3di` e `pessoas-poses.3di`.

`vehicle(kind="car", style="stylized", length=None, color=None, wheels_angle=0, seed=None)` — `kind`: `car`,
`hatch`, `suv`, `pickup`, `van`, `bus`, `truck`, `tractor`, `bike`, `motorbike`. O veículo anda para +z, o eixo das
rodas é x e as rodas tocam y = 0. `color` pinta a carroceria, `length` redimensiona e `wheels_angle` gira as rodas em
graus: `wheels_angle=time * 360` faz as rodas girarem (cenas assim ficam animadas e compilam em alguns segundos).
Veja `veiculos.3di` e `veiculos-estilos.3di`.

Orçamento: formas simples (plantas, árvores, pessoas, veículos) vão para uma estrutura de dados (BVH) e compilam
rápido mesmo aos centenas (500 primitivas em menos de 1 s). A grama usa `repeat`/recorte, que viram código
no shader: um canteiro custa de 20 a 80 primitivas e ~0,5 s, e passando de uns 150 primitivas desse tipo no
total o shader leva vários segundos. Prefira um canteiro grande a muitos pequenos (ele divide a grade
sozinho quando passa de 9000 células).

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

## Rig (esqueleto)

```python
esq = skeleton("boneco")
quadril = esq.bone("quadril", head=(0, 0.95, 0))
coxa = esq.bone("coxa.E", head=(0.1, 0.93, 0), parent=quadril)
canela = esq.bone("canela.E", head=(0.1, 0.5, 0), tail=(0.1, 0.1, 0), parent=coxa)

perna = segment((0.1, 0.93, 0), (0.1, 0.5, 0), 0.07).bind(coxa)   # parte presa ao osso
coxa.rotate(x=-sin(time * 5) * 28)                                 # pose / animação
show(group(perna, ..., smooth=0.025), esq.debug())                 # debug() desenha os ossos
```

- `esq.bone(nome, head, tail=None, parent=None)`: `head` é a junta, onde o osso gira; `parent` pode
  ser o osso ou o nome dele.
- `forma.bind(osso)`: a forma, modelada na pose de repouso, passa a seguir o osso e toda a cadeia de pais.
- `osso.rotate(x, y, z)` e `osso.move(x, y, z)` somam à pose e aceitam `time`.
- Cada parte é rígida (peso 1 no osso). Com `group(..., smooth=...)` as juntas se fundem no render.
- `animation(duration=4, fps=30)` define o ciclo exportado para o glTF. Escolha `duration` para o ciclo
  fechar (ex.: um passo com `sin(time * 5)` repete a cada 2π/5 s).

## Conferir o GLB

O botão **Conferir GLB** (ou a ferramenta MCP `check_glb`) exporta a cena e abre o resultado num motor padrão
(three.js) no mesmo ângulo do shader: **Dividido** compara a forma exata com a malha exportada; **Triângulos**
mostra a densidade (faces planas têm poucos, curvas têm mais) e **Normais** o sombreamento. O relatório lista,
por peça, os triângulos, o **desvio** da malha em relação à forma (em mm, contra o tamanho da célula) e o
**volume** (quanto da forma virou malha).

Há duas rotas de conversão, escolhidas por peça:
- **direta**: peças feitas de primitivas (caixa, esfera, cone, pirâmide, cilindro, cápsula, toro, prisma,
  `polygon`/`star`/`wedge`/`extrude`, `lathe`, inclusive com `round`) posicionadas, unidas, repetidas
  (`repeat`, `mirror`, `polar`) e recortadas viram triângulos direto da primitiva: exatos, nada se perde
  (pontas e lâminas finas como as da grama incluídas). É o padrão.
- **grade**: subtrações, uniões suaves, deformações (`bend`, `taper`...), `displace`, fórmulas (`implicit`)
  e o chão são amostrados numa grade. Partes mais finas que a célula podem sumir; o relatório mede isso.

Isso não depende do formato: OBJ ou FBX teriam a mesma diferença, porque ela vem da conversão, não do arquivo.

## Exportar glTF / GLB

```bash
node scripts/export.mjs examples/boneco.3di out/boneco.glb --res 128
```

No editor, o botão **GLB** faz o mesmo e baixa o arquivo. O resultado:

- **Malhas:** geradas do SDF por *dual contouring*, preservando quinas, e simplificadas
  por erro quádrico para reduzir triângulos em faces planas. As partes podem ser
  processadas em paralelo por workers; se isso falhar, há retorno ao processamento sequencial.
- **Materiais:** peças sem textura usam cor por vértice. Texturas procedurais viram
  atlas PNG embutidos no GLB, com UV; `bump` também gera normal maps PNG.
  O GLB contém as imagens: a exportação não grava PNGs separados automaticamente.
- **Detalhe:** `--res` são as células na maior dimensão de cada peça, independente do
  tamanho total da cena. Eixos finos buscam pelo menos seis camadas; arredondamentos
  podem refinar a grade, e um limite de células contém o uso de memória.
  A simplificação limita o tamanho das arestas em peças texturizadas para preservar o padrão.
- **Esqueleto:** vira um `skin` glTF (juntas na pose de repouso), e as rotações e movimentos dos ossos
  com `time` viram uma animação amostrada.
- **O que fica parado:** `time` fora de ossos (ex.: um `rotate(y=time * 90)` direto na forma) é
  exportado em t = 0. Para animar no glTF, use um osso.
- **Chão:** `plane()` vira um piso recortado em volta da cena.

Para conferir num motor padrão, abra `scripts/viewer.html?file=/out/boneco.glb` com o servidor rodando
(three.js, toca a animação) ou arraste um `.glb` para a página.

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

Funções disponíveis: `range`, `len`, `enumerate`, `zip`, `min`, `max`, `sum`, `abs`, `round`,
`sqrt`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`, `exp`, `log`, `hypot`,
`sign`, `step`, `radians`, `degrees`, `floor`, `ceil`, `lerp`, `clamp`, `smoothstep`,
`fract`, `osc`, `linspace`, `print`, `random`, `uniform`, `randint`, `choice`, `seed`
(aleatório determinístico), `mix`, `hsv` e `vary` (cores). Constantes: `pi` e `tau`.
As funções aceitas com coordenadas simbólicas estão em "Formas por fórmula";
isso não inclui automaticamente todas as funções numéricas.

Desempacotamento com `*` também funciona (`porta, *janelas = lista`, `[*a, *b]`), inclusive com
tuplas aninhadas no `for` (`for (a, b), c in ...`).
Não há `import`, classes nem arquivos.

## Dicas para IA

- Prefira o layout semântico (`on`, `beside`, `place`, `mirror`) a fazer contas de coordenadas.
- Use `.mirror()` e `.repeat()` para simetrias e cópias, porque não pesam nada.
- Cópias feitas com loop custam uma primitiva cada. Quando são simples (formas posicionadas, giradas,
  coloridas e agrupadas com `group()`), elas vão para a BVH, sem teto fixo de instâncias; a capacidade depende da GPU.
- Subtrações, `smooth`, `mirror`, `repeat`, `twist`, `round` e `shell` viram código no shader, sem teto fixo de primitivas;
  o shader demora mais para compilar quanto mais código houver
  (a vila, com 78, leva ~0,6 s). A compilação roda em segundo plano, sem travar o editor.
- Dê `.name()` às peças principais e rode `node scripts/check.mjs` para conferir tamanhos e posições.
- Depois, rode `node scripts/render.mjs cena.3di cena.png` e olhe a imagem: as vistas de frente, lado e
  topo mostram peças flutuando, atravessadas ou fora do lugar que os números não deixam ver.
- Os erros dizem a linha e trazem uma dica do tipo "você quis dizer 'sphere'?".

## Exemplos

| arquivo | mostra |
|---|---|
| `vila.3di` | geração procedural: casas aleatórias, recortes com `repeat`, bosque, postes |
| `pinguim.3di` | personagem com uniões suaves, `mirror`, materiais |
| `gato.3di`, `cachorro.3di` | bichos low poly: `chain`, `paint` (pelagem), `facets` e olhos com pupila e brilho |
| `cemiterio.3di` | diorama completo só com funções genéricas: `repeat` (lajotas, grade), `merge`, `bevel`, `polar` (abóboras), `chain` (árvores secas), `facets`, `paint` |
| `robo.3di` | boneco de brinquedo só com funções genéricas: `merge` nas junções, `bevel`, `paint` com relevo, `light()` e verniz |
| `arvore.3di` | recursão: árvore fractal com 600 primitivas (BVH) |
| `mesa.3di`, `castelo.3di`, `templo.3di` | layout semântico, booleanas, `repeat` |
| `basico.3di`, `organico.3di` | todas as primitivas, `smooth`, `twist` |
| `materiais.3di` | todas as texturas e `displace` |
| `animacao.3di` | moinho girando, bola quicando, gema pulsando, órbitas |
| `boneco.3di` | personagem com esqueleto andando em círculo (exporta com skin e animação) |

## Arquitetura

```
src/parser.js    lexer + parser (subconjunto de Python) → AST
src/interp.js    interpretador → árvore de formas
src/shapes.js    formas, transformações, layout e caixas envolventes
src/compiler.js  árvore → GLSL (mapD: distância, mapM: material) + BVH
                 primitivas simples viram dados numa textura (BVH percorrida no shader);
                 só o que é complexo (booleanas, smooth, mirror...) vira código
src/expr.js      expressões simbólicas com `time` (viram GLSL)
src/rig.js       esqueleto, ossos e bind (resolvidos em rotações antes de compilar)
src/sdf.js       o mesmo SDF avaliado em JavaScript (com BVH), para a exportação
src/profile.js   perfis 2D para extrusão e revolução
src/mesh.js      SDF -> malha (dual contouring, avaliando só perto da superfície)
src/simplify.js  simplificação de malhas por erro quádrico
src/gltf.js      escrita de .glb (buffers, skin, animação)
src/export.js    cena -> partes -> malhas -> .glb
src/parallel-*.js e src/parts-worker-*.js: exportação de peças em workers web/Node
src/renderer.js  WebGL2: raymarching, sombras suaves, AO, PBR simples, texturas.
                 O main é uma máquina de estados que chama a cena em um único ponto: o
                 compilador da GPU copia a função da cena em cada chamada, então isso
                 mantém a compilação rápida. Compila em segundo plano (KHR_parallel_shader_compile).
src/main.js      editor + câmera orbital + 4 vistas; window.tdi é a API de automação
scripts/render.mjs Chrome headless (protocolo DevTools por pipe, sem npm) → tdi.views() → PNG
```

## IDE e app desktop

```bash
npm install                        # Monaco local (o editor funciona offline)
node scripts/app.mjs cena.3di        # abre a IDE numa janela do Chrome em modo app
node scripts/install-desktop.mjs     # atalho "3DI (dev)" no menu, sem encobrir o app instalado (--default associa os .3di; --uninstall remove)
```

- **Editor (Monaco):** cores, autocomplete pelo contexto (métodos de forma, de osso e de esqueleto,
  cores, texturas e parâmetros), assinaturas, documentação ao passar o mouse, snippets e erros na linha.
- **Arquivos:** Novo/Abrir/Salvar (Ctrl+O, Ctrl+S, Ctrl+Shift+S); PNG e GLB abrem "salvar como".
- **Câmera:** botões Frente/Lado/Topo/Persp.; clique numa peça do painel Peças para enquadrá-la.
- **MCP** (`.mcp.json`, `src/services/mcp.ts`): `describe_language`, `check_script`, `get_script`,
  `set_script`, `save_script`, `screenshot` (vista, peça, grade de 4 vistas, instante), `set_reference`, `compare_reference`, `set_camera`,
  `frame`, `list_parts`, `set_time`, `export_glb`. O ponto verde no editor indica a ponte conectada.
  A IDE usa 8327 e o MCP HTTP usa 8328 no desenvolvimento; no app instalado usam 8317 e 8318.

## Verificação de regressões

`npm test` valida os exemplos, exportações GLB, comunicação com o worker e as proteções do servidor local.
Os testes HTTP abrem uma porta temporária em loopback.

A execução de scripts, geração de GLSL, cálculo de caixas animadas e exportação GLB da IDE
rodam em Web Workers. Uma nova compilação cancela a execução anterior; cada tarefa tem
limite de 120 segundos. `window.tdi.views()` devolve uma Promise com a imagem.

A ponte HTTP usa token e verifica Host/Origin. A IDE obtém a sessão por uma requisição
na mesma origem; clientes HTTP da ponte enviam `X-3DI-Token` e SSE usa o token na URL.
A resolução de exportação deve ser um inteiro positivo representável com precisão. Não há teto fixo nem redução automática de resolução. A malha direta aumenta o detalhe das curvas com a resolução; a amostragem mantém uma proteção de memória de 40 milhões de células e informa erro quando excedida.
