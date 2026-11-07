---
title: "Learn: Neuroscience & Lucid Dreaming"
description: "Everything you'd need to know to actually work on OpenLucid — the real science, the electrodes, the signal, the build. Free, sourced, and honest about what isn't settled yet."
---

A course, not a reading list: each chapter has a reading, sometimes a hands-on lab with our own real data, and where it fits, a small game that teaches exactly one idea. Every chapter ends with **Done when** (how you'd know you actually got it) and **What this doesn't show** (the honest limits of what you just read) — nothing here pretends to be more settled than it is.

**Who it's for:** anyone who wants to understand lucid dreaming and sleep-EEG well enough to actually contribute to OpenLucid — no neuroscience or electronics background assumed going in.

**Status:** skeleton first. Chapters marked **written** are real; everything else is a placeholder with its scope decided, filled in gradually — see [the journey](/journey/) for when each one lands. Several already exist as [research notes](/research/) and just need restructuring into this shape, not writing from scratch.

**Using OpenLucid doesn't require any of this.** Every "reading" chapter needs no install and no code — it's for understanding, not building. A few chapters go further and include an optional, clearly-marked code-level section for people who want to contribute, not just read; skip it and the chapter still stands on its own.

## Part I — The Signal, and the Story

| # | Chapter | Category · type | Status |
|---|---|---|---|
| 1 | Why dreaming is measurable at all — REM, sleep stages, a night's architecture | Science · reading | Not written — must explain polysomnography (PSG): the multi-channel EEG+EOG+EMG(+more) lab setup that makes a sleep stage a checkable claim, not a guess. Good candidate for an animation (a person wired up, the channels moving together to call REM) |
| 2 | The 2012 case that changed the question — Dresler's EEG/fMRI study | Science · reading | Not written — draft exists as [a concept pending Dresler's review](/questions/the-scanner-script-review/) |
| 3 | A thousand years before the scanner — dream yoga and the historical record | Tradition · reading | Written as [Episode 1, "The Bell"](/videos/are-you-dreaming-01-the-bell/) — needs a reading version |
| 4 | What's disputed, and why that's fine — induction methods, supplements, binaural beats | Disputed · reading | Not written |
| 5 | What nobody's answered yet | Open question · reading | Not written |

## Part II — Reading the Trace, Building the Thing

| # | Chapter | Category · type | Status |
|---|---|---|---|
| 6 | EEG in one picture — what an electrode actually measures | Science · reading | Expand from [EEG and eye-movement options](/research/eeg-and-eog-options/) |
| 7 | Electrodes in practice — contact, impedance, why dry sensors fail | Practice · reading + lab | Lab: our own [contact-check numbers](/journey/2026-11-02-day-04c-contact-check-before-the-first-night/), already real data |
| 8 | Real event or artifact? Reading a trace | Practice · reading + game | Written as [research](/research/reading-a-sleep-trace-real-event-or-artifact/) + [Brain Atlas](/games/brain-atlas/) already exists as the game |
| 9 | Build your own EOG — electronics for a DIY sensor | Practice · reading + lab | Expand from [DIY EOG with an ESP32](/research/diy-eog-esp32/) — add the *why*, not just the *how* |
| 10 | How a night gets saved — EDF+, BIDS, data standards | Science · reading | Expand from [how sleep EEG is saved](/research/eeg-data-standards/) |
| 11 | [From signal to sleep stage — what a classifier actually does](11-from-signal-to-sleep-stage.md) | Science · reading | **Written** — conceptual read, no code required; the hands-on lab with our own data still needs checkpoint 04 (sleep staging) to exist first. **Still planned:** an animation contrasting Konkoly et al. (2024)'s home app — a fixed 6-hour timer, cues paused for 5 minutes after any phone movement, nothing that actually confirms REM — against real EEG-based staging, so the "guessing vs. knowing" gap is immediately obvious without reading a word |
| 12 | Connecting it to OpenLucid's own code | Practice · reading + lab | Not written |

## Part III — Practice, and Where You Come In

| # | Chapter | Category · type | Status |
|---|---|---|---|
| 13 | The eye signal — LRLR, verifying lucidity | Science · reading | Not written |
| 14 | What we still don't know, and how to help | Open question · reading | Ties to [donate](/donate/) and to asking the field directly — see the open questionnaire once it exists |

## How a chapter gets reviewed

Any chapter built on someone else's real, documented research gets its own review-request page before it's treated as final — the same pattern already built for [the Dresler documentary concept](/questions/the-scanner-script-review/): the chapter in full, our own truth ledger, then specific questions, sent directly to whoever's work it's based on. Not every chapter needs one — only the ones making a real claim about someone's real findings.

That's the heavyweight path, for a named expert whose own work is cited. **Still planned:** a lightweight feedback widget on every page of this course (and the research notes), so anyone with real knowledge of the field can flag what's wrong in a chapter without needing a dedicated review page first.

## Format, for when a chapter actually gets written

- **Category badge:** Science · Tradition · Disputed · Open question · Practice.
- **Type:** Reading (just the chapter) · Lab (a hands-on exercise with real OpenLucid data, no install needed where possible) · Game (a small interactive piece teaching one idea, linked from [Neuroscience Games](/games/)) · Animation (a short explainer animation embedded in the chapter, for ideas that are easier to show moving than to describe — e.g. a PSG setup, or channels moving together to call REM).
- **Level, inside a chapter:** the main text is always plain language — no code, nothing to install, written for someone who just wants to understand. Where a chapter has real code or training detail worth showing, it goes under its own clearly marked "Going deeper" section at the end, so a reader knows exactly where the no-code part ends.
- **Done when:** one concrete, checkable sentence — what you'd be able to do or recognise if the chapter actually landed.
- **What this doesn't show:** the chapter's own honest limits, every time, not just for the contested ones.
- **References:** full citations, the same discipline [the research notes](/research/) already use.
