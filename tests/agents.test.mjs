// Agentes no painel da IDE: os eventos do Claude Code e do Codex viram o mesmo formato, e a
// segunda mensagem retoma a conversa. Usa um agente falso (sem rede nem modelo).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const fake = fileURLToPath(new URL('./fixtures/fake-agent.mjs', import.meta.url));
process.env.THREEDI_CLAUDE = fake;
process.env.THREEDI_CODEX = fake;
const { AgentSession, agentEnv } = await import('../src/services/agents.mjs');

for (const provider of ['claude', 'codex']) {
  test(`${provider}: texto, ferramentas e retomada da conversa`, async () => {
    process.env.FAKE_AGENT = provider;
    const events = [];
    const a = new AgentSession({ provider, cwd: process.cwd(), mcpEndpoint: 'http://127.0.0.1:1/mcp', emit: (e) => events.push(e) });
    await a.run('desenhe um cubo');
    const finals = events.filter((e) => e.kind === 'text' && e.final).map((e) => e.final);
    assert.equal(finals.at(-1), 'eco: desenhe um cubo');
    const tool = events.find((e) => e.kind === 'tool');
    assert.equal(tool.name, provider === 'claude' ? 'set_script' : 'screenshot', 'nome da ferramenta sem o prefixo do MCP');
    assert.ok(events.some((e) => e.kind === 'tool-result' && e.id === tool.id && !e.error));
    assert.equal(events.at(-1).kind, 'done');
    assert.equal(a.session, provider === 'claude' ? 'sess-1' : 'thread-1');
    events.length = 0;
    await a.run('mais um');
    assert.equal(events.filter((e) => e.final).at(-1).final, 'eco: mais um (retomado)');
  });
}

test('o agente não herda as variáveis de uma sessão do Claude Code que abriu o 3DI', () => {
  const env = agentEnv({ PATH: '/bin', HOME: '/h', CLAUDE_CODE_SESSION_ID: 'x', CLAUDECODE: '1', ANTHROPIC_BASE_URL: 'u' });
  assert.deepEqual(Object.keys(env).sort(), ['ANTHROPIC_BASE_URL', 'HOME', 'PATH']);
});

test('os agentes do painel só têm o MCP do 3DI: sem shell, arquivos, web nem ferramentas de arquivo do MCP', async () => {
  const { agentArgs, AGENT_TOOLS } = await import('../src/services/agents.mjs');
  const c = agentArgs('claude', { mcpEndpoint: 'http://127.0.0.1:1/mcp' });
  assert.equal(c[c.indexOf('--tools') + 1], '', 'nenhuma ferramenta embutida');
  assert.ok(c.includes('--strict-mcp-config'));
  assert.ok(!c.includes('--permission-mode') || c[c.indexOf('--permission-mode') + 1] !== 'bypassPermissions');
  const allowed = c[c.indexOf('--allowedTools') + 1].split(',');
  assert.ok(allowed.every((t) => t.startsWith('mcp__3di__')) && allowed.includes('mcp__3di__get_documentation') && allowed.includes('mcp__3di__set_script'));
  const denied = c[c.indexOf('--disallowedTools') + 1];
  for (const t of ['delete_scene', 'set_workspace', 'install_skills', 'read_scene']) assert.ok(denied.includes(`mcp__3di__${t}`), t);
  const x = agentArgs('codex', { mcpEndpoint: 'http://127.0.0.1:1/mcp' }).join(' ');
  assert.ok(x.includes('--sandbox read-only'));
  for (const f of ['shell_tool', 'unified_exec', 'browser_use', 'computer_use', 'view_image']) assert.ok(x.includes(`features.${f}=false`), f);
  assert.ok(x.includes('web_search="disabled"') && x.includes('project_doc_max_bytes=0'));
  assert.ok(x.includes(`mcp_servers.3di.enabled_tools=${JSON.stringify(AGENT_TOOLS)}`));
  assert.ok(!AGENT_TOOLS.some((t) => /file|scene|workspace|skills|export/.test(t)));
});
