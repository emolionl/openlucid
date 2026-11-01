---
title: "Day 1: the headband on the table"
date: 2026-11-01
description: "A real Muse S over Bluetooth, Fake Moose, a confusing first signal, filters, and an app that fits on a phone."
weight: 1
---

## Goal

Connect a real EEG headband and see brainwaves move on screen. Our headband is a **Muse S Gen 2** (model MS-02), the soft fabric one made for wearing at night.

## Any headband, not just ours

The app never talks to a headband directly. It talks to an **EEG source**: something that can say "these are my electrodes, this is how many samples per second I send, and here are the numbers in microvolts". The Muse is the first source. A second one, **Fake Moose**, is a simulated headband, so anyone can follow along without buying hardware. It makes a calm 10 Hz alpha rhythm, a blink now and then, and an occasional look left and right.

## Bluetooth on Windows

The most popular Flutter Bluetooth library doesn't support Windows. We used `universal_ble`, which covers Windows, Android, macOS and Linux with one API. The Muse protocol itself is well documented by two open-source projects, muse-lsl and muse-js: each electrode sends 20-byte packets with a counter and twelve 12-bit samples. We wrote tests that build those packets by hand, so the decoding is checked without any headband.

Small surprise: Windows' own *Add a device* screen refuses to connect to the Muse. That's fine. Bluetooth Low Energy devices don't need to be paired; our app talks to it directly.

## The first signal: chaos

The Muse connected immediately, and the screen filled with wild stripes slamming from top to bottom on all four electrodes. We tried, in order:

1. **Filters.** Raw EEG has a big offset and picks up the 50 Hz hum of the power grid. We added display filters (0.5–40 Hz, 50 Hz notch) and a contact dot per electrode. Still chaos, and every dot red.
2. **A "Muse not found" mystery.** After a hot restart of the app, the scan found nothing. Windows had kept the old Bluetooth link open, and a connected Muse stops announcing itself. Fix: also ask the system which headbands it is already connected to.
3. **Duplicate packets.** Maybe the old link was delivering every packet twice? We added a duplicate counter and a live samples-per-second readout. Result: exactly 256 samples per second, 0 duplicates, 0 lost. The stream was perfect.
4. **A raw-data button**, to save 10 seconds of exactly what the Muse sends, so we could analyze it properly.

And then the obvious question: *was the headband actually on a head?*

It was lying on the table.

With no skin to touch, the electrodes are tiny antennas in the air. They pick up mains hum and the amplifier's own correction circuit, the same on every channel. The red dots had been telling the truth the whole time.

**Lesson:** check the simplest explanation first. But we didn't waste the time: the app now handles leftover connections, ignores duplicate packets, shows the stream's health, filters the view, and can save raw data. All of that will matter on a real night.

## An app that fits on a phone

Before going further we gave the app a proper layout, because it will mostly run on a phone next to a bed:

- a dark **night theme**,
- a **tab bar** on phones and a **side rail** on tablets and laptops,
- four screens: **Tonight** (headband, contact check, live signal), **Nights** and **Journal** (coming in later modules), and **Settings**,
- a contact check that says where each sensor sits (*left forehead, right ear*) and what to do when it's red,
- tests at five screen sizes, from a small phone to a laptop, that fail if anything doesn't fit. They caught two real layout bugs on their first run.

Building for Android hit one more snag: the newest version of the Bluetooth library expects Android build tools that weren't released with our Flutter version yet. Four lines in the Android build file fixed it.

## Where we stand

- ✅ Fake Moose streams and draws
- ✅ The Muse S connects and streams 256 samples per second with nothing lost
- ✅ The app builds for Windows and Android
- ⏳ **Still to do:** wear the headband, see a blink on the forehead electrodes, and tag `checkpoint-01`

## Code at the end of the day

```bash
git clone https://github.com/emolionl/openlucid
cd openlucid/frontend/desktop
flutter run -d windows
```
