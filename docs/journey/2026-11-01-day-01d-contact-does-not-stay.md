---
title: "Day 1, part 4: contact doesn't stay, and what research says about eyes"
date: 2026-11-01T14:00:00+01:00
description: "The first real eye checks fail because the forehead dried out again. Why that matters for a whole night, and what the research standard for eye signals is."
weight: 4
outcome: "Open problem"
tldr:
  - "Contact faded within about 15 minutes as the skin dried."
  - "The eye check now checks contact first and saves its recording."
  - "Research: the gold standard for eye signals is EOG, with electrodes beside the eyes."
---

## The first eye checks with a real headband

Two runs of the eye check, both **0 of 3 blinks and 0 of 4 eye movements**. Before blaming the eyes, we looked at the data again.

## Contact changes from minute to minute

| Sensor | 15:11, forehead just dampened | 15:27, sixteen minutes later |
|---|---|---|
| AF7, left forehead | touching skin | **identical to AF8**, 32% mains hum |
| AF8, right forehead | touching skin | **identical to AF7**, 32% mains hum |
| TP9, left ear | no contact | still floating |
| TP10, right ear | no contact | touching skin |

As the water dried, the forehead sensors went back to behaving like one antenna. You cannot see eyes through sensors that aren't touching, so the eye check never stood a chance.

**This is the core problem for a whole night:** with this headband and this skin, dry contact does not hold. Moisture helps for a few minutes, then fades.

## What we changed

- The eye check now shows the **forehead contact before it starts** and warns when AF7 or AF8 is below 80%, instead of running a test that can't succeed.
- It **saves its recording** (AF7, AF8 and the exact time of every prompt) to `Documents/OpenLucid/eyecheck-*.csv`, so a failed check can be analyzed.
- Two fixes in how it judges: the filter no longer starts with a jolt (raw EEG begins hundreds of microvolts from zero), and a blink is measured against the moment just before it, so a drifting sensor can't hide it.

## What the research standard says

We asked: how does science record eye movements during sleep, and what can a home project realistically use? The full answer, with sources and prices, is on the [research page](../research/eeg-and-eog-options.md). The short version:

- Sleep labs record eye movements with **EOG**: two electrodes beside the outer corners of the eyes. Lucid-dream research has verified the left-right signal this way since 1981. **A horizontal EOG is the gold standard.**
- A forehead headband like the Muse sees eye movements only *approximately*. One independent study found the Muse S scores REM sleep well against a sleep lab, but **nobody has published a test of left-right signal detection on a consumer headband**. That is open territory, and worth testing ourselves.
- A cheap way to get real EOG at home: stick-on electrodes beside the eyes with an open amplifier (OpenBCI, or an educational kit like BITalino). Battery-powered only, never connected to a charging laptop.

## Next

- Try the eye check again right after dampening the forehead, while both forehead sensors are green.
- Decide whether to add a real EOG channel next to the Muse, to test how well the forehead sees what the EOG sees.
