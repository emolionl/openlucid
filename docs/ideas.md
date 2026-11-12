# Ideas for later

Things we want to build or teach, but not yet. Add yours.

## Course and learning

- **Contact Detective (three.js game).** A 3D head with a headband. The player moves sensors, adds moisture, tightens the strap, and watches the live signal change: floating sensors catch the mains hum, two floating sensors look identical, a sensor that just touched skin drifts slowly, a good sensor shows alpha when the character closes its eyes. Teaches the lesson from [Day 1, part 2](journey/2026-11-01-day-01b-what-bad-contact-looks-like.md) by playing instead of reading.
- **A lesson on reading raw EEG data** built around `tools/analyze_raw_muse.py`: is it my code, or is it the skin?

## App

- **Settling phase** before a night: wait for good contact and say which sensor is still settling.
- **Contact quality recorded all night**, shown in the morning report.
- **"Identical channels" warning** in the contact check.
- **Use the best sensors available.** The forehead sensors (AF7, AF8) carry what OpenLucid needs most (eye movements, the left-right signal); if the ear sensors stay poor during the night, carry on with the forehead and say so in the report.
- **Other headbands:** OpenBCI, ZMax, BrainBit, and the Muse S Athena (MS-03, different protocol).

## Review and verification

Step 1 is built: claims, human reviews and labels for `/d/` documents (`website/assets/js/verification.js`, `reviews/` in `website/firestore.rules`). Still to do:

- **TODO: the three Claude checks per claim (step 2).** A Cloud Function that runs three independent checks per claim (each gets only the claim and the source), records verdict, access, location, quoted passage, model and date, and verifies the quoted passage really occurs in the fetched text. Plus the Crossref retraction check, and a PDF upload for paywalled sources (Wiley and KNAW return 403). **Needs an Anthropic API key first:** create one in the Anthropic Console with a monthly spending cap, then `firebase functions:secrets:set ANTHROPIC_API_KEY --project openlucid`. Rough cost: about $0.15 per check, $0.45 per claim, so roughly $10–20 for the NWO draft. Each check the server writes must carry `claimKey` (from `claimKey()` in `verification.js`, the same function, not a copy), the document's `contentHash`, a `runId`, `checkedAt`, and a fixed agent number 1, 2 or 3; otherwise the logic rightly refuses to count it.
- **TODO: Markdown pages in the workflow (step 3).** A `review:` front-matter status (drafts get noindex and stay out of navigation, lists and the sitemap), and a build step that exports the review data to JSON so the real labels end up in the HTML instead of "Not yet verified".
- **TODO: tutorial page "How to verify a source" (step 4):** find the original via the DOI, read the full text rather than the abstract, find the exact page, check numbers exactly, check the claim isn't stronger than the source, check for retractions, record the result. Verified with this same workflow.
- **TODO: verification appendix in PDF/Word export (step 5)**, as a fourth export toggle on `/d/`.

## Related work to read and cite

- An open-source watchOS app for targeted lucidity reactivation, *International Journal of Dream Research* (2024).
