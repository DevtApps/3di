// Vídeo do 3DI: codifica os quadros (PNG) com o ffmpeg empacotado, gera as falas do roteiro com o
// Qwen3-TTS e junta áudio e legendas. Usado pelo app (os quadros vêm da janela do editor, por HTTP)
// e por scripts/video.mjs (quadros de um Chrome headless).
//
// Tudo o que não cabe no pacote fica numa pasta do 3DI ($XDG_DATA_HOME/3di, padrão ~/.local/share/3di):
//   tts/venv   ambiente Python com qwen-tts (criado por installTts, sob pedido)
//   tts/cache  falas já geradas (só fala nova ou alterada é gerada de novo)
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, openSync, readSync, closeSync, writeFileSync, rmSync } from 'node:fs';
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
// tts = { model, device, speaker, language, instruct }: configurações (a voz padrão vale para say() sem voice)
export async function synthesize(jobs, { root, tts = {}, log = () => {} }) {
  const py = ttsPython(root);
  if (!py) throw new Error('vozes não instaladas: use Instalar vozes nas configurações do 3DI');
  mkdirSync(cacheDir(), { recursive: true });
  const items = jobs.map((j) => {
    const job = { text: j.text, speaker: j.speaker, language: j.language, instruct: j.instruct || null, model: tts.model || null };
    const key = createHash('sha1').update(JSON.stringify(job)).digest('hex').slice(0, 16);
    return { ...job, key, out: join(cacheDir(), `${key}.wav`) };
  });
  const missing = items.filter((it) => !existsSync(it.out));
  if (missing.length) {
    log(`gerando ${missing.length} fala(s) com o Qwen3-TTS (a primeira vez baixa o modelo)`);
    const req = join(cacheDir(), `pedido-${process.pid}-${Date.now()}.json`);
    writeFileSync(req, JSON.stringify(missing));
    const env = { ...(tts.model ? { THREEDI_TTS_MODEL: tts.model } : {}), ...(tts.device && tts.device !== 'auto' ? { THREEDI_TTS_DEVICE: tts.device } : {}) };
    try { await run(py, [unpacked(join(root, 'scripts', 'tts.py')), req], { env, onLine: (l) => { if (l.startsWith('{')) log(`fala pronta: ${JSON.parse(l).seconds.toFixed(1)} s`); } }); }
    finally { rmSync(req, { force: true }); }
  }
  return items.map((it) => ({ key: it.key, file: it.out, seconds: wavSeconds(it.out) }));
}

// arquivo de uma fala do cache pela chave (para o preview tocar)
export function clipFile(key) {
  return /^[0-9a-f]{16}$/.test(key) ? join(cacheDir(), `${key}.wav`) : null;
}

export async function speech(script, voices, { root, tts = {}, log = () => {} }) {
  const lines = script.filter((l) => l.speak);
  if (!lines.length) return [];
  if (!ttsPython(root)) { log('aviso: vozes não instaladas, sem as falas (instale nas configurações do 3DI)'); return []; }
  const fallback = { speaker: tts.speaker || 'Serena', language: tts.language || 'Portuguese', instruct: tts.instruct || null };
  const made = await synthesize(lines.map((l) => {
    const v = (l.voice && voices[l.voice]) || fallback;
    return { text: l.text, speaker: v.speaker, language: v.language, instruct: [v.instruct, l.style].filter(Boolean).join('; ') || null };
  }), { root, tts, log });
  const items = lines.map((line, i) => ({ line, job: { out: made[i].file, key: made[i].key } }));
  const clips = [];
  let prevEnd = 0;
  for (const { line, job } of items.sort((p, q) => p.line.start - q.line.start)) {
    const len = wavSeconds(job.out);
    if (line.start < prevEnd) {
      if (line.auto) { const shift = prevEnd + 0.25 - line.start; line.start += shift; line.end += shift; }
      else log(`aviso: a fala em ${line.start.toFixed(2)} s começa antes da anterior acabar (${prevEnd.toFixed(2)} s)`);
    }
    line.end = Math.max(line.end, line.start + len + 0.15);
    prevEnd = line.start + len;
    clips.push({ file: job.out, key: job.key, start: line.start, seconds: len });
  }
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
