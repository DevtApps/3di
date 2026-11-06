// Empacota o que as sobreposições (overlay) usam no navegador, para o app funcionar offline:
// React + ReactDOM + o compilador de JSX (Sucrase) num arquivo ES, e o Tailwind CSS v4 que gera o
// CSS no próprio navegador. Os arquivos gerados são versionados: rode de novo só ao trocar versões.
import { build } from 'esbuild';
import { writeFile, rm, stat, copyFile, mkdir } from 'node:fs/promises';

await mkdir('assets/vendor', { recursive: true });
await writeFile('assets/vendor/.overlay-entry.js', `export * as React from 'react';
export { createRoot } from 'react-dom/client';
export { flushSync } from 'react-dom';
export { transform } from 'sucrase';
`);
await build({
  entryPoints: ['assets/vendor/.overlay-entry.js'], outfile: 'assets/vendor/overlay-libs.js',
  bundle: true, format: 'esm', minify: true, target: 'es2022', legalComments: 'none',
  define: { 'process.env.NODE_ENV': '"production"' },
  banner: { js: '/* React + ReactDOM (MIT) + Sucrase (MIT), gerado por scripts/vendor-overlay.mjs */' },
});
await rm('assets/vendor/.overlay-entry.js');
await copyFile('node_modules/@tailwindcss/browser/dist/index.global.js', 'assets/vendor/tailwind-browser.js');
for (const f of ['overlay-libs.js', 'tailwind-browser.js']) console.log(`assets/vendor/${f}: ${((await stat(`assets/vendor/${f}`)).size / 1024).toFixed(0)} KB`);
