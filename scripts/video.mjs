#!/usr/bin/env node
// Renderiza uma cena .3di com timeline() num vídeo MP4: quadros pelo editor num Chrome headless,
// falas do roteiro (say) geradas pelo Qwen3-TTS, legendas (say/caption) num .srt ao lado do vídeo,
// embutidas como faixa de legenda ou gravadas na imagem (--burn).
// Uso: node scripts/video.mjs cena.3di saida.mp4 [--size 1280x720] [--fps 30] [--from 0] [--to 10]
//                             [--burn] [--no-audio] [--no-subs] [--cpu]
// Áudio: precisa do ambiente .venv-tts (pip install qwen-tts soundfile); as falas ficam em cache
// em out/.tts-cache e só são geradas de novo quando o texto, a voz ou o estilo mudam.
import { spawn, execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { openEditor } from './headless.mjs';

const USAGE = 'uso: node scripts/video.mjs cena.3di saida.mp4 [--size 1280x720] [--fps 30] [--from s] [--to s] [--burn] [--no-audio] [--no-subs] [--cpu]';
const root = dirname(dirname(fileURLToPath(import.meta.url)));
const fail = (msg, code = 1) => { console.error(msg); process.exit(code); };

// ---------- argumentos ----------
const args = process.argv.slice(2), pos = [];
const opt = { size: '1280x720', fps: null, from: 0, to: null, burn: false, audio: true, subs: true, cpu: false };
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--size') opt.size = args[++i];
  else if (a === '--fps' || a === '--from' || a === '--to') {
    const v = Number(args[++i]);
    if (!Number.isFinite(v)) fail(`${a} precisa de um número\n${USAGE}`, 2);
    opt[a.slice(2)] = v;
  } else if (a === '--burn') opt.burn = true;
  else if (a === '--no-audio') opt.audio = false;
  else if (a === '--no-subs') opt.subs = false;
  else if (a === '--cpu') opt.cpu = true;
  else if (a === '-h' || a === '--help') { console.log(USAGE); process.exit(0); }
  else pos.push(a);
}
if (pos.length !== 2) fail(USAGE, 2);
const [input, output] = pos.map((p) => resolve(p));
const m = /^(\d+)x(\d+)$/.exec(opt.size);
if (!m) fail(`--size deve ser LARGURAxALTURA, ex.: 1280x720\n${USAGE}`, 2);
// libx264 com yuv420p exige dimensões pares
const W = Number(m[1]) & ~1, H = Number(m[2]) & ~1;
const src = readFileSync(input, 'utf8');

const log = (s) => process.stderr.write(`${s}\n`);
const run = (cmd, argv, opts = {}) => new Promise((res, rej) => {
  const p = spawn(cmd, argv, { stdio: ['ignore', 'pipe', 'pipe'], ...opts });
  let out = '', err = '';
  p.stdout?.on('data', (d) => { out += d; });
  p.stderr?.on('data', (d) => { err = (err + d).slice(-6000); });
  p.on('error', rej);
  p.on('exit', (code) => (code === 0 ? res(out) : rej(new Error(`${cmd} falhou (${code})\n${err}`))));
});
const seconds = (file) => Number(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'default=nw=1:nk=1', file]).toString().trim());

// ---------- legendas ----------
const srtTime = (t) => {
  const ms = Math.max(0, Math.round(t * 1000));
  const p = (n, w = 2) => String(n).padStart(w, '0');
  return `${p(Math.floor(ms / 3600000))}:${p(Math.floor(ms / 60000) % 60)}:${p(Math.floor(ms / 1000) % 60)},${p(ms % 1000, 3)}`;
};
const toSrt = (lines) => lines.map((l, i) => `${i + 1}\n${srtTime(l.start)} --> ${srtTime(l.end)}\n${l.text}\n`).join('\n');

// ---------- falas (Qwen3-TTS) ----------
async function speech(script, voices) {
  const lines = script.filter((l) => l.speak);
  if (!lines.length) return [];
  const py = join(root, '.venv-tts', 'bin', 'python');
  if (!existsSync(py)) {
    log('aviso: sem .venv-tts, o vídeo sai sem as falas (python3 -m venv .venv-tts && .venv-tts/bin/pip install qwen-tts soundfile)');
    return [];
  }
  const cache = join(root, 'out', '.tts-cache');
  mkdirSync(cache, { recursive: true });
  const items = lines.map((l) => {
    const v = (l.voice && voices[l.voice]) || { speaker: 'Ryan', language: 'Portuguese', instruct: null };
    const instruct = [v.instruct, l.style].filter(Boolean).join('; ') || null;
    const job = { text: l.text, speaker: v.speaker, language: v.language, instruct };
    const key = createHash('sha1').update(JSON.stringify(job)).digest('hex').slice(0, 16);
    return { line: l, job: { ...job, out: join(cache, `${key}.wav`) } };
  });
  const missing = items.filter((it) => !existsSync(it.job.out)).map((it) => it.job);
  if (missing.length) {
    log(`gerando ${missing.length} fala(s) com o Qwen3-TTS...`);
    const req = join(cache, `pedido-${process.pid}.json`);
    writeFileSync(req, JSON.stringify(missing));
    try { await run(py, [join(root, 'scripts', 'tts.py'), req]); } finally { rmSync(req, { force: true }); }
  }
  // Reagenda pelo áudio real: a legenda dura pelo menos a fala; falas sem `at` andam para depois
  // da fala anterior (a estimativa do script não sabe a duração real); com `at`, só avisa.
  const clips = [];
  let prevEnd = 0;
  for (const { line, job } of items.sort((p, q) => p.line.start - q.line.start)) {
    const len = seconds(job.out);
    if (line.start < prevEnd) {
      if (line.auto) {
        const shift = prevEnd + 0.25 - line.start;
        line.start += shift;
        line.end += shift;
      } else log(`aviso: a fala em ${line.start.toFixed(2)} s começa antes da anterior acabar (${prevEnd.toFixed(2)} s): "${line.text.slice(0, 40)}"`);
    }
    line.end = Math.max(line.end, line.start + len + 0.15);
    prevEnd = line.start + len;
    clips.push({ file: job.out, start: line.start, seconds: len });
  }
  return clips;
}

// ---------- principal ----------
async function main() {
  const b = await openEditor(src, { cpu: opt.cpu, log });
  try {
    const status = await b.evaluate(`window.tdi.load(${JSON.stringify(src)})`);
    if (!status.startsWith('✓')) throw new Error(status.replace(/^✗\s*/, ''));
    const info = await b.evaluate('window.tdi.info()');
    const fps = opt.fps ?? info.fps ?? 30;
    const end = opt.to ?? info.duration;
    if (!(end > opt.from)) throw new Error('a cena não tem duração: use timeline(segundos), keys(...) ou say(...), ou passe --to');
    const script = info.script
      .filter((l) => l.end > opt.from && l.start < end)
      .map((l) => ({ ...l, start: Math.max(0, l.start - opt.from), end: Math.min(end, l.end) - opt.from }));

    const clips = opt.audio ? await speech(script, info.voices) : [];
    mkdirSync(dirname(output), { recursive: true });
    const srt = output.replace(/\.[^./]+$/, '') + '.srt';
    script.sort((p, q) => p.start - q.start);
    if (opt.subs && script.length) writeFileSync(srt, toSrt(script));

    // quadros -> vídeo intermediário (PNG pelo stdin do ffmpeg)
    const tmp = output.replace(/\.[^./]+$/, '') + `.quadros-${process.pid}.mp4`;
    const n = Math.max(1, Math.round((end - opt.from) * fps));
    const ff = spawn('ffmpeg', ['-y', '-v', 'error', '-f', 'image2pipe', '-framerate', String(fps), '-i', '-',
      '-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-pix_fmt', 'yuv420p', tmp], { stdio: ['pipe', 'ignore', 'pipe'] });
    let ffErr = '';
    ff.stderr.on('data', (d) => { ffErr = (ffErr + d).slice(-4000); });
    const ffDone = new Promise((res, rej) => ff.on('exit', (c) => (c === 0 ? res() : rej(new Error(`ffmpeg falhou\n${ffErr}`)))));
    const t0 = Date.now();
    for (let i = 0; i < n; i++) {
      const t = opt.from + i / fps;
      const png = await b.evaluate(`window.tdi.frame({ t: ${t}, width: ${W}, height: ${H} })`);
      if (!ff.stdin.write(Buffer.from(png, 'base64'))) await new Promise((r) => ff.stdin.once('drain', r));
      if (i % fps === 0 || i === n - 1) process.stderr.write(`\rquadro ${i + 1}/${n} (${((i + 1) / ((Date.now() - t0) / 1000)).toFixed(1)} q/s)`);
    }
    ff.stdin.end();
    await ffDone;
    process.stderr.write('\n');

    // mistura as falas em seus instantes, embute ou grava as legendas
    const argv = ['-y', '-v', 'error', '-i', tmp];
    for (const c of clips) argv.push('-i', c.file);
    const useSoftSubs = opt.subs && script.length && !opt.burn;
    if (useSoftSubs) argv.push('-i', srt);
    const filters = [];
    if (clips.length) {
      clips.forEach((c, i) => filters.push(`[${i + 1}:a]adelay=${Math.round(c.start * 1000)}:all=1[a${i}]`));
      filters.push(`${clips.map((_, i) => `[a${i}]`).join('')}amix=inputs=${clips.length}:normalize=0:duration=longest[aout]`);
    }
    if (opt.subs && script.length && opt.burn) filters.push(`[0:v]subtitles='${srt.replace(/'/g, "\\'")}':force_style='FontSize=22,Outline=2,MarginV=28'[vout]`);
    if (filters.length) argv.push('-filter_complex', filters.join(';'));
    argv.push('-map', opt.burn && opt.subs && script.length ? '[vout]' : '0:v');
    if (clips.length) argv.push('-map', '[aout]', '-c:a', 'aac', '-b:a', '192k');
    if (useSoftSubs) argv.push('-map', `${clips.length + 1}:s`, '-c:s', 'mov_text', '-metadata:s:s:0', 'language=por');
    argv.push('-c:v', opt.burn && opt.subs && script.length ? 'libx264' : 'copy');
    if (opt.burn) argv.push('-crf', '18', '-pix_fmt', 'yuv420p');
    // o vídeo dura a timeline, mesmo se a última fala passar do fim
    argv.push('-t', String(end - opt.from), output);
    await run('ffmpeg', argv);
    rmSync(tmp, { force: true });
    console.log(`vídeo: ${output} (${W}x${H}, ${fps} q/s, ${(end - opt.from).toFixed(1)} s, ${n} quadros)` +
      `${clips.length ? `, ${clips.length} fala(s)` : ''}${opt.subs && script.length ? `, legendas ${opt.burn ? 'gravadas na imagem' : 'embutidas'} + ${srt}` : ''}`);
  } finally {
    await b.close();
  }
}

main().then(() => process.exit(0), (e) => fail(`ERRO ${e.message}`));
