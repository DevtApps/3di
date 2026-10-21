#!/usr/bin/env node
// Instala o 3DI do código-fonte no menu de aplicativos (Linux/freedesktop) como "3DI (dev)".
// O arquivo é 3di-dev.desktop: com o mesmo nome do app instalado (3di.desktop) o atalho do
// usuário encobria o do pacote, e abrir "3DI" no menu subia o dev (portas 8327/8328) sem o MCP
// do release. Os arquivos .3di só abrem no dev com --default.
// Uso: node scripts/install-desktop.mjs            instala
//      node scripts/install-desktop.mjs --default   instala e associa os .3di ao dev
//      node scripts/install-desktop.mjs --uninstall remove
import { writeFileSync, readFileSync, mkdirSync, rmSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const share = process.env.XDG_DATA_HOME ?? join(homedir(), '.local', 'share');
const desktopFile = join(share, 'applications', '3di-dev.desktop');
// versões antigas instalavam como 3di.desktop, encobrindo o app instalado
const legacyFile = join(share, 'applications', '3di.desktop');
const mimeFile = join(share, 'mime', 'packages', '3di.xml');
const quiet = (cmd, args) => { try { execFileSync(cmd, args, { stdio: 'ignore' }); return true; } catch { return false; } };

function removeLegacy() {
  try { if (readFileSync(legacyFile, 'utf8').includes('app.mjs')) rmSync(legacyFile); } catch {}
}

if (process.argv.includes('--uninstall')) {
  rmSync(desktopFile, { force: true });
  removeLegacy();
  rmSync(mimeFile, { force: true });
  quiet('update-mime-database', [join(share, 'mime')]);
  quiet('update-desktop-database', [join(share, 'applications')]);
  console.log('3DI removido do menu de aplicativos.');
  process.exit(0);
}

// Exec do .desktop: caminhos entre aspas (os do projeto não têm aspas nem $)
const q = (s) => `"${s}"`;
removeLegacy();
mkdirSync(dirname(desktopFile), { recursive: true });
writeFileSync(desktopFile, `[Desktop Entry]
Type=Application
Name=3DI (dev)
GenericName=Editor de cenas 3D
Comment=3DI rodando do código-fonte (portas 8327/8328)
Exec=${q(process.execPath)} ${q(join(ROOT, 'scripts', 'app.mjs'))} %f
Icon=${join(ROOT, 'assets', 'icon.svg')}
Terminal=false
Categories=Graphics;3DGraphics;
MimeType=text/x-3di;
StartupWMClass=3DI-dev
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
const assoc = process.argv.includes('--default') && quiet('xdg-mime', ['default', '3di-dev.desktop', 'text/x-3di']);
console.log(`ok: ${desktopFile}`);
console.log(`    arquivos .3di ${assoc ? 'abrem no 3DI (dev)' : mime ? 'continuam no app padrão (--default associa ao dev)' : 'não foram associados (falta update-mime-database ou xdg-mime)'}`);
console.log('    procure "3DI (dev)" no menu de aplicativos. Para remover: node scripts/install-desktop.mjs --uninstall');
