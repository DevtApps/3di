// Falas pela API do ElevenLabs (alternativa ao Qwen3-TTS local). A chave vem das configurações
// (secrets.json) ou de ELEVENLABS_API_KEY. Pede PCM 24 kHz e grava como WAV, igual às falas do Qwen.
import { writeFileSync } from 'node:fs';

const API = () => process.env.THREEDI_ELEVENLABS_URL || 'https://api.elevenlabs.io';

async function call(path, key, init = {}) {
  if (!key) throw new Error('falta a chave de API do ElevenLabs: configure em ⚙ → Vozes');
  const r = await fetch(`${API()}${path}`, { ...init, headers: { 'xi-api-key': key, ...(init.headers ?? {}) }, signal: AbortSignal.timeout(120000) });
  if (!r.ok) {
    let msg = `${r.status}`;
    try { const j = await r.json(); msg = j.detail?.message ?? j.detail?.status ?? JSON.stringify(j.detail ?? j).slice(0, 200); } catch {}
    throw new Error(`ElevenLabs recusou (${msg})`);
  }
  return r;
}

// vozes da conta: [{ id, name, labels, preview }]
export async function elevenVoices(key) {
  const j = await (await call('/v1/voices', key)).json();
  return (j.voices ?? []).map((v) => ({ id: v.voice_id, name: v.name, labels: v.labels ?? {}, category: v.category ?? '', preview: v.preview_url ?? null }));
}

// acha a voz por id ou pelo nome (sem diferenciar maiúsculas)
export function findElevenVoice(voices, speaker) {
  const s = String(speaker ?? '').toLowerCase();
  return voices.find((v) => v.id.toLowerCase() === s) ?? voices.find((v) => v.name.toLowerCase() === s)
    ?? voices.find((v) => v.name.toLowerCase().startsWith(s)) ?? null;
}

const LANG = { portuguese: 'pt', english: 'en', spanish: 'es', french: 'fr', german: 'de', italian: 'it', russian: 'ru', japanese: 'ja', korean: 'ko', chinese: 'zh' };

// PCM 16 bits mono -> WAV
function wav(pcm, rate) {
  const h = Buffer.alloc(44);
  h.write('RIFF', 0); h.writeUInt32LE(36 + pcm.length, 4); h.write('WAVE', 8);
  h.write('fmt ', 12); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22);
  h.writeUInt32LE(rate, 24); h.writeUInt32LE(rate * 2, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34);
  h.write('data', 36); h.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([h, pcm]);
}

// job: { text, voiceId, model, language, tags, stability, style, speed, out }
export async function elevenSpeak(key, job) {
  // marcações de áudio (ex.: [excited]) só o v3 entende; nos outros modelos seriam lidas em voz alta
  const text = job.tags && job.model === 'eleven_v3' ? `${job.tags} ${job.text}` : job.text;
  const voice_settings = {};
  if (job.stability !== null && job.stability !== undefined) voice_settings.stability = job.stability;
  if (job.style !== null && job.style !== undefined) voice_settings.style = job.style;
  if (job.speed !== null && job.speed !== undefined) voice_settings.speed = job.speed;
  const lang = LANG[String(job.language ?? '').toLowerCase()];
  const body = { text, model_id: job.model, ...(Object.keys(voice_settings).length ? { voice_settings } : {}),
    // language_code só é aceito pelos modelos v2.5 e v3
    ...(lang && job.model !== 'eleven_multilingual_v2' ? { language_code: lang } : {}) };
  const r = await call(`/v1/text-to-speech/${encodeURIComponent(job.voiceId)}?output_format=pcm_24000`, key, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'audio/pcm' }, body: JSON.stringify(body),
  });
  const pcm = Buffer.from(await r.arrayBuffer());
  writeFileSync(job.out, wav(pcm, 24000));
  return pcm.length / 48000;
}
