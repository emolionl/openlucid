---
title: "Day 3: testing everything"
date: 2026-11-01T17:30:00+01:00
description: "Eight AI test agents tested the whole of OpenLucid end to end, from outside: the Diary Keeper in Docker, its API docs, the website, the web app and the desktop app. 122 checks, 16 bugs, and what could not be tested."
weight: 7
outcome: "Tested"
tldr:
  - "Eight test agents ran 122 checks from outside: 105 passed, 4 failed and 13 could not be tested, each with a reason."
  - "16 bugs, 2 of them medium: a broken link on the website, and a server error on deeply nested JSON. No data leaked between users."
  - "The server survives restarts without losing anything, but says 'awake' while its database is down."
  - "Each agent got its own tool, its own test accounts and its own evidence folder, and tests that disturb others ran last."
  - "Both medium bugs and five low ones were fixed the same evening, each with a test; seven small ones are listed as open."
---

## Why test again?

The Diary Keeper already had 381 passing tests ([day 2](2026-11-01-day-02-the-diary-keeper-grows-up.md)). Those tests run *inside* the code: they call functions and check the answers. Nobody had yet used the whole thing the way a person does: opening the docs in a browser, clicking through the website on a phone, starting the desktop app, or pulling the plug on the database.

So tonight the server ran in **Docker** (PostgreSQL 17, the API at `http://127.0.0.1:8001`), and a team of AI test agents attacked it from the outside. Each one had one job, one tool, and had to write down what it did, what it found and what it could *not* test.

## Who tested what, with which tool

| Tester | What | Tool | Checks | Pass | Fail | Not tested | Bugs |
|---|---|---|---|---|---|---|---|
| API docs | Swagger UI, ReDoc, the OpenAPI file | Playwright MCP (a browser the agent drives) | 18 | 16 | 0 | 2 | 5 low |
| Website | Every page of openlucid.web.app, phone and desktop | Chrome DevTools MCP with Lighthouse, a Python link crawler | 14 | 10 | 3 | 1 | 1 medium, 4 low |
| Web app | The small Vue app talking to the Diary Keeper | Puppeteer MCP, httpx | 10 | 8 | 0 | 2 | none |
| API flow | Five users syncing whole nights at the same time | Python httpx with threads | 16 | 13 | 0 | 3 | none |
| Flutter tests | The desktop app, driven from inside | Flutter `integration_test` on Windows | 9 | 7 | 0 | 2 | 1 low |
| Security | Attacks from outside: tokens, uploads, odd input | Python httpx, hand-made tokens | 32 | 31 | 1 | 0 | 1 medium |
| Robustness | Restarts, a missing database, huge uploads | `docker compose`, httpx probes | 9 | 9 | 0 | 0 | 3 low |
| Desktop GUI | The real app window, real mouse and keyboard | AutoIt | 14 | 11 | 0 | 3 | 1 low |
| **Total** | | | **122** | **105** | **4** | **13** | **16** |

The first five ran **at the same time**. Then security, robustness and the desktop GUI ran **one after the other**, because each of them gets in the way of the others (more on that in [lesson 8](../agentic/08-end-to-end-testing-with-agents.md)).

## What worked

**The API docs.** All 33 operations from the spec show up in Swagger UI at `/docs`, every protected one with a lock icon. A new developer can register, click *Authorize*, and use the whole API from the browser. Retrying works as promised: sending the same night twice gives the same night back, and sending the same events twice gives `created: 0, existing: 3`.

**Five people syncing at once.** Each test user synced a realistic 8-hour night: 960 epochs in 4 batches, 30 events and a 5 MB recording. All five together took **3.4 to 3.7 seconds**. Then everything was sent again, as a phone would after a lost connection: still exactly 960 epochs, no duplicates.

| Request (5 users at once) | Median | 95th percentile |
|---|---|---|
| Save 240 epochs | 175 ms | 286 ms |
| Read 960 epochs | 147 ms | 239 ms |
| Export everything (about 291 KB) | 189 ms | 328 ms |
| Upload 5 MB | 332 ms | 379 ms |
| Download 5 MB | 583 ms | 792 ms |
| Register (password hashing is slow on purpose) | 233 ms | 240 ms |

**Nobody sees anyone else's data.** 20 pairs of users, 12 attempts each to read, change or delete the other's night: all **240 attempts gave 404** ("not found"), never 403. A 403 would tell an attacker that the night exists. After deleting two accounts, a direct look in the database and on disk showed their rows and files were really gone.

**Security from outside.** Fake tokens (`alg: none`, a changed signature, a changed user id) were all refused. Sending `role: admin` while registering was ignored. A wrong email and a wrong password give the same message. Password guessing is stopped after 10 tries per email and 30 per address, exactly as the spec says. Upload file names such as `../../etc/passwd` were reduced to `passwd`. The database port is not reachable from outside Docker, and the API runs as a normal user, not as root.

**Restarts.** Restarting the API caused 14 failed requests in a 3.9-second window, then everything recovered on its own. Restarting the database caused **0** failures (one request waited 4 seconds). After `docker compose down` and `up` all data was still there, the recording's checksum matched, and even the old sign-in tokens still worked. A 210 MB upload was refused with "The file is too big; the limit is 200 MB." and left no half file behind. The logs contained no passwords, tokens or EEG data.

**The website.** Lighthouse gave the home page **100** for accessibility, best practices and SEO. A long article scored 96 for accessibility. On a simulated phone with slow 4G the main content appeared after 1.55 s, with no jumping layout. None of the 27 pages scrolls sideways at 360 px wide, and there were 0 console errors.

**The desktop app.** Flutter's own integration test started the real app four times in a row: all four screens, the Diary Keeper reached in 118–162 ms, Fake Moose streaming 256 samples per second with 0 lost, and a full eye check (blinks 3 of 3, left and right 4 of 4). AutoIt then drove the release build with the real mouse at phone, tablet and laptop size: 7 of 7 self-checks passed, and the window icon is the moon.

## The bugs

| Severity | Where | Bug |
|---|---|---|
| medium | Website | Lesson 1 links to `/journey/README/`, which doesn't exist. The link converter didn't know that `README.md` is the index of a folder |
| medium | Diary Keeper | Event details nested about 1,500 levels deep (still under the 10 kB limit) give a server error (500) instead of a clean 422. Found by testing just below and just above the limit |
| low | Diary Keeper | While the database is down, requests wait about 8 s and then return plain text "Internal Server Error" instead of a JSON error. An app can't tell "try again later" from a real bug |
| low | Diary Keeper | `/health` keeps saying "awake" while the database is down, so Docker thinks all is well |
| low | Diary Keeper | A phone that drops off during an upload produces a long error in the log. The cleanup does work |
| low | API docs | Error answers (401, 404, 409, 429) aren't described in the docs, so Swagger labels them "Undocumented" |
| low | API docs | One 422 answer has a different shape from the one in the docs |
| low | API docs | The example bodies in Swagger fail if you run them unchanged (`timezone: "string"`) |
| low | API docs | Almost no field has a description, and *Authorize* asks for a "username" without saying it's your email |
| low | API docs | ReDoc loads from the internet, so `/redoc` is blank offline |
| low | Website | Jumping to a section hides its heading behind the sticky header |
| low | Website | Links in text are only told apart by colour (that's the 96) |
| low | Website | No `robots.txt` and no OpenLucid 404 page |
| low | Website | The parts tables are hard to read on a phone |
| low | Desktop app | Fake Moose's forehead contact sits right on the 80% line, so the eye check button flips between "Start" and "Start anyway" |
| low | Desktop app | At phone width the hint under the Diary Keeper address is cut off, exactly where a phone user needs it |

These are written down, not fixed yet. Each one comes with steps to reproduce it, so the fix can start with a failing test, as in [lesson 4](../agentic/04-review-and-fix.md).

## What we could not test, and why

- **A real Muse headband.** There was none on the table, so the apps were tested with Fake Moose.
- **Real phones, Safari and Firefox.** Only Chrome pretending to be a phone.
- **The phone layout in the Flutter test.** A Windows window is always laptop-sized there; AutoIt covered it instead by resizing the window.
- **Token expiry after 15 minutes**, and an expired token with a valid signature: that needs the server's secret key, which an outside tester doesn't have.
- **Wrong passwords during the parallel phase.** The guessing limit counts per address, and all testers share one address (127.0.0.1). One tester's failed logins would have blocked everyone. The security tester did it later, alone.
- **The web app's "No answer" message.** That needs the server switched off, which would have broken the other testers.
- **Uploading the same recording twice.** Recordings have no id from the app, so a retry stores a second copy. Not a bug according to the spec, but a gap worth fixing.

## Lessons

1. **Tests inside the code and tests from outside find different things.** 381 tests passed, and the outside testers still found 16 bugs: in the docs, the website, the logs and the error answers, places unit tests never look.
2. **Test on both sides of a limit.** The nesting bug looked like the 10 kB rule doing its job until the tester tried 1,450 levels (fine) and 1,500 levels (crash).
3. **Check a "pass" can fail.** A command that found no files looked like a pass, but Git Bash had changed the path. A colour check matched the wrong pixels until it was tested with the signal stopped. Prove your check can say "no".
4. **Leave the machine as you found it.** Test users were deleted, settings were kept in memory, and eye-check files were moved out of the Documents folder.

All logs, screenshots and scripts are in a `test-results/` folder on the test machine. It isn't in the repository, because the screenshots contain test accounts and local paths.

## Code at the end of the day

No new checkpoint: tonight was testing only. The new Flutter integration test lives in `frontend/desktop/integration_test/app_test.dart`. Run it with:

```bash
cd frontend/desktop
flutter test integration_test -d windows
```

## Fixed the same evening

The lead went through every report, reproduced the bugs, and fixed these right away:

| Bug | Fix | Proof |
|---|---|---|
| **Medium:** deeply nested JSON (about 1,500 levels) gave a server error | The real cause was not where we first looked: validation correctly refused the body, but FastAPI then tried to echo the whole structure back in its error message, and that crashed. Now requests deeper than 32 levels get a clear 422, and **error responses no longer echo the submitted data at all**, which is also better for privacy (no health data repeated in errors or logs) | 4 new tests; 385 tests on SQLite, 384 on PostgreSQL |
| **Medium:** a broken link from Learn lesson 1 to the journey | Links to a folder's README now go to that section's front page | A check of all 596 internal links on the built site: 0 broken |
| Section headings hidden under the sticky menu after a jump | Headings keep a margin for the menu | Checked in the browser |
| Links in text only recognisable by colour | Links in articles are underlined | Lighthouse's accessibility rule |
| No 404 page, no robots.txt | An OpenLucid 404 page ("Lost in a dream?") and a robots.txt | Built and deployed |
| The settings help text was cut off on phones | It wraps onto more lines | Flutter tests |
| The eye check's start button flickered between "Start" and "Start anyway" | **Hysteresis:** the check becomes ready at 80% contact and only stops being ready below 50%, so a blink no longer flips it | Flutter integration tests, re-run by the lead on the real Windows app: 4 of 4 passed, eye check 3/3 blinks and 4/4 left/right |

**Still open** (all low): the API docs don't list error responses and most fields have no description; while the database is down, requests hang for about 8 seconds and `/health` still says "awake"; a client that disconnects mid-upload leaves a stack trace in the log; the consent error uses a different shape from other validation errors; ReDoc loads from a CDN without a pinned version; the parts tables are cramped on a phone.

