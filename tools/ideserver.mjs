// Servidor HTTP da IDE + ponte com o editor aberto (usado pelo MCP e pelo app desktop).
//  - serve os arquivos do projeto (sem cache);
//  - /bridge/events (SSE): o editor recebe comandos;  /bridge/reply (POST): responde;
//  - /bridge/call (POST {cmd, args}): repassa um comando ao editor e devolve a resposta
//    (é assim que uma segunda instância usa o editor desta).
import http from 'node:http';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { extname, join, normalize, isAbsolute, dirname } from 'node:path';
import { homedir } from 'node:os';
import { randomBytes } from 'node:crypto';

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

const readBody = (req) => new Promise((res) => { let b = ''; req.on('data', (c) => { b += c; }); req.on('end', () => res(b)); });

// Pergunta se quem está na porta é um servidor 3DI (responde em /bridge/call).
export async function isIdeServer(port) {
  try {
    const r = await fetch(`http://127.0.0.1:${port}/bridge/call`, { method: 'POST', body: JSON.stringify({ cmd: 'ping', args: {} }) });
    const j = await r.json();
    return typeof j.ok === 'boolean';
  } catch {
    return false;
  }
}

/**
 * Sobe o servidor. Se a porta estiver ocupada por outro servidor 3DI, não sobe e devolve
 * { relay: true }: os comandos vão para ele. Se estiver ocupada por outro programa e
 * fallbackPort for true, usa uma porta livre qualquer.
 */
export async function startIdeServer({ root, port = 8317, log = () => {}, fallbackPort = false } = {}) {
  const token = appToken();
  const clients = new Set();
  const pending = new Map();
  let nextId = 1;
  let onClients = () => {};

  const callLocal = (cmd, args = {}, timeoutMs = 30000) => {
    const client = [...clients].at(-1);
    if (!client) return Promise.reject(new Error(`nenhum editor conectado: abra http://localhost:${port} no navegador ou o app 3DI`));
    const id = nextId++;
    client.write(`data: ${JSON.stringify({ id, cmd, args })}\n\n`);
    return new Promise((res, rej) => {
      const timer = setTimeout(() => { pending.delete(id); rej(new Error(`o editor não respondeu a '${cmd}'`)); }, timeoutMs);
      pending.set(id, { resolve: res, reject: rej, timer });
    });
  };

  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://localhost');
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
      const msg = JSON.parse(await readBody(req));
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
      const { cmd, args } = JSON.parse(await readBody(req));
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
          const chunks = [];
          for await (const c of req) chunks.push(c);
          await mkdir(dirname(p), { recursive: true });
          await writeFile(p, Buffer.concat(chunks));
          res.writeHead(204).end();
        }
      } catch (e) {
        res.writeHead(404).end(e.message);
      }
      return;
    }
    const path = normalize(join(root, decodeURIComponent(url.pathname === '/' ? '/index.html' : url.pathname)));
    if (!path.startsWith(root)) { res.writeHead(403).end(); return; }
    try {
      const data = await readFile(path);
      res.writeHead(200, { 'Content-Type': MIME[extname(path)] ?? 'application/octet-stream', 'Cache-Control': 'no-store' }).end(data);
    } catch {
      res.writeHead(404).end('não encontrado');
    }
  });

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
    if (await isIdeServer(port)) {
      log(`porta ${port} já tem um servidor 3DI: usando o editor dele`);
      const call = async (cmd, args) => {
        const r = await fetch(`http://127.0.0.1:${port}/bridge/call`, { method: 'POST', body: JSON.stringify({ cmd, args }) });
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
    close: () => server.close(),
  };
}
