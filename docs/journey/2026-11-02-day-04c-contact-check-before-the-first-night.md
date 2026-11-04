---
title: "Day 4c: contact check before the first night"
date: 2026-11-02T20:30:00+01:00
description: "A pre-flight contact check right before the first whole-night recording. Forehead sensors recover with water, ear sensors don't. Day 1 already warned this wouldn't hold for long."
weight: 10
outcome: "Open risk, going into tonight anyway"
tldr:
  - "Dry: all four sensors Poor, 0% on target."
  - "After dampening: AF7 and AF8 (forehead) went to Good, 100%. TP9 and TP10 (ears) stayed Poor, 0%."
  - "Removing hair from under the ear clips did not fix TP9/TP10 — the hair guess was wrong."
  - "AF7 dropped from 100% back to 0% within under 10 minutes, replicating Day 1's 'contact fades as it dries' finding a third time."
  - "AF8 was the one sensor that held at Okay/50-60% across repeated checks — unexplained, worth tracking, not worth guessing at yet."
  - "Running the first night anyway, on whatever contact is available at lights-out, to see the pattern over 7-8 hours instead of minutes."
---

## What this was

A contact check right before starting tonight's first whole-night recording with the [night recorder built today](2026-11-02-day-04b-building-the-night-recorder.md).

## Dry vs. dampened

| Sensor | Dry | After dampening |
|---|---|---|
| TP9, left ear | Poor · 201 µV · 0% | Poor · 187 µV · 0% |
| AF7, left forehead | Poor · 190 µV · 0% | **Good · 21 µV · 100%** |
| AF8, right forehead | Poor · 279 µV · 0% | **Good · 17 µV · 100%** |
| TP10, right ear | Poor · 167 µV · 0% | Poor · 158 µV · 0% |

Dampening fixed both forehead sensors outright. It did nothing measurable for either ear sensor. The app's own hint — "make sure no hair is under the sensor" — points at the ears specifically, so hair was checked next.

## Hair removed, contact re-checked twice more

| Sensor | 20:24 | 20:29 |
|---|---|---|
| TP9, left ear | Poor · 253 µV · 0% | Poor · 245 µV · 0% |
| AF7, left forehead | Poor · 128 µV · 9% | Poor · 178 µV · 0% |
| AF8, right forehead | **Okay · 61 µV · 50%** | **Okay · 51 µV · 60%** |
| TP10, right ear | Poor · 273 µV · 0% | Poor · 128 µV · 9% |

Clearing the hair did **not** fix the ears — TP9/TP10 stayed at 0% or close to it. Hair wasn't the (sole) cause there; the earlier guess was wrong. AF7, which had been Good at 100% right after dampening, had already dropped back to 9% and then 0% five minutes later — a third replication of Day 1's "contact fades as it dries," now timed at under 10 minutes rather than ~15. AF8 is the one outlier: not Good, but holding at Okay/50-60% across both checks, more stable than every other sensor. No explanation for why yet — worth tracking whether that holds, rather than guessing.

## This isn't a new problem

[Day 1](2026-11-01-day-01d-contact-does-not-stay.md) already found that a dampened forehead goes back to floating within about 15 minutes, once the water dries. Tonight's test is a replication of that, not a new finding: dampening gets you a green light for a few minutes, not for a night.

## The open question for tonight

A first contact check can only show a snapshot. The real question for a whole-night recording is what happens to AF7/AF8 contact over 7-8 hours of sleep, not 15 minutes awake at a desk: does it fail completely, fail in patches that the 30-second epoch quality label can catch, or drift slowly enough that only part of the night is unusable? Recording tonight anyway, on whatever contact is available at lights-out, specifically to get that answer — a night with some bad epochs marked is more useful than no night at all.

## Why this matters beyond this project

This is the same question Dreamento's `goodContact` flag and the lab's `ezscore-f`/`eegFloss` tools exist to handle for ZMax recordings: non-expert, self-applied dry/semi-dry EEG contact is not a one-time pass/fail, it's a moving target across a night. A system that only checks contact once, at the start, misses this entirely.
