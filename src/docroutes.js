// Rotas da documentação servidas pelo MCP (get_documentation, recursos threedi://docs/<rota>
// e /docs/<rota> no HTTP). Um tema por rota: o agente lê só o que vai usar.
// file é relativo à raiz do projeto/instalação.
export const DOC_ROUTES = [
  { topic: 'inicio', name: 'Por onde começar', description: 'O que é o 3DI, fluxo de trabalho e qual rota ler para cada tarefa.', file: 'docs/rotas/inicio.md' },
  { topic: 'fundamentos', name: 'Fundamentos', description: 'Eixos, unidades, Python suportado, posicionamento (place, on, beside), cena e câmera.', file: 'docs/rotas/fundamentos.md' },
  { topic: 'formas', name: 'Formas', description: 'Primitivas, bevel, segment/chain, extrude, lathe e implicit.', file: 'docs/rotas/formas.md' },
  { topic: 'combinar', name: 'Combinar', description: 'União, subtração, interseção, smooth, merge (junções com filete, chanfro ou sulco), mirror, repeat, polar.', file: 'docs/rotas/combinar.md' },
  { topic: 'deformar', name: 'Deformar', description: 'taper, bend, twist, shear, elongate, round, shell, displace.', file: 'docs/rotas/deformar.md' },
  { topic: 'materiais', name: 'Materiais, pintura e luz', description: 'color, material (coat), texture, paint (com relief), facets, sun, sky, fog, light.', file: 'docs/rotas/materiais.md' },
  { topic: 'organico', name: 'Personagens e criaturas', description: 'Receita genérica para corpos orgânicos: smooth, chain, pelagem com paint, olhos, low poly.', file: 'docs/rotas/organico.md' },
  { topic: 'hard-surface', name: 'Peças duras', description: 'Brinquedos, robôs e máquinas: bevel, merge com sulco/chanfro, faixas e vincos com paint(relief), verniz.', file: 'docs/rotas/hard-surface.md' },
  { topic: 'cenarios', name: 'Cenários e dioramas', description: 'Arquitetura e cenas grandes: funções reutilizáveis, repeat, recortes, telhados, orçamento.', file: 'docs/rotas/cenarios.md' },
  { topic: 'animacao', name: 'Animação e rig', description: 'time, osc, esqueleto e bind (exporta animado no GLB).', file: 'docs/rotas/animacao.md' },
  { topic: 'exportar', name: 'Exportar GLB', description: 'Como a conversão funciona (peças, resolução, atlas, facetas) e como conferir com check_glb.', file: 'docs/rotas/exportar.md' },
  { topic: 'referencia-visual', name: 'Copiar uma imagem', description: 'set_reference, compare_reference e o fluxo para modelar fiel a uma imagem.', file: 'docs/rotas/referencia-visual.md' },
  { topic: 'revisao', name: 'Revisão geométrica', description: 'Conferir apoios, alinhamentos, encaixes e vistas antes de entregar.', file: 'docs/rotas/revisao.md' },
  { topic: 'desempenho', name: 'Desempenho e limites', description: 'Tempo de compilação, BVH, limites de primitivas e o que é caro.', file: 'docs/rotas/desempenho.md' },
  { topic: 'ferramentas', name: 'Ferramentas MCP', description: 'Todas as ferramentas do servidor, por grupo.', file: 'docs/rotas/ferramentas.md' },
  { topic: 'exemplos', name: 'Exemplos', description: 'Cenas prontas e o que cada uma demonstra.', file: 'docs/rotas/exemplos.md' },
  { topic: 'linguagem', name: 'Referência completa', description: 'Documento único e longo com toda a linguagem; use quando as rotas não bastarem.', file: 'docs/language.md' },
];
export const DOC_TOPICS = DOC_ROUTES.map((r) => r.topic);
