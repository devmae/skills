# Game Audio Taxonomy Reference

This skill classifies **all game audio** into three top-level domains, then into
categories. SFX category IDs follow the **Universal Category System (UCS)** — the
free industry standard read by Soundly, Soundminer, BaseHead, etc. (official
spreadsheet: <https://universalcategorysystem.com>). MUSIC and VOICE IDs are a
game-audio convention, since UCS is SFX-centric — adjust them to your studio's
standard if you have one.

The taxonomy lives in the `TAXONOMY` list at the top of
`scripts/organize_audio.py` and is the single source of truth.

## MUSIC (BGM)

| Folder | CatID | Matches filenames containing… | Use |
|--------|-------|-------------------------------|-----|
| `MUSIC/THEME`   | `MUSCThm` | theme, bgm, soundtrack, ost, maintheme, music, title, main | Main/level theme, title music |
| `MUSIC/LOOP`    | `MUSCLop` | loop, bgmloop, underscore, background | Seamless background loops |
| `MUSIC/STINGER` | `MUSCStg` | stinger, sting, accent | Short musical accents |
| `MUSIC/JINGLE`  | `MUSCJgl` | jingle, fanfare, levelup, victory, gameover, logo, intro, outro | Win/level-up fanfares, logo |

## VOICE

| Folder | CatID | Matches filenames containing… | Use |
|--------|-------|-------------------------------|-----|
| `VOICE/DIALOGUE`  | `VOXDlg` | dialogue, dialog, vo, speech, voice, conversation, talk, line | Character lines |
| `VOICE/NARRATION` | `VOXNar` | narration, narrator, voiceover, narrate | Narrator / VO |
| `VOICE/EFFORT`    | `VOXEff` | grunt, effort, breath, exhale, pain, hurt, groan, death | Combat efforts, breaths |
| `VOICE/CALLOUT`   | `VOXCal` | shout, yell, callout, battlecry, scream, cheer, taunt, cry | Battle cries, crowd, taunts |

## SFX

| Folder | CatID | Matches filenames containing… | Use |
|--------|-------|-------------------------------|-----|
| `SFX/USER_INTERFACE` | `UI`   | ui, click, stab, button, select, tap, confirm, hover, toggle, menu, beep, cursor | Button click, select, confirm |
| `SFX/IMPACTS`        | `IMPT` | impact, thud, slam, thump, punch, smash, hit, bang | Heavy landing, defeat |
| `SFX/MAGIC`          | `MAGC` | magic, spell, elemental, arcane, enchant, mana, wizard, sparkle | Skill cast, power-up |
| `SFX/DESIGNED`       | `DSGN` | riser, uplifter, braam, build, swell, rise, sweep, reveal | Reward reveal, build-up |
| `SFX/WHOOSHES`       | `WHSH` | whoosh, woosh, swoosh, swish, swoop, descent, transition, passby | Screen/menu transition |
| `SFX/BIRDS`          | `BIRD` | bird, cardinal, chirp, songbird, tweet, robin, sparrow, crow | Nature ambience |
| `SFX/AMBIENCE`       | `AMB`  | ambience, ambient, roomtone, nature, forest, wind, rain | Background loops |

## How matching works

1. The filename is split into lowercase tokens.
2. For every taxonomy entry, the weights of all matched keywords are summed.
3. The highest-scoring **(domain, category)** wins; **confidence = top / (top + second)**.
   Ambiguous names resolve sensibly — e.g. `menu-music` → `menu`(UI 1) vs
   `music`(THEME 2) → **MUSIC/THEME**; `riser-hit` → `riser`(3) vs `hit`(1) →
   **SFX/DESIGNED**.
4. Confidence below `THRESHOLD` (default 0.6), or no match, → `_REVIEW/`.

## Extending for a real (thousands-of-files) library

Add categories you actually have. Each entry just needs `domain`, `category`,
`catid`, `keywords` (weighted), and `clap` prompts. Common additions:

```python
# SFX
{"domain":"SFX","category":"WEAPONS","catid":"WEAP","keywords":{"weapon":3,"gun":3,"sword":3,"blade":2,"reload":2},"clap":["a gunshot","a sword swing"]},
{"domain":"SFX","category":"FOOTSTEPS","catid":"FOOT","keywords":{"footstep":3,"foot":2,"step":2,"walk":1},"clap":["a single footstep"]},
{"domain":"SFX","category":"COINS","catid":"COIN","keywords":{"coin":3,"money":3,"cash":2,"jackpot":3,"reward":2,"win":2},"clap":["coins falling","a jackpot win"]},
{"domain":"SFX","category":"EXPLOSIONS","catid":"EXPL","keywords":{"explosion":3,"explode":3,"blast":2,"boom":2},"clap":["an explosion"]},
# MUSIC
{"domain":"MUSIC","category":"COMBAT","catid":"MUSCCbt","keywords":{"combat":3,"battle":3,"boss":2,"tension":2},"clap":["intense battle music"]},
# VOICE
{"domain":"VOICE","category":"ANNOUNCER","catid":"VOXAnc","keywords":{"announcer":3,"announce":2,"commentator":3},"clap":["a sports-style announcer"]},
```

Tips:
- Keep SFX CatIDs aligned with the official UCS list for tool interoperability.
- More specific terms carry higher weights (e.g. `jackpot` 3, `win` 2).
- Re-run on the same source after editing — it is idempotent, so only newly-added
  files are processed; existing entries stay in place.
