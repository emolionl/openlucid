---
title: "Privacy"
description: "What OpenLucid.nl actually collects: almost nothing, and what little there is, in plain language."
---

OpenLucid is a hobby, open-source project with no company behind it. This page covers the **website** (openlucid.nl) and the **Questions page** specifically — the **desktop app** is covered separately below, because it works completely differently.

## The short version

- No analytics, no ad trackers, no cookies that follow you to other sites.
- The site itself stores a couple of small things on your own device (localStorage, not a cookie): whether you've dismissed the little notice at the bottom, and a draft of the Questions form if you start filling one in.
- If you submit the Questions form, your answers (and your email, only if you choose to give one) go to OpenLucid's Firebase project, hosted on Google Cloud in Europe.
- The desktop app never sends your brainwaves, your nights, or anything else about you anywhere. It runs entirely on your own computer.

## What the website stores locally

Two things, both in your browser's `localStorage`, never sent anywhere by themselves:

- `ol-consent-seen` — set once you dismiss the notice at the bottom of the page, so it doesn't show again.
- A draft of the Questions form, if you start one, so a reload doesn't lose your answers. Cleared automatically once you submit, or you can clear it yourself by clearing your browser's site data.

## The Questions page

The [Questions](/questions/) page is the one place on the site that actually asks for anything. If you submit it:

- Your answers are stored in OpenLucid's Firebase project (Google Cloud, Europe), in a database only the maintainer can read in full.
- Giving an email is optional. If you give one, you can also [sign in at user.openlucid.nl](https://user.openlucid.nl/) to read or change what you submitted later, and the maintainer may email you about it directly.
- Submitting also sends a notification email to the maintainer via Brevo (a transactional email service), containing what you submitted.
- Nothing you submit is published, quoted, or shared anywhere else without asking you first.

## The desktop app

The OpenLucid app (Windows today, more platforms later) is a completely separate thing from the website, and collects nothing. Your brainwaves, your sleep nights, your dream journal: all of it stays in files on your own computer (or, if you choose to run the optional Diary Keeper server yourself, on whichever computer you chose to run it on). There is no OpenLucid server that your nights get sent to, because no such server exists — the Diary Keeper is something *you* run, not something we operate.

The one exception: the app checks a small, public file (`openlucid-releases.web.app/manifest.json`, also Firebase-hosted) to see if a newer version exists, so it can offer to update itself. That request doesn't carry any personal information — just "is there a newer version of this app."

## Third parties involved

- **Firebase / Google Cloud** — hosts the website and the Questions database, in a European region.
- **Brevo** — sends the one notification email when someone submits the Questions form.
- **YouTube** — the embedded video on the homepage and episode pages uses `youtube-nocookie.com`, YouTube's reduced-tracking embed mode.
- **GitHub** — the code, releases, and discussions all live there under GitHub's own privacy policy.

No one else. No ad networks, no analytics platforms, no social-media pixels.

## Your rights

If you submitted the Questions form with an email, you can read or change your answers at [user.openlucid.nl](https://user.openlucid.nl/), or just email the maintainer (through [GitHub](https://github.com/emolionl/openlucid)) to ask for your data to be shown to you, corrected, or deleted.

## Changes to this page

If this changes, it'll change here, in the open, the same way everything else about this project does — check [the journey](/journey/) if you want to see how.
