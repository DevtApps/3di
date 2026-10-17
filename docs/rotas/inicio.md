# 3DI pelo MCP: por onde começar

3DI é um subconjunto de Python que descreve cenas 3D. O script vira um shader de SDF
(preview em tempo real) e pode ser exportado como GLB. Você escreve formas genéricas
(primitivas, combinações, deformações, pintura) e monta seus próprios objetos com `def`.
Não existem funções prontas por tipo de modelo: casas, bichos e robôs são feitos com as
mesmas funções genéricas.

## Rotas da documentação

Leia só as rotas do que for fazer (`get_documentation(topic=...)` ou `threedi://docs/<rota>`):

| rota | quando ler |
|---|---|
| `fundamentos` | sempre: eixos, unidades, Python suportado, layout (`place`, `on`, `beside`), câmera e cena |
| `formas` | primitivas, perfis (`extrude`, `lathe`), formas por fórmula (`implicit`) |
| `combinar` | união, subtração, interseção, `smooth`, **`merge`** (junções), `mirror`, `repeat`, `polar` |
| `deformar` | `taper`, `bend`, `twist`, `shear`, `elongate`, `round`, `shell`, `displace` |
| `materiais` | cor, `material` (rough, metal, glow, coat), texturas, `paint`, `facets`, luz e céu |
| `organico` | personagens e criaturas: corpos fundidos, `chain`, pelagem com `paint`, olhos |
| `hard-surface` | peças duras: `bevel`, `merge` com sulco/chanfro, faixas e vincos com `paint(relief=)` |
| `cenarios` | arquitetura e dioramas: funções reutilizáveis, `repeat`, orçamento de primitivas |
| `animacao` | `time`, `osc`, esqueleto, `bind` |
| `exportar` | GLB: peças, resolução, facetas, atlas de pintura, `check_glb` |
| `referencia-visual` | copiar uma imagem: `set_reference`, `compare_reference`, `screenshot` |
| `revisao` | conferir apoios, alinhamentos e encaixes antes de entregar |
| `desempenho` | limites e tempo de compilação do shader |
| `ferramentas` | todas as ferramentas MCP, por grupo |
| `exemplos` | cenas prontas e o que cada uma demonstra |
| `linguagem` | referência completa (longa): use quando as rotas não bastarem |

`describe_language` devolve todas as assinaturas atuais (geradas do interpretador, sempre certas).

## Fluxo de trabalho

1. `get_script` antes de editar uma cena existente.
2. Escreva o script; valide com `check_script` (erros com linha e dica, medidas das peças nomeadas).
3. `set_script` aplica no editor; `screenshot(view="grid")` mostra frente, lado, topo e perspectiva.
4. Para copiar uma imagem: rota `referencia-visual`.
5. Revise (rota `revisao`) e, se for exportar, confira a malha com `check_glb` (rota `exportar`).
6. `save_script` / `export_glb` quando fizer parte do pedido.

Sem o editor aberto, documentação e `check_script` funcionam; as ferramentas de preview não.
