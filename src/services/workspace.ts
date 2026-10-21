import { lstat, realpath, readdir, readFile, writeFile, mkdir, link, unlink } from 'node:fs/promises';
import { resolve, relative, isAbsolute, dirname, basename, extname, sep } from 'node:path';

type EditorState = { path: string | null; dirty: boolean };
export interface WorkspaceHooks {
  state(): Promise<EditorState>;
  open(file: { path: string; name: string; text: string }): Promise<void>;
  detach(): Promise<void>;
  trash(path: string): Promise<void>;
  validate(code: string): Promise<unknown>;
}

export class SceneWorkspace {
  private root: string | null = null;
  private queue: Promise<unknown> = Promise.resolve();
  constructor(private hooks: WorkspaceHooks) {}
  private serial<T>(fn: () => Promise<T>): Promise<T> {
    const result = this.queue.then(fn); this.queue = result.catch(() => {}); return result;
  }
  info() { return { workspace: this.root, extensions: ['.3di'], deletion: 'trash', paths: 'relative' }; }
  set(path: string, discardApproved = false) { return this.serial(async () => {
    if (!isAbsolute(path)) throw new Error('Informe uma pasta absoluta para selecionar o workspace.');
    const next = await realpath(path);
    if (!(await lstat(next)).isDirectory()) throw new Error('Workspace deve ser uma pasta.');
    const state = await this.hooks.state();
    if (!discardApproved && this.root !== next && state.dirty) throw new Error('Salve as alterações antes de trocar o workspace.');
    this.root = next; return this.info();
  }); }
  private async checked(path: string, createParents = false, directory = false) {
    if (!this.root) throw new Error('Selecione um workspace no app ou com set_workspace.');
    if (!path || isAbsolute(path) || path.includes('\\') || path.includes('\0') || path.split('/').some((p) => p === '..' || p === '.')) throw new Error('Use um caminho relativo sem .. ou barras invertidas.');
    if (!directory && extname(path).toLowerCase() !== '.3di') throw new Error('Somente arquivos .3di são permitidos.');
    const full = resolve(this.root, path);
    const rel = relative(this.root, full);
    if (!rel || isAbsolute(rel) || rel === '..' || rel.startsWith(`..${sep}`)) throw new Error('Caminho fora do workspace.');
    const segments = rel.split(sep);
    let current = this.root;
    for (let i = 0; i < segments.length; i++) {
      current = resolve(current, segments[i]);
      const parent = i < segments.length - 1;
      try {
        const stat = await lstat(current);
        if (stat.isSymbolicLink() || (parent && !stat.isDirectory())) throw new Error('Links simbólicos e caminhos especiais não são permitidos.');
        if (!parent && (directory ? !stat.isDirectory() : !stat.isFile())) throw new Error('Tipo de destino inválido.');
      } catch (e: any) {
        if (e.code !== 'ENOENT') throw e;
        if (parent && createParents) await mkdir(current);
        else if (parent || directory) throw e;
      }
    }
    return full;
  }
  list(path?: string) { return this.serial(async () => {
    if (!this.root) throw new Error('Selecione um workspace.');
    const dir = path ? await this.checked(path, false, true) : this.root;
    const files: { path: string; bytes: number }[] = [];
    let visited = 0;
    const walk = async (folder: string) => {
      for (const entry of await readdir(folder, { withFileTypes: true })) {
        if (++visited > 20000) throw new Error('Workspace muito grande; liste uma subpasta.');
        if (entry.name.startsWith('.') || ['node_modules', 'build', 'out'].includes(entry.name)) continue;
        const full = resolve(folder, entry.name);
        if (entry.isSymbolicLink()) continue;
        if (entry.isDirectory()) await walk(full);
        else if (entry.isFile() && extname(entry.name).toLowerCase() === '.3di') files.push({ path: relative(this.root!, full).split(sep).join('/'), bytes: (await lstat(full)).size });
      }
    };
    await walk(dir); return { ...this.info(), files: files.sort((a, b) => a.path.localeCompare(b.path)) };
  }); }
  read(path: string) { return this.serial(async () => {
    const full = await this.checked(path);
    const stat = await lstat(full);
    if (stat.size > 2000000) throw new Error('Cena excede 2 MB.');
    return { path, code: await readFile(full, 'utf8') };
  }); }
  create(path: string, code: string) { return this.serial(async () => {
    await this.hooks.validate(code);
    const full = await this.checked(path, true);
    await writeFile(full, code, { flag: 'wx' }); return { created: path };
  }); }
  open(path: string) { return this.serial(async () => {
    const full = await this.checked(path);
    const state = await this.hooks.state();
    if (state.dirty) throw new Error('Salve as alterações antes de abrir outra cena.');
    if ((await lstat(full)).size > 2000000) throw new Error('Cena excede 2 MB.');
    await this.hooks.open({ path: full, name: basename(full), text: await readFile(full, 'utf8') });
    return { opened: path };
  }); }
  move(source: string, destination: string) { return this.serial(async () => {
    const from = await this.checked(source), to = await this.checked(destination, true);
    if (from === to) return { moved: source, to: destination };
    const state = await this.hooks.state(); const active = state.path === from;
    if (active && state.dirty) throw new Error('Salve a cena antes de movê-la.');
    // link is exclusive: unlike rename(), an existing destination is never overwritten.
    await link(from, to);
    try { await unlink(from); } catch (e) { await unlink(to); throw e; }
    if (active) {
      try { await this.hooks.open({ path: to, name: basename(to), text: await readFile(to, 'utf8') }); }
      catch (e) { await link(to, from); await unlink(to); throw e; }
    }
    return { moved: source, to: destination };
  }); }
  delete(path: string) { return this.serial(async () => {
    const full = await this.checked(path);
    const state = await this.hooks.state(); const active = state.path === full;
    if (active && state.dirty) throw new Error('Salve a cena antes de removê-la.');
    // Detach before trashing so a later Save cannot silently recreate the deleted path.
    if (active) await this.hooks.detach();
    await this.hooks.trash(full);
    return { trashed: path, editor: active ? 'Cena preservada como rascunho sem caminho.' : 'unchanged' };
  }); }
}
