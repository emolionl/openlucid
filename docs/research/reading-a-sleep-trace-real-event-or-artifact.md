---
title: "Real event or artifact? Reading an EEG/EOG/EMG trace"
date: 2026-11-04
description: "The judgment call OpenLucid's whole cueing system depends on: telling a genuine REM-onset event from a channel artifact, by eye, in a live trace."
outcome: "Overview"
tldr:
  - "A real sleep event moves EEG, EOG and EMG together; most artifacts show up on a single channel."
  - "REM's signature: fast, mixed-frequency, low-voltage EEG; rapid eye movements on EOG; chin muscle tone drops to near zero (atonia)."
  - "Sweat and loose contacts ('electrodermal artifacts') drift one EEG channel slowly; a pulse artifact from a scalp artery usually hits only one lead too — 'single channel' is a better tell than 'EEG only'."
  - "This is the exact skill behind the Brain Atlas game's trace-reading challenge."
---

> Educational, not medical advice.

## Why this matters

For a system like OpenLucid, this call happens in real time, unsupervised, while someone's asleep: every few minutes the live trace does something, and the software has to decide whether it's watching the start of REM sleep — the only time its cue should fire — or a channel artifact that should be ignored. Fire a cue on a false event and you've woken someone for nothing (what the [Brain Atlas](/games/brain-atlas/) game scores as a "false alarm"). Stay quiet through a real one and the cueing window is gone ("missed it"). It's the same read of the same trace whether a sleep technician is scoring it by eye or a script is making the call at 3 a.m.

## What a real event looks like, together

REM is scored from three channels at once, never EEG alone, because EEG by itself genuinely cannot tell REM from waking — both show fast, low-voltage, mixed-frequency activity. What gives REM away is the other two channels moving in the same window:

- **EOG — rapid eye movements.** The dreamer's eyes really move behind closed lids; it's the signal lucid-dream research has relied on since [LaBerge, Nagel, Dement and Zarcone (1981)](https://journals.macewan.ca/lucidity/article/download/596/510/1874) verified lucid dreams with a pre-agreed eye signal, confirmed in PSG-scored REM.
- **EMG — muscle tone drops out.** Chin and body muscle tone falls to near zero in REM — the brainstem actively suppresses it so the body can't act out the dream. This is the classic finding behind [Chase and Morales (1990)](https://www.annualreviews.org/content/journals/10.1146/annurev.ps.41.020190.003013), *"The Atonia and Myoclonia of Active (REM) Sleep,"* Annual Review of Psychology 41:557–584 — widely cited as the standard reference on REM atonia; we worked from how it's cited elsewhere, not the paper itself, which sits behind a paywall we didn't check.
- **EEG — busy, low-voltage, "sawtooth" activity**, roughly as fast and unstructured as waking EEG on its own ([Ruehland et al. on the 2007 AASM montage](https://pmc.ncbi.nlm.nih.gov/articles/PMC4067446)).

None of these three is REM by itself. Together, in the same window, they are.

## What an artifact looks like

[Anderer, Roberts, Schlögl, Gruber, Klösch, Herrmann, Rappelsberger, Filz, Barbanoj, Dorffner and Saletu (1999)](https://pub.ista.ac.at/~schloegl/publications/Anderer1999a.pdf), *"Artifact Processing in Computerized Analysis of Sleep EEG — A Review,"* Neuropsychobiology 40:150–157, catalogues the usual suspects:

- **Sweat and loose contacts ("electrodermal artifacts").** Sweat changes the electrolyte concentration at the electrode-skin interface, and that drifts the baseline voltage slowly and smoothly — confined to whichever electrode is affected, not synced to anything on the other channels.
- **Pulse artifact.** A scalp artery pulsing directly under one electrode makes a small, heart-rate-locked ripple that "usually affect[s] only one lead." Worth knowing the exception: real ECG interference (the heart's own electrical field, not just a pulsing artery) *can* show up on several leads simultaneously — so "more than one channel moved" isn't proof of a real event by itself. It also has to look like REM, not like a steady 60–100 bpm tick.
- **Movement.** Head or body movement can cause a slow potential shift that Anderer et al. specifically warn can be "misinterpreted as delta activity" — it can fake a different sleep stage outright, not just look obviously wrong.
- **Line noise.** A constant, mechanically regular 50 or 60 Hz ripple (depending on the local power grid) is never real brain signal — nothing in the nervous system oscillates that cleanly, that fast, for that long.

## The rule of thumb

Ask two questions, in order: does the change match real physiology (eyes genuinely sweeping, muscle tone genuinely falling — not just "the line looks weird")? And does it show up across the channels that physiology would actually move? A change confined to one channel, or one that's too mechanically regular to be a nervous system, is an artifact. A change that's synced across EEG, EOG and EMG and looks like the real thing, is real.

## Try it

The [Brain Atlas](/games/brain-atlas/) night-drive mode freezes a live trace mid-anomaly and asks exactly this question, with the physiology spelled out afterward either way.

## Sources

- LaBerge, Nagel, Dement and Zarcone (1981), *Lucid dreaming verified by volitional communication during REM sleep*, Perceptual and Motor Skills 52:727–732; summary: <https://journals.macewan.ca/lucidity/article/download/596/510/1874>
- Chase and Morales (1990), *The Atonia and Myoclonia of Active (REM) Sleep*, Annual Review of Psychology 41:557–584: <https://www.annualreviews.org/content/journals/10.1146/annurev.ps.41.020190.003013> (abstract page only; we could not check the full text)
- Ruehland et al., on the 2007 AASM EEG montage: <https://pmc.ncbi.nlm.nih.gov/articles/PMC4067446> (as already cited in [EEG and eye-movement options](eeg-and-eog-options.md))
- Anderer, Roberts, Schlögl, Gruber, Klösch, Herrmann, Rappelsberger, Filz, Barbanoj, Dorffner and Saletu (1999), *Artifact Processing in Computerized Analysis of Sleep EEG — A Review*, Neuropsychobiology 40:150–157: <https://pub.ista.ac.at/~schloegl/publications/Anderer1999a.pdf>
