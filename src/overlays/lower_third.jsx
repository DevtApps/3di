// Tarja de nome (lower third): barra que desliza da esquerda com nome e função.
// props: name, role, accent, side ("left" | "right")
import { interpolate, fade } from '3di';

export default ({ name = 'Nome', role = '', accent = '#f97316', side = 'left', local, duration }) => {
  const bar = interpolate(local, [0, 0.45], [0, 1], { easing: 'out' });
  const txt = interpolate(local, [0.25, 0.7], [0, 1], { easing: 'out' });
  const o = fade(local, duration, 0.01, 0.4);
  const right = side === 'right';
  return (
    <div className={`absolute bottom-28 ${right ? 'right-28 items-end' : 'left-28 items-start'} flex flex-col`} style={{ opacity: o }}>
      <div className="overflow-hidden" style={{ clipPath: `inset(0 ${right ? 0 : (1 - bar) * 100}% 0 ${right ? (1 - bar) * 100 : 0}%)` }}>
        <div className="flex items-stretch bg-slate-950/85 shadow-2xl rounded-r-2xl">
          <div className="w-4" style={{ background: accent }} />
          <div className="px-10 py-6" style={{ opacity: txt, transform: `translateX(${(1 - txt) * -30}px)` }}>
            <div className="text-6xl font-bold text-white">{name}</div>
            {role && <div className="text-4xl text-slate-300 mt-2">{role}</div>}
          </div>
        </div>
      </div>
    </div>
  );
};
