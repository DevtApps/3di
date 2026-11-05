// Configurações do 3DI que valem para todos os projetos, num arquivo da pasta do 3DI
// ($XDG_DATA_HOME/3di/settings.json): modelo e voz do TTS e modelos dos agentes.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { dataDir } from './video.mjs';

export const TTS_MODELS = [
  { id: 'Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice', label: '1.7B (melhor, segue o estilo; ~6 GB de GPU)' },
  { id: 'Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice', label: '0.6B (mais leve, não segue o estilo)' },
];
export const SPEAKERS = [
  { id: 'Vivian', note: 'feminina, chinês' }, { id: 'Serena', note: 'feminina, chinês' }, { id: 'Uncle_Fu', note: 'masculina madura, chinês' },
  { id: 'Dylan', note: 'masculina, chinês de Pequim' }, { id: 'Eric', note: 'masculina, chinês de Sichuan' }, { id: 'Ryan', note: 'masculina, inglês' },
  { id: 'Aiden', note: 'masculina, inglês' }, { id: 'Ono_Anna', note: 'feminina, japonês' }, { id: 'Sohee', note: 'feminina, coreano' },
];

const DEFAULTS = {
  tts: { model: TTS_MODELS[0].id, device: 'auto', speaker: 'Serena', language: 'Portuguese', instruct: '' },
  agents: { claude: { model: '', models: [] }, codex: { model: '', models: [] } },
};

const file = () => join(dataDir(), 'settings.json');
const merge = (base, over) => {
  if (!over || typeof over !== 'object' || Array.isArray(base)) return over ?? base;
  const out = { ...base };
  for (const [k, v] of Object.entries(over)) out[k] = k in base && base[k] && typeof base[k] === 'object' && !Array.isArray(base[k]) ? merge(base[k], v) : v;
  return out;
};

export function loadSettings() {
  try { return merge(DEFAULTS, JSON.parse(readFileSync(file(), 'utf8'))); } catch { return structuredClone(DEFAULTS); }
}

// Grava só os campos conhecidos, com tipos conferidos
export function saveSettings(patch) {
  const s = merge(loadSettings(), patch ?? {});
  const str = (v, d = '') => (typeof v === 'string' ? v.slice(0, 200) : d);
  const clean = {
    tts: {
      model: TTS_MODELS.some((m) => m.id === s.tts.model) ? s.tts.model : DEFAULTS.tts.model,
      device: ['auto', 'cuda', 'cpu'].includes(s.tts.device) ? s.tts.device : 'auto',
      speaker: SPEAKERS.some((v) => v.id === s.tts.speaker) ? s.tts.speaker : DEFAULTS.tts.speaker,
      language: str(s.tts.language, 'Portuguese') || 'Portuguese',
      instruct: str(s.tts.instruct),
    },
    agents: Object.fromEntries(['claude', 'codex'].map((p) => [p, {
      model: str(s.agents?.[p]?.model),
      models: [...new Set((Array.isArray(s.agents?.[p]?.models) ? s.agents[p].models : []).map((m) => str(m).trim()).filter(Boolean))].slice(0, 30),
    }])),
  };
  mkdirSync(dataDir(), { recursive: true });
  writeFileSync(file(), JSON.stringify(clean, null, 2));
  return clean;
}
