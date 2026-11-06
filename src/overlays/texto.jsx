// Texto livre em qualquer posição, com animação de entrada.
// props: text, x, y (0..1 da tela, centro do texto), size (px no palco de 1920), color, weight,
//   animation ("fade" | "slide" | "pop" | "typewriter" | "none"), className (classes Tailwind extras)
import { fade, spring, typewriter, interpolate } from '3di';

export default ({ text = 'Texto', x = 0.5, y = 0.5, size = 96, color = '#ffffff', weight = 800, animation = 'fade', className = '', local, duration }) => {
  const o = fade(local, duration, animation === 'none' ? 0 : 0.35, 0.4);
  let shown = text, transform = '';
  if (animation === 'slide') transform = `translateY(${spring(local, { from: 80, to: 0, damping: 15 })}px)`;
  if (animation === 'pop') transform = `scale(${spring(local, { from: 0.4, to: 1, damping: 9, stiffness: 180 })})`;
  if (animation === 'typewriter') shown = typewriter(text, interpolate(local, [0, Math.max(0.5, String(text).length / 18)], [0, 1]));
  return (
    <div className="absolute" style={{ left: `${x * 100}%`, top: `${y * 100}%`, transform: 'translate(-50%, -50%)' }}>
      <div className={`whitespace-pre-wrap text-center drop-shadow-2xl ${className}`}
           style={{ fontSize: size, color, fontWeight: weight, opacity: o, transform }}>{shown}</div>
    </div>
  );
};
