// Estilos visuais compartilhados por todos os geradores (grama, plantas, árvores, pessoas, veículos).
// A mesma ideia vale para tudo: do low poly (poucas peças, cores chapadas, quinas vivas) ao
// realista (mais peças, variação de cor, relevo, rugosidade). O gerador lê estes botões e decide
// o que fazer com eles; `detail` e `variation` do usuário sobrepõem os valores do estilo.
import { ScriptError } from '../parser.js';
import { didYouMean } from '../runtime.js';

export const STYLES = {
  // poucas peças grandes, facetadas, cores chapadas
  lowpoly: { detail: 0.5, facets: true, vary: 0.05, gradient: false, bump: 0, mottle: false, rough: 0.85, round: 0 },
  // formas lisas e limpas, degradês suaves, cores vivas
  stylized: { detail: 1, facets: false, vary: 0.1, gradient: true, bump: 0, mottle: false, rough: 0.7, round: 1 },
  // mais detalhe, variação natural de cor, manchas e relevo
  realistic: { detail: 1.8, facets: false, vary: 0.18, gradient: true, bump: 0.35, mottle: true, rough: 0.6, round: 1 },
};

const ALIASES = { low_poly: 'lowpoly', 'low-poly': 'lowpoly', poly: 'lowpoly', cartoon: 'stylized', estilizado: 'stylized', realista: 'realistic', real: 'realistic' };

export function resolveStyle(name, what) {
  const key = ALIASES[String(name).toLowerCase()] ?? String(name).toLowerCase();
  const st = STYLES[key];
  if (!st) {
    throw new ScriptError(`${what}: estilo desconhecido '${name}'`, null,
      didYouMean(String(name), [...Object.keys(STYLES), ...Object.keys(ALIASES)]) ?? `use ${Object.keys(STYLES).join(', ')}`);
  }
  return { name: key, ...st };
}

export const STYLE_NAMES = Object.keys(STYLES);
