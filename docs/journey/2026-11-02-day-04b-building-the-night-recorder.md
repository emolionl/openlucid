---
title: "Day 4b: building the night recorder"
date: 2026-11-02T19:00:00+01:00
description: "Checkpoint 03 in code: a Start night button that writes EEG and movement to an EDF+ file every second, in a BIDS folder, checked with MNE. And the four mistakes on the way."
weight: 9
outcome: "Built, tested with Fake Moose; first real night tonight"
tldr:
  - "Start night writes one EDF+ file as it goes: 4 EEG channels at 256 Hz, accelerometer and gyroscope at 52 Hz, and the events as annotations."
  - "Every 30 seconds: contact per sensor, movement, position change and a quality label, in epochs.tsv."
  - "A Bluetooth dropout becomes a marked gap, the app reconnects by itself, and the computer is kept awake."
  - "MNE, the tool most sleep research uses, opens the files exactly as intended. Tested end to end in the real Windows app."
  - "Four mistakes on the way, one of them a real bug that a flaky test found."
---

## What was built

The plan from [Day 4](2026-11-02-day-04-planning-the-first-night.md), in code (all in `frontend/desktop/lib`):

| Piece | File | What it does |
|---|---|---|
| Movement from the Muse | `eeg/muse_protocol.dart`, `eeg/muse_source.dart` | Reads the accelerometer and gyroscope: 20-byte packets, 3 samples of x, y, z each, 16-bit big-endian numbers |
| EDF+ writer | `night/edf_writer.dart` | Writes the file one second at a time. The header says "-1 records" until the night is stopped, so a crash leaves a file that can be repaired |
| Night recorder | `night/night_recorder.dart` | Puts EEG and movement together in 1-second records, fills gaps, summarises every 30-second epoch, writes the BIDS files when stopped |
| Keep awake | `app/keep_awake.dart` | Asks Windows not to sleep (`SetThreadExecutionState`, called directly through `dart:ffi`) |
| Reconnect | `app/headband.dart` | When the headband drops: marks it, tries again every 10 seconds, marks the return |
| Screens | `ui/screens/tonight_screen.dart`, `nights_screen.dart` | Start night / Stop night (with a confirmation), a recording card, and the list of nights |

A night lands in `Documents/OpenLucid/nights`, laid out as BIDS-EEG:

```
nights/
  dataset_description.json
  sub-<random code>/ses-<yyyymmddhhmm>/
    eeg/   ..._task-sleep_eeg.edf   the recording
           ..._eeg.json              the sidecar BIDS requires
           ..._channels.tsv          each channel, its unit, good or bad
           ..._events.tsv            lights off/on, movement, gaps...
    openlucid/
           epochs.tsv                every 30 s: contact, movement, quality
           EEG L.edf, EEG R.edf      the same signal the way Dreamento opens it
```

The subject code is random (8 hexadecimal characters, made once per device). No name goes into a file, and the EDF header's patient field stays `X X X X`.

## How it was checked

- **Unit tests** for the EDF writer (every header field, the size of each record, repairing a cut-off file) and for the recorder with the Fake Moose: a full BIDS folder, a turn-over that becomes a position change, a 6-second silence that becomes a marked gap.
- **An independent reader.** `tools/check_night.py` opens the night with MNE-Python and compares what it reads with what the app meant to write: channels, sample rates (256 Hz and 52 Hz), length, annotations, the sidecar's required fields.
- **End to end** in the real Windows app (integration test 5): Fake Moose, Start night, 35 seconds, Stop night, confirm. Result: 36 records, one epoch, the night listed on the Nights screen, and MNE reads it.

What is *not* tested yet: the real Muse's movement channels and the reconnect with real Bluetooth. That's what tonight is for.

## The mistakes

**1. A name used twice.** The recorder had a method `start()` (begin a night) and a field `start` (when it began). Dart doesn't allow a static and an instance member with the same name. Renamed the field to `startedAt`. Small, but the compiler caught it before anything ran.

**2. The test was wrong, not the code.** The gap test sent 5 seconds of data instantly, waited 4 seconds, and expected a gap. There was none: data that arrives *ahead* of the clock can never fall behind it. A real headband sends one second per second. Fixed the test to send data in real time, and learned that "more than 2 seconds behind" means a silence of more than about 3 seconds.

**3. A real bug, found by a flaky test.** The turn-over test passed alone and failed when all tests ran together. The reason: contact and movement were measured when the data *arrived*, but the epochs are cut when the data is *written*. When the computer is busy (or Bluetooth delivers a burst), the two drift apart, and the movement of one epoch gets counted in another. A turn-over averaged over two positions looks like no turn-over at all. Now both are measured on exactly the samples written into each record. A flaky test is often a real bug that only shows under load.

**4. Too tall for a phone.** The new night card pushed the live signal off small screens; three layout tests failed. On phones it's now just a button, and one line while recording.

## For tonight

- Close any old OpenLucid window first; the new build is in `build/windows/x64/runner/Release`.
- Laptop on the charger, next to the bed. If the lid will be closed: set "When I close the lid" to "Do nothing" while plugged in. The app keeps Windows awake, not a closed lid.
- Muse charged, Muse app on the phone closed. Moisten the sensors (see [Day 1d](2026-11-01-day-01d-contact-does-not-stay.md)).
- Tonight → Muse → connect → check contact → **Start night**. In the morning: **Stop night**. Then run `python tools/check_night.py <the night's folder>`.
