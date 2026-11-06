// Número que conta de `from` até `to`, com rótulo.
// props: from, to, prefix, suffix, decimals, label, color, accent, x, y
import { interpolate, fade } from '3di';

export default ({ from = 0, to = 100, prefix = '', suffix = '', decimals = 0, label = '', color = '#ffffff', accent = '#22c55e', x = 0.5, y = 0.5, local, duration }) => {
  const v = interpolate(local, [0, Math.min(2, duration * 0.6)], [from, to], { easing: 'out' });
  const n = v.toLocaleString('pt-BR', { minimumFractionDigits: decimals, maximumFractionDigits: decimals });
  return (
    <div className="absolute flex flex-col items-center" style={{ left: `${x * 100}%`, top: `${y * 100}%`, transform: 'translate(-50%, -50%)', opacity: fade(local, duration, 0.3, 0.4) }}>
      <div className="text-[200px] leading-none font-black tabular-nums drop-shadow-2xl" style={{ color }}>{prefix}{n}{suffix}</div>
      {label && <div className="text-5xl font-semibold mt-4 px-6 py-2 rounded-xl text-slate-950" style={{ background: accent }}>{label}</div>}
    </div>
  );
};
