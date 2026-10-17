// Imagem de referência sobre a vista 3D (como o "blueprint" dos programas de modelagem):
// fica por cima do canvas, sem capturar o mouse, com opacidade, escala e deslocamento ajustáveis.
// Fica salva no navegador (localStorage) e pode vir da ponte MCP (set_reference).
const KEY = '3di.reference';

export function createReference({ host, button, getShot }) {
  const layer = document.createElement('div');
  layer.id = 'refLayer';
  layer.hidden = true;
  const img = document.createElement('img');
  img.alt = 'Imagem de referência';
  layer.append(img);
  const bar = document.createElement('div');
  bar.id = 'refBar';
  bar.hidden = true;
  bar.innerHTML = `<span>Referência</span>
    <label title="Opacidade">◐ <input type="range" min="0" max="100" value="50" data-k="opacity"></label>
    <label title="Escala">⤢ <input type="range" min="20" max="300" value="100" data-k="scale"></label>
    <label title="Deslocamento horizontal">↔ <input type="range" min="-50" max="50" value="0" data-k="x"></label>
    <label title="Deslocamento vertical">↕ <input type="range" min="-50" max="50" value="0" data-k="y"></label>
    <button data-a="side" title="Mostra a referência ao lado da cena em vez de por cima">Lado a lado</button>
    <button data-a="hide" title="Esconde sem apagar">Esconder</button>
    <button data-a="clear" title="Remove a referência">✕</button>`;
  host.append(layer, bar);
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = 'image/*';

  let st = { src: null, opacity: 0.5, scale: 1, x: 0, y: 0, side: false, visible: true };
  const save = () => { try { st.src ? localStorage.setItem(KEY, JSON.stringify(st)) : localStorage.removeItem(KEY); } catch {} };
  const apply = () => {
    const on = !!st.src;
    bar.hidden = !on;
    layer.hidden = !on || !st.visible;
    button.classList.toggle('on', on);
    if (!on) return;
    img.src = st.src;
    layer.classList.toggle('side', st.side);
    img.style.opacity = st.side ? 1 : st.opacity;
    img.style.transform = `translate(${st.x}%, ${st.y}%) scale(${st.scale})`;
    for (const r of bar.querySelectorAll('input')) {
      const k = r.dataset.k;
      r.value = k === 'opacity' ? Math.round(st.opacity * 100) : k === 'scale' ? Math.round(st.scale * 100) : st[k];
    }
    bar.querySelector('[data-a=side]').classList.toggle('on', st.side);
    bar.querySelector('[data-a=hide]').textContent = st.visible ? 'Esconder' : 'Mostrar';
  };
  bar.addEventListener('input', (e) => {
    const k = e.target.dataset.k;
    if (!k) return;
    const v = Number(e.target.value);
    st[k] = k === 'opacity' || k === 'scale' ? v / 100 : v;
    apply(); save();
  });
  bar.addEventListener('click', (e) => {
    const a = e.target.dataset.a;
    if (a === 'side') st.side = !st.side;
    else if (a === 'hide') st.visible = !st.visible;
    else if (a === 'clear') st.src = null;
    else return;
    apply(); save();
  });
  input.onchange = () => {
    const f = input.files?.[0];
    if (!f) return;
    const rd = new FileReader();
    rd.onload = () => set({ src: rd.result });
    rd.readAsDataURL(f);
    input.value = '';
  };
  button.onclick = () => input.click();
  // arrastar uma imagem para a vista também define a referência
  host.addEventListener('dragover', (e) => { if ([...e.dataTransfer.items].some((i) => i.type.startsWith('image/'))) e.preventDefault(); });
  host.addEventListener('drop', (e) => {
    const f = [...e.dataTransfer.files].find((x) => x.type.startsWith('image/'));
    if (!f) return;
    e.preventDefault();
    const rd = new FileReader();
    rd.onload = () => set({ src: rd.result });
    rd.readAsDataURL(f);
  });

  function set(opts) {
    st = { ...st, visible: true, ...opts };
    apply(); save();
  }

  const loadImage = (src) => new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = () => rej(new Error('imagem de referência inválida')); i.src = src; });

  // Imagem para comparar: referência | render, lado a lado e na mesma altura, mais a sobreposição
  // (render com a referência por cima a 50%) com a mesma escala e deslocamento da tela.
  async function compare() {
    if (!st.src) throw new Error('nenhuma imagem de referência; use set_reference ou o botão Referência');
    const ref = await loadImage(st.src);
    const shotImg = await loadImage(`data:image/png;base64,${getShot()}`);
    const H = 512, rw = Math.round((ref.width / ref.height) * H), sw = Math.round((shotImg.width / shotImg.height) * H);
    const c = document.createElement('canvas');
    c.width = rw + sw * 2 + 16; c.height = H;
    const g = c.getContext('2d');
    g.fillStyle = '#20232b'; g.fillRect(0, 0, c.width, H);
    g.drawImage(ref, 0, 0, rw, H);
    g.drawImage(shotImg, rw + 8, 0, sw, H);
    // sobreposição: a referência encaixada (contain) na área do render, com escala/deslocamento
    const ox = rw + sw + 16;
    g.drawImage(shotImg, ox, 0, sw, H);
    const k = Math.min(sw / ref.width, H / ref.height) * st.scale;
    const w = ref.width * k, h = ref.height * k;
    g.globalAlpha = 0.5;
    g.drawImage(ref, ox + (sw - w) / 2 + (st.x / 100) * w, (H - h) / 2 + (st.y / 100) * h, w, h);
    g.globalAlpha = 1;
    g.font = '600 14px system-ui, sans-serif';
    for (const [t, x] of [['referência', 6], ['cena', rw + 14], ['sobreposição', ox + 6]]) {
      g.fillStyle = 'rgba(15,17,22,.75)'; g.fillRect(x - 4, 6, g.measureText(t).width + 10, 22);
      g.fillStyle = '#fff'; g.fillText(t, x, 22);
    }
    return c.toDataURL('image/png').split(',')[1];
  }

  try { const s = JSON.parse(localStorage.getItem(KEY) || 'null'); if (s?.src) st = { ...st, ...s }; } catch {}
  apply();
  return { set, compare, state: () => ({ ...st, src: st.src ? `${st.src.slice(0, 30)}…` : null }) };
}
