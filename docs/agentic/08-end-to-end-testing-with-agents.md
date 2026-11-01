---
title: "8. End-to-end testing with agents"
description: "How eight AI test agents tested OpenLucid from the outside: one tool per agent, the order that keeps them out of each other's way, unique test accounts, evidence folders, black-box security probes, and Flutter integration_test versus AutoIt."
weight: 8
tldr:
  - "Unit tests check the code from inside; end-to-end tests use the real thing from outside. 381 passing tests, and outside testers still found 16 bugs."
  - "One tool per agent, a unique email prefix per agent, and one evidence folder per agent keep parallel testers from fighting."
  - "Run harmless black-box tests in parallel first; run tests that disturb shared state (failed logins, restarts, the real mouse) last, one at a time."
  - "Every tester reports what it could not test, and why. A 'not tested' is honest; a faked pass is worse than no test."
---

This lesson uses the real test run from [day 3](../journey/2026-11-01-day-03-testing-everything.md). Read that first for the results; this lesson is about **how** the run was organised, and why.

## Why test end to end, after the unit tests?

The Diary Keeper had **381 passing tests** ([lesson 4](04-review-and-fix.md)). They call the code directly, with a test database, inside one process. They can't tell you:

- whether the API docs a new developer opens actually work,
- whether the website has a broken link,
- whether the server comes back after Docker restarts it,
- whether the desktop app looks right at phone size,
- what ends up in the logs.

An end-to-end test uses the system the way a person or another program does: through the browser, the network, the window, Docker. It's slower and coarser, so it doesn't replace unit tests. It finds a different kind of bug. In this run: **122 checks, 16 bugs**, all of them missed by the 381 unit tests. Most were in places unit tests don't look at all: the docs, the website, the logs, the behaviour while the database is down.

## The team

| Agent | Tool | Runs |
|---|---|---|
| API docs | Playwright MCP | in parallel |
| Website | Chrome DevTools MCP (with Lighthouse) and a Python crawler | in parallel |
| Web app | Puppeteer MCP and httpx | in parallel |
| API flow | Python httpx with threads | in parallel |
| Flutter tests | Flutter `integration_test` | in parallel |
| Security | Python httpx | alone, after the parallel phase |
| Robustness | `docker compose` and httpx | alone, after security |
| Desktop GUI | AutoIt | alone, last |

An **MCP server** is a tool an agent can call, here: a browser it can steer. Three different browser tools, for a reason.

## Rule 1: one tool per agent

If two agents share one browser, they fight: agent A navigates to `/docs` while agent B is halfway through filling in a form. Neither notices; both report nonsense. So each browser tester got **its own** browser tool: Playwright for the API docs, Chrome DevTools for the website, Puppeteer for the web app. Three browsers, no shared tabs.

The same goes for ports. The web app tester found port 5174 already taken by another tester's dev server. It didn't kill it; it picked port 5180 with `--strictPort`, so Vite would fail loudly instead of quietly moving to another port and testing someone else's server.

And for windows. The AutoIt tester found a second app window with the same title, "OpenLucid", started by someone else. Searching by title could have clicked the wrong app. It found its own window by **process id** instead.

## Rule 2: harmless tests first, disturbing tests last

Some tests change the world for everyone:

- **Failed logins.** The server blocks an address after 30 failed logins in 15 minutes. All testers run on one machine, so they all share the address `127.0.0.1`. One security probe would lock every other tester out with a 429.
- **Restarts.** `docker compose restart db` makes every running test fail for a few seconds.
- **The real mouse and keyboard.** AutoIt moves the actual mouse pointer. Nothing else can use the screen while it runs.

So the order was:

1. **In parallel:** everything that only reads, or writes only its own data. The parallel testers were told explicitly: *no wrong passwords, don't stop the server.*
2. **Alone: security**, including the rate-limit probes. Even inside this step the order mattered: first the small per-email test (blocked on the 11th try), then the per-address sweep last, because that one uses up the budget.
3. **Alone: robustness**: restart the API, restart the database, stop it for 15 seconds, `down` and `up`.
4. **Alone: the desktop GUI with AutoIt**, because it takes over the mouse.

The Flutter integration test could run in parallel, because it drives the app from inside the Flutter engine, not with the real mouse.

## Rule 3: a unique email prefix per tester

Every tester registered its own accounts with its own prefix: `swagger-…`, `flow-<run>-u1…`, `sec-…`, `rob-…`. That gives three things:

- testers never trip over each other's data,
- cleanup is one query (the API flow tester checked afterwards: 0 users matching `flow-%`),
- anything left behind shows who left it.

One surprise: the spec says *the first account becomes admin*. On the fresh Docker database, the API docs tester happened to register first, so `swagger-newdev` became the admin of the shared stack. Harmless here, but a tester who checks admin rules must not assume it will be the first. Start from a known seed instead.

## Rule 4: one evidence folder per tester, and a structured report

Each tester wrote only into its own folder: `test-results/swagger/`, `test-results/website/`, `test-results/autoit/`, and so on. Scripts, logs, screenshots and raw JSON. That's the same file-ownership rule as in [lesson 3](03-orchestrating-agents.md), applied to evidence.

Each tester also returned a report in a fixed shape:

```js
{ tested: [{ what, result: "pass" | "fail" | "not tested", note }],
  bugs: [{ title, severity, steps, expected, actual, evidence }],
  tools_used, lessons, files_added }
```

Two fields matter most:

- **`not tested`** is a valid result, with a reason. "Real Muse headband: not tested, there is none." "Expired token with a valid signature: not tested, that needs the server's secret key." The security tester wrote: *could not fully isolate the expiry path black-box, reported honestly.* That's what you want. A faked pass hides a gap; a "not tested" shows it.
- **`steps`, `expected`, `actual`, `evidence`** turn a bug into something a fixer can reproduce with a failing test.

## Rule 5: prove that your check can fail

Three times in this run, a check said "pass" when it shouldn't have:

- The robustness tester ran `docker exec … find /data` and got nothing back: no files, a pass. But Git Bash had quietly rewritten `/data` into `C:/Program Files/Git/data`. Only checking against a file that *must* be there (its own recording) revealed it. Fix: `MSYS_NO_PATHCONV=1`.
- The AutoIt tester's first colour check for the EEG trace found 162 hits **with the signal stopped**: it matched the off-white text. After sampling the exact trace colour it found 243 hits while listening and 0 after Stop.
- The Flutter tester's "wrong address" check sent the old, working address, because typing into the text field a second time silently did nothing. The test passed for the wrong reason until it logged the field's actual value.

The rule: **add a negative control**, a case where the check must say no, and run it.

## Black-box security probing

"Black box" means testing only from outside, like an attacker, without reading the code. You don't need special tools; the security tester used Python and httpx:

| Probe | How | Result |
|---|---|---|
| Fake tokens | Build a token by hand with `alg: none`, or change one letter of a real one | 401 |
| Mass assignment | Send `role: admin` when registering | ignored, role stays `user` |
| User enumeration | Compare the message (and timing) for a wrong password and an unknown email | the same |
| Path traversal | Upload a file named `../../etc/passwd` | stored as `passwd` |
| Odd input | NUL characters, NaN, 501 events, 5001-character notes | 422 each |
| Limits on both sides | Nested JSON at 1,450 and 1,500 levels, both under 10 kB | 200 and **500** |

The last row is the one bug this tester found. One test above the limit would have said "rejected, as designed". Testing **just below and just above** a boundary showed that something other than the size rule was failing.

Also probe *below* the API. Through the API, a deleted user's night gives 404, which looks exactly like "exists but isn't yours". Only a read-only look in the database and on the disk proved the rows and files were gone.

## Desktop GUIs: Flutter integration_test versus AutoIt

Two very different ways to test the same desktop app.

| | Flutter `integration_test` | AutoIt |
|---|---|---|
| How it drives the app | From inside: finds widgets by text or type | From outside: real mouse clicks at coordinates, real keys |
| What it can check | Exact text and widget state | Screenshots and pixel colours |
| Runs in parallel with others | Yes | No, it takes over the mouse |
| Tests the real installed build | A debug build started by the test | The release `.exe`, like a user |
| Window sizes | Whatever the window is (here always laptop size) | Any: it resized to phone, tablet and laptop |
| Breaks when | Texts change | Layout or colours change, or the screen scale differs |

Limits the testers hit:

- **Flutter:** a live EEG plot redraws all the time, so `pumpAndSettle` waits forever. Write your own `pumpFor(duration)` and `pumpUntil(finder, timeout)`. `takeScreenshot()` doesn't work on Windows desktop; rendering the root layer to a PNG does. And integration tests run on the real machine: use `SharedPreferences.setMockInitialValues({})` so the user's settings aren't touched, and move files the app writes out of their Documents folder.
- **AutoIt:** a Flutter window has no Windows controls inside it, so AutoIt's `ControlClick` and `ControlGetText` see nothing. Everything goes by coordinates. Make it deterministic: DPI-aware, client-area coordinates, always resize the window to a fixed size before clicking. Backspace and paste don't reach the app; Ctrl+A then typing does.

Use both: integration_test for the logic of the screens, AutoIt for "does the real release build look and behave right at every size".

## Measure, don't eyeball

The website tester's first check said a section heading landed at 76 px below the top, below the header. It had measured in the middle of a smooth scroll. Measured again after the scroll stopped: 0 px, hidden behind the 53 px header. That's a bug, found only by reading numbers instead of looking at a screenshot.

The same goes for downtime: a script hitting the API every 250 ms during a restart gives "14 failed requests in 3.9 s", which you can compare after a fix. "It came back quickly" can't be compared.

## Exercises

### 1. Plan a test team

Take OpenLucid (or your own project) and plan an end-to-end test team of at least four agents. For each: what it tests, which tool, its email prefix, its evidence folder, and whether it runs in parallel or alone. Mark every test that changes shared state (logins, restarts, the mouse, shared files) and put those in a safe order.

**Done when:** you can explain, for every pair of agents that runs at the same time, why they can't disturb each other.

### 2. One boundary, both sides

Pick one limit in `backend/SPEC.md` (for example: at most 500 events per request, notes at most 5000 characters, uploads at most 200 MB, 10 failed logins per email). Write a black-box script with httpx that tests **just below**, **exactly at** and **just above** the limit against a running Diary Keeper, using its own email prefix and deleting its user at the end. Add one negative control that proves your script would notice a wrong answer.

**Done when:** the script prints pass or fail for all three cases plus the control, leaves no test user behind, and you can say which line of code enforces the limit.
