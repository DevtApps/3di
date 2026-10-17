import { spawn } from 'node:child_process';
import { mkdtemp, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const temp = await mkdtemp(join(tmpdir(), '3di-vscode-host-'));
const result = join(temp, 'result.json');
const profile = join(temp, 'profile');
const args = [
  '--new-window', '--wait', '--skip-welcome', '--skip-release-notes', '--disable-updates',
  '--user-data-dir', profile, '--extensions-dir', join(temp, 'extensions'),
  `--extensionDevelopmentPath=${process.cwd()}`, `--extensionTestsPath=${join(process.cwd(), 'dist/host-test.cjs')}`,
  '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
];
const child = spawn('code', args, { stdio: 'inherit', env: { ...process.env, THREEDI_TEST_RESULT: result, THREEDI_TEST_SCREENSHOT: join(temp, 'preview.png') } });
const timeout = setTimeout(() => { child.kill(); console.error('Extension Host test timeout'); process.exitCode = 1; }, 120000);
const code = await new Promise((resolve, reject) => { child.once('exit', resolve); child.once('error', reject); });
clearTimeout(timeout);
try { console.log(await readFile(result, 'utf8')); console.log(`Artifacts: ${temp}`); }
catch { process.exitCode = 1; console.error(`Extension Host não produziu resultado. Consulte ${temp}`); }
if (code) process.exitCode = Number(code);
