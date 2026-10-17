import { build } from 'esbuild';
import { cp, mkdir, readFile, writeFile } from 'node:fs/promises';

await mkdir('dist-desktop/desktop', { recursive: true });
const node = { bundle: true, platform: 'node', format: 'cjs', target: 'node22', external: ['electron'], define: { 'import.meta.url': '__bundleFileUrl' }, banner: { js: 'var __bundleFileUrl = require("node:url").pathToFileURL(__filename).href;' } };
await build({ ...node, entryPoints: ['desktop/main.ts'], outfile: 'dist-desktop/desktop/main.cjs' });
await build({ ...node, entryPoints: ['desktop/runtime.ts'], outfile: 'dist-desktop/desktop/runtime.cjs' });
await build({ bundle: true, platform: 'node', format: 'cjs', target: 'node22', external: ['electron'], entryPoints: ['desktop/preload.ts'], outfile: 'dist-desktop/desktop/preload.cjs' });
await build({ ...node, entryPoints: ['extension/engine-worker.ts'], outfile: 'dist-desktop/desktop/engine-worker.cjs' });
await build({ ...node, entryPoints: ['src/parts-worker-node.js'], outfile: 'dist-desktop/desktop/parts-worker-node.cjs' });
await build({ ...node, entryPoints: ['extension/mcp.ts'], outfile: 'dist/mcp.cjs' });
for (const path of ['src', 'assets', 'examples', 'docs', 'skills', 'index.html']) await cp(path, `dist-desktop/${path}`, { recursive: true });
await mkdir('dist-desktop/node_modules', { recursive: true });
await cp('node_modules/monaco-editor', 'dist-desktop/node_modules/monaco-editor', { recursive: true });
const pkg = JSON.parse(await readFile('package.json', 'utf8'));
await writeFile('dist-desktop/package.json', JSON.stringify({ name: '3di-studio', productName: '3DI', version: pkg.version, description: pkg.description, homepage: 'http://127.0.0.1:8317', dependencies: { 'monaco-editor': pkg.dependencies['monaco-editor'] }, main: 'desktop/main.cjs', author: { name: '3DI', email: '3di@localhost' }, license: pkg.license }, null, 2));
console.log('Desktop pronto em dist-desktop/');
