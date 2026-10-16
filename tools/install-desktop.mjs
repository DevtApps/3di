#!/usr/bin/env node
// Instala o 3DI no menu de aplicativos (Linux/freedesktop): atalho com ícone e associação dos
// arquivos .3di ao app (abrir com duplo clique no gerenciador de arquivos).
// Uso: node tools/install-desktop.mjs            instala
//      node tools/install-desktop.mjs --uninstall remove
import { writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const share = process.env.XDG_DATA_HOME ?? join(homedir(), '.local', 'share');
const desktopFile = join(share, 'applications', '3di.desktop');
const mimeFile = join(share, 'mime', 'packages', '3di.xml');
const quiet = (cmd, args) => { try { execFileSync(cmd, args, { stdio: 'ignore' }); return true; } catch { return false; } };

if (process.argv.includes('--uninstall')) {
  rmSync(desktopFile, { force: true });
  rmSync(mimeFile, { force: true });
  quiet('update-mime-database', [join(share, 'mime')]);
  quiet('update-desktop-database', [join(share, 'applications')]);
  console.log('3DI removido do menu de aplicativos.');
  process.exit(0);
}

// Exec do .desktop: caminhos entre aspas (os do projeto não têm aspas nem $)
const q = (s) => `"${s}"`;
mkdirSync(dirname(desktopFile), { recursive: true });
writeFileSync(desktopFile, `[Desktop Entry]
Type=Application
Name=3DI
GenericName=Editor de cenas 3D
Comment=Crie cenas 3D com código (linguagem 3DI)
Exec=${q(process.execPath)} ${q(join(ROOT, 'tools', 'app.mjs'))} %f
Icon=${join(ROOT, 'assets', 'icon.svg')}
Terminal=false
Categories=Graphics;3DGraphics;
MimeType=text/x-3di;
StartupWMClass=3DI
Keywords=3d;sdf;modelagem;cena;
`);

mkdirSync(dirname(mimeFile), { recursive: true });
writeFileSync(mimeFile, `<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="text/x-3di">
    <comment>Cena 3DI</comment>
    <sub-class-of type="text/plain"/>
    <glob pattern="*.3di"/>
  </mime-type>
</mime-info>
`);

const mime = quiet('update-mime-database', [join(share, 'mime')]);
quiet('update-desktop-database', [join(share, 'applications')]);
const assoc = quiet('xdg-mime', ['default', '3di.desktop', 'text/x-3di']);
console.log(`ok: ${desktopFile}`);
console.log(`    arquivos .3di ${mime && assoc ? 'abrem no 3DI' : 'não foram associados (falta update-mime-database ou xdg-mime)'}`);
console.log('    procure "3DI" no menu de aplicativos. Para remover: node tools/install-desktop.mjs --uninstall');
