# Phase 2 — Optional CLAP Audio Layer

The default layer classifies by **filename keywords**, which is accurate and free
for downloaded/library audio (descriptive names) and runs in any environment.
Phase 2 adds **content-based** classification for files whose names are *not*
descriptive — own recordings, engine exports with hash names, or anything that
lands in `_REVIEW/` as `UNCATEGORIZED`. It works across all three domains
(MUSIC / VOICE / SFX) because each `TAXONOMY` entry carries its own `clap` prompts.

It uses **CLAP** (Contrastive Language-Audio Pretraining): audio and text are
mapped into the same embedding space, so a clip is matched to the closest
natural-language label — zero-shot, no training.

## How it plugs in (no core changes needed)

`organize_audio.py` already calls `classify_audio()`, which **lazily** tries to
`import sfx_clap`. If the module is absent it returns "no match" and only the
filename layer runs. To enable Phase 2, create `scripts/sfx_clap.py` exposing:

```python
def classify(path: str, taxonomy: list, threshold: float) -> tuple:
    """Return (domain, category, catid, confidence).
    Return (None, None, None, conf) to decline (-> stays in _REVIEW)."""
```

Because it is an optional drop-in, the default package stays dependency-free.

## Requirements (heavier — install only where Phase 2 runs)

```bash
pip install laion-clap torch numpy
# ffmpeg must be on PATH for decoding (brew install ffmpeg)
```

> ⚠️ Environment limits: Phase 2 does **not** run on locked-down sandboxes such as
> the Claude API code-execution surface (no network, no runtime pip installs). Use it
> on a local machine, Claude Code, or Codex CLI. On Apple Silicon, PyTorch uses the
> MPS backend for acceleration.

## Reference implementation — `scripts/sfx_clap.py`

```python
import numpy as np, laion_clap

_model = _text_emb = _labels = None

def _ensure(taxonomy):
    global _model, _text_emb, _labels
    if _model is not None:
        return
    _model = laion_clap.CLAP_Module(enable_fusion=False)
    _model.load_ckpt()                       # downloads default checkpoint once
    prompts, labels = [], []
    for e in taxonomy:
        for p in e["clap"]:
            prompts.append(p)
            labels.append((e["domain"], e["category"], e["catid"]))
    _text_emb = _model.get_text_embedding(prompts, use_tensor=False)  # L2-normalized
    _labels = labels

def classify(path, taxonomy, threshold):
    _ensure(taxonomy)
    audio_emb = _model.get_audio_embedding_from_filelist([path], use_tensor=False)
    sims = (audio_emb @ _text_emb.T)[0]      # cosine (embeddings are normalized)
    best = int(np.argmax(sims))
    domain, category, catid = _labels[best]
    conf = round(float((sims[best] + 1) / 2), 2)   # map cosine [-1,1] -> [0,1]
    return (domain, category, catid, conf) if conf >= threshold else (None, None, None, conf)
```

## Performance notes for large libraries
- Filename matching handles most library files instantly; CLAP runs **only** on the
  remainder, so total cost stays low even at thousands of files.
- Text embeddings are computed once per run and reused across all files.
- Music vs voice vs SFX are easy for CLAP; fine-grained music subtypes (theme vs
  loop) are harder — tune `THRESHOLD` and review `_REVIEW/` to calibrate. Anything
  CLAP is unsure about stays in `_REVIEW/` for a human — never silently misfiled.
