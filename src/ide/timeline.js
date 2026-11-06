// Linha do tempo do preview: tocar/pausar, arrastar o tempo, marcas das chaves (keys) e blocos das
// falas/legendas do roteiro, mais a legenda ativa por cima da vista.
import { icon, hydrateIcons } from './icons.js';

export function createTimeline({ host, captionHost = host, onSeek, onToggle, onFollow, onMute = () => {}, onVoice = () => {} }) {
  const bar = document.createElement('div');
  bar.id = 'timeline';
  bar.hidden = true;
  bar.innerHTML = `<div class="transport">
      <button data-a="start" class="ghost icon-btn sm" title="Voltar ao início" aria-label="Voltar ao início"><i data-icon="skip-back"></i></button>
      <button data-a="play" class="icon-btn sm" title="Tocar/pausar" aria-label="Tocar/pausar"><i data-icon="pause"></i></button>
      <span class="time">0.0 / 0.0 s</span>
    </div>
    <div class="track" title="Arraste para mudar o tempo"><div class="ruler"></div><div class="lanes"></div><div class="head"></div></div>
    <div class="tl-tools">
      <span class="audio-state idle"><i class="spin"></i><span class="txt"></span><span class="bar"><span></span></span></span>
      <select data-a="voice" title="Voz das falas no preview (e no vídeo)"><option value="">Voz do roteiro</option></select>
      <button data-a="mute" class="ghost icon-btn sm" title="Liga/desliga o som das falas no preview" aria-label="Som das falas"><i data-icon="volume-2"></i></button>
      <button data-a="follow" class="ghost icon-btn sm on" title="Usar a câmera animada do roteiro (girar a vista solta a câmera)" aria-label="Seguir a câmera do roteiro"><i data-icon="video"></i></button>
    </div>`;
  hydrateIcons(bar);
  const caption = document.createElement('div');
  caption.id = 'captionLine';
  caption.hidden = true;
  captionHost.append(caption);
  host.append(bar);
  const track = bar.querySelector('.track'), ruler = bar.querySelector('.ruler'), lanes = bar.querySelector('.lanes'), head = bar.querySelector('.head');
  const label = bar.querySelector('.time'), play = bar.querySelector('[data-a=play]'), follow = bar.querySelector('[data-a=follow]');
  let duration = 0, script = [], lastText = null, muted = false, wasPlaying = null;

  const pct = (t) => `${(100 * Math.min(duration, Math.max(0, t))) / (duration || 1)}%`;
  const seekFrom = (e) => {
    const r = track.getBoundingClientRect();
    onSeek(Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)) * duration);
  };
  track.addEventListener('pointerdown', (e) => {
    track.setPointerCapture(e.pointerId);
    seekFrom(e);
    const move = (ev) => seekFrom(ev);
    track.addEventListener('pointermove', move);
    track.addEventListener('pointerup', () => track.removeEventListener('pointermove', move), { once: true });
  });
  bar.addEventListener('click', (e) => {
    const a = e.target.dataset.a;
    if (a === 'start') onSeek(0);
    else if (a === 'play') onToggle();
    else if (a === 'follow') onFollow(!follow.classList.contains('on'));
    else if (a === 'mute') { muted = !muted; e.target.innerHTML = icon(muted ? 'volume-x' : 'volume-2'); e.target.classList.toggle('on', muted); onMute(muted); }
  });

  const voiceSel = bar.querySelector('[data-a=voice]');
  voiceSel.addEventListener('change', () => onVoice(voiceSel.value ? JSON.parse(voiceSel.value) : null));
  return {
    // opções do seletor de voz: [{ provider, speaker, label }]; current = override atual ou null
    setVoices(options, current) {
      voiceSel.replaceChildren(new Option('Voz do roteiro', ''), ...options.map((o) => new Option(o.label, JSON.stringify({ provider: o.provider, speaker: o.speaker }))));
      voiceSel.value = current ? JSON.stringify({ provider: current.provider, speaker: current.speaker }) : '';
      if (current && !voiceSel.value) voiceSel.value = '';
    },
    // dados da cena compilada: duração, chaves, roteiro e se há câmera animada
    setScene({ duration: d = 0, keyTimes = [], script: s = [], overlays = [], camTrack = null } = {}) {
      duration = d;
      script = s;
      bar.hidden = !(d > 0);
      follow.hidden = !camTrack;
      lanes.replaceChildren();
      // régua: marcas a cada 1, 2, 5, 10... s, conforme a duração
      const step = [0.5, 1, 2, 5, 10, 15, 30, 60, 120].find((v) => d / v <= 12) ?? 300;
      ruler.replaceChildren(...Array.from({ length: Math.floor(d / step) + 1 }, (_, i) => {
        const m = document.createElement('span');
        m.style.left = pct(i * step);
        m.textContent = `${+(i * step).toFixed(1)}s`;
        return m;
      }));
      for (const o of overlays) {
        const b = document.createElement('b');
        b.className = 'ovl';
        const end = o.end ?? d;
        b.style.left = pct(o.start);
        b.style.width = `calc(${pct(end)} - ${pct(o.start)})`;
        b.title = `${o.start.toFixed(1)}–${end.toFixed(1)} s: overlay ${/[<(]/.test(o.src) ? '(JSX)' : o.src}`;
        lanes.append(b);
      }
      for (const t of keyTimes) {
        const k = document.createElement('i');
        k.className = 'key';
        k.style.left = pct(t);
        k.title = `chave em ${t} s`;
        lanes.append(k);
      }
      for (const l of s) {
        const b = document.createElement('b');
        b.className = l.speak ? 'say' : 'cap';
        b.style.left = pct(l.start);
        b.style.width = `calc(${pct(l.end)} - ${pct(l.start)})`;
        b.title = `${l.start.toFixed(1)}–${l.end.toFixed(1)} s: ${l.text}`;
        lanes.append(b);
      }
      lastText = null;
    },
    // atualiza o cursor e a legenda para o instante t
    update(t, playing) {
      if (bar.hidden) return;
      head.style.left = pct(t);
      label.textContent = `${t.toFixed(1)} / ${duration.toFixed(1)} s`;
      if (playing !== wasPlaying) { wasPlaying = playing; play.innerHTML = icon(playing ? 'pause' : 'play'); }
      const text = script.filter((l) => t >= l.start && t < l.end).map((l) => l.text).join('\n') || null;
      if (text !== lastText) {
        lastText = text;
        caption.hidden = !text;
        caption.textContent = text ?? '';
      }
    },
    setFollow(on) { follow.classList.toggle('on', on); },
    // estado das falas: busy = gerando (blocos das falas piscam), progress = 0..1 ou null (indeterminado)
    setAudio({ has, status, busy = false, progress = null }) {
      if (has !== undefined) { bar.querySelector('[data-a=mute]').hidden = !has; voiceSel.hidden = !has; }
      const st = bar.querySelector('.audio-state');
      st.classList.toggle('busy', busy);
      st.querySelector('.txt').textContent = status ?? '';
      st.classList.toggle('idle', !busy && !status);
      st.querySelector('.bar').hidden = !busy;
      const fill = st.querySelector('.bar span');
      fill.classList.toggle('indet', busy && progress === null);
      fill.style.width = progress === null ? '' : `${Math.round(progress * 100)}%`;
      lanes.classList.toggle('pending', busy);
    },
  };
}
