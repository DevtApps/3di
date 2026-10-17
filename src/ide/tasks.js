import { ScriptError } from '../parser.js';
import { webPartRunner } from '../parallel-web.js';

// One worker per job permits cancellation without leaving expensive work queued.
// O export GLB tem duas etapas: a página cria workers que malham as peças em paralelo, e o worker da cena
// só monta o arquivo com essas geometrias. Se a etapa paralela falhar, o worker da cena faz tudo sozinho.
export function sceneTask(task, code, options = {}) {
  if (task === 'export') return exportTask(code, options);
  return singleTask(task, code, options);
}

function exportTask(code, options) {
  const runner = webPartRunner({ code, time: options.time ?? 0, res: options.res ?? 128 });
  let current = null, cancelled = false;
  const promise = (async () => {
    let geoms = null;
    if (runner) {
      try { geoms = await runner(null); } catch (e) {
        if (cancelled || e?.name === 'AbortError') throw e;
        console.warn(`malha em paralelo falhou (${e.message}); exportando num núcleo`);
      }
    }
    if (cancelled) throw new DOMException('processamento substituído', 'AbortError');
    current = singleTask('export', code, { ...options, geoms });
    return current.promise;
  })();
  return { promise, cancel: () => { cancelled = true; runner?.cancel(); current?.cancel(); } };
}

function singleTask(task, code, options = {}) {
  const worker = new Worker(new URL('../scene-worker.js', import.meta.url), { type: 'module' });
  let cancel;
  const promise = new Promise((resolve, reject) => {
    const finish = (error, result) => {
      clearTimeout(timer);
      worker.terminate();
      error ? reject(error) : resolve(result);
    };
    const timer = setTimeout(() => finish(new Error('processamento excedeu 120 segundos')), 120000);
    cancel = () => finish(new DOMException('processamento substituído', 'AbortError'));
    worker.onmessage = ({ data }) => finish(data.error ? new ScriptError(data.error.message, data.error.line, data.error.hint) : null, data.result);
    worker.onerror = (event) => finish(new Error(event.message || 'falha no processamento da cena'));
    // as geometrias (typed arrays) são transferidas, sem cópia
    const transfer = [];
    for (const g of options.geoms ?? []) for (const c of g.chunks ?? []) for (const k of ['positions', 'normals', 'colors', 'uv', 'png', 'normalPng', 'indices']) if (c[k]?.buffer && !transfer.includes(c[k].buffer)) transfer.push(c[k].buffer);
    worker.postMessage({ task, code, ...options }, transfer);
  });
  return { promise, cancel: () => cancel() };
}
