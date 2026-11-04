---
title: "Day 6: producing the first episode"
date: 2026-11-05T00:10:00+01:00
description: "The Bell went from a written script to a published video in one sitting: 14 Higgsfield shots, a cloned voice, a sync problem caught by actually measuring instead of guessing, and an ffmpeg pipeline that replaced a video editor."
weight: 13
outcome: "Shipped: Episode 1 produced end-to-end and published to YouTube, embedded on its own page"
tldr:
  - "Generated all 14 shots plus a brand intro in Higgsfield, in order, checking each one against the script before moving on — then ran out of credits right as the intro/outro cards were being built."
  - "Wrote narration in a cloned voice (ElevenLabs) instead of a synthetic one, after checking what was actually free and already installed first (Windows' built-in voices are real but dated)."
  - "Caught a real design mistake by measuring, not guessing: VO lines written for '~5 second shots' ran up to 16.7 seconds once actually spoken aloud — some lines got rewritten shorter, the rest got a freeze-frame extension instead of silently clipping the audio."
  - "Assembled the whole episode with a Python-driven ffmpeg pipeline — no video editor — including burned-in subtitles generated from a timing file built from the real, measured durations."
  - "Found that the project's own auto-archived video files were out of order relative to Higgsfield's actual generation order; caught it by extracting and looking at real frames before trusting any filename."
---

## From script to shots

[Yesterday's script](2026-11-04-day-05b-the-bell-script.md) was 14 Higgsfield prompts and nothing rendered yet. Today was rendering them — one at a time, in order, the same discipline the script called for: generate a shot, open it, check it against the prompt, only then move on. All 14 came out matching what was asked for, including the two reusable Character elements holding the monk's face and robe consistent across completely separate generations.

The intro card (`OpenLucid` wordmark, generated the obvious way: just describe it in a prompt) came out fine too — until it got pointed out that this is backwards. The project already has a real logo file, `branding/logo-mark-512.png`, a hand-made blue crescent moon with a gold EEG-wave mark. Describing a *fake* wordmark in English and hoping Higgsfield's model draws something close is never going to beat handing it the actual file as a reference image. The outro got built properly, logo uploaded as a reference — and then Higgsfield ran out of credits before it could finish rendering. The intro, already generated the wrong way, is still sitting in the published video right now. That's flagged openly on the episode page rather than quietly left in.

## The VO didn't fit the shots, and the only way to know was to measure

The script's narration was written to *sound* roughly five seconds per line — nobody actually timed it, because there was nothing to time yet. Once the lines were recorded for real (see below), `ffprobe` gave real numbers, and they were not close:

| Shot | Video | Spoken VO |
|---|---|---|
| 2 | 5s | **16.7s** |
| 9 | 5s | 12.4s |
| 1 | 5s | 10.3s |
| 12 | 5s | 9.7s |

Thirteen lines of narration added up to about 108 seconds against 70 seconds of video (14 shots × 5s). That's not a rounding error, that's a third of the episode's audio with nowhere to play.

Two fixes, used together on purpose rather than picking one: the worst-offending lines (six of them) got rewritten shorter by hand — Shot 2 lost "one of the Six Yogas" and "Its first instruction is simple to say and hard to do" but kept the historically load-bearing parts (*milam*, Nāropa, "a thousand years ago") intact, because that's the one line in the episode actually carrying sourced claims. The rest of the gap, on every shot, got closed by freezing each clip's last frame for the difference instead — a standard documentary-editing move, not a workaround. Re-measuring after the rewrite brought the total down from 108s to about 85s; the remaining gaps are small enough that freeze-frame padding is unnoticeable rather than a visible crutch.

## Narrating in an actual voice

The plan going in was generic text-to-speech, and before reaching for a paid tool it was worth checking what already existed for free: Windows ships two tiers of built-in voices (older SAPI "Desktop" voices and slightly newer "OneCore" ones), both installed already, both still recognizably synthetic. Windows 11's newer neural "Natural" voices exist too but aren't installed by default and need a one-time download.

None of that mattered once a better option was already paid for and sitting unused: ElevenLabs credits that needed spending this month anyway, and a voice clone made from an actual recording. Thirteen VO lines were generated and downloaded one at a time, in a cloned voice named "Davor English" — real narration, not a synthetic read.

## Building the episode without an editor

No CapCut, no Premiere — the whole episode was assembled with `ffmpeg`, driven by a Python script instead of typed by hand, because the per-shot math (how much to freeze, how loud to duck the ambient track, where every subtitle starts and ends) is exactly the kind of thing that's easy to get wrong typing out fifteen separate commands and trivial to get right once it's a loop:

1. For each shot, freeze the last frame by exactly enough to cover the gap between video length and VO length (`tpad`).
2. Mix the clip's own ambient sound (wind, bells, candle crackle — whatever Higgsfield generated) underneath the narration at 22% volume, so the scene still breathes without competing with the voice.
3. Build one subtitle file for the whole episode from the real, measured timings — not estimated ones — and burn it into the final video.
4. Concatenate all fifteen segments (intro + 14 shots) into one file.

It ran clean on the first full pass: a 103-second MP4, subtitles readable, the freeze-frame extensions invisible unless you're looking for them.

## A filename lied, and the fix was to actually look

The project has an auto-archiving folder (`OpenLucid.creative/archive/`) that syncs generated clips out of Higgsfield automatically, named by download timestamp. It seemed like the obvious source for the 14 shot files — until checking it against what Higgsfield's own UI reported as each shot's *creation* time showed the archive's 10th file by name was actually Shot 12's content, not Shot 10's. Trusting the filename order would have silently built the episode with scenes out of sequence.

The fix was mechanical but non-negotiable: extract an actual frame from each archived file with `ffmpeg -ss ... -frames:v 1` and look at it before using it anywhere. Given that one mismatch, every shot ended up re-downloaded individually and matched by hand against its prompt and "Created" timestamp directly in Higgsfield, rather than trusting any automated sync.

## Where things stand

- `promotion/video-scripts/video/the-bell/` — all 14 source clips plus the intro, and the assembled `the-bell-episode1-draft.mp4`, kept locally only (the folder is `.gitignore`d on purpose: 156MB of raw clips has no reason to live in git history when the published episode is served from YouTube instead).
- `promotion/video-scripts/audio/the-bell/` — 13 VO files in the cloned voice, small enough to commit, kept as source material.
- Episode 1 is [published to YouTube](https://youtu.be/6bN5SzqJXn4) and embedded directly on [its own page](/videos/are-you-dreaming-01-the-bell/) and the homepage, with the full shot-by-shot prompt script left visible below the video on purpose — anyone learning AI video prompting can read the exact prompt next to the few seconds it produced.

Not done: the intro card still carries the placeholder AI-hallucinated wordmark instead of the real logo; the outro with the real logo was never finished (credits ran out mid-render); and this episode is a ~2-minute first cut against the series' 6–10 minute target, so more coverage shots are still ahead of it before it's "final" rather than "produced."
