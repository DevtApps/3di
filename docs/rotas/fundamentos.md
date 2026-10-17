# Fundamentos

- **Unidades e eixos:** metros; y para cima; +z é a frente (a câmera "Frente" olha de +z).
- **Formas nascem centradas na origem** e são **imutáveis**: todo método devolve uma forma nova.
  Guarde o retorno: `mesa = mesa.color("wood")`.
- **Termine com `show(...)`** com as formas da cena (pode chamar várias vezes).
- **Ângulos em graus.** Cores: nome (`"red"`, `"wood"`, `"vermelho"`), `"#rrggbb"` ou `(r, g, b)`.

## Python suportado

`def` (com padrões e `*args`), `return`, `if/elif/else`, `for`, `while`, `break`, `continue`,
listas e compreensões, tuplas, dicts, `lambda`, f-strings, `a if c else b`, desempacotamento com `*`.
Funções: `range len enumerate zip min max sum abs round sqrt sin cos tan asin acos atan atan2 exp
log hypot sign step radians degrees floor ceil lerp clamp smoothstep fract osc linspace print
random uniform randint choice seed mix hsv vary`; constantes `pi`, `tau`.
**Não há** `import`, classes, exceções, `assert` nem arquivos. `print` sai nos logs do `check_script`.

## Posicionar

| método | o que faz |
|---|---|
| `.at(x, y, z)` / `.move(...)` | **desloca** (soma ao lugar atual) |
| `.place(x=0, y=0, z=0)` | coloca o **centro da base** no ponto (absoluto) |
| `.ground()` | apoia no chão (y = 0) |
| `.on(alvo, x=None, z=None, gap=0)` | apoia em cima do alvo, centrada nele; x/z relativos ao centro do alvo |
| `.under(alvo, ...)` | embaixo do alvo |
| `.beside(alvo, side="right", gap=0)` | encosta ao lado (right, left, front, back), bases alinhadas |
| `.rotate(x=0, y=0, z=0, pivot=None)` | gira em volta do próprio centro (ou do `pivot`) |
| `.scale(s, pivot=None)` | número ou `(sx, sy, sz)` |

Propriedades para medir e alinhar: `top bottom left right front back width height depth size center x y z`.

Regras que evitam erros:
- Modele cada conjunto em coordenadas locais (centrado na origem) e mova o grupo pronto uma vez.
- Gire e escale **antes** de apoiar: a rotação muda a caixa envolvente.
- `mirror("x")` espelha no plano x = 0 global: modele o par em torno da origem antes de mover.
- Derive medidas de poucas variáveis (`W`, `H`, `espessura`) em vez de repetir números.
- Dê `.name("peca")` às partes que precisa medir: aparecem em `check_script`, `list_parts` e no GLB.

## Cena

`camera(pos, look=None, fov=45)`, `sun(x, y, z, color=None)`, `sky(cor)`, `fog(density)`,
`light(rim=0.6, fill=0.4, ao=1, rim_color=None)` (rota `materiais`), `seed(n)` (aleatório determinístico).
