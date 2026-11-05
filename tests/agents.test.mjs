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
