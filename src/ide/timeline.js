// Linha do tempo do preview: tocar/pausar, arrastar o tempo, marcas das chaves (keys) e blocos das
// falas/legendas do roteiro, mais a legenda ativa por cima da vista.
export function createTimeline({ host, onSeek, onToggle, onFollow, onMute = () => {} }) {
  const bar = document.createElement('div');
  bar.id = 'timeline';
  bar.hidden = true;
  bar.innerHTML = `<button data-a="start" title="Voltar ao início">⏮</button>
    <button data-a="play" title="Tocar/pausar (espaço com a vista em foco)">⏸</button>
    <div class="track"><div class="lanes"></div><div class="head"></div></div>
    <span class="time">0.0 / 0.0 s</span>
    <button data-a="mute" title="Liga/desliga o som das falas no preview">🔊</button>
    <span class="audio-state"><i class="spin"></i><span class="txt"></span><span class="bar"><span></span></span></span>
    <button data-a="follow" class="on" title="Usar a câmera animada do roteiro (girar a vista solta a câmera)">🎥</button>`;
  const caption = document.createElement('div');
  caption.id = 'captionLine';
  caption.hidden = true;
  host.append(caption, bar);
  const track = bar.querySelector('.track'), lanes = bar.querySelector('.lanes'), head = bar.querySelector('.head');
  const label = bar.querySelector('.time'), play = bar.querySelector('[data-a=play]'), follow = bar.querySelector('[data-a=follow]');
  let duration = 0, script = [], lastText = null;

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
    else if (a === 'mute') { const b = e.target; const off = b.textContent === '🔊'; b.textContent = off ? '🔇' : '🔊'; onMute(off); }
  });

  return {
    // dados da cena compilada: duração, chaves, roteiro e se há câmera animada
    setScene({ duration: d = 0, keyTimes = [], script: s = [], camTrack = null } = {}) {
      duration = d;
      script = s;
      bar.hidden = !(d > 0);
      follow.hidden = !camTrack;
      lanes.replaceChildren();
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
      play.textContent = playing ? '⏸' : '▶';
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
      if (has !== undefined) bar.querySelector('[data-a=mute]').hidden = !has;
      const st = bar.querySelector('.audio-state');
      st.classList.toggle('busy', busy);
      st.querySelector('.txt').textContent = status ?? '';
      st.querySelector('.bar').hidden = !busy;
      const fill = st.querySelector('.bar span');
      fill.classList.toggle('indet', busy && progress === null);
      fill.style.width = progress === null ? '' : `${Math.round(progress * 100)}%`;
      lanes.classList.toggle('pending', busy);
    },
  };
}
