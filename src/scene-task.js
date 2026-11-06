import { runScript } from './interp.js';
import { compileScene } from './compiler.js';
import { exportGLB } from './export.js';
import { withTime, val0 } from './expr.js';
import { sceneDuration, cameraTrack } from './timeline.js';

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
    return { out, logs: run.logs, scene: sceneMeta(run.scene) };
  });
}

// Dados da cena que atravessam o worker (só valores simples: formas e expressões ficam lá).
// A câmera animada vira trilha amostrada e a câmera em si leva os valores em t = 0.
export function sceneMeta(scene) {
  const { fog, sun, sky, light, script, voices } = scene;
  const overlays = (scene.overlays ?? []).map((o) => ({ ...o }));
  const duration = sceneDuration(scene);
  const camTrack = cameraTrack(scene.camera, duration);
  const camera = scene.camera && { pos: scene.camera.pos.map(val0), look: scene.camera.look?.map(val0) ?? null, fov: val0(scene.camera.fov) };
  return { camera, camTrack, fog, sun, sky, light, script, voices, overlays, duration, keyTimes: [...(scene.keyTimes ?? [])].sort((p, q) => p - q), fps: scene.anim?.fps ?? 30 };
}
