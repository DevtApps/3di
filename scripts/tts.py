#!/usr/bin/env python3
"""Gera as falas do roteiro com o Qwen3-TTS (um WAV por fala).

Uso: python scripts/tts.py pedidos.json
pedidos.json: [{"text": "...", "language": "Portuguese", "out": "caminho.wav",
                 "speaker": "Ryan", "instruct": "fala animada" | null}            voz pronta
                 ou {"text", "language", "out", "ref_audio": "voz.wav", "ref_text": "..."}]  voz clonada
Imprime uma linha JSON por fala: {"out": ..., "seconds": ...}.

Vozes prontas usam THREEDI_TTS_MODEL (padrão Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice); vozes clonadas usam
THREEDI_TTS_CLONE_MODEL (padrão Qwen/Qwen3-TTS-12Hz-1.7B-Base). Os dois modelos são carregados um de cada
vez, para caberem numa GPU de 8 GB. THREEDI_TTS_DEVICE=cpu força a CPU. Os pesos são baixados do Hugging
Face na primeira vez.
"""
import gc
import json
import os
import sys

import soundfile as sf
import torch
from qwen_tts import Qwen3TTSModel

MODEL = os.environ.get("THREEDI_TTS_MODEL", "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice")
CLONE_MODEL = os.environ.get("THREEDI_TTS_CLONE_MODEL", "Qwen/Qwen3-TTS-12Hz-1.7B-Base")


def load(name):
    cuda = torch.cuda.is_available() and os.environ.get("THREEDI_TTS_DEVICE", "auto") != "cpu"
    return Qwen3TTSModel.from_pretrained(
        name,
        device_map="cuda:0" if cuda else "cpu",
        dtype=torch.bfloat16 if cuda else torch.float32,
        attn_implementation="sdpa",
    )


def free(model):
    del model
    gc.collect()
    if torch.cuda.is_available():
        torch.cuda.empty_cache()


def save(job, wav, sr):
    os.makedirs(os.path.dirname(os.path.abspath(job["out"])), exist_ok=True)
    sf.write(job["out"], wav, sr)
    print(json.dumps({"out": job["out"], "seconds": len(wav) / sr}), flush=True)


def language_of(model, job):
    languages = {l.lower(): l for l in model.get_supported_languages()}
    return languages.get(str(job.get("language", "Auto")).lower(), "Auto")


def custom_voices(jobs):
    model = load(MODEL)
    print(json.dumps({"loaded": MODEL}), flush=True)
    speakers = {s.lower(): s for s in model.get_supported_speakers()}
    for job in jobs:
        speaker = speakers.get(str(job.get("speaker", "Ryan")).lower())
        if speaker is None:
            raise SystemExit(f"voz desconhecida '{job.get('speaker')}'; use {', '.join(speakers.values())} ou uma voz clonada")
        kwargs = {"text": job["text"], "language": language_of(model, job), "speaker": speaker}
        if job.get("instruct"):
            kwargs["instruct"] = job["instruct"]
        wavs, sr = model.generate_custom_voice(**kwargs)
        save(job, wavs[0], sr)
    free(model)


def cloned_voices(jobs):
    model = load(CLONE_MODEL)
    print(json.dumps({"loaded": CLONE_MODEL}), flush=True)
    prompts = {}
    for job in jobs:
        ref, ref_text = job["ref_audio"], (job.get("ref_text") or "").strip()
        key = (ref, ref_text)
        # a análise do áudio de referência é feita uma vez por voz
        if key not in prompts:
            prompts[key] = model.create_voice_clone_prompt(ref_audio=ref, ref_text=ref_text or None, x_vector_only_mode=not ref_text)
        wavs, sr = model.generate_voice_clone(text=job["text"], language=language_of(model, job), voice_clone_prompt=prompts[key])
        save(job, wavs[0], sr)
    free(model)


def main():
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    with open(sys.argv[1], encoding="utf-8") as f:
        jobs = json.load(f)
    custom = [j for j in jobs if not j.get("ref_audio")]
    clone = [j for j in jobs if j.get("ref_audio")]
    if custom:
        custom_voices(custom)
    if clone:
        cloned_voices(clone)


if __name__ == "__main__":
    main()
