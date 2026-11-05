import { AgentSession, agentStatus } from './agents.mjs';
import { ffmpegPath, ttsStatus, installTts, removeTts, speech, synthesize, clipFile, toSrt, scriptRange, frameEncoder, muxVideo } from './video.mjs';
import { loadSettings, saveSettings, TTS_MODELS, SPEAKERS } from './settings.mjs';
import { createReadStream } from 'node:fs';
import { mkdir as mkdirP, writeFile as writeFileP, rm as rmP, access } from 'node:fs/promises';
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
// agents (opcional): { mcpEndpoint(): url do MCP do 3DI, cwd(): pasta onde o agente trabalha }
// video (opcional): { dir(): pasta onde os vídeos são gravados }
export async function startIdeServer({ root, port = 8317, log = () => {}, fallbackPort = false, reuse = true, token = appToken(), agents = null, video = null } = {}) {
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

  // ---- agentes (Claude Code / Codex) no painel Agente da IDE: uma conversa por vez ----
  const agentClients = new Set();
  const agentLog = []; // eventos da conversa atual, reenviados a quem reconecta
  let agent = null;
  const agentEmit = (e) => {
    const ev = { ...e, at: Date.now() };
    // trechos parciais de texto não vão para o histórico: a mensagem final substitui
    if (!(ev.kind === 'text' && ev.delta)) { agentLog.push(ev); if (agentLog.length > 800) agentLog.splice(0, agentLog.length - 800); }
    for (const c of agentClients) c.write(`data: ${JSON.stringify(ev)}\n\n`);
  };

  // ---- vídeo: a IDE desenha os quadros e os envia; aqui viram MP4 com falas e legendas ----
  const videoClients = new Set();
  const videoEmit = (e) => { for (const c of videoClients) c.write(`data: ${JSON.stringify(e)}\n\n`); };
  const videoJobs = new Map();
  let ttsInstall = null;
  let nextVideo = 1;
  const freeName = async (dir, name) => {
    for (let i = 0; ; i++) {
      const file = join(dir, `${name}${i ? `-${i + 1}` : ''}.mp4`);
      try { await access(file); } catch { return file; }
    }
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
        const doc = await readDocumentation(url.pathname.slice('/docs/'.length), root);
        res.writeHead(200, { 'Content-Type': 'text/markdown; charset=utf-8', 'Cache-Control': 'no-store' }).end(doc.text);
      } catch { res.writeHead(404).end('documento não encontrado'); }
      return;
    }
    if (url.pathname === '/bridge/session' && req.method === 'GET') {
      if (req.headers['x-3di-client'] !== 'ide') { res.writeHead(403).end(); return; }
      res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }).end(JSON.stringify({ token }));
      return;
    }
    if (/^\/(bridge|agent|video|settings)(\/|$)/.test(url.pathname)) {
      // EventSource e <audio> não mandam cabeçalhos: o token vai na URL
      const supplied = url.pathname.endsWith('/events') || url.pathname === '/video/clip' ? url.searchParams.get('token') : req.headers['x-3di-token'];
      if (supplied !== token) { res.writeHead(403).end(); return; }
    }
    if (url.pathname === '/settings') {
      const json = (o, code = 200) => res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }).end(JSON.stringify(o));
      if (req.method === 'GET') { json({ settings: loadSettings(), ttsModels: TTS_MODELS, speakers: SPEAKERS }); return; }
      if (req.method !== 'POST') { res.writeHead(405).end(); return; }
      let body = '';
      for await (const chunk of req) { body += chunk; if (body.length > 1e5) { res.writeHead(413).end(); return; } }
      try { json({ settings: saveSettings(JSON.parse(body || '{}')) }); } catch (e) { json({ error: e.message }, 400); }
      return;
    }
    if (url.pathname.startsWith('/video/')) {
      const json = (o, code = 200) => res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }).end(JSON.stringify(o));
      // fala do cache para o preview tocar
      if (url.pathname === '/video/clip' && req.method === 'GET') {
        const f = clipFile(String(url.searchParams.get('k') ?? ''));
        try { await access(f); } catch { res.writeHead(404).end(); return; }
        res.writeHead(200, { 'Content-Type': 'audio/wav', 'Cache-Control': 'max-age=86400' });
        createReadStream(f).pipe(res);
        return;
      }
      if (url.pathname === '/video/status' && req.method === 'GET') { json({ tts: ttsStatus(root), installing: !!ttsInstall, ffmpeg: ffmpegPath(root) }); return; }
      if (url.pathname === '/video/events') {
        res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', Connection: 'keep-alive' });
        res.write(': ok\n\n');
        videoClients.add(res);
        req.on('close', () => videoClients.delete(res));
        return;
      }
      if (req.method !== 'POST') { res.writeHead(405).end(); return; }
      const job = videoJobs.get(Number(url.searchParams.get('id')));
      if (url.pathname === '/video/frame') {
        if (!job) { json({ error: 'vídeo desconhecido' }, 404); return; }
        const chunks = [];
        for await (const c of req) chunks.push(c);
        await job.enc.write(Buffer.concat(chunks));
        json({ ok: true });
        return;
      }
      let body = '';
      for await (const chunk of req) { body += chunk; if (body.length > 4e6) { res.writeHead(413).end(); return; } }
      let args = {};
      try { args = body ? JSON.parse(body) : {}; } catch { json({ error: 'JSON inválido' }, 400); return; }
      // falas do roteiro para o preview: gera o que faltar (cache) e devolve os trechos já reagendados
      if (url.pathname === '/video/speech') {
        try {
          const script = (args.script ?? []).map((l) => ({ ...l }));
          const clips = await speech(script, args.voices ?? {}, { root, tts: loadSettings().tts, log: (text) => videoEmit({ kind: 'log', text }) });
          json({ clips: clips.map(({ key, start, seconds }) => ({ key, start, seconds })), script });
        } catch (e) { json({ error: e.message }, 500); }
        return;
      }
      // ouvir uma voz nas configurações
      if (url.pathname === '/video/sample') {
        try {
          const tts = loadSettings().tts;
          const [clip] = await synthesize([{ text: String(args.text || 'Olá! Esta é a minha voz no três D I.').slice(0, 300), speaker: String(args.speaker || tts.speaker), language: String(args.language || tts.language), instruct: args.instruct ?? tts.instruct }], { root, tts, log: (text) => videoEmit({ kind: 'log', text }) });
          json({ key: clip.key, seconds: clip.seconds });
        } catch (e) { json({ error: e.message }, 500); }
        return;
      }
      if (url.pathname === '/video/remove-tts') {
        if (ttsInstall) { json({ error: 'a instalação ainda está em andamento' }, 409); return; }
        await removeTts();
        json({ ok: true });
        return;
      }
      if (url.pathname === '/video/install-tts') {
        if (!ttsInstall) {
          ttsInstall = installTts((line) => videoEmit({ kind: 'log', text: line }))
            .then(() => videoEmit({ kind: 'tts-ready' }), (e) => videoEmit({ kind: 'error', text: e.message }))
            .finally(() => { ttsInstall = null; });
        }
        json({ ok: true });
        return;
      }
      if (url.pathname === '/video/start') {
        const dir = await (video?.dir?.() ?? join(root, 'out'));
        await mkdirP(dir, { recursive: true });
        const name = String(args.name || 'video').replace(/[^\w.-]+/g, '-').replace(/\.mp4$/i, '') || 'video';
        const output = await freeName(dir, name);
        const id = nextVideo++;
        const frames = `${output}.quadros.mp4`;
        videoJobs.set(id, { id, output, frames, fps: Number(args.fps) || 30, enc: frameEncoder(ffmpegPath(root), frames, Number(args.fps) || 30) });
        json({ id, output });
        return;
      }
      if (url.pathname === '/video/cancel') {
        if (job) { job.enc.kill(); videoJobs.delete(job.id); await rmP(job.frames, { force: true }); }
        json({ ok: true });
        return;
      }
      if (url.pathname === '/video/finish') {
        if (!job) { json({ error: 'vídeo desconhecido' }, 404); return; }
        videoJobs.delete(Number(url.searchParams.get('id')));
        try {
          await job.enc.close();
          const from = Number(args.from) || 0, to = Number(args.to);
          const script = args.subs === false && args.audio === false ? [] : scriptRange(args.script ?? [], from, to);
          const log = (text) => videoEmit({ kind: 'log', text });
          const clips = args.audio === false ? [] : await speech(script, args.voices ?? {}, { root, tts: loadSettings().tts, log });
          const srt = args.subs !== false && script.length ? job.output.replace(/\.mp4$/, '.srt') : null;
          if (srt) await writeFileP(srt, toSrt(script));
          log('juntando vídeo, falas e legendas');
          await muxVideo(ffmpegPath(root), { frames: job.frames, output: job.output, clips, script: args.subs === false ? [] : script, srt, burn: !!args.burn, duration: to - from });
          json({ ok: true, output: job.output, srt, falas: clips.length });
        } catch (e) { json({ error: e.message }, 500); }
        finally { await rmP(job.frames, { force: true }); }
        return;
      }
      res.writeHead(404).end();
      return;
    }
    if (url.pathname.startsWith('/agent/')) {
      const json = (o, code = 200) => res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }).end(JSON.stringify(o));
      if (!agents) { json({ error: 'agentes indisponíveis neste servidor' }, 404); return; }
      if (url.pathname === '/agent/status' && req.method === 'GET') {
        json({ agents: agentStatus(), active: agent ? { provider: agent.provider, busy: agent.busy, session: agent.session, model: agent.model } : null, cwd: await agents.cwd(), mcp: agents.mcpEndpoint() });
        return;
      }
      if (url.pathname === '/agent/events') {
        res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', Connection: 'keep-alive' });
        res.write(`data: ${JSON.stringify({ kind: 'history', events: agentLog })}\n\n`);
        agentClients.add(res);
        req.on('close', () => agentClients.delete(res));
        return;
      }
      if (req.method !== 'POST') { res.writeHead(405).end(); return; }
      let body = '';
      for await (const chunk of req) { body += chunk; if (body.length > 1e6) { res.writeHead(413).end(); return; } }
      let args = {};
      try { args = body ? JSON.parse(body) : {}; } catch { json({ error: 'JSON inválido' }, 400); return; }
      if (url.pathname === '/agent/send') {
        const text = String(args.text ?? '').trim();
        if (!text) { json({ error: 'mensagem vazia' }, 400); return; }
        if (agent?.busy) { json({ error: 'o agente ainda está respondendo' }, 409); return; }
        const provider = args.provider === 'codex' ? 'codex' : 'claude';
        const model = args.model ? String(args.model) : null;
        // trocar de agente ou de modelo começa outra conversa
        if (!agent || agent.provider !== provider || agent.model !== model) {
          agent = new AgentSession({ provider, model, cwd: await agents.cwd(), mcpEndpoint: agents.mcpEndpoint(), emit: agentEmit });
          agentLog.length = 0;
          agentEmit({ kind: 'reset', provider, model });
        }
        agentEmit({ kind: 'user', text });
        try { agent.run(text).catch((e) => agentEmit({ kind: 'error', text: e.message })); }
        catch (e) { agentEmit({ kind: 'error', text: e.message }); agentEmit({ kind: 'done', stopped: false }); }
        json({ ok: true });
        return;
      }
      if (url.pathname === '/agent/stop') { agent?.stop(); json({ ok: true }); return; }
      if (url.pathname === '/agent/reset') {
        agent?.stop();
        agent = null;
        agentLog.length = 0;
        agentEmit({ kind: 'reset' });
        json({ ok: true });
        return;
      }
      res.writeHead(404).end();
      return;
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
      agent?.stop();
      for (const c of agentClients) c.end();
      for (const client of clients) client.end();
      for (const p of pending.values()) { clearTimeout(p.timer); p.reject(new Error('servidor encerrado')); }
      pending.clear();
      server.close();
      server.closeAllConnections();
    },
  };
}
