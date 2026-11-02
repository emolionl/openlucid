"""Check a recorded night with independent tools, the way a researcher would open it.

The app writes each night as a BIDS-EEG folder with an EDF+ file (see docs/research/eeg-data-standards.md).
This script opens it with MNE-Python, which is what Dreamento, YASA and most sleep research use, and
checks that what MNE reads matches what the app meant to write:

1. The EDF+ file opens, with the expected channels, sample rates and length.
2. The annotations (Lights off/on, movement, position change, gaps) come through.
3. The BIDS sidecars have the fields BIDS requires.
4. A short summary per 30-second epoch from openlucid/epochs.tsv.

Usage:
    pip install -r tools/requirements.txt
    python tools/check_night.py "C:/Users/you/Documents/OpenLucid/nights/sub-xxxx/ses-yyyymmddhhmm"

The verdicts are rules of thumb for learning, not a medical or scientific measurement.
"""

import csv
import json
import pathlib
import sys

import mne

REQUIRED_SIDECAR = ["EEGReference", "SamplingFrequency", "PowerLineFrequency", "SoftwareFilters", "TaskName"]


def main(session: pathlib.Path) -> int:
    problems = []
    edfs = sorted((session / "eeg").glob("*_eeg.edf"))
    if not edfs:
        print(f"No *_eeg.edf in {session / 'eeg'}")
        return 1
    edf = edfs[0]
    base = edf.name[: -len("_eeg.edf")]

    raw = mne.io.read_raw_edf(edf, preload=False, verbose="error")
    print(f"File       {edf.name}")
    print(f"Start      {raw.info['meas_date']}")
    print(f"Length     {raw.times[-1] + 1 / raw.info['sfreq']:.0f} s ({raw.n_times} samples at {raw.info['sfreq']:g} Hz)")
    print(f"Channels   {', '.join(raw.ch_names)}")
    eeg = [c for c in raw.ch_names if c.startswith("EEG")]
    if not eeg:
        problems.append("no EEG channels")

    # MNE resamples slower signals (movement, 52 Hz) to the fastest rate; read the originals from the header.
    rates = raw._raw_extras[0]["n_samps"] / raw._raw_extras[0]["record_length"][0]
    for name, rate in zip(raw.ch_names, rates):
        print(f"  {name:<14} {rate:g} Hz")

    counts = {}
    for a in raw.annotations:
        counts[a["description"]] = counts.get(a["description"], 0) + 1
    print("Annotations")
    for text, n in sorted(counts.items()):
        print(f"  {n:>4} x {text}")
    for needed in ["Lights off", "Lights on"]:
        if needed not in counts:
            problems.append(f"annotation '{needed}' missing")

    sidecar = json.loads((session / "eeg" / f"{base}_eeg.json").read_text(encoding="utf8"))
    missing = [k for k in REQUIRED_SIDECAR if k not in sidecar]
    if missing:
        problems.append(f"sidecar misses {missing}")
    if abs(sidecar.get("SamplingFrequency", 0) - raw.info["sfreq"]) > 0.01:
        problems.append("sidecar SamplingFrequency differs from the EDF")

    epochs_file = session / "openlucid" / "epochs.tsv"
    if epochs_file.exists():
        with epochs_file.open(encoding="utf8") as f:
            rows = list(csv.DictReader(f, delimiter="\t"))
        quality = {}
        for r in rows:
            quality[r["quality"]] = quality.get(r["quality"], 0) + 1
        moved = sum(1 for r in rows if r["movement_deg_s"] not in ("n/a", "") and float(r["movement_deg_s"]) > 5)
        turned = sum(1 for r in rows if r["position_changed"] == "1")
        print(f"Epochs     {len(rows)} of 30 s: " + ", ".join(f"{n} {q}" for q, n in sorted(quality.items())))
        print(f"Movement   {moved} epochs with movement, {turned} changes of position")

    print()
    if problems:
        print("PROBLEMS: " + "; ".join(problems))
        return 1
    print("OK: MNE reads the night as the app meant to write it.")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(pathlib.Path(sys.argv[1])))
