---
title: "Learn: Neuroscience & Lucid Dreaming"
description: "One night with an EEG headband, followed from start to finish: what sleep is, how a device hears the brain, and how a computer turns that into an answer. Written so that anyone, even a child, can follow it."
# The lessons, rendered by website/layouts/course/list.html as one night (on GitHub, as a table).
#   topics:  neuroscience | signal (signal & hardware) | data (data & code) | lucid (lucid dreaming)
#   formats: reading | lab | game | animation | video
#   status:  written (a lesson) | research (exists as a research note, to be reshaped) | planned
parts:
  - title: "What happens when I sleep?"
    lessons:
      - num: 1
        q: "Why does sleep come in stages?"
        hint: "A night as a journey through stages, in cycles of roughly 90 minutes."
        topics: [neuroscience]
        formats: [reading]
        status: planned
      - num: 2
        q: "What is REM, and why do we dream then?"
        hint: "Eyes move fast, muscles go slack, and the brain is almost as active as when awake."
        topics: [neuroscience]
        formats: [reading]
        status: planned
      - num: 3
        q: "How do scientists know which stage I'm in?"
        hint: "Polysomnography (PSG) watches three things: brain (EEG), eyes (EOG) and muscles (EMG)."
        topics: [neuroscience, signal]
        formats: [reading, animation]
        status: planned
        note: "Good candidate for an animation: three lines moving together to call REM."
  - title: "How does a device hear the brain?"
    lessons:
      - num: 4
        q: "What does an electrode actually measure?"
        topics: [signal]
        formats: [reading]
        status: planned
        note: "Expands the research note on EEG and eye-movement options."
        source: "/research/eeg-and-eog-options/"
      - num: 5
        q: "Why does contact matter so much?"
        topics: [signal]
        formats: [reading, lab]
        status: planned
        note: "Lab: our own contact-check numbers from the journey."
        source: "/journey/2026-11-02-day-04c-contact-check-before-the-first-night/"
      - num: 6
        q: "Real signal or noise?"
        hint: "Blinks, movement, sweat."
        topics: [signal]
        formats: [reading, game]
        status: research
        url: "/research/reading-a-sleep-trace-real-event-or-artifact/"
        note: "Game: Brain Atlas."
        game: "/games/brain-atlas/"
  - title: "From signal to answer"
    lessons:
      - num: 7
        q: "Which device should I choose?"
        topics: [signal]
        formats: [reading]
        status: planned
        note: "Built on Table 1 of Jafarzadeh Esfahani et al. (2024, pp. 953–956), by category, not device by device. The table reflects 2023, so every device we name gets checked against a current source before publishing. Use the table's price ranges, never guessed prices."
      - num: 8
        q: "How does a night get saved?"
        topics: [data]
        formats: [reading]
        status: planned
        note: "Short, from the research note on how sleep EEG is saved."
        source: "/research/eeg-data-standards/"
      - num: 9
        q: "How does a computer recognise a sleep stage?"
        topics: [data, neuroscience]
        formats: [reading, lab, animation]
        status: written
        url: "/course/09-how-a-computer-recognises-a-sleep-stage/"
        note: "The hands-on lab with our own data needs checkpoint 04 (sleep staging) first. Still planned: an animation contrasting Konkoly et al. (2024)'s home app, which ran on a fixed timer and never confirmed REM, with real EEG-based staging."
  - title: "Lucid dreaming and you"
    lessons:
      - num: 10
        q: "How can a dreamer give a signal with their eyes?"
        hint: "The left-right-left-right (LRLR) eye signal."
        topics: [lucid, signal]
        formats: [reading]
        status: planned
        note: "Expands the research note on a DIY EOG with an ESP32."
        source: "/research/diy-eog-esp32/"
      - num: 11
        q: "What does nobody know yet, and how can I help?"
        topics: [lucid]
        formats: [reading]
        status: planned
        note: "Ties to the donate page and the open questionnaires."
        source: "/questions/"
extras:
  - title: "A thousand years before the scanner"
    desc: "Dream yoga, written as Episode 1, \"The Bell\"."
    topics: [lucid]
    url: "/videos/are-you-dreaming-01-the-bell/"
    formats: [video]
  - title: "The 2012 case that changed the question"
    desc: "Dresler's EEG/fMRI study, a draft pending Dresler's review."
    topics: [neuroscience, lucid]
    url: "/questions/the-scanner-script-review/"
    formats: [reading]
  - title: "What's disputed, and why that's fine"
    desc: "Induction methods, supplements, binaural beats."
    topics: [lucid]
    formats: [reading]
  - title: "Build your own EOG"
    desc: "The electronics, for people who want to build."
    topics: [signal]
    url: "/research/diy-eog-esp32/"
    formats: [reading, lab]
---

This course follows one story: **one night with an EEG headband**, from putting it on in the evening to reading a graph of your sleep stages in the morning. Every lesson answers one question, asked the way a curious child would ask it. Anything that doesn't move the story forward goes into the extras.

**Who it's for:** anyone. No neuroscience, electronics or code needed. If a 12-year-old can't explain a lesson back to you in one sentence, the lesson isn't finished.

**Status:** being rebuilt into this structure. Lessons marked **written** are real. Everything else has its scope decided and gets written gradually. See [the journey](/journey/) for when each one lands.

## Why a story

People understand and remember stories better than explanatory texts. A meta-analysis of 78 samples and about 33,000 participants found a medium-sized advantage for stories, both for comprehension and for memory (Mar et al., 2021). The authors also warn that this doesn't mean all information should be forced into a story where that's unnatural.

Narratives are especially useful when scientists explain science to people who aren't experts (Dahlstrom, 2014). But a story also persuades, and that can mislead. That's why every lesson says where its comparison stops being true, and lists its sources.

**The story we follow is our own.** The [journey](/journey/) already documents a real first night with a Muse S, including the failures: contact that dried out in under 10 minutes, and eye movements the forehead sensors could barely see. Those are real numbers, and they are the course's examples. Other people's stories go in only with their permission.

## Why small games

Serious games helped people learn and remember better than conventional instruction. They worked best when combined with other teaching, used over several sessions, or played in groups (Wouters et al., 2013). A later meta-analysis also found that digital games improved learning compared with lessons without games (Clark et al., 2016).

One finding matters for how we build them: in Wouters et al. (2013), games **with** a narrative were not more effective, and the results hinted that games without one might work better. So the story lives in the course, and each game stays small and teaches exactly one idea, inside a lesson rather than instead of it.

## Required before writing code

Parts 1 and 2, plus lesson 9, are required before anyone writes OpenLucid's signal or sleep-scoring code. You can't write good software for a measurement you don't understand.

Their scope follows the programme of the Donders Sleep & Memory Lab's 2019 workshop *Introduction into Sleep Research Methods* ([programme](https://dreslerlab.org/workshop/)): how sleep is measured, polysomnography and applying electrodes, sleep scoring by the AASM rules, and analysis with open-source tools.

- Written in our own words, with links to the original sources. We never copy another course's material.
- The AASM scoring manual is a paid publication. We describe its rules in our own words and cite it, and don't reproduce it.
- **Still to do:** ask the Donders lab (sleep@donders.institute) whether a new edition of the workshop is planned.

## Every lesson has the same shape

| Part | What | For whom |
|---|---|---|
| **Question** | One question, in a child's words | everyone |
| **In short** | Three sentences, no jargon | a child |
| **Picture or animation** | One, showing the idea | everyone |
| **How it works** | Step by step, with an everyday comparison | MBO students |
| **Where the comparison stops** | One sentence, so simple never becomes wrong | everyone |
| **Try it** | A game, real data, or a small exercise | everyone |
| **You've got it when...** | One question you can now answer | everyone |
| **Going deeper** | Code and details, optional | contributors |
| **Sources** | With page numbers | everyone |

The main part of a lesson takes about five minutes to read. If it takes longer, the lesson covers too much.

## How a lesson gets checked

- **Is it clear?** Give the lesson to a child or an MBO student and ask them to explain it back in one sentence. If they can't, it isn't finished.
- **Is it correct?** Every claim gets checked against its source, with the page number. A lesson built on someone's own research gets a review-request page sent to that researcher, the same pattern as [the Dresler documentary concept](/questions/the-scanner-script-review/).
- **Still planned:** a small feedback widget on every lesson, so anyone who knows the field can flag what's wrong.

## Sources

- Clark, D. B., Tanner-Smith, E. E., & Killingsworth, S. S. (2016). Digital games, design, and learning: A systematic review and meta-analysis. *Review of Educational Research*, 86(1), 79–122. https://doi.org/10.3102/0034654315582065
- Dahlstrom, M. F. (2014). Using narratives and storytelling to communicate science with nonexpert audiences. *PNAS*, 111(Suppl. 4), 13614–13620. https://doi.org/10.1073/pnas.1320645111
- Jafarzadeh Esfahani, M., et al. (2024). Citizen neuroscience: Wearable technology and open software to study the human brain in its natural habitat. *European Journal of Neuroscience*, 59(5), 948–965. https://doi.org/10.1111/ejn.16227
- Mar, R. A., Li, J., Nguyen, A. T. P., & Ta, C. P. (2021). Memory and comprehension of narrative versus expository texts: A meta-analysis. *Psychonomic Bulletin & Review*, 28(3), 732–749. https://doi.org/10.3758/s13423-020-01853-1
- Wouters, P., van Nimwegen, C., van Oostendorp, H., & van der Spek, E. D. (2013). A meta-analysis of the cognitive and motivational effects of serious games. *Journal of Educational Psychology*, 105(2), 249–265. https://doi.org/10.1037/a0031311
