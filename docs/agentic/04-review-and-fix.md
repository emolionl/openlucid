---
title: "4. Reviewers and test-first fixes"
description: "Why separate reviewers with different lenses find what builders miss, the 14 real findings, and the rule: prove it with a failing test before you fix it."
weight: 4
tldr:
  - "Builders test what they thought of; reviewers with a different question find the rest."
  - "Four lenses (security, isolation, contract, operations) found 14 real problems in code with 325 passing tests."
  - "Rule: reproduce every finding with a failing test first. No failing test, no fix."
---

## Passing tests are not enough

After integration the backend had **325 passing tests** on SQLite and PostgreSQL. Four reviewers then found **14 real problems**. Every one of them was invisible to the tests the builders had written, because the builders hadn't thought of those situations.

## Four lenses

Each reviewer got one question to ask of the whole codebase, read-only:

| Lens | The question |
|---|---|
| Security | Tokens, passwords, rate limits, uploads, error messages, mass assignment |
| Isolation and privacy | Can user B see, change, export or attach to anything of user A, through any endpoint? Does deleting really delete files? |
| Contract | Does every endpoint match the spec on both databases? Races in "create if not exists"? |
| Operations | Does the README work from scratch? Docker, migrations twice, cleanup, version pins? |

A reviewer with one sharp question goes deeper than one asked to "review everything".

## What they found

| Severity | Finding | Why the tests missed it |
|---|---|---|
| high | A future database migration on SQLite could silently delete users' nights (foreign keys are enforced inside a migration transaction) | No migration has rebuilt a table yet |
| medium | The protection against password guessing could be bypassed by sending many attempts at the same moment | Tests send one request at a time |
| medium | With the default Docker settings, every visitor would share one rate-limit bucket behind a proxy | Docker wasn't running during the build |
| medium | A NUL character in a text field crashed PostgreSQL (fine on SQLite) | Nobody types NUL characters in tests |
| medium | NaN or Infinity in event details: crash on PostgreSQL, silently changed on SQLite | Same |
| medium | Timestamps near year 1 or 9999 caused a server error | Same |
| medium | Running the tests with the wrong setting in your shell could drop every table of a real database | The builder's own shell was always clean |
| medium | An `.env` copied from the example but not filled in crashed the app | The builder never copied the example |
| medium | On Windows, a recording file that was open during deletion stayed on disk | Files are rarely open during tests |
| low | Two people registering at the same moment on an empty server could both become admin | Sequential tests |
| low | Two admins demoting each other at the same moment caused a deadlock | Same |
| low | Reusing a logged-out refresh token didn't end the other sessions | Spec wording read differently |
| low | Minimum versions in requirements.txt allowed versions the code couldn't import | Builders had newer versions installed |

Notice the pattern: **concurrency, unusual input, the other database, and "a fresh machine"**. Those are the four places to look in any review.

## The rule: a failing test first

The fixer got one instruction that mattered most: *for each finding, first reproduce it with a test. If the test fails, fix the code until it passes and keep the test. If you can't reproduce it, don't change code; mark it rejected with the reason.*

Why:

- It **proves the problem is real**. Reviewers can be wrong; a failing test can't.
- It **proves the fix works**, not just that the code changed.
- It **keeps the problem from coming back**: the test stays in the suite. For the race conditions, the tests send many requests in parallel threads and check that exactly one admin exists.

All 14 findings were reproduced and fixed; none were rejected. Final count: 381 tests on SQLite, 380 on PostgreSQL.
