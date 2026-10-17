import { runScript } from './interp.js';
import { compileScene } from './compiler.js';
import { exportGLB } from './export.js';
import { withTime } from './expr.js';

export function executeSceneTask({ code, task = 'compile', time = 0, res = 128 }) {
  return withTime(time, () => {
    const run = runScript(code);
    if (!run.ok) throw run.error;
    if (task === 'export') return exportGLB(run.scene, { res });
    const out = compileScene(run.scene);
    const { camera, fog, sun, sky } = run.scene;
    return { out, logs: run.logs, scene: { camera, fog, sun, sky } };
  });
}
