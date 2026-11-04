---
title: "The journey"
description: "How OpenLucid gets built, step by step, including the wrong turns."
---

This is the build diary of OpenLucid: what we did, why, what broke, and what we learned. It's written for people who are new to all of this, because the mistakes are often more useful than the polished result.

Every entry ends with where the code stood at that moment, so you can check out the same version and follow along.

| Day | What happened |
|---|---|
| [Day 0: a name and a skeleton](2026-10-31-day-00-a-name-and-a-skeleton.md) | Why open source, why everything stays local, the folder layout, and checkpoint 00: an app and a server that wave at each other |
| [Day 1: the headband on the table](2026-11-01-day-01-the-headband-on-the-table.md) | Connecting a real Muse S over Bluetooth, Fake Moose, a very confusing first signal, filters, and an app that fits on a phone |
| [Day 1, part 2: what bad contact looks like](2026-11-01-day-01b-what-bad-contact-looks-like.md) | The headband on a head and still chaos: a debugging log with real numbers, one wrong conclusion, and what contact really means |
| [Day 1, part 3: can the headband see my eyes?](2026-11-01-day-01c-can-it-see-my-eyes.md) | A contact score with a clear target, and a guided eye check for blinks and left-right eye movements |
| [Day 1, part 4: contact doesn't stay](2026-11-01-day-01d-contact-does-not-stay.md) | The first eye checks fail because the forehead dried out again, and what the research standard for eye signals is |
| [Day 1, part 5: blinks yes, left and right no](2026-11-01-day-01e-blinks-yes-left-right-no.md) | The first eye check with good contact: two wrong assumptions in our code, and a Muse S forehead that barely sees sideways eye movements |
| [Day 2: the Diary Keeper grows up](2026-11-01-day-02-the-diary-keeper-grows-up.md) | A multi-user backend that also runs on a laptop, built and reviewed by a team of AI agents, tested on SQLite and PostgreSQL |
| [Day 3: testing everything](2026-11-01-day-03-testing-everything.md) | Eight AI test agents test the Diary Keeper in Docker, the API docs, the website and both apps from outside: 122 checks, 16 bugs, and what could not be tested |
| [Day 4: planning the first real night](2026-11-02-day-04-planning-the-first-night.md) | People move and lie on their side in their sleep: how OpenLucid records movement and position next to the EEG, and marks it instead of deleting it |
| [Day 4, part 2: building the night recorder](2026-11-02-day-04b-building-the-night-recorder.md) | Checkpoint 03 in code: a Start night button that writes EEG and movement to an EDF+ file every second, in a BIDS folder, checked with MNE, and the mistakes on the way |
| [Day 4, part 3: contact check before the first night](2026-11-02-day-04c-contact-check-before-the-first-night.md) | A pre-flight contact check right before the first whole-night recording: forehead sensors recover with water, ear sensors don't |
| [Day 5: real event or artifact](2026-11-04-day-05-real-event-or-artifact.md) | A stuck UI bug becomes a real trace-reading challenge (zoom, freeze, explain), a sourced research page checked against the actual PDFs, and untangling a website navigation that had grown to 10 flat items |
| [Day 5, part 2: writing the first video script](2026-11-04-day-05b-the-bell-script.md) | The animated anthology's first finished script: Episode 1, The Bell, a 14-shot Higgsfield-ready script on Tibetan dream yoga, picked specifically because it needed no one's permission first |
| [Day 6: producing the first episode](2026-11-05-day-06-producing-the-bell.md) | The script becomes a video: 14 Higgsfield shots, a cloned voice, a VO-to-video sync mismatch caught by measuring instead of guessing, an ffmpeg pipeline with no video editor, and a publish to YouTube |
