"""Check a raw Muse capture, independently of the app.

The app's "Save 10 s raw data" button writes every Bluetooth notification exactly as it arrived:

    ms,channel,hex        (channel -1 = control, 0..3 = TP9, AF7, AF8, TP10)

This script decodes those bytes itself and answers three questions:

1. Did the data arrive intact?    (packet sizes, counters without gaps)
2. Is the decoding right?         (no extra jumps exactly at packet boundaries)
3. Is each sensor touching skin?  (stuck at the limits, mains hum, channels that look identical)

Usage:
    pip install numpy
    python tools/analyze_raw_muse.py raw-2026-11-01T14-47-45.csv

The verdicts are rules of thumb for learning, not a medical or scientific measurement.
"""

import collections
import csv
import sys

import numpy as np

FS = 256  # samples per second per channel
NAMES = {-1: "control", 0: "TP9", 1: "AF7", 2: "AF8", 3: "TP10"}
WHERE = {"TP9": "behind the left ear", "AF7": "left forehead", "AF8": "right forehead", "TP10": "behind the right ear"}


def decode(packet: bytes):
    """A 20-byte Muse EEG packet: 2-byte counter, then twelve 12-bit samples."""
    counter = (packet[0] << 8) | packet[1]
    samples = []
    for i in range(2, 20, 3):
        samples.append((packet[i] << 4) | (packet[i + 1] >> 4))
        samples.append(((packet[i + 1] & 0x0F) << 8) | packet[i + 2])
    return counter, samples


def band_share(x, low, high):
    """Fraction of the signal's power between low and high Hz."""
    spectrum = np.abs(np.fft.rfft((x - x.mean()) * np.hanning(len(x)))) ** 2
    freqs = np.fft.rfftfreq(len(x), 1 / FS)
    total = spectrum[freqs > 0.5].sum()
    return spectrum[(freqs >= low) & (freqs <= high)].sum() / total if total else 0


def main(path):
    rows = list(csv.DictReader(open(path)))
    by_channel = collections.defaultdict(list)
    for row in rows:
        by_channel[int(row["channel"])].append(bytes.fromhex(row["hex"]))

    if -1 in by_channel:
        text = "".join(b[1 : 1 + b[0]].decode("ascii", "replace") for b in by_channel[-1] if b)
        print(f"Muse status reply: {text}\n")

    signals = {}
    by_counter = {}
    print("1. Did the data arrive intact?")
    for ch in range(4):
        packets = by_channel.get(ch, [])
        sizes = collections.Counter(len(p) for p in packets)
        decoded = [decode(p) for p in packets if len(p) == 20]
        counters = np.array([c for c, _ in decoded])
        gaps = int(np.sum((np.diff(counters) % 65536) != 1)) if len(counters) > 1 else 0
        print(f"   {NAMES[ch]:5} {len(packets)} packets, sizes {dict(sizes)}, counter gaps {gaps}")
        raw = np.array([s for _, samples in decoded for s in samples], dtype=float)
        signals[NAMES[ch]] = raw
        by_counter[NAMES[ch]] = dict(decoded)

    print("\n2. Is the decoding right?")
    for name, raw in signals.items():
        uv = 0.48828125 * (raw - 2048)
        steps = np.abs(np.diff(uv))
        at_edges = steps[11::12].mean()
        inside = np.delete(steps, np.s_[11::12]).mean()
        verdict = "ok" if at_edges < 1.5 * inside + 5 else "SUSPICIOUS: jumps at packet boundaries"
        print(f"   {name:5} typical step inside packets {inside:6.1f} uV, at boundaries {at_edges:6.1f} uV  -> {verdict}")

    print("\n3. Is each sensor touching skin?")
    # Compare channels sample by sample, using only packets that every channel received.
    names = list(signals)
    shared = sorted(set.intersection(*(set(by_counter[n]) for n in names)))
    aligned = np.array([[v for c in shared for v in by_counter[n][c]] for n in names], dtype=float)
    matrix = np.corrcoef(aligned)
    for i, name in enumerate(names):
        raw = signals[name]
        uv = 0.48828125 * (raw - 2048)
        railed = np.mean((raw <= 0) | (raw >= 4095)) * 100
        mains = (band_share(uv, 48, 52) + band_share(uv, 98, 102)) * 100
        alpha = band_share(uv, 8, 12) * 100
        # The Muse sends 12 samples per Bluetooth packet, 21.3 packets per second. A floating input picks up
        # the headband's own radio bursts at exactly that rate.
        packet_rate = band_share(uv, 20.8, 21.8) * 100
        fast = band_share(uv, 60, 128) * 100
        twins = [names[j] for j in range(len(names)) if j != i and matrix[i, j] > 0.9]
        if mains > 20 and (railed > 5 or mains > 50):
            verdict = "NO CONTACT: the sensor is an antenna for the mains hum"
        elif railed > 5 and (fast > 20 or packet_rate > 3):
            verdict = "NO CONTACT: a floating input, picking up the headband's own radio (21.3 Hz) and fast noise"
        elif railed > 5:
            verdict = "SETTLING: little hum, but a big slow drift pushes it off the scale; contact is forming"
        elif twins:
            verdict = "SUSPICIOUS: almost identical to " + ", ".join(twins)
        else:
            verdict = "touching skin"
        print(f"   {name:5} ({WHERE[name]})")
        print(f"         stuck at the limits {railed:5.1f}%   mains hum {mains:5.1f}%   radio 21.3 Hz {packet_rate:5.1f}%   above 60 Hz {fast:5.1f}%   alpha 8-12 Hz {alpha:5.1f}%")
        if twins:
            print(f"         looks identical to: {', '.join(twins)} (sensors in different places should not match)")
        print(f"         -> {verdict}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
