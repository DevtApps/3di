// Falas: templates de áudio, ElevenLabs e Fish Audio (com um servidor falso que imita as APIs) e as chaves guardadas à parte.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { mkdtemp, rm, stat, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const data = await mkdtemp(join(tmpdir(), '3di-voices-'));
process.env.XDG_DATA_HOME = data;
delete process.env.ELEVENLABS_API_KEY;
delete process.env.FISH_API_KEY;
const requests = [];
const fake = http.createServer(async (req, res) => {
  let body = '';
  for await (const c of req) body += c;
  requests.push({ url: req.url, key: req.headers['xi-api-key'] ?? req.headers.authorization, model: req.headers.model, body: body ? JSON.parse(body) : null });
  // Fish Audio: Bearer, /model e /v1/tts
  if (req.headers.authorization) {
    if (req.headers.authorization !== 'Bearer fish-chave-123') { res.writeHead(401, { 'Content-Type': 'application/json' }).end(JSON.stringify({ status: 401, message: 'Invalid token' })); return; }
    if (req.url.startsWith('/model?')) { res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify({ total: 2, items: [{ _id: 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4', title: 'Narradora BR', languages: ['pt'], state: 'trained', author: { nickname: 'eu' } }, { _id: 'ffffffffffffffffffffffffffffffff', title: 'Treinando', state: 'training' }] })); return; }
    if (req.url.startsWith('/wallet/self/api-credit')) { res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify({ credit: '1.50', has_free_credit: true })); return; }
    if (req.url === '/v1/tts') { res.writeHead(200, { 'Content-Type': 'audio/pcm' }).end(Buffer.alloc(24000)); return; } // 0,5 s
    res.writeHead(404).end(); return;
  }
  if (req.headers['xi-api-key'] !== 'chave-de-teste-123') { res.writeHead(401, { 'Content-Type': 'application/json' }).end(JSON.stringify({ detail: { message: 'invalid api key' } })); return; }
  if (req.url === '/v1/voices') { res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify({ voices: [{ voice_id: 'v-rachel', name: 'Rachel', labels: { gender: 'female' } }, { voice_id: 'v-adam', name: 'Adam', labels: {} }] })); return; }
  if (req.url.startsWith('/v1/text-to-speech/')) { res.writeHead(200, { 'Content-Type': 'audio/pcm' }).end(Buffer.alloc(48000)); return; } // 1 s de PCM 24 kHz
  res.writeHead(404).end();
});
await new Promise((r) => fake.listen(0, '127.0.0.1', r));
process.env.THREEDI_ELEVENLABS_URL = `http://127.0.0.1:${fake.address().port}`;
process.env.THREEDI_FISH_URL = process.env.THREEDI_ELEVENLABS_URL;
const { saveSettings, ttsConfig, setApiKey, apiKey, apiKeys, apiKeyInfo, loadSettings } = await import('../src/services/settings.mjs');
const { speech, wavSeconds } = await import('../src/services/video.mjs');
const { runScript } = await import('../src/interp.js');
const runScriptOk = (code) => runScript(code).ok;

test.after(async () => { fake.close(); await rm(data, { recursive: true, force: true }); });

test('a chave do ElevenLabs fica em secrets.json (600) e não aparece nas configurações', async () => {
  assert.throws(() => setApiKey('elevenlabs', 'curta'), /inválida/);
  assert.throws(() => setApiKey('outro', 'chave-de-teste-123'), /sem chave/);
  setApiKey('elevenlabs', 'chave-de-teste-123');
  setApiKey('fishaudio', 'fish-chave-123');
  assert.equal(apiKey('elevenlabs'), 'chave-de-teste-123');
  assert.deepEqual(apiKeyInfo(), { elevenlabs: { set: true, hint: '…-123', fromEnv: false }, fishaudio: { set: true, hint: '…-123', fromEnv: false } });
  assert.equal((await stat(join(data, '3di', 'secrets.json'))).mode & 0o777, 0o600);
  saveSettings({ tts: { provider: 'elevenlabs' } });
  assert.ok(!/chave-de-teste|fish-chave/.test(await readFile(join(data, '3di', 'settings.json'), 'utf8')));
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
  const clips = await speech(script, voices, { root: process.cwd(), tts: ttsConfig(), keys: apiKeys() });
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
  await speech(script.map((l) => ({ ...l })), voices, { root: process.cwd(), tts: ttsConfig(), keys: apiKeys() });
  assert.equal(requests.filter((r) => r.url.startsWith('/v1/text-to-speech/')).length, 0);
});

test('erros claros: chave errada e voz que não existe', async () => {
  const one = [{ text: 'x', start: 0, end: 1, speak: true, voice: 'n', auto: true }];
  await assert.rejects(speech(one, { n: { provider: 'elevenlabs', speaker: 'Ninguém' } }, { root: process.cwd(), tts: ttsConfig(), keys: apiKeys() }), /não existe na sua conta/);
  await assert.rejects(speech([{ ...one[0], text: 'y' }], { n: { provider: 'elevenlabs' } }, { root: process.cwd(), tts: ttsConfig(), keys: { elevenlabs: 'chave-errada-000' } }), /recusou \(invalid api key\)/);
});

test('narração contínua: falas seguidas da mesma voz numa chamada, legendas pelas pausas', async () => {
  const { splitByPauses } = await import('../src/services/video.mjs');
  // 3 frases de tamanhos parecidos em 9 s, pausas perto de 3 e 6 s (e uma falsa em 1 s)
  const parts = splitByPauses(['Primeira frase aqui.', 'Segunda frase aqui.', 'Terceira frase aqui.'], 9, [{ start: 0.9, end: 1.1 }, { start: 2.8, end: 3.2 }, { start: 6.3, end: 6.5 }]);
  assert.deepEqual(parts.map((p) => [+p.start.toFixed(2), +p.end.toFixed(2)]), [[0, 3], [3, 6.4], [6.4, 9]]);
  // sem pausas: corta proporcional ao texto
  assert.deepEqual(splitByPauses(['aa', 'aaaaaa'], 8, []).map((p) => p.start), [0, 2]);
  saveSettings({ tts: { provider: 'elevenlabs' }, elevenlabs: { model: 'eleven_multilingual_v2', voice: 'v-adam', voiceName: 'Adam' } });
  const script = ['Um.', 'Dois.', 'Três.'].map((text, i) => ({ text: `${text} ${Date.now()}`, start: i, end: i + 0.5, speak: true, voice: null, style: null, auto: true }));
  requests.length = 0;
  const clips = await speech(script, {}, { root: process.cwd(), tts: ttsConfig(), keys: apiKeys() });
  const calls = requests.filter((r) => r.url.startsWith('/v1/text-to-speech/'));
  assert.equal(calls.length, 1, 'uma chamada para as três falas');
  assert.ok(calls[0].body.text.includes('Um.') && calls[0].body.text.includes('Três.'));
  assert.equal(clips.length, 3, 'o áudio contínuo é cortado em um arquivo por fala');
  assert.ok(clips.every((c, i) => !i || Math.abs(c.start - (clips[i - 1].start + clips[i - 1].seconds)) < 1e-6), 'falas emendadas sem lacuna');
  assert.ok(Math.abs(clips.reduce((t, c) => t + c.seconds, 0) - 1) < 0.01, 'a soma dos cortes é o áudio inteiro');
  assert.ok(script[1].start > script[0].start && script[2].end <= clips[2].start + clips[2].seconds + 0.2, 'legendas dentro do áudio contínuo');
  // cache por fala: editar uma fala ou acrescentar outra gera só ela
  requests.length = 0;
  const edited = script.map((l, i) => ({ ...l, start: i, end: i + 0.5, text: i === 1 ? `${l.text} editada` : l.text }));
  await speech([...edited, { text: `Quatro ${Date.now()}.`, start: 3, end: 3.5, speak: true, voice: null, style: null, auto: true }], {}, { root: process.cwd(), tts: ttsConfig(), keys: apiKeys() });
  const texts = requests.filter((r) => r.url.startsWith('/v1/text-to-speech/')).map((r) => r.body.text);
  assert.equal(texts.length, 2, 'uma chamada por trecho novo');
  assert.ok(texts[0].includes('editada') && !texts.some((t) => t.includes('Um.')), `só as falas novas: ${texts}`);
  // nada mudou: nenhuma chamada
  requests.length = 0;
  await speech(script.map((l, i) => ({ ...l, start: i, end: i + 0.5 })), {}, { root: process.cwd(), tts: ttsConfig(), keys: apiKeys() });
  assert.equal(requests.filter((r) => r.url.startsWith('/v1/text-to-speech/')).length, 0);
  // override: troca a voz de todas as falas
  requests.length = 0;
  await speech(script.map((l) => ({ ...l, text: `${l.text}!` })), {}, { root: process.cwd(), tts: ttsConfig(), keys: apiKeys(), override: { provider: 'elevenlabs', speaker: 'Rachel' } });
  assert.ok(requests.find((r) => r.url.startsWith('/v1/text-to-speech/')).url.startsWith('/v1/text-to-speech/v-rachel'));
});

test('falas pelo Fish Audio: voz por nome ou ID, modelo no cabeçalho, marcações e PCM em WAV', async () => {
  const { fishVoices, fishCredit } = await import('../src/services/fishaudio.mjs');
  const mine = await fishVoices(apiKey('fishaudio'), { mine: true });
  assert.deepEqual(mine.map((v) => v.name), ['Narradora BR'], 'vozes ainda em treino ficam de fora');
  assert.ok(requests.at(-1).url.includes('self=true'));
  assert.deepEqual(await fishCredit(apiKey('fishaudio')), { credit: '1.50', free: true });
  saveSettings({ tts: { provider: 'fishaudio' }, fishaudio: { model: 's2.1-pro-free', voice: '', voiceName: '' } });
  const script = [{ text: `Olá do Fish ${Date.now()}.`, start: 0, end: 0.4, speak: true, voice: 'n', style: 'animado', auto: true }];
  requests.length = 0;
  const clips = await speech(script, { n: { provider: 'fishaudio', speaker: 'narradora', language: 'Portuguese' } }, { root: process.cwd(), tts: ttsConfig(), keys: apiKeys() });
  assert.equal(clips.length, 1);
  assert.ok(Math.abs(wavSeconds(clips[0].file) - 0.5) < 1e-6);
  const call = requests.find((r) => r.url === '/v1/tts');
  assert.equal(call.model, 's2.1-pro-free');
  assert.equal(call.body.reference_id, 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4', 'voz achada pelo nome na conta');
  assert.equal(call.body.format, 'pcm');
  assert.equal(call.body.language, 'pt');
  assert.ok(call.body.text.startsWith('[excited] '), 'marcação do template no S2');
  // ID direto, sem listar; chave errada vira erro claro
  requests.length = 0;
  await speech([{ ...script[0], text: `ID ${Date.now()}` }], { n: { provider: 'fishaudio', speaker: 'ffffffffffffffffffffffffffffffff' } }, { root: process.cwd(), tts: ttsConfig(), keys: apiKeys() });
  assert.ok(!requests.some((r) => r.url.startsWith('/model')));
  await assert.rejects(speech([{ ...script[0], text: `x ${Date.now()}` }], { n: { provider: 'fishaudio' } }, { root: process.cwd(), tts: ttsConfig(), keys: { fishaudio: 'fish-errada-0000' } }), /Fish Audio recusou \(Invalid token\)/);
  assert.equal(runScriptOk('voice("n", provider="fishaudio")\nshow(box())'), true);
});
