import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, mkdir, writeFile, rename, symlink, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { SceneWorkspace } from '../build/services/workspace.mjs';

async function setup(t) {
  const base = await mkdtemp(join(tmpdir(), '3di-files-'));
  t.after(() => rm(base, { recursive: true, force: true }));
  const root = join(base, 'project'); await mkdir(root);
  let editor = { path: null, dirty: false, text: '' };
  const service = new SceneWorkspace({
    state: async () => editor,
    open: async (file) => { if (editor.dirty) throw new Error('dirty'); editor = { ...file, dirty: false }; },
    detach: async () => { editor = { ...editor, path: null, dirty: true }; },
    trash: async (path) => rename(path, join(base, 'trashed.3di')),
    validate: async (code) => { if (!code.startsWith('show(')) throw new Error('invalid script'); },
  });
  await service.set(root);
  return { base, root, service, editor: () => editor, dirty: () => { editor.dirty = true; } };
}

test('workspace manages scenes, updates active path and preserves trashed text', async (t) => {
  const { base, root, service, editor } = await setup(t);
  await service.create('scenes/one.3di', 'show(sphere())');
  assert.equal((await service.list()).files[0].path, 'scenes/one.3di');
  assert.equal((await service.read('scenes/one.3di')).code, 'show(sphere())');
  await service.open('scenes/one.3di');
  await service.move('scenes/one.3di', 'final/renamed.3di');
  assert.equal(editor().path, join(root, 'final/renamed.3di'));
  await assert.rejects(readFile(join(root, 'scenes/one.3di')), { code: 'ENOENT' });
  await service.delete('final/renamed.3di');
  assert.equal(await readFile(join(base, 'trashed.3di'), 'utf8'), 'show(sphere())');
  assert.equal(editor().path, null); assert.equal(editor().dirty, true); assert.equal(editor().text, 'show(sphere())');
});

test('workspace refuses overwrite, escapes, links and invalid scenes', async (t) => {
  const { base, root, service } = await setup(t);
  await service.create('a.3di', 'show(sphere())');
  await service.create('b.3di', 'show(box())');
  await assert.rejects(service.create('a.3di', 'show(box())'), { code: 'EEXIST' });
  await assert.rejects(service.move('a.3di', 'b.3di'), { code: 'EEXIST' });
  assert.equal(await readFile(join(root, 'a.3di'), 'utf8'), 'show(sphere())');
  assert.equal(await readFile(join(root, 'b.3di'), 'utf8'), 'show(box())');
  for (const path of ['../escape.3di', '/tmp/escape.3di', 'file.txt', 'a/../../escape.3di', 'a\\escape.3di']) await assert.rejects(service.create(path, 'show(box())'));
  await assert.rejects(service.create('bad.3di', 'nonsense'), /invalid script/);
  await writeFile(join(base, 'outside.3di'), 'outside');
  await symlink(join(base, 'outside.3di'), join(root, 'link.3di'));
  await symlink(base, join(root, 'escape'));
  for (const path of ['link.3di', 'escape/outside.3di']) {
    await assert.rejects(service.read(path), /Links/);
    await assert.rejects(service.delete(path), /Links/);
  }
  assert.deepEqual((await service.list()).files.map((f) => f.path), ['a.3di', 'b.3di']);
});

test('workspace protects unsaved documents from navigation, moves and deletion', async (t) => {
  const { base, root, service, dirty } = await setup(t);
  await service.create('active.3di', 'show(sphere())');
  await service.open('active.3di'); dirty();
  await assert.rejects(service.open('active.3di'), /Salve/);
  await assert.rejects(service.move('active.3di', 'moved.3di'), /Salve/);
  await assert.rejects(service.delete('active.3di'), /Salve/);
  await assert.rejects(service.set(base), /Salve/);
  assert.equal(service.info().workspace, root);
  assert.equal(await readFile(join(root, 'active.3di'), 'utf8'), 'show(sphere())');
});
