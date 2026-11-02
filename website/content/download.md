---
title: "Download"
description: "OpenLucid for Windows today; the server for any computer; Android, iPhone, Mac and Linux later. Free and open source."
tldr:
  - "Windows: download, unzip, double-click. No installer, no account."
  - "It's an early preview: it records nights and checks your headband, it doesn't play sound cues yet."
  - "The Diary Keeper server runs on any computer with Python or Docker. Android, iPhone and iPad, Mac and Linux come later, from the same code."
---

## The goal: as easy as possible

OpenLucid should be something you can try tonight without being a programmer. So every version will come as a ready-made download, and the code stays open for anyone who wants to read it, change it or build it themselves.

## Windows (preview)

**[Download OpenLucid for Windows](https://github.com/emolionl/openlucid/releases)** (64-bit, about 12 MB)

1. Download the `.zip` file from the newest release (for example `OpenLucid-0.3.0-preview-windows-x64.zip`) and unzip it anywhere, for example in your Documents folder.
2. Open the `OpenLucid` folder and double-click `openlucid.exe`.
3. Windows may warn you with "Windows protected your PC", because the app isn't signed yet (signing certificates cost money; it's on the list). Click **More info**, then **Run anyway**. If you'd rather not, you can build the app yourself from the code (below).
4. Try it with **Fake Moose**, the built-in simulated headband, or connect a **Muse** (Muse 2016, Muse 2 or Muse S) over Bluetooth.

What this preview can do:

- Show your brainwaves live and how well each sensor touches your skin.
- An eye check: can your headband see blinks and left-right eye movements?
- **Record a whole night**: brain signal plus head movement, saved on your own computer in the formats sleep research uses (EDF+ in a BIDS folder). See [Day 4b](../journey/2026-11-02-day-04b-building-the-night-recorder/).

What it can't do yet: recognise sleep stages and play the sound cue. Those are the next checkpoints, and you can follow them in [the journey](../journey/).

## Every platform, from one code base

The app is written once in Flutter and built for each platform. The server is plain Python.

| Part | Platform | Status |
|---|---|---|
| The app | Windows | **Preview, download above** |
| The app | Android | Builds from the code; not tested with a headband yet |
| The app | iPhone and iPad | Later |
| The app | Mac | Later |
| The app | Linux | Later |
| The Diary Keeper (server) | Any computer with Python 3.11+, or Docker | Works; for now you start it yourself ([how](../docs/getting-started/)) |

Your nights stay on your own device. The Diary Keeper is optional and runs on your own computer too; nothing is sent to us, because there is no "us" server.

## Build it yourself

All code is on GitHub under the MIT license: <https://github.com/emolionl/openlucid>. The [getting started guide](../docs/getting-started/) shows how to run the app and the server from the code.

*Educational, not medical advice. OpenLucid is not a medical device and doesn't diagnose or treat anything.*
