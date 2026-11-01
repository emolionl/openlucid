---
title: "Day 1, part 5: blinks yes, left and right no"
date: 2026-11-01T15:00:00+01:00
description: "The first eye check with good contact. Two wrong assumptions in our own code, and a real finding: a Muse S forehead barely sees sideways eye movements."
weight: 5
---

## The setup

Forehead dampened, both forehead sensors at **100% contact**, the Muse confirmed preset **p21** (firmware 2.0.11). The eye check said: **0 of 3 blinks, 0 of 4 left/right**. This time it saved its recording, so we could look.

## Wrong assumption 1: when to measure "rest"

The check measured the resting wiggle in the first three seconds and got **46 µV**. Later, in the second "eyes still" moment, it was **10–11 µV**. People are still settling in when a test starts. Because every threshold scaled with the rest value, a blink had to exceed 184 µV.

**Fix:** use the quieter of the two "eyes still" moments.

## Wrong assumption 2: which way a blink goes

We assumed a blink moves both forehead sensors in the same direction. On this Muse S, it didn't:

| Blink at | AF7 | AF8 |
|---|---|---|
| 3 s | +303 µV | −465 µV |
| 5 s | +170 µV | −117 µV |
| 7 s | −72 µV | −46 µV |

Which way a sensor swings depends on where the headband measures *against* (its reference). The data was right; our rule wasn't.

**Fix:** a blink counts when both sensors respond clearly, in any direction.

## The real finding: left and right barely show

| Prompt | AF7 | AF8 |
|---|---|---|
| look left (11 s) | +51 µV | +18 µV |
| look right (12.5 s) | +7 µV | +2 µV |
| look left (14 s) | −8 µV | −8 µV |
| look right (15.5 s) | +1 µV | +47 µV |

Next to blinks of hundreds of microvolts, that's practically nothing. With the corrected rules, the same recording scores **3 of 3 blinks, 0 of 4 left/right**. The check still fails, and now it fails for the right reason.

Why? The forehead sensors of the Muse S sit close to the middle of the forehead (a validation study even names them Fp1 and Fp2). Sideways eye movements produce their biggest signal *beside* the eyes, which is exactly where sleep labs put their eye electrodes.

## What this means

- A Muse S can probably see **that** your eyes move during REM sleep, and it clearly sees blinks.
- It probably **cannot** reliably see a left-right-left-right signal sent from inside a dream. That's one person, one headband and one day, so we'll test more, but it's a measured result, not a guess.
- This is why we're looking at a cheap, home-built eye sensor (EOG) with electrodes beside the eyes.

## Lessons

1. **Save the data before you judge.** The check failed three times; only the saved recording showed why.
2. **Measure, don't assume.** Both wrong rules came from what we *expected* a headband to do.
3. **A failing test can be the right answer.** The point of the eye check is to tell the truth about the hardware, not to pass.

## Checkpoint 01

With this, the first milestone is done and tagged as `checkpoint-01`: any EEG source, a Muse S over Bluetooth, Fake Moose, a live view with a contact score, and an eye check that tells the truth. Measured on our Muse S Gen 2: **blinks yes, left and right no.**

```bash
git clone https://github.com/emolionl/openlucid
cd openlucid
git checkout checkpoint-01
```

Next: a home-built eye sensor (EOG) beside the eyes, researched on the [research page](../research/diy-eog-esp32.md).
