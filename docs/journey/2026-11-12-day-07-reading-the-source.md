---
title: "Day 7: reading the source before writing"
date: 2026-11-12T11:00:00+01:00
description: "Rewriting the PhD proposal by hand, starting with one paper read in full: what it says, what it changed in my own draft, a required foundation for the course, and a list of what I still need to find out."
weight: 14
outcome: "Read: Jafarzadeh Esfahani et al. (2024) in full. Changed: three claims in my own draft, and the course plan now has a required foundation"
tldr:
  - "I'm rewriting the PhD proposal by hand. Every claim has to be one I can defend, from a source I have read."
  - "The first paper, Jafarzadeh Esfahani et al. (2024), showed three problems in my own draft."
  - "The course gets a required foundation (chapters 1, 6, 7, 8 and 11) before anyone writes signal code."
  - "AI helped me read, but couldn't open the paywalled paper itself. 'Could not access' is not the same as 'checked'."
---

## Why today was reading, not building

My PhD proposal draft had grown long, and some of it was wrong. One claim had to be removed because it wasn't true, and two statistics had to go because I couldn't find a source for them. So I'm rewriting it from scratch, in my own words. The rule is simple: every sentence is one I can defend in a conversation, and every source is one I have actually read.

I started with the paper the whole project leans on: [Jafarzadeh Esfahani et al. (2024), *Citizen neuroscience: Wearable technology and open software to study the human brain in its natural habitat*](https://doi.org/10.1111/ejn.16227), European Journal of Neuroscience 59(5), 948–965. It's an editorial, not an empirical study, so that's how I'll cite it.

## What the paper says

Page numbers are included so you can check each point yourself.

- **Citizen neuroscience is about taking part, not just about equipment** (pp. 948–949). The public doesn't only collect data. They can also come up with ideas, ask research questions, design protocols, analyse data and share results.
- **Sleep is a good place to start** (p. 950). Everyone sleeps, there are many affordable devices, and home recordings can run for many nights. The authors also warn that you need a quality standard for "acceptable" data, set in advance.
- **Choosing hardware depends on the question** (pp. 951–956). Table 1 compares about 30 devices by category: modular boards such as OpenBCI, headbands such as ZMax, Dreem and the Muse S I use, in-ear EEG and patches. Watches and rings have mostly unknown accuracy, because their algorithms are closed and keep changing.
- **Scoring models usually expect a standard EEG layout** (p. 957), so they don't work out of the box on wearables. They need new models, or existing ones retrained.
- **Dreamento** has a graphical interface (pp. 957–959) and currently works with the ZMax only.
- **The challenges** (pp. 959–961): citizens may struggle to follow protocols, and the quality of citizen-collected data has been questioned. The authors' answer is that professional researchers provide training, tools and infrastructure, and work together with citizens.

## What it changed in my own draft

1. **My definition was too narrow.** I described citizen neuroscience as using cheap sensors outside the lab. The paper puts participation first.
2. **"Dreamento needs Python and the command line" was misleading.** It has a graphical interface. What's true, from its own README, is that installing it and starting the real-time version go through Anaconda and a command prompt.
3. **"The literature identifies this gap" claimed more than the paper says.** The paper names protocol difficulties and data-quality concerns. That nobody has measured how often self-applied home EEG fails is my conclusion, so I have to write it as mine and check it.

I also had device prices in the draft that I couldn't source. The ZMax price isn't public without signing up. From now on I'll use the paper's price ranges, or no price at all.

## The course gets a foundation

The [course](/course/) now has a required foundation: chapters 1, 6, 7, 8 and 11, before anyone writes signal or scoring code. Their scope follows the programme of a 2019 workshop by the Donders Sleep & Memory Lab: how sleep is measured, polysomnography, sleep scoring and open-source analysis. There's also a new planned chapter, 7b, on choosing a device, built on the paper's Table 1.

## On using AI

I use AI a lot, and today showed both sides. Claude read the PDF and listed its claims with page numbers. That made my own reading faster, but this page isn't my verification yet: I'm reading the paper myself in English now.

The publisher and the repository both blocked automated access, so the AI couldn't open the paper at all until I downloaded it myself. That's an important difference. "The AI couldn't check it" must never quietly become "checked".

I'm now designing a way to mark, on every page of this site, what was checked, by whom, and how. That isn't built yet.

## What I still need to find out

- Has anyone measured how often non-experts fail when they apply EEG at home by themselves? I need to search the literature, and ask people who know the field.
- The original paper behind a reported study at the University of Salzburg that tested 15 sleep trackers against polysomnography. So far I've only seen it in secondary sources.
- The current ZMax price and availability.
- Whether the Donders lab plans a new edition of its sleep-methods workshop.
- Next to read: Konkoly et al. (2024), then the ZMax validation (Esfahani, Weber et al., 2023).

## Where things stand

- `docs/neuroscience/README.md`: a required foundation section, and the new chapter 7b.
- The proposal rewrite has started in a separate working file, by hand. Reading comes first.
