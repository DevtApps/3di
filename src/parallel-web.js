// Malha as peças do export GLB em vários núcleos no navegador. Os workers são criados pela PÁGINA:
// workers aninhados (criados de dentro de outro worker) se mostraram instáveis entre navegadores e servidores.
// Mesma fila do parallel-node.js: cada worker roda o script uma vez e pede a próxima peça ao terminar.
// runner(n, onProgress): n = número de peças, ou null para usar o que o primeiro worker contar.
// runner.cancel() encerra os workers.
export function webPartRunner({ code, time = 0, res = 128, maxWorkers = null }) {
  if (typeof Worker === 'undefined') return null;
  let cancel = () => {};
  const runner = (n0, onProgress) => new Promise((resolve, reject) => {
    let n = n0;
    const cores = (typeof navigator !== 'undefined' && navigator.hardwareConcurrency) || 4;
    // sem saber o número de peças, abre um worker só; os outros abrem quando ele contar as peças
    const limit = (m) => Math.max(1, Math.min(m, maxWorkers ?? Math.max(1, cores - 1), 16));
    let results = n === null ? null : new Array(n);
    const workers = [];
    let next = 0, done = 0, failed = false;
    const stop = () => workers.forEach((w) => w.terminate());
    const fail = (e) => { if (failed) return; failed = true; stop(); reject(e instanceof Error ? e : new Error(String(e))); };
    cancel = () => fail(new DOMException('processamento substituído', 'AbortError'));
    const feed = (w) => { if (next < n) w.postMessage({ part: next++ }); };
    const spawn = () => {
      const w = new Worker(new URL('./parts-worker-web.js', import.meta.url), { type: 'module' });
      workers.push(w);
      w.onmessage = ({ data: msg }) => {
        if (msg.error && msg.part === undefined) return fail(new Error(msg.error));
        if (msg.ready) {
          if (n === null) {
            n = msg.count;
            results = new Array(n);
            if (n === 0) { stop(); return resolve([]); }
            for (let k = 1; k < limit(n); k++) spawn();
          }
          if (msg.count !== n) return fail(new Error(`o worker viu ${msg.count} peças, esperava ${n}`));
          return feed(w);
        }
        if (msg.error) return fail(new Error(msg.error));
        results[msg.part] = msg.geom;
        // (o ++ fica fora da chamada opcional: sem callback, os argumentos de ?.() nem são avaliados)
        done++;
        onProgress?.(done - 1, n);
        if (done === n) { stop(); resolve(results); } else feed(w);
      };
      w.onerror = (ev) => fail(new Error(ev.message || 'falha num worker de malha'));
      w.postMessage({ init: true, code, time, res });
    };
    const first = n === null ? 1 : limit(n);
    for (let k = 0; k < first; k++) spawn();
  });
  runner.cancel = () => cancel();
  return runner;
}
