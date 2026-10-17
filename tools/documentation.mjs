import { readFile } from 'node:fs/promises';

const entries = [
  ['geometry-review', 'Revisão geométrica', 'Checagens de apoios, medidas e posições.', '../skills/3di-geometry-review/SKILL.md'],
  ['language', 'Linguagem 3DI', 'Sintaxe, primitivas, materiais, animação e exportação.', '../docs/language.md'],
  ['best-practices', 'Boas práticas', 'Layout, desempenho e validação de cenas.', '../docs/best-practices.md'],
  ['examples', 'Exemplos', 'Catálogo de exemplos e fluxo de trabalho.', '../docs/examples.md'],
  ['skill', 'Skill 3DI', 'Instruções reutilizáveis para agentes externos.', '../skills/3di-scenes/SKILL.md'],
];

export const documentationResources = entries.map(([topic, name, description]) => ({
  uri: `threedi://docs/${topic}`, name, description, mimeType: 'text/markdown',
}));

export async function readDocumentation(topicOrUri) {
  const entry = entries.find(([topic]) => topicOrUri === topic || topicOrUri === `threedi://docs/${topic}`);
  if (!entry) throw new Error('Documento desconhecido. Use language, best-practices, examples, skill ou geometry-review.');
  const [topic, , , path] = entry;
  return { uri: `threedi://docs/${topic}`, mimeType: 'text/markdown', text: await readFile(new URL(path, import.meta.url), 'utf8') };
}
