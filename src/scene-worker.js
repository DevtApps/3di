import { runScript } from './interp.js';
import { compileScene } from './compiler.js';
import { exportGLB } from './export.js';
import { withTime } from './expr.js';

// geoms (opcional): geometrias das peças já malhadas em paralelo pela página; aqui só monta o GLB
self.onmessage = async ({ data: { code, task, time = 0, res = 128, geoms = null } }) => {
  try {
    const result = withTime(time, () => {
      const run = runScript(code);
      if (!run.ok) throw run.error;
      if (task === 'export') {
        const runParts = geoms ? async (n) => { if (geoms.length !== n) throw new Error(`recebi ${geoms.length} peças, a cena tem ${n}`); return geoms; } : null;
        return exportGLB(run.scene, { res, runParts });
      }
      const out = compileScene(run.scene);
      // Only plain metadata crosses the worker boundary; shapes and symbolic expressions stay here.
      const { camera, fog, sun, sky } = run.scene;
      return { out, logs: run.logs, scene: { camera, fog, sun, sky } };
    });
    self.postMessage({ result: await result });
  } catch (e) {
    self.postMessage({ error: { message: e.message, line: e.line, hint: e.hint } });
  }
};
