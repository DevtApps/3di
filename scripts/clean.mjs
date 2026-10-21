// Build outputs only: user scenes and exported models are preserved.
import { rm } from 'node:fs/promises';
await rm(new URL('../build/', import.meta.url), { recursive: true, force: true });
console.log('build/ removido.');
