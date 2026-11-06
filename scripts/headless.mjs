// Editor 3DI num Chrome sem janela (headless), controlado pelo protocolo DevTools num pipe.
// Usado por render.mjs (imagens das 4 vistas) e video.mjs (quadros do vídeo).
import { spawn } from 'node:child_process';
import { existsSync, mkdtempSync, readdirSync, rmSync } from 'node:fs';
import { createServer } from 'node:net';
import { homedir, tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url)));

// ---------- Chrome ----------

function findChrome() {
  const list = [process.env.CHROME, '/usr/bin/google-chrome', '/usr/bin/google-chrome-stable', '/usr/bin/chromium',
    '/usr/bin/chromium-browser', '/snap/bin/chromium',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe'];
  // navegadores baixados pelo Playwright
  const pw = process.env.PLAYWRIGHT_BROWSERS_PATH || join(homedir(), '.cache', 'ms-playwright');
  try {
    for (const d of readdirSync(pw).filter((d) => d.startsWith('chromium-')).sort().reverse()) {
      list.push(join(pw, d, 'chrome-linux', 'chrome'), join(pw, d, 'chrome-linux64', 'chrome'));
    }
  } catch {}
  return list.find((p) => p && existsSync(p));
}

// Protocolo DevTools pelo pipe (fd 3 = comandos, fd 4 = respostas, mensagens terminadas em \0):
// dispensa WebSocket e pacotes npm.
function devtools(proc) {
  const out = proc.stdio[3], inp = proc.stdio[4];
  let id = 0, buf = '';
  const waiting = new Map();
  inp.on('data', (chunk) => {
    buf += chunk.toString('utf8');
    let k;
    while ((k = buf.indexOf('\0')) >= 0) {
      const msg = JSON.parse(buf.slice(0, k));
      buf = buf.slice(k + 1);
      const w = waiting.get(msg.id);
      if (!w) continue;
      waiting.delete(msg.id);
      if (msg.error) w.reject(new Error(`${msg.error.message}`));
      else w.resolve(msg.result);
    }
  });
  return (method, params = {}, sessionId) => new Promise((resolve, reject) => {
    const msg = { id: ++id, method, params };
    if (sessionId) msg.sessionId = sessionId;
    waiting.set(msg.id, { resolve, reject });
    out.write(JSON.stringify(msg) + '\0');
  });
}

// ---------- servidor local ----------

function freePort() {
  return new Promise((resolve, reject) => {
    const s = createServer();
    s.once('error', reject);
    s.listen(0, '127.0.0.1', () => {
      const { port } = s.address();
      s.close(() => resolve(port));
    });
  });
}

async function waitHttp(url, ms) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    try {
      if ((await fetch(url)).ok) return;
    } catch {}
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error(`o servidor local não respondeu em ${url}`);
}

// ---------- principal ----------

const GPU_FLAGS = ['--enable-gpu', '--ignore-gpu-blocklist'];
// WebGL2 por software: funciona em qualquer máquina, com ou sem GPU
const CPU_FLAGS = ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'];

let server = null;
const browsers = new Set();
process.on('exit', () => {
  for (const b of browsers) b.kill();
  server?.kill('SIGKILL');
});
process.on('SIGINT', () => process.exit(130));

// Abre o Chrome headless numa aba com o editor carregado e a cena já compilada.
async function launch(chrome, url, flags, src) {
  const profile = mkdtempSync(join(tmpdir(), '3di-render-'));
  const proc = spawn(chrome, [
    '--headless=new', '--remote-debugging-pipe', `--user-data-dir=${profile}`,
    '--no-first-run', '--no-default-browser-check', '--disable-extensions', '--hide-scrollbars',
    '--mute-audio', '--window-size=1280,800', ...flags, 'about:blank',
  ], { stdio: ['ignore', 'ignore', 'pipe', 'pipe', 'pipe'] });
  const exited = new Promise((r) => proc.once('exit', r));
  let stderr = '';
  proc.stderr.on('data', (d) => { stderr = (stderr + d).slice(-4000); });
  const send = devtools(proc);
  const b = {
    kill: () => proc.kill('SIGKILL'),
    // fecha o Chrome e só então apaga o perfil (antes ele ainda está escrevendo nele)
    async close() {
      browsers.delete(b);
      send('Browser.close').catch(() => {});
      const timer = setTimeout(() => proc.kill('SIGKILL'), 3000);
      await exited;
      clearTimeout(timer);
      try { rmSync(profile, { recursive: true, force: true, maxRetries: 5 }); } catch {}
    },
  };
  browsers.add(b);
  const died = exited.then((code) => { throw new Error(`o Chrome terminou (código ${code})\n${stderr}`); });
  died.catch(() => {});

  const { targetId } = await Promise.race([send('Target.createTarget', { url: 'about:blank' }), died]);
  const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
  const page = (m, p) => Promise.race([send(m, p, sessionId), died]);
  b.evaluate = async (expression) => {
    const r = await page('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
    if (r.exceptionDetails) {
      throw new Error(r.exceptionDetails.exception?.description ?? r.exceptionDetails.text);
    }
    return r.result.value;
  };
  // captura da janela inteira (PNG em base64), para conferir a interface
  b.screenshot = async ({ width = 1440, height = 900 } = {}) => {
    await page('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: false });
    await new Promise((r) => setTimeout(r, 300));
    return (await page('Page.captureScreenshot', { format: 'png' })).data;
  };

  await page('Runtime.enable');
  await page('Page.enable');
  // o editor abre com o código salvo no localStorage: assim já compila a cena pedida
  // (e não o exemplo inicial), e o tdi.load abaixo reaproveita o shader pronto
  if (src !== null) await page('Page.addScriptToEvaluateOnNewDocument', {
    source: `try { localStorage.setItem('3di.code', ${JSON.stringify(src)}); } catch {}`,
  });
  await page('Page.navigate', { url });

  // espera o editor carregar e terminar a primeira compilação
  const deadline = Date.now() + 120000;
  for (;;) {
    const st = await b.evaluate(`window.tdi ? window.tdi.status() : (document.getElementById('status')?.textContent ?? '')`)
      .catch((e) => { if (/Chrome terminou/.test(e.message)) throw e; return ''; });
    b.webgl = !/WebGL2 não disponível/.test(st);
    if (/^[✓✗]/.test(st) || !b.webgl) break;
    if (Date.now() > deadline) throw new Error(`o editor não carregou (status: ${st || 'vazio'})`);
    await new Promise((r) => setTimeout(r, 100));
  }
  return b;
}


// Sobe o servidor local e abre o editor com a cena src compilada. Usa a GPU e cai para o
// SwiftShader (lento) sem WebGL2 ou com cpu = true. Devolve o navegador (evaluate, close).
export async function openEditor(src, { cpu = false, log = (m) => console.error(m) } = {}) {
  const chrome = findChrome();
  if (!chrome) throw new Error('Chrome/Chromium não encontrado. Instale um ou defina CHROME=/caminho/do/chrome');
  const port = await freePort();
  server = spawn('python3', [join(root, 'scripts', 'serve.py'), String(port)], { stdio: 'ignore' });
  const url = `http://127.0.0.1:${port}/index.html`;
  await waitHttp(url, 10000);
  let b = null;
  if (!cpu) {
    b = await launch(chrome, url, GPU_FLAGS, src).catch(() => null);
    if (b && !b.webgl) { await b.close(); b = null; }
    if (!b) log('aviso: sem WebGL2 na GPU, usando renderização por software (lenta)');
  }
  b ??= await launch(chrome, url, CPU_FLAGS, src);
  if (!b.webgl) throw new Error('WebGL2 não disponível no Chrome headless');
  return b;
}

// Abre uma IDE já em execução (ex.: o modo dev em http://localhost:8327) no Chrome headless.
export async function openUrl(url, { cpu = false } = {}) {
  const chrome = findChrome();
  if (!chrome) throw new Error('Chrome/Chromium não encontrado');
  return launch(chrome, url, cpu ? CPU_FLAGS : GPU_FLAGS, null);
}
