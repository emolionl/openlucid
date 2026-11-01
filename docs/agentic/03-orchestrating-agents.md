---
title: "3. Orchestrating a team of agents"
description: "The real workflow that built OpenLucid's backend with 13 agents in six phases: phases, file ownership, structured reports, the integrator, and what it cost."
weight: 3
tldr:
  - "Six phases: foundation, five features in parallel, integration, four reviewers, fixer, fresh-install check."
  - "Parallel agents don't collide when each owns its own files and asks for changes to shared files instead of making them."
  - "Every agent returns a structured report, so the next phase can use it without guessing."
  - "13 agents, about 72 minutes, about 1.4 million tokens."
---

The script is in this repository: [examples/backend-workflow.js](https://github.com/emolionl/openlucid/blob/main/docs/agentic/examples/backend-workflow.js). It ran in Claude Code's Workflow tool, which starts agents, runs them in parallel where asked, and passes results between phases. Read it alongside this lesson.

## The six phases

| Phase | Agents | Why this shape |
|---|---|---|
| Foundation | 1 | Everything others depend on: config, database, **all** models and schemas, security, auth, migrations, the test setup |
| Features | 5 in parallel | Nights and epochs, recordings, journal, account and admin, deployment. Independent once the foundation exists |
| Integrate | 1 | Applies the requests for shared files, runs everything on SQLite **and** PostgreSQL, starts a real server |
| Review | 4 in parallel | Security, isolation and privacy, API contract, operations. Read-only |
| Fix | 1 | Reproduces each finding with a failing test, then fixes it |
| Verify | 1 | A fresh install following only the README, a 20-step user story |

## Why the foundation is one agent

Models and schemas are shared by everything. If five agents each added fields to `models.py`, they'd overwrite each other. So the foundation agent created **all** tables and **all** request/response schemas from the spec, plus empty router files for the others to fill in. After that, the five feature agents could work in parallel without touching shared files.

## File ownership and "shared change requests"

Each feature agent was told exactly which files it owns:

```text
YOU OWN ONLY: app/routers/journal.py and tests/test_journal.py. Do NOT edit any other file.
If you need a change in a file you don't own, do NOT make it — list it precisely in shared_change_requests.
```

This is the trick that makes parallel work safe. In the real run, the feature agents asked for **5 shared changes** in total (for example: add `.env` to `.gitignore`). The integrator applied them, one agent, one place, no conflicts.

## Structured reports

Every agent ends with a report in a fixed shape (a JSON schema), for example:

```js
{ summary, files_changed, tests_passed, tests_failed, shared_change_requests, open_issues }
```

Because the shape is fixed, the script can pass all five feature reports to the integrator, count findings, and log progress, without a human reading every message. Free-text reports are fine for humans; **schemas are for pipelines**.

## Parallel versus sequential

Parallel saves time only when tasks are independent. The features were; the foundation and the integration weren't. Reviewers are naturally parallel: each looks through a different lens and doesn't need the others. A rule worth remembering: **parallelise reading and reviewing freely; parallelise writing only with strict file ownership.**

## The prompt shared by every agent

Every agent got the same opening block (`COMMON` in the script): the spec is binding, use this Python environment, never kill processes by name, don't commit, no medical claims, never log passwords or EEG. Rules you put there once apply to all 13 agents.

## Cost and time

About 72 minutes and 1.4 million tokens for 13 agents. That's a lot for a hobby project and little compared to the work it replaced. **Don't use a team for small changes:** the hamburger menu was one agent, five minutes.
