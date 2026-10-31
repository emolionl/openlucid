# Contributing to OpenLucid

Thank you for being here. OpenLucid is built to be understood by people who are new to programming, so questions are contributions too.

## Ways to help

- **Ask a question** by opening an issue. If something in the docs confused you, it will confuse the next person too.
- **Report a bug**: what you did, what you expected, what happened instead, and your operating system.
- **Improve the docs**: typos, clearer explanations, a missing step.
- **Write code**: pick an issue, say you're working on it, and open a pull request.

## Ground rules

1. **Brain data stays local.** No feature may send EEG or dream journals to the internet without the user explicitly choosing to.
2. **Sound and light cues only.** OpenLucid does not and will not drive electrical stimulation.
3. **No medical claims.** OpenLucid is an educational and self-experimentation tool, not a medical device. Docs and UI text must not promise health effects.
4. **Honest about uncertainty.** If something is unvalidated (for example, sleep staging accuracy on a Muse), say so.
5. **Be kind.** Everyone here was a beginner once.

## Before you open a pull request

- Backend: `cd backend && pytest`
- App: `cd frontend/desktop && flutter analyze && flutter test`
- Web: `cd frontend/web && npm run build`
- Website: `cd website && hugo`
