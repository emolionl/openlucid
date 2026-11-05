---
title: "What's actually essential to learn here?"
description: "We're building a free neuroscience & lucid-dreaming course inside OpenLucid. Before writing it all, we'd rather ask people who know more than guess."
date: 2026-11-05
status: open
audience: "Neuroscience, sleep/EEG, electronics, and lucid-dreaming people — anyone with real expertise"
sections:
  - title: "Your background"
    intro: "So we know whose advice we're reading. Leave it blank if you'd rather stay anonymous."
    items:
      - id: who_name
        type: short
        q: "Your name, and how we may credit you"
        placeholder: "e.g. Dr. A. Jansen, may be thanked by name on openlucid.nl"
      - id: who_field
        type: multi
        q: "Which of these is closest to your own background?"
        options:
          - "Neuroscience / sleep research"
          - "EEG / PSG technician"
          - "Electronics / firmware engineering"
          - "Teaching / curriculum design"
          - "Lucid dreaming practice (no formal background needed)"
          - "Software development"
        other: true
  - title: "What's actually essential"
    intro: "Not a quiz — just your honest read on what matters."
    items:
      - id: ess_topics
        q: "If someone wanted to genuinely understand this field well enough to contribute to a project like OpenLucid, what would they have to learn first?"
        type: text
      - id: ess_gaps
        q: "What do people usually get wrong, skip, or oversimplify, that actually matters?"
        type: text
      - id: ess_papers
        q: "Papers, researchers, or textbooks you'd consider required reading?"
        type: text
  - title: "Our draft outline"
    intro: "We already sketched a rough table of contents — see it at openlucid.nl/course/ — organised as readings, hands-on labs with our own real data, and small games, each teaching one idea."
    items:
      - id: toc_feedback
        type: choice
        q: "Looking at that draft, is the coverage and order roughly right?"
        options:
          - "Yes, roughly right"
          - "Missing something important"
          - "Some of it doesn't belong"
          - "Haven't looked yet"
        comment: "What to add, remove, or reorder"
  - title: "Getting involved"
    items:
      - id: help_review
        type: choice
        q: "Once a chapter in your area is actually written, would you be willing to review it before we publish it?"
        options:
          - "Yes"
          - "Maybe — ask me when it's ready"
          - "No thanks"
      - id: help_game
        type: text
        q: "Any idea for a small game or interactive piece that would teach one of these concepts well — the way Brain Atlas teaches trace-reading?"
---

OpenLucid is building a free course — the real neuroscience, the electrodes, the signal-reading, the DIY build — modelled on how its own [Neuroscience Games](/games/) and [research notes](/research/) already work: sourced, honest about what isn't settled, and built to be used, not just read.

We've sketched a [draft table of contents](/course/) already, mostly by reorganising what we'd already written while building OpenLucid itself. Before writing the rest, we'd rather ask people who actually know this field than guess at what matters. Answer whatever falls in your area and skip the rest — even "I don't know, but here's who might" helps.
