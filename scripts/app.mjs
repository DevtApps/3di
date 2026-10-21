#!/usr/bin/env node
// App desktop do 3DI: sobe o servidor da IDE (ou usa um que já esteja rodando, como o do MCP)
// e abre a IDE numa janela do Chrome/Chromium em modo app (sem abas nem barra de endereço),
// com perfil próprio em ~/.config/3di/chrome. O processo fica vivo enquanto houver janela aberta.
// Uso: node scripts/app.mjs [cena.3di]      Navegador: THREEDI_BROWSER=/caminho/do/chrome
import { spawn, execFileSync } from 'node:child_process';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';
import { existsSync } from 'node:fs';
import { startIdeServer } from '../src/services/ideserver.mjs';
import { createRequire } from 'node:module';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const PORT = Number(process.env.THREEDI_PORT ?? 8327);
const log = (...a) => process.stderr.write(`[3di] ${a.join(' ')}\n`);

const CANDIDATES = ['google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser', 'microsoft-edge', 'brave-browser'];

function findBrowser() {
  if (process.env.THREEDI_BROWSER) return process.env.THREEDI_BROWSER;
  for (const c of CANDIDATES) {
    try { return execFileSync('which', [c], { encoding: 'utf8' }).trim(); } catch {}
  }
  return null;
}

const browser = findBrowser();
if (!browser) {
  log('nenhum Chrome/Chromium encontrado. Instale um ou defina THREEDI_BROWSER.');
  process.exit(1);
}

const file = process.argv[2] ? resolve(process.argv[2]) : null;
if (file && !existsSync(file)) log(`aviso: ${file} não existe (será criado ao salvar)`);

// O launcher web também precisa oferecer o MCP HTTP, como o desktop e npm run dev.
const mcpPort = Number(process.env.THREEDI_MCP_PORT ?? 8328);
let runtime = null;
let existingMcp = false;
try {
  const response = await fetch(`http://127.0.0.1:${mcpPort}/health`, { signal: AbortSignal.timeout(2000) });
  const health = await response.json();
  existingMcp = response.ok && health.name === '3di' && health.endpoint === `http://127.0.0.1:${mcpPort}/mcp`;
} catch {}
if (!existingMcp) {
  const require = createRequire(import.meta.url);
  const { startRuntime } = require('../build/desktop/desktop/runtime.cjs');
  runtime = await startRuntime(ROOT, join(ROOT, 'build/desktop/desktop/engine-worker.cjs'), {
    port: PORT, mcpPort, reuseIde: true, log,
  });
}
const ide = runtime?.ide ?? await startIdeServer({ root: ROOT, port: PORT, log, fallbackPort: true });
async function stop() { await runtime?.stop(); process.exit(0); }
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => void stop());
const hash = new URLSearchParams({ token: ide.token, ...(file ? { file } : {}) });
const profile = join(homedir(), '.config', '3di', 'chrome');

const child = spawn(browser, [
  `--app=${ide.url}/#${hash}`,
  `--user-data-dir=${profile}`,
  '--class=3DI-dev',
  '--window-size=1440,900',
  '--no-first-run',
  '--no-default-browser-check',
], { stdio: 'ignore' });
child.on('error', (e) => { log(`não abriu o navegador: ${e.message}`); process.exit(1); });

// O Chrome pode repassar a janela para uma instância já aberta do mesmo perfil e sair na hora;
// por isso o servidor só fecha quando nenhum editor estiver conectado (com uma folga inicial
// para a janela repassada se conectar).
child.on('exit', () => {
  if (ide.relay && !runtime) process.exit(0);
  const started = Date.now();
  let idleChecks = 0;
  let checking = false;
  setInterval(async () => {
    if (checking) return;
    checking = true;
    try {
    if (ide.relay) {
      try { await ide.call('fileState'); idleChecks = 0; return; } catch {}
    } else if (ide.clientCount() > 0) { idleChecks = 0; return; }
    if (Date.now() - started < 8000) return;
    if (++idleChecks >= 2) { log('nenhuma janela aberta; encerrando'); await stop(); }
    } finally { checking = false; }
  }, 2000);
});
