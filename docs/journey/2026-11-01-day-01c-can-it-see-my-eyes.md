---
title: "Day 1, part 3: can the headband see my eyes?"
date: 2026-11-01T13:00:00+01:00
description: "A contact score with a clear target, and a guided eye check that tells you whether the forehead sensors can see blinks and left-right eye movements."
weight: 3
---

## Why the eyes come first

OpenLucid stands or falls with the eyes. In REM sleep the eyes move while the body is still, and a lucid dreamer can send a signal from inside a dream by looking **left, right, left, right**. Before anything else, the forehead sensors have to be able to see that.

## A contact score with a target

"Poor · 198 µV" didn't tell anyone what *good* looks like. The contact table now shows a target and a percentage:

- **Target: under 25 µV** of wiggle while you sit still (after the viewing filter).
- **100%** means on target, **0%** means 150 µV or more: the sensor is as good as not touching.
- In between, on a logarithmic scale: 50 µV is about 61%, 100 µV about 23%.
- Green from 80%, orange from 40%, red below. Each sensor gets a bar; on phones the percentage sits next to the dot.

These are rules of thumb for learning, not a medical measurement.

## The eye check

Looking at a live signal and guessing whether that bump was your blink doesn't work: you don't know exactly *when* you blinked. So the app now has a guided **Eye check**:

| Seconds | Prompt |
|---|---|
| 0–3 | Keep your eyes still (this measures the resting wiggle) |
| 3, 5, 7 | Blink |
| 9 | Eyes still |
| 11, 12.5, 14, 15.5 | Look left, right, left, right |
| 17 | Straight ahead |

Because the app knows when it asked, it can judge the recording itself:

- **A blink** should make both forehead sensors (AF7, AF8) swing **the same way**, well above the resting wiggle.
- **Looking left or right** should move them **in opposite directions**: the eyeball is a tiny battery (front positive, back negative), and turning it brings one pole closer to one sensor.
- **Left and right should flip**: if "left" moves AF7 up, "right" should move it down.

The check passes when at least 2 of 3 blinks and 3 of 4 looks are seen, in consistent directions.

## Testing it without a headband

Fake Moose learned to blink and look on command. The tests run the whole check with a Fake Moose that follows the prompts (it must pass) and one that ignores them (it must fail), for several random seeds.

The first version missed one of four eye movements. The cause was the filter: a high-pass at 0.3 Hz made a **held** gaze fade away before it was measured. Lowering it to 0.1 Hz fixed it. **Lesson:** a filter that is right for one signal (brainwaves) can be wrong for another (a step from a held gaze).

## Still to do

- Run the eye check with the real Muse S, wearing it, and tag `checkpoint-01` when it passes.
