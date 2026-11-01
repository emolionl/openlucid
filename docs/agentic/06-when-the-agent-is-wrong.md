---
title: "6. When the agent is wrong"
description: "Real mistakes from building OpenLucid: confident wrong conclusions, wrong assumptions in code, a dangerous command that was blocked, and the simple human question that solved a bug."
weight: 6
tldr:
  - "Agents reach confident conclusions from too little data. One measurement is a guess."
  - "Assumptions hide in code as 'obvious' rules. Save the data before you judge."
  - "Safety checks blocked a command that would have killed every Python process on the computer."
  - "Sometimes the best debugging tool is a human asking the obvious question."
---

## The headband on the table

The first real EEG signal looked like chaos. The agent added filters, then a duplicate-packet detector, then a stream-health readout, then a raw-data recorder, each a reasonable step. Then the human was asked: *was the headband on your head?* It was lying on the table.

**Lesson:** an agent will happily build increasingly clever tools for a problem that has a simple cause. Ask the obvious question first. (The tools weren't wasted, but they weren't the answer.) Read [the full story](../journey/2026-11-01-day-01-the-headband-on-the-table.md).

## A confident wrong conclusion

From one raw-data measurement, the agent concluded that the headband's reference sensor wasn't touching the skin. The next measurement proved that wrong: a sensor that depends on the reference was fine. The real cause, three sensors simply not touching, was confirmed by a one-variable experiment: dampen only the forehead, and see that only the forehead sensors come to life.

**Lesson:** one measurement is a guess. Design the experiment that would prove you wrong. Read [the debugging log](../journey/2026-11-01-day-01b-what-bad-contact-looks-like.md).

## Assumptions hidden in code

The eye check failed three times with "0 of 3 blinks". Only when it saved its recording could anyone see why: two rules in the code were wrong. It measured "rest" while the person was still settling in (46 µV instead of 11 µV), and it assumed a blink moves both forehead sensors the same way, while on this headband they move in opposite directions. The data was right; the code's expectations weren't.

**Lesson:** make your program save what it measured before it judges. Read [blinks yes, left and right no](../journey/2026-11-01-day-01e-blinks-yes-left-right-no.md).

## Dangerous actions get blocked

Two real examples where the safety system in Claude Code stopped the agent:

- To stop a test server, the agent wrote a command that would have **force-killed every Python process on the computer**, including unrelated work. It was blocked. The agent rewrote the test so the server started and stopped inside one script.
- The agent tried to **set a password on someone else's existing account** because it was asked to create an account that already existed. It was blocked, and the decision went back to the human.

**Lesson:** an agent optimises for the task in front of it. Hard-to-undo actions that affect other things or other people need a human's explicit yes, and good tooling enforces that.

## What this means for you

- Treat every agent conclusion as a hypothesis until data confirms it.
- Ask for the raw data, not just the verdict.
- Keep the human in the loop for anything irreversible.
- Write the mistakes down. The journey of this project is more useful *because* the wrong turns are in it.
