---
title: "How sleep EEG is saved: Dreamento and the standards"
date: 2026-11-01
description: "How the Dreamento toolbox stores recordings, markers and hypnograms, which standards sleep research uses (EDF+, AASM, BIDS-EEG), and exactly how OpenLucid will save a night so it fits in."
outcome: "Decision"
tldr:
  - "Sleep research exchanges recordings as EDF/EDF+ files; hypnograms use AASM stages (W, N1, N2, N3, R) in 30-second epochs."
  - "Research datasets are organised with BIDS-EEG: a fixed folder layout, file names, and small JSON/TSV files describing the recording."
  - "Dreamento uses EDF (one file per signal from the ZMax), CSV for live recordings, a JSON marker file and a text hypnogram with numeric codes."
  - "OpenLucid will save each night as BIDS-EEG with one EDF+ file, plus a Dreamento-compatible export."
---

> Educational, not medical advice. Standards were checked on 1 November 2026; links are at the bottom.

## Why this matters

If OpenLucid invents its own file format, nobody else's tools can open our nights, and our nights can't be compared with published research. If we save the way sleep research does, a night recorded at home can be opened in Dreamento, YASA, MNE-Python, EDFbrowser or a sleep lab's software, and a dataset can be shared in the format reviewers expect.

## How Dreamento saves data

[Dreamento](https://github.com/dreamento/dreamento) (open source, MIT) records from the Hypnodyne ZMax headband. Reading its code shows five kinds of files:

| What | Format | Details |
|---|---|---|
| Raw ZMax recording | `.hyp` (Hypnodyne's own) | Converted by Hypnodyne's `HDRecorder.exe -conv` (Dreamento's `DreamentoConverter.py` automates this) |
| Converted signals | **EDF, one file per signal** | `EEG L.edf`, `EEG R.edf` (forehead EEG, F7/F8 against Fpz), `dX.edf`, `dY.edf`, `dZ.edf` (movement), `OXY_IR_AC.edf` (PPG), `NOISE.edf`, and more. Dreamento's offline tools open these with MNE (`mne.io.read_raw_edf`) |
| Live recording | CSV text | Dreamento's real-time app writes the samples with `numpy.savetxt(..., delimiter=',')` |
| Markers and cues | JSON, `<name>-markers.json` | One entry per light, sound, text-to-speech cue or manual marker, keyed by its sample number and second |
| Hypnogram | Text, one number per 30-second epoch | Header line says the code: `Wake:0, N1:1, N2:2, SWS:3, REM:4`. Live predictions go to `<name>-predictions.txt`; sleep statistics to a JSON file |

Lab recordings that Dreamento analyses next to the ZMax (for example EMG) come in the **BrainVision** format (`.vhdr`, `.vmrk`, `.eeg`), and its analysis scripts expect a `participant\session\eeg\` folder structure.

**One thing to learn from:** inside Dreamento, the scorer writes REM as `4`, while a statistics function defaults to `[0, 1, 2, 3, 5]` (REM as `5`, an older convention). Numbers without a written mapping are a classic source of bugs. Always store the stage as text, or write the mapping into the file.

## The standards of the field

### EDF and EDF+: the file format

The **European Data Format** (Kemp et al., 1992) is the common exchange format for sleep recordings; **EDF+** (Kemp & Olivan, 2003) adds annotations and discontinuous recordings. Almost every sleep tool reads it.

- A header (patient and recording identification, start date and time, one block per signal: label, physical unit, physical and digital minimum and maximum, sampling rate), then the samples as **16-bit integers**, scaled to physical units with each signal's min/max.
- Signal labels are written as `type position-reference`, for example `EEG Fpz-Cz`, with the unit `uV`.
- **Annotations** live in a special signal called `EDF Annotations`, as time-stamped text (onset in seconds from the start, optional duration, text). A hypnogram is a list of such annotations.
- **Standard texts** exist for sleep scoring. For AASM scoring: `Sleep stage W`, `Sleep stage N1`, `Sleep stage N2`, `Sleep stage N3`, `Sleep stage R`, `Sleep stage ?` (unknown). The older stages 1–4 must not be used when scoring by AASM rules. Also: `Lights off`, `Lights on`, `EEG arousal`. There is **no standard text for an eye signal**, so we define our own and document it.
- The patient field can be anonymous (`X` for every unknown subfield). We never put names or emails in it.

Public datasets use exactly this: the [Sleep-EDF database](https://physionet.org/content/sleep-edfx/1.0.0/) stores recordings as EDF and hypnograms as EDF+.

### AASM scoring: the stages

The American Academy of Sleep Medicine scoring rules split a night into **30-second epochs**, each scored as **W, N1, N2, N3 or R**; an epoch gets the stage that fills most of it (at least 15 seconds). Numeric codes are **not** standardised: YASA uses `W=0, N1=1, N2=2, N3=3, R=4`, so does Dreamento's scorer, while older files use 5 for REM.

### BIDS-EEG: how a dataset is organised

The **Brain Imaging Data Structure** for EEG ([specification](https://bids-specification.readthedocs.io/en/stable/modality-specific-files/electroencephalography.html)) is how research datasets are shared. It fixes:

- **Folders and names:** `sub-<label>/[ses-<label>/]eeg/sub-<label>[_ses-<label>]_task-<label>[_run-<index>]_eeg.<ext>`.
- **Formats:** EDF (`.edf`, EDF+ allowed) and BrainVision are recommended; EEGLAB and BDF are allowed.
- **A JSON sidecar** (`*_eeg.json`) with REQUIRED fields `EEGReference`, `SamplingFrequency`, `PowerLineFrequency`, `SoftwareFilters` and `TaskName`, and recommended ones such as `Manufacturer`, `ManufacturersModelName`, `RecordingDuration`, `RecordingType`, `EEGChannelCount`, `EOGChannelCount`, `EEGPlacementScheme`.
- **A channels table** (`*_channels.tsv`) with the columns `name`, `type`, `units` first (types include `EEG`, `EOG`, `HEOG`, `VEOG`, `EMG`), and optional ones such as `reference` and `status`.
- **An events table** (`*_events.tsv`) for things that happen during the recording.

### Electrode names

Electrode positions follow the international **10-20 system** (and its 10-10 extension): the Muse sensors are TP9, AF7, AF8 and TP10, referenced to Fpz.

## How OpenLucid will save a night

This is binding for checkpoint 03 (recording a whole night).

**1. One BIDS-EEG folder per night**, inside the user's data:

```text
sub-<random id>/ses-<YYYYMMDD>/eeg/
  sub-…_ses-…_task-sleep_eeg.edf        EDF+ (continuous), all channels in one file
  sub-…_ses-…_task-sleep_eeg.json       sidecar: required BIDS fields + device info
  sub-…_ses-…_task-sleep_channels.tsv   name, type, units, reference, status
  sub-…_ses-…_task-sleep_events.tsv     onset, duration, trial_type, value
```

- The subject label is a random id, never a name or email.
- **EDF+ details:** one signal per sensor, labelled `EEG TP9-Fpz`, `EEG AF7-Fpz`, `EEG AF8-Fpz`, `EEG TP10-Fpz`, unit `uV`, 256 Hz. The Muse's full range (about ±1000 µV) becomes the physical minimum and maximum, so no value is clipped. The patient field is anonymous (`X X X X`).
- **Annotations in the EDF+ file:** the hypnogram as AASM texts (`Sleep stage W` … `Sleep stage R`, `Sleep stage ?`), `Lights off` and `Lights on` at the start and end of the night, and our own events with documented texts: `OpenLucid cue`, `OpenLucid LRLR`, `OpenLucid marker`, `OpenLucid contact lost`, `OpenLucid reconnect`.
- **Sidecar:** `TaskName: "sleep"`, `SamplingFrequency: 256`, `PowerLineFrequency` from the app's 50/60 Hz setting, `EEGReference: "Fpz"`, `SoftwareFilters: "n/a"` (we store raw data), `Manufacturer: "InteraXon"`, `ManufacturersModelName` (e.g. `"Muse S Gen 2 (MS-02)"`), `RecordingType: "continuous"`, `EEGPlacementScheme: "10-20 subset: TP9, AF7, AF8, TP10"`, `EEGChannelCount: 4`.
- **Channels table:** `status` is `good` or `bad` from the contact score over the whole night.

**2. The same events as a table** (`events.tsv`, with `onset` in seconds), so they're readable without an EDF reader.

**3. A hypnogram text file** next to it, one stage per 30-second epoch, with the mapping written in the header (`W=0, N1=1, N2=2, N3=3, R=4`, the YASA and Dreamento convention), so Dreamento and YASA can use it directly.

**4. A Dreamento-compatible export:** `EEG L.edf` (AF7) and `EEG R.edf` (AF8), one signal per file like the ZMax, so Dreamento's offline tools can open an OpenLucid night. This is an approximation: the ZMax measures F7/F8, the Muse AF7/AF8, both against Fpz.

**What stays out of these files:** the raw Bluetooth captures (`raw-*.csv`) remain a debugging tool only.

## Sources

- Dreamento source code: <https://github.com/dreamento/dreamento> (`DreamentoConverter.py`, `mainWindow.py`, `OfflineDreamento.py`, `Dreamento_from_conversion_to_scoring.py`)
- Jafarzadeh Esfahani et al. (2023), *Dreamento: an open-source dream engineering toolbox*, SoftwareX 24:101595
- EDF+ specification: <https://edfplus.info/specs/edfplus.html>; standard texts: <https://edfplus.info/specs/edftexts.html>; Kemp & Olivan (2003), Clinical Neurophysiology 114:1755–1761; Kemp et al. (1992), Electroencephalography and Clinical Neurophysiology 82:391–393
- Sleep-EDF database (EDF recordings, EDF+ hypnograms): <https://physionet.org/content/sleep-edfx/1.0.0/>
- AASM scoring summary (30-second epochs, W/N1/N2/N3/R, majority rule): <https://isr.aasm.org/help/GeneralInstructions.html>
- BIDS-EEG specification: <https://bids-specification.readthedocs.io/en/stable/modality-specific-files/electroencephalography.html>; Pernet et al. (2019), *EEG-BIDS*, Scientific Data 6:103
- YASA hypnogram conventions: <https://raphaelvallat.com/yasa/>
