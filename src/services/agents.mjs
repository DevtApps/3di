// Agentes de código (Claude Code e Codex) rodando direto no 3DI, como o Cooder faz: o servidor da
// IDE roda o CLI do agente na pasta do projeto, uma vez por mensagem, retomando a mesma conversa
// (claude --resume / codex exec resume), e transmite os eventos para o painel Agente da IDE.
// O agente recebe o MCP do 3DI: lê e altera a cena aberta, tira screenshots e confere o GLB.
//
// Eventos normalizados (enviados à IDE): { kind: 'start' | 'text' | 'tool' | 'tool-result' | 'session'
//   | 'done' | 'error' | 'log', ... }. 'text' traz delta (parcial) ou final (mensagem completa).
import { spawn, spawnSync, execFileSync } from 'node:child_process';
import { existsSync, readdirSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { loadSettings } from './settings.mjs';

const INSTRUCTIONS = 'Você está dentro do 3DI, um editor de cenas 3D por código. O usuário vê a cena aberta no editor ao lado deste chat. ' +
  'Você só tem as ferramentas do MCP "3di": documentação da linguagem e o código da cena aberta (mais o preview para conferir). ' +
  'Não há shell, arquivos, internet nem outros projetos: não tente acessá-los. Para saber como fazer algo (inclusive desempenho), ' +
  'consulte get_documentation (comece por topic="inicio") e describe_language; leia get_script antes de editar, valide com check_script, ' +
  'aplique com set_script e confira com screenshot(view="grid"). Se algo exigir mudar o 3DI em si (o motor, não a cena), diga isso ao usuário ' +
  'em vez de procurar o código-fonte. Responda em português, de forma curta.';

// Executável de cada agente. O atalho em ~/.local/bin pode apontar para uma instalação que sumiu:
// por isso cada candidato é testado com --version. O caminho escolhido em ⚙ → Agentes, ou
// THREEDI_CLAUDE / THREEDI_CODEX, vem primeiro. Lançado pelo menu, o app não tem o PATH do shell
// (nvm, pnpm): as pastas comuns de instalação global também são procuradas.
function candidates(name, custom) {
  const h = homedir();
  const list = [custom, process.env[`THREEDI_${name.toUpperCase()}`], name, join(h, '.local', 'bin', name),
    join(h, '.local', 'share', 'pnpm', name), join(h, '.npm-global', 'bin', name), join(h, '.bun', 'bin', name),
    join(h, '.claude', 'local', name), `/usr/local/bin/${name}`, `/usr/bin/${name}`];
  const pkg = name === 'codex' ? ['@openai', 'codex', 'bin', 'codex.js'] : ['@anthropic-ai', 'claude-code', 'cli.js'];
  const nvm = join(h, '.nvm', 'versions', 'node');
  try {
    for (const v of readdirSync(nvm).sort(byVersion)) list.push(join(nvm, v, 'bin', name), join(nvm, v, 'lib', 'node_modules', ...pkg));
  } catch {}
  return [...new Set(list.filter(Boolean))];
}
const byVersion = (a, b) => b.localeCompare(a, undefined, { numeric: true });

// Node para rodar um .js: o da mesma instalação do nvm, o do PATH, ou o próprio Electron como Node
function nodeFor(js) {
  const sibling = join(js.split('/lib/node_modules/')[0], 'bin', 'node');
  if (js.includes('/lib/node_modules/') && existsSync(sibling)) return { cmd: [sibling], env: {} };
  for (const n of ['node', join(homedir(), '.local', 'bin', 'node'), '/usr/local/bin/node', '/usr/bin/node']) {
    try { execFileSync(n, ['--version'], { timeout: 4000, stdio: 'ignore' }); return { cmd: [n], env: {} }; } catch {}
  }
  return { cmd: [process.execPath], env: process.versions.electron ? { ELECTRON_RUN_AS_NODE: '1' } : {} };
}

// Ambiente do agente: o do usuário, sem as variáveis de uma sessão do Claude Code que tenha aberto
// o 3DI (o claude filho se comportaria como sub-sessão dela)
export function agentEnv(base = process.env) {
  return Object.fromEntries(Object.entries(base).filter(([k]) => !/^(CLAUDE_CODE_|CLAUDE_AGENT_SDK|CLAUDECODE$|CLAUDE_PID$|CLAUDE_EFFORT$)/.test(k)));
}

const customPath = (name) => { try { return loadSettings().agents?.[name]?.path || null; } catch { return null; } };
const resolved = new Map();
// esquece o que foi achado (depois de instalar o CLI ou trocar o caminho nas configurações)
export function rescanAgents() { resolved.clear(); }
export function findAgent(name) {
  if (resolved.has(name)) return resolved.get(name);
  let found = null;
  const custom = customPath(name);
  const tried = [];
  for (const c of candidates(name, custom)) {
    if (c.includes('/') && !existsSync(c)) continue;
    const node = c.endsWith('.js') ? nodeFor(c) : null;
    const cmd = node ? [...node.cmd, c] : [c];
    const env = { ...agentEnv(), ...(node?.env ?? {}) };
    try {
      const out = execFileSync(cmd[0], [...cmd.slice(1), '--version'], { encoding: 'utf8', timeout: 8000, env, stdio: ['ignore', 'pipe', 'pipe'] }).trim();
      found = { cmd, env: node?.env ?? {}, version: out.split('\n').pop(), path: c };
      break;
    } catch (e) { tried.push(`${c}: ${String(e.stderr || e.message).trim().split('\n').find((l) => /error|not found|cannot/i.test(l)) ?? 'falhou'}`.slice(0, 200)); }
  }
  if (!found) found = null;
  resolved.set(name, found);
  if (!found) resolved.set(`${name}:tried`, { custom, tried });
  return found;
}

export function agentStatus() {
  return Object.fromEntries(['claude', 'codex'].map((n) => {
    const a = findAgent(n);
    if (a) return [n, { available: true, version: a.version, path: a.path }];
    const t = resolved.get(`${n}:tried`) ?? {};
    return [n, { available: false, custom: t.custom ?? null, tried: t.tried ?? [] }];
  }));
}

// Login do agente (o CLI tem de estar autenticado para responder)
export function agentLogin(name) {
  const a = findAgent(name);
  if (!a) return { ok: false, text: 'CLI não encontrado' };
  const args = name === 'codex' ? ['login', 'status'] : ['auth', 'status'];
  const r = spawnSync(a.cmd[0], [...a.cmd.slice(1), ...args], { encoding: 'utf8', timeout: 10000, env: { ...agentEnv(), ...a.env } });
  try { const j = JSON.parse(r.stdout); if ('loggedIn' in j) return { ok: !!j.loggedIn, text: j.loggedIn ? `logado (${j.authMethod ?? 'ok'})` : 'sem login: rode claude num terminal' }; } catch {}
  return { ok: r.status === 0, text: `${r.stdout ?? ''}${r.stderr ?? ''}`.trim().slice(0, 300) || (r.error?.message ?? '') };
}

// Ferramentas que o agente do painel pode usar: documentação, código da cena aberta e o preview para
// conferir. Arquivos, workspace, skills e exportação ficam de fora (o usuário faz pela IDE).
export const AGENT_TOOLS = ['get_documentation', 'describe_language', 'get_script', 'check_script', 'set_script', 'screenshot',
  'list_parts', 'frame', 'set_camera', 'set_time', 'check_glb', 'compare_reference'];
const BLOCKED_TOOLS = ['get_workspace', 'set_workspace', 'list_files', 'read_scene', 'create_scene', 'open_scene', 'move_scene',
  'delete_scene', 'install_skills', 'save_script', 'export_glb', 'set_reference'];

// ---------- Claude Code: claude -p --output-format stream-json ----------
function claudeArgs({ resume, mcpEndpoint, model }) {
  const args = ['-p', '--output-format', 'stream-json', '--verbose', '--include-partial-messages',
    // nenhuma ferramenta embutida (shell, leitura/edição de arquivos, busca, web): só o MCP do 3DI
    '--tools', '',
    // as do MCP permitidas rodam sem perguntar; as bloqueadas são negadas mesmo que as configurações do usuário liberem
    '--allowedTools', AGENT_TOOLS.map((t) => `mcp__3di__${t}`).join(','),
    '--disallowedTools', BLOCKED_TOOLS.map((t) => `mcp__3di__${t}`).join(','),
    '--append-system-prompt', INSTRUCTIONS];
  // só o MCP deste 3DI (um "3di" da configuração do usuário pode apontar para outra porta)
  if (mcpEndpoint) args.push('--strict-mcp-config', '--mcp-config', JSON.stringify({ mcpServers: { '3di': { type: 'http', url: mcpEndpoint } } }));
  if (model) args.push('--model', model);
  if (resume) args.push('--resume', resume);
  return args;
}

function claudeEvents(msg, emit, state) {
  if (msg.type === 'system' && msg.subtype === 'init') {
    state.session = msg.session_id;
    emit({ kind: 'session', id: msg.session_id, model: msg.model });
  } else if (msg.type === 'stream_event') {
    const e = msg.event;
    if (e?.type === 'content_block_delta' && e.delta?.type === 'text_delta') emit({ kind: 'text', delta: e.delta.text });
  } else if (msg.type === 'assistant') {
    for (const c of msg.message?.content ?? []) {
      if (c.type === 'text' && c.text) emit({ kind: 'text', final: c.text });
      else if (c.type === 'tool_use') emit({ kind: 'tool', id: c.id, name: c.name.replace(/^mcp__3di__/, ''), input: c.input });
    }
  } else if (msg.type === 'user') {
    for (const c of msg.message?.content ?? []) {
      if (c.type !== 'tool_result') continue;
      const text = Array.isArray(c.content) ? c.content.filter((x) => x.type === 'text').map((x) => x.text).join('\n') : String(c.content ?? '');
      const images = Array.isArray(c.content) ? c.content.filter((x) => x.type === 'image').length : 0;
      emit({ kind: 'tool-result', id: c.tool_use_id, error: !!c.is_error, text: text.slice(0, 2000), images });
    }
  } else if (msg.type === 'result') {
    state.session = msg.session_id ?? state.session;
    state.done = { cost: msg.total_cost_usd ?? null, error: msg.is_error ? (msg.result || 'erro') : null };
  }
}

// ---------- Codex: codex exec --json (prompt pelo stdin) ----------
const CODEX_OFF = ['shell_tool', 'unified_exec', 'shell_snapshot', 'apps', 'plugins', 'browser_use', 'browser_use_external', 'in_app_browser',
  'computer_use', 'image_generation', 'view_image', 'skill_search'];
function codexArgs({ resume, mcpEndpoint, model }) {
  // `exec resume` herda o sandbox da conversa e não aceita --sandbox. Sandbox só leitura e sem as
  // ferramentas embutidas (shell, exec, navegador, plugins, apps, imagens, web): só o MCP do 3DI.
  const args = resume ? ['exec', 'resume', '--json', '--skip-git-repo-check'] : ['exec', '--json', '--sandbox', 'read-only', '--skip-git-repo-check'];
  // sem AGENTS.md da pasta ou do usuário: o agente segue só as instruções do 3DI
  args.push('-c', 'approval_policy="never"', '-c', 'web_search="disabled"', '-c', 'project_doc_max_bytes=0');
  for (const f of CODEX_OFF) args.push('-c', `features.${f}=false`);
  if (mcpEndpoint) {
    args.push('-c', `mcp_servers.3di.url="${mcpEndpoint}"`, '-c', `mcp_servers.3di.enabled_tools=${JSON.stringify(AGENT_TOOLS)}`);
  }
  if (model) args.push('--model', model);
  if (resume) args.push(resume);
  args.push('-'); // lê o prompt do stdin
  return args;
}

function codexEvents(msg, emit, state) {
  const item = msg.item;
  if (msg.type === 'thread.started') {
    state.session = msg.thread_id;
    emit({ kind: 'session', id: msg.thread_id });
  } else if (msg.type === 'item.started' && item) {
    if (item.type === 'command_execution') emit({ kind: 'tool', id: item.id, name: 'shell', input: { command: item.command } });
    else if (item.type === 'mcp_tool_call') emit({ kind: 'tool', id: item.id, name: item.tool, input: item.arguments ?? {} });
  } else if (msg.type === 'item.completed' && item) {
    if (item.type === 'agent_message') emit({ kind: 'text', final: item.text });
    else if (item.type === 'command_execution') emit({ kind: 'tool-result', id: item.id, error: item.exit_code ? true : false, text: String(item.aggregated_output ?? '').slice(0, 2000) });
    else if (item.type === 'mcp_tool_call') emit({ kind: 'tool-result', id: item.id, error: item.status === 'failed', text: JSON.stringify(item.result ?? item.error ?? '').slice(0, 2000) });
    else if (item.type === 'file_change') emit({ kind: 'tool', id: item.id, name: 'arquivos', input: { changes: item.changes } });
  } else if (msg.type === 'turn.completed') {
    state.done = { cost: null, usage: msg.usage ?? null, error: null };
  } else if (msg.type === 'turn.failed' || msg.type === 'error') {
    state.done = { cost: null, error: msg.error?.message ?? msg.message ?? 'erro do Codex' };
  }
}

const PROVIDERS = {
  claude: { args: claudeArgs, events: claudeEvents, prompt: (text) => text },
  codex: { args: codexArgs, events: codexEvents, prompt: (text) => `${INSTRUCTIONS}\n\n${text}` },
};

// argumentos do CLI de cada agente (para conferir as restrições nos testes)
export const agentArgs = (provider, opts) => PROVIDERS[provider].args(opts);

// Um agente por conversa: run() processa uma mensagem e devolve quando o turno termina.
export class AgentSession {
  constructor({ provider, cwd, mcpEndpoint, model = null, emit }) {
    if (!PROVIDERS[provider]) throw new Error(`agente desconhecido '${provider}'; use claude ou codex`);
    this.provider = provider;
    this.cwd = cwd;
    this.mcpEndpoint = mcpEndpoint;
    this.model = model;
    this.emit = emit;
    this.session = null;
    this.proc = null;
    this.turns = 0;
  }

  get busy() { return !!this.proc; }

  stop() { this.proc?.kill('SIGTERM'); }

  run(text) {
    if (this.proc) throw new Error('o agente ainda está respondendo');
    const agent = findAgent(this.provider);
    if (!agent) throw new Error(`${this.provider === 'claude' ? 'Claude Code (claude)' : 'Codex (codex)'} não encontrado: instale o CLI e faça login`);
    const P = PROVIDERS[this.provider];
    // o Codex recebe as instruções só na primeira mensagem; nas seguintes a conversa já as tem
    const prompt = this.provider === 'codex' && this.turns ? text : P.prompt(text);
    const args = P.args({ resume: this.session, mcpEndpoint: this.mcpEndpoint, model: this.model });
    const proc = spawn(agent.cmd[0], [...agent.cmd.slice(1), ...args], { cwd: this.cwd, env: { ...agentEnv(), ...agent.env }, stdio: ['pipe', 'pipe', 'pipe'] });
    this.proc = proc;
    this.turns++;
    const state = { session: this.session, done: null };
    let buf = '', err = '';
    this.emit({ kind: 'start', provider: this.provider, version: agent.version });
    proc.stdout.on('data', (d) => {
      buf += d;
      let k;
      while ((k = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, k).trim();
        buf = buf.slice(k + 1);
        if (!line) continue;
        let msg;
        try { msg = JSON.parse(line); } catch { this.emit({ kind: 'log', text: line.slice(0, 500) }); continue; }
        try { P.events(msg, this.emit, state); } catch (e) { this.emit({ kind: 'log', text: `evento não reconhecido: ${e.message}` }); }
      }
    });
    proc.stderr.on('data', (d) => { err = (err + d).slice(-4000); });
    proc.stdin.end(prompt);
    return new Promise((resolve) => {
      const finish = (code, signal) => {
        if (this.proc !== proc) return;
        this.proc = null;
        this.session = state.session ?? this.session;
        const stopped = signal === 'SIGTERM';
        const error = stopped ? null : state.done?.error ?? (code ? (err.trim().split('\n').slice(-3).join('\n') || `o agente terminou com código ${code}`) : null);
        if (error) this.emit({ kind: 'error', text: error });
        this.emit({ kind: 'done', stopped, cost: state.done?.cost ?? null, session: this.session });
        resolve();
      };
      proc.on('exit', finish);
      proc.on('error', (e) => { err = e.message; finish(1, null); });
    });
  }
}
