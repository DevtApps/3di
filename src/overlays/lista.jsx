// Lista de tópicos que aparecem um a um.
// props: title, items (lista de textos), every (s entre itens), accent, side ("left" | "right")
import { interpolate, fade } from '3di';

export default ({ title = '', items = [], every = 0.6, accent = '#a78bfa', side = 'left', local, duration }) => (
  <div className={`absolute top-1/2 -translate-y-1/2 ${side === 'right' ? 'right-32' : 'left-32'} flex flex-col gap-6 max-w-[900px]`} style={{ opacity: fade(local, duration, 0.3, 0.4) }}>
    {title && <h2 className="text-7xl font-black text-white drop-shadow-2xl mb-4">{title}</h2>}
    {items.map((it, i) => {
      const k = interpolate(local, [0.3 + i * every, 0.7 + i * every], [0, 1], { easing: 'out' });
      return (
        <div key={i} className="flex items-center gap-6 text-5xl font-semibold text-white drop-shadow-xl" style={{ opacity: k, transform: `translateX(${(1 - k) * -60}px)` }}>
          <span className="w-6 h-6 rounded-full shrink-0" style={{ background: accent }} />
          <span>{it}</span>
        </div>
      );
    })}
  </div>
);
