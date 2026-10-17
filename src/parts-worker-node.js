// Worker (Node) que malha peças de uma cena para o export GLB em paralelo.
// Recebe o código do script, roda uma vez e responde a pedidos { part: i } com a geometria.
import { parentPort, workerData } from 'node:worker_threads';
import { runScript } from './interp.js';
import { partSession, geometryTransfer } from './export.js';
import { withTime } from './expr.js';

const { code, time = 0, res = 128 } = workerData;
let session = null;
try {
  session = withTime(time, () => {
    const run = runScript(code);
    if (!run.ok) throw run.error;
    return partSession(run.scene, res);
  });
  parentPort.postMessage({ ready: true, count: session.count });
} catch (e) {
  parentPort.postMessage({ error: e.message });
}

parentPort.on('message', async ({ part }) => {
  try {
    const geom = await withTime(time, () => session.build(part));
    parentPort.postMessage({ part, geom }, geometryTransfer(geom));
  } catch (e) {
    parentPort.postMessage({ part, error: e.message });
  }
});
