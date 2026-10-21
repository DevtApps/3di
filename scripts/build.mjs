import { build } from 'esbuild';
import { cp, mkdir, readFile, writeFile } from 'node:fs/promises';

await mkdir('build/desktop/desktop', { recursive: true });
const node = { bundle: true, platform: 'node', format: 'cjs', target: 'node22', external: ['electron'], define: { 'import.meta.url': '__bundleFileUrl' }, banner: { js: 'var __bundleFileUrl = require("node:url").pathToFileURL(__filename).href;' } };
await build({ ...node, entryPoints: ['apps/desktop/main.ts'], outfile: 'build/desktop/desktop/main.cjs' });
await build({ ...node, entryPoints: ['apps/desktop/runtime.ts'], outfile: 'build/desktop/desktop/runtime.cjs' });
await build({ bundle: true, platform: 'node', format: 'cjs', target: 'node22', external: ['electron'], entryPoints: ['apps/desktop/preload.ts'], outfile: 'build/desktop/desktop/preload.cjs' });
await build({ ...node, entryPoints: ['src/services/engine-worker.ts'], outfile: 'build/desktop/desktop/engine-worker.cjs' });
await build({ ...node, entryPoints: ['src/parts-worker-node.js'], outfile: 'build/desktop/desktop/parts-worker-node.cjs' });
await mkdir('build/services', { recursive: true });
await build({ ...node, entryPoints: ['src/services/mcp.ts'], outfile: 'build/services/mcp.cjs' });
for (const name of ['project', 'workspace']) await build({ bundle: true, platform: 'node', format: 'esm', target: 'node22', entryPoints: [`src/services/${name}.ts`], outfile: `build/services/${name}.mjs` });
for (const path of ['src', 'assets', 'examples', 'docs', 'skills', 'index.html']) await cp(path, `build/desktop/${path}`, { recursive: true });
await mkdir('build/desktop/node_modules', { recursive: true });
await cp('node_modules/monaco-editor', 'build/desktop/node_modules/monaco-editor', { recursive: true });
const pkg = JSON.parse(await readFile('package.json', 'utf8'));
await writeFile('build/desktop/package.json', JSON.stringify({ name: '3di-studio', productName: '3DI', version: pkg.version, description: pkg.description, homepage: 'http://127.0.0.1:8317', dependencies: { 'monaco-editor': pkg.dependencies['monaco-editor'] }, main: 'desktop/main.cjs', author: { name: '3DI', email: '3di@localhost' }, license: pkg.license }, null, 2));
console.log('Desktop pronto em build/desktop/');
