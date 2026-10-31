# Desktop / phone app (Flutter)

The app you take to bed, so to speak: it connects to the Muse headband over Bluetooth, shows the live signal, sends every 30 seconds of EEG to the Diary Keeper, and plays the sound cue.

## Start it

1. Start the backend first (see `../../backend/README.md`).
2. From this folder:

```bash
flutter pub get
flutter run -d windows
```

(Use `-d android` with a phone connected, or `-d macos` / `-d linux`.)

3. Press **Wave at the Diary Keeper**. If it answers "The Diary Keeper is awake.", checkpoint 00 is done.

On a phone, `localhost` is the phone itself: change `diaryKeeperUrl` in `lib/main.dart` to your laptop's IP address and start the backend with `--host 0.0.0.0`.

## Tests

```bash
flutter test
```
