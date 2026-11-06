// Falas pela API do Fish Audio (alternativa remota ao Qwen3-TTS local e ao ElevenLabs). A chave vem das
// configurações (secrets.json) ou de FISH_API_KEY. A voz é um modelo de voz do Fish (reference_id): da
// biblioteca pública ou da sua conta. Pede PCM 24 kHz e grava como WAV, igual às outras falas.
import { writeFileSync } from 'node:fs';
import { wav } from './elevenlabs.mjs';

const API = () => process.env.THREEDI_FISH_URL || 'https://api.fish.audio';

async function call(path, key, init = {}) {
  if (!key) throw new Error('falta a chave de API do Fish Audio: configure em ⚙ → Fish Audio');
  const r = await fetch(`${API()}${path}`, { ...init, headers: { Authorization: `Bearer ${key}`, ...(init.headers ?? {}) }, signal: AbortSignal.timeout(180000) });
  if (!r.ok) {
    let msg = `${r.status}`;
    try { const j = await r.json(); msg = j.message ?? j.reason ?? j.detail ?? JSON.stringify(j).slice(0, 200); } catch {}
    if (r.status === 402) msg += ' (sem crédito de API: use o modelo s2.1-pro-free ou adicione crédito)';
    throw new Error(`Fish Audio recusou (${msg})`);
  }
  return r;
}

// vozes: as da sua conta (mine) ou da biblioteca pública (busca por nome/idioma)
// [{ id, name, languages, author, description }]
export async function fishVoices(key, { mine = true, query = '', language = '', size = 50 } = {}) {
  const q = new URLSearchParams({ page_size: String(size), sort_by: mine ? 'created_at' : 'score' });
  if (mine) q.set('self', 'true');
  if (query) q.set('title', query);
  if (language) q.set('language', language);
  const j = await (await call(`/model?${q}`, key)).json();
  return (j.items ?? []).filter((m) => !m.state || m.state === 'trained')
    .map((m) => ({ id: m._id, name: m.title ?? m._id, languages: m.languages ?? [], author: m.author?.nickname ?? '', description: m.description ?? '' }));
}

// confere a chave e mostra o crédito
export async function fishCredit(key) {
  const j = await (await call('/wallet/self/api-credit?check_free_credit=true', key)).json();
  return { credit: j.credit ?? '0', free: !!j.has_free_credit };
}

// idioma das falas do 3DI -> BCP-47 (o Fish usa só para normalizar números, datas etc.)
const LANG = { portuguese: 'pt', english: 'en', spanish: 'es', french: 'fr', german: 'de', italian: 'it', russian: 'ru', japanese: 'ja', korean: 'ko', chinese: 'zh' };

// job: { text, voiceId, model, language, tags, speed, out }
export async function fishSpeak(key, job) {
  // marcações de emoção entre colchetes ([excited], [whispering]) valem nos modelos S2 e drama-3
  const text = job.tags && job.model !== 's1' ? `${job.tags} ${job.text}` : job.text;
  const body = { text, format: 'pcm', sample_rate: 24000, normalize: true, latency: 'normal' };
  if (job.voiceId) body.reference_id = job.voiceId;
  const lang = LANG[String(job.language ?? '').toLowerCase()];
  if (lang) body.language = lang;
  if (job.speed !== null && job.speed !== undefined) body.prosody = { speed: Math.min(2, Math.max(0.5, job.speed)), volume: 0 };
  const r = await call('/v1/tts', key, { method: 'POST', headers: { 'Content-Type': 'application/json', model: job.model }, body: JSON.stringify(body) });
  const pcm = Buffer.from(await r.arrayBuffer());
  writeFileSync(job.out, wav(pcm, 24000));
  return pcm.length / 48000;
}
