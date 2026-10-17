# Deformar e modificar

| método | |
|---|---|
| `.round(r)` | arredonda (e engorda) em r |
| `.shell(espessura)` | deixa oca (aparece quando recortada) |
| `.twist(graus)` | torce em volta do eixo vertical |
| `.taper(top=0.5, bottom=1, axis="y")` | afunila ao longo do eixo |
| `.bend(angle, axis="y", toward=None, pivot=None)` | curva: a ponta inclina `angle` graus para + de `toward` |
| `.shear(x=0, z=0)` | inclina como um baralho (metros por metro de altura) |
| `.elongate(x=0, y=0, z=0)` | estica no meio sem deformar (esfera vira cápsula) |
| `.displace(amount=0.05, size=0.3)` | ruído na superfície (rochas, terreno) |

Exigem forma finita (exceto round/shell/displace). A ordem importa: deforme antes de girar e apoiar.
Caixas envolventes de formas deformadas são aproximadas: meça contatos pela superfície real.
`bend.pivot` é uma coordenada no eixo de curvatura (não um ponto 3D como em `rotate`).
Deformações e ruído são caros no shader e vão para a malha por amostragem no GLB.
