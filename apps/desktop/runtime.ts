import { startIdeServer } from '../../src/services/ideserver.mjs';
import { startMcp } from '../../src/services/mcp.js';
import { Engine } from '../../src/services/engine.js';
import { SceneWorkspace } from '../../src/services/workspace.js';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { dirname, resolve, relative, isAbsolute, join } from 'node:path';
import { mkdir, realpath, writeFile } from 'node:fs/promises';

export async function startRuntime(root: string, workerFile: string, options: { port?: number; mcpPort?: number | null; reuseIde?: boolean; log?: (s: string) => void; workspace?: string; onScenePath?: (path: string | null) => void; trash?: (path: string) => Promise<void> } = {}) {
  const log = options.log ?? console.log;
  const engine = new Engine(workerFile);
  let mcp: Awaited<ReturnType<typeof startMcp>> | undefined;
  const ide = await (startIdeServer as any)({ root, port: options.port ?? 8317, fallbackPort: true, reuse: options.reuseIde ?? false, log,
    integration: () => ({ endpoint: mcp?.endpoint ?? null }),
  });
  const workspace = new SceneWorkspace({
    state: () => ide.relay || ide.clientCount() ? ide.call('fileState') : Promise.resolve({ path: null, dirty: false }),
    validate: (code) => engine.run({ code }),
    open: async (file) => { await ide.call('openScene', file); options.onScenePath?.(file.path); },
    detach: async () => { await ide.call('detachScene'); options.onScenePath?.(null); },
    trash: options.trash ?? (async (path) => { await promisify(execFile)('gio', ['trash', path]); }),
  });
  try {
    if (options.workspace) await workspace.set(options.workspace);
    // mcpPort null: sem MCP (o modo dev pode rodar só a IDE)
    if (options.mcpPort !== null) mcp = await startMcp({
      workspace,
      getScript: () => ide.call('getScript'),
      setScript: async (code) => { await engine.run({ code }); return ide.call('setScript', { code }); },
      save: () => ide.call('save'),
      check: (code) => engine.run({ code }),
      preview: (command, args) => ide.call(command, args, 120000),
      exportGlb: async ({ code, path = 'out/cena.glb', res = 128 }) => {
        const state = await ide.call('fileState');
        if (!state.path) throw new Error('Salve a cena no app antes de exportar pelo MCP.');
        const sceneRoot = await realpath(dirname(state.path));
        const target = resolve(sceneRoot, path);
        const rel = relative(sceneRoot, target);
        if (isAbsolute(rel) || rel === '..' || rel.startsWith('../') || !target.endsWith('.glb')) throw new Error('Use um caminho .glb dentro da pasta da cena.');
        // Check every existing ancestor before creating directories or following links.
        let ancestor = dirname(target);
        for (;;) {
          try { const actual = await realpath(ancestor); const r = relative(sceneRoot, actual); if (isAbsolute(r) || r === '..' || r.startsWith('../')) throw new Error('Destino fora da pasta da cena.'); break; }
          catch (e: any) { if (e.code !== 'ENOENT') throw e; ancestor = dirname(ancestor); }
        }
        const result = await engine.run({ code: code ?? await ide.call('getScript'), task: 'export', res });
        await mkdir(dirname(target), { recursive: true });
        await writeFile(target, result.glb, { flag: 'wx' });
        return JSON.stringify({ path: target, ...result.stats });
      },
    }, root, options.mcpPort ?? 8318, log);
    return { ide, mcp, engine, workspace, stop: async () => { engine.dispose(); await mcp?.stop(); ide.close(); } };
  } catch (error) { engine.dispose(); ide.close(); throw error; }
}
