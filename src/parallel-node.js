// Malha as peças do export GLB em vários núcleos (Node: CLI, MCP, app desktop).
// Cada worker roda o script uma vez; a fila entrega a próxima peça a quem terminar primeiro.
import { Worker } from 'node:worker_threads';
import { availableParallelism, cpus } from 'node:os';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const cores = () => (typeof availableParallelism === 'function' ? availableParallelism() : cpus().length);

/**
 * Devolve runParts(n, onProgress) para exportGLB, ou null se o arquivo do worker não existir.
 * workerUrl: URL do worker de peças (src/parts-worker-node.js, ou o parts-worker-node.cjs empacotado);
 * é passada por quem chama porque `import.meta.url` não existe nos pacotes CJS.
 * code/time: o script e o instante usados no export.
 */
export function nodePartRunner({ code, time = 0, res = 128, workerUrl, maxWorkers = null }) {
  if (!workerUrl || !existsSync(fileURLToPath(workerUrl))) return null;
  return (n, onProgress) => new Promise((resolve, reject) => {
    const count = Math.max(1, Math.min(n, maxWorkers ?? Math.max(1, cores() - 1), 16));
    const results = new Array(n);
    const workers = [];
    let next = 0, done = 0, failed = false;
    const stop = () => workers.forEach((w) => void w.terminate());
    const fail = (e) => { if (failed) return; failed = true; stop(); reject(e instanceof Error ? e : new Error(String(e))); };
    const feed = (w) => {
      if (next < n) w.postMessage({ part: next++ });
    };
    for (let k = 0; k < count; k++) {
      const w = new Worker(workerUrl, { workerData: { code, time, res } });
      workers.push(w);
      w.on('message', (msg) => {
        if (msg.error && msg.part === undefined) return fail(new Error(msg.error));
        if (msg.ready) { if (msg.count !== n) return fail(new Error(`o worker viu ${msg.count} peças, esperava ${n}`)); return feed(w); }
        if (msg.error) return fail(new Error(msg.error));
        results[msg.part] = msg.geom;
        // mesmo formato do export sequencial: índice (base 0) da peça que acabou
        // (o ++ fica fora da chamada opcional: sem callback, os argumentos de ?.() nem são avaliados)
        done++;
        onProgress?.(done - 1, n);
        if (done === n) { stop(); resolve(results); } else feed(w);
      });
      w.on('error', fail);
      w.on('exit', (c) => { if (!failed && done < n && c !== 0) fail(new Error(`worker encerrado (${c})`)); });
    }
  });
}
