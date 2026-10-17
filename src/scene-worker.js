import { runScript } from './interp.js';
import { compileScene } from './compiler.js';
import { exportGLB } from './export.js';
import { withTime } from './expr.js';

self.onmessage = async ({ data: { code, task, time = 0, res = 128 } }) => {
  try {
    const result = withTime(time, () => {
      const run = runScript(code);
      if (!run.ok) throw run.error;
      if (task === 'export') return exportGLB(run.scene, { res });
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
