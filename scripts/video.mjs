#!/usr/bin/env node
// Renderiza uma cena .3di com timeline() num vídeo MP4 pela linha de comando: quadros pelo editor
// num Chrome headless, falas do roteiro (say) pelo Qwen3-TTS e legendas num .srt ao lado do vídeo,
// embutidas como faixa ou gravadas na imagem (--burn). No app, o botão Vídeo faz o mesmo.
// Uso: node scripts/video.mjs cena.3di saida.mp4 [--size 1280x720] [--fps 30] [--from 0] [--to 10]
//                             [--burn] [--no-audio] [--no-subs] [--cpu]
import { mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { openEditor } from './headless.mjs';
import { ffmpegPath, speech, toSrt, scriptRange, frameEncoder, muxVideo } from '../src/services/video.mjs';
import { ttsConfig, apiKeys } from '../src/services/settings.mjs';

const USAGE = 'uso: node scripts/video.mjs cena.3di saida.mp4 [--size 1280x720] [--fps 30] [--from s] [--to s] [--burn] [--no-audio] [--no-subs] [--cpu]';
const root = dirname(dirname(fileURLToPath(import.meta.url)));
const fail = (msg, code = 1) => { console.error(msg); process.exit(code); };

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

async function main() {
  const b = await openEditor(src, { cpu: opt.cpu, log });
  try {
    // componentes .jsx de overlay() ao lado da cena: o editor headless não lê o disco
    const jsx = {};
    for (const [, name] of src.matchAll(/["']([^"'\n]+\.(?:jsx|tsx))["']/g)) {
      try { jsx[name] = readFileSync(resolve(dirname(input), name), 'utf8'); } catch {}
    }
    await b.evaluate(`window.tdi.overlayFiles = ${JSON.stringify(jsx)}`);
    const status = await b.evaluate(`window.tdi.load(${JSON.stringify(src)})`);
    if (!status.startsWith('✓')) throw new Error(status.replace(/^✗\s*/, ''));
    const info = await b.evaluate('window.tdi.info()');
    const fps = opt.fps ?? info.fps ?? 30;
    const end = opt.to ?? info.duration;
    if (!(end > opt.from)) throw new Error('a cena não tem duração: use timeline(segundos), keys(...) ou say(...), ou passe --to');
    const script = scriptRange(info.script, opt.from, end);
    const clips = opt.audio ? await speech(script, info.voices, { root, tts: ttsConfig(), keys: apiKeys(), log }) : [];
    mkdirSync(dirname(output), { recursive: true });
    const base = output.replace(/\.[^./]+$/, '');
    const srt = opt.subs && script.length ? `${base}.srt` : null;
    if (srt) writeFileSync(srt, toSrt(script.sort((p, q) => p.start - q.start)));

    const ffmpeg = ffmpegPath(root);
    const frames = `${base}.quadros-${process.pid}.mp4`;
    const enc = frameEncoder(ffmpeg, frames, fps);
    const n = Math.max(1, Math.round((end - opt.from) * fps));
    const t0 = Date.now();
    for (let i = 0; i < n; i++) {
      const png = await b.evaluate(`window.tdi.frame({ t: ${opt.from + i / fps}, width: ${W}, height: ${H} })`);
      await enc.write(Buffer.from(png, 'base64'));
      if (i % fps === 0 || i === n - 1) process.stderr.write(`\rquadro ${i + 1}/${n} (${((i + 1) / ((Date.now() - t0) / 1000)).toFixed(1)} q/s)`);
    }
    await enc.close();
    process.stderr.write('\n');
    await muxVideo(ffmpeg, { frames, output, clips, script, srt, burn: opt.burn, duration: end - opt.from });
    rmSync(frames, { force: true });
    console.log(`vídeo: ${output} (${W}x${H}, ${fps} q/s, ${(end - opt.from).toFixed(1)} s, ${n} quadros)` +
      `${clips.length ? `, ${clips.length} fala(s)` : ''}${srt ? `, legendas ${opt.burn ? 'gravadas na imagem' : 'embutidas'} + ${srt}` : ''}`);
  } finally {
    await b.close();
  }
}

main().then(() => process.exit(0), (e) => fail(`ERRO ${e.message}`));
