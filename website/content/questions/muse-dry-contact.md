---
title: "Questions for EEG and sleep experts"
description: "Our dry Muse headband loses contact within minutes, and a whole night recorded no usable EEG. If you know EEG, EOG or sleep recordings, these questions take about 15 minutes."
date: 2026-11-04
# open: the form is shown and accepts answers. closed: the page stays, the form is replaced by a note.
status: open
# Who this questionnaire is for, shown on the overview page.
audience: "EEG, EOG and sleep-recording experts"
# Rendered by layouts/questions/single.html. Each answer is stored with its question text, so old answers
# stay readable when questions change later. Keep ids stable once a questionnaire has answers.
sections:
  - title: "About you"
    intro: "So we know whose advice we're reading. Leave it blank if you'd rather stay anonymous."
    items:
      - id: who_name
        type: short
        q: "Your name, and how we may credit you"
        placeholder: "e.g. Dr. A. Jansen, may be thanked by name on openlucid.nl"
      - id: who_field
        type: multi
        q: "Which of these have you worked with?"
        options:
          - "Clinical or research polysomnography (PSG)"
          - "Dry-electrode or consumer EEG (Muse, Dreem, Emotiv, ...)"
          - "ZMax / Dreamento"
          - "OpenBCI or other DIY amplifiers"
          - "EOG and eye-movement scoring"
          - "Lucid dreaming research"
          - "Signal processing / artefact handling"
  - title: "Keeping contact through the night"
    intro: "This is the problem blocking everything else."
    items:
      - id: c_method
        type: multi
        q: "Which methods would you expect to keep the Muse S forehead sensors at good contact for 7–8 hours?"
        why: "Water works for under 10 minutes. We want something that lasts a night without hurting the skin or the fabric sensors."
        options:
          - "Electrode gel on the skin under the sensors"
          - "Saline or conductive spray"
          - "Small hydrogel pieces (cut from ECG/TENS pads) between skin and sensor"
          - "Skin prep first (alcohol wipe, light abrasion)"
          - "Tighter band, more even pressure"
          - "None of these: a dry Muse can't do a whole night"
        other: true
        comment: "Brand or product names, amounts, how you'd apply it"
      - id: c_safety
        type: text
        q: "Is any of those unsafe for skin overnight, or likely to damage the Muse's fabric sensors?"
        why: "We plan to try the safest option first, awake for an hour, before any night."
      - id: c_diagnosis
        type: choice
        q: "Do you agree that floating sensors, and possibly a floating Fpz reference, explain the night data above?"
        why: "15–28% of samples at the ±1000 µV limit, mostly 50 Hz, left and right pairs correlated at 0.94 and 0.99."
        options:
          - "Agree"
          - "Partly agree"
          - "Disagree, something else is going on"
          - "Can't tell from this"
        comment: "What else could cause it, or what we should check"
      - id: c_ears
        type: choice
        q: "The ear sensors (TP9/TP10) never reached good contact, even wet and with hair removed. What would you do with them?"
        options:
          - "Keep trying to fix their contact"
          - "Ignore them and score sleep from AF7/AF8 only"
          - "Use them only as a reference when they're good"
          - "Not sure"
        comment: "Tips for placement behind the ear"
      - id: c_metric
        type: choice
        q: "Is our contact score a sensible way to judge whether a 30-second sleep epoch is usable?"
        why: "RMS of 1 s after 0.5–40 Hz filtering and a 50 Hz notch; ≤ 25 µV is 100%, ≥ 150 µV is 0%."
        options:
          - "Yes, good enough for now"
          - "The thresholds need changing"
          - "Use a different measure (e.g. line-noise ratio, flat-line or clipping checks, impedance)"
          - "Not sure"
        comment: "What you would use instead"
  - title: "Choosing the hardware"
    intro: "We want to verify lucid dreams with the standard left-right-left-right eye signal and, eventually, publish open data."
    items:
      - id: h_route
        type: choice
        q: "For a home lucid dream lab whose data should hold up in a paper, which route would you pick?"
        options:
          - "Muse S with better contact, as the main device"
          - "Muse S plus a separate EOG channel (OpenBCI, or an ESP32 with BioAmp EXG Pill)"
          - "ZMax with Dreamento (hydrogel electrodes at F7/F8)"
          - "Something else"
        other: true
        comment: "Why, and roughly what it would cost"
      - id: h_eog
        type: text
        q: "For horizontal EOG at home overnight: which electrodes, where exactly, and what minimum specs (sample rate, resolution, input range)?"
        why: "Our test showed the Muse forehead sees blinks clearly but barely sees left-right eye movements."
      - id: h_safety
        type: text
        q: "Any electrical-safety rules for a DIY amplifier worn while sleeping, beyond 'battery only, never connected to a charging laptop'?"
  - title: "Protocol and next steps"
    items:
      - id: p_usable
        type: text
        q: "When would you call a home night 'usable' for sleep scoring and for spotting eye signals?"
        why: "For example: share of good epochs, which channels must be good, how long without movement."
      - id: p_mistake
        type: text
        q: "What is the most common mistake beginners make with home sleep EEG?"
      - id: p_read
        type: text
        q: "Papers, tools, datasets or people we should look at?"
      - id: p_contact
        type: choice
        q: "May we follow up with you?"
        options:
          - "Yes, a short call is fine"
          - "Yes, by email only"
          - "No, these answers are enough"
        comment: "How to reach you (optional)"
---

OpenLucid is an open-source home sleep-EEG project that aims to detect and study lucid dreams, built in public [day by day](/journey/). Our first whole night with a dry Muse S recorded no usable EEG. Answer only what falls in your field and skip the rest. Every answer helps, including "I don't know" and "this won't work".

## What we have

**Hardware.** Muse S Gen 2 (MS-02), soft fabric band with dry sensors at TP9, AF7, AF8 and TP10, reference at Fpz, 256 Hz. We stream raw EEG over Bluetooth into our own app (preset p21) and save each night as EDF+ in BIDS-EEG, with the accelerometer and gyroscope ([how we store it](/research/eeg-data-standards/)).

**Our contact score.** RMS of the last second after a 0.5 Hz high-pass, a 50 Hz notch and a 40 Hz low-pass. 25 µV or less counts as 100%, 150 µV or more as 0%, on a log scale. "Good" means at least 80%.

## What we measured

| Check | Forehead AF7 / AF8 | Ears TP9 / TP10 |
|---|---|---|
| Dry, awake | 190 / 279 µV · 0% | 201 / 167 µV · 0% |
| Skin dampened with water | **21 / 17 µV · 100%** | 187 / 158 µV · 0% |
| Same, under 10 minutes later | 178 µV · 0% / 51 µV · 60% | 245 / 128 µV · 0–9% |
| Hair removed under the ear sensors | no change | still 0–9% |

Full numbers: [contact check before the first night](/journey/2026-11-02-day-04c-contact-check-before-the-first-night/).

**The first night**, 2 November 2026, 2 h 23 min:

| Measure | Result |
|---|---|
| 30-second epochs with good contact, any channel | 0 of 286 |
| Samples at the ±1000 µV limit (TP9, AF7, AF8, TP10) | 28 · 28 · 15 · 16 % |
| Share of power at 50 Hz mains | up to 53 % |
| Share of power in 2–30 Hz | 2–9 % |
| Correlation TP9 ↔ AF7 and AF8 ↔ TP10 | r = 0.94 and 0.99 |

Our reading: the sensors, and possibly the reference at Fpz, are floating, and each side of the head picks up the room like an antenna. We would like you to confirm or correct that.
