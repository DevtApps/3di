import { spawn } from 'node:child_process';
import electron from 'electron';
const child = spawn(electron, ['build/desktop', ...process.argv.slice(2)], { stdio: 'inherit' });
child.on('error', (e) => { console.error(e); process.exitCode = 1; });
child.on('exit', (code) => { process.exitCode = code ?? 1; });
