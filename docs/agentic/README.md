---
title: "Learn agentic development"
description: "How OpenLucid was built by one person working with AI agents: the method, the real scripts, the real mistakes, and exercises. For software developers and students."
---

OpenLucid was built in the open by one person working with an AI coding agent (Claude Code), which in turn ran teams of other agents. This section teaches the method using what actually happened, including what went wrong. Everything it refers to is in this repository, so you can check every claim.

**Who it's for:** software development students and developers who know some programming and want to learn how to work with AI agents on real projects, without losing control of quality.

| Lesson | What you learn |
|---|---|
| [1. What agentic development is](01-what-is-agentic-development.md) | Who decides, who builds, who checks; the loop of goal, plan, build, verify, log |
| [2. Write the spec first](02-spec-first.md) | Why a specification makes parallel agents possible, and what goes into one |
| [3. Orchestrating a team of agents](03-orchestrating-agents.md) | The real 13-agent workflow that built the backend, line by line |
| [4. Reviewers and test-first fixes](04-review-and-fix.md) | Why separate reviewers find what builders miss, and the rule "prove it with a failing test" |
| [5. Trust, but verify](05-trust-but-verify.md) | What the lead (human or agent) checks before anything is published |
| [6. When the agent is wrong](06-when-the-agent-is-wrong.md) | Wrong conclusions, wrong assumptions, blocked actions, and the simple question that solves the bug |
| [7. Exercises](07-exercises.md) | Practice on this repository |

**The numbers, honestly:** the backend (checkpoint 02) was built by 13 agents in six phases in about 72 minutes, using about 1.4 million tokens. Four reviewers found 14 real problems; all 14 were reproduced with a failing test and fixed. The result: 381 tests on SQLite, 380 on PostgreSQL. Before publishing, the lead re-ran the tests, read the security code, and tested the Docker deployment with a 22-step scenario.

Agents are fast and thorough, and they are also confidently wrong sometimes. The method in these lessons is about getting the first without suffering from the second.
