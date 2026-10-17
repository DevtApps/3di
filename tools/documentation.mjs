import { readFile } from 'node:fs/promises';
import { DOC_ROUTES, DOC_TOPICS } from '../src/docroutes.js';

export { DOC_TOPICS };
export const documentationResources = DOC_ROUTES.map(({ topic, name, description }) => ({
  uri: `threedi://docs/${topic}`, name, description, mimeType: 'text/markdown',
}));

export async function readDocumentation(topicOrUri) {
  const entry = DOC_ROUTES.find(({ topic }) => topicOrUri === topic || topicOrUri === `threedi://docs/${topic}`);
  if (!entry) throw new Error(`Rota desconhecida. Use: ${DOC_TOPICS.join(', ')}.`);
  return { uri: `threedi://docs/${entry.topic}`, mimeType: 'text/markdown', text: await readFile(new URL(`../${entry.file}`, import.meta.url), 'utf8') };
}
