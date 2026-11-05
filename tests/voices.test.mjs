// Falas: templates de áudio, ElevenLabs (com um servidor falso que imita a API) e a chave guardada à parte.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { mkdtemp, rm, stat, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const data = await mkdtemp(join(tmpdir(), '3di-voices-'));
process.env.XDG_DATA_HOME = data;
delete process.env.ELEVENLABS_API_KEY;
const requests = [];
const fake = http.createServer(async (req, res) => {
  let body = '';
  for await (const c of req) body += c;
  requests.push({ url: req.url, key: req.headers['xi-api-key'], body: body ? JSON.parse(body) : null });
  if (req.headers['xi-api-key'] !== 'chave-de-teste-123') { res.writeHead(401, { 'Content-Type': 'application/json' }).end(JSON.stringify({ detail: { message: 'invalid api key' } })); return; }
  if (req.url === '/v1/voices') { res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify({ voices: [{ voice_id: 'v-rachel', name: 'Rachel', labels: { gender: 'female' } }, { voice_id: 'v-adam', name: 'Adam', labels: {} }] })); return; }
  if (req.url.startsWith('/v1/text-to-speech/')) { res.writeHead(200, { 'Content-Type': 'audio/pcm' }).end(Buffer.alloc(48000)); return; } // 1 s de PCM 24 kHz
  res.writeHead(404).end();
});
await new Promise((r) => fake.listen(0, '127.0.0.1', r));
process.env.THREEDI_ELEVENLABS_URL = `http://127.0.0.1:${fake.address().port}`;
const { saveSettings, ttsConfig, setElevenKey, elevenKey, elevenKeyInfo, loadSettings } = await import('../src/services/settings.mjs');
const { speech, wavSeconds } = await import('../src/services/video.mjs');

test.after(async () => { fake.close(); await rm(data, { recursive: true, force: true }); });

test('a chave do ElevenLabs fica em secrets.json (600) e não aparece nas configurações', async () => {
  assert.throws(() => setElevenKey('curta'), /inválida/);
  setElevenKey('chave-de-teste-123');
  assert.equal(elevenKey(), 'chave-de-teste-123');
  assert.deepEqual(elevenKeyInfo(), { set: true, hint: '…-123', fromEnv: false });
  assert.equal((await stat(join(data, '3di', 'secrets.json'))).mode & 0o777, 0o600);
  saveSettings({ tts: { provider: 'elevenlabs' } });
  assert.ok(!(await readFile(join(data, '3di', 'settings.json'), 'utf8')).includes('chave-de-teste'));
});

test('templates de áudio vêm prontos, são editáveis e validados', () => {
  const ids = loadSettings().templates.map((t) => t.id);
  for (const id of ['narrador', 'animado', 'calmo', 'sussurro']) assert.ok(ids.includes(id), id);
  const s = saveSettings({ templates: [...loadSettings().templates, { id: 'vilao', label: 'Vilão', prompt: 'voz de vilão', tags: '[laughs]', stability: 2, speed: 9 }, { id: 'com espaço', prompt: 'x' }] });
  const v = s.templates.find((t) => t.id === 'vilao');
  assert.deepEqual([v.stability, v.speed], [1, 1.2], 'valores presos à faixa da API');
  assert.ok(!s.templates.some((t) => t.id === 'com espaço'));
});

test('falas pelo ElevenLabs: voz por nome, template aplicado, WAV no cache e reagendamento', async () => {
  saveSettings({ tts: { provider: 'elevenlabs' }, elevenlabs: { model: 'eleven_v3', voice: 'v-adam', voiceName: 'Adam' } });
  const script = [
    { text: 'Primeira fala.', start: 0, end: 0.5, speak: true, voice: 'n', style: 'animado', auto: true },
    { text: 'Segunda fala.', start: 0.5, end: 1, speak: true, voice: null, style: null, auto: true },
  ];
  const voices = { n: { provider: 'elevenlabs', speaker: 'Rachel', language: 'Portuguese' } };
  requests.length = 0;
  const clips = await speech(script, voices, { root: process.cwd(), tts: ttsConfig(), elevenKey: elevenKey() });
  assert.equal(clips.length, 2);
  assert.ok(Math.abs(wavSeconds(clips[0].file) - 1) < 1e-6, 'PCM virou WAV de 1 s');
  const tts = requests.filter((r) => r.url.startsWith('/v1/text-to-speech/'));
  assert.ok(tts[0].url.startsWith('/v1/text-to-speech/v-rachel?output_format=pcm_24000'), 'voz achada pelo nome');
  assert.ok(tts[0].body.text.startsWith('[excited] '), 'marcação do template no v3');
  assert.equal(tts[0].body.voice_settings.stability, 0.35);
  assert.equal(tts[0].body.language_code, 'pt');
  assert.ok(tts[1].url.startsWith('/v1/text-to-speech/v-adam'), 'sem voice(): a voz padrão das configurações');
  assert.ok(script[1].start >= script[0].start + 1, 'a segunda fala entra depois do áudio real da primeira');
  // de novo: tudo do cache, nenhuma chamada nova
  requests.length = 0;
  await speech(script.map((l) => ({ ...l })), voices, { root: process.cwd(), tts: ttsConfig(), elevenKey: elevenKey() });
  assert.equal(requests.filter((r) => r.url.startsWith('/v1/text-to-speech/')).length, 0);
});

test('erros claros: chave errada e voz que não existe', async () => {
  const one = [{ text: 'x', start: 0, end: 1, speak: true, voice: 'n', auto: true }];
  await assert.rejects(speech(one, { n: { provider: 'elevenlabs', speaker: 'Ninguém' } }, { root: process.cwd(), tts: ttsConfig(), elevenKey: elevenKey() }), /não existe na sua conta/);
  await assert.rejects(speech([{ ...one[0], text: 'y' }], { n: { provider: 'elevenlabs' } }, { root: process.cwd(), tts: ttsConfig(), elevenKey: 'chave-errada-000' }), /recusou \(invalid api key\)/);
});
