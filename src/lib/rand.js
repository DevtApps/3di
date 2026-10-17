// Gerador pseudoaleatório reproduzível (mulberry32): o mesmo seed gera sempre a mesma cena.
export function makeRng(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Utilitários em cima de um rng: u(a, b) uniforme, pick(lista), chance(p)
export function randTools(rng) {
  const u = (a = 0, b = 1) => a + (b - a) * rng();
  return { u, pick: (xs) => xs[Math.floor(rng() * xs.length)], chance: (p) => rng() < p, int: (a, b) => a + Math.floor((b - a + 1) * rng()) };
}

// Aleatório de uma chamada: `seed=` próprio (reprodutível por objeto) ou o da cena (controlado por seed()).
export const rngFor = (ctx, seed) => (seed === null || seed === undefined ? ctx.rng : ctx.makeRng(Math.floor(seed)));
