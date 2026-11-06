// Vídeo do 3DI: codifica os quadros (PNG) com o ffmpeg empacotado, gera as falas do roteiro com o
// Qwen3-TTS e junta áudio e legendas. Usado pelo app (os quadros vêm da janela do editor, por HTTP)
// e por scripts/video.mjs (quadros de um Chrome headless).
//
// Tudo o que não cabe no pacote fica numa pasta do 3DI ($XDG_DATA_HOME/3di, padrão ~/.local/share/3di):
//   tts/venv   ambiente Python com qwen-tts (criado por installTts, sob pedido)
//   tts/cache  falas já geradas (só fala nova ou alterada é gerada de novo)
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, openSync, readSync, closeSync, writeFileSync, rmSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';

export const dataDir = () => join(process.env.XDG_DATA_HOME || join(homedir(), '.local', 'share'), '3di');
const venvDir = () => join(dataDir(), 'tts', 'venv');
const cacheDir = () => join(dataDir(), 'tts', 'cache');

// Arquivos do app empacotado ficam dentro de app.asar; executáveis vão para app.asar.unpacked
const unpacked = (p) => p.replace(/app\.asar(?=[\\/])/, 'app.asar.unpacked');

// ffmpeg: THREEDI_FFMPEG, o do pacote (bin/ffmpeg), o do ffmpeg-static (desenvolvimento) ou o do sistema
export function ffmpegPath(root) {
  for (const p of [process.env.THREEDI_FFMPEG, join(root, 'bin', 'ffmpeg'), join(root, 'node_modules', 'ffmpeg-static', 'ffmpeg')]) {
    if (p && existsSync(unpacked(p))) return unpacked(p);
  }
  return 'ffmpeg';
}

// Python das vozes: o ambiente do 3DI; no desenvolvimento, também o .venv-tts do repositório
export function ttsPython(root) {
  for (const p of [join(venvDir(), 'bin', 'python'), join(root, '.venv-tts', 'bin', 'python')]) if (existsSync(p)) return p;
  return null;
}

export const ttsStatus = (root) => ({ installed: !!ttsPython(root), dir: venvDir() });

const run = (cmd, argv, { onLine, env } = {}) => new Promise((res, rej) => {
  const p = spawn(cmd, argv, { stdio: ['ignore', 'pipe', 'pipe'], env: env ? { ...process.env, ...env } : process.env });
  let out = '', err = '';
  const lines = (d) => { for (const l of String(d).split(/\r?\n/)) if (l.trim()) onLine?.(l.trim().slice(0, 300)); };
  p.stdout.on('data', (d) => { out += d; lines(d); });
  p.stderr.on('data', (d) => { err = (err + d).slice(-6000); lines(d); });
  p.on('error', rej);
  p.on('exit', (code) => (code === 0 ? res(out) : rej(new Error(`${cmd.split('/').pop()} falhou (${code})\n${err.trim().split('\n').slice(-6).join('\n')}`))));
});

// Cria o ambiente das vozes na pasta do 3DI (pip baixa o qwen-tts e o PyTorch: alguns GB).
// Precisa do python3 com venv (no Debian/Ubuntu: python3-venv).
export async function removeTts() {
  const { rm } = await import('node:fs/promises');
  await rm(join(dataDir(), 'tts'), { recursive: true, force: true });
}

export async function installTts(log = () => {}) {
  const dir = venvDir();
  mkdirSync(dirname(dir), { recursive: true });
  log(`criando o ambiente das vozes em ${dir}`);
  try { await run('python3', ['-m', 'venv', dir], { onLine: log }); }
  catch (e) { throw new Error(`não consegui criar o ambiente Python (instale o python3-venv): ${e.message}`); }
  const pip = join(dir, 'bin', 'pip');
  await run(pip, ['install', '-U', 'pip'], { onLine: log });
  log('instalando qwen-tts e soundfile (pode levar vários minutos)');
  await run(pip, ['install', '-U', 'qwen-tts', 'soundfile'], { onLine: log });
  log('vozes instaladas; os pesos do modelo são baixados na primeira fala');
}

// Duração de um WAV PCM pelo cabeçalho (o ffmpeg empacotado não traz o ffprobe)
export function wavSeconds(file) {
  const fd = openSync(file, 'r');
  try {
    const head = Buffer.alloc(4096);
    const n = readSync(fd, head, 0, head.length, 0);
    let off = 12, rate = 0, block = 0;
    while (off + 8 <= n) {
      const id = head.toString('ascii', off, off + 4), size = head.readUInt32LE(off + 4);
      if (id === 'fmt ') { rate = head.readUInt32LE(off + 12); block = head.readUInt16LE(off + 20); }
      if (id === 'data') return rate && block ? size / (rate * block) : 0;
      off += 8 + size + (size & 1);
    }
    return 0;
  } finally { closeSync(fd); }
}

// ---------- legendas ----------
const srtTime = (t) => {
  const ms = Math.max(0, Math.round(t * 1000));
  const p = (v, w = 2) => String(v).padStart(w, '0');
  return `${p(Math.floor(ms / 3600000))}:${p(Math.floor(ms / 60000) % 60)}:${p(Math.floor(ms / 1000) % 60)},${p(ms % 1000, 3)}`;
};
export const toSrt = (lines) => lines.map((l, i) => `${i + 1}\n${srtTime(l.start)} --> ${srtTime(l.end)}\n${l.text}\n`).join('\n');

// Recorta o roteiro ao trecho [from, to) e o põe em tempo do vídeo
export function scriptRange(script, from, to) {
  return script.filter((l) => l.end > from && l.start < to)
    .map((l) => ({ ...l, start: Math.max(0, l.start - from), end: Math.min(to, l.end) - from }))
    .sort((p, q) => p.start - q.start);
}

// ---------- falas (Qwen3-TTS) ----------
// Gera (ou pega do cache) o áudio de cada say(). Reagenda pela duração real: a legenda dura pelo
// menos a fala e falas sem `at` andam para depois da anterior; com `at`, só avisa.
// Pedido de fala: { text, provider ('qwen' | 'elevenlabs'), speaker, language, template, instruct }.
// tts = configurações (ttsConfig): provedor e voz padrão, modelos, templates, vozes clonadas e o ElevenLabs.
// Cada fala gerada fica em cache pelo conteúdo do pedido: só fala nova ou alterada é gerada de novo.
export async function synthesize(jobs, { root, tts = {}, log = () => {}, progress = () => {}, elevenKey = null }) {
  mkdirSync(cacheDir(), { recursive: true });
  const cloned = new Map((tts.voices ?? []).map((v) => [v.id.toLowerCase(), v]));
  const templates = new Map((tts.templates ?? []).map((x) => [x.id.toLowerCase(), x]));
  const eleven = tts.elevenlabs ?? {};
  let elevenVoiceList = null;
  const items = [];
  for (const j of jobs) {
    const provider = j.provider || tts.provider || 'qwen';
    const tpl = j.template ? templates.get(String(j.template).toLowerCase()) : null;
    if (j.template && !tpl) throw new Error(`template de áudio '${j.template}' não existe (veja ⚙ → Templates de áudio)`);
    let job;
    if (provider === 'elevenlabs') {
      // voz: o speaker do script (nome ou id) ou a voz padrão do ElevenLabs nas configurações
      let voiceId = eleven.voice;
      if (j.speaker && j.speaker !== tts.speaker) {
        // nome da voz: procura na conta; um ID de voz é usado direto (funciona sem a permissão voices_read)
        const looksLikeId = /^[A-Za-z0-9]{18,32}$/.test(String(j.speaker));
        try {
          elevenVoiceList ??= await (await import('./elevenlabs.mjs')).elevenVoices(elevenKey);
          const v = (await import('./elevenlabs.mjs')).findElevenVoice(elevenVoiceList, j.speaker);
          if (!v && !looksLikeId) throw new Error(`voz '${j.speaker}' não existe na sua conta do ElevenLabs`);
          voiceId = v?.id ?? j.speaker;
        } catch (e) {
          if (!looksLikeId || !/voices_read/.test(e.message)) throw /voices_read/.test(e.message) ? new Error(`${e.message}: use o ID da voz em speaker= ou ligue a permissão "Voices: Read" na chave`) : e;
          voiceId = j.speaker;
        }
      }
      if (!voiceId) throw new Error('escolha uma voz do ElevenLabs nas configurações (⚙ → Vozes)');
      job = { provider, text: j.text, voiceId, model: eleven.model, language: j.language, tags: tpl?.tags || '',
        stability: tpl?.stability ?? null, style: tpl?.style ?? null, speed: tpl?.speed ?? null };
    } else {
      const c = cloned.get(String(j.speaker).toLowerCase());
      const instruct = [tpl?.prompt, j.instruct].filter(Boolean).join('; ') || null;
      job = c
        ? { text: j.text, language: j.language || c.language, ref_audio: c.file, ref_text: c.refText || null, model: tts.cloneModel || null,
          ref: existsSync(c.file) ? `${statSync(c.file).size}-${statSync(c.file).mtimeMs}` : null }
        : { text: j.text, speaker: j.speaker, language: j.language, instruct, model: tts.model || null };
      if (c && !job.ref) throw new Error(`o áudio da voz clonada '${c.id}' sumiu: clone de novo nas configurações`);
    }
    const key = createHash('sha1').update(JSON.stringify(job)).digest('hex').slice(0, 16);
    items.push({ ...job, key, out: join(cacheDir(), `${key}.wav`) });
  }
  const missing = items.filter((it) => !existsSync(it.out));
  const total = missing.length;
  let done = 0;
  if (total) progress({ stage: 'model', done, total });
  // ElevenLabs: uma chamada por fala
  const remote = missing.filter((it) => it.provider === 'elevenlabs');
  if (remote.length) {
    const { elevenSpeak } = await import('./elevenlabs.mjs');
    log(`gerando ${remote.length} fala(s) pelo ElevenLabs`);
    for (const it of remote) {
      const secs = await elevenSpeak(elevenKey, it);
      done++;
      progress({ stage: 'speech', done, total });
      log(`fala pronta: ${secs.toFixed(1)} s`);
    }
  }
  // Qwen3-TTS: todas de uma vez, num processo Python
  const local = missing.filter((it) => it.provider !== 'elevenlabs');
  if (local.length) {
    const py = ttsPython(root);
    if (!py) throw new Error('vozes do Qwen3-TTS não instaladas: use Instalar vozes nas configurações do 3DI (ou escolha o ElevenLabs)');
    log(`gerando ${local.length} fala(s) com o Qwen3-TTS (a primeira vez baixa o modelo)`);
    const req = join(cacheDir(), `pedido-${process.pid}-${Date.now()}.json`);
    writeFileSync(req, JSON.stringify(local));
    const env = { ...(tts.model ? { THREEDI_TTS_MODEL: tts.model } : {}), ...(tts.cloneModel ? { THREEDI_TTS_CLONE_MODEL: tts.cloneModel } : {}), ...(tts.device && tts.device !== 'auto' ? { THREEDI_TTS_DEVICE: tts.device } : {}) };
    try { await run(py, [unpacked(join(root, 'scripts', 'tts.py')), req], { env, onLine: (l) => {
      if (!l.startsWith('{')) return;
      if (l.includes('"loaded"')) { progress({ stage: 'speech', done, total }); return; }
      done++;
      progress({ stage: 'speech', done, total });
      log(`fala pronta: ${JSON.parse(l).seconds.toFixed(1)} s`);
    } }); }
    finally { rmSync(req, { force: true }); }
  }
  return items.map((it) => ({ key: it.key, file: it.out, seconds: wavSeconds(it.out) }));
}

// arquivo de uma fala do cache pela chave (para o preview tocar)
export function clipFile(key) {
  return /^[0-9a-f]{16}$/.test(key) ? join(cacheDir(), `${key}.wav`) : null;
}

// Gera as falas do roteiro. A voz de cada say() vem da voice() dele (provider, speaker, language,
// instruct, template) ou das configurações; style é o nome de um template ou um estilo livre.
// Pausas de um WAV (silencedetect do ffmpeg): [{ start, end }] em segundos
export async function detectSilences(ffmpeg, file, { noise = -32, min = 0.12 } = {}) {
  return new Promise((res) => {
    const p = spawn(ffmpeg, ['-hide_banner', '-nostats', '-i', file, '-af', `silencedetect=noise=${noise}dB:d=${min}`, '-f', 'null', '-'], { stdio: ['ignore', 'ignore', 'pipe'] });
    let err = '';
    p.stderr.on('data', (d) => { err += d; });
    p.on('error', () => res([]));
    p.on('exit', () => {
      const out = [];
      let start = null;
      for (const m of err.matchAll(/silence_(start|end): (-?[\d.]+)/g)) {
        if (m[1] === 'start') start = Math.max(0, Number(m[2]));
        else if (start !== null) { out.push({ start, end: Number(m[2]) }); start = null; }
      }
      res(out);
    });
  });
}

// Onde cada frase de um bloco começa no áudio contínuo: perto da posição proporcional ao texto,
// na pausa mais próxima (a fala tem ritmo variável; as pausas entre frases são o corte natural)
export function splitByPauses(texts, total, silences) {
  const chars = texts.map((t) => Math.max(1, t.length));
  const sum = chars.reduce((p, q) => p + q, 0);
  const cuts = [0];
  let acc = 0;
  for (let i = 0; i + 1 < texts.length; i++) {
    acc += chars[i];
    const expected = (total * acc) / sum;
    const prev = cuts[cuts.length - 1];
    const window = Math.max(0.6, total * 0.25);
    let best = null;
    for (const sil of silences) {
      const mid = (sil.start + sil.end) / 2;
      if (mid <= prev + 0.3 || mid >= total - 0.2) continue;
      const d = Math.abs(mid - expected);
      if (d <= window && (!best || d < best.d)) best = { d, at: mid };
    }
    cuts.push(best ? best.at : Math.max(prev + 0.3, expected));
  }
  cuts.push(total);
  return texts.map((_, i) => ({ start: cuts[i], end: cuts[i + 1] }));
}

// Gera as falas do roteiro. A voz de cada say() vem da voice() dele (provider, speaker, language,
// instruct, template) ou das configurações; style é o nome de um template ou um estilo livre.
// override = { provider, speaker }: troca a voz de todas as falas (seletor de voz do preview/vídeo).
//
// Falas seguidas com a mesma voz e o mesmo estilo saem NUMA chamada só (a entonação segue de uma frase
// para a outra, como numa narração); as legendas de cada frase são achadas pelas pausas do áudio. Uma
// fala com `at` explícito, outra voz ou outro estilo começa outro bloco. Devolve um trecho por bloco.
const BLOCK_CHARS = 900;
export async function speech(script, voices, { root, tts = {}, log = () => {}, progress = () => {}, elevenKey = null, override = null }) {
  const lines = script.filter((l) => l.speak).sort((p, q) => p.start - q.start);
  if (!lines.length) return [];
  const provider = override?.provider || tts.provider || 'qwen';
  const usesQwen = provider === 'qwen' || Object.values(voices ?? {}).some((v) => v.provider === 'qwen');
  if (usesQwen && !ttsPython(root) && provider !== 'elevenlabs' && !Object.values(voices ?? {}).some((v) => v.provider === 'elevenlabs')) {
    log('aviso: vozes não instaladas, sem as falas (instale nas configurações do 3DI ou use o ElevenLabs)');
    return [];
  }
  const templates = new Set((tts.templates ?? []).map((x) => x.id.toLowerCase()));
  const jobOf = (l) => {
    const v = (l.voice && voices[l.voice]) || {};
    const isTemplate = l.style && templates.has(String(l.style).toLowerCase());
    return {
      provider: override?.provider || v.provider || provider,
      speaker: override?.speaker || v.speaker || tts.speaker,
      language: v.language || tts.language || 'Portuguese',
      template: isTemplate ? l.style : (v.template || tts.template || null),
      instruct: [v.instruct ?? (l.voice ? null : tts.instruct), isTemplate ? null : l.style].filter(Boolean).join('; ') || null,
    };
  };
  // blocos de fala contínua
  const blocks = [];
  for (const line of lines) {
    const job = jobOf(line);
    const sig = JSON.stringify(job);
    const last = blocks[blocks.length - 1];
    const chars = last ? last.lines.reduce((n, l) => n + l.text.length, 0) : 0;
    if (last && last.sig === sig && line.auto && chars + line.text.length <= BLOCK_CHARS) last.lines.push(line);
    else blocks.push({ sig, job, lines: [line] });
  }
  const made = await synthesize(blocks.map((b) => ({ ...b.job, text: b.lines.map((l) => l.text.trim()).join(' ') })), { root, tts, log, progress, elevenKey });
  const ffmpeg = ffmpegPath(root);
  const clips = [];
  let prevEnd = 0;
  for (let i = 0; i < blocks.length; i++) {
    const { lines: ls } = blocks[i];
    const len = made[i].seconds;
    const first = ls[0];
    let start = first.start;
    if (start < prevEnd) {
      if (first.auto) start = prevEnd + 0.25;
      else log(`aviso: a fala em ${start.toFixed(2)} s começa antes da anterior acabar (${prevEnd.toFixed(2)} s)`);
    }
    // legendas por frase: pelas pausas do áudio contínuo
    const parts = ls.length > 1 ? splitByPauses(ls.map((l) => l.text), len, await detectSilences(ffmpeg, made[i].file)) : [{ start: 0, end: len }];
    ls.forEach((l, k) => {
      l.start = start + parts[k].start;
      l.end = start + parts[k].end + (k === ls.length - 1 ? 0.15 : 0);
    });
    prevEnd = start + len;
    clips.push({ file: made[i].file, key: made[i].key, start, seconds: len, lines: ls.length });
  }
  if (blocks.length < lines.length) log(`${lines.length} falas em ${blocks.length} trecho(s) contínuo(s)`);
  return clips;
}

// ---------- codificação ----------
// Recebe os quadros PNG em ordem (write) e grava um MP4 intermediário (close).
export function frameEncoder(ffmpeg, file, fps) {
  const ff = spawn(ffmpeg, ['-y', '-v', 'error', '-f', 'image2pipe', '-framerate', String(fps), '-i', '-',
    '-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-pix_fmt', 'yuv420p', file], { stdio: ['pipe', 'ignore', 'pipe'] });
  let err = '';
  ff.stderr.on('data', (d) => { err = (err + d).slice(-4000); });
  const done = new Promise((res, rej) => {
    ff.on('error', rej);
    ff.on('exit', (c) => (c === 0 ? res() : rej(new Error(`ffmpeg falhou\n${err}`))));
  });
  done.catch(() => {});
  return {
    async write(png) { if (!ff.stdin.write(png)) await new Promise((r) => ff.stdin.once('drain', r)); },
    async close() { ff.stdin.end(); await done; },
    kill() { ff.kill('SIGKILL'); },
  };
}

// Junta o vídeo dos quadros, as falas nos seus instantes e as legendas (faixa embutida ou --burn)
export async function muxVideo(ffmpeg, { frames, output, clips, script, srt, burn, duration }) {
  const subs = script.length > 0 && !!srt;
  const argv = ['-y', '-v', 'error', '-i', frames];
  for (const c of clips) argv.push('-i', c.file);
  const soft = subs && !burn;
  if (soft) argv.push('-i', srt);
  const filters = [];
  if (clips.length) {
    clips.forEach((c, i) => filters.push(`[${i + 1}:a]adelay=${Math.round(c.start * 1000)}:all=1[a${i}]`));
    filters.push(`${clips.map((_, i) => `[a${i}]`).join('')}amix=inputs=${clips.length}:normalize=0:duration=longest[aout]`);
  }
  if (subs && burn) filters.push(`[0:v]subtitles='${srt.replace(/\\/g, '/').replace(/'/g, "\\'").replace(/:/g, '\\:')}':force_style='FontSize=22,Outline=2,MarginV=28'[vout]`);
  if (filters.length) argv.push('-filter_complex', filters.join(';'));
  argv.push('-map', subs && burn ? '[vout]' : '0:v');
  if (clips.length) argv.push('-map', '[aout]', '-c:a', 'aac', '-b:a', '192k');
  if (soft) argv.push('-map', `${clips.length + 1}:s`, '-c:s', 'mov_text', '-metadata:s:s:0', 'language=por');
  argv.push('-c:v', subs && burn ? 'libx264' : 'copy');
  if (subs && burn) argv.push('-crf', '18', '-pix_fmt', 'yuv420p');
  argv.push('-t', String(duration), output);
  await run(ffmpeg, argv);
}
