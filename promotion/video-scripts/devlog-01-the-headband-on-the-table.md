---
title: "Devlog 1: the headband on the table"
date: 2026-11-01
description: "A short, funny devlog about our first real EEG signal, and the most important debugging lesson there is."
weight: 2
status: "Script, draft 1"
---

**Format:** about 2 minutes, screen recordings of the app plus simple animation, one narrator.
**Based on:** [Day 1 of the journey](../../docs/journey/2026-11-01-day-01-the-headband-on-the-table.md).

---

**[0:00] Screen: the OpenLucid app. A button: "Find my Muse". Click. "MuseS-6FFC" appears.**

> **NARRATOR:** Day one. We have an app, a Muse S headband, and a lot of optimism.

**[0:08] Click. The screen fills with wild stripes slamming top to bottom.**

> **NARRATOR:** Connected! And these are… brainwaves? They look more like a barcode having a panic attack.

**[0:16] Animation: a detective magnifying glass. Title card: "Suspect 1: noise."**

> **NARRATOR:** Raw EEG drifts, and it picks up the 50 Hz hum from the electricity in your walls. So we add filters. And a little dot per electrode: green for good contact, red for bad.

**[0:28] The app again: filtered, still chaos. Four red dots.**

> **NARRATOR:** Still chaos. All red.

**[0:32] Title card: "Suspect 2: a ghost connection."**

> **NARRATOR:** Maybe Windows kept an old connection alive, and every packet arrives twice? We add a counter.

**[0:40] Close-up: "256 samples/s · duplicates 0 · lost 0".**

> **NARRATOR:** Two hundred and fifty-six samples per second. Zero duplicates. Zero lost. The data stream is perfect.

**[0:48] Title card: "Suspect 3: a decoding bug?" The developer builds a button: "Save 10 s raw data".**

> **NARRATOR:** So we build a tool to save the raw bytes and inspect them. Serious debugging. And then someone asks the question.

**[0:58] Black screen. White text: "Was the headband on your head?"**

**[1:02] Camera pans across a desk. The Muse is lying next to a coffee cup.**

> **NARRATOR:** It was on the table.

**[1:06] Animation: the Muse's sensors as tiny antennas, catching zigzags from a wall socket.**

> **NARRATOR:** Without skin to touch, the sensors are little antennas in the air. They catch hum from the walls and the amplifier's own feedback, the same on every channel. The red dots were telling the truth all along.

**[1:20] Title card: "Lesson 1: check the simplest explanation first."**

> **NARRATOR:** Lesson one: check the simplest explanation first.

**[1:24] Montage: the filters, the duplicate counter, the raw-data button, the stream health line.**

> **NARRATOR:** Lesson two: nothing was wasted. The app now survives ghost connections, ignores duplicates, shows the health of the stream, and can save raw data. On a real night at 3 a.m., all of that will matter.

**[1:38] Next episode teaser: the headband on a forehead, a green dot appearing.**

> **NARRATOR:** Next time: we put it on a head. Revolutionary.

**[1:44] End card: github.com/emolionl/openlucid**
