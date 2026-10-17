// Browser development shares the desktop runtime and MCP HTTP.
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { startRuntime } = require('../dist-desktop/desktop/runtime.cjs');
const root = fileURLToPath(new URL('../', import.meta.url));
// Portas próprias do modo dev (o app instalado usa 8317 para a IDE e 8318 para o MCP): assim os dois rodam
// juntos e um agente configurado para o app nunca fala com o código em desenvolvimento por engano.
// THREEDI_MCP=0 desliga o MCP do dev; THREEDI_PORT / THREEDI_MCP_PORT trocam as portas.
const port = Number(process.env.THREEDI_PORT ?? 8327);
const mcpPort = process.env.THREEDI_MCP === '0' ? null : Number(process.env.THREEDI_MCP_PORT ?? 8328);
const runtime = await startRuntime(root, fileURLToPath(new URL('../dist-desktop/desktop/engine-worker.cjs', import.meta.url)), { port, mcpPort, reuseIde: false, workspace: process.env.THREEDI_WORKSPACE });
console.log(`[3di dev] IDE em ${runtime.ide.url}${mcpPort === null ? ' · MCP desligado (THREEDI_MCP=0)' : ` · MCP HTTP em http://127.0.0.1:${mcpPort}/mcp`}`);
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, async () => { await runtime.stop(); process.exit(0); });
