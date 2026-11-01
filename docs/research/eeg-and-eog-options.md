---
title: "EEG and eye-movement options: research standard, devices and costs"
date: 2026-11-01
description: "What sleep labs use, what lucid-dream research uses, and which devices a home project can realistically choose, with prices."
outcome: "Overview"
tldr:
  - "Sleep labs record eye movements with EOG: electrodes beside the outer corners of the eyes."
  - "Lucid-dream research has verified the left-right eye signal this way since 1981."
  - "The Muse S scores REM sleep well in an independent study, but nobody has published how well any consumer headband detects the left-right signal."
  - "Budgets: home ~US$400–500, validation ~US$1,200–1,900, lab €10,000+."
---

> Educational, not medical advice. None of the devices below are used here to diagnose or treat anything. Prices are approximate, in the currency the source used, and were checked around October–November 2026 unless a different date is given. Prices change; check the seller before buying.

## 1. The research standard

### What a sleep lab records

A sleep lab records **polysomnography (PSG)**: several body signals at once, all night, scored in 30-second epochs according to the American Academy of Sleep Medicine (AASM) scoring manual.

- **EEG (brain activity).** The recommended derivations are **F4-M1, C4-M1 and O2-M1** (frontal, central, occipital, each against the opposite mastoid), with backups F3-M2, C3-M2 and O1-M2. An accepted alternative is Fz-Cz, Cz-Oz, C4-M1 ([Ruehland et al. on the 2007 AASM montage](https://pmc.ncbi.nlm.nih.gov/articles/PMC4067446)).
- **EOG (eye movements).** Two electrodes near the outer corners of the eyes (the *outer canthi*): **E1-M2 and E2-M2**. In the common setup E1 sits about 1 cm below the left outer canthus and E2 about 1 cm above the right one, so both horizontal and vertical movements show up as opposite-polarity swings. (This placement detail comes from training material and the NSRR protocol, not the manual text itself, which we could not access: [Brainscape PSG cards](https://brainscape.com/flashcards/for-poly-test-1-2554079/packs/4475612), [NSRR CFS EOG manual](https://sleepdata.org/datasets/cfs/pages/manuals/polysomnography/17-08-03-09-determine-eog.md).)
- **Chin EMG (muscle tone).** Muscle tone drops sharply in REM sleep. Together with rapid eye movements on the EOG and a "sawtooth" mixed-frequency EEG, low chin tone is how REM is scored.
- **Sampling rate.** Secondary sources consistently quote the AASM technical spec as **200 Hz minimum, 500 Hz desirable** for EEG, EOG and EMG, with an EEG/EOG filter of 0.3–35 Hz ([TESU PSG lecture notes](https://www2.tesu.edu/dial/psg/psg102/lectures/Lecture3/Lecture3_print.html), [PMC table](https://pmc.ncbi.nlm.nih.gov/articles/PMC5705734/table/Tab4)). We did not read the official manual; treat these as "widely reported", not quoted.

### How lucid-dream research verifies lucidity

The method has barely changed since **LaBerge, Nagel, Dement and Zarcone (1981)**, *"Lucid dreaming verified by volitional communication during REM sleep"* (Perceptual and Motor Skills 52:727–732). Before sleep, the dreamer agrees on an eye-movement signal. When they become lucid in the dream they move their dream eyes, and because the eyes really move in REM sleep, the signal appears on the EOG. In that study, every lucid dream verified by eye signals happened in PSG-scored REM ([summary in Lucidity journal](https://journals.macewan.ca/lucidity/article/download/596/510/1874)).

**Baird, Mota-Rolim and Dresler (2019)**, *"The cognitive neuroscience of lucid dreaming"* (Neuroscience & Biobehavioral Reviews 100:305–323), calls the pre-agreed eye signal the gold standard. Their description of **LRLR**: look all the way left, then all the way right, twice in a row, without pausing. On the **horizontal EOG** it shows as four consecutive full-scale swings, larger than ordinary REMs. Verification relies on convergence: the dream report after waking, the signal on the EOG, and PSG evidence of REM ([PMC6451677](https://pmc.ncbi.nlm.nih.gov/articles/PMC6451677/)).

**Konkoly et al. (2021)**, *"Real-time dialogue between experimenters and dreamers during REM sleep"* (Current Biology 31:1417–1427), ran the same idea in four labs (USA, France, Germany, Netherlands) with 36 participants. Of 57 sessions in REM, 15 (26%) had a signal-verified lucid dream. In 158 attempts to get answers from dreamers, 29 were correct (18%), 5 incorrect, 28 ambiguous and 96 got no response. REM was confirmed by three blind certified scorers; eye/face signals were judged by independent raters. Labs used full lab amplifiers (Neuroscan, BrainAmp) with EOG; the USA lab used LRLRLR, the Dutch lab LRLR, the French lab face-muscle signals ([PMC8162929](https://pmc.ncbi.nlm.nih.gov/articles/PMC8162929/)). The low response rate is a useful reality check: even in good labs, most attempts give nothing usable.

### What a forehead headband can and cannot replace

- **The gold standard for LRLR is a horizontal EOG**: one electrode at each outer canthus (or the AASM E1/E2 pair). Left-right eye movement makes the largest, cleanest signal across this pair because the eyeball is an electrical dipole (cornea positive, retina negative) and the electrodes sit right on its horizontal axis.
- **Muse AF7/AF8** sit on the forehead above and slightly outside the eyes. Horizontal movements do leak into them as large, opposite-polarity deflections, so LRLR is often *visible*. The Muse-S PSG study below confirmed by eye that rapid eye movements are visible in the Muse signal, but did not formally compare it with EOG.
- **What it cannot replace:** a calibrated amplitude (the forehead picks up the eyes at an unknown, head-size-dependent angle), clean separation of horizontal from vertical movement and blinks, chin EMG (needed for proper REM scoring), and acceptance by reviewers. We found **no peer-reviewed study** testing LRLR detection from Muse forehead channels. Any claim that OpenLucid "detects LRLR" from a Muse is something we would need to validate ourselves against EOG.

## 2. Device options

### EEG headbands and research wearables

| Device | Channels and placement | Sees eye movements well? | Data access / SDK | In published research? | Approx. price (source) | Notes |
|---|---|---|---|---|---|---|
| **Muse 2** | 4 dry: TP9, AF7, AF8, TP10; ref. around Fpz; 256 Hz ([Muse Monitor manual](https://musemonitor.com/Technical_Manual.php)) | Partly (AF7/AF8, forehead) | Raw EEG via [muse-lsl](https://github.com/alexandrebarachant/muse-lsl), [BrainFlow](https://brainflow.readthedocs.io/en/stable/SupportedBoards.html) | Yes, many (mostly awake) | ~US$250 ([Particl](https://www.particl.com/company/muse)) | Rigid band, uncomfortable for sleep |
| **Muse S Gen 2** | Same 4 sites in a soft fabric band; 256 Hz | Partly | muse-lsl, BrainFlow | Yes, PSG validation 2025 | ~US$400 (2023 price, [synced.sg](https://synced.sg/blogs/news/muse-s-gen-2-vs-muse-2-a-comprehensive-comparison)); official product page now returns 404, so it may be discontinued | The headband OpenLucid uses |
| **Muse S Athena** | EEG (vendor says 7 sensors) + fNIRS + PPG + IMU; BrainFlow default preset exposes TP9/AF7/AF8/TP10 at 256 Hz | Partly | BrainFlow (new BLE protocol, separate board ID), [OpenMuse](https://github.com/DominiqueMakowski/OpenMuse); muse-lsl not compatible | Little yet | US$474.99 ([choosemuse.com](https://choosemuse.com/products/muse-s-athena)) | Has "Dream Recall" REM-wake feature (beta, Premium) |
| **Hypnodyne ZMax** | 2 EEG: F7-Fpz, F8-Fpz with hydrogel patches; plus PPG, SpO2, IMU, light, sound, temperature ([Hypnodyne](https://hypnodynecorp.com/zmax.php)) | **Good**: F7/F8 sit near the outer canthi | EDF files; TCP socket with example code; works with Dreamento | Yes, several sleep and dream research groups | Not listed (price on request). ~US$900–1,000 per a secondary source ([oneironauts.io, Oct 2026](https://oneironauts.io/blog/best-lucid-dreaming-devices)); electrodes ~€15 each per a user ([blog.kto.to](https://blog.kto.to/hypnodyne-zmax-vs-openbci-eeg-psg)) | Closest thing to a lucid-dream research wearable |
| **OpenBCI Ganglion** | 4 differential channels, 200 Hz | **Good, if you put electrodes at the canthi** | Fully open; BrainFlow | Yes | US$624.99 + dongle; listed **sold out** on 2026-11-01 ([OpenBCI shop](https://shop.openbci.com/products/ganglion-board)) | No electrodes included |
| **OpenBCI Cyton** | 8 differential channels, 250 Hz, TI ADS1299 | **Good, with canthus electrodes** | Fully open; BrainFlow | Yes, widely | US$1,249; listed **sold out** ([OpenBCI shop](https://shop.openbci.com/products/cyton-biosensing-board-8-channel)) | Can do EEG + EOG + chin EMG at once |
| **BrainBit** | 4 dry: O1, O2, T3, T4; 250 Hz | Poorly (no frontal sites) | SDK (Python, C#, C++, Java); BrainFlow | Some | US$499; first gen US$399 sale ([BrainBit store](https://store.brainbit.com/products/brainbit-sdk)) | Headband Pro (8 ch, adds Fp1/Fp2) ~€1,061 ([store](https://store.brainbit.com/en-nl/products/headband-pro)) |
| **Neurosity Crown** | 8: CP3, C3, F5, PO3, PO4, F6, C4, CP4; 256 Hz ([specs](https://neurosity.co/tech-specs)) | Moderately (F5/F6 only) | Raw EEG via SDK ([docs](https://docs.neurosity.co/docs/api/brainwaves)); BrainFlow | A few | Not found officially; third parties quote US$899–1,499 ([outliyr](https://outliyr.com/neurosity-crown), [selfresearch](https://library.selfresearch.org/devices/the-crown-neurosity/)) | Hard frame, not made for sleep |
| **Emotiv Insight** | 5 semi-dry (AF3, AF4, T7, T8, Pz) | Partly | Raw EEG needs a paid EmotivPRO licence (Emotiv's own pages disagree) ([Emotiv KB](https://www.emotiv.com/knowledge-base/is-software-included-when-you-purchase-emotiv-eeg-headset)) | Yes | US$499 ([Emotiv](https://www.emotiv.com/blog/emotiv-headset-price-guide)) | Not designed for sleep |
| **Emotiv EPOC X** | 14 saline (includes F7, F8, AF3, AF4) | Good-ish (F7/F8) | Paid licence for raw data | Yes, widely | US$999 store / US$1,199 in Emotiv's Feb 2026 guide ([guide](https://www.emotiv.com/blog/emotiv-epoc-x-price-guide)) | Saline pads dry out overnight |
| **Emotiv MN8** | In-ear EEG (earbuds) | Poorly | Paid licence | Few | US$399 ([guide](https://www.emotiv.com/blog/emotiv-mn8-price-guide)) | Earbuds |
| **Dreem 3S** (Beacon Biosignals) | Dreem 3S: 6 EEG electrodes ([MedTech Dive](https://www.medtechdive.com/news/beacon-biosignals-fda-clearance-sleep-tracking-headband/693901/)); the validated earlier model used 5 dry: Fpz, F7, F8, O1, O2 at 250 Hz | Good (F7/F8) | Clinical/research only | Yes, PSG-validated | Not sold to consumers; consumer Dreem ended 2021 ([Sleep Review](https://sleepreviewmag.com/sleep-diagnostics/connected-care/remote-monitoring/beacon-biosignals-bolsters-sleep-medicine-research-acquisition-dreem/), [MedTech Dive](https://www.medtechdive.com/news/beacon-biosignals-fda-clearance-sleep-tracking-headband/693901/)) | FDA-cleared; research contracts only |
| **Elemind** | Forehead EEG (count not published) + acoustic stimulation | Unknown | No raw data or API found | Company-linked studies | US$399 incl. membership ([elemindtech.com](https://elemindtech.com/)) | Closed |
| **Somnee** | "EEG+" headband with tACS stimulation | Unknown | No raw data or API found | Company-linked studies | Conflicting: US$499 or a US$99.95 promo ([VCA Online](https://www.vcaonline.com/news/2025061009/somnee-secures-10m-to-revolutionize-sleep-with-new-ai-powered-neurotech-sleep-wearables/)) | Closed |
| **Frenz Brainband** (Earable) | Forehead dry EEG + EOG | Probably good (has EOG) | Raw data/APIs for partners only ([Tom's Guide](https://www.tomsguide.com/wellness/sleep/ces-2025-winner-the-frenz-brainband-helps-you-sleep-faster-and-perform-better)) | Few | US$490–680, sources conflict | Ask Earable about research access |
| **Philips Sleep Headphones with Kokoon** | In-ear "biosensors" | Unknown | None found | No | Discontinued in the US ([Philips](https://www.usa.philips.com/c-p/TAN7808GY_00/sleep-headphones/overview)) | App needs a subscription |
| **iBand+** | 1 dry EEG + LEDs | Unknown | None | No independent evidence | Not sold; crowdfunded 2016, reported failed ([oneironauts.io](https://oneironauts.io/blog/best-lucid-dreaming-devices)) | Avoid |
| **Ambulatory PSG** (SOMNOmedics, Compumedics, Natus) | Full AASM montage incl. EOG and chin EMG | **Reference** | Vendor software, EDF export | The standard | SOMNOscreen plus PSG+ ~€11,800–12,300 incl. VAT ([SOMNOmedics shop](https://shop.somnomedics.de/en/Sleep-Diagnostics/Polysomnography/SOMNOscreen-plus/)); Compumedics Grael and Natus Embla by quote only ([Compumedics](https://www.compumedics.com.au/products/grael-psg)); used Embla units resell for a few hundred US$ ([DOTmed](https://dotmed.com/browse/equipment/neurology/neurology/polysomnograph/embla)) | Plus electrodes, paste and a trained scorer |

### Eye-movement-only options

You do not need a full EEG system to record LRLR. You need **two electrodes at the outer canthi, one reference/ground on the forehead or mastoid, and an amplifier** that can follow slow signals (down to ~0.3 Hz).

- **OpenBCI + disposable electrodes.** One channel of a Ganglion or Cyton, with snap ECG electrodes or gold cup electrodes about 1 cm from each outer canthus, is the cleanest open DIY EOG. Cyton has enough channels to add two forehead EEG channels and chin EMG, which is close to a mini-PSG.
- **BITalino (PLUX).** A Portuguese educational biosignal kit with a dedicated EOG sensor. Board kit ~€149–189, EOG sensor from €25 ([PLUX](https://pluxbiosignals.com/products/bitalino-revolution-board-kit-ble-bt)).
- **AD8232 modules.** Single-lead ECG front ends (SparkFun US$24.41, [SparkFun](https://www.sparkfun.com/sparkfun-single-lead-heart-rate-monitor-ad8232.html)) that hobbyists repurpose for EOG. Its filters are designed for the heart, so slow eye drifts get distorted; fine for a demo, not for validation.
- **ADS1299 boards** (the chip inside Cyton; also PiEEG, FreeEEG32, all in BrainFlow). Good quality, more assembly work. Olimex EEG-SMT: price not checked.
- **Safety note for DIY:** anything wired to your face should be battery-powered and never connected to a mains-powered laptop while charging. Use isolated or battery-only setups.

**Why cameras and normal eye trackers don't work.** Video and infrared eye trackers find the pupil and a corneal reflection. With the eyes closed there is no pupil to see, only the eyelid. Some masks shine infrared at the closed lid and detect the bulge of the moving cornea (REM-Dreamer, older NovaDreamer; research prototypes reach about 80% REM/NREM accuracy ([Smart Eye Mask, ACM 2017](https://unpaywall.org/10.1145%2F3123021.3123061))). Those can show that the eyes are moving, but not reliably which direction, and nothing validated reads LRLR this way. A dark bedroom, a sleeping face that turns into the pillow and covers make it worse.

### Open-source software

- **[Dreamento](https://github.com/dreamento/dreamento)** (MIT): real-time ZMax recording, autoscoring and visual/auditory/tactile cues; offline REM eye-movement detection and manual marking of LRLR ([Esfahani et al. 2023, SoftwareX 24:101595](https://www.sciencedirect.com/science/article/pii/S2352711023002911)).
- **[BrainFlow](https://brainflow.readthedocs.io/en/stable/SupportedBoards.html)**: one API for OpenBCI, Muse 2/S/Athena, BrainBit, Neurosity Crown, Unicorn, FreeEEG, PiEEG and more. Not Emotiv, not ZMax.
- **[muse-lsl](https://github.com/alexandrebarachant/muse-lsl)**: Muse 2, Muse S, Muse 2016 to Lab Streaming Layer. **[OpenMuse](https://github.com/DominiqueMakowski/OpenMuse)** for the Athena.

## 3. Validation evidence

| Device | Study | Result against PSG | Eye movements / REM |
|---|---|---|---|
| **Muse-S** | Lanthier, Robillard et al., *Sleep Advances* 2025, 7(1):zpaf089; 47 adults analysed of 56 ([PMC12782022](https://pmc.ncbi.nlm.nih.gov/articles/PMC12782022/)) | Overall kappa 0.76 (substantial) | REM kappa 0.85, sensitivity 91.5%. REMs "visible" in the signal; no formal EOG comparison. InteraXon lent devices but did not fund the study. 9 of 56 excluded for poor signal |
| **ZMax** | Esfahani, Dresler et al., *bioRxiv* 2023 (preprint; we found no journal version); 135 nights with simultaneous PSG ([bioRxiv](https://www.biorxiv.org/content/10.1101/2023.08.18.553744v1)) | Kappa 0.60 (ZMax's own ZLab scorer) and 0.72 (open DreamentoScorer) | Per-stage REM numbers not checked by us |
| **ZMax** | Wearanize+ dataset, *medRxiv* 2026 ([preprint](https://www.medrxiv.org/content/10.64898/2026.06.01.26354591v1)) | DreamentoScorer more robust than YASA on poor recordings (kappa 0.41 vs 0.33) | Systematically lower band power, blamed on the Fpz reference |
| **Dreem** | Arnal et al., *Sleep* 2020; 25 adults ([PMC7751170](https://pmc.ncbi.nlm.nih.gov/articles/PMC7751170)) | Accuracy 83.5%, kappa 0.75 (experts: 86.4%) | REM kappa 0.79; eye-movement detection not evaluated |
| **Dreem 3** | Six-tracker comparison, 2023 ([PubMed 38087674](https://pubmed.ncbi.nlm.nih.gov/38087674/)) | Best of six; 4-stage kappa 0.76–0.86 | — |

**The gap:** every study above validates **sleep staging**. We found **no published validation of LRLR detection** from any consumer headband against EOG. The best evidence that wearables can carry lucid-dream signals comes from the Dreamento/ZMax work, whose F7/F8 electrodes sit near the canthi. For Muse, this is open territory. That is a weakness and also a publishable gap.

## 4. What this means for OpenLucid

1. **Home tool: Muse S.** Cheap, comfortable enough to sleep in, open data through BrainFlow and muse-lsl, and the one consumer headband with an independent PSG validation of staging (REM kappa 0.85). Its forehead channels give an *approximate* view of eye movements. Present LRLR detection on it as experimental, with a confidence score, never as verified lucidity.
2. **Validation setup: OpenBCI Cyton (or Ganglion) with outer-canthus EOG, worn together with the Muse.** This records the gold-standard horizontal EOG at home and lets us measure how often Muse catches the LRLR signals the EOG sees (sensitivity, false alarms per night). ZMax plus Dreamento is the alternative if we want to match the published Dreamento/ZMax literature. Note that OpenBCI boards showed "sold out" on 2026-11-01.
3. **Reference: full PSG in a sleep lab**, with blind scorers, as in Konkoly et al. This is what a research project or a publication needs, and is best done in partnership with an existing lab rather than by buying equipment.

### Rough budgets (approximate, November 2026)

| Setup | What | Approx. cost |
|---|---|---|
| **Home tinkerer** | Muse S Athena (US$475) or a used/remaining Muse S Gen 2 (~US$400) + laptop/phone + free software | ~US$400–500 |
| **Home tinkerer, EOG only** | BITalino kit + EOG sensor (~€175–215) or AD8232 (~US$25) + disposable electrodes | ~US$50–250 |
| **Validation setup** | Muse S + OpenBCI Cyton (US$1,249) or Ganglion (US$625 + dongle) + electrodes, paste, tape | ~US$1,200–1,900 |
| **Validation, ZMax route** | ZMax (~US$900–1,000, quote needed) + recurring electrodes (~€15 each) | ~US$1,000–1,500 |
| **Lab reference** | Ambulatory PSG (~€6,000–12,300 for the recorder alone) plus sensors, scoring software and a trained scorer; or lab collaboration | €10,000+ to buy; partnership cost varies |

### Honest uncertainties

- ZMax price is not published; the figure is second-hand.
- Muse S Gen 2 may no longer be sold new.
- OpenBCI stock status may be temporary.
- Elemind, Somnee and Frenz do not publish raw-data access for consumers.
- Sampling-rate and electrode-placement rules come from secondary sources, not the AASM manual itself.

## 5. Sources

- https://pmc.ncbi.nlm.nih.gov/articles/PMC4067446
- https://brainscape.com/flashcards/for-poly-test-1-2554079/packs/4475612
- https://sleepdata.org/datasets/cfs/pages/manuals/polysomnography/17-08-03-09-determine-eog.md
- https://www2.tesu.edu/dial/psg/psg102/lectures/Lecture3/Lecture3_print.html
- https://pmc.ncbi.nlm.nih.gov/articles/PMC5705734/table/Tab4
- https://journals.macewan.ca/lucidity/article/download/596/510/1874
- https://pmc.ncbi.nlm.nih.gov/articles/PMC6451677/
- https://pubmed.ncbi.nlm.nih.gov/30880167/
- https://pmc.ncbi.nlm.nih.gov/articles/PMC8162929/
- https://www.frontiersin.org/journals/human-neuroscience/articles/10.3389/fnhum.2020.00259/pdf
- https://musemonitor.com/Technical_Manual.php
- https://github.com/alexandrebarachant/muse-lsl
- https://pypi.org/project/muselsl
- https://brainflow.readthedocs.io/en/stable/SupportedBoards.html
- https://github.com/brainflow-dev/brainflow/pull/829/files
- https://github.com/DominiqueMakowski/OpenMuse
- https://www.particl.com/company/muse
- https://synced.sg/blogs/news/muse-s-gen-2-vs-muse-2-a-comprehensive-comparison
- https://choosemuse.com/products/muse-s-athena
- https://borncity.com/news/muse-dream-recall-eeg-kopfband-weckt-gezielt-in-rem-phase/
- https://hypnodynecorp.com/zmax.php
- https://oneironauts.io/blog/best-lucid-dreaming-devices
- https://blog.kto.to/hypnodyne-zmax-vs-openbci-eeg-psg
- https://shop.openbci.com/products/ganglion-board
- https://shop.openbci.com/products/cyton-biosensing-board-8-channel
- https://store.brainbit.com/products/brainbit-sdk
- https://store.brainbit.com/en-nl/products/headband-pro
- https://neurosity.co/tech-specs
- https://docs.neurosity.co/docs/api/brainwaves
- https://outliyr.com/neurosity-crown
- https://library.selfresearch.org/devices/the-crown-neurosity/
- https://www.emotiv.com/knowledge-base/is-software-included-when-you-purchase-emotiv-eeg-headset
- https://www.emotiv.com/blog/emotiv-headset-price-guide
- https://www.emotiv.com/blog/emotiv-epoc-x-price-guide
- https://www.emotiv.com/blog/emotiv-mn8-price-guide
- https://sleepreviewmag.com/sleep-diagnostics/connected-care/remote-monitoring/beacon-biosignals-bolsters-sleep-medicine-research-acquisition-dreem/
- https://www.medtechdive.com/news/beacon-biosignals-fda-clearance-sleep-tracking-headband/693901/
- https://elemindtech.com/
- https://www.tomsguide.com/wellness/sleep-tech/elemind-sleep-headband
- https://www.vcaonline.com/news/2025061009/somnee-secures-10m-to-revolutionize-sleep-with-new-ai-powered-neurotech-sleep-wearables/
- https://www.tomsguide.com/wellness/sleep/ces-2025-winner-the-frenz-brainband-helps-you-sleep-faster-and-perform-better
- https://www.usa.philips.com/c-p/TAN7808GY_00/sleep-headphones/overview
- https://www.wareable.com/health-and-wellbeing/iband-price-specs-release-date-3221
- https://shop.somnomedics.de/en/Sleep-Diagnostics/Polysomnography/SOMNOscreen-plus/
- https://dotmed.com/browse/equipment/neurology/neurology/polysomnograph/embla
- https://www.compumedics.com.au/products/grael-psg
- https://pluxbiosignals.com/products/bitalino-revolution-board-kit-ble-bt
- https://www.sparkfun.com/sparkfun-single-lead-heart-rate-monitor-ad8232.html
- https://pressrelease.brainproducts.com/eog_actichamp/
- https://unpaywall.org/10.1145%2F3123021.3123061
- https://github.com/dreamento/dreamento
- https://www.sciencedirect.com/science/article/pii/S2352711023002911
- https://pmc.ncbi.nlm.nih.gov/articles/PMC12782022/
- https://www.biorxiv.org/content/10.1101/2023.08.18.553744v1
- https://www.medrxiv.org/content/10.64898/2026.06.01.26354591v1
- https://pmc.ncbi.nlm.nih.gov/articles/PMC7751170
- https://pubmed.ncbi.nlm.nih.gov/38087674/
