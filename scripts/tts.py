#!/usr/bin/env python3
"""Gera as falas do roteiro com o Qwen3-TTS (um WAV por fala).

Uso: .venv-tts/bin/python scripts/tts.py pedidos.json
pedidos.json: [{"text": "...", "speaker": "Ryan", "language": "Portuguese",
                "instruct": "fala animada" | null, "out": "caminho.wav"}, ...]
Carrega o modelo uma vez e imprime uma linha JSON por fala: {"out": ..., "seconds": ...}.
Modelo: THREEDI_TTS_MODEL (padrão Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice; o 0.6B gasta menos
memória mas não segue `instruct`). Baixa os pesos do Hugging Face na primeira vez.
"""
import json
import os
import sys

import soundfile as sf
import torch
from qwen_tts import Qwen3TTSModel

MODEL = os.environ.get("THREEDI_TTS_MODEL", "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice")


def main():
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    with open(sys.argv[1], encoding="utf-8") as f:
        jobs = json.load(f)
    if not jobs:
        return
    device = os.environ.get("THREEDI_TTS_DEVICE", "auto")
    cuda = torch.cuda.is_available() and device != "cpu"
    model = Qwen3TTSModel.from_pretrained(
        MODEL,
        device_map="cuda:0" if cuda else "cpu",
        dtype=torch.bfloat16 if cuda else torch.float32,
        attn_implementation="sdpa",
    )
    speakers = {s.lower(): s for s in model.get_supported_speakers()}
    languages = {l.lower(): l for l in model.get_supported_languages()}
    for job in jobs:
        speaker = speakers.get(str(job.get("speaker", "Ryan")).lower())
        if speaker is None:
            raise SystemExit(f"voz desconhecida '{job.get('speaker')}'; use {', '.join(speakers.values())}")
        language = languages.get(str(job.get("language", "Auto")).lower(), "Auto")
        kwargs = {"text": job["text"], "language": language, "speaker": speaker}
        if job.get("instruct"):
            kwargs["instruct"] = job["instruct"]
        wavs, sr = model.generate_custom_voice(**kwargs)
        os.makedirs(os.path.dirname(os.path.abspath(job["out"])), exist_ok=True)
        sf.write(job["out"], wavs[0], sr)
        print(json.dumps({"out": job["out"], "seconds": len(wavs[0]) / sr}), flush=True)


if __name__ == "__main__":
    main()
