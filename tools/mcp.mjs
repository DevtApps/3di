#!/usr/bin/env node
// Servidor MCP do 3DI.
//  - stdio: protocolo MCP (JSON-RPC 2.0, uma mensagem por linha) para agentes de IA.
//  - HTTP (porta 8327 ou --port/THREEDI_PORT; o app instalado usa 8317): serve a IDE e a ponte com o editor aberto
//    no navegador ou no app desktop (veja ideserver.mjs). Se a porta já tiver outro servidor
//    3DI (outra instância ou o app), os comandos são repassados para ele.
// Uso: node tools/mcp.mjs [--port 8327]
import { writeFile, mkdir, readFile } from 'node:fs/promises';
import { resolve, dirname, relative, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';
import { runScript } from '../src/interp.js';
import { compileScene } from '../src/compiler.js';
import { exportGLB } from '../src/export.js';
import { nodePartRunner } from '../src/parallel-node.js';
const PARTS_WORKER = new URL('../src/parts-worker-node.js', import.meta.url);
import { languageSummary } from '../src/langinfo.js';
import { collectBones } from '../src/rig.js';
import { ScriptError } from '../src/parser.js';
import { startIdeServer } from './ideserver.mjs';
import { documentationResources, readDocumentation, DOC_TOPICS } from './documentation.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const argPort = process.argv.indexOf('--port');
const PORT = Number(argPort >= 0 ? process.argv[argPort + 1] : process.env.THREEDI_PORT ?? 8327);
const URL_IDE = `http://localhost:${PORT}`;
const log = (...a) => process.stderr.write(`[3di-mcp] ${a.join(' ')}\n`);

// ---------- servidor da IDE e ponte com o editor ----------

let ide = null;
const ready = startIdeServer({ root: ROOT, port: PORT, log })
  .then((s) => { ide = s; })
  .catch((e) => log(e.message));

async function callEditor(cmd, args) {
  await ready;
  if (!ide) throw new Error(`servidor da IDE não subiu na porta ${PORT}`);
  return ide.call(cmd, args);
}

// ---------- ferramentas ----------

const v = (a) => `(${a.map((x) => +x.toFixed(3)).join(', ')})`;

function checkCode(code) {
  const res = runScript(code);
  const lines = res.logs.map((l) => `print: ${l}`);
  if (!res.ok) return { ok: false, text: [...lines, `ERRO ${res.error.toString()}`].join('\n') };
  try {
    const out = compileScene(res.scene);
    lines.push(`ok: ${out.leaves} primitivas${out.instances ? ` (${out.instances} na BVH)` : ''}${out.animated ? ', animada' : ''}`);
    lines.push(`cena: de ${v(out.bbox.min)} até ${v(out.bbox.max)}`);
    for (const p of out.parts) lines.push(`  ${p.name}: tamanho ${v(p.bbox.max.map((x, i) => x - p.bbox.min[i]))}, de ${v(p.bbox.min)} até ${v(p.bbox.max)}`);
    const bones = collectBones(res.scene.shapes);
    if (bones.length) lines.push(`esqueleto: ${bones.map((b) => `${b.name}${b.parent ? `<${b.parent.name}` : ''}`).join(', ')}`);
    return { ok: true, text: lines.join('\n') };
  } catch (e) {
    return { ok: false, text: [...lines, `ERRO ${e instanceof ScriptError ? e.toString() : e.message}`].join('\n') };
  }
}

const VIEWS = ['current', 'front', 'back', 'left', 'right', 'top', 'perspective', 'grid'];
const vec3 = { type: 'array', items: { type: 'number' }, minItems: 3, maxItems: 3 };

function text(t, isError = false) {
  return { content: [{ type: 'text', text: t }], ...(isError ? { isError: true } : {}) };
}

const TOOLS = [
  {
    name: 'get_documentation',
    description: 'Documentação do 3DI em rotas por tema (funciona sem editor). Comece por "inicio", que diz qual rota ler para cada tarefa. Rotas: ' + DOC_TOPICS.join(', ') + '.',
    inputSchema: { type: 'object', properties: { topic: { type: 'string', enum: DOC_TOPICS, default: 'inicio' } } },
    run: async ({ topic = 'inicio' }) => text((await readDocumentation(topic)).text),
  },
  {
    name: 'describe_language',
    description: 'Referência resumida da linguagem 3DI (primitivas, métodos, layout, rig, animação, cores, texturas). Leia antes de escrever cenas.',
    inputSchema: { type: 'object', properties: {} },
    run: async () => text(languageSummary()),
  },
  {
    name: 'check_script',
    description: 'Executa e compila um script 3DI sem abrir o editor. Devolve erros (linha + dica) ou as medidas das peças nomeadas e o esqueleto.',
    inputSchema: { type: 'object', properties: { code: { type: 'string', description: 'código 3DI' } }, required: ['code'] },
    run: async ({ code }) => { const r = checkCode(code); return text(r.text, !r.ok); },
  },
  {
    name: 'get_script',
    description: 'Lê o código que está no editor aberto.',
    inputSchema: { type: 'object', properties: {} },
    run: async () => text(await callEditor('getScript')),
  },
  {
    name: 'set_script',
    description: 'Substitui o código do editor, compila e mostra na vista 3D. Devolve o status (ou o erro com linha e dica).',
    inputSchema: { type: 'object', properties: { code: { type: 'string' } }, required: ['code'] },
    run: async ({ code }) => { const st = await callEditor('setScript', { code }); return text(st, st.startsWith('✗')); },
  },
  {
    name: 'save_script',
    description: 'Salva o código do editor no arquivo que está aberto nele (o mesmo que Ctrl+S). Se o arquivo ainda não tem lugar no disco, o usuário precisa escolher no editor.',
    inputSchema: { type: 'object', properties: {} },
    run: async () => text(await callEditor('save')),
  },
  {
    name: 'screenshot',
    description: 'Imagem da vista 3D do editor. view: current (como está), front, back, left, right, top, perspective, ou grid (4 vistas: frente, lado, topo e perspectiva). target: nome de uma peça (.name) para enquadrar só ela. time: instante da animação em segundos.',
    inputSchema: {
      type: 'object',
      properties: {
        view: { type: 'string', enum: VIEWS, default: 'current' },
        target: { type: 'string', description: 'peça nomeada para enquadrar (opcional)' },
        time: { type: 'number', description: 'instante da animação (opcional)' },
      },
    },
    run: async (args) => {
      const r = await callEditor('screenshot', args);
      return { content: [{ type: 'image', data: r.png, mimeType: 'image/png' }, { type: 'text', text: r.info }] };
    },
  },
  {
    name: 'check_glb',
    description: 'Confere a conversão para GLB: o editor exporta a cena, abre o resultado num motor padrão (three.js) no ângulo atual e devolve uma imagem da malha exportada mais um relatório por peça (triângulos, desvio da malha em relação à forma exata em mm, veredito). Use depois de mudar formas, resolução ou texturas. res = detalhe (padrão 128); style: solid, wire (mostra os triângulos) ou normals (sombreamento); mode: glb (só a malha), shader (só a forma exata) ou split (lado a lado).',
    inputSchema: {
      type: 'object',
      properties: {
        res: { type: 'number', default: 128 },
        style: { type: 'string', enum: ['solid', 'wire', 'normals'], default: 'solid' },
        mode: { type: 'string', enum: ['glb', 'shader', 'split'], default: 'glb' },
      },
    },
    run: async (args) => {
      const r = await callEditor('glbCheck', args);
      return { content: [{ type: 'image', data: r.png, mimeType: 'image/png' }, { type: 'text', text: r.report }] };
    },
  },
  {
    name: 'set_reference',
    description: 'Coloca uma imagem de referência (PNG/JPEG) por cima da vista 3D do editor, para modelar copiando um desenho ou foto. path: arquivo no disco (absoluto ou relativo ao projeto). opacity 0..1, scale (1 = encaixada na vista), x/y = deslocamento em % do tamanho da imagem, side = mostrar ao lado em vez de por cima. Sem path, só ajusta a atual. Depois use compare_reference.',
    inputSchema: { type: 'object', properties: { path: { type: 'string' }, opacity: { type: 'number' }, scale: { type: 'number' }, x: { type: 'number' }, y: { type: 'number' }, side: { type: 'boolean' } } },
    run: async ({ path, ...opts }) => {
      let data, mime;
      if (path) {
        const file = isAbsolute(path) ? path : resolve(ROOT, path);
        data = (await readFile(file)).toString('base64');
        mime = /\.jpe?g$/i.test(file) ? 'image/jpeg' : /\.webp$/i.test(file) ? 'image/webp' : 'image/png';
      }
      return text(await callEditor('setReference', { ...opts, data, mime }));
    },
  },
  {
    name: 'compare_reference',
    description: 'Imagem para comparar a cena com a referência: referência | cena (vista atual) | sobreposição a 50%. Ajuste câmera (set_camera) e escala/deslocamento (set_reference) até a silhueta bater, depois corrija proporções e cores.',
    inputSchema: { type: 'object', properties: {} },
    run: async () => {
      const r = await callEditor('compareReference');
      return { content: [{ type: 'image', data: r.png, mimeType: 'image/png' }, { type: 'text', text: r.info }] };
    },
  },
  {
    name: 'set_camera',
    description: 'Posiciona a câmera do editor: pos (x, y, z) olhando para look (padrão: centro da cena), com fov em graus.',
    inputSchema: { type: 'object', properties: { pos: vec3, look: vec3, fov: { type: 'number' } }, required: ['pos'] },
    run: async (args) => text(await callEditor('setCamera', args)),
  },
  {
    name: 'frame',
    description: 'Enquadra a cena inteira ou uma peça nomeada, opcionalmente num ângulo pronto (front, back, left, right, top, perspective).',
    inputSchema: { type: 'object', properties: { target: { type: 'string' }, view: { type: 'string', enum: VIEWS.filter((x) => x !== 'grid' && x !== 'current') } } },
    run: async (args) => text(await callEditor('frame', args)),
  },
  {
    name: 'list_parts',
    description: 'Peças nomeadas da cena aberta no editor, com tamanho e posição (caixa envolvente), mais a câmera atual.',
    inputSchema: { type: 'object', properties: {} },
    run: async () => text(await callEditor('parts')),
  },
  {
    name: 'set_time',
    description: 'Controla a animação: time congela num instante (segundos); playing true/false toca ou pausa.',
    inputSchema: { type: 'object', properties: { time: { type: 'number' }, playing: { type: 'boolean' } } },
    run: async (args) => text(await callEditor('setTime', args)),
  },
  {
    name: 'export_glb',
    description: 'Exporta para .glb (glTF binário com malhas, texturas procedurais assadas em PNG embutido, esqueleto e animação). Usa o code dado ou o do editor. path relativo ao projeto (padrão out/cena.glb); res = detalhe (células na maior dimensão).',
    inputSchema: { type: 'object', properties: { code: { type: 'string' }, path: { type: 'string' }, res: { type: 'number', default: 128 } } },
    run: async ({ code, path = 'out/cena.glb', res = 128 }) => {
      const src = code ?? await callEditor('getScript');
      const run = runScript(src);
      if (!run.ok) return text(`ERRO ${run.error.toString()}`, true);
      const out = resolve(ROOT, path);
      const rel = relative(ROOT, out);
      if (isAbsolute(rel) || rel.startsWith('..')) return text('path deve ficar dentro do projeto', true);
      const { glb, stats } = await exportGLB(run.scene, { res, runParts: nodePartRunner({ code: src, res, workerUrl: PARTS_WORKER }) });
      await mkdir(dirname(out), { recursive: true });
      await writeFile(out, glb);
      return text(`ok: ${rel} (${(stats.bytes / 1024).toFixed(0)} KB) · ${stats.parts} partes · ${stats.triangles} triângulos` +
        `${stats.bones ? ` · ${stats.bones} ossos` : ''}${stats.animated ? ' · animado' : ''}${stats.warnings.map((w) => `\naviso: ${w}`).join('')}\n` +
        `confira em ${URL_IDE}/tools/viewer.html?file=/${rel}`);
    },
  },
];

// ---------- protocolo MCP sobre stdio ----------

const SUPPORTED = ['2025-06-18', '2025-03-26', '2024-11-05'];
const send = (msg) => process.stdout.write(JSON.stringify(msg) + '\n');

async function handle(msg) {
  if (!msg || typeof msg !== 'object' || Array.isArray(msg)) { send({ jsonrpc: '2.0', id: null, error: { code: -32600, message: 'requisição inválida' } }); return; }
  const { id, method, params } = msg;
  const reply = (result) => id !== undefined && send({ jsonrpc: '2.0', id, result });
  const fail = (code, message) => id !== undefined && send({ jsonrpc: '2.0', id, error: { code, message } });
  switch (method) {
    case 'initialize':
      return reply({
        protocolVersion: SUPPORTED.includes(params?.protocolVersion) ? params.protocolVersion : SUPPORTED[0],
        capabilities: { tools: {}, resources: {} },
        serverInfo: { name: '3di', version: '0.3.0' },
        instructions: '3DI: linguagem (subconjunto de Python) de cenas 3D feitas só com funções genéricas (formas, combinações, merge, deformações, paint, facets); objetos específicos são funções def do próprio script. Leia get_documentation(topic="inicio") primeiro: ela indica a rota de cada tarefa (fundamentos, formas, combinar, materiais, organico, hard-surface, cenarios, exportar, referencia-visual, revisao...). describe_language lista todas as assinaturas. Fluxo: get_script antes de editar, check_script para validar, set_script para aplicar, screenshot(view="grid") para ver, check_glb antes de entregar um GLB. ' +
          `O preview exige a IDE aberta (app 3DI ou ${URL_IDE}).`,
      });
    case 'ping': return reply({});
    case 'resources/list': return reply({ resources: documentationResources });
    case 'resources/read': {
      try { return reply({ contents: [await readDocumentation(params?.uri)] }); }
      catch (e) { return fail(-32602, e.message); }
    }
    case 'tools/list': return reply({ tools: TOOLS.map(({ run, ...t }) => t) });
    case 'tools/call': {
      const tool = TOOLS.find((t) => t.name === params?.name);
      if (!tool) return fail(-32602, `ferramenta desconhecida: ${params?.name}`);
      try {
        return reply(await tool.run(params.arguments ?? {}));
      } catch (e) {
        return reply(text(e.message, true));
      }
    }
    default:
      if (method?.startsWith('notifications/')) return;
      return fail(-32601, `método não suportado: ${method}`);
  }
}

let buf = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  buf += chunk;
  let i;
  while ((i = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, i).trim();
    buf = buf.slice(i + 1);
    if (!line) continue;
    let msg;
    try { msg = JSON.parse(line); } catch { send({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'JSON inválido' } }); continue; }
    handle(msg).catch((e) => log(e.stack));
  }
});
// quando o cliente MCP fecha a conexão, encerra (o app desktop tem o próprio servidor)
process.stdin.on('end', () => { ready.finally(() => process.exit(0)); });
