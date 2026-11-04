// Small helpers shared by the views.

export function when(ts) {
  if (!ts) return "";
  const d = typeof ts.toDate === "function" ? ts.toDate() : new Date(ts);
  return d.toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
}

/** A response's answers in question order: [{id, n, q, lines}]. Answers carry their own question text. */
export function orderedAnswers(answers) {
  return Object.entries(answers || {})
    .map(([id, a]) => {
      const lines = [];
      if (Array.isArray(a.picked) && a.picked.length) lines.push(a.picked.join("; "));
      if (a.other) lines.push("Other: " + a.other);
      if (a.text) lines.push(a.text);
      if (a.comment) lines.push("Note: " + a.comment);
      return { id, n: Number(a.n) || 999, q: a.q || id, lines };
    })
    .sort((x, y) => x.n - y.n);
}

export const answeredCount = (r) => Object.keys(r.answers || {}).length;

// The public website (Hugo). The console runs on its own domain, app.openlucid.nl.
export const SITE = "https://openlucid.nl";

export const editUrl = (r) => `/responses/${r.id}/edit`;

let questionnairesPromise;
/** The questionnaires published on the website, with their questions (Hugo writes /questions/index.json). */
export function loadQuestionnaires() {
  questionnairesPromise ||= fetch(`${SITE}/questions/index.json`)
    .then((res) => (res.ok ? res.json() : { questionnaires: [] }))
    .then((j) => j.questionnaires || [])
    .catch(() => []);
  return questionnairesPromise;
}
