# Plano: formas mais complexas com código simples

Objetivo: que uma IA (ou pessoa) descreva um objeto rico — uma casa longa viking, um barco, um
personagem — em poucas linhas de intenção, sem calcular coordenadas nem empilhar centenas de
primitivas à mão, e que o renderizador aguente o resultado.

## Diagnóstico

O 3DI já tem bastante coisa: primitivas, CSG com `smooth`/`merge`, layout semântico (`on`, `beside`,
`place`), `mirror`/`repeat`/`polar` sem custo, perfis (`extrude`, `lathe`), deformações (`taper`,
`bend`, `shear`, `twist`), `implicit`, `chain`, `paint`, texturas, geradores (grama, árvores,
pessoas, veículos), rig e export GLB. O que ainda trava cenas complexas:

1. **Falta estrutura hierárquica.** Para uma fachada com portas, janelas e vigas é preciso calcular
   onde cada peça cai. Não há como dizer "divida esta parede em 3 faixas e ponha uma porta no meio".
2. **Falta curva como cidadã de primeira classe.** `chain` e `lathe` cobrem casos, mas não há
   `sweep` (perfil ao longo de um caminho) nem `loft` (entre perfis). Casco de barco, telhado
   curvo, corrimão, corda, presa e asa exigem truques.
3. **Detalhe de superfície custa peças.** Tábuas, telhas, palha, pedras de muro e entalhes viram
   loops com uma primitiva cada, ou ficam de fora — por isso as cenas parecem "de bloquinhos"
   (a vila nórdica foi o caso recente).
4. **Componentes não se encaixam.** Uma função `casa()` devolve uma forma, mas não diz onde fica a
   porta, a cumeeira ou o ponto de apoio; quem usa refaz as contas.
5. **O shader cresce mal.** A compilação é superlinear no código inline (`repeat`, `subtract`,
   `smooth`...). 30 casas iguais compiladas como 30 trechos de código são 30 vezes o custo.

## O que outras ferramentas fazem (e o que vale copiar)

| referência | ideia | para o 3DI |
|---|---|---|
| **CGA shape / CityEngine** (Müller et al.) | gramática de divisão: `split`, `repeat`, `comp` (decompor em faces); cada regra trabalha num "escopo" local | `split`, `faces`, `tile` (fase 1) |
| **Curv** (Doug Moen) | linguagem funcional de SDF que compila para shader; toda a biblioteca escrita na própria linguagem; cor e animação como campos | biblioteca padrão em 3DI, campos de cor (`paint` já vai nessa linha) |
| **hg_sdf** (Mercury) | catálogo de operadores de junção: chanfro, degraus, colunas, sulco, lingueta; repetição de domínio com espelho | novos `profile` em `merge`/`group` (fase 2) |
| **Inigo Quilez** (artigos de SDF) | `sweep`/`revolution`, `onion`, `elongate`, curvas de Bézier exatas, bounding volumes no raymarch | `sweep`, `bezier`, `loft` (fase 1) |
| **Dreams / Clayxels / Claybook** | edições SDF avaliadas em hierarquia e **cacheadas em blocos 8³** (octree); render do cache, não da fórmula | assar peças estáticas pesadas em textura 3D (fase 3) |
| **libfive / Fidget** (Matt Keeter) | expressão vira "fita" simplificada por **aritmética de intervalos**: em cada região só sobra o que importa | poda por região/BVH de nós de código (fase 3) |
| **ShapeAssembly** (Jones et al.) | programas de cuboides com **pontos de encaixe** (`attach`): a forma diz onde se liga | âncoras nomeadas em componentes (fase 1) |
| **CadQuery / build123d**, CAD-Recode, CAD-Coder | LLMs acertam mais código CAD quando ele é **intenção + seleção** ("faces de cima, chanfre 2 mm") e quando planejam antes (chain-of-thought) | seletores e um modo "esboço → detalhe" documentado |
| **OpenSCAD / Geometry Nodes** | módulos parametrizados; distribuir instâncias sobre curvas e superfícies | `along(curva)`, `scatter(superfície)` |

## Fase 1 — vocabulário estrutural (maior ganho por linha de código)

### 1.1 `split`: dividir uma forma em faixas

Inspirado no CGA. Divide a caixa da forma num eixo; os tamanhos aceitam metros, frações (`"1fr"`)
ou `"~"` (o que sobrar). Devolve uma lista de escopos (caixas) para preencher.

```python
parede = box(8, 3, 0.3)
base, meio, topo = parede.split("y", [0.4, "~", 0.5])
esq, vao, dir = meio.split("x", ["~", 1.2, "~"])
casa = group(base.fill("stone"), esq.fill("wood"), dir.fill("wood"),
             porta(vao), topo.fill(viga))
```

`fill(x)` aceita cor/material (preenche a caixa), uma forma (encaixa e escala) ou uma função
`f(escopo)`. Escopos têm `w`, `h`, `d`, `top`, `center` como as formas já têm.

### 1.2 `tile` / `repeat_in`: repetir ocupando o espaço

`escopo.tile("x", tamanho=0.9, f)` cabe quantas cópias der, ajustando o tamanho (como `repeat` do
CGA). Janelas numa fachada, tábuas numa parede, telhas num telhado, sem contar unidades à mão.

### 1.3 `faces` e escopos inclinados

`telhado.faces("top")`, `parede.faces("front")`: devolve escopos orientados nas faces de uma caixa,
prisma ou cunha, para colar detalhes na superfície (telhas no plano inclinado do `prism`). O escopo
traz sistema local (u, v, normal) e os métodos de layout passam a aceitar escopos como alvo.

### 1.4 Âncoras e encaixe de componentes

```python
def casa(w=6):
    corpo = box(w, 2.5, 4).ground()
    return corpo.anchor("porta", corpo.front, y=0).anchor("cume", corpo.top)

c = casa()
placa.attach(c, "porta", gap=0.02)      # cola na âncora, orientado pela normal dela
```

Âncora = ponto + direção, guardada na forma e herdada por transformações (como `name`). Resolve o
item 4 sem classes; inclui âncoras padrão (`top`, `bottom`, `front`...) em toda forma.

### 1.5 Curvas: `bezier`, `spline`, `sweep`, `loft`, `along`

```python
casco_curva = spline([(-4, 0.6, 0), (0, 0, 0), (4, 0.6, 0)])
casco = loft([perfil_u(1.2, 0.8), perfil_u(1.6, 1.0), perfil_u(1.2, 0.8)], along=casco_curva)
corda = sweep(circle(0.02), spline(pontos))
escudos = shield().along(casco_curva.offset(z=1.1), count=12)   # distribui ao longo
```

No shader: `sweep` por Bézier quadrática exata (IQ) por trecho, `loft` como interpolação de perfis
2D ao longo do parâmetro da curva (campo aproximado, com `lip` automático). `along` só gera
transformações (vai para a BVH, barato).

**Pronto quando:** uma casa longa viking com paredes de tábua, portas, vigas cruzadas e telhado de
telhas sai em ~40 linhas sem coordenada absoluta além do tamanho da casa; um barco com casco
curvo e escudos em ~30. Os dois entram em `examples/` e no `render.mjs` dos testes.

## Fase 2 — detalhe barato e junções melhores

### 2.1 Padrões de superfície como modificadores

`.planks(largura=0.2, gap=0.01, axis="x")`, `.shingles(...)`, `.thatch(...)`, `.masonry(...)`,
`.carve(padrão, depth)`. Implementação: repetição de domínio + deslocamento limitado (`relief`),
**custo constante**, sem uma primitiva por tábua. O `texture(..., bump=)` existente já é meio
caminho: aqui o relevo muda a silhueta (até `depth`) e a sombra.

### 2.2 Junções do hg_sdf

`merge(..., profile=...)` ganha `"chamfer"`, `"stairs"` (n degraus), `"columns"`, `"groove"`,
`"tongue"`; o mesmo em `group`/`subtract`. Dão encaixes de madeira, molduras e acabamento de
pedra com uma palavra.

### 2.3 Variação controlada

`vary(forma, seed, pos=0.02, rot=3, scale=0.05)`: pequenas imperfeições determinísticas em cópias
(tábuas tortas, pedras diferentes). Evita o visual "perfeito demais" que denuncia o procedural.

### 2.4 Kits temáticos na biblioteca (`src/lib`)

Como os geradores de árvore/pessoa já existentes: `nordic.longhouse()`, `nordic.boat()`,
`medieval.wall()`, `furniture.*`, escritos **na própria linguagem** sempre que possível (como no
Curv), servindo também de exemplo para a IA copiar o estilo.

## Fase 3 — renderizador que aguente

1. **Instâncias de código.** Duas chamadas à mesma função com as mesmas formas (só mudando a
   transformação/cor) devem compilar **um** trecho GLSL e virar instâncias na BVH. Hoje só as folhas
   simples vão para a BVH; com isso, 30 casas custam 1 casa de compilação. Maior ganho de escala.
2. **Poda por região** (ideia do Fidget/libfive): estender o "pula nós pesados por caixa" a uma BVH
   de nós de código, para que cada raio só avalie o que está perto.
3. **Assar peças estáticas** (ideia do Dreams/Claybook): nós caros e parados (`displace`, `implicit`,
   padrões de 2.1) avaliados uma vez numa textura 3D esparsa (blocos 8³) e lidos por interpolação
   no raymarch. Troca tempo de compilação/frame por memória; opcional por peça (`.bake(res)`).
4. **Orçamento visível.** O `check.mjs`/MCP informa custo estimado (código inline, folhas, peças
   assadas) e sugere a troca ("estes 40 `subtract` iguais podem virar instância").

## Fase 4 — fluxo para IA

- **Esboço → detalhe**: documentar e testar um roteiro em que a IA primeiro monta volumes com
  `split`/âncoras (`blockout`), confere com `render.mjs`, e só depois aplica padrões e materiais.
  Trabalhos como CAD-Coder mostram que planejar antes do código melhora a validade.
- **Exemplos como referência de estilo**: galeria por tema (nórdico, medieval, sci-fi, orgânico)
  com a imagem renderizada ao lado do código, usada pelo MCP como contexto.
- **Erros e dicas para as novas funções** no mesmo padrão atual ("você quis dizer...?", unidade
  esperada, escopo vazio no `split`).
- **Teste visual de regressão**: `render.mjs` dos exemplos comparado com imagens de referência.

## Ordem sugerida

| # | entrega | esforço | por quê |
|---|---|---|---|
| 1 | `split` + `fill` + `tile` (1.1, 1.2) | médio | resolve fachadas, móveis, prédios; só layout, sem shader novo |
| 2 | âncoras + `attach` (1.4) | pequeno | componentes reutilizáveis sem contas |
| 3 | `spline`/`bezier` + `sweep` + `along` (1.5) | médio | curvas: barcos, cordas, galhos, corrimões |
| 4 | `planks`/`shingles`/`masonry` (2.1) | médio | o salto visual de "bloquinho" para "feito à mão" |
| 5 | instâncias de código (3.1) | grande | condição para vilas e cidades inteiras |
| 6 | `faces` (1.3), junções hg_sdf (2.2), `vary` (2.3) | pequeno cada | acabamento |
| 7 | `loft` (1.5), kits temáticos (2.4) | médio | cascos, asas; bibliotecas prontas |
| 8 | poda por região e `.bake` (3.2, 3.3) | grande | escala de cenas muito densas |

Marco de validação ao fim dos itens 1–4: refazer `vila.3di` como vila nórdica (casas longas,
barco, cercas, telhados de palha/telha) e comparar código, tempo de compilação e imagem com a
versão atual.

## Fontes

- Curv: <https://www.github.com/curv3d/curv>
- CGA shape (Müller et al., *Procedural Modeling of Buildings*): <https://course.ccs.neu.edu/cs5150f13/readings/muller_buildings.pdf>;
  visão geral: <https://gamedev.net/tutorials/programming/engines-and-middleware/procedural-modeling-of-buildings-with-shape-grammars-r4596>
- Fidget / libfive (Matt Keeter): <https://mattkeeter.com/projects/fidget>, <https://mattkeeter.com/research/fidget-2024.pdf>
- hg_sdf (Mercury): <https://mercury.sexy/hg_sdf>; port em JS: <https://www.npmjs.com/package/hg-ast>
- Dreams (Alex Evans, SIGGRAPH 2015): <https://advances.realtimerendering.com/s2015/AlexEvans_SIGGRAPH-2015-sml.pdf>
- ShapeAssembly: <https://github.com/subeeshvasu/ShapeAssembly>
- CAD-Recode (ICCV 2025): <https://orbilu.uni.lu/bitstream/10993/67036/1/CADRecode_ICCV_2025.pdf>;
  CAD-Coder (NeurIPS 2025): <https://papers.neurips.cc/paper_files/paper/2025/hash/564a224e88f2490f3c1deaae877d37e3-Abstract-Conference.html>
