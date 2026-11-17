# Desktop / phone app (Flutter)

The app you take to bed, so to speak: it connects to an EEG headband, shows the live signal, sends every 30 seconds of EEG to the Diary Keeper, and plays the sound cue.

## Start it

1. Start the backend first (see `../../backend/README.md`).
2. From this folder:

```bash
flutter pub get
flutter run -d windows
```

(Use `-d android` with a phone connected, or `-d macos` / `-d linux`.)

3. Press **Wave at the Diary Keeper**. If it answers "The Diary Keeper is awake.", checkpoint 00 is done.
4. Pick **Fake Moose** and press **Start listening**: four wiggly lines should scroll by, with a big slow bump on AF7/AF8 now and then (a simulated blink).
5. Got a Muse? Switch it on, pick **Muse**, press **Find my Muse** and tap it in the list. Same four lines, but now they're yours. Blink, clench your jaw, look left and right, and watch what happens.

On a phone, `localhost` is the phone itself: change `diaryKeeperUrl` in `lib/main.dart` to your laptop's IP address and start the backend with `--host 0.0.0.0`.

## Supported devices

| Device | Status | How it connects |
|---|---|---|
| Fake Moose (simulation) | ✅ | Built in: no hardware needed |
| Muse 2016, Muse 2, Muse S | ✅ first version, needs testing on each model | Bluetooth Low Energy |
| Other headbands (OpenBCI, ZMax, BrainBit, ...) | Wanted: see below | |
| Fake Heart (simulation) | ✅ | Built in: a simulated heart-rate strap |
| Polar H10 chest strap (or any strap with standard Bluetooth heart rate) | ✅ first version, needs testing | Bluetooth Low Energy, next to the headband |

## Heart rate and HRV (Polar H10)

Optional, next to the headband: on the Tonight screen, **Heart (optional)** → **Polar H10** → **Find my strap**. Wet the electrodes and wear the strap first: a Polar H10 only wakes up on skin. Or pick **Fake Heart** to try it without one.

The app reads the strap's standard Heart Rate service (heart rate and every beat-to-beat RR interval, like the mybliss-hrv app), not Polar's own protocol, so it also works with other straps. Raw ECG is not recorded.

While a night is recorded, every beat goes into the night folder:

- `openlucid/heartbeats.tsv`: onset (s since the start of the night), RR interval (ms), the strap's heart rate, whether the beat counts for HRV, and skin contact. Described in `heartbeats.json`.
- `openlucid/epochs.tsv`: per 30-second epoch, heart rate, HRV (RMSSD and SDNN, ms) and how many beats were clean.

Artifacts (a missed or extra beat, a moving strap) would make HRV look much higher than it is, so intervals outside 300-2000 ms, or more than 20% different from the previous clean one, are kept in the file but left out of the numbers (`lib/heart/hrv.dart`). An epoch needs 10 clean beats for HRV. The strap can be connected, lost and reconnected during the night; each of those is an event in the night.

## Sending nights to the Diary Keeper

In **Settings → Diary Keeper**, sign in (or create an account; the first account on a new Diary Keeper becomes its admin). With **Send every night after it is saved** on, each night goes to the Diary Keeper as soon as you stop it; older nights have a cloud button in the **Nights** tab. The night stays on this device either way.

What is sent (`lib/sync/night_upload.dart`, read from the night's files, so it works for any night): the night (device, channels, start and end, heart strap), every epoch (contact, quality, heart rate, HRV, RR intervals), every event, and the files themselves (EDF, BIDS sidecars, epochs, heartbeats). Repeating an upload doesn't double anything. Only the refresh token is kept on the device, in the app's settings.

Test against a running Diary Keeper: `OPENLUCID_DIARY_KEEPER_URL=http://127.0.0.1:8000 flutter test test/sync_test.dart`.

## Adding another EEG device

The app never talks to a headband directly. It talks to an `EegSource` (`lib/eeg/eeg_source.dart`), which only has to say:

- its **channel names** (10-20 notation, such as `AF7`),
- its **sample rate**,
- and deliver a **stream of samples in microvolts**.

To support a new device, write one class that implements `EegSource` (see `lib/eeg/muse_source.dart` for a Bluetooth example and `lib/eeg/fake_moose.dart` for the simplest possible one), add it to the device picker in `lib/main.dart`, and add tests for its decoding. Nothing else in the app needs to change.

## Tests

```bash
flutter test
```

The Muse decoding is tested with hand-built packets, so the tests need no headband.
