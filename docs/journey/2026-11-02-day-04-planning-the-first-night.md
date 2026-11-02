---
title: "Day 4: planning the first real night"
date: 2026-11-02T09:00:00+01:00
description: "Before sleeping with the headband: people turn over, lie on their side and move without knowing. How OpenLucid will recognise that instead of mistaking it for brain activity."
weight: 8
outcome: "Plan"
tldr:
  - "Everybody moves in their sleep, turns over and lies on their side. That's normal, and the recording has to cope with it."
  - "The Muse S has an accelerometer and a gyroscope (52 samples per second). OpenLucid will record them next to the EEG."
  - "Movement is marked, not deleted: every 30-second epoch gets a movement score, a position-change flag and a quality label."
  - "The first night is recorded locally and saved in the research standard (BIDS-EEG with EDF+). Syncing to the server comes next."
---

## The problem

A night isn't a lab test. The sleeper doesn't sit still with their eyes closed for 18 seconds; they turn over a few times an hour, lie on their side, push the headband into the pillow, and scratch their nose. None of that is wrong. Most people move dozens of times a night without remembering it.

For the recording, movement does three things:

1. **Large artifacts.** A head movement produces swings far bigger than brain activity, on every channel at once. An automatic sleep scorer can mistake them for waking or for eye movements.
2. **Contact changes.** Lying on one side presses the sensors on that side into the pillow (sometimes better contact, sometimes worse) and can lift the others. On day 1 we learned what lost contact looks like: [floating sensors](2026-11-01-day-01b-what-bad-contact-looks-like.md).
3. **False eye signals.** Movement can look like the left-right eye signal. A detector that doesn't know the head moved will raise false alarms.

## What OpenLucid will do

**Record movement next to the EEG.** The Muse S has an accelerometer and a gyroscope, each 3 axes at 52 samples per second, on their own Bluetooth channels (`273e000a` and `273e0009`, as documented by the open-source muse-lsl project). They go into the same EDF+ file as the EEG.

**Mark, don't delete.** Throwing away "bad" data hides information: a movement is also a sign of waking up, or of the end of a REM period. So every 30-second epoch gets:

| Label | Meaning | How |
|---|---|---|
| Movement score | How much the head moved | The gyroscope's rotation speed plus changes in the accelerometer, per epoch |
| Position change | The head turned to a new position (more than 30 degrees) | The direction of gravity in the accelerometer, compared with the last steady position |
| Quality | `good`, `okay`, `poor`, `gap` | Contact score per sensor, movement, and missing data |
| Events | `OpenLucid movement`, `OpenLucid position change`, `OpenLucid contact lost`, `OpenLucid disconnected` / `reconnected`, `OpenLucid gap` | Written as EDF+ annotations and in the events table |

Why "position change" and not "lying on the left side": we don't know yet which way the Muse's axes point when it's on the head. Naming positions (back, left, right) needs a short calibration first: lie on your back for ten seconds, then on each side. That's a later step; tonight the raw accelerometer is saved, so the positions can be worked out afterwards.

Analysis tools can then choose: score only clean epochs, treat movement epochs as "unknown", or count position changes.

**Use the eye signal only when the head was still.** The left-right detector (a later checkpoint) will ignore moments when the gyroscope shows the head moving.

## What the standards say

- The older sleep scoring rules had a separate "movement time" stage; the current AASM rules don't, and EDF+ says the old stages must not be mixed with AASM scoring. So we keep the AASM stages for sleep and add movement as our own documented annotation, `OpenLucid movement`.
- In BIDS-EEG, the accelerometer and gyroscope channels go into the channels table as type `MISC`, with their units (g and degrees per second).

The full decision about file formats is on the research page [how sleep EEG is saved](../research/eeg-data-standards.md).

## The plan for checkpoint 03

**For the first night (tonight):**

- A **Start night** button: the app keeps the computer awake, records EEG, accelerometer and gyroscope continuously to disk (written as it goes, so a crash or power cut doesn't lose the night), reconnects if the headband drops, and records contact per sensor every 30 seconds.
- **Stop** in the morning: the night is saved as a BIDS-EEG folder with one EDF+ file, the sidecar, channels and events tables, plus the Dreamento export.
- The **Nights** screen lists recorded nights.

**Right after:** signing in to the Diary Keeper and syncing the night to it.

## A practical note for the first night

Put the laptop on its charger and next to the bed, turn off "sleep when the lid is closed" if the lid will be closed, and keep the headband within a couple of metres. The headband's own battery should last a night; check it is full.
