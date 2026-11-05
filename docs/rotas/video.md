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

```bash
node scripts/video.mjs cena.3di out/video.mp4 [--size 1280x720] [--fps 30] [--from s] [--to s] [--burn] [--no-audio] [--no-subs] [--cpu]
```

- Quadros pelo próprio editor num Chrome headless (GPU), em H.264.
- Falas pelo Qwen3-TTS (modelo 1.7B CustomVoice, GPU com ~6 GB ou CPU lenta), em cache em `out/.tts-cache`:
  só fala nova ou alterada é gerada de novo. Instalação: `python3 -m venv .venv-tts && .venv-tts/bin/pip install qwen-tts soundfile`.
  A primeira execução baixa os pesos do Hugging Face. `THREEDI_TTS_MODEL` troca o modelo (0.6B gasta menos memória, sem `instruct`).
- Legendas: `.srt` ao lado do vídeo e faixa de legenda embutida no MP4; `--burn` grava na imagem.
