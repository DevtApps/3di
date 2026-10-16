#!/usr/bin/env node
// App desktop do 3DI: sobe o servidor da IDE (ou usa um que já esteja rodando, como o do MCP)
// e abre a IDE numa janela do Chrome/Chromium em modo app (sem abas nem barra de endereço),
// com perfil próprio em ~/.config/3di/chrome. O processo fica vivo enquanto houver janela aberta.
// Uso: node tools/app.mjs [cena.3di]      Navegador: THREEDI_BROWSER=/caminho/do/chrome
import { spawn, execFileSync } from 'node:child_process';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';
import { existsSync } from 'node:fs';
import { startIdeServer } from './ideserver.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const PORT = Number(process.env.THREEDI_PORT ?? 8317);
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

const ide = await startIdeServer({ root: ROOT, port: PORT, log, fallbackPort: true });
const hash = new URLSearchParams({ token: ide.token, ...(file ? { file } : {}) });
const profile = join(homedir(), '.config', '3di', 'chrome');

const child = spawn(browser, [
  `--app=${ide.url}/#${hash}`,
  `--user-data-dir=${profile}`,
  '--class=3DI',
  '--window-size=1440,900',
  '--no-first-run',
  '--no-default-browser-check',
], { stdio: 'ignore' });
child.on('error', (e) => { log(`não abriu o navegador: ${e.message}`); process.exit(1); });

// O Chrome pode repassar a janela para uma instância já aberta do mesmo perfil e sair na hora;
// por isso o servidor só fecha quando nenhum editor estiver conectado (com uma folga inicial
// para a janela repassada se conectar).
child.on('exit', () => {
  if (ide.relay) process.exit(0);
  const started = Date.now();
  let idleChecks = 0;
  setInterval(() => {
    if (ide.clientCount() > 0) { idleChecks = 0; return; }
    if (Date.now() - started < 8000) return;
    if (++idleChecks >= 2) { log('nenhuma janela aberta; encerrando'); process.exit(0); }
  }, 2000);
});
