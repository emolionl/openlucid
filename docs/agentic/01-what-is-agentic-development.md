---
title: "1. What agentic development is"
description: "Who decides, who builds, who checks: the loop of goal, plan, build, verify and log, with examples from OpenLucid."
weight: 1
tldr:
  - "You decide what and why; agents work out how and do the work; somebody checks every result."
  - "The loop: goal, plan, build, verify, log. Skipping verify is how bad code gets published."
  - "Agents ask before actions that are hard to undo; you give clear goals and answer questions."
---

## The roles

In agentic development an AI agent doesn't just suggest code. It reads files, runs commands, writes code, runs tests, opens a browser to look at the result, and reports back. A **lead agent** can also start other agents and give each a task.

That changes the human's job. In OpenLucid the project owner, a teacher, rarely wrote code. Their job was:

- **Deciding what and why.** "The app has to work on Android too." "Make the website look like Apple's." "The backend should run locally and on a server."
- **Providing reality.** Wearing the headband, pressing buttons, sending screenshots, saying "it was lying on the table".
- **Making the calls only a human can make.** Which name to use, what to buy, what may be published, whether a password may be changed.

The agent's job was everything in between: researching, planning, building, testing, and **checking its own work before claiming it was done**.

## The loop

Every step in OpenLucid followed the same loop:

1. **Goal.** One sentence from the human: *"make a hamburger menu"*.
2. **Plan.** The agent says what it will do, and asks only when a decision really belongs to the human.
3. **Build.** Small steps, each one testable.
4. **Verify.** Run the tests, start the real thing, look at it. For the hamburger menu: open the site in a browser at phone width, click the button, check that the menu opens and nothing sticks out.
5. **Log.** Write down what happened in the [journey](../journey/README.md), including the mistakes, and commit.

The step people skip is **verify**. An agent that writes "done" without having run anything is guessing. In OpenLucid, verification regularly found real problems: two layout bugs on the first run of the phone-size tests, a menu that showed the page through it, a website that was 696 pixels wide on a 360-pixel phone.

## Asking versus acting

A good agent acts on clear instructions and asks when a choice is genuinely the human's to make. Examples from OpenLucid:

| Situation | What happened |
|---|---|
| "Push it to GitHub" | Acted: created the repository and pushed |
| Which GitHub account and repository name? | Asked: the human chose the account and the name *OpenLucid* |
| Build the full backend first, or record a night tonight? | Asked, with a recommendation |
| Delete all Docker projects | Done only after the human explicitly said so, after listing what would be lost |
| Change a real person's password | Blocked by the safety system; left to the human |

**Rule of thumb:** the harder an action is to undo, or the more it affects other people, the more it needs an explicit "yes".

## Logging is part of the work

The project owner asked for every step to be written down, "so every programmer knows". That turned out to be one of the most useful habits: the journey shows not just what was built but **why**, and where the agent was wrong. A log is also the agent's memory for the next session.
