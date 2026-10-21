import { Worker } from 'node:worker_threads';

export interface EngineRequest { code: string; task?: 'compile' | 'export'; time?: number; res?: number }
export class Engine {
  private workers = new Set<Worker>();
  constructor(private workerFile: string) {}
  run(request: EngineRequest, signal?: AbortSignal): Promise<any> {
    return new Promise((resolve, reject) => {
      if (signal?.aborted) { reject(new Error('Compilação substituída')); return; }
      const worker = new Worker(this.workerFile, { workerData: request });
      this.workers.add(worker);
      let done = false;
      const finish = (error?: Error, result?: unknown) => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        signal?.removeEventListener('abort', abort);
        this.workers.delete(worker);
        void worker.terminate();
        error ? reject(error) : resolve(result);
      };
      const abort = () => finish(new Error('Compilação substituída'));
      const timer = setTimeout(() => finish(new Error('A engine excedeu 120 segundos')), 120000);
      signal?.addEventListener('abort', abort, { once: true });
      worker.once('message', ({ result, error }) => finish(error ? Object.assign(new Error(error.message), error) : undefined, result));
      worker.once('error', (error) => finish(error instanceof Error ? error : new Error(String(error))));
      worker.once('exit', (code) => { if (!done) finish(new Error(`Engine encerrada (${code})`)); });
    });
  }
  dispose() { for (const worker of this.workers) void worker.terminate(); this.workers.clear(); }
}
