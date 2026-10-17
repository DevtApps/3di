// Web Worker que malha peças de uma cena para o export GLB em paralelo (editor no navegador e no app).
// Primeira mensagem { init, code, time, res }: roda o script; depois { part: i } devolve a geometria.
import { runScript } from './interp.js';
import { partSession, geometryTransfer } from './export.js';
import { withTime } from './expr.js';

let session = null, time = 0;
self.onmessage = async ({ data }) => {
  if (data.init) {
    try {
      time = data.time ?? 0;
      session = withTime(time, () => {
        const run = runScript(data.code);
        if (!run.ok) throw run.error;
        return partSession(run.scene, data.res ?? 128);
      });
      self.postMessage({ ready: true, count: session.count });
    } catch (e) {
      self.postMessage({ error: e.message });
    }
    return;
  }
  try {
    const geom = await withTime(time, () => session.build(data.part));
    self.postMessage({ part: data.part, geom }, geometryTransfer(geom));
  } catch (e) {
    self.postMessage({ part: data.part, error: e.message });
  }
};
