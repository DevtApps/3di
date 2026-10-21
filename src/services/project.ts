import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { installSkills, readSkills } from './skills.js';

export const INITIAL_SCENE = `# Unidades em metros; y para cima.
chao = plane().color("lightgray")
objeto = box(1, round=0.04).ground().color("#6aa6ff").name("objeto")
show(chao, objeto)
camera(pos=(3, 2, 4), look=(0, 0.5, 0))
`;

export const PROJECT_GUIDELINES = `# Projeto 3DI

## Estrutura
- main.3di é a cena inicial. Guarde cenas adicionais em scenes/ e recursos em assets/.
- A skill 3di-scenes está em .agents/skills e .claude/skills: ela aponta para a documentação do MCP.
- Use o app 3DI para editar, conferir o preview e exportar; o editor web também pode ser usado.

## Trabalho com agentes
- Leia a cena atual antes de editar e preserve alterações fora do pedido.
- Consulte a documentação pelo MCP HTTP do 3DI: get_documentation(topic="inicio") indica a rota
  de cada tarefa (formas, combinar, materiais, organico, hard-surface, cenarios, exportar, revisao...).
- Use só funções genéricas da linguagem; objetos específicos são funções def no próprio script.
- O painel Integrações MCP e skills mostra o endpoint HTTP local atual.
- Antes de finalizar, confira numericamente apoios, alinhamentos, margens e encaixes
  com tolerâncias explícitas, leia os logs e examine frente/lado/topo/perspectiva e
  vistas aproximadas dos encontros críticos. Compilar não certifica a geometria.
- Valide com check_script antes de aplicar. Confira o preview e screenshot view=grid
  quando as ferramentas estiverem disponíveis. Não afirme revisão visual sem examinar a imagem.

## Modelagem
- Use metros, y para cima e +z para frente; formas nascem centradas na origem.
- Métodos devolvem novas formas: guarde o retorno quando precisar reutilizá-lo.
- Prefira place, on, beside e ground a coordenadas calculadas manualmente.
- Nomeie peças principais com .name() e termine a cena com show(...).
- Use mirror e repeat para padrões regulares. Faça recortes atravessarem a superfície.
- Use ossos e .bind() para animações exportadas em GLB. time fora dos ossos exporta em t=0.
- Comece exportações com resolução baixa e confira peças finas e avisos antes da versão final.

## Alterações e arquivos
- Não sobrescreva cenas, assets ou configurações sem necessidade para o pedido.
- Só faça git commit ou git push quando o usuário pedir explicitamente a ação correspondente.
`;

// mkdir without recursive intentionally refuses an existing project; no file is overwritten.
export async function createProject(parent: string, name: string, skillFile: string | URL) {
  if (!/^[\p{L}\p{N}_][\p{L}\p{N}_. -]*$/u.test(name) || name.endsWith('.') || name.endsWith(' ')) {
    throw new Error('Use um nome de pasta sem barras ou caracteres especiais.');
  }
  const sourceRoot = resolve(dirname(skillFile instanceof URL ? fileURLToPath(skillFile) : skillFile), '../..');
  await readSkills(sourceRoot);
  const root = join(parent, name);
  await mkdir(root);
  await installSkills(sourceRoot, root, 'both');
  await mkdir(join(root, 'scenes'));
  await mkdir(join(root, 'assets'));
  for (const [path, content] of [
    ['main.3di', INITIAL_SCENE], ['AGENTS.md', PROJECT_GUIDELINES],
    ['3di.json', JSON.stringify({ version: 1, scene: 'main.3di' }, null, 2) + '\n'],
  ]) await writeFile(join(root, path), content, { flag: 'wx' });
  return root;
}
