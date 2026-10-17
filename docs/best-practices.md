# Boas práticas para cenas 3DI

## Construção e layout

- Use metros, y para cima e +z para frente. As primitivas nascem centradas na origem.
- Prefira `place`, `on`, `beside` e `ground` para apoiar e alinhar peças.
- Formas são imutáveis: guarde o retorno dos métodos quando precisar reutilizá-lo.
- Use `.name()` nas peças principais para inspecionar medidas com `list_parts` e `check_script`.
- Faça recortes atravessarem a superfície para evitar películas nas aberturas.
- Termine o script com `show(...)`; não há import, classes ou acesso a arquivos na linguagem.

## Escolher a forma

- Use `extrude` para perfis próprios e `lathe` para revolução; confira o plano e
  a origem do perfil antes de posicionar. `polygon`, `star`, `wedge`, `hemisphere`
  e `tube` evitam montar manualmente essas formas.
- Use `taper`, `bend`, `shear` e `elongate` antes do apoio final. Caixas de formas
  deformadas são aproximações e podem deixar folga nas medidas de contato.
- Afaste a peça do eixo y antes de `polar`; mova o conjunto depois da repetição.
- Em `implicit`, mantenha o campo próximo de uma distância e ajuste `lip` conforme
  "Formas por fórmula". A caixa `size` recorta a forma; comparações e `if` com
  coordenadas simbólicas não funcionam. Exemplos: `formas.3di` e `formulas.3di`.

## Custo de renderização

- Prefira `mirror` e `repeat` para repetições regulares; não acrescentam primitivas extras.
- Uniões simples podem usar a BVH, até 16000 instâncias. Booleanas, uniões suaves e
  modificadores complexos geram GLSL, com limite de 2000 primitivas como código.
- Aumente a complexidade aos poucos e acompanhe o tempo de compilação.

## Animação e exportação

- `time` funciona em transformações e glow, mas não em condições ou tamanhos de primitivas.
- O layout semântico usa a posição em t=0. Confira outros instantes em cenas animadas.
- Para exportar animação em GLB, use ossos e `.bind()`. Animações diretas na forma
  são exportadas em t=0. Uniões suaves entre ossos diferentes viram malhas separadas.
- `res` deve ser inteiro entre 1 e 2048. Comece com resolução baixa para revisar a
  geometria e aumente depois. Confira avisos do exportador e peças finas na malha.
- A resolução é por peça. Faces planas são simplificadas; texturas procedurais
  viram atlas PNG embutidos no GLB e `bump` vira normal map. Confira UV, padrão e
  relevo no destino; PNGs separados não são salvos automaticamente.

## Fluxo com agentes externos

1. Consulte `threedi://docs/language` e este guia, ou use `get_documentation`.
2. Antes de editar uma cena existente, leia `get_script` para preservar o trabalho atual.
3. Valide o código proposto com `check_script` e corrija os erros encontrados.
4. Aplique no editor com `set_script` e confira o status da compilação.
5. Use `screenshot` com `view="grid"` para conferir frente, lado, topo e perspectiva.
   Use `target` para uma peça nomeada e `time` para conferir um instante da animação.
6. Salve quando solicitado. `save_script` usa o arquivo aberto; se não houver caminho,
   peça ao usuário para escolher um arquivo no editor.

O preview pode ficar em tela cheia com o código oculto: as ferramentas MCP continuam
funcionando. O indicador da IDE informa a conexão da ponte, não o estado do Codex ou Claude Code.

## Geometria e conclusão da cena

Leia as skills `3di-scenes` e `3di-geometry-review` via `get_skill` ou recursos
`threedi://skills/<nome>`. `list_skills` permite descobri-las sem instalar arquivos.
Para preparar o workspace do agente, use `install_skills` com `workspace` absoluto
e `target="both"`; arquivos existentes diferentes são preservados e reportados.

Defina dimensões principais e derive bordas/níveis dependentes. `place` posiciona
a base; `at` desloca. Modele grupos em coordenadas locais antes de movê-los.
Meça apoios, centros, margens e encaixes com tolerância explícita antes da entrega.
Caixas envolventes são aproximações: sobreposição de caixas não prova colisão,
e o topo da caixa do telhado não representa a altura de uma água inclinada.
Leia mensagens de diagnóstico dos logs; a linguagem não suporta `assert`.

Depois de aplicar a versão final, examine as quatro vistas e os encontros ocluídos
em vistas adicionais/aproximadas. Corrija falhas e repita a revisão nas regiões
alteradas. Relate o que foi efetivamente medido/visto e eventuais pendências.
Não declare concluída a revisão visual quando apenas recebeu os bytes da imagem.
