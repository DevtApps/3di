import { build } from 'esbuild';
import { mkdir, readFile, writeFile } from 'node:fs/promises';

await mkdir('dist', { recursive: true });
await mkdir('out', { recursive: true });
const nodeBundle = {
  bundle: true, platform: 'node', format: 'cjs', target: 'node22',
  external: ['vscode', 'sury', 'effect', '@valibot/to-json-schema'],
  define: { 'import.meta.url': '__bundleFileUrl' },
  banner: { js: 'var __bundleFileUrl = require("node:url").pathToFileURL(__filename).href;' },
};
await build({ ...nodeBundle, entryPoints: ['extension/extension.ts'], outfile: 'dist/extension.cjs', logLevel: 'info' });
await build({ entryPoints: ['extension/engine-worker.ts'], outfile: 'dist/engine-worker.cjs', bundle: true, platform: 'node', format: 'cjs', target: 'node22' });
await build({ entryPoints: ['extension/preview.ts'], outfile: 'dist/preview.js', bundle: true, platform: 'browser', format: 'iife', target: 'chrome120' });
await build({ entryPoints: ['extension/project.ts'], outfile: 'dist/project.mjs', bundle: true, platform: 'node', format: 'esm' });
await build({ ...nodeBundle, entryPoints: ['extension/mcp.ts'], outfile: 'dist/mcp.cjs' });
await build({ ...nodeBundle, entryPoints: ['extension/host-test.ts'], outfile: 'dist/host-test.cjs' });
// The original README is preserved as the language reference; the extension README is user-facing.
await writeFile('dist/THIRD-PARTY-NOTICES.txt', 'MCP uses the official @modelcontextprotocol/sdk (MIT). Bundled dependencies retain license notices.\n');

await build({ entryPoints: ['services/workspace.ts'], outfile: 'dist/workspace.mjs', bundle: true, platform: 'node', format: 'esm' });
