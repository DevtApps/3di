// Empacota o three.js (núcleo + GLTFLoader + OrbitControls) num único arquivo ES em assets/vendor/,
// para o painel "Conferir GLB" funcionar offline, no app desktop e sem import maps nem CDN.
// O arquivo gerado é versionado: só precisa rodar de novo ao trocar a versão do three.
import { build } from 'esbuild';
import { writeFile, mkdir } from 'node:fs/promises';

await mkdir('assets/vendor', { recursive: true });
await writeFile('assets/vendor/.three-entry.js', `export * from 'three';
export { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
export { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
`);
await build({
  entryPoints: ['assets/vendor/.three-entry.js'], outfile: 'assets/vendor/three-preview.js',
  bundle: true, format: 'esm', minify: true, target: 'es2022', legalComments: 'none',
  banner: { js: '/* three.js (MIT) + GLTFLoader + OrbitControls, gerado por tools/vendor-three.mjs */' },
});
const { rm, stat } = await import('node:fs/promises');
await rm('assets/vendor/.three-entry.js');
console.log(`assets/vendor/three-preview.js: ${((await stat('assets/vendor/three-preview.js')).size / 1024).toFixed(0)} KB`);
