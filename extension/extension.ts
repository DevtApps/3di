import * as vscode from 'vscode';
import { randomBytes } from 'node:crypto';
import { basename, dirname, join, resolve, relative, isAbsolute } from 'node:path';
import { mkdir, readFile, realpath, writeFile } from 'node:fs/promises';
import { Engine } from './engine';
import { createProject, INITIAL_SCENE } from './project';
import { startMcp, type SceneHost } from './mcp';
import { languageCatalog } from '../src/langinfo.js';
import { integrationConfig } from '../src/integration-config.js';

const escape = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);

export async function activate(context: vscode.ExtensionContext) {
  const output = vscode.window.createOutputChannel('3DI');
  const diagnostics = vscode.languages.createDiagnosticCollection('3di');
  const engine = new Engine(context.asAbsolutePath('dist/engine-worker.cjs'));
  const status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 20);
  status.command = '3di.integrations'; status.text = '$(cube) 3DI'; status.show();
  context.subscriptions.push(output, diagnostics, engine, status);
  let document: vscode.TextDocument | undefined;
  let panel: vscode.WebviewPanel | undefined;
  let ready = false;
  let generation = 0;
  let debounce: NodeJS.Timeout | undefined;
  let cancellation: AbortController | undefined;
  let lastResult: any;
  let lastCompiledVersion = -1;
  let lastCompiledUri = '';
  let renderError: string | undefined;
  let maximized = false;
  let mcp: Awaited<ReturnType<typeof startMcp>> | undefined;
  let mcpStarting: Promise<void> | undefined;
  const pending = new Map<number, { resolve: (r: any) => void; reject: (e: Error) => void; timer: NodeJS.Timeout }>();
  let nextRequest = 0;
  const command = (id: string, fn: (...args: any[]) => unknown) => context.subscriptions.push(vscode.commands.registerCommand(id, async (...args) => {
    try { return await fn(...args); }
    catch (e) { const message = (e as Error).message; output.appendLine(message); void vscode.window.showErrorMessage(`3DI: ${message}`); throw e; }
  }));
  const activeDocument = () => {
    const active = vscode.window.activeTextEditor?.document;
    if (active?.languageId === '3di') document = active;
    if (!document || document.isClosed) document = vscode.workspace.textDocuments.find((d) => d.languageId === '3di' && !d.isClosed);
    if (!document) throw new Error('Abra uma cena .3di ou use 3DI: Novo projeto.');
    return document;
  };
  const publish = (result: any) => {
    if (!panel || !ready) return;
    const data = result.out.data;
    void panel.webview.postMessage({ type: 'scene', result: { ...result, out: { ...result.out, data: data ? { ...data, inst: Array.from(data.inst), bvh: Array.from(data.bvh) } : null } } });
  };
  const compile = async () => {
    const doc = activeDocument();
    const id = ++generation;
    const version = doc.version;
    cancellation?.abort(); cancellation = new AbortController();
    try {
      const result = await engine.run({ code: doc.getText() }, cancellation.signal);
      if (id !== generation || doc.isClosed || doc.version !== version) return;
      diagnostics.delete(doc.uri);
      lastResult = result; lastCompiledVersion = version; lastCompiledUri = doc.uri.toString();
      renderError = undefined;
      if (panel) panel.title = `3DI · ${basename(doc.fileName)}`;
      publish(result);
      result.logs.forEach((line: string) => output.appendLine(line));
      return result;
    } catch (cause) {
      if (id !== generation) return;
      const error = cause as Error & { line?: number; hint?: string };
      const line = Math.min(Math.max(0, (error.line ?? 1) - 1), doc.lineCount - 1);
      const diagnostic = new vscode.Diagnostic(doc.lineAt(line).range, error.message + (error.hint ? `\nDica: ${error.hint}` : ''), vscode.DiagnosticSeverity.Error);
      diagnostic.source = '3DI'; diagnostics.set(doc.uri, [diagnostic]);
      void panel?.webview.postMessage({ type: 'error', message: diagnostic.message });
      output.appendLine(diagnostic.message);
      throw error;
    }
  };
  const preview = async (uri?: vscode.Uri) => {
    if (uri) { document = await vscode.workspace.openTextDocument(uri); await vscode.window.showTextDocument(document, { preserveFocus: true }); }
    activeDocument();
    if (!panel) {
      panel = vscode.window.createWebviewPanel('3di.preview', '3DI · Preview', { viewColumn: vscode.ViewColumn.Beside, preserveFocus: true }, {
        enableScripts: true, retainContextWhenHidden: true,
        localResourceRoots: [vscode.Uri.joinPath(context.extensionUri, 'dist')],
      });
      const nonce = randomBytes(20).toString('hex');
      const js = panel.webview.asWebviewUri(vscode.Uri.joinPath(context.extensionUri, 'dist/preview.js'));
      const css = panel.webview.asWebviewUri(vscode.Uri.joinPath(context.extensionUri, 'dist/preview.css'));
      panel.webview.html = `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${panel.webview.cspSource}; script-src 'nonce-${nonce}'; img-src data:;"><link rel="stylesheet" href="${css}"></head><body><nav aria-label="Preview 3DI"><strong>3DI</strong><button data-view="front">Frente</button><button data-view="right">Lado</button><button data-view="top">Topo</button><button data-view="perspective">Persp.</button><button id="play">Pausar</button><button id="code">Código</button><button id="focus">Só preview</button><button id="png">PNG</button><button id="glb">GLB</button><button id="integrations">MCP</button></nav><main><canvas id="view"></canvas><aside id="parts"></aside></main><footer id="status" role="status">Preparando a engine…</footer><script nonce="${nonce}" src="${js}"></script></body></html>`;
      panel.webview.onDidReceiveMessage(async (msg) => {
        if (msg.type === 'ready') { ready = true; if (lastResult) publish(lastResult); return; }
        if (msg.type === 'rendered') { renderError = undefined; return; }
        if (msg.type === 'renderError') { renderError = String(msg.message); output.appendLine(renderError); return; }
        if (msg.type === 'reply') {
          const request = pending.get(msg.id);
          if (request) { clearTimeout(request.timer); pending.delete(msg.id); msg.error ? request.reject(new Error(msg.error)) : request.resolve(msg.result); }
          return;
        }
        if (msg.type === 'command' && ['showCode', 'previewOnly', 'exportGlb', 'exportPng', 'integrations'].includes(msg.command)) {
          void vscode.commands.executeCommand(`3di.${msg.command}`).then(undefined, (e) => output.appendLine(String(e)));
        }
      }, undefined, context.subscriptions);
      panel.onDidDispose(() => {
        panel = undefined; ready = false;
        for (const p of pending.values()) { clearTimeout(p.timer); p.reject(new Error('Preview fechado')); }
        pending.clear();
      }, undefined, context.subscriptions);
    } else panel.reveal(panel.viewColumn, true);
    return compile();
  };
  const previewCall = async (cmd: string, args: any = {}) => {
    const doc = activeDocument();
    if (!panel || lastCompiledVersion !== doc.version || lastCompiledUri !== doc.uri.toString()) await preview();
    const deadline = Date.now() + 20000;
    while (!ready && Date.now() < deadline) await new Promise((r) => setTimeout(r, 30));
    if (!ready || !panel) throw new Error('O preview ainda não está disponível');
    if (renderError) throw new Error(renderError);
    return new Promise<any>((resolve, reject) => {
      const id = ++nextRequest;
      const timer = setTimeout(() => { pending.delete(id); reject(new Error('O preview não respondeu')); }, cmd === 'glbCheck' ? 180000 : 30000);
      pending.set(id, { resolve, reject, timer });
      void panel!.webview.postMessage({ type: 'request', id, command: cmd, args });
    });
  };
  const saveAs = async (ext: string, data: Uint8Array) => {
    const doc = activeDocument();
    const initial = doc.isUntitled ? vscode.Uri.joinPath(vscode.workspace.workspaceFolders?.[0]?.uri ?? context.globalStorageUri, `cena.${ext}`) : doc.uri.with({ path: doc.uri.path.replace(/\.3di$/i, '') + `.${ext}` });
    const target = await vscode.window.showSaveDialog({ defaultUri: initial, filters: { [ext.toUpperCase()]: [ext] } });
    if (target) { await vscode.workspace.fs.writeFile(target, data); void vscode.window.showInformationMessage(`3DI: ${basename(target.fsPath)} exportado.`); }
    return target;
  };
  const host: SceneHost = {
    getScript: async () => activeDocument().getText(),
    check: (code) => engine.run({ code }),
    setScript: async (code) => {
      await engine.run({ code });
      const doc = activeDocument();
      const edit = new vscode.WorkspaceEdit();
      edit.replace(doc.uri, new vscode.Range(0, 0, doc.lineCount, 0), code);
      if (!(await vscode.workspace.applyEdit(edit))) throw new Error('Não foi possível editar a cena');
      const result = await compile();
      return `ok: ${result?.out.leaves ?? 0} primitivas`;
    },
    save: async () => { const doc = activeDocument(); if (doc.isUntitled) throw new Error('Use Salvar como no VS Code para escolher o caminho.'); if (!await doc.save()) throw new Error('Salvamento cancelado'); return doc.fileName; },
    preview: previewCall,
    exportGlb: async ({ code, path = 'out/cena.glb', res = 128 }) => {
      const doc = activeDocument();
      const root = doc.isUntitled ? vscode.workspace.workspaceFolders?.[0]?.uri.fsPath : dirname(doc.fileName);
      if (!root) throw new Error('Salve a cena ou abra um workspace para exportar.');
      const target = resolve(root, path);
      const rel = relative(root, target);
      if (isAbsolute(rel) || rel === '..' || rel.startsWith('../') || rel.startsWith('..\\')) throw new Error('A exportação deve ficar na pasta da cena.');
      if (!target.toLowerCase().endsWith('.glb')) throw new Error('Use a extensão .glb.');
      await mkdir(dirname(target), { recursive: true });
      const resolvedRoot = await realpath(root), resolvedParent = await realpath(dirname(target));
      const parentRel = relative(resolvedRoot, resolvedParent);
      if (parentRel === '..' || parentRel.startsWith('../') || isAbsolute(parentRel)) throw new Error('Diretório fora da pasta da cena.');
      const { glb, stats } = await engine.run({ code: code ?? doc.getText(), task: 'export', res });
      await writeFile(target, glb, { flag: 'wx' });
      return JSON.stringify({ path: target, ...stats });
    },
  };
  const restartMcp = () => {
    if (mcpStarting) return mcpStarting;
    mcpStarting = (async () => {
      await mcp?.stop(); mcp = undefined;
      const cfg = vscode.workspace.getConfiguration('3di');
      if (!cfg.get('mcp.enabled', true)) { status.tooltip = 'MCP desativado'; return; }
      mcp = await startMcp(host, context.extensionPath, cfg.get('mcp.port', 8317), (s) => output.appendLine(s));
      status.tooltip = `MCP HTTP: ${mcp.endpoint}`;
    })().catch((e) => { status.tooltip = `Falha no MCP: ${e.message}`; output.appendLine(String(e)); }).finally(() => { mcpStarting = undefined; });
    return mcpStarting;
  };
  command('3di.openPreview', preview);
  command('3di.previewOnly', async () => {
    if (!panel) await preview();
    panel?.reveal(panel.viewColumn);
    if (!maximized) { await vscode.commands.executeCommand('workbench.action.toggleMaximizeEditorGroup'); maximized = true; }
  });
  command('3di.showCode', async () => {
    if (maximized) { await vscode.commands.executeCommand('workbench.action.toggleMaximizeEditorGroup'); maximized = false; }
    await vscode.window.showTextDocument(activeDocument(), vscode.ViewColumn.One);
    panel?.reveal(vscode.ViewColumn.Beside, true);
  });
  command('3di.exportGlb', async () => {
    const code = activeDocument().getText();
    const result = await vscode.window.withProgress({ location: vscode.ProgressLocation.Notification, title: '3DI: gerando GLB' }, () => engine.run({ code, task: 'export', res: vscode.workspace.getConfiguration('3di').get('export.resolution', 128) }));
    await saveAs('glb', result.glb);
    result.stats.warnings.forEach((w: string) => output.appendLine(w));
  });
  command('3di.exportPng', async () => { const { png } = await previewCall('screenshot', { view: 'current' }); await saveAs('png', Buffer.from(png, 'base64')); });
  command('3di.examples', async () => {
    const names = (await vscode.workspace.fs.readDirectory(vscode.Uri.joinPath(context.extensionUri, 'examples'))).filter(([n]) => n.endsWith('.3di')).map(([n]) => n);
    const name = await vscode.window.showQuickPick(names, { title: '3DI: Abrir exemplo' });
    if (!name) return;
    const content = await readFile(context.asAbsolutePath(`examples/${name}`), 'utf8');
    document = await vscode.workspace.openTextDocument({ language: '3di', content });
    await vscode.window.showTextDocument(document); await preview();
  });
  command('3di.newProject', async () => {
    const selection = await vscode.window.showOpenDialog({ canSelectFiles: false, canSelectFolders: true, canSelectMany: false, title: '3DI: Escolha a pasta de destino do projeto', openLabel: 'Usar esta pasta' });
    if (!selection) return;
    const name = await vscode.window.showInputBox({ title: '3DI: Nome do projeto', value: 'meu-projeto-3di', validateInput: (value) => /^[\p{L}\p{N}_][\p{L}\p{N}_. -]*$/u.test(value) ? null : 'Use um nome de pasta sem barras.' });
    if (!name) return;
    const root = await createProject(selection[0].fsPath, name, context.asAbsolutePath('skills/3di-scenes/SKILL.md'));
    await vscode.commands.executeCommand('vscode.openFolder', vscode.Uri.file(root), { forceReuseWindow: true });
  });
  command('3di.restartMcp', restartMcp);
  command('3di.integrations', async () => {
    await restartMcpIfNeeded();
    const view = vscode.window.createWebviewPanel('3di.integrations', '3DI · Integrações', vscode.ViewColumn.Active, { enableScripts: true });
    const nonce = randomBytes(20).toString('hex');
    const config = mcp ? integrationConfig(mcp.endpoint) : undefined;
    const block = (label: string, value: string) => `<h3>${label}</h3><pre>${escape(value)}</pre>`;
    view.webview.html = `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'nonce-${nonce}'; script-src 'nonce-${nonce}'"><style nonce="${nonce}">body{max-width:850px;margin:32px auto;padding:0 24px;color:var(--vscode-foreground);font:14px/1.6 var(--vscode-font-family)}pre{background:var(--vscode-textCodeBlock-background);padding:16px;white-space:pre-wrap;overflow-wrap:anywhere}button{background:var(--vscode-button-background);color:var(--vscode-button-foreground);border:0;padding:8px 14px;cursor:pointer;margin-right:8px}h1{font-size:26px}</style></head><body><h1>Conecte seu agente ao 3DI</h1><p>MCP HTTP local com SDK oficial, sem autenticação. A extensão gerencia o serviço enquanto o VS Code está aberto.</p>${config ? block('Endpoint', mcp!.endpoint) + block('Codex', config.codexCommand) + block('Codex · config.toml', config.codex) + block('Claude Code', config.claudeCommand) + block('Claude Code · .mcp.json', config.claude) : '<p>MCP desativado ou indisponível. Confira as configurações 3DI e o painel de saída.</p>'}<button id="copy">Copiar endpoint</button><button id="skill">Salvar SKILL.md</button><button id="docs">Documentação</button><p>Use /mcp no cliente para conferir a conexão. A skill pode ser salva em .agents/skills/3di-scenes/SKILL.md (Codex) ou .claude/skills/3di-scenes/SKILL.md (Claude Code). Projetos criados pelo comando 3DI: Novo projeto já incluem .agents e AGENTS.md.</p><h2>Documentação pelo MCP</h2>${block('Comece por', 'get_documentation(topic="inicio")\nthreedi://docs/inicio')}<p>A documentação é dividida em rotas por tema (formas, combinar, materiais, organico, hard-surface, cenarios, exportar, revisao...); a rota inicio indica qual ler para cada tarefa. O preview usa o documento .3di ativo; nenhuma configuração exige o caminho da instalação.</p><script nonce="${nonce}">const api=acquireVsCodeApi();for(const id of ['copy','skill','docs'])document.getElementById(id).onclick=()=>api.postMessage({command:id});</script></body></html>`;
    view.webview.onDidReceiveMessage(async ({ command: action }) => {
      if (action === 'copy' && mcp) { await vscode.env.clipboard.writeText(mcp.endpoint); void vscode.window.showInformationMessage('Endpoint MCP copiado.'); }
      if (action === 'docs') await vscode.commands.executeCommand('markdown.showPreviewToSide', vscode.Uri.joinPath(context.extensionUri, 'docs/rotas/inicio.md'));
      if (action === 'skill') {
        const target = await vscode.window.showSaveDialog({ saveLabel: 'Salvar skill', defaultUri: vscode.Uri.joinPath(vscode.workspace.workspaceFolders?.[0]?.uri ?? context.globalStorageUri, '.agents/skills/3di-scenes/SKILL.md') });
        if (target) { await vscode.workspace.fs.createDirectory(vscode.Uri.joinPath(target, '..')); await vscode.workspace.fs.writeFile(target, await vscode.workspace.fs.readFile(vscode.Uri.joinPath(context.extensionUri, 'skills/3di-scenes/SKILL.md'))); }
      }
    }, undefined, context.subscriptions);
  });
  async function restartMcpIfNeeded() { if (mcpStarting) await mcpStarting; else if (!mcp) await restartMcp(); }
  const catalog: any = languageCatalog();
  const entries: any[] = [...catalog.functions, ...catalog.constants, ...catalog.methods, ...catalog.properties, ...catalog.rig.bone, ...catalog.rig.skeleton];
  context.subscriptions.push(vscode.languages.registerCompletionItemProvider('3di', {
    provideCompletionItems(doc, position) {
      const before = doc.lineAt(position.line).text.slice(0, position.character);
      const methods = /\.\w*$/.test(before);
      const items = methods ? [...catalog.methods, ...catalog.properties, ...catalog.rig.bone, ...catalog.rig.skeleton] : [...catalog.functions, ...catalog.constants];
      return items.map((entry: any) => {
        const item = new vscode.CompletionItem(entry.name, entry.signature ? vscode.CompletionItemKind.Function : vscode.CompletionItemKind.Property);
        item.detail = entry.signature; item.documentation = entry.doc;
        if (entry.signature?.includes('(')) { item.insertText = new vscode.SnippetString(`${entry.name}($0)`); item.command = { command: 'editor.action.triggerParameterHints', title: 'Parâmetros' }; }
        return item;
      });
    },
  }, '.'), vscode.languages.registerHoverProvider('3di', {
    provideHover(doc, position) {
      const range = doc.getWordRangeAtPosition(position); if (!range) return;
      const info = entries.find((e) => e.name === doc.getText(range)); if (!info) return;
      return new vscode.Hover(new vscode.MarkdownString().appendCodeblock(info.signature ?? info.name, 'python').appendText(`\n${info.doc ?? ''}`), range);
    },
  }), vscode.workspace.onDidChangeTextDocument((e) => {
    if (e.document.languageId !== '3di' || e.document !== document) return;
    clearTimeout(debounce); debounce = setTimeout(() => { void compile().catch(() => {}); }, 300);
  }), vscode.window.onDidChangeActiveTextEditor((editor) => {
    if (editor?.document.languageId !== '3di') return;
    const changed = document !== editor.document; document = editor.document;
    if (changed && (panel || vscode.workspace.getConfiguration('3di').get('autoPreview', true))) void preview().catch((e) => output.appendLine(String(e)));
  }), vscode.workspace.onDidChangeConfiguration((e) => { if (e.affectsConfiguration('3di.mcp')) void restartMcp(); }),
  { dispose() { clearTimeout(debounce); cancellation?.abort(); panel?.dispose(); void mcp?.stop(); } });
  void restartMcp();
  const current = vscode.window.activeTextEditor?.document;
  if (current?.languageId === '3di') {
    document = current;
    if (vscode.workspace.getConfiguration('3di').get('autoPreview', true)) void preview().catch((e) => output.appendLine(String(e)));
  } else {
    const folder = vscode.workspace.workspaceFolders?.[0];
    if (folder) {
      try {
        const config = JSON.parse(await readFile(join(folder.uri.fsPath, '3di.json'), 'utf8'));
        if (config.scene === 'main.3di') {
          document = await vscode.workspace.openTextDocument(vscode.Uri.joinPath(folder.uri, 'main.3di'));
          await vscode.window.showTextDocument(document);
          if (vscode.workspace.getConfiguration('3di').get('autoPreview', true)) await preview();
        }
      } catch {}
    }
  }
  // A small API supports automated Extension Host verification without UI automation.
  return { engine, host, endpoint: () => mcp?.endpoint, preview, status: () => ({ ready, primitives: lastResult?.out.leaves, renderError }) };
}
