import test from 'node:test';
import assert from 'node:assert/strict';
import { integrationConfig } from '../src/integration-config.js';

test('integration config uses only a local HTTP endpoint', () => {
  const config = integrationConfig('http://127.0.0.1:18317/mcp');
  const server = JSON.parse(config.claude).mcpServers['3di'];
  assert.deepEqual(server, { type: 'http', url: 'http://127.0.0.1:18317/mcp' });
  assert.ok(config.codexCommand.includes('--url http://127.0.0.1:18317/mcp'));
  assert.ok(!config.codex.includes('command ='));
  for (const endpoint of ['file:///tmp/mcp', 'http://remote.example/mcp', 'http://127.0.0.1:8317/other']) assert.throws(() => integrationConfig(endpoint));
});

