// Browser development shares the desktop runtime and MCP HTTP.
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { startRuntime } = require('../dist-desktop/desktop/runtime.cjs');
const root = fileURLToPath(new URL('../', import.meta.url));
const runtime = await startRuntime(root, fileURLToPath(new URL('../dist-desktop/desktop/engine-worker.cjs', import.meta.url)), { port: Number(process.env.THREEDI_PORT ?? 8317), mcpPort: Number(process.env.THREEDI_MCP_PORT ?? 8318), reuseIde: true, workspace: process.env.THREEDI_WORKSPACE });
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, async () => { await runtime.stop(); process.exit(0); });
