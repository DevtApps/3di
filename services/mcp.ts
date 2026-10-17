import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { createServer as httpServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { z } from 'zod';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { languageSummary } from '../src/langinfo.js';
import { SKILLS, readSkills, installSkills } from './skills.js';
import type { SceneWorkspace } from './workspace.js';

export interface SceneHost {
  workspace?: SceneWorkspace;
  getScript(): Promise<string>;
  setScript(code: string): Promise<string>;
  save(): Promise<string>;
  check(code: string): Promise<any>;
  preview(command: string, args: unknown): Promise<any>;
  exportGlb(args: { code?: string; path?: string; res?: number }): Promise<string>;
}

export const DOCS = [
  { topic: 'language', name: 'Linguagem 3DI', file: 'docs/language.md' },
  { topic: 'best-practices', name: 'Boas práticas', file: 'docs/best-practices.md' },
  { topic: 'examples', name: 'Exemplos', file: 'docs/examples.md' },
  { topic: 'skill', name: 'Skill 3DI', file: 'skills/3di-scenes/SKILL.md' },
  { topic: 'geometry-review', name: 'Skill de revisão geométrica', file: 'skills/3di-geometry-review/SKILL.md' },
] as const;

export async function startMcp(host: SceneHost, extensionRoot: string, preferredPort: number, log: (message: string) => void) {
  // Bind the configured port directly. Falling back to an ephemeral port made
  // agent configurations stale whenever another process briefly held 8318.
  const endpointForPort = (port: number) => `http://127.0.0.1:${port}/mcp`;
  let boundPort = preferredPort;
  let endpoint = endpointForPort(preferredPort);
  const createMcp = () => {
  const mcp = new McpServer({ name: '3di', version: '0.4.0' }, {
    instructions: 'Antes de modelar, consulte list_skills e leia get_skill: 3di-scenes e 3di-geometry-review, ou os recursos threedi://skills/<nome>. As skills podem ser usadas diretamente pelo MCP. Para instalá-las, chame install_skills com o workspace absoluto real do agente e target=both; não use a pasta de instalação do app. Consulte language e best-practices, leia get_script antes de editar, valide medidas e logs com check_script, aplique set_script e examine screenshot grid e encontros críticos antes de finalizar.',
  });
  // Keep registration shared between desktop, browser development and VS Code.
  const server = {
    addResource(entry: any) {
      mcp.registerResource(entry.name, entry.uri, { mimeType: entry.mimeType }, async () => ({ contents: [{ uri: entry.uri, mimeType: entry.mimeType, ...(await entry.load()) }] }));
    },
    addTool(entry: { name: string; description: string; parameters?: any; annotations?: any; timeoutMs?: number; execute: (args: any) => any }) {
      mcp.registerTool(entry.name, { description: entry.description, inputSchema: entry.parameters ?? z.object({}), annotations: entry.annotations }, async (args: any) => {
        try {
          const result = await entry.execute(args);
          return typeof result === 'object' && result?.content ? result : { content: [{ type: 'text' as const, text: typeof result === 'string' ? result : JSON.stringify(result) }] };
        } catch (error) {
          return { isError: true, content: [{ type: 'text' as const, text: error instanceof Error ? error.message : String(error) }] };
        }
      });
    },
  };
  const doc = async (topic: string) => {
    const entry = DOCS.find((d) => d.topic === topic);
    if (!entry) throw new Error('Documento desconhecido');
    return readFile(join(extensionRoot, entry.file), 'utf8');
  };
  if (host.workspace) {
    const files = host.workspace;
    const path = z.string().min(1).max(4096);
    server.addTool({ name: 'get_workspace', description: 'Mostra o workspace ativo. Todos os caminhos de cenas são relativos a ele.', annotations: { readOnlyHint: true }, execute: async () => JSON.stringify(files.info()) });
    server.addTool({ name: 'set_workspace', description: 'Seleciona a pasta absoluta do projeto informado pelo usuário. Não muda a configuração HTTP. Recusa troca com alterações não salvas.', parameters: z.object({ path }), execute: async ({ path }) => JSON.stringify(await files.set(path)) });
    server.addTool({ name: 'list_files', description: 'Lista recursivamente cenas .3di do workspace, ignorando links, pastas ocultas e dependências.', parameters: z.object({ path: path.optional() }), annotations: { readOnlyHint: true }, execute: async ({ path }) => JSON.stringify(await files.list(path)) });
    server.addTool({ name: 'read_scene', description: 'Lê um arquivo .3di sem trocar a cena aberta.', parameters: z.object({ path }), annotations: { readOnlyHint: true }, execute: async ({ path }) => JSON.stringify(await files.read(path)) });
    server.addTool({ name: 'create_scene', description: 'Valida e cria uma cena .3di no workspace sem sobrescrever arquivos. Não troca a cena aberta.', parameters: z.object({ path, code: z.string().max(2000000) }), execute: async ({ path, code }) => JSON.stringify(await files.create(path, code)) });
    server.addTool({ name: 'open_scene', description: 'Abre uma cena .3di do workspace no editor/preview. Recusa se houver alterações não salvas.', parameters: z.object({ path }), execute: async ({ path }) => JSON.stringify(await files.open(path)) });
    server.addTool({ name: 'move_scene', description: 'Move ou renomeia uma cena dentro do workspace sem sobrescrever o destino. Atualiza o caminho do editor se estiver aberta; recusa se ela tiver alterações não salvas.', parameters: z.object({ source: path, destination: path }), execute: async ({ source, destination }) => JSON.stringify(await files.move(source, destination)) });
    server.addTool({ name: 'delete_scene', description: 'Envia uma cena .3di para a lixeira do sistema. Nunca apaga permanentemente. Recusa cena aberta com alterações não salvas; preserva o texto aberto como rascunho.', parameters: z.object({ path }), annotations: { destructiveHint: true }, execute: async ({ path }) => JSON.stringify(await files.delete(path)) });
  }
  for (const entry of DOCS) {
    server.addResource({ uri: `threedi://docs/${entry.topic}`, name: entry.name, mimeType: 'text/markdown', load: async () => ({ text: await doc(entry.topic) }) });
  }
  for (const skill of SKILLS) {
    server.addResource({ uri: `threedi://skills/${skill.name}`, name: skill.name, mimeType: 'text/markdown', load: async () => ({ text: (await readSkills(extensionRoot)).find((s) => s.name === skill.name)!.files[0].content }) });
  }
  server.addTool({ name: 'list_skills', description: 'Descobre skills de construção e revisão do 3DI, disponíveis para leitura pelo MCP ou instalação local.', annotations: { readOnlyHint: true }, execute: async () => JSON.stringify(SKILLS.map((s) => ({ ...s, uri: `threedi://skills/${s.name}` }))) });
  server.addTool({ name: 'get_skill', description: 'Lê uma skill com seus arquivos. Aplique as instruções na sessão ou instale via install_skills.', parameters: z.object({ name: z.enum(['3di-scenes', '3di-geometry-review']) }), annotations: { readOnlyHint: true }, execute: async ({ name }) => JSON.stringify((await readSkills(extensionRoot)).find((s) => s.name === name)) });
  server.addTool({ name: 'install_skills', description: 'Instala as duas skills no workspace absoluto informado pelo agente. target agents usa .agents/skills; claude usa .claude/skills; both prepara ambos. Não sobrescreve arquivos existentes diferentes. Use quando o usuário solicitar a instalação/configuração ou autorizar instalar automaticamente neste workspace.', parameters: z.object({ workspace: z.string().min(1), target: z.enum(['agents', 'claude', 'both']).default('both') }), annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false }, execute: async ({ workspace, target }) => JSON.stringify(await installSkills(extensionRoot, workspace, target)) });
  server.addTool({ name: 'get_documentation', description: 'Documentação, exemplos, boas práticas e skills da engine.', parameters: z.object({ topic: z.enum(['language', 'best-practices', 'examples', 'skill', 'geometry-review']) }), annotations: { readOnlyHint: true }, execute: async ({ topic }) => doc(topic) });
  server.addTool({ name: 'describe_language', description: 'Referência resumida da linguagem 3DI.', annotations: { readOnlyHint: true }, execute: async () => languageSummary() });
  server.addTool({ name: 'check_script', description: 'Valida uma cena sem alterar o documento.', parameters: z.object({ code: z.string().max(2000000) }), annotations: { readOnlyHint: true }, execute: async ({ code }) => {
    const result = await host.check(code);
    return JSON.stringify({ primitives: result.out.leaves, bbox: result.out.bbox, parts: result.out.parts, logs: result.logs });
  } });
  server.addTool({ name: 'get_script', description: 'Lê o documento .3di ativo.', annotations: { readOnlyHint: true }, execute: async () => host.getScript() });
  server.addTool({ name: 'set_script', description: 'Valida e substitui a cena ativa, preservando o histórico de desfazer.', parameters: z.object({ code: z.string().max(2000000) }), execute: async ({ code }) => host.setScript(code) });
  server.addTool({ name: 'save_script', description: 'Salva o documento ativo no caminho atual.', execute: async () => host.save() });
  const views = z.enum(['current', 'front', 'back', 'left', 'right', 'top', 'perspective', 'grid']);
  server.addTool({ name: 'screenshot', description: 'PNG do preview ou grade com frente, lado, topo e perspectiva.', parameters: z.object({ view: views.default('current'), target: z.string().optional(), time: z.number().finite().optional() }), annotations: { readOnlyHint: true }, execute: async (args) => {
    const r = await host.preview('screenshot', args);
    return { content: [{ type: 'image' as const, data: r.png, mimeType: 'image/png' }] };
  } });
  const vec3 = z.tuple([z.number().finite(), z.number().finite(), z.number().finite()]);
  server.addTool({ name: 'set_camera', description: 'Posiciona a câmera do preview.', parameters: z.object({ pos: vec3, look: vec3.optional(), fov: z.number().min(5).max(150).optional() }), execute: async (args) => JSON.stringify(await host.preview('setCamera', args)) });
  server.addTool({ name: 'frame', description: 'Enquadra a cena ou uma peça nomeada.', parameters: z.object({ target: z.string().optional(), view: views.exclude(['current', 'grid']).optional() }), execute: async (args) => JSON.stringify(await host.preview('frame', args)) });
  server.addTool({ name: 'list_parts', description: 'Lista peças e medidas da cena ativa.', annotations: { readOnlyHint: true }, execute: async () => {
    const result = await host.check(await host.getScript()); return JSON.stringify(result.out.parts);
  } });
  server.addTool({ name: 'set_time', description: 'Pausa ou reproduz a animação em um instante.', parameters: z.object({ time: z.number().finite().optional(), playing: z.boolean().optional() }), execute: async (args) => JSON.stringify(await host.preview('setTime', args)) });
  server.addTool({ name: 'export_glb', description: 'Exporta GLB na pasta da cena/workspace, nunca na instalação. Não sobrescreve arquivos existentes.', parameters: z.object({ code: z.string().max(2000000).optional(), path: z.string().optional(), res: z.number().int().min(1).max(2048).default(128) }), timeoutMs: 180000, execute: (args) => host.exportGlb(args) });
  return mcp;
  };
  const active = new Set<McpServer>();
  const http = httpServer(async (req: IncomingMessage, res: ServerResponse) => {
    const requestHost = req.headers.host;
    if (![ `127.0.0.1:${boundPort}`, `localhost:${boundPort}` ].includes(requestHost ?? '') ||
      (req.headers.origin && req.headers.origin !== `http://${requestHost}`)) {
      res.writeHead(403).end('Acesso somente local'); return;
    }
    try {
      const path = new URL(req.url ?? '/', endpoint).pathname;
      if (path === '/health') { res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify({ name: '3di', endpoint })); return; }
      if (path.startsWith('/docs/')) {
        const entry = DOCS.find((d) => path === `/docs/${d.topic}`);
        if (!entry) { res.writeHead(404).end(); return; }
        res.setHeader('Content-Type', 'text/markdown; charset=utf-8');
        res.end(await readFile(join(extensionRoot, entry.file), 'utf8')); return;
      }
      if (path !== '/mcp') { res.writeHead(404).end(); return; }
      if (req.method !== 'POST') { res.writeHead(405, { Allow: 'POST' }).end(); return; }
      const chunks: Buffer[] = []; let size = 0;
      for await (const chunk of req) {
        size += chunk.length;
        if (size > 4 * 1024 * 1024) { res.writeHead(413).end(); return; }
        chunks.push(chunk);
      }
      let body: unknown;
      try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
      catch { res.writeHead(400).end('JSON inválido'); return; }
      const mcp = createMcp(); active.add(mcp);
      const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true });
      res.on('close', () => { active.delete(mcp); void mcp.close(); });
      await mcp.connect(transport);
      await transport.handleRequest(req, res, body);
    } catch (error) {
      log(String(error));
      if (!res.headersSent) res.writeHead(500).end('Erro MCP'); else res.end();
    }
  });
  await new Promise<void>((resolve, reject) => {
    http.once('error', reject);
    http.listen(preferredPort, '127.0.0.1', () => {
      boundPort = (http.address() as { port: number }).port;
      endpoint = endpointForPort(boundPort);
      resolve();
    });
  });
  log(`MCP HTTP em ${endpoint}`);
  return { endpoint, stop: async () => {
    await Promise.all([...active].map((mcp) => mcp.close()));
    http.closeAllConnections();
    await new Promise<void>((resolve) => http.close(() => resolve()));
  } };
}
