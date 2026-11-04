---
title: "Day 5: real event or artifact"
date: 2026-11-04T18:30:00+01:00
description: "A stuck UI bug turned into the trace-reading challenge Brain Atlas was always missing: zoom, freeze, and a real explanation when you're wrong. Then a sourced research page, and finally untangling the website's own navigation."
weight: 11
outcome: "Shipped: game redesign, sourced research page, site navigation cleanup"
tldr:
  - "Brain Atlas's anomaly panel wasn't closing for good — missing a toast() function. Fixed, then used the same bug report to redesign the whole challenge."
  - "The trace-reading challenge now zooms in, freezes the trace, pauses the rover, gives a real answer window, and explains the physiology when you're wrong instead of just scoring you."
  - "New research page sourced from three real papers (LaBerge 1981, Chase & Morales 1990, Anderer et al. 1999), checked against the actual PDFs, not memory."
  - "The site's top nav had grown to 10 flat items with no games section at all. Collapsed Videos/Research/Agentic Dev/Docs into one Education hub; nav is down to 7, homepage path down to 3 steps."
  - "Two silent failures today: a homepage edit that did nothing because the template ignores markdown content, and a new Hugo layout the dev server didn't pick up until restarted."
---

## What started it

A bug report: the anomaly prompt in [Brain Atlas](/games/brain-atlas/) (the exploded-view 3D brain, drive-to-electrode game) would come back up after you'd already answered it, or just never fully go away. The cause was small — `toast()`, the function that shows the little "you got it" message, didn't exist yet; the code that called it was throwing silently and leaving the panel in a half-closed state. Added the function, confirmed the panel now closes for good.

That fix exposed the actual problem underneath it: even working correctly, the challenge gave you 4.5 seconds, scrolling the whole time, to decide "real event or artifact?" from a fast-moving three-line squiggle. Nobody was learning anything from it. They were pattern-matching against a timer.

## Redesigning the challenge

The anomaly now runs in three phases instead of one:

| Phase | What happens |
|---|---|
| Lead-in (1.4s) | The trace keeps moving, letting the anomaly actually develop and become visible, same as before |
| Prompt | The trace **freezes** mid-anomaly, the panel **zooms** to the center of the screen over a dimmed backdrop, the rover and camera **stop moving entirely**, and you get 8 seconds — not 4.5 — to answer |
| Explain (only on a wrong answer or timeout) | No score, no toast. A plain-language explanation of what each channel actually did and why that makes it real or an artifact, with a "Got it →" button the player dismisses themselves |

The freeze is the part that matters most: `driveUpdate()` now checks `anomalyLocked()` first and, if the challenge owns the screen, skips rover movement and camera lerp entirely but keeps calling `updateAnomaly()` and `drawTrace()` — so the game genuinely pauses rather than just overlaying a dialog on a scene still running underneath it. `drawTrace()` stops pushing new samples into the trace buffer while frozen, so what's on screen when you're asked is exactly what you're asked about, not something that scrolled off three frames ago.

**Mistake today:** the first version of the zoomed canvas clipped the top of the "EEG" label — the text baseline sat at `y = h*0.17 - 10 ≈ 3px` in a canvas with its origin at 0, so the glyph's ascender rendered above the visible area. Invisible at the old 78px display height, obvious once the canvas was stretched to 200px for the zoom. Fixed with a floor: `Math.max(9, lane.y - 10)`.

## A sourced research page

The redesigned challenge needed somewhere to point a curious player, so [`/research/reading-a-sleep-trace-real-event-or-artifact/`](/research/reading-a-sleep-trace-real-event-or-artifact/) explains the same judgment call with citations: REM's three-channel signature (LaBerge, Nagel, Dement & Zarcone 1981; Chase & Morales 1990 on atonia), and the artifact taxonomy from Anderer et al. (1999), *Artifact Processing in Computerized Analysis of Sleep EEG*, Neuropsychobiology 40:150–157 — electrodermal drift from sweat, single-lead pulse artifacts, movement that can fake delta activity outright, and line noise.

**Mistake today:** first draft cited "Ruehland et al., Sleep 2011" from memory with a specific PMC id and page range. A search turned up a real Ruehland paper, but a different one (hypopnea scoring, not the EEG montage), at a different PMC id than what the existing site already links to. Rather than invent bibliographic details I couldn't verify, the new page just reuses the exact citation link the site already had in [`eeg-and-eog-options.md`](/research/eeg-and-eog-options/), unembellished. The Anderer citation, by contrast, got checked directly: fetched the actual PDF and read the title page and the "Types of Artifacts" section before writing a single claim from it.

## The website had no front door for any of this

Brain Atlas had no link anywhere except a chat message. The top nav had grown to 10 flat items — Download, Journey, Videos, Research, Learn (actually unrelated agentic-AI-development tutorials, not sleep science), Docs, Questions, Proposal, GitHub, plus whatever came next — with no grouping and nowhere that said "here's how to approach this site."

Three passes, each one simplifying the last:

1. Added a `/games/` section and linked Brain Atlas from the homepage's "Built in public" cards.
2. Added a "Where to start" section to the homepage: five numbered steps (videos, research, install, the Diary Keeper's multi-user server mode, developer docs), each a full-width row instead of a card grid — closer to a table of contents than a feature grid.
3. Noticed four of those five steps were all "education" wearing different names. Pulled Videos, Research, Agentic Dev and Docs under one new `/education/` hub page (same numbered-row layout, reused), collapsed the top nav from 10 items to 7, and cut the homepage path down to three real stops: Education, Install, and the backend's early multi-user mode.

That last step also corrected an assumption: "multiple people on one server" wasn't vaporware to label "coming soon" — `backend/README.md` already documents a working local-vs-server split (SQLite solo, PostgreSQL + Docker for a few people), with `app/models.py` carrying a real `User` model with roles and `tests/test_account.py`/`test_admin.py` passing. Early, not imaginary. The homepage step links straight to the backend instead of hedging.

**Mistake today:** the first attempt to add a homepage game link edited `content/_index.md`'s markdown body and changed nothing. The homepage doesn't render through `_default/single.html` — it has its own `layouts/index.html` that never references `.Content` at all. The real fix was a hand-written `<a class="link-card">` inside that template. Separately, the new `layouts/education/list.html` rendered as a blank generic list page until the Hugo dev server was restarted — new files under `layouts/` didn't trigger its watcher.

## Where things stand

- `website/static/games/brain-atlas/index.html` — the trace-reading redesign, tested by hand through all three phases including a deliberate wrong answer and a timeout.
- `docs/research/reading-a-sleep-trace-real-event-or-artifact.md` — new, sourced.
- `website/content/education/`, `website/content/games/`, `website/layouts/education/list.html` — new site structure.
- `website/hugo.toml`, `website/layouts/index.html`, `website/assets/css/site.css` — nav and homepage changes.

Left over from an earlier session: `website/static/games/night-drive/` is the prototype Brain Atlas grew out of, already committed, now linked from nowhere. Not cleaned up yet.
