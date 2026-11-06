// Animação por chaves, linha do tempo e roteiro (falas, legendas e vozes).
// keys() devolve expressões de `time`: valem em tudo que já aceita time (at, rotate, scale, glow,
// cores de glow, fórmulas, câmera). O roteiro vira dados da cena: o preview mostra as legendas e o
// render de vídeo gera o áudio das falas (TTS) e grava as legendas.
import { ScriptError } from './parser.js';
import { Native, num, tuple, typeName } from './runtime.js';
import { isExpr, sym, TIME } from './expr.js';

const EASES = ['linear', 'smooth', 'in', 'out', 'step'];

// curva de 0 a 1 dentro de um trecho (x é uma expressão já limitada a 0..1)
function ease(kind, x) {
  if (kind === 'linear') return x;
  if (kind === 'smooth') return sym('smoothstep', 0, 1, x);
  if (kind === 'in') return sym('*', x, x);
  if (kind === 'out') { const u = sym('-', 1, x); return sym('-', 1, sym('*', u, u)); }
  return sym('step', 1, x); // step: segura o valor até a próxima chave
}

// valor em função do tempo passando pelas chaves (t, v): v0 + soma dos saltos já percorridos
function track(points, kind, T) {
  let e = points[0][1];
  for (let i = 0; i + 1 < points.length; i++) {
    const [t0, v0] = points[i], [t1, v1] = points[i + 1];
    if (v1 === v0) continue;
    const x = sym('clamp', sym('/', sym('-', T, t0), Math.max(1e-6, t1 - t0)), 0, 1);
    e = sym('+', e, sym('*', v1 - v0, ease(kind, x)));
  }
  return e;
}

// props das sobreposições: só valores simples (atravessam o worker e vão para o React)
function plain(v, k) {
  if (v === null || typeof v === 'string' || typeof v === 'boolean' || isNum(v)) return v;
  if (Array.isArray(v)) return v.map((x) => plain(x, k));
  if (v instanceof Map) return Object.fromEntries([...v].map(([kk, x]) => [String(kk), plain(x, k)]));
  if (isExpr(v)) throw new ScriptError(`overlay(): ${k} não pode ser keys()/time; anime dentro do componente com t e progress`, null);
  throw new ScriptError(`overlay(): ${k} deve ser texto, número, lista ou dict (recebeu ${typeName(v)})`, null);
}
const isNum = (v) => typeof v === 'number' && Number.isFinite(v);
// fala em português do TTS: ~12 caracteres por segundo
const estimateDuration = (text) => Math.max(1.4, 0.5 + String(text).length / 12);

export function timelineBuiltins(scene) {
  scene.keyTimes ??= [];
  scene.script ??= [];
  scene.voices ??= {};
  scene.overlays ??= [];
  const N = (name, params, fn) => new Native(name, params, fn);
  // Próximo instante livre do roteiro (falas sem `at` entram em sequência)
  const cursor = () => scene.script.reduce((m, l) => Math.max(m, l.end), 0);
  const line = (a, speak) => {
    const text = String(a.text);
    if (!text.trim()) throw new ScriptError(`${speak ? 'say' : 'caption'}(): texto vazio`, null);
    const start = a.at === null ? cursor() + (scene.script.length ? 0.25 : 0) : num(a.at, 'at');
    const dur = a.dur === null ? estimateDuration(text) : num(a.dur, 'dur');
    if (start < 0 || !(dur > 0)) throw new ScriptError('at deve ser >= 0 e dur > 0 (segundos)', null);
    const voice = a.voice === null ? null : String(a.voice);
    if (voice && !scene.voices[voice]) throw new ScriptError(`voz '${voice}' não definida`, null, 'crie antes com voice("nome", speaker="Ryan")');
    const entry = { text, start, end: start + dur, voice, style: a.style === null || a.style === undefined ? null : String(a.style), speak, estimated: a.dur === null, auto: a.at === null };
    scene.script.push(entry);
    return entry.end;
  };
  return {
    // keys((0, 0), (1, 90), (3, 0), ease="smooth", loop=False): chaves (tempo, valor). O valor pode
    // ser número ou tupla (posição, ângulos, cor); devolve uma expressão (ou tupla) de time.
    keys: N('keys', ['*points', 'ease="smooth"', 'loop=False'], (a) => {
      const kind = String(a.ease).toLowerCase();
      if (!EASES.includes(kind)) throw new ScriptError(`keys(): ease desconhecido '${a.ease}'`, null, `use ${EASES.join(', ')}`);
      const pts = a.points.length === 1 && Array.isArray(a.points[0]) && Array.isArray(a.points[0][0]) ? a.points[0] : a.points;
      if (pts.length < 2) throw new ScriptError('keys() precisa de pelo menos 2 chaves (tempo, valor)', null, 'ex.: keys((0, 0), (2, 90))');
      const parsed = pts.map((p, i) => {
        if (!Array.isArray(p) || p.length !== 2) throw new ScriptError(`keys(): a chave ${i + 1} deve ser (tempo, valor), recebeu ${typeName(p)}`, null);
        const t = num(p[0], `tempo da chave ${i + 1}`);
        const v = p[1];
        if (isNum(v)) return [t, [v]];
        if (Array.isArray(v) && v.length && v.every(isNum)) return [t, [...v]];
        throw new ScriptError(`keys(): o valor da chave ${i + 1} deve ser número ou tupla de números`, null);
      });
      for (let i = 1; i < parsed.length; i++) {
        if (!(parsed[i][0] > parsed[i - 1][0])) throw new ScriptError('keys(): os tempos devem ser crescentes', null);
        if (parsed[i][1].length !== parsed[0][1].length) throw new ScriptError('keys(): todas as chaves devem ter o mesmo tipo de valor', null);
      }
      const last = parsed[parsed.length - 1][0];
      const T = a.loop ? sym('%', TIME, last) : TIME;
      for (const [t] of parsed) if (!scene.keyTimes.includes(t)) scene.keyTimes.push(t);
      const comps = parsed[0][1].map((_, c) => track(parsed.map(([t, v]) => [t, v[c]]), kind, T));
      return isNum(pts[0][1]) ? comps[0] : tuple(comps);
    }),
    // duração e quadros por segundo do vídeo (e da animação exportada no GLB)
    timeline: N('timeline', ['duration=10', 'fps=30'], (a) => {
      const duration = num(a.duration, 'duration'), fps = num(a.fps, 'fps');
      if (!(duration > 0) || !(fps >= 1 && fps <= 120)) throw new ScriptError('timeline(): duration > 0 e fps de 1 a 120', null);
      scene.anim = { duration, fps };
      return null;
    }),
    // voz para as falas. provider: "qwen" (Qwen3-TTS local) ou "elevenlabs"; speaker: voz pronta do Qwen
    // (Vivian, Serena, Uncle_Fu, Dylan, Eric, Ryan, Aiden, Ono_Anna, Sohee), voz clonada ou voz do ElevenLabs
    // (nome ou id); template: template de áudio (estilo com o prompt); instruct: estilo livre (Qwen).
    // Sem speaker/provider, valem os padrões das configurações (⚙).
    voice: N('voice', ['name', 'speaker=None', 'language="Portuguese"', 'instruct=None', 'provider=None', 'template=None'], (a) => {
      const name = String(a.name);
      const provider = a.provider === null ? null : String(a.provider).toLowerCase();
      if (provider && !['qwen', 'elevenlabs'].includes(provider)) throw new ScriptError(`voice(): provider deve ser "qwen" ou "elevenlabs"`, null);
      scene.voices[name] = { speaker: a.speaker === null ? null : String(a.speaker), language: String(a.language), instruct: a.instruct === null ? null : String(a.instruct),
        provider, template: a.template === null ? null : String(a.template) };
      return name;
    }),
    // fala: legenda + áudio gerado por TTS. Sem `at`, entra depois da fala anterior. style: nome de um
    // template de áudio ou um estilo livre.
    // dur estima pelo tamanho do texto; no vídeo, vale a duração real do áudio. Devolve o fim (s).
    say: N('say', ['text', 'at=None', 'dur=None', 'voice=None', 'style=None'], (a) => line(a, true)),
    // Sobreposição em React + Tailwind sobre a imagem, de `at` até `at + dur` (sem dur: até o fim).
    // component: nome de um componente do 3DI ("titulo", "lower_third", "texto", ...), arquivo .jsx
    // ao lado da cena ou o próprio código JSX (string com '<'). Os outros argumentos nomeados viram
    // props do componente. z: ordem de empilhamento.
    overlay: N('overlay', ['component', 'at=0', 'dur=None', 'z=0', '**props'], (a) => {
      const src = String(a.component);
      if (!src.trim()) throw new ScriptError('overlay(): component vazio', null);
      const start = num(a.at, 'at'), dur = a.dur === null ? null : num(a.dur, 'dur');
      if (start < 0 || (dur !== null && !(dur > 0))) throw new ScriptError('overlay(): at >= 0 e dur > 0 (segundos)', null);
      const props = {};
      for (const [k, v] of Object.entries(a.props)) props[k] = plain(v, k);
      scene.overlays.push({ src, start, end: dur === null ? null : start + dur, z: num(a.z, 'z'), props });
      if (dur !== null) scene.keyTimes.push(start + dur);
      return null;
    }),
    // só legenda, sem áudio
    caption: N('caption', ['text', 'at=None', 'dur=None'], (a) => line({ ...a, voice: null, style: null }, false)),
  };
}

// Duração da cena: timeline() > fim do roteiro / última chave
export function sceneDuration(scene) {
  if (scene.anim?.duration) return scene.anim.duration;
  const ends = [...(scene.keyTimes ?? []), ...(scene.script ?? []).map((l) => l.end)];
  // sem dur, a sobreposição dura até o fim; ela conta pelo início
  for (const o of scene.overlays ?? []) ends.push(o.end ?? o.start + 3);
  return ends.length ? Math.max(...ends) + 0.5 : 0;
}

// Câmera animada vira trilha amostrada (expressões não atravessam o worker): {fps, pos, look, fov}
export function cameraTrack(camera, duration, fps = 60) {
  if (!camera) return null;
  const parts = [camera.pos, camera.look, [camera.fov]].filter(Boolean);
  if (!parts.some((p) => p.some(isExpr))) return null;
  const at = (v, t) => (isExpr(v) ? v.eval(t, {}) : v);
  const n = Math.max(2, Math.ceil(duration * fps) + 1);
  const pos = [], look = [], fov = [];
  for (let i = 0; i < n; i++) {
    const t = i / fps;
    pos.push(camera.pos.map((v) => at(v, t)));
    look.push(camera.look ? camera.look.map((v) => at(v, t)) : null);
    fov.push(at(camera.fov, t));
  }
  return { fps, pos, look, fov };
}
