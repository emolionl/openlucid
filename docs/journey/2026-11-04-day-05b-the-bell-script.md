---
title: "Day 5, part 2: writing the first video script"
date: 2026-11-04T19:50:00+01:00
description: "The animated anthology's eight episodes had titles and one-line pitches, but nothing written. Episode 1, The Bell, got a full shot-by-shot script instead — because it's the one episode with no real person to ask permission from first."
weight: 12
outcome: "Shipped: a complete, sourced, Higgsfield-ready script for Episode 1"
tldr:
  - "Picked Episode 1 over Episode 4 on purpose: The Bell dramatizes an anonymous centuries-old practice, not two named living researchers — no permission needed before writing it."
  - "Found Higgsfield's actual prompt schema (MCSLA: Model, Camera, Subject, Look, Action) instead of guessing at AI-video prompt conventions from memory."
  - "14 shots, each a complete Higgsfield prompt with reusable identity and style blocks so the monk and the watercolor look stay consistent across separate generations."
  - "Checked the history before writing the truth ledger: Nāropa and Tilopa's approximate dates, and that 'dream yoga' as an English term comes specifically from Evans-Wentz's 1935 translation, not from Tibetan usage directly."
  - "The monastery, the teacher and the bell-as-cue are invented. The practice, its lineage and its goal — recognizing the dream while still inside it — are documented. The script says which parts are which."
---

## Which episode to write first

[The animated anthology](/videos/are-you-dreaming-series/) has had eight titles and one-line pitches since it was first sketched, but only Episode 4, **The First Message**, had an actual script — and that one can't be published yet. It tells a true story about two named, living researchers from their own published accounts, and the series' own rule is to contact real people before going further with their story.

Episode 1, **The Bell**, has no such problem. It's about Tibetan dream yoga — a centuries-old practice, not a specific named person — so there was nothing stopping it from being written and published today. Picking the episode that was actually *available* to finish, instead of the one at the top of the list, meant the series went from zero finished scripts to one.

## Writing for Higgsfield instead of guessing

The plan is to generate this with [Higgsfield](https://higgsfield.ai), an AI video tool. Rather than write prompts from memory of how AI video prompting "usually" works, the actual format got checked first: Higgsfield's prompts follow a formula called **MCSLA** (Model, Camera, Subject, Look, Action), with a specific order for text-to-video work — subject and appearance, then environment and atmosphere, then one primary action, then a named camera preset (Dolly In, Crash Zoom In, 360 Orbit, Crane Up, and so on — exact preset names, not vague motion words), then style and color grade. No negative prompts; state what should be in frame, not what to avoid. One primary action per shot — anything more complex gets split into separate shots instead of crammed into one.

That last rule shaped the whole script: instead of one long continuous take, [the episode](/videos/are-you-dreaming-01-the-bell/) is 14 short shots, each one a single clean action, written in order the same way the site's "Where to start" path works — generate shot 1, check it, move to shot 2.

**The consistency problem.** Higgsfield has no memory between separate prompts — generate the monk in shot 2 and again in shot 5, and nothing guarantees the same face or robe color unless the description is identical both times. The script handles this with two reusable blocks pasted verbatim wherever they're needed: an **identity block** (exact wording for the young monk, exact wording for the elder teacher) and a **style block** (the watercolor look, the palette, the paper grain) — written once at the top, referenced by name in every shot instead of re-described each time.

## Checking the history before writing it

The brief was one line: *"Tibetan dream yoga, a centuries-old practice built around recognizing a dream as a dream."* Before turning that into a script, it got checked:

- **Dream yoga (*milam*)** is a real practice within the Six Yogas (or, more precisely, Six Dharmas) of Nāropa — Nāropa (c. 1016–1100 CE) and his own teacher Tilopa (c. 988–1069 CE) are both historically dated figures, carried into Tibet via Marpa Lotsawa.
- **"Dream yoga" as an English name** comes specifically from W. Y. Evans-Wentz's 1935 translation, *Tibetan Yoga and Secret Doctrines*. Scholar Peter Alan Roberts has argued the Tibetan term never used the word "yoga" (*sbyor ba*) for this practice at all, and that "Six Dharmas of Nāropa" is the more accurate name — a useful correction that almost got missed by trusting the popular name at face value.
- **"Practiced for at least a thousand years"** is a Lion's Roar magazine claim, not something checked against a primary source — flagged as reported, not documented.
- Two books turned up that should be read before this script is treated as final rather than a first draft: Ulrich Timme Kragh's *Tibetan Yoga and Mysticism* (2015) and Tenzin Wangyal Rinpoche's *The Tibetan Yogas of Dream and Sleep* (1998). Neither has been read yet.

The monastery, the teacher, and the bell itself as the recognition cue are invented — there's no documented account of a specific monk noticing a dream because of a bell. The script dramatizes the practice's documented *goal* (catching the dream from inside it), not a recorded incident, and the truth ledger at the bottom of the script says so plainly, the same way every other episode in this series is supposed to.

## Where things stand

- `promotion/video-scripts/are-you-dreaming-01-the-bell.md` — the full script, 14 shots, ready for a first test render in Higgsfield.
- `promotion/video-scripts/are-you-dreaming-series.md` — links Episode 1's script from the episode table, and notes why it went first.

Not done: the two books above, unread; shots 1–14 are a complete ~2-minute first cut, not yet the series' 6–10 minute target length; and no render has actually been attempted yet, so the shot list is unvalidated against what Higgsfield actually produces.
