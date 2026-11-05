#!/usr/bin/env node
// Agente falso para os testes: imita a saída JSON do `claude -p --output-format stream-json`
// ou do `codex exec --json`, conforme FAKE_AGENT, ecoando a mensagem recebida pelo stdin.
const kind = process.env.FAKE_AGENT;
if (process.argv.includes('--version')) { console.log(`fake-${kind} 1.0`); process.exit(0); }
let input = '';
process.stdin.on('data', (d) => { input += d; });
process.stdin.on('end', () => {
  const resume = process.argv.includes('--resume') || process.argv.includes('resume');
  const say = (o) => console.log(JSON.stringify(o));
  const text = `eco: ${input.trim().split('\n').pop()}${resume ? ' (retomado)' : ''}`;
  if (kind === 'claude') {
    say({ type: 'system', subtype: 'init', session_id: 'sess-1', model: 'fake' });
    say({ type: 'stream_event', event: { type: 'content_block_delta', delta: { type: 'text_delta', text: 'eco' } } });
    say({ type: 'assistant', message: { content: [{ type: 'tool_use', id: 't1', name: 'mcp__3di__set_script', input: { code: 'show(box())' } }] } });
    say({ type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: 't1', content: [{ type: 'text', text: '✓ 1 primitivas' }] }] } });
    say({ type: 'assistant', message: { content: [{ type: 'text', text }] } });
    say({ type: 'result', session_id: 'sess-1', total_cost_usd: 0.01, is_error: false });
  } else {
    say({ type: 'thread.started', thread_id: 'thread-1' });
    say({ type: 'item.started', item: { id: 'i1', type: 'mcp_tool_call', tool: 'screenshot', arguments: { view: 'grid' } } });
    say({ type: 'item.completed', item: { id: 'i1', type: 'mcp_tool_call', tool: 'screenshot', status: 'completed', result: {} } });
    say({ type: 'item.completed', item: { id: 'i2', type: 'agent_message', text } });
    say({ type: 'turn.completed', usage: { input_tokens: 1 } });
  }
});
