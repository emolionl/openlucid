---
title: "7. Exercises"
description: "Practice agentic development on the OpenLucid repository: specs, workflows, reviews, test-first fixes and verification."
weight: 7
tldr:
  - "Six exercises, from writing a spec to running your own small team of agents."
  - "Work on a fork of OpenLucid; every exercise has a clear 'done when'."
---

Fork [github.com/emolionl/openlucid](https://github.com/emolionl/openlucid), check out `checkpoint-02`, and get the backend tests running locally first (see `backend/README.md`).

## 1. Read before you build

Read `backend/SPEC.md` and answer: which principle decides what happens when user B asks for user A's journal entry? Where in the code is it enforced? Which test proves it?

**Done when:** you can point to the principle, the line of code and the test.

## 2. Write a spec section

Feature: users can add **tags** to a night (for example `stressed`, `new-moon`, `cue-night`). Write the spec section: principles (if any), data model changes, endpoints, status codes, isolation and test rules. Don't write code yet.

**Done when:** a classmate can implement it without asking you a question.

## 3. One agent, one feature

Give an agent your spec from exercise 2 and let it implement the tags feature, with tests. Then check its work as in lesson 5: rerun the tests yourself, read the queries that filter by user, check `git status`.

**Done when:** the full suite passes on SQLite and on PostgreSQL (`scripts/pg_test.py`), and you found at least one thing to improve in the agent's work, or can explain why it's correct.

## 4. Be the reviewer

Pick one lens from lesson 4 (security, isolation, contract, operations) and review the tags feature through that lens only. Write each finding with a concrete scenario as evidence.

**Done when:** you have at least one finding, or a written argument why the lens finds nothing.

## 5. Prove it with a failing test

For each finding from exercise 4: write a test that fails because of it. Then fix the code until the test passes. If you can't make a test fail, the finding isn't real; write down why.

**Done when:** every finding is either fixed with a test or rejected with a reason.

## 6. A small team

Write a workflow with three agents, modelled on [examples/backend-workflow.js](https://github.com/emolionl/openlucid/blob/main/docs/agentic/examples/backend-workflow.js): one builds a feature, one reviews it through two lenses, one fixes the findings test-first. Use file ownership and a structured report for each agent.

**Done when:** the workflow runs end to end, and you can explain in two sentences why each agent needed the information it was given, and nothing more.

## Reflection

Write half a page: where did the agent save you the most time, where did it mislead you, and which check caught it? That half page is worth more than the code.
