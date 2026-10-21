import { parentPort, workerData } from 'node:worker_threads';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { executeSceneTask } from '../scene-task.js';
import { nodePartRunner } from '../parallel-node.js';

// O export devolve uma Promise: é preciso esperar antes de enviar (uma Promise não atravessa postMessage).
// As peças do export são malhadas em paralelo por workers do parts-worker-node.cjs, empacotado ao lado deste
// arquivo; se não estiver lá, o export roda num núcleo só.
const workerUrl = pathToFileURL(join(__dirname, 'parts-worker-node.cjs'));
(async () => {
  try {
    const result = await executeSceneTask(workerData, { partRunner: (o: { code: string; time: number; res: number }) => nodePartRunner({ ...o, workerUrl }) });
    parentPort!.postMessage({ result });
  } catch (cause) {
    const e = cause as Error & { line?: number; hint?: string };
    parentPort!.postMessage({ error: { message: e.message, line: e.line, hint: e.hint } });
  }
})();
