---
title: "Day 0: a name and a skeleton"
date: 2026-10-31
description: "Why open source, why local, the folder layout, and an app that waves at a server."
weight: 0
outcome: "Done"
tldr:
  - "Open source (MIT), everything local, sound cues only, no medical claims."
  - "The name: OpenLucid."
  - "Four parts: backend (FastAPI), app (Flutter), web view (Vue), website (Hugo)."
  - "Checkpoint 00: the app and the server wave at each other."
---

## The idea

A lucid dream is a dream in which you realize you are dreaming. Sleep labs have shown that a soft sound played during REM sleep, one you trained yourself to link with the question *"Am I dreaming?"*, can help some people get there. Those labs use expensive equipment. We wanted to see how far you get with a consumer EEG headband, a laptop and free software, and to build it in public so anyone can learn from it.

## Decisions we made on day 0

- **Open source, MIT license.** Anyone may use, change and share the code, including researchers and teachers.
- **Everything runs locally.** Brain data is personal. It stays on your own laptop and phone; nothing is uploaded.
- **Sound only.** Some research uses weak electrical currents on the scalp. That belongs in a lab with an ethics committee, so OpenLucid will never do it.
- **No medical claims.** A consumer headband is not a medical device, and lucid dreaming is not a treatment.
- **Device-agnostic.** We start with the Muse because that's the headband we have, but the app is built so other EEG devices can be added.

## The name

We went through *Lucid*, *LucidBox*, *REMcue* and *Nachtwacht* (Dutch for "night watch", a nod to the Dutch psychiatrist Frederik van Eeden, who coined the term "lucid dream" in 1913). We picked **OpenLucid**: it says what it is (open, lucid) to researchers and beginners alike.

## The skeleton

```
openlucid/
├── backend/            the Diary Keeper: Python + FastAPI, writes down every night
├── frontend/
│   ├── desktop/        the app: Flutter, runs on Windows, Android, macOS and Linux
│   └── web/            the morning view: Vue, in the browser
└── website/            this website: Hugo
```

Why these tools? Flutter gives one app for every platform, which matters because the app has to talk to a Bluetooth headband. FastAPI gives us a small server with a free, automatically written manual at `/docs`. Hugo turns plain text files into a fast website.

## Checkpoint 00: they wave at each other

The first milestone is deliberately tiny: the server has one endpoint, `GET /health`, that answers *"The Diary Keeper is awake."* The app and the web view each have one button, **Wave at the Diary Keeper**. Press it, get a wave back. That proves the whole chain works before anything clever is added.

Each milestone gets a git tag (`checkpoint-00`, `checkpoint-01`, …), like a save point in a video game: if you get lost, jump back to a version that works.

## Code at the end of the day

```bash
git clone https://github.com/emolionl/openlucid
cd openlucid
git checkout checkpoint-00
```
