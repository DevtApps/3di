// Comportamento do shell do studio: ícones, painel lateral redimensionável (largura salva) e menus
// suspensos (popover nativo) que fecham ao escolher um item.
import { hydrateIcons } from './icons.js';

const KEY = '3di.sideWidth';
const MIN = 300;

export function setupLayout({ onResize = () => {} } = {}) {
  hydrateIcons();
  const app = document.getElementById('app'), splitter = document.getElementById('splitter');
  const max = () => Math.max(MIN, app.getBoundingClientRect().width * 0.7);
  const setWidth = (w, save = true) => {
    const v = Math.round(Math.min(max(), Math.max(MIN, w)));
    app.style.setProperty('--side-w', `${v}px`);
    splitter.setAttribute('aria-valuenow', String(v));
    if (save) try { localStorage.setItem(KEY, String(v)); } catch {}
    onResize();
  };
  try { const w = Number(localStorage.getItem(KEY)); if (w) setWidth(w, false); } catch {}

  splitter.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    splitter.setPointerCapture(e.pointerId);
    splitter.classList.add('dragging');
    const left = app.getBoundingClientRect().left;
    const move = (ev) => setWidth(ev.clientX - left);
    splitter.addEventListener('pointermove', move);
    splitter.addEventListener('pointerup', () => { splitter.removeEventListener('pointermove', move); splitter.classList.remove('dragging'); }, { once: true });
  });
  splitter.addEventListener('keydown', (e) => {
    if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
    e.preventDefault();
    const cur = parseFloat(getComputedStyle(app).getPropertyValue('--side-w')) || 440;
    setWidth(cur + (e.key === 'ArrowRight' ? 24 : -24));
  });
  splitter.addEventListener('dblclick', () => setWidth(440));

  // diálogos (.modal): Esc ou clique fora do cartão fecham pelo próprio botão [data-a=close]
  const closeModal = (m) => m.querySelector('[data-a=close]')?.click();
  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    const open = [...document.querySelectorAll('.modal')].filter((m) => !m.hidden).at(-1);
    if (open) { e.preventDefault(); closeModal(open); }
  });
  document.addEventListener('pointerdown', (e) => { if (e.target.classList?.contains('modal')) closeModal(e.target); });

  // escolher um item fecha o menu
  for (const menu of document.querySelectorAll('.menu[popover]')) {
    menu.addEventListener('click', (e) => { if (e.target.closest('button')) menu.hidePopover(); });
  }
}
