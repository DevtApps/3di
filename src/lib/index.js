// Registro dos geradores da linguagem (grass, plant, tree, person, vehicle...).
// Cada módulo exporta `builtins(ctx)` e devolve funções nativas; ctx.rng() é o aleatório da
// cena (controlado por seed()), ctx.makeRng(n) cria um aleatório independente para `seed=` próprio.
import { builtins as grass } from './grass.js';
import { builtins as plants } from './plants.js';
import { builtins as trees } from './trees.js';
import { builtins as people } from './people.js';
import { builtins as vehicles } from './vehicles.js';

export function libBuiltins(ctx) {
  return { ...grass(ctx), ...plants(ctx), ...trees(ctx), ...people(ctx), ...vehicles(ctx) };
}
