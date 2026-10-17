import { app, BrowserWindow, dialog, ipcMain, Menu, shell } from 'electron';
import { join, dirname, basename, resolve, relative, isAbsolute } from 'node:path';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { startRuntime } from './runtime.js';
import { createProject } from '../extension/project.js';

let win: BrowserWindow;
let runtime: Awaited<ReturnType<typeof startRuntime>>;
let currentPath: string | null = null;
let dirty = false;
const root = resolve(__dirname, '..');
const smoke = process.argv.includes('--smoke');
app.setName('3DI');
if (smoke) app.setPath('userData', mkdtempSync(join(tmpdir(), '3di-desktop-smoke-')));
const initial = process.argv.find((arg) => arg.endsWith('.3di'));
const firstFile = async () => currentPath ? { path: currentPath, name: basename(currentPath), text: await readFile(currentPath, 'utf8') } : null;
async function confirmDiscard() {
  if (!dirty) return true;
  return (await dialog.showMessageBox(win, { type: 'question', message: 'Descartar alterações não salvas?', buttons: ['Cancelar', 'Descartar'], defaultId: 0, cancelId: 0 })).response === 1;
}
async function openFile(file?: string) {
  if (!await confirmDiscard()) return null;
  if (!file) { const picked = await dialog.showOpenDialog(win, { properties: ['openFile'], filters: [{ name: 'Cena 3DI', extensions: ['3di'] }] }); if (picked.canceled) return null; file = picked.filePaths[0]; }
  const text = await readFile(file, 'utf8');
  const activeRoot = runtime.workspace.info().workspace;
  const rel = activeRoot ? relative(activeRoot, file) : '..';
  if (!activeRoot || rel === '..' || rel.startsWith('../') || isAbsolute(rel)) await runtime.workspace.set(dirname(file), true);
  currentPath = file; dirty = false;
  return { path: file, name: basename(file), text };
}
async function newProject() {
  if (!await confirmDiscard()) return null;
  const picked = await dialog.showSaveDialog(win, { title: 'Nome e pasta do novo projeto', defaultPath: join(app.getPath('documents'), 'Meu projeto 3DI'), buttonLabel: 'Criar projeto' });
  if (picked.canceled || !picked.filePath) return null;
  const target = picked.filePath;
  const project = await createProject(dirname(target), basename(target), join(root, 'skills/3di-scenes/SKILL.md'));
  await runtime.workspace.set(project, true);
  currentPath = join(project, 'main.3di'); dirty = false;
  return firstFile();
}
if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on('second-instance', async (_event, argv) => { win?.show(); win?.focus(); const file = argv.find((a) => a.endsWith('.3di')); if (file) { const opened = await openFile(resolve(file)); if (opened) win.webContents.send('3di:opened', opened); } });
  app.whenReady().then(async () => {
    runtime = await startRuntime(root, join(__dirname, 'engine-worker.cjs'), { port: smoke ? 0 : Number(process.env.THREEDI_PORT ?? 8317), mcpPort: smoke ? 0 : Number(process.env.THREEDI_MCP_PORT ?? 8318), workspace: initial ? dirname(resolve(initial)) : undefined, trash: (path) => shell.trashItem(path), onScenePath: (path) => { currentPath = path; } });
    if (initial) currentPath = resolve(initial);
    win = new BrowserWindow({ width: 1440, height: 940, minWidth: 900, minHeight: 600, title: '3DI', icon: join(root, 'assets/icon.png'), show: !smoke,
      webPreferences: { preload: join(__dirname, 'preload.cjs'), contextIsolation: true, nodeIntegration: false, sandbox: true, backgroundThrottling: !smoke },
    });
    if (smoke) win.webContents.on('console-message', (_event, _level, message) => console.log('renderer:', message));
    const trusted = (url: string) => { try { return new URL(url).origin === runtime.ide.url; } catch { return false; } };
    win.webContents.on('will-navigate', (event, url) => { if (!trusted(url)) event.preventDefault(); });
    win.webContents.setWindowOpenHandler(({ url }) => { if (/^https?:/.test(url)) void shell.openExternal(url); return { action: 'deny' }; });
    const handle = (name: string, callback: (value: any) => any) => ipcMain.handle(name, (event, value) => { if (event.sender !== win.webContents || !trusted(event.senderFrame?.url ?? '')) throw new Error('Origem inválida'); return callback(value); });
    handle('3di:workspace', async () => {
      const result = await dialog.showOpenDialog(win, { title: 'Escolher workspace 3DI', properties: ['openDirectory'] });
      if (result.canceled) return null;
      return runtime.workspace.set(result.filePaths[0]);
    });
    handle('3di:reset', () => { currentPath = null; });
    handle('3di:open', () => openFile());
    handle('3di:initialFile', firstFile);
    handle('3di:newProject', newProject);
    handle('3di:save', async ({ text, name, saveAs }) => {
      if (typeof text !== 'string' || text.length > 2000000) throw new Error('Cena inválida');
      let target = currentPath;
      if (!target || saveAs) { const result = await dialog.showSaveDialog(win, { defaultPath: target ?? basename(String(name)), filters: [{ name: 'Cena 3DI', extensions: ['3di'] }] }); if (result.canceled || !result.filePath) return null; target = result.filePath; }
      await writeFile(target, text); currentPath = target; dirty = false;
      if (!runtime.workspace.info().workspace) await runtime.workspace.set(dirname(target), true);
      return { path: target, name: basename(target) };
    });
    handle('3di:export', async ({ bytes, name, ext }) => {
      if (!['.png', '.glb'].includes(ext) || !(bytes instanceof Uint8Array)) throw new Error('Exportação inválida');
      const result = await dialog.showSaveDialog(win, { defaultPath: join(currentPath ? dirname(currentPath) : app.getPath('documents'), basename(String(name))), filters: [{ name: ext.slice(1).toUpperCase(), extensions: [ext.slice(1)] }] });
      if (result.canceled || !result.filePath) return null;
      await writeFile(result.filePath, bytes); return basename(result.filePath);
    });
    ipcMain.on('3di:dirty', (event, value) => { if (event.sender === win.webContents) { dirty = Boolean(value); win.setDocumentEdited(dirty); } });
    let closing = false;
    win.on('close', (event) => { if (!closing && dirty) { event.preventDefault(); void confirmDiscard().then((yes) => { if (yes) { closing = true; win.close(); } }); } });
    Menu.setApplicationMenu(Menu.buildFromTemplate([
      { label: 'Arquivo', submenu: [
        { label: 'Escolher workspace…', click: () => void dialog.showOpenDialog(win, { title: 'Workspace 3DI', properties: ['openDirectory'] }).then(async (result) => { if (!result.canceled) await runtime.workspace.set(result.filePaths[0]); }).catch((e) => dialog.showErrorBox('Workspace', String(e))) },
        { label: 'Novo projeto…', click: () => void newProject().then((file) => { if (file) win.webContents.send('3di:opened', file); }).catch((e) => dialog.showErrorBox('Novo projeto', String(e))) },
        { label: 'Abrir cena…', accelerator: 'CmdOrCtrl+O', click: () => void openFile().then((file) => { if (file) win.webContents.send('3di:opened', file); }).catch((e) => dialog.showErrorBox('Abrir cena', String(e))) },
        { type: 'separator' }, { role: 'quit' },
      ] },
      { label: 'Editar', submenu: [{ role: 'undo' }, { role: 'redo' }, { type: 'separator' }, { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { role: 'selectAll' }] },
      { label: 'Exibir', submenu: [{ role: 'togglefullscreen' }, { role: 'toggleDevTools' }, { label: 'Integrações MCP', click: () => void win.webContents.executeJavaScript('document.getElementById("btnIntegrations").click()') }] },
    ]));
    await win.loadURL(runtime.ide.url);
    if (smoke) {
      try {
        const { Client } = await import('@modelcontextprotocol/sdk/client/index.js');
        const { StreamableHTTPClientTransport } = await import('@modelcontextprotocol/sdk/client/streamableHttp.js');
        for (let i = 0; i < 100 && runtime.ide.clientCount() === 0; i++) await new Promise((r) => setTimeout(r, 100));
        const client = new Client({ name: 'desktop-smoke', version: '1' });
        await client.connect(new StreamableHTTPClientTransport(new URL(runtime.mcp.endpoint)));
        for (let i = 0; i < 100; i++) {
          if (await win.webContents.executeJavaScript('Boolean(window.tdi && window.tdi.status().startsWith("✓"))')) break;
          await new Promise((r) => setTimeout(r, 100));
        }
        const tools = await client.listTools();
        const invoke = async (name: string, args: any) => { const result = await client.callTool({ name, arguments: args }); if (result.isError) throw new Error(JSON.stringify(result)); return result; };
        const testWorkspace = join(app.getPath('userData'), 'workspace'); await mkdir(testWorkspace);
        await invoke('set_workspace', { path: testWorkspace });
        await invoke('create_scene', { path: 'scenes/test.3di', code: 'show(box().name("caixa"))' });
        await invoke('open_scene', { path: 'scenes/test.3di' });
        await invoke('move_scene', { source: 'scenes/test.3di', destination: 'scenes/renamed.3di' });
        await invoke('set_script', { code: 'show(sphere().name("esfera"))' });
        const rejected = await client.callTool({ name: 'delete_scene', arguments: { path: 'scenes/renamed.3di' } });
        if (!rejected.isError) throw new Error('Não protegeu alterações não salvas');
        await invoke('save_script', {});
        if (!(await readFile(join(testWorkspace, 'scenes/renamed.3di'), 'utf8')).includes('sphere')) throw new Error('Salvar não acompanhou o caminho movido');
        await invoke('delete_scene', { path: 'scenes/renamed.3di' });
        console.log('3DI_WORKSPACE_OK', JSON.stringify({ create: true, open: true, move: true, save: true, trash: true, dirtyProtection: true }));
        const result = await client.callTool({ name: 'set_script', arguments: { code: 'show(sphere().color("red").name("esfera"))' } });
        if (result.isError) throw new Error(JSON.stringify(result));
        const screenshot = await client.callTool({ name: 'screenshot', arguments: { view: 'grid' } });
        if (!screenshot.content || !(screenshot.content as any[]).some((c) => c.type === 'image' && c.data.length > 2000)) throw new Error('Preview sem imagem');
        if (process.argv.includes('--performance-smoke')) {
          await invoke('set_script', { code: 'show([sphere(0.1).at((i%20)*0.26,0,(i//20)*0.26) for i in range(400)], box(1).twist(40).displace(0.02,0.2).move(y=0.8))' });
          const navigation = await win.webContents.executeJavaScript(`(async () => {
            const canvas = document.getElementById('view');
            const before = window.tdi.performance();
            const capture = canvas.setPointerCapture; canvas.setPointerCapture = () => {}; 
            canvas.dispatchEvent(new PointerEvent('pointerdown', { pointerId: 9, clientX: 150, clientY: 150 }));
            let events = 0;
            for (let i=0;i<60;i++) {
              canvas.dispatchEvent(new PointerEvent('pointermove', { pointerId: 9, clientX: 150+i*2, clientY: 150+Math.sin(i/10)*20 })); events++;
              await new Promise(r=>setTimeout(r,16));
            }
            const during = window.tdi.performance();
            canvas.dispatchEvent(new PointerEvent('pointercancel', { pointerId: 9 }));
            for(let i=0;i<100;i++) { await new Promise(r=>setTimeout(r,50)); if (!window.tdi.performance().interactive) break; }
            canvas.setPointerCapture = capture;
            return { before, during, after: window.tdi.performance(), events, status: window.tdi.status() };
          })()`);
          if (navigation.during.glError || navigation.after.glError || !navigation.during.interactive || navigation.after.interactive) throw new Error(JSON.stringify(navigation));
          console.log('3DI_NAVIGATION_OK', JSON.stringify(navigation));
        }
        console.log('3DI_DESKTOP_OK', JSON.stringify({ tools: tools.tools.length, screenshot: true, endpoint: runtime.mcp.endpoint, native: await win.webContents.executeJavaScript('typeof window.desktop3di.open') }));
        await client.close(); dirty = false; app.quit();
      } catch (e) { console.error(e); dirty = false; app.exit(1); }
    }
  }).catch((e) => { console.error(e); dialog.showErrorBox('3DI', String(e)); app.exit(1); });
  app.on('window-all-closed', () => app.quit());
  app.on('will-quit', () => { void runtime?.stop(); });
}
