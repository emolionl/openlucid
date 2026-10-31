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
