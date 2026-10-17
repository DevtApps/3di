import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, rm, mkdir, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createRequire } from 'node:module';
import { createProject } from '../dist/project.mjs';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';

const require = createRequire(import.meta.url);
const { startMcp } = require('../dist/mcp.cjs');

test('new project creates agent instructions and refuses overwrite', async (t) => {
  const parent = await mkdtemp(join(tmpdir(), '3di-project-'));
  t.after(() => rm(parent, { recursive: true, force: true }));
  const root = await createProject(parent, 'Meu projeto', new URL('../skills/3di-scenes/SKILL.md', import.meta.url));
  assert.equal(JSON.parse(await readFile(join(root, '3di.json'), 'utf8')).scene, 'main.3di');
  assert.ok((await readFile(join(root, 'AGENTS.md'), 'utf8')).includes('get_documentation'));
  assert.ok((await readFile(join(root, '.agents/skills/3di-scenes/SKILL.md'), 'utf8')).includes('name: 3di-scenes'));
  assert.ok((await readFile(join(root, '.agents/skills/3di-geometry-review/SKILL.md'), 'utf8')).includes('name: 3di-geometry-review'));
  assert.ok((await readFile(join(root, '.claude/skills/3di-geometry-review/SKILL.md'), 'utf8')).includes('name: 3di-geometry-review'));
  await writeFile(join(root, 'main.3di'), 'meu trabalho');
  await assert.rejects(createProject(parent, 'Meu projeto', new URL('../skills/3di-scenes/SKILL.md', import.meta.url)), /EEXIST/);
  assert.equal(await readFile(join(root, 'main.3di'), 'utf8'), 'meu trabalho');
  await assert.rejects(createProject(parent, '../escape', new URL('../skills/3di-scenes/SKILL.md', import.meta.url)), /nome/);
});

test('Official MCP SDK HTTP supports two clients, documentation and engine tools without authentication', { timeout: 15000 }, async (t) => {
  let code = 'show(sphere())';
  const host = {
    getScript: async () => code,
    setScript: async (value) => { code = value; return 'ok'; },
    save: async () => 'saved',
    check: async () => ({ out: { leaves: 1, bbox: { min: [-1, -1, -1], max: [1, 1, 1] }, parts: [] }, logs: [] }),
    preview: async () => ({ png: 'image' }),
    exportGlb: async () => 'exported',
  };
  const root = new URL('../', import.meta.url).pathname;
  const server = await startMcp(host, decodeURIComponent(root), 0, () => {});
  t.after(() => server.stop());
  const first = new Client({ name: 'codex-test', version: '1.0.0' }, { capabilities: {} });
  const second = new Client({ name: 'claude-test', version: '1.0.0' }, { capabilities: {} });
  t.after(async () => { await first.close(); await second.close(); });
  await first.connect(new StreamableHTTPClientTransport(new URL(server.endpoint)));
  await second.connect(new StreamableHTTPClientTransport(new URL(server.endpoint)));
  assert.ok((await first.listTools()).tools.some((tool) => tool.name === 'set_script'));
  assert.equal((await second.listResources()).resources.length, 7);
  const docs = await first.readResource({ uri: 'threedi://docs/best-practices' });
  assert.ok(docs.contents[0].text.includes('check_script'));
  await first.callTool({ name: 'set_script', arguments: { code: 'show(box())' } });
  assert.equal((await second.callTool({ name: 'get_script' })).content[0].text, 'show(box())');
  assert.equal((await second.callTool({ name: 'check_script', arguments: { code: 42 } })).isError, true);
  const catalog = JSON.parse((await first.callTool({ name: 'list_skills' })).content[0].text);
  assert.equal(catalog.length, 2);
  const review = await second.readResource({ uri: 'threedi://skills/3di-geometry-review' });
  assert.ok(review.contents[0].text.includes('check_script'));
  const skill = JSON.parse((await first.callTool({ name: 'get_skill', arguments: { name: '3di-geometry-review' } })).content[0].text);
  assert.equal(skill.files[0].path, 'SKILL.md');
  const workspace = await mkdtemp(join(tmpdir(), '3di-install-'));
  t.after(() => rm(workspace, { recursive: true, force: true }));
  const install = async (args) => first.callTool({ name: 'install_skills', arguments: args });
  const installed = JSON.parse((await install({ workspace, target: 'both' })).content[0].text);
  assert.equal(installed.installed.length, 4);
  assert.equal(JSON.parse((await install({ workspace, target: 'both' })).content[0].text).unchanged.length, 4);
  const modified = join(workspace, '.agents/skills/3di-scenes/SKILL.md');
  await writeFile(modified, 'minhas instruções');
  const conflict = JSON.parse((await install({ workspace, target: 'agents' })).content[0].text);
  assert.deepEqual(conflict.conflicts, [modified]);
  assert.equal(await readFile(modified, 'utf8'), 'minhas instruções');
  assert.equal((await install({ workspace: '../relative' })).isError, true);
  const linked = join(workspace, 'linked'); await mkdir(linked);
  await symlink(join(workspace, '.agents'), join(linked, '.agents'));
  assert.equal((await install({ workspace: linked, target: 'agents' })).isError, true);
  const response = await fetch(server.endpoint.replace('/mcp', '/health'));
  assert.equal((await response.json()).endpoint, server.endpoint);
  const blocked = await fetch(server.endpoint.replace('/mcp', '/health'), { headers: { Origin: 'https://other.example' } });
  assert.equal(blocked.status, 403);
});
