import { parentPort, workerData } from 'node:worker_threads';
import { executeSceneTask } from '../src/scene-task.js';

try { parentPort!.postMessage({ result: executeSceneTask(workerData) }); }
catch (cause) {
  const e = cause as Error & { line?: number; hint?: string };
  parentPort!.postMessage({ error: { message: e.message, line: e.line, hint: e.hint } });
}
