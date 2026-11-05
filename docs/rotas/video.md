# Animação por chaves, roteiro e vídeo

## Chaves: `keys()`

`keys((t0, v0), (t1, v1), ..., ease="smooth", loop=False)` devolve um valor que muda com o tempo,
passando pelas chaves `(tempo em s, valor)`. O valor é número ou tupla (posição, ângulos, escala, cor de glow).
Vale em tudo que aceita `time`: `.at()`, `.rotate()`, `.scale()`, `material(glow=)`, `camera(pos=, look=, fov=)`.

- `ease`: `linear`, `smooth` (padrão: acelera e freia), `in`, `out`, `step` (segura até a próxima chave).
- `loop=True`: repete a cada duração da última chave.
- Antes da primeira chave vale o primeiro valor; depois da última, o último.

```python
timeline(12, fps=30)                       # duração do vídeo e quadros por segundo
cubo = box(0.5).at(keys((0, (0, 0, 0)), (2, (1, 0, 0)), (4, (1, 1, 0))))
cubo = cubo.rotate(y=keys((0, 0), (12, 720), ease="linear"))
camera(pos=keys((0, (0, 1.6, 5)), (6, (3, 2, 3)), (12, (0, 1.6, 5))), look=(0, 0.5, 0), fov=40)
```

O layout (`on`, `beside`, `place`) e as caixas usam o valor em t = 0. Anime a peça já posicionada.

## Roteiro: falas, legendas e vozes

| | |
|---|---|
| `voice(name, speaker="Ryan", language="Portuguese", instruct=None)` | define uma voz do Qwen3-TTS. `speaker`: Vivian, Serena, Uncle_Fu, Dylan, Eric, Ryan, Aiden, Ono_Anna, Sohee; `instruct`: estilo ("tom animado", "sussurrando") |
| `say(text, at=None, dur=None, voice=None, style=None)` | fala: legenda + áudio. Sem `at`, entra depois da fala anterior; `style` soma ao estilo da voz. Devolve o instante em que termina |
| `caption(text, at=None, dur=None)` | só legenda, sem áudio |

`dur` é estimada pelo tamanho do texto (~12 caracteres/s). No vídeo vale a duração real do áudio:
falas sem `at` são reagendadas em sequência; com `at` ficam no lugar (o render avisa se sobrepuserem).
Sem `timeline()`, a duração é o fim do roteiro ou a última chave.

## Preview

A barra de timeline embaixo da vista toca/pausa, arrasta o tempo, mostra as chaves (amarelo) e as falas
(azul) e legendas (cinza). A legenda ativa aparece por cima da vista. Com câmera animada, o botão 🎥
segue a câmera do roteiro; girar a vista solta a câmera. Pelo MCP: `set_time(time=..., playing=False)`
e `screenshot(time=...)` conferem um instante.

## Render de vídeo

**No app:** botão **Vídeo** (Exportar). Escolha nome, tamanho, quadros por segundo, legendas (faixa embutida,
gravadas na imagem ou sem) e se as falas têm voz. Os quadros são desenhados pela própria vista; o vídeo, o `.srt`
e as falas vão para `out/` da pasta do projeto (workspace, pasta da cena aberta ou `~/3DI`).

**Pela linha de comando** (no repositório):

```bash
node scripts/video.mjs cena.3di out/video.mp4 [--size 1280x720] [--fps 30] [--from s] [--to s] [--burn] [--no-audio] [--no-subs] [--cpu]
```

O que o vídeo usa e onde fica:
- **ffmpeg:** vem no pacote do 3DI (no desenvolvimento, o `ffmpeg-static` do npm).
- **Vozes (Qwen3-TTS):** grandes demais para o pacote (PyTorch: alguns GB). O botão **Instalar vozes** cria um
  ambiente Python próprio em `~/.local/share/3di/tts/venv` (precisa do `python3-venv`, recomendado pelo `.deb`).
  Os pesos do modelo (1.7B CustomVoice) são baixados na primeira fala; GPU com ~6 GB ou CPU (lenta).
  `THREEDI_TTS_MODEL` troca o modelo (0.6B gasta menos memória, sem `instruct`).
- **Cache das falas:** `~/.local/share/3di/tts/cache`; só fala nova ou alterada é gerada de novo.
- Legendas: `.srt` ao lado do vídeo e faixa embutida no MP4, ou gravadas na imagem.
