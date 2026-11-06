---
title: "11. From signal to sleep stage"
description: "What a classifier actually does when OpenLucid (or the lab tools it builds on) decides you're probably dreaming — in plain language first, the code second."
weight: 11
tldr:
  - "A classifier turns one 30-second slice of raw EEG into a label (Wake/N1/N2/N3/REM) plus a confidence number — it never just 'sees' sleep stages the way a person scoring a chart does."
  - "Three different Donders-lab tools do three different jobs here, and it's easy to conflate them: YASA stages (OpenLucid's own planned approach), DreamentoScorer and ezscore-f also stage but are tuned to different hardware, and eegFloss doesn't stage at all — it screens whether a recording is clean enough to trust first."
  - "None of this is wired into OpenLucid today. Staging is a planned checkpoint; integrating and extending the lab's own classifiers is a later, separate PhD-stage plan."
---

> Educational, not medical advice.

## Do you need this chapter?

No — not to just use OpenLucid. The app is meant to make this call for you and tell you in plain terms ("you're probably dreaming now"), the same way it already aims to for signal quality. Skip this one and come back if you're curious, or if you want to help build the staging feature itself.

This chapter is for people who want to understand *how* that call gets made — or eventually help make it. The first two sections are plain language, no code. The last section ("Going deeper") is for people planning to touch the actual training code; it's clearly marked so you know exactly where to stop.

## The four-step pipeline, in plain language

However it's built, an automatic sleep-stage classifier always does the same four things to a recording:

1. **Cut it into epochs.** The whole night gets chopped into fixed 30-second slices — the standard unit sleep has been scored in since the field's original scoring manual. A classifier never looks at "the whole night" at once; it judges one slice at a time.
2. **Turn each slice into numbers.** Raw EEG voltage isn't fed to the classifier directly. Each epoch gets reduced to a set of **features** — things like how much power is in different frequency bands (slow delta waves vs. faster alpha/beta), how irregular or "entropic" the signal is, and similar time- and frequency-domain statistics. This is the same idea as [the trace-reading chapter](reading-a-sleep-trace-real-event-or-artifact.md)'s "does it look like REM, together" — just computed as numbers instead of judged by eye.
3. **Pick which numbers actually matter.** Not every feature is useful, and some are redundant with each other. A feature-selection step narrows a large candidate list down to the ones that actually carry information about sleep stage, before training even starts.
4. **Classify.** A trained model takes that epoch's selected features and outputs a stage label, plus — in the better tools — a confidence per possible stage (a "hypnodensity"), not just a single hard answer. Low confidence on a given epoch is itself useful information: it's the model telling you it isn't sure.

That's it. Everything else is detail about *which* features, *which* model, and *what data* it was trained on — which is where the different tools stop being interchangeable.

## Three different tools, three different jobs

The proposal behind OpenLucid's research phase name-checks several Donders-lab tools together, which makes it easy to assume they're all "the sleep-staging model." They're not — they split into two genuinely different jobs, and mixing them up leads to wrong expectations about what each one can tell you.

**Staging — deciding what stage an epoch is:**

- **YASA** — a general-purpose, independently validated automatic sleep-staging algorithm (not built by the Dreamento/Donders team specifically). This is what OpenLucid itself plans to use for its own staging — currently a **planned**, not yet built, checkpoint.
- **DreamentoScorer** — the Dreamento toolbox's own classifier, built specifically for its ZMax headband recordings. It uses a LightGBM model, trained on the lab's own pooled dataset (reportedly over 130 nights), and reports hypnodensity, not just a hard label.
- **ezscore-f** — a newer, separately published set of classifiers (2025, not yet peer-reviewed) built specifically for *forehead* EEG, because a model trained on standard scalp PSG electrode placement doesn't transfer well to a forehead-only headband. It ships a real-time variant and a separate offline variant, trained on two named datasets (*Wearanize+* and *Donders2022*).

**Quality screening — deciding whether an epoch is trustworthy enough to stage at all:**

- **eegFloss** — this is not a stage classifier. It's an artifact/usability filter (its model is called *eegUsability*) that flags which channel-epochs are too contaminated to trust, plus a second model (*eegMobility*) for detecting time-in-bed. It was trained on 15 participants over 127 nights of labelled ZMax data.

Why the distinction matters in practice: a "research-usable" recording, in the plan this chapter connects to, means passing *both* kinds of check — enough epochs surviving eegFloss's quality screen, *and* being scorable by a staging classifier like ezscore-f above a set confidence threshold. One without the other isn't enough: a perfectly clean recording a classifier can't confidently stage isn't usable, and neither is a confidently-staged recording built on contaminated data.

## Where OpenLucid actually fits today

None of this is live in OpenLucid yet. Two separate things are true at once, and it's worth keeping them apart:

- OpenLucid's own staging (the "Sleep staging with YASA" item on [the roadmap](https://github.com/emolionl/openlucid#roadmap)) is **planned**, not built — this chapter has no hands-on lab with real OpenLucid staging data yet because that data doesn't exist yet.
- Going further — integrating and then training/extending the lab's own ezscore-f/eegFloss pipeline on newly pooled volunteer recordings, rather than building a new model architecture — is a later-stage plan tied to a specific research phase, not a near-term OpenLucid feature.

When OpenLucid's own staging checkpoint lands, this chapter gets a real hands-on lab section using actual recorded data, and chapter 12 ("Connecting it to OpenLucid's own code," not yet written) becomes writable.

---

## Going deeper (optional, code-level — for contributors)

Everything above is enough to understand what a classifier does. This section is for people who want the actual recipe — precise enough to use as a starting point for training something yourself, not just a description of the result. All three tools below were read from their own primary source (the code itself, or the full paper text), not from an abstract or a secondary summary.

### DreamentoScorer — classical ML, hand-built features

Reading Dreamento's own `DreamentoScorer.py` directly (it's open source) shows the training pipeline is ordinary, readable scikit-learn/LightGBM code, not a black box:

- **Feature selection** uses the Boruta algorithm (`BorutaPy`, wrapping a random forest) to decide which extracted features are actually informative before training the real classifier.
- **Training** tries several classifier families in the code (random forest, SVM, XGBoost, even some commented-out deep-learning experiments) but the one actually shipped is **LightGBM**, tuned with `RandomizedSearchCV` for hyperparameters.
- **What ships vs. what doesn't:** the repository includes the trained model files (`.sav`/`.pickle`) and the training *code*, but not the raw training recordings themselves — real participant sleep-EEG data, which isn't something a lab publishes raw. You can read and re-run the exact training procedure; you can't reproduce it from scratch without your own recordings or a data-sharing agreement with the lab.

### eegUsability (eegFloss) — also classical ML, fully specified end to end

This is the most completely documented of the three — the paper itself (Sikder et al. 2025) lays out the whole pipeline as a numbered recipe:

- **Input:** one EEG channel plus tri-axial accelerometer (ACC) from a Zmax headband, 256 Hz. The three ACC axes are first collapsed into one "movement magnitude" signal (Euclidean norm of X/Y/Z), so each sample is really two signals: EEG and movement.
- **Epoch length:** 10 seconds, not the usual 30 — chosen specifically because the hardest artifact to catch ("M-shaped noise") has a roughly 4-second period, and a shorter window risked missing a full cycle of it.
- **Labels (5 classes):** 0 = usable/good data, 1 = no data (flat line, disconnected electrode), 2 = high noise, 3 = spiky (high-frequency, low-amplitude) noise, 4 = M-shaped periodic noise — labelled by visually inspecting the bandpass-filtered (0.3–30 Hz) signal, its spectrogram, and the ACC trace together, with a defined tie-breaking rule for windows that straddled more than one artifact type.
- **Training data:** 181 nights from 15 participants (the *Donders2022* dataset — the same one ezscore-f partly uses below) — about 1 million 10-second samples before any balancing.
- **Class balancing:** usable data was over 82% of all samples, which would bias a classifier toward always predicting "usable." Fixed in two steps: first, 54 of the 181 recordings with no noise at all were dropped; second, after a subject-wise train/test split (10 subjects train, 5 test — chosen to preserve each class's ratio while keeping any one subject's data out of both sets), Class 0 was randomly undersampled within each split until usable data was ~50% of the set, ~25% No Data, and the rest split across the other three classes.
- **Feature extraction — two families, concatenated:**
  - *Spectrogram features:* an FFT-based spectrogram of each 10-second epoch (256 Hz × 10 s = 2,560 samples → an 11×129 time–frequency grid), flattened and computed for both EEG and the ACC-magnitude signal — 2,838 features.
  - *TSFEL features:* the open-source Time Series Feature Extraction Library (v0.1.4) run on both signals — 390 statistical/temporal/spectral features per signal, 780 total.
  - Combined: **3,618 features per 10-second sample.**
- **Model:** LightGBM (gradient-boosted decision trees, leaf-wise growth), trained with categorical cross-entropy loss and a softmax output over the 5 classes. Regularization: 80% of features sampled per tree, 70% of training rows resampled every 10 iterations, learning rate η = 0.01.
- **Reported performance (held-out test subjects):** weighted F1 = 84.87%, precision = 84.98%, recall = 86.01%, AUC = 0.96, Cohen's κ = 0.78. Usable data and No Data score well (recall 93.55% / 94.03%); the weak point is M-shaped noise, caught only 29% of the time and most often mistaken for usable data — the paper names this openly as the model's hardest case, not something it glosses over.

### ezscore-f — deep learning, end to end on the raw signal

Architecturally a different animal — a hybrid CNN + transformer + recurrent network, not a feature-engineered tree model:

- **Input:** two forehead EEG channels from a Zmax headband, 256 Hz, high-pass filtered at 0.5 Hz and downsampled to 64 Hz. Two preprocessing variants exist — real-time (raw µV amplitudes) and offline (median/IQR-normalized, clipped at ±20× the IQR).
- **Architecture, in order:**
  1. A **CNN front end** extracts spatiotemporal and frequency-domain features directly from each 30-second epoch — no hand-built feature list; the network learns what to extract.
  2. Two **parallel transformer encoder stacks** both read the CNN's output: one ends in max-pooling (tuned to catch brief transients like K-complexes and spindles), the other in average-pooling (tuned to catch steady trends like slow waves). Their outputs are concatenated.
  3. A **bidirectional LSTM** looks across a 100-epoch (50-minute) window of that combined representation, so the call on one epoch is informed by what came before and after it, not just that one slice. At inference it can still run on as little as a single epoch if that's all that's available.
  4. Output: 5 sleep stages (Wake/N1/N2/N3/REM), or 6 classes in the variant that also flags artifact epochs directly.
- **Artifact labels for training** came from simple epoch-level metrics (mean/median amplitude, Hjorth parameters), with a fixed rule: epochs with mean amplitude under 1.4 µV or over 200 µV were marked artifact.
- **Training data:** 160 overnight recordings with concurrent PSG — *Wearanize+* (96) and *Donders2022* (64) — expert-scored per standard AASM sleep-staging guidelines.
- **Training setup:** categorical cross-entropy loss, Adam optimizer, 100 epochs, learning rate 0.001 dropped to 0.0001 after epoch 8, a 90/10 train/test split. Built in Python 3.10 with TensorFlow 2.13 and Keras-NLP 0.9.3.
- **Reported performance:** cross-device generalization was tested by applying the ZMax-trained model, with no retraining, to a different headband (DCM) — 76.4% ± 0.2% accuracy, κ = 0.65. The authors flag class imbalance (especially N1, the stage human scorers also agree on least) as an open limitation, and name oversampling or an imbalance-aware loss as future work, not something already solved.

### If you actually wanted to build one

The two working, published recipes above point in genuinely different directions, not variations on the same idea:

- **The classical route** (DreamentoScorer, eegUsability): hand-built features (spectrograms, TSFEL's statistical/temporal/spectral set, or both) feeding a gradient-boosted tree model like LightGBM. Needs far less data to get working — eegUsability's entire training set is 15 people — trains in minutes to hours on an ordinary CPU, and the resulting model and its feature importances are inspectable, not a black box. This is the realistic starting point for extending an existing pipeline on a modest, newly-collected volunteer dataset — which is exactly what this project's own plan already commits to.
- **The deep-learning route** (ezscore-f): no hand-built features — a CNN learns them directly from the signal, then a transformer+LSTM stack reasons across a 50-minute window of context. This needs an order of magnitude more labelled data (160 full nights, all with concurrent PSG as ground truth — not something collected casually), a GPU to train in reasonable time, and real deep-learning engineering (TensorFlow/Keras, not scikit-learn). A legitimate, working, published approach — just a much bigger undertaking, and not what this project is scoped to attempt.

Both are real, both are published with real numbers to beat, and now it's clear exactly which one you'd actually be signing up for.

This is also the honest boundary OpenLucid's own curriculum plan draws for students: understanding *what* a model like this does and *which* choices (features, hyperparameters) actually matter, well enough to test and trust a result — without needing to derive the underlying math. Contributing actual training code is opt-in, for people who want to go further, not assumed of everyone reading this chapter.

## Done when

You can explain, without looking anything up: the four-step pipeline (epoch → features → feature selection → classifier), and correctly say which of YASA / DreamentoScorer / ezscore-f / eegFloss actually assigns a sleep stage versus which one only screens data quality. If you've read "Going deeper" too: you can say, for any of the three named models, whether it's a classical feature-engineered model or an end-to-end deep-learning one, and roughly what data and compute each would cost you to redo.

## What this doesn't show

- No hands-on lab with real data yet — OpenLucid's own staging checkpoint hasn't landed.
- ezscore-f and eegFloss are both preprints as of writing, not yet peer-reviewed; described here as what their authors report, not as settled, certified findings. The "Going deeper" architecture and pipeline details were read directly from each paper's full text (not an abstract or secondary summary), but the reported performance numbers themselves are the authors' own, not independently reproduced here.
- None of the three models' raw training data is available to us — only the trained model files (DreamentoScorer) or the published description of the pipeline (eegUsability, ezscore-f). You could re-run DreamentoScorer's exact training code today; reproducing eegUsability or ezscore-f from scratch means collecting and labelling your own dataset at a similar scale, or getting a data-sharing agreement with the lab.
- This chapter describes the tools as published. Nothing here is a commitment about which of them OpenLucid ends up using, or how — that's decided jointly with the lab as the relevant research phase actually starts.

## Sources

- Jafarzadeh Esfahani, Daraie, Zerr, Weber and Dresler (2023), *Dreamento: An open-source dream engineering toolbox for sleep EEG wearables*, SoftwareX 24:101595: <https://doi.org/10.1016/j.softx.2023.101595>
- Jafarzadeh Esfahani, Weber, Boon, Anthes, Almazova, van Hal et al. (2023), *Validation of the sleep EEG headband ZMax*, bioRxiv 2023-08: <https://doi.org/10.1101/2023.08.18.553744>
- Coon, Zerr, Milsap, Sikder, Smith, Dresler and Reid (2025), *ezscore-f: A Set of Freely Available, Validated Sleep Stage Classifiers for Forehead EEG*, bioRxiv preprint, DOI 10.1101/2025.06.02.657451 — architecture and training details read from the full preprint text: <https://www.biorxiv.org/content/10.1101/2025.06.02.657451v1.full>
- Sikder, Zerr, Jafarzadeh Esfahani, Dresler and Krauledat (2025), *eegFloss: A Python package for refining sleep EEG recordings using machine learning models*, arXiv:2507.06433 — architecture, feature list and hyperparameters read from the full paper text: <https://arxiv.org/pdf/2507.06433>
- Vallat and Walker (2021), *An open-source, high-performance tool for automated sleep staging*, eLife 10:e70092 (YASA): <https://doi.org/10.7554/eLife.70092>
- Dreamento source code, `DreamentoScorer/DreamentoScorer.py` (feature selection and training pipeline read directly, not from secondary description): <https://github.com/dreamento/dreamento>
- eegFloss source code and model variants: <https://github.com/Niloy333/eegFloss>
