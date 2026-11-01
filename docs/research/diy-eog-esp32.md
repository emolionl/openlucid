---
title: "Build your own eye-movement sensor (EOG) with an ESP32"
date: 2026-11-01
description: "Why eye signals are easy to measure, which cheap boards work, what it costs, how to stay safe, and how it plugs into OpenLucid."
---

> Educational, not medical advice. A home-built sensor is not a medical device and must not be used to diagnose or treat anything. Prices are what the seller showed on or around 2026-11-01, in the seller's currency, without shipping or tax. They change, so check before you buy.

The short answer to "can we build an EOG cheaply?" is **yes**. Eye-movement signals are among the largest signals you can pick up from the skin, and the 1970s experiments were done with an ordinary lab polygraph. A battery-powered ESP32 with a small amplifier board, for roughly €50–65, can record a usable left-right-left-right (LRLR) signal. The catch is that a cheap build needs testing before we trust it, and the safety rules below are not optional.

**Why we need it:** our first eye check with good contact showed that a Muse S forehead sees blinks clearly but barely sees left and right eye movements ([journey, day 1 part 5](../journey/2026-11-01-day-01e-blinks-yes-left-right-no.md)). Electrodes beside the eyes are where sideways movements are strongest.

This page covers building one yourself. For the ready-made devices (Muse, ZMax, OpenBCI, BITalino and others) see [EEG and eye-movement options](eeg-and-eog-options.md).

## 1. Why EOG is the easy biosignal

**The eye works like a small battery.** The front of the eye (cornea) is electrically positive compared to the back (retina). This "corneoretinal potential" is usually quoted at about 0.4–1 mV ([Iowa State physiology text](https://iastate.pressbooks.pub/curehumanphysiology/chapter/the-electrooculogram/)). Put one electrode beside each eye: when you look left, the cornea moves towards the left electrode and the voltage between the two electrodes swings one way. When you look right, it swings the other way.

**How big is the signal?** Sources differ, so here is the range:

| Source | µV per degree of horizontal gaze |
|---|---|
| Cornell ECE 4760 project notes | 5–20 µV/° ([Cornell 2014](https://people.ece.cornell.edu/land/courses/ece4760/FinalProjects/f2014/skg73_wfh42/skg73_wfh42/), [Cornell 2005](https://people.ece.cornell.edu/land/courses/ece4760/FinalProjects/s2005/dcc34/finalsite/design.html)) |
| MDPI *Electronics* paper | about 20 µV/°, close to linear within ±30° ([doi:10.3390/electronics9060970](https://dx.doi.org/10.3390/electronics9060970)) |
| Older measurements cited in a US patent | 35 µV/° on average ([US 4561448](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/4561448)) |

The potential also drifts during the day and with lighting (Cornell 2005 notes), which is why we calibrate each night (section 6).

**What that means for an LRLR signal.** A swing from straight ahead to 30° to one side gives about **150–600 µV** at 5–20 µV/°. A full left-to-right sweep (60°) gives about **300–1,200 µV peak to peak**. Those are our calculations from the sourced range, not measurements. For comparison, scalp EEG is usually quoted at about **10–100 µV** ([UCSD Cogs 179 notes](https://pages.ucsd.edu/~scoulson/cogs179/technical.pdf), [learningeeg.com](https://learningeeg.com/terminology-and-waveforms)). So a deliberate eye signal is often **ten times larger** than the brain waves an EEG headband is built for. That is why cheap hardware can manage it.

**How fast is it?** Not very. A 30° saccade (quick eye jump) lasts roughly 120 ms using the classic Baloh et al. (1975) fit of 37 ms + 2.7 ms per degree, as quoted in a [main-sequence review](https://iris.unige.it/retrieve/e268c4ce-65fa-a6b7-e053-3a05fe0adea1/Main_Sequence_BRM%20%28revised%29.pdf). Sleep labs filter EEG/EOG at about **0.3–35 Hz** and sample at **200 Hz minimum** (widely reported AASM figures, see the [companion page](eeg-and-eog-options.md)). For our purpose, a band of roughly **0.1 Hz (or DC) to 30 Hz** and **250 samples per second** is plenty. Keep the low end low: a high-pass filter set too high turns a "look left and hold" into a blip that fades away.

**What the 1970s used.** In April 1975, Keith Hearne at Hull University recorded Alan Worsley's pre-agreed left-right eye signals from a lucid dream on the sleep lab's polygraph ([IONS blog](https://noetic.org/blog/exploring-scientific-discovery-lucid-dreaming/), [Hearne's site](https://www.keithhearne.com/?p=27)). The original chart records are on display at the Science Museum in London, per Hearne's site. At Stanford, LaBerge's signals showed up as "unmistakable ping-pong volleys on the polygraph paper" ([Noema](https://www.noemamag.com/living-in-a-lucid-dream/)). LaBerge's chart had an EEG trace, two eye-movement traces and a chin-muscle trace ([Lucidity Letter reprint](https://journals.macewan.ca/lucidity/article/download/776/717/2267)). These were ink-pen polygraphs writing on paper. We could **not** find a source naming the make (often said to be Grass), so we don't claim it. The point holds anyway: the signal was big enough for pens on paper.

## 2. The building blocks

1. **Electrodes.** Disposable, pre-gelled snap pads (the kind used for ECG). SparkFun sells a 10-pack of 24 mm pads for US$9.25 ([SparkFun](https://www.sparkfun.com/disposable-surface-emg-ecg-ekg-electrode-24mm-10-pack.html)). Listings rarely say whether the pads are Ag/AgCl, so check: Ag/AgCl drifts less, which matters for slow eye signals. Placement for horizontal EOG: one pad just beside each **outer eye corner** (outer canthus). The reference goes on a bony spot such as the **forehead** or the **mastoid** (the bone behind the ear). Upside Down Labs puts it "on the bony part behind the earlobe" ([BioAmp EXG Pill docs](https://docs.upsidedownlabs.tech/hardware/bioamp/bioamp-exg-pill/index.html)). Clean the skin with soap or an alcohol wipe and let it dry. Less skin oil means lower, more stable contact resistance.
2. **Front-end amplifier.** This boosts microvolts to volts and rejects the mains hum that hits both electrodes equally. It is usually an *instrumentation amplifier* plus filters.
3. **ADC (analog-to-digital converter).** Turns the amplified voltage into numbers. It can be the microcontroller's own ADC, a separate chip like the ADS1115, or built into a "biopotential front-end" chip (ADS1292R, ADS1299) that combines amplifier and ADC.
4. **Microcontroller.** An ESP32 runs the timing and the radio.
5. **Wireless link.** Bluetooth Low Energy (BLE) to the phone. The data rate is tiny: 2 channels × 250 samples/s × 2 bytes is 1 kB/s.

**Why not the ESP32's own ADC alone?** Espressif itself says the ESP32 ADC "is sensitive to noise, leading to large discrepancies in ADC readings". It recommends a 100 nF capacitor and averaging several readings. The internal reference also varies between chips (1000–1200 mV around a nominal 1100 mV) ([ESP-IDF ADC calibration docs](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/peripherals/adc_calibration.html)). Hobby guides also report non-linearity near the ends of the range ([Zbotic](https://zbotic.in/esp32-adc-accuracy-fix-noise-and-non-linearity-issues/)), though that is not an Espressif source. You cannot wire electrodes straight to it: a few hundred µV is far below its noise. **After** an amplifier has made the signal hundreds of millivolts, the ESP32 ADC is usable for a demo. A separate ADC is still cleaner and more repeatable.

## 3. Concrete options

| Board | What it is | Channels | Resolution / rate | Works with ESP32? | Approx. price (2026-11-01) | Documented EOG? | Pros / cons for overnight EOG |
|---|---|---|---|---|---|---|---|
| **Upside Down Labs BioAmp EXG Pill** | Tiny open-source analog front-end, 25.4 × 10 mm | 1 per board | Analog out, so it depends on your ADC | Yes, the datasheet lists ESP32 ([datasheet](https://robu-prod-media.s3.ap-south-1.amazonaws.com/uploads/2024/04/BioAmp-EXG-Pill-Data-Sheet.pdf)). Default is 5 V, and 3.3 V ADCs need a voltage divider on the output | US$34.49 ([Tindie](https://www.tindie.com/products/upsidedownlabs/bioamp-exg-pill-sensor-for-ecg-emg-eog-or-eeg/)); 2-pack "Explorer" also listed | **Yes**: horizontal and vertical EOG placement, an EOG filter sketch (0.5–19.5 Hz) and an ESP32 BLE EOG example ([Eye-BioAmp firmware](https://github.com/upsidedownlabs/Eye-BioAmp-Arduino-Firmware)) | + Cheapest real EOG front-end, default config is "EEG & EOG", big hobby community. − AC-coupled (we found no published high-pass value), one channel per board, 5 V supply |
| **Upside Down Labs Neuro PlayGround Lite (NPG Lite)** | ESP32-C6 board with BioAmp channels built in, Feather size, LiPo charging | 3 (6 with add-on) | 12-bit; rate not stated | It *is* an ESP32 (BLE 5, Wi-Fi 6) | Explorer US$99 ([Tindie](https://www.tindie.com/products/upsidedownlabs/neuro-playground-lite-npg-lite-explorer-pack/)); US$113–240 on [Crowd Supply](https://www.crowdsupply.com/upside-down-labs/neuro-playground-lite) | Lists EOG as supported; blink demos ([Hackster](https://www.hackster.io/upsidedownlabs/controlling-keyboard-with-eye-blinks-using-neuro-playground-faec3f)) | + No soldering, wireless, multichannel. − About twice our budget |
| **AD8232 module** (SparkFun or clone) | Single-lead **ECG** front-end | 1 | Analog out | Yes, via the ESP32 ADC (3.3 V part) | US$24.41 (SparkFun, see companion page); clones are cheaper | Hobby and student projects only | − Designed for the heart: a two-pole high-pass of about 0.5 Hz (ECG band ~0.5–40 Hz, [theremino](https://www.theremino.com/wp-content/uploads/files/AD8232_for_EMG_ENG.pdf)). This shapes slow eye holds into decaying blips. You can lower it by swapping capacitors. The [AD8232 datasheet](https://www-cce.cldnet.analog.com/media/en/technical-documentation/data-sheets/ad8232.pdf) gives the formulas (the first pole is 100/(2πR1C1)). A UCSD student project used a ~0.07 Hz high-pass for EOG ([UCSD 2023](https://isn.ucsd.edu/courses/beng186b/project/2023/reports/group1.pdf)). The popular EMG mod goes the *wrong* way for EOG |
| **ProtoCentral ADS1292R breakout** | TI ADS1292R: 2-channel, 24-bit biopotential front-end with built-in amp and ADC, SPI | 2 | 24-bit, 125 SPS–8 kSPS ([TI](https://www.ti.com/product/ADS1292R)) | Yes, ProtoCentral lists ESP32 and has Arduino/ESP32 wiring | ₹3,945 ([ProtoCentral](https://protocentral.com/product/ads1292r-ecg-respiration-breakout-kit/)) | No EOG-specific example found | + Two clean digital channels (horizontal EOG + vertical EOG or chin EMG). − Sold for ECG, the library is ECG-oriented, more firmware work. ADS1293: not checked |
| **ADS1299 boards with ESP32** | TI's 8-channel EEG chip (as in OpenBCI Cyton) | 8 | 24-bit, 250 SPS default | Cerelog ESP-EEG uses ESP32 ([GitHub](https://github.com/Cerelog-ESP-EEG/ESP-EEG)); ironbci uses STM32 + BLE, not ESP32 ([GitHub](https://github.com/Ildaron/ironbci)); HackEEG is an Arduino Due shield | Cerelog: not listed. HackEEG: US$495+ ([Crowd Supply](https://crowdsupply.com/starcat/hackeeg)). Bare-chip DIY: not found | Not specifically | + Research-grade, EEG + EOG + EMG at once. − Far over budget. Cerelog is **not isolated** and USB-powered, so laptop on battery only |
| **Discrete INA333 / INA128 + ADS1115** | Build your own: instrumentation amp chip, filters, 16-bit I²C ADC | 1–2 | ADS1115: 16-bit, 8–860 SPS, ±256 mV smallest range ([TI](https://www.ti.com/product/ADS1115)) | Yes (I²C) | INA333 chip ~US$1.19–4.75 ([LCSC](https://www.lcsc.com/product-image/C19450.html), TI); ADS1115 board US$14.95 ([Adafruit](https://www.adafruit.com/product/1085)) | Student EOG designs exist (e.g., AD622-based [UCSD REM-sleep EOG](https://isn.ucsd.edu/courses/beng186b/project/2022/reports/eogdesigntotrackremsleep_19207_6710856.pdf)) | + You choose the filters (you can keep it near DC). − Breadboard noise, more to get wrong; better as a second project |
| **ESP32 ADC alone** | No amplifier | — | 12-bit, noisy | — | — | — | − Will not see a raw eye signal (see section 2) |
| **BITalino (PLUX)** | Educational biosignal kit with a dedicated EOG sensor | several | (not checked here) | No, it has its own board with BT/BLE | Kit ~€149–189 (companion page); EOG sensor €60 ([PLUX](https://pluxbiosignals.com/products/electrooculography-eog-sensor)) | **Yes**, a dedicated EOG sensor | + The "known good" teaching reference. − Not ESP32, several times the price |

## 4. Safety (read this before you put anything on your face)

- **Battery only. Nothing on your body may be connected, even indirectly, to mains power.** That means no USB cable to a laptop or PC that is plugged into the wall, and no charging while it is worn. A faulty charger or mains surge can put dangerous voltage on the electrodes, and so on your head ([eegsynth](https://www.eegsynth.org/?p=1881); [Open Ephys course safety page](https://oe-ephys-course.readthedocs.io/en/latest/EEA/safety.html)). Every DIY board we checked says the same: HackEEG ("no patient isolation… operate… from battery power"), ironbci ("never wear it while charging"), Cerelog ("not galvanically isolated"), ProtoCentral (run the host on battery), and OpenBCI, whose boards are meant to be powered only from low-voltage batteries ([OpenBCI liability page](https://docs.openbci.com/Policies/Liability/)).
- **Why a battery ESP32 over Bluetooth is inherently isolated.** If the whole device runs on its own small LiPo and talks to the phone by radio, there is no wire to mains anywhere. A 3.7 V cell cannot push a dangerous current through skin, and the radio link carries no current. One trap: the Seeed XIAO wiki says you may leave USB connected while running on battery ([Seeed wiki](https://wiki.seeedstudio.com/XIAO_ESP32C3_Getting_Started/)). That is fine for the board, but **not while it is on your face**. Unplug USB before you put the electrodes on.
- **What "medical grade" means.** Medical devices are tested to IEC 60601-1, which caps leakage current through the patient. In normal conditions the cap is 100 µA for body-contact (type BF) parts and 10 µA for parts that may touch the heart (type CF) ([Advanced Energy](https://advancedenergy.com/en-us/about/news/blog/safety-requirements-in-medical-equipment-designing-for-bf-and-cf-classifications), [TDK-Lambda](https://emea.lambda.tdk.com/uk/KB/Understanding-leakage-currents-in-medical-applications.pdf)). **Our build has not been tested to any of this.** Battery-only operation is what keeps the risk low.
- **Check the power wiring twice.** Swapping VCC and GND destroys the EXG Pill ([datasheet](https://robu-prod-media.s3.ap-south-1.amazonaws.com/uploads/2024/04/BioAmp-EXG-Pill-Data-Sheet.pdf)), and a reversed LiPo damages boards (ironbci). Use a LiPo with a protection circuit.
- **Skin overnight.** Adhesive pads can cause redness or itching, especially on sensitive skin and over long wear. A 30-day study of electrodes on the face found breathable backings did better than foam, and adhesive remover reduced skin-stripping ([UEA manuscript](https://ueaeprints.uea.ac.uk/id/eprint/75748/1/Accepted_Manuscript.pdf)). Use a fresh pad each night, move it slightly, and stop if the skin reacts. Keep gel and pads away from the eye itself.
- **Not a medical device.** It is for experiments and fun, not for diagnosing sleep problems.

## 5. Recommended first build for OpenLucid

**Choice: BioAmp EXG Pill + Seeed XIAO ESP32-C3 + LiPo, with an ADS1115 as the recommended upgrade.** It is the cheapest option with documented EOG examples and an ESP32 BLE example. Nearly everything is solderable by a beginner.

| Part | Price (seller, 2026-11-01) |
|---|---|
| BioAmp EXG Pill | US$34.49 ([Tindie](https://www.tindie.com/products/upsidedownlabs/bioamp-exg-pill-sensor-for-ecg-emg-eog-or-eeg/)) |
| Seeed XIAO ESP32-C3 (BLE 5, on-board LiPo charger) | US$4.90 ([Seeed](https://www.seeedstudio.com/Seeed-XIAO-ESP32C3-p-5431.html)) |
| 3.7 V 500 mAh LiPo with protection | US$7.95 ([Adafruit](https://www.adafruit.com/product/1578), out of stock that day; any protected cell works) |
| Snap electrodes, 10-pack | US$9.25 ([SparkFun](https://www.sparkfun.com/disposable-surface-emg-ecg-ekg-electrode-24mm-10-pack.html)) |
| **Core total** | **US$56.59** (roughly €50, plus shipping) |
| Upgrade: ADS1115 16-bit ADC | +US$14.95 ([Adafruit](https://www.adafruit.com/product/1085)) → US$71.54 |

**Wiring in words.** Three electrode leads (IN+, IN−, REF) from the EXG Pill's cable go to the left outer canthus, the right outer canthus and the mastoid or forehead. The Pill's OUT goes, through a voltage divider (the board is 5 V by default), either to an ADC pin on the XIAO or, better, to input A0 of the ADS1115. The ADS1115 connects to the XIAO's I²C pins (SDA/SCL). The LiPo plugs into the XIAO's battery pads.

**Two open questions about this build. Settle them on the bench before ordering in bulk:**
1. *Power.* The datasheet says the Pill operates at 5 V, while a LiPo gives 3.7–4.2 V. Whether it runs well straight from the cell or from 3.3 V is not documented clearly, so you may need a small 5 V boost module (price not checked).
2. *ESP32 ADC.* Upside Down Labs' own firmware table lists the "ESP32 C3 Mini" as **not compatible**, even though the datasheet lists ESP32. That is a good reason to use the ADS1115 rather than the C3's ADC.

**Firmware outline.**
- A hardware timer fires at **250 Hz**. Each tick reads one sample (ADS1115 in continuous mode at 250 SPS, or 475/860 SPS if you read two channels in turn).
- Samples go into a buffer. Every 10 samples (25 times a second) the device sends one **BLE notification**: a 16-bit **packet counter**, a channel count, then 10 × 16-bit samples per channel. That is about 25 bytes for one channel. The counter lets the app spot dropped packets and mark the gap instead of silently gluing data together.
- Also send the sample rate and gain once on connect, so the app can convert to µV. A battery-voltage reading is a nice extra.
- **In the app:** add a new data source alongside the Muse, with its own timestamps. The LRLR detector runs on both streams, and the two are aligned by time.

**A second channel.** With a second EXG Pill (the 2-pack) into ADS1115 input A1, you can record **vertical EOG** (above and below one eye, which separates blinks from sideways looks) or **chin EMG** (muscle tone, which drops in REM). If you want two channels from day one, the ADS1292R breakout (2 channels, 24-bit, SPI) is the step up. It costs more and needs more firmware work.

## 6. How to validate it cheaply

1. **Guided eye check at the start of each night.** The app prompts: blink 3 times, then look far left and far right 4 times, holding about a second at each side, then look at two marks a known angle apart (for example, two dots on the wall). The swing between the marks divided by their angle gives **µV per degree** for tonight. It should fall somewhere in the 5–35 µV/° range from section 1. Store it with the recording.
2. **Check the shape.** A held gaze should show as a step that stays up, not a spike that fades. If it fades within a second, the high-pass filter is too high for EOG.
3. **Wear it together with the Muse.** Run the same eye check and some deliberate LRLRs while awake, then overnight. Compare: does each LRLR show up on both? How many false alarms per night does each give? The companion page describes the gold-standard version of this test, using OpenBCI.
4. **Check the packet counter.** Count dropped BLE packets per hour. A phone that sleeps its Bluetooth will show up here first.

## 7. Uncertainties

- Published µV-per-degree figures range from 5 to 35 µV/°. Calibrate, don't assume.
- No source names the polygraph make used by Hearne or LaBerge.
- The EXG Pill's analog gain and filter cutoffs are not published numerically in the sources we read, and there are the power and ESP32-ADC questions above.
- NPG Lite sample rate, Cerelog price, ADS1293 boards and BITalino ADC specs: not checked or not found.
- Prices exclude shipping and import tax, and US$ → € conversion is approximate.

## Sources

- https://iastate.pressbooks.pub/curehumanphysiology/chapter/the-electrooculogram/
- https://people.ece.cornell.edu/land/courses/ece4760/FinalProjects/f2014/skg73_wfh42/skg73_wfh42/
- https://people.ece.cornell.edu/land/courses/ece4760/FinalProjects/s2005/dcc34/finalsite/design.html
- https://dx.doi.org/10.3390/electronics9060970
- https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/4561448
- https://pages.ucsd.edu/~scoulson/cogs179/technical.pdf
- https://learningeeg.com/terminology-and-waveforms
- https://iris.unige.it/retrieve/e268c4ce-65fa-a6b7-e053-3a05fe0adea1/Main_Sequence_BRM%20%28revised%29.pdf
- https://noetic.org/blog/exploring-scientific-discovery-lucid-dreaming/
- https://www.keithhearne.com/?p=27
- https://www.noemamag.com/living-in-a-lucid-dream/
- https://journals.macewan.ca/lucidity/article/download/776/717/2267
- https://docs.upsidedownlabs.tech/hardware/bioamp/bioamp-exg-pill/index.html
- https://robu-prod-media.s3.ap-south-1.amazonaws.com/uploads/2024/04/BioAmp-EXG-Pill-Data-Sheet.pdf
- https://github.com/upsidedownlabs/BioAmp-EXG-Pill
- https://github.com/upsidedownlabs/Eye-BioAmp-Arduino-Firmware
- https://www.tindie.com/products/upsidedownlabs/bioamp-exg-pill-sensor-for-ecg-emg-eog-or-eeg/
- https://www.tindie.com/products/upsidedownlabs/neuro-playground-lite-npg-lite-explorer-pack/
- https://www.crowdsupply.com/upside-down-labs/neuro-playground-lite
- https://www.hackster.io/upsidedownlabs/controlling-keyboard-with-eye-blinks-using-neuro-playground-faec3f
- https://www.theremino.com/wp-content/uploads/files/AD8232_for_EMG_ENG.pdf
- https://www-cce.cldnet.analog.com/media/en/technical-documentation/data-sheets/ad8232.pdf
- https://isn.ucsd.edu/courses/beng186b/project/2023/reports/group1.pdf
- https://isn.ucsd.edu/courses/beng186b/project/2022/reports/eogdesigntotrackremsleep_19207_6710856.pdf
- https://community.sparkfun.com/t/modify-ad8232-for-full-frequency-spectrum-electroretinogram/37383
- https://protocentral.com/product/ads1292r-ecg-respiration-breakout-kit/
- https://www.ti.com/product/ADS1292R
- https://www.ti.com/product/ADS1115
- https://github.com/Cerelog-ESP-EEG/ESP-EEG
- https://github.com/Ildaron/ironbci
- https://crowdsupply.com/starcat/hackeeg
- https://www.lcsc.com/product-image/C19450.html
- https://www.adafruit.com/product/1085
- https://www.adafruit.com/product/1578
- https://www.seeedstudio.com/Seeed-XIAO-ESP32C3-p-5431.html
- https://wiki.seeedstudio.com/XIAO_ESP32C3_Getting_Started/
- https://www.sparkfun.com/disposable-surface-emg-ecg-ekg-electrode-24mm-10-pack.html
- https://pluxbiosignals.com/products/electrooculography-eog-sensor
- https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/peripherals/adc_calibration.html
- https://zbotic.in/esp32-adc-accuracy-fix-noise-and-non-linearity-issues/
- https://www.eegsynth.org/?p=1881
- https://oe-ephys-course.readthedocs.io/en/latest/EEA/safety.html
- https://docs.openbci.com/Policies/Liability/
- https://advancedenergy.com/en-us/about/news/blog/safety-requirements-in-medical-equipment-designing-for-bf-and-cf-classifications
- https://emea.lambda.tdk.com/uk/KB/Understanding-leakage-currents-in-medical-applications.pdf
- https://ueaeprints.uea.ac.uk/id/eprint/75748/1/Accepted_Manuscript.pdf
