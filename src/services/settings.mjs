// Configurações do 3DI que valem para todos os projetos, num arquivo da pasta do 3DI
// ($XDG_DATA_HOME/3di/settings.json): provedor, modelo e voz das falas, templates de áudio,
// vozes clonadas e modelos dos agentes. Segredos (chave do ElevenLabs) ficam em secrets.json, só
// legível pelo usuário, e nunca voltam inteiros para a IDE.
import { readFileSync, writeFileSync, mkdirSync, chmodSync } from 'node:fs';
import { join } from 'node:path';
import { dataDir } from './video.mjs';

export const PROVIDERS = [
  { id: 'qwen', label: 'Qwen3-TTS (local, na sua GPU)' },
  { id: 'elevenlabs', label: 'ElevenLabs (API, precisa de chave)' },
];
export const TTS_MODELS = [
  { id: 'Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice', label: '1.7B (melhor, segue o estilo; ~6 GB de GPU)' },
  { id: 'Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice', label: '0.6B (mais leve, não segue o estilo)' },
];
export const ELEVEN_MODELS = [
  { id: 'eleven_multilingual_v2', label: 'Multilingual v2 (estável, ótimo em português)' },
  { id: 'eleven_v3', label: 'v3 (mais expressivo; entende marcações como [excited])' },
  { id: 'eleven_flash_v2_5', label: 'Flash v2.5 (rápido e barato)' },
  { id: 'eleven_turbo_v2_5', label: 'Turbo v2.5' },
];
export const SPEAKERS = [
  { id: 'Vivian', note: 'feminina, chinês' }, { id: 'Serena', note: 'feminina, chinês' }, { id: 'Uncle_Fu', note: 'masculina madura, chinês' },
  { id: 'Dylan', note: 'masculina, chinês de Pequim' }, { id: 'Eric', note: 'masculina, chinês de Sichuan' }, { id: 'Ryan', note: 'masculina, inglês' },
  { id: 'Aiden', note: 'masculina, inglês' }, { id: 'Ono_Anna', note: 'feminina, japonês' }, { id: 'Sohee', note: 'feminina, coreano' },
];
export const CLONE_MODELS = [
  { id: 'Qwen/Qwen3-TTS-12Hz-1.7B-Base', label: '1.7B (melhor; ~6 GB de GPU)' },
  { id: 'Qwen/Qwen3-TTS-12Hz-0.6B-Base', label: '0.6B (mais leve)' },
];
// nome de voz clonada ou de template: letras, números, - e _ (usado no script)
export const VOICE_NAME = /^[A-Za-z0-9_-]{2,40}$/;

// Templates de áudio: o estilo de uma fala. prompt = instrução para o Qwen3-TTS (instruct);
// tags = marcações de áudio do ElevenLabs v3 postas antes do texto; stability/style/speed = ajustes do
// ElevenLabs (null = padrão da voz).
const t = (id, label, prompt, tags, stability, style, speed) => ({ id, label, prompt, tags, stability, style, speed });
export const DEFAULT_TEMPLATES = [
  t('narrador', 'Narrador de documentário', 'voz grave e calma de narrador de documentário, ritmo pausado e claro', '[calm]', 0.7, 0.2, 0.95),
  t('animado', 'Apresentador animado', 'tom animado e sorridente de apresentador, energia alta', '[excited]', 0.35, 0.6, 1.05),
  t('calmo', 'Calmo e acolhedor', 'voz suave, calma e acolhedora, sem pressa', '[softly]', 0.75, 0.15, 0.92),
  t('sussurro', 'Sussurro', 'sussurrando, bem baixinho e próximo do microfone', '[whispers]', 0.6, 0.3, 0.9),
  t('comercial', 'Locução comercial', 'locução de comercial de rádio, confiante, enfática e clara', '[confident]', 0.45, 0.5, 1.02),
  t('noticiario', 'Âncora de telejornal', 'âncora de telejornal, neutro, articulado e firme', '', 0.8, 0.1, 1.0),
  t('crianca', 'Para crianças', 'contando história para crianças, expressivo, alegre e lento', '[playfully]', 0.4, 0.55, 0.9),
];

const DEFAULTS = {
  tts: { provider: 'qwen', model: TTS_MODELS[0].id, cloneModel: CLONE_MODELS[0].id, device: 'auto', speaker: 'Serena', language: 'Portuguese', instruct: '', template: '' },
  elevenlabs: { model: ELEVEN_MODELS[0].id, voice: '', voiceName: '' },
  templates: DEFAULT_TEMPLATES,
  // vozes clonadas: { id, file (WAV na pasta do 3DI), refText, language }
  voices: [],
  agents: { claude: { model: '', models: [], path: '' }, codex: { model: '', models: [], path: '' } },
};

const file = () => join(dataDir(), 'settings.json');
const secretsFile = () => join(dataDir(), 'secrets.json');
export const voicesDir = () => join(dataDir(), 'voices');
const merge = (base, over) => {
  if (!over || typeof over !== 'object' || Array.isArray(base)) return over ?? base;
  const out = { ...base };
  for (const [k, v] of Object.entries(over)) out[k] = k in base && base[k] && typeof base[k] === 'object' && !Array.isArray(base[k]) ? merge(base[k], v) : v;
  return out;
};

export function loadSettings() {
  try { return merge(DEFAULTS, JSON.parse(readFileSync(file(), 'utf8'))); } catch { return structuredClone(DEFAULTS); }
}

const num01 = (v, lo = 0, hi = 1) => (v === null || v === undefined || v === '' || !Number.isFinite(Number(v)) ? null : Math.min(hi, Math.max(lo, Number(v))));

// Grava só os campos conhecidos, com tipos conferidos
export function saveSettings(patch) {
  const s = merge(loadSettings(), patch ?? {});
  const str = (v, d = '') => (typeof v === 'string' ? v.slice(0, 200) : d);
  const templates = (Array.isArray(s.templates) ? s.templates : []).filter((x) => x && VOICE_NAME.test(x.id))
    .map((x) => ({ id: x.id, label: str(x.label) || x.id, prompt: str(x.prompt).slice(0, 400), tags: str(x.tags).slice(0, 120),
      stability: num01(x.stability), style: num01(x.style), speed: num01(x.speed, 0.7, 1.2) })).slice(0, 60);
  const voices = (Array.isArray(s.voices) ? s.voices : []).filter((v) => v && VOICE_NAME.test(v.id) && typeof v.file === 'string')
    .map((v) => ({ id: v.id, file: v.file, refText: str(v.refText).slice(0, 500), language: str(v.language, 'Portuguese') || 'Portuguese' })).slice(0, 100);
  const clean = {
    tts: {
      provider: PROVIDERS.some((p) => p.id === s.tts.provider) ? s.tts.provider : 'qwen',
      model: TTS_MODELS.some((m) => m.id === s.tts.model) ? s.tts.model : DEFAULTS.tts.model,
      cloneModel: CLONE_MODELS.some((m) => m.id === s.tts.cloneModel) ? s.tts.cloneModel : DEFAULTS.tts.cloneModel,
      device: ['auto', 'cuda', 'cpu'].includes(s.tts.device) ? s.tts.device : 'auto',
      speaker: SPEAKERS.some((v) => v.id === s.tts.speaker) || voices.some((v) => v.id === s.tts.speaker) ? s.tts.speaker : DEFAULTS.tts.speaker,
      language: str(s.tts.language, 'Portuguese') || 'Portuguese',
      instruct: str(s.tts.instruct),
      template: templates.some((x) => x.id === s.tts.template) ? s.tts.template : '',
    },
    elevenlabs: {
      model: ELEVEN_MODELS.some((m) => m.id === s.elevenlabs?.model) ? s.elevenlabs.model : DEFAULTS.elevenlabs.model,
      voice: str(s.elevenlabs?.voice).replace(/[^\w-]/g, ''),
      voiceName: str(s.elevenlabs?.voiceName),
    },
    templates,
    voices,
    agents: Object.fromEntries(['claude', 'codex'].map((p) => [p, {
      model: str(s.agents?.[p]?.model),
      path: str(s.agents?.[p]?.path).trim(),
      models: [...new Set((Array.isArray(s.agents?.[p]?.models) ? s.agents[p].models : []).map((m) => str(m).trim()).filter(Boolean))].slice(0, 30),
    }])),
  };
  mkdirSync(dataDir(), { recursive: true });
  writeFileSync(file(), JSON.stringify(clean, null, 2));
  return clean;
}

// ---------- segredos ----------
function loadSecrets() {
  try { return JSON.parse(readFileSync(secretsFile(), 'utf8')); } catch { return {}; }
}
export function elevenKey() {
  return process.env.ELEVENLABS_API_KEY || loadSecrets().elevenlabsKey || null;
}
// grava (ou apaga, com '') a chave; o arquivo fica só legível pelo usuário
export function setElevenKey(key) {
  const k = String(key ?? '').trim();
  if (k && !/^[\w-]{10,200}$/.test(k)) throw new Error('chave do ElevenLabs inválida');
  const sec = loadSecrets();
  if (k) sec.elevenlabsKey = k; else delete sec.elevenlabsKey;
  mkdirSync(dataDir(), { recursive: true });
  writeFileSync(secretsFile(), JSON.stringify(sec), { mode: 0o600 });
  chmodSync(secretsFile(), 0o600);
}
// o que a IDE pode ver da chave
export function elevenKeyInfo() {
  const k = elevenKey();
  return { set: !!k, hint: k ? `…${k.slice(-4)}` : '', fromEnv: !!process.env.ELEVENLABS_API_KEY };
}

// configuração passada à geração das falas
export function ttsConfig() {
  const s = loadSettings();
  return { ...s.tts, voices: s.voices, templates: s.templates, elevenlabs: s.elevenlabs };
}
