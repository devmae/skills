#!/usr/bin/env python3
"""
Game Audio Organizer - classify ALL game audio into domain + category folders.

Three top-level domains: MUSIC (BGM/themes/loops/stingers), VOICE (dialogue,
narration, efforts, callouts), and SFX (UI, impacts, magic, whooshes, ...).

Pipeline:
  [1] Content-hash dedup / skip-already-processed    (idempotent, incremental-safe)
  [2] Filename keyword matching -> domain/category    (free, instant; default layer)
  [3] Optional CLAP audio layer for filename misses   (see references/phase2-clap.md)
  [4] Below confidence threshold -> _REVIEW/          (human check)
  [5] _manifest.csv (mapping + source) and _CREDITS.txt (attribution) generated

SFX category IDs follow the UCS (Universal Category System) -
https://universalcategorysystem.com . MUSIC/VOICE IDs are a game-audio convention
(UCS is SFX-centric); see references/game-audio-taxonomy.md.

The default layer uses only the Python standard library (no install needed) and
produces identical results regardless of which model/agent invokes it.

Usage:
  python3 organize_audio.py --src <folder>                 # dry-run (plan only)
  python3 organize_audio.py --src <folder> --apply         # execute (copy)
  python3 organize_audio.py --src <folder> --apply --move  # execute (move)
  python3 organize_audio.py --src <folder> --dst <out>     # custom output dir
"""

import argparse, csv, hashlib, re, shutil
from pathlib import Path

# -----------------------------------------------------------------------------
# TAXONOMY - single source of truth. Each entry: domain + category + UCS-style
# catid + weighted keywords + CLAP prompts (Phase 2 only). Add entries freely.
# -----------------------------------------------------------------------------
TAXONOMY = [
    # ---------------- SFX ----------------
    {"domain": "SFX", "category": "USER_INTERFACE", "catid": "UI",
     "keywords": {"ui": 3, "click": 3, "stab": 3, "button": 2, "select": 2, "tap": 2,
                  "confirm": 2, "hover": 2, "toggle": 2, "menu": 1, "beep": 1, "cursor": 1},
     "clap": ["a UI click sound", "a button press", "a menu select beep"]},
    {"domain": "SFX", "category": "IMPACTS", "catid": "IMPT",
     "keywords": {"impact": 3, "thud": 3, "slam": 2, "thump": 2, "punch": 2,
                  "smash": 2, "hit": 1, "bang": 1},
     "clap": ["a heavy impact", "a low thud", "a body fall thump"]},
    {"domain": "SFX", "category": "MAGIC", "catid": "MAGC",
     "keywords": {"magic": 3, "spell": 3, "elemental": 3, "arcane": 2, "enchant": 2,
                  "mana": 2, "wizard": 2, "sparkle": 1},
     "clap": ["a magic spell cast", "a magical shimmer", "an arcane impact"]},
    {"domain": "SFX", "category": "DESIGNED", "catid": "DSGN",
     "keywords": {"riser": 3, "uplifter": 3, "braam": 3, "build": 2, "swell": 2,
                  "rise": 2, "sweep": 1, "reveal": 1},
     "clap": ["a riser build-up", "an uplifter sweep", "a trailer braam hit"]},
    {"domain": "SFX", "category": "WHOOSHES", "catid": "WHSH",
     "keywords": {"whoosh": 3, "woosh": 3, "swoosh": 3, "swish": 3, "swoop": 2,
                  "descent": 2, "transition": 2, "passby": 2},
     "clap": ["a whoosh transition", "a fast swoosh", "a cinematic descent whoosh"]},
    {"domain": "SFX", "category": "BIRDS", "catid": "BIRD",
     "keywords": {"bird": 3, "cardinal": 3, "chirp": 3, "songbird": 3, "tweet": 2,
                  "robin": 2, "sparrow": 2, "crow": 2},
     "clap": ["a bird chirping", "songbird calls", "birdsong ambience"]},
    {"domain": "SFX", "category": "AMBIENCE", "catid": "AMB",
     "keywords": {"ambience": 3, "ambient": 3, "roomtone": 2, "nature": 1,
                  "forest": 1, "wind": 1, "rain": 1},
     "clap": ["a background ambience", "room tone", "nature ambience"]},

    # ---------------- MUSIC (BGM) ----------------
    {"domain": "MUSIC", "category": "THEME", "catid": "MUSCThm",
     "keywords": {"theme": 3, "bgm": 3, "soundtrack": 3, "ost": 3, "maintheme": 3,
                  "music": 2, "title": 2, "main": 1},
     "clap": ["background music theme", "a game soundtrack", "a main title theme"]},
    {"domain": "MUSIC", "category": "LOOP", "catid": "MUSCLop",
     "keywords": {"loop": 3, "bgmloop": 3, "underscore": 2, "background": 1},
     "clap": ["a seamless music loop", "a background music loop"]},
    {"domain": "MUSIC", "category": "STINGER", "catid": "MUSCStg",
     "keywords": {"stinger": 3, "sting": 3, "accent": 2},
     "clap": ["a short musical stinger", "a musical accent"]},
    {"domain": "MUSIC", "category": "JINGLE", "catid": "MUSCJgl",
     "keywords": {"jingle": 3, "fanfare": 3, "levelup": 2, "victory": 2,
                  "gameover": 2, "logo": 2, "intro": 2, "outro": 2},
     "clap": ["a short victory fanfare", "a level-up jingle", "a logo sound"]},

    # ---------------- VOICE ----------------
    {"domain": "VOICE", "category": "DIALOGUE", "catid": "VOXDlg",
     "keywords": {"dialogue": 3, "dialog": 3, "vo": 3, "speech": 2, "voice": 2,
                  "conversation": 2, "talk": 1, "line": 1},
     "clap": ["spoken character dialogue", "a line of speech"]},
    {"domain": "VOICE", "category": "NARRATION", "catid": "VOXNar",
     "keywords": {"narration": 3, "narrator": 3, "voiceover": 3, "narrate": 2},
     "clap": ["a narrator speaking", "documentary-style narration"]},
    {"domain": "VOICE", "category": "EFFORT", "catid": "VOXEff",
     "keywords": {"grunt": 3, "effort": 3, "breath": 2, "exhale": 2, "pain": 2,
                  "hurt": 2, "groan": 2, "death": 1},
     "clap": ["a character grunt", "a pain effort vocalization", "a breath"]},
    {"domain": "VOICE", "category": "CALLOUT", "catid": "VOXCal",
     "keywords": {"shout": 3, "yell": 3, "callout": 3, "battlecry": 3, "scream": 2,
                  "cheer": 2, "taunt": 2, "cry": 1},
     "clap": ["a battle cry shout", "a crowd cheer", "a character yelling"]},
]
THRESHOLD = 0.6
AUDIO_EXTS = {".mp3", ".wav", ".aiff", ".aif", ".flac", ".ogg", ".m4a"}
NOISE = {"sfx", "sound", "effect", "fx", "audio", "the", "a", "of"}


def tokens(name):
    return [t for t in re.split(r"[^a-z0-9]+", Path(name).stem.lower()) if t]


def parse_source(name):
    """Best-effort: creator = first token, source_id = trailing number,
    desc = the middle (noise words, lone chars/digits, and the creator removed)."""
    toks = re.split(r"[-_]", Path(name).stem)
    source_id = ""
    if toks and toks[-1].isdigit():
        source_id, toks = toks[-1], toks[:-1]
    creator = toks[0] if toks else "unknown"
    mid = [t for t in toks[1:]
           if t.lower() not in NOISE and not t.isdigit()
           and len(t) > 1 and t.lower() != creator.lower()]
    desc = " ".join(mid) if mid else (toks[1] if len(toks) > 1 else "untitled")
    return creator, source_id, desc


def classify_filename(name):
    """Return (domain, category, catid, confidence)."""
    ts = set(tokens(name))
    scores = {}
    for e in TAXONOMY:
        s = sum(w for kw, w in e["keywords"].items() if kw in ts)
        if s:
            scores[(e["domain"], e["category"])] = (s, e["catid"])
    if not scores:
        return None, None, None, 0.0
    ranked = sorted(scores.items(), key=lambda x: x[1][0], reverse=True)
    (dom, cat), (ts_, catid) = ranked[0]
    second = ranked[1][1][0] if len(ranked) > 1 else 0
    return dom, cat, catid, round(ts_ / (ts_ + second), 2)


def classify_audio(path):
    """Optional Phase-2 layer. Activates only if a `sfx_clap` module is importable
    (scripts/sfx_clap.py - see references/phase2-clap.md). Falls back to no-match,
    so the default layer always works.
    Contract: sfx_clap.classify(path, taxonomy, threshold) -> (domain, category, catid, conf)."""
    try:
        import sfx_clap  # type: ignore
    except Exception:
        return None, None, None, 0.0
    try:
        return sfx_clap.classify(str(path), TAXONOMY, THRESHOLD)
    except Exception:
        return None, None, None, 0.0


def titlecase(s):
    return " ".join(w.capitalize() for w in s.split())


def file_hash(p):
    h = hashlib.sha1()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def load_seen(manifest):
    seen = {}
    if manifest.exists():
        with open(manifest, newline="", encoding="utf-8") as f:
            for r in csv.DictReader(f):
                seen[r["sha1"]] = r["original_name"]
    return seen


def _rel(target, dst):
    try:
        target.relative_to(dst)
        return True
    except ValueError:
        return False


def main():
    ap = argparse.ArgumentParser(description="Game-audio classifier (dry-run by default).")
    ap.add_argument("--src", required=True, help="folder containing audio files")
    ap.add_argument("--dst", default=None, help="output dir (default: <src>/Audio_Library)")
    ap.add_argument("--move", action="store_true", help="move files instead of copying")
    ap.add_argument("--apply", action="store_true", help="actually perform the operations")
    args = ap.parse_args()

    src = Path(args.src).expanduser().resolve()
    dst = Path(args.dst).expanduser().resolve() if args.dst else src / "Audio_Library"
    review = dst / "_REVIEW"
    manifest = dst / "_manifest.csv"
    credits = dst / "_CREDITS.txt"

    if not src.is_dir():
        print(f"  ERROR: --src is not a directory: {src}")
        return

    seen = load_seen(manifest)
    files = sorted(p for p in src.rglob("*")
                   if p.is_file() and p.suffix.lower() in AUDIO_EXTS)

    plan, rows, batch_hashes = [], [], {}
    for p in files:
        h = file_hash(p)
        if h in seen:
            plan.append((p, None, "SKIP (already in library)", "-", 0.0))
            continue
        dup = batch_hashes.get(h)
        batch_hashes.setdefault(h, p.name)

        # Bypass filename-based classification and run CLAP audio content analysis exclusively
        dom, cat, catid, conf = classify_audio(p)
        method = "clap"

        creator, sid, desc = parse_source(p.name)
        if dup:
            tgt_dir, domain, category, label, newname = review, "", "DUPLICATE", "DUPLICATE", p.name
        elif cat and conf >= THRESHOLD:
            tgt_dir = dst / dom / cat
            domain, category, label = dom, cat, f"{dom}/{cat}"
            newname = f"{catid}_{titlecase(desc)}_{titlecase(creator)}_{sid or 'na'}{p.suffix.lower()}"
        else:
            tgt_dir = dst / "SFX" / "UNCATEGORIZED"
            domain, category, label, newname = "SFX", "UNCATEGORIZED", "SFX/UNCATEGORIZED", p.name

        target = tgt_dir / newname
        plan.append((p, target, label, method, conf))
        rows.append({
            "original_name": p.name,
            "new_path": str(target.relative_to(dst)) if _rel(target, dst) else target.name,
            "domain": domain, "category": category, "catid": catid or "",
            "method": method, "confidence": conf, "sha1": h, "duplicate_of": dup or "",
            "creator": creator, "source_id": sid,
        })

    # ---- print plan ----
    mode = ("APPLY " + ("MOVE" if args.move else "COPY")) if args.apply else "DRY-RUN"
    print(f"\n  SRC: {src}\n  DST: {dst}   mode: {mode}")
    print(f"  files found: {len(files)}   to process: {len(rows)}\n")
    print(f"  {'DOMAIN/CATEGORY':<22}{'CONF':<6}{'METHOD':<10}NEW NAME  <- original")
    print("  " + "-" * 98)
    for p, target, label, method, conf in plan:
        nm = target.name if target else "-"
        print(f"  {label:<22}{conf:<6}{method:<10}{nm}\n  {'':>38}<- {p.name}")

    if not args.apply:
        print("\n  (dry-run) add --apply to perform the operations\n")
        return

    # ---- execute ----
    for e in TAXONOMY:
        (dst / e["domain"] / e["category"]).mkdir(parents=True, exist_ok=True)
    review.mkdir(parents=True, exist_ok=True)
    for p, target, label, method, conf in plan:
        if target is None:
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        (shutil.move if args.move else shutil.copy2)(str(p), str(target))

    write_header = not manifest.exists()
    with open(manifest, "a", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["original_name", "new_path", "domain", "category",
                                          "catid", "method", "confidence", "sha1",
                                          "duplicate_of", "creator", "source_id"])
        if write_header:
            w.writeheader()
        w.writerows(rows)

    with open(credits, "a", encoding="utf-8") as f:
        if write_header:
            f.write("GAME AUDIO LIBRARY - SOURCE & ATTRIBUTION\n")
            f.write("Verify each source's license terms before commercial use.\n" + "=" * 70 + "\n\n")
        for r in rows:
            tag = f"{r['domain']}/{r['category']}" if r['domain'] else r['category']
            f.write(f"[{tag}] {Path(r['new_path']).name}\n")
            f.write(f"    source file : {r['original_name']}\n")
            f.write(f"    creator     : {r['creator']}\n")
            f.write(f"    source id   : {r['source_id']}\n\n")

    n_dup = sum(r["category"] == "DUPLICATE" for r in rows)
    n_unc = sum(r["category"] == "UNCATEGORIZED" for r in rows)
    print(f"\n  DONE: classified {len(rows) - n_dup - n_unc} · duplicates {n_dup} · uncategorized {n_unc}")
    print(f"  -> {manifest}\n  -> {credits}\n")


if __name__ == "__main__":
    main()
