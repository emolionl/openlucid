---
title: "5. Trust, but verify"
description: "Agent reports are claims. What the lead checked before publishing: rerunning tests, reading security code, checking what goes to GitHub, testing the real deployment, and reading research before it goes online."
weight: 5
tldr:
  - "An agent's report is a claim, not a fact. The lead re-checks the claims that matter."
  - "Rerun the tests yourself, read the security-critical code, check that nothing private gets committed."
  - "Test the real deployment, not just the tests: the Docker version passed a 22-step scenario."
  - "Read research before publishing it, and fix what doesn't belong in public."
---

## Reports are claims

When the 13-agent workflow finished, its report said: 381 tests passing, 14 findings fixed, a 20-step user story passing. All of that turned out to be true, but the lead didn't know that until it checked. Agents can misreport, run the wrong command, or test against the wrong database.

## What the lead checked before committing

1. **Rerun the tests.** Both suites, by the lead itself: 381 passed on SQLite, 380 plus one skipped on PostgreSQL (the skipped one only applies to SQLite).
2. **Read the security-critical code.** Not everything: the parts where a mistake is catastrophic. How a login token is checked (the algorithm is pinned, required claims are enforced, the token type is checked, deactivated users are refused) and how a night, recording or journal entry is looked up (always filtered by the current user).
3. **Check what goes to GitHub.** `git status` before committing: is `.env` ignored? Is there a `data/` folder, a database file, a generated secret key? An open-source repository is forever.
4. **Check the agent's own changes to shared files.** The deployment agent had edited the root README; the lead read the diff.

## Test the real thing

Tests use a test client. Users use a real server. When Docker became available, the lead built the image, started PostgreSQL and the API with Docker Compose, and ran a 22-step scenario over real HTTP: two users, idempotent nights and events, epoch upserts, a recording upload and download with matching checksums, isolation between users, an admin list without health data, account deletion, and finally a look inside the Docker volume to confirm the recording file was really gone.

It also checked things a scenario doesn't: the API runs as a non-root user, the database isn't reachable from outside, and migrations ran on start.

## Reading research before publishing

Research agents wrote three public pages (EEG options, a DIY eye sensor, a parts guide). The lead read each one completely before publishing and changed things:

- An institution's name appeared in a way that could suggest an affiliation the project doesn't have. It was reworded.
- Two pages gave different prices for the same part. The older one was updated.
- Every page had to list its sources, date its prices, and say what couldn't be found.

**Rule:** you are responsible for what you publish, whoever wrote it.
