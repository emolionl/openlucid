<p align="center"><img src="branding/logo-mark-512.png" alt="OpenLucid logo: a crescent moon with a yellow zigzag" width="140"></p>

<h1 align="center">OpenLucid</h1>

**An open-source dream machine you can build yourself.**

You put on a [Muse](https://choosemuse.com/) EEG headband and go to sleep. An app listens to your brainwaves. A small program on your own laptop guesses your sleep stage. When it is fairly sure you are dreaming, it plays a soft sound that you trained yourself, that evening, to link with the question *"Am I dreaming?"*. And if you realize you are, you can signal back from inside the dream with your eyes: left, right, left, right.

Will it give you lucid dreams? Honest answer: maybe, sometimes. Sound cues during REM sleep (*targeted lucidity reactivation*) have helped some people in lab studies; at home the evidence is weaker. OpenLucid is a tool to find out, honestly, what works for you.

> **Educational, not medical advice.** A Muse is a consumer gadget, not a medical device. OpenLucid does not diagnose or treat anything. Sound cues only: no electricity goes into anyone's head.

## What's in here

```
openlucid/
├── backend/            The Diary Keeper: Python + FastAPI + SQLite, runs on your laptop
├── frontend/
│   ├── desktop/        The app: Flutter (Windows, Android, macOS, Linux), talks to the Muse over Bluetooth
│   └── web/            The morning view: Vue, your night's report and dream journal in the browser
├── website/            The project website (openlucid.nl): Hugo, static, hosted on Firebase
├── docs/journey/       The build diary: every step we took, including the wrong turns
├── promotion/          Video scripts and the animated series "Are You Dreaming?"
└── branding/           The logo and the script that makes every icon size
```

**Follow the build:** start with [the journey](docs/journey/README.md). It's written for beginners, and the mistakes are in there too.

Everything runs locally. Your brain data never leaves your computer.

## Quick start (checkpoint 00: make them wave at each other)

You need [Python 3.11+](https://www.python.org/downloads/), and for the app [Flutter](https://docs.flutter.dev/get-started/install) or for the browser view [Node.js](https://nodejs.org/).

**1. Start the Diary Keeper** (Windows PowerShell; on macOS/Linux use `source .venv/bin/activate`):

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Open <http://localhost:8000/health>. It should say *"The Diary Keeper is awake."*

**2. Wave from the app** (in a second terminal):

```bash
cd frontend/desktop
flutter run -d windows
```

**3. Or wave from the browser:**

```bash
cd frontend/web
npm install
npm run dev
```

Got an answer? Checkpoint 00 is done. 🎉

## Roadmap

Each step is a checkpoint (a git tag such as `checkpoint-03`), so you can always jump to a working version.

| Checkpoint | What it adds |
|---|---|
| 00 | App, web view and server say hello |
| 01 | Connect to the Muse over Bluetooth, live signal on screen, Fake Moose replay mode |
| 02 | Record a whole night (30-second epochs, reconnects, EDF file) |
| 03 | The Diary Keeper's REST API and database (sessions, epochs, events, journal) |
| 04 | Sleep staging of a recorded night with [YASA](https://github.com/raphaelvallat/yasa), hypnogram |
| 05 | Live staging and the "stable REM" rule |
| 06 | Detect the left-right-left-right eye signal |
| 07 | Sound cues: evening training, playback during stable REM |
| 08 | Morning report and dream journal |
| 09 | Export and honest analysis of your own nights |
| 10 | One-click installer |

## Contributing

New to programming? You're very welcome here. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE): free to use, change and share, including for research and teaching.
