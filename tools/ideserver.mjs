// Servidor HTTP da IDE + ponte com o editor aberto (usado pelo MCP e pelo app desktop).
//  - serve os arquivos do projeto (sem cache);
//  - /bridge/events (SSE): o editor recebe comandos;  /bridge/reply (POST): responde;
//  - /bridge/call (POST {cmd, args}): repassa um comando ao editor e devolve a resposta
//    (é assim que uma segunda instância usa o editor desta).
import http from 'node:http';
import { readFile, writeFile, mkdir, realpath } from 'node:fs/promises';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { extname, join, resolve, relative, sep, isAbsolute, dirname } from 'node:path';
import { homedir } from 'node:os';
import { randomBytes } from 'node:crypto';
import { readDocumentation } from './documentation.mjs';

// Token que libera /fs/read e /fs/write: fica em ~/.config/3di/token (só o usuário lê) e é
// passado para a janela do app no endereço (#token=...). Todas as instâncias usam o mesmo.
export function appToken() {
  const file = join(homedir(), '.config', '3di', 'token');
  try { return readFileSync(file, 'utf8').trim(); } catch {}
  const t = randomBytes(24).toString('hex');
  mkdirSync(dirname(file), { recursive: true, mode: 0o700 });
  writeFileSync(file, t, { mode: 0o600 });
  return t;
}

const FS_READ = new Set(['.3di']);
const FS_WRITE = new Set(['.3di', '.glb', '.png']);

const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json',
  '.css': 'text/css', '.png': 'image/png', '.svg': 'image/svg+xml', '.glb': 'model/gltf-binary',
  '.3di': 'text/plain; charset=utf-8', '.md': 'text/markdown; charset=utf-8',
};

const MAX_BODY = 32 * 1024 * 1024;
async function readBody(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY) throw Object.assign(new Error('requisição grande demais'), { status: 413 });
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}
async function readJson(req) {
  try {
    const value = JSON.parse((await readBody(req)).toString('utf8'));
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error();
    return value;
  } catch (e) {
    if (e.status) throw e;
    throw Object.assign(new Error('JSON inválido'), { status: 400 });
  }
}
const within = (root, path) => {
  const rel = relative(root, path);
  return !isAbsolute(rel) && rel !== '..' && !rel.startsWith(`..${sep}`);
};

// Pergunta se quem está na porta é um servidor 3DI (responde em /bridge/call).
export async function isIdeServer(port, token = appToken()) {
  try {
    const r = await fetch(`http://127.0.0.1:${port}/bridge/call`, { method: 'POST', headers: { 'X-3DI-Token': token }, signal: AbortSignal.timeout(2000), body: JSON.stringify({ cmd: 'ping', args: {} }) });
    const j = await r.json();
    return typeof j.ok === 'boolean';
  } catch {
    return false;
  }
}

/**
 * Sobe o servidor. Pode reutilizar outro editor 3DI na mesma porta quando reuse=true.
 * Com reuse=false, mantém uma instância própria e usa uma porta livre se fallbackPort=true.
 */
export async function startIdeServer({ root, port = 8317, log = () => {}, fallbackPort = false, reuse = true, token = appToken() } = {}) {
  root = await realpath(root);
  const clients = new Set();
  const pending = new Map();
  let nextId = 1;
  let onClients = () => {};

  const callLocal = (cmd, args = {}, timeoutMs = cmd === 'glbCheck' ? 180000 : 30000) => {
    const client = [...clients].at(-1);
    if (!client) return Promise.reject(new Error(`nenhum editor conectado: abra http://localhost:${port} no navegador ou o app 3DI`));
    const id = nextId++;
    client.write(`data: ${JSON.stringify({ id, cmd, args })}\n\n`);
    return new Promise((res, rej) => {
      const timer = setTimeout(() => { pending.delete(id); rej(new Error(`o editor não respondeu a '${cmd}'`)); }, timeoutMs);
      pending.set(id, { resolve: res, reject: rej, timer });
    });
  };

  const server = http.createServer((req, res) => {
    handle(req, res).catch((e) => {
      if (res.headersSent) { res.destroy(); return; }
      res.writeHead(e.status ?? 500, { 'Content-Type': 'text/plain; charset=utf-8' }).end(e.status ? e.message : 'erro interno');
    });
  });
  const handle = async (req, res) => {
    const host = req.headers.host;
    if (host !== `localhost:${port}` && host !== `127.0.0.1:${port}`) { res.writeHead(403).end(); return; }
    if (req.headers.origin && req.headers.origin !== `http://${host}`) { res.writeHead(403).end(); return; }
    const url = new URL(req.url, `http://${host}`);
    if (url.pathname === '/integration/config' && req.method === 'GET') {
      res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }).end(JSON.stringify({ root, port }));
      return;
    }
    if (url.pathname.startsWith('/docs/') && !url.pathname.endsWith('.md') && req.method === 'GET') {
      try {
        const doc = await readDocumentation(url.pathname.slice('/docs/'.length));
        res.writeHead(200, { 'Content-Type': 'text/markdown; charset=utf-8', 'Cache-Control': 'no-store' }).end(doc.text);
      } catch { res.writeHead(404).end('documento não encontrado'); }
      return;
    }
    if (url.pathname === '/bridge/session' && req.method === 'GET') {
      if (req.headers['x-3di-client'] !== 'ide') { res.writeHead(403).end(); return; }
      res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }).end(JSON.stringify({ token }));
      return;
    }
    if (url.pathname.startsWith('/bridge/')) {
      const supplied = url.pathname === '/bridge/events' ? url.searchParams.get('token') : req.headers['x-3di-token'];
      if (supplied !== token) { res.writeHead(403).end(); return; }
    }
    if (url.pathname === '/bridge/events') {
      res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', Connection: 'keep-alive' });
      res.write(': conectado\n\n');
      clients.add(res);
      onClients(clients.size);
      const ping = setInterval(() => res.write(': ping\n\n'), 15000);
      req.on('close', () => { clearInterval(ping); clients.delete(res); onClients(clients.size); });
      log(`editor conectado (${clients.size})`);
      return;
    }
    if (url.pathname === '/bridge/reply' && req.method === 'POST') {
      const msg = await readJson(req);
      const p = pending.get(msg.id);
      if (p) {
        clearTimeout(p.timer);
        pending.delete(msg.id);
        msg.ok ? p.resolve(msg.result) : p.reject(new Error(msg.error));
      }
      res.writeHead(204).end();
      return;
    }
    if (url.pathname === '/bridge/call' && req.method === 'POST') {
      const { cmd, args } = await readJson(req);
      const json = (o) => res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify(o));
      if (cmd === 'ping') { json({ ok: true, result: 'pong' }); return; }
      try { json({ ok: true, result: await callLocal(cmd, args) }); } catch (e) { json({ ok: false, error: e.message }); }
      return;
    }
    // arquivos do usuário (só com o token, só caminhos absolutos e extensões da IDE)
    if (url.pathname === '/fs/read' || url.pathname === '/fs/write') {
      const p = url.searchParams.get('path') ?? '';
      const allowed = url.pathname === '/fs/read' ? FS_READ : FS_WRITE;
      if (req.headers['x-3di-token'] !== token) { res.writeHead(403).end('token inválido'); return; }
      if (!isAbsolute(p) || !allowed.has(extname(p).toLowerCase())) { res.writeHead(400).end('caminho não permitido'); return; }
      try {
        if (url.pathname === '/fs/read') {
          res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' }).end(await readFile(p, 'utf8'));
        } else {
          const body = await readBody(req);
          await mkdir(dirname(p), { recursive: true });
          await writeFile(p, body);
          res.writeHead(204).end();
        }
      } catch (e) {
        res.writeHead(404).end(e.message);
      }
      return;
    }
    let pathname;
    try { pathname = decodeURIComponent(url.pathname); } catch { res.writeHead(400).end('URL inválida'); return; }
    const candidate = resolve(root, `.${pathname === '/' ? '/index.html' : pathname}`);
    if (!within(root, candidate)) { res.writeHead(403).end(); return; }
    try {
      const path = await realpath(candidate);
      if (!within(root, path)) { res.writeHead(403).end(); return; }
      const data = await readFile(path);
      res.writeHead(200, { 'Content-Type': MIME[extname(path)] ?? 'application/octet-stream', 'Cache-Control': 'no-store' }).end(data);
    } catch {
      res.writeHead(404).end('não encontrado');
    }
  };

  const listen = (p) => new Promise((res, rej) => {
    const onErr = (e) => { server.off('listening', onOk); rej(e); };
    const onOk = () => { server.off('error', onErr); res(server.address().port); };
    server.once('error', onErr);
    server.once('listening', onOk);
    server.listen(p, '127.0.0.1');
  });

  try {
    port = await listen(port);
  } catch (e) {
    if (e.code !== 'EADDRINUSE') throw e;
    if (await isIdeServer(port, token) && reuse) {
      log(`porta ${port} já tem um servidor 3DI: usando o editor dele`);
      const call = async (cmd, args) => {
        const r = await fetch(`http://127.0.0.1:${port}/bridge/call`, { method: 'POST', headers: { 'X-3DI-Token': token }, body: JSON.stringify({ cmd, args }) });
        const j = await r.json();
        if (!j.ok) throw new Error(j.error);
        return j.result;
      };
      return { relay: true, port, url: `http://localhost:${port}`, token, call, clientCount: () => 0, close() {} };
    }
    if (!fallbackPort) throw new Error(`porta ${port} em uso por outro programa; use --port`);
    port = await listen(0);
  }
  log(`IDE em http://localhost:${port}`);
  return {
    relay: false,
    port,
    url: `http://localhost:${port}`,
    token,
    call: callLocal,
    onClients: (fn) => { onClients = fn; },
    clientCount: () => clients.size,
    close: () => {
      for (const client of clients) client.end();
      for (const p of pending.values()) { clearTimeout(p.timer); p.reject(new Error('servidor encerrado')); }
      pending.clear();
      server.close();
      server.closeAllConnections();
    },
  };
}
