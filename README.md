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

Para exportar para glTF: `node tools/export.mjs cena.3di` (veja "Exportar glTF / GLB").

Para validar um script sem navegador (útil para agentes de IA):

```bash
node tools/check.mjs examples/mesa.3di
```

Esse comando mostra os erros com linha e dica, ou então o tamanho e a posição de cada peça nomeada com `.name()`.

Para **ver** a cena sem abrir o editor (também útil para agentes de IA conferirem o que montaram):

```bash
node tools/render.mjs examples/mesa.3di mesa.png
node tools/render.mjs examples/boneco.3di boneco.png --t 1.5
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
| `segment(a, b, r=0.05)` | cápsula ligando os pontos a e b (membros, canos, galhos) |

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

## Exportar glTF / GLB

```bash
node tools/export.mjs examples/boneco.3di out/boneco.glb --res 128
```

No editor, o botão **GLB** faz o mesmo e baixa o arquivo. O resultado:

- **Malhas:** uma por forma mostrada (ou por parte presa a osso), com normais e cor por vértice
  (texturas incluídas), geradas do SDF por *surface nets*.
- **Detalhe:** `--res` são as células na maior dimensão da cena; peças finas ganham voxel menor no eixo
  em que são finas.
- **Esqueleto:** vira um `skin` glTF (juntas na pose de repouso), e as rotações e movimentos dos ossos
  com `time` viram uma animação amostrada.
- **O que fica parado:** `time` fora de ossos (ex.: um `rotate(y=time * 90)` direto na forma) é
  exportado em t = 0. Para animar no glTF, use um osso.
- **Chão:** `plane()` vira um piso recortado em volta da cena.

Para conferir num motor padrão, abra `tools/viewer.html?file=/out/boneco.glb` com o servidor rodando
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

Funções disponíveis: `range`, `len`, `enumerate`, `zip`, `min`, `max`, `sum`, `abs`, `round`, `sqrt`, `sin`, `cos`, `tan`, `atan2`, `radians`, `degrees`, `floor`, `ceil`, `pi`, `lerp`, `clamp`, `linspace`, `print`, `random`, `uniform`, `randint`, `choice` e `seed` (aleatório determinístico).

Desempacotamento com `*` também funciona (`porta, *janelas = lista`, `[*a, *b]`), inclusive com
tuplas aninhadas no `for` (`for (a, b), c in ...`).
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
- Depois, rode `node tools/render.mjs cena.3di cena.png` e olhe a imagem: as vistas de frente, lado e
  topo mostram peças flutuando, atravessadas ou fora do lugar que os números não deixam ver.
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
src/mesh.js      SDF -> malha (surface nets, avaliando só perto da superfície)
src/gltf.js      escrita de .glb (buffers, skin, animação)
src/export.js    cena -> partes -> malhas -> .glb
src/renderer.js  WebGL2: raymarching, sombras suaves, AO, PBR simples, texturas.
                 O main é uma máquina de estados que chama a cena em um único ponto: o
                 compilador da GPU copia a função da cena em cada chamada, então isso
                 mantém a compilação rápida. Compila em segundo plano (KHR_parallel_shader_compile).
src/main.js      editor + câmera orbital + 4 vistas; window.tdi é a API de automação
tools/render.mjs Chrome headless (protocolo DevTools por pipe, sem npm) → tdi.views() → PNG
```

## IDE e app desktop

```bash
npm install                        # Monaco local (o editor funciona offline)
node tools/app.mjs cena.3di        # abre a IDE numa janela do Chrome em modo app
node tools/install-desktop.mjs     # atalho "3DI" no menu e .3di abrindo no app (--uninstall remove)
```

- **Editor (Monaco):** cores, autocomplete pelo contexto (métodos de forma, de osso e de esqueleto,
  cores, texturas e parâmetros), assinaturas, documentação ao passar o mouse, snippets e erros na linha.
- **Arquivos:** Novo/Abrir/Salvar (Ctrl+O, Ctrl+S, Ctrl+Shift+S); PNG e GLB abrem "salvar como".
- **Câmera:** botões Frente/Lado/Topo/Persp.; clique numa peça do painel Peças para enquadrá-la.
- **MCP** (`.mcp.json`, `tools/mcp.mjs`): `describe_language`, `check_script`, `get_script`,
  `set_script`, `save_script`, `screenshot` (vista, peça, grade de 4 vistas, instante), `set_camera`,
  `frame`, `list_parts`, `set_time`, `export_glb`. O ponto verde no editor indica a ponte conectada.
  O app e o MCP compartilham o mesmo servidor (porta 8317).
