// Recursos da interface que vão no pacote (funciona offline): ícones Lucide (ISC) usados pela IDE,
// num módulo JS com só o miolo de cada SVG, e as fontes Inter e JetBrains Mono (OFL) em WOFF2.
// Os arquivos gerados são versionados: rode de novo ao adicionar ícones ou trocar versões.
import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from 'node:fs';

const ICONS = ['file-plus', 'folder-open', 'save', 'settings', 'panel-left', 'code', 'bot', 'plug', 'play', 'pause', 'skip-back',
  'volume-2', 'volume-x', 'clapperboard', 'scan', 'boxes', 'layout-grid', 'image', 'download', 'image-down', 'box', 'shield-check',
  'chevron-down', 'x', 'video', 'camera', 'layers', 'book-open', 'sparkles', 'circle-alert', 'circle-check', 'loader-circle',
  'send', 'square', 'rotate-ccw', 'mic', 'trash-2', 'plus', 'refresh-cw', 'key-round', 'audio-lines', 'user-round', 'copy', 'external-link',
  'maximize', 'eye', 'eye-off', 'move-3d', 'type', 'list', 'circle-play', 'monitor', 'cpu', 'ellipsis'];
const out = {};
for (const name of ICONS) {
  const svg = readFileSync(`node_modules/lucide-static/icons/${name}.svg`, 'utf8');
  out[name] = svg.replace(/^[\s\S]*?<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '').replace(/\s+/g, ' ').trim();
}
writeFileSync('src/ide/icons.js', `// Ícones Lucide (ISC), gerados por scripts/vendor-ui.mjs (não editar à mão)
const PATHS = ${JSON.stringify(out, null, 0).replace(/","/g, '",\n  "')};

// <svg> de um ícone; size em px (o traço segue a cor do texto)
export function icon(name, { size = 16, label = null } = {}) {
  const p = PATHS[name];
  if (!p) throw new Error(\`ícone '\${name}' não existe (adicione em scripts/vendor-ui.mjs)\`);
  const a11y = label ? \`role="img" aria-label="\${label}"\` : 'aria-hidden="true"';
  return \`<svg class="icon" width="\${size}" height="\${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" \${a11y}>\${p}</svg>\`;
}

// troca os <i data-icon="nome"> do documento (ou de root) pelos SVGs
export function hydrateIcons(root = document) {
  for (const el of root.querySelectorAll('i[data-icon]')) el.outerHTML = icon(el.dataset.icon, { size: Number(el.dataset.size) || 16 });
}
`);
mkdirSync('assets/fonts', { recursive: true });
for (const f of ['inter-latin-wght-normal.woff2', 'inter-latin-ext-wght-normal.woff2']) copyFileSync(`node_modules/@fontsource-variable/inter/files/${f}`, `assets/fonts/${f}`);
copyFileSync('node_modules/@fontsource-variable/jetbrains-mono/files/jetbrains-mono-latin-wght-normal.woff2', 'assets/fonts/jetbrains-mono-latin-wght-normal.woff2');
console.log(`src/ide/icons.js: ${ICONS.length} ícones; fontes em assets/fonts/`);
