import { readFile, mkdir, lstat, realpath, writeFile } from 'node:fs/promises';
import { isAbsolute, join } from 'node:path';

export const SKILLS = [
  { name: '3di-scenes', description: 'Construção de cenas com medidas e layout semântico.' },
  { name: '3di-geometry-review', description: 'Revisão de apoios, alinhamentos, encaixes e múltiplas vistas antes de finalizar.' },
] as const;

export async function readSkills(root: string) {
  return Promise.all(SKILLS.map(async (skill) => ({ ...skill, uri: `threedi://skills/${skill.name}`, files: [{ path: 'SKILL.md', content: await readFile(join(root, 'skills', skill.name, 'SKILL.md'), 'utf8') }] })));
}

export async function installSkills(root: string, workspace: string, target: 'agents' | 'claude' | 'both' = 'both') {
  if (!isAbsolute(workspace)) throw new Error('workspace deve ser o caminho absoluto da pasta de trabalho do agente.');
  const destination = await realpath(workspace);
  if (!(await lstat(destination)).isDirectory()) throw new Error('workspace deve ser uma pasta existente.');
  const skills = await readSkills(root);
  const folders = target === 'both' ? ['.agents', '.claude'] : [target === 'agents' ? '.agents' : '.claude'];
  const installed: string[] = [], unchanged: string[] = [], conflicts: string[] = [];
  // Refuse links in managed destinations; never follow a skill directory outside the workspace.
  const ensureDirectory = async (path: string) => {
    try { await mkdir(path); } catch (e: any) { if (e.code !== 'EEXIST') throw e; }
    const stat = await lstat(path);
    if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error(`Destino não é uma pasta normal: ${path}`);
  };
  for (const folder of folders) {
    await ensureDirectory(join(destination, folder));
    await ensureDirectory(join(destination, folder, 'skills'));
    for (const skill of skills) {
      const skillDir = join(destination, folder, 'skills', skill.name);
      await ensureDirectory(skillDir);
      for (const file of skill.files) {
        const path = join(skillDir, file.path);
        try { await writeFile(path, file.content, { flag: 'wx' }); installed.push(path); }
        catch (e: any) {
          if (e.code !== 'EEXIST') throw e;
          const stat = await lstat(path);
          if (stat.isFile() && !stat.isSymbolicLink() && await readFile(path, 'utf8') === file.content) unchanged.push(path);
          else conflicts.push(path);
        }
      }
    }
  }
  return { workspace: destination, installed, unchanged, conflicts,
    instruction: 'Leia as duas SKILL.md e aplique a revisão antes de finalizar. Se o cliente não redescobrir skills nesta sessão, use get_skill ou leia os arquivos diretamente. Arquivos diferentes foram preservados.' };
}
