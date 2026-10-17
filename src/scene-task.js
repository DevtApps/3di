import { runScript } from './interp.js';
import { compileScene } from './compiler.js';
import { exportGLB } from './export.js';
import { withTime } from './expr.js';

/**
 * partRunner (opcional): ({ code, time, res }) => runParts, para malhar as peças do export em paralelo.
 * @param {{ code: string, task?: string, time?: number, res?: number }} request
 * @param {{ partRunner?: ((o: { code: string, time: number, res: number }) => any) | null }} [options]
 */
export function executeSceneTask({ code, task = 'compile', time = 0, res = 128 }, { partRunner = null } = {}) {
  return withTime(time, () => {
    const run = runScript(code);
    if (!run.ok) throw run.error;
    if (task === 'export') return exportGLB(run.scene, { res, runParts: partRunner?.({ code, time, res }) ?? null });
    const out = compileScene(run.scene);
    const { camera, fog, sun, sky, light } = run.scene;
    return { out, logs: run.logs, scene: { camera, fog, sun, sky, light } };
  });
}
