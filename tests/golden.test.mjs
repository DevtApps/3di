// os golden files do port em C++ (tests/golden/) devem acompanhar o JS: regrave com `npm run golden`
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';

test('golden files atualizados', () => {
  const r = spawnSync(process.execPath, [new URL('../scripts/golden.mjs', import.meta.url).pathname, '--check'], { encoding: 'utf8' });
  assert.equal(r.status, 0, `${r.stderr}\nrode: npm run golden`);
});
