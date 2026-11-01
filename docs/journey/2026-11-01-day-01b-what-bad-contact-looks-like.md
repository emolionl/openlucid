---
title: "Day 1, part 2: what bad contact looks like"
date: 2026-11-01T12:00:00+01:00
description: "The headband on a head, still chaos. A debugging log with real numbers, one wrong conclusion, and what every EEG programmer needs to know about contact."
weight: 2
---

Every programmer who touches EEG runs into this, and most tutorials skip it: **the hardest part is not the code, it's the contact between a sensor and skin.** This is our log, measurement by measurement, including the conclusion we got wrong.

## The setup

- Headband: Muse S Gen 2 (model MS-02), sensors at **TP9** (behind the left ear), **AF7** (left forehead), **AF8** (right forehead), **TP10** (behind the right ear), with the reference in the middle of the forehead.
- Skin: dry. No water, no wiping.
- Tool: the app's **Save 10 s raw data** button, which stores every Bluetooth packet exactly as it arrived, and [`tools/analyze_raw_muse.py`](https://github.com/emolionl/openlucid/blob/main/tools/analyze_raw_muse.py), which decodes those bytes independently of the app.

## Question 1: is it our code?

When a signal looks wrong, first rule out your own bugs. The script checks:

| Check | What it would show if our code were wrong | Result |
|---|---|---|
| Packet sizes | anything other than 20 bytes | all 20 bytes ✅ |
| Packet counters | gaps or repeats | 0 gaps on every channel ✅ |
| Samples per second | not 256 | 256 ✅ |
| Jumps at packet boundaries | much bigger steps exactly every 12 samples (bytes decoded in the wrong order) | the same size inside and at boundaries ✅ |

**Conclusion: the data arrives complete and is decoded correctly.** Whatever is wrong is happening before the data reaches us: at the skin.

## Question 2: what does the signal say?

### Measurement 1, band just put on (14:47)

| Sensor | Stuck at the limits | Mains hum (50 + 100 Hz) | Verdict |
|---|---|---|---|
| TP9, left ear | 22.7% | 40% of the power | no contact |
| AF7, left forehead | 22.3% | 36% | no contact |
| AF8, right forehead | 0.8% | 36% | touching, but humming |
| TP10, right ear | 21.8% | 42% | no contact |

TP9 and TP10, on opposite sides of the head, were **almost identical, sample by sample**. Sensors in different places should never match like that.

### Our first conclusion, and why it was wrong

We concluded: *the reference sensor in the middle of the forehead isn't touching*, because when the reference floats, every channel picks up the same hum.

### Measurement 2, two minutes later (14:49)

| Sensor | Stuck at the limits | Mains hum | Verdict |
|---|---|---|---|
| TP9 | 23.0% | 31% | no contact |
| AF7 | 22.6% | 26% | no contact |
| AF8 | 8.0% | **2.7%** | settling: hum gone, slow drift |
| TP10 | 22.7% | 34% | no contact |

AF8 lost almost all of its hum. **If the reference were the problem, AF8 would be humming too.** So the reference was fine; three sensors simply weren't touching skin yet. We had blamed the one part that was working.

**Lesson:** one measurement is a guess. Two measurements can prove the first guess wrong.

## What's going on physically

- A sensor on dry skin, or not quite on skin, is a tiny **antenna**. The wiring in your walls carries 50 Hz (60 Hz in the Americas), and the antenna picks it up. That hum is far bigger than brainwaves, so the signal slams into the top and bottom of the amplifier's range: *stuck at the limits*.
- Two floating sensors catch **the same hum at the same moment**, which is why they look identical.
- When contact forms, the hum disappears first. What's left is a **slow drift** while the skin and sensor settle. After that, real brain activity becomes visible, for example **alpha** (8–12 Hz) when you close your eyes.

## What about a whole night?

Wetting your skin helps at the start, but nobody stays wet all night. The Muse S is made to be worn dry: after **5–10 minutes** your skin warms up and gets slightly moist on its own, and contact improves. What matters more is **firm, even pressure**: the strap snug, forehead sensors flat above the eyebrows, ear sensors on bare skin behind the ears.

### Measurement 3, after 10 minutes of wearing (14:57)

| Sensor | Stuck at the limits | Mains hum | Verdict |
|---|---|---|---|
| TP9 | 18.5% | 37% | no contact, still identical to TP10 |
| AF7 | 18.0% | 37% | no contact |
| AF8 | 1.5% | 28% | touching skin, humming again |
| TP10 | 18.1% | 38% | no contact |

Ten minutes of wearing changed almost nothing. Three sensors are stuck at nearly the **same** percentage (18.0, 18.1, 18.5), and the two ear sensors still match each other. That makes us less sure it's only the skin: it could also be a setting this headband model handles differently from the ones the open-source decoders were written for.

**We don't know yet.** Instead of guessing a third time, we planned two tests that tell the possibilities apart:

1. **Check with the manufacturer's own app.** If the official Muse app shows good contact on all four sensors while ours doesn't, the problem is in our code. If the Muse app also shows poor contact, it's the contact.
2. **The wet test.** Dampen the skin under the three silent sensors. If they come to life, it's contact. If they still only hum, something else is wrong.

### A clue from an older app

Before running those tests, we remembered an earlier Flutter app (for mybliss.space) that had the same trouble with a Muse S and was made to work. Comparing its Muse code with ours showed three differences:

| | The app that worked | OpenLucid so far |
|---|---|---|
| Timing | waits 200–400 ms between commands | sent `h`, `p21`, `s`, `d` back to back |
| Checking | asks for the firmware version, sends a preset, and **reads the answer** (`"rc":0` means accepted); tries other presets if refused | sent `p21` and never checked |
| Order | control channel, choose preset, then subscribe to EEG, then `s` and `d` | subscribed to EEG first, then all commands at once |

Commands go to the Muse "without response", so nothing tells the sender when one is lost. If `p21` gets lost, the headband keeps streaming in its own default mode, and the data channels may not carry four clean EEG signals. That would explain three sensors that look strangely alike.

We copied the careful approach, and the app now shows which firmware and preset the headband accepted. **Lesson:** when talking to hardware, never assume a command arrived. Ask, wait, and check the answer.

### Measurement 4, with the careful start (15:05)

| Sensor | Stuck at the limits | Mains hum | Radio, 21.3 Hz | Above 60 Hz | Verdict |
|---|---|---|---|---|---|
| TP9 | 20.0% (always at the bottom) | 2.9% | 6.0% | 41% | floating input |
| AF7 | 20.8% | 3.2% | 6.9% | 37% | floating input |
| AF8 | 2.3% | 6.2% | 2.0% | 2% | touching skin |
| TP10 | 20.4% | 2.8% | 5.7% | 38% | floating input |

The mains hum was gone, but the three sensors were still stuck at the limits, now with a new rhythm: **exactly 21.3 Hz**. That number is a giveaway: the Muse sends 12 samples per Bluetooth packet, 256 ÷ 12 = 21.3 packets per second. Brains don't keep time with Bluetooth. A **floating input**, an electrode connected to nothing, does: it picks up the headband's own radio bursts. AF8 meanwhile looked like a real signal, smooth and slow.

**Honest conclusion:** the careful start is better code, but probably not the fix. Whether the hum vanished because of the code or because something around us changed, we can't tell from one measurement. What four measurements in a row do say: **the same three sensors never touched skin, and AF8 always did.**

**Lesson:** the frequency of a disturbance tells you where it comes from. 50 Hz: the walls. 21.3 Hz: the headband's own radio. 8–12 Hz with your eyes closed: finally, a brain.

*Next: the manufacturer's app, to see whether it agrees about those three sensors.*

## What this changes in OpenLucid

- The app needs a **settling phase** before a night starts: wait until the contact is good, and say which sensor is still settling.
- Contact quality must be **recorded all night**, so the morning report can say "your left ear sensor lost contact at 03:12".
- The contact check should recognize the **"identical channels"** pattern and say so in plain words.
- The course needs a lesson, and maybe a game, about exactly this.
