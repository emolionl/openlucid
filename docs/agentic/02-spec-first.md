---
title: "2. Write the spec first"
description: "Why a specification makes parallel agents possible, what goes into one, and how OpenLucid's backend spec was used."
weight: 2
tldr:
  - "Agents working in parallel can only fit together if they build against the same written contract."
  - "A good spec has principles, a data model, every endpoint, security rules, file ownership and test rules."
  - "When the spec has to change, change it in the same commit and say why."
---

## Why

Ask five agents to "build the backend" and you get five backends. Ask them to build *their part* of one written specification and the parts fit together.

Before any backend code existed, the lead agent wrote [backend/SPEC.md](https://github.com/emolionl/openlucid/blob/main/backend/SPEC.md). Every other agent was told: *read this first, it is binding.* It took about ten minutes to write and saved hours of integration.

## What goes into it

The OpenLucid spec has six parts. Open it next to this list.

1. **Principles.** Short rules that decide many small questions at once: *local first*, *raw EEG never goes into database rows*, *every user sees only their own data; another user's resource is 404, never 403*, *idempotent sync*, *privacy built in*.
2. **Stack.** Exact choices (FastAPI, SQLAlchemy 2.0, Alembic, argon2, PyJWT, pytest), so nobody picks a different library.
3. **Configuration.** Every setting with its default and meaning.
4. **Data model.** Every table, column, constraint and what happens on delete.
5. **API.** Every endpoint with request, response, status codes and edge cases (for example: *repeating a create with the same `client_id` returns 200 with the existing night*).
6. **Code layout with owners.** Which file belongs to which agent. This is what makes parallel work possible (lesson 3).

And a seventh: **test rules.** *Every endpoint has tests for the happy path, validation errors, unauthenticated access (401) and another user's resource (404).* That one sentence produced dozens of isolation tests.

## Principles do the heavy lifting

Specs can't foresee everything. Principles cover the gaps. When the reviewers later asked "can user B see anything of user A?", the answer for every new endpoint was already decided by one principle: scope every query to the current user, and answer 404 for anything else.

## Changing the spec

A spec is not frozen. While building, the foundation agent found an edge case: with registration closed from the very start, nobody could ever become admin. The rule is: **change the spec in the same commit as the code, and say why**, so the spec stays the truth.

## Writing one yourself

Start with the principles; they're the part people skip and the part that matters most. Then the data model, then the endpoints. If you can't write the spec, you don't understand the feature well enough yet, and an agent won't either.
