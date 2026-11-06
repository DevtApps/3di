// Título grande com subtítulo: entra subindo com mola e sai em fade.
// props: title, subtitle, align ("center" | "left"), position ("center" | "top" | "bottom"), color, accent
import { spring, fade, interpolate } from '3di';

export default ({ title = 'Título', subtitle = '', align = 'center', position = 'center', color = '#ffffff', accent = '#38bdf8', local, duration }) => {
  const up = spring(local, { from: 60, to: 0, damping: 14 });
  const o = fade(local, duration, 0.35, 0.5);
  const line = interpolate(local, [0.2, 0.9], [0, 100], { easing: 'out' });
  const place = { center: 'items-center', top: 'items-start pt-32', bottom: 'items-end pb-32' }[position] ?? 'items-center';
  const text = align === 'left' ? 'text-left items-start pl-32' : 'text-center items-center';
  return (
    <div className={`absolute inset-0 flex ${place} justify-center`} style={{ opacity: o }}>
      <div className={`flex flex-col gap-6 w-full ${text}`} style={{ transform: `translateY(${up}px)` }}>
        <h1 className="text-9xl font-black tracking-tight drop-shadow-2xl" style={{ color }}>{title}</h1>
        <div className="h-2 rounded-full" style={{ width: `${line * 4}px`, background: accent }} />
        {subtitle && <p className="text-5xl font-medium opacity-90 drop-shadow-xl" style={{ color }}>{subtitle}</p>}
      </div>
    </div>
  );
};
