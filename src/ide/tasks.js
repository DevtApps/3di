import { ScriptError } from '../parser.js';

// One worker per job permits cancellation without leaving expensive work queued.
export function sceneTask(task, code, options = {}) {
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
    worker.postMessage({ task, code, ...options });
  });
  return { promise, cancel: () => cancel() };
}
