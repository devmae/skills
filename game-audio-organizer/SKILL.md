---
name: game-audio-organizer
description: >-
  Classify and organize ALL game audio — music/BGM, voice/dialogue, and sound
  effects (SFX) — into a domain-first library of category folders. Sorts files
  into MUSIC (themes, loops, stingers, jingles), VOICE (dialogue, narration,
  efforts, callouts), and SFX (UI, impacts, magic, whooshes, ambience, and more),
  renaming each with a UCS-style category ID and writing a manifest CSV plus a
  CREDITS attribution file. Classification runs via a Python CLI that plays back
  and analyzes the actual audio signals using a CLAP model, so results are based
  solely on the sound content. Low-confidence files (confidence < 0.6) are routed
  to SFX/UNCATEGORIZED. Use when the user wants to sort, categorize, tag, or
  organize a folder of game audio / .mp3/.wav/.aiff/.flac/.ogg files. Also
  triggers on Korean requests such as "게임 사운드 정리", "효과음 분류", "배경음악
  정리", "보이스 정리", "사운드 폴더별로 정리".
---

# Game Audio Organizer

Organizes a folder of game audio into a **domain-first** library: top-level
`MUSIC/`, `VOICE/`, and `SFX/` folders, each split into categories. Files are
renamed with a UCS-style category-ID prefix; a manifest and credits file are
written. All decision logic lives in the bundled script and the CLAP audio layer.
It analyzes and listens to the actual audio waves to decide the domain and category,
completely ignoring the file names.

## When to use
- The user has many game audio files (.mp3 / .wav / .aiff / .flac / .ogg / .m4a)
  to sort — music, voice, and/or sound effects.
- The user wants a searchable, categorized audio library with attribution tracking.
- Requests like: "organize my game sounds", "sort SFX/music/voice by type",
  "게임 사운드 정리해줘", "배경음악이랑 효과음 분류해줘".

## How to run

The engine is `scripts/organize_audio.py` (path is relative to this skill's
directory). This execution relies on a virtual environment containing PyTorch,
torchvision, and laion-clap, alongside a working `ffmpeg` installation.

1. **Always dry-run first.** Prints the classification plan; touches no files:
   ```
   .venv/Scripts/python scripts/organize_audio.py --src "<folder with audio files>"
   ```
2. Show the printed plan to the user (domain/category, confidence, new name) and confirm.
3. **Apply.** Default = *copy* into `<src>/Audio_Library/` (originals left untouched):
   ```
   .venv/Scripts/python scripts/organize_audio.py --src "<folder>" --apply
   ```
   - Add `--move` to move instead of copy.
   - Add `--dst "<path>"` to choose the output location.

## Output (domain-first)
```
Audio_Library/
├── MUSIC/   THEME/  LOOP/  STINGER/  JINGLE/
├── VOICE/   DIALOGUE/  NARRATION/  EFFORT/  CALLOUT/
├── SFX/     USER_INTERFACE/  IMPACTS/  MAGIC/  DESIGNED/  WHOOSHES/  BIRDS/  AMBIENCE/  UNCATEGORIZED/
├── _REVIEW/        ← duplicate files for a human to check
├── _manifest.csv   ← original↔new path, domain, category, method, confidence, sha1, source
└── _CREDITS.txt    ← source/author attribution (verify each license before use)
```

## Key behaviors
- **Audio Signal Classification (CLAP):** Zero-shot Contrastive Language-Audio Pretraining model reads, loads, and processes the actual waveforms of the audio files and maps them to text prompts.
- **Idempotent / incremental:** re-running skips files already in `_manifest.csv`
  (matched by content hash). Drop new files in and re-run — only new ones are
  processed. Safe for ongoing ingestion of thousands of files.
- **Confidence threshold** (default `0.6`): anything below it is routed to `SFX/UNCATEGORIZED/` instead of `_REVIEW/`.
- **Duplicate detection:** identical files (by SHA-1) are routed to `_REVIEW/`.
- **Non-destructive by default:** copies unless `--move` is given.

## Extending the taxonomy
Edit the `TAXONOMY` list at the top of `scripts/organize_audio.py` — the single
source of truth. Each entry has a `domain` (MUSIC/VOICE/SFX), a `category` folder,
a `catid`, and `clap` prompts. For the full domain/category map and how to align with
official UCS, see [references/game-audio-taxonomy.md](references/game-audio-taxonomy.md).
