# Animação e rig

- `time` (segundos) funciona em transformações (`at`, `rotate`, `scale`), `glow` e fórmulas de `implicit`;
  não em tamanhos de primitivas nem em condições. `osc(...)` oscila (veja `describe_language`).
- O layout semântico (`on`, `beside`, `place`) usa t = 0.
- `set_time(time=, playing=)` congela ou toca o preview; `screenshot(time=)` captura um instante.

## Esqueleto (exporta animado no GLB)

```python
esq = skeleton()
quadril = esq.bone("quadril", head=(0, 1, 0))
braco = esq.bone("braco", head=(0.2, 1.4, 0), parent=quadril)
braco.rotate(z=osc(-30, 30, 2))
show(segment((0.2, 1.4, 0), (0.5, 1.4, 0), 0.05).bind(braco), esq.debug())
```

Modele cada parte na pose de repouso e prenda com `.bind(osso)`. Animação direta nas formas (sem ossos)
exporta parada em t = 0. Veja `boneco.3di` e `animacao.3di`.
