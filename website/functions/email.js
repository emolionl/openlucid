// Turns one questionnaire response (as stored in Firestore "responses") into an email.
// Everything in a response was typed by a website visitor, so all of it is escaped before it goes into HTML.

const escape = (s) =>
  String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");

const oneLine = (s, max) => String(s ?? "").replace(/[\r\n]+/g, " ").slice(0, max);

/** The answers in question order: [{n, q, lines: [...]}]. */
function orderedAnswers(answers) {
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

function buildEmail(response, { docId, consoleUrl, pageUrl, changed = false }) {
  const title = oneLine(response.title || response.questionnaire, 120);
  const who = oneLine(response.name, 80) || "someone who didn't give a name";
  const items = orderedAnswers(response.answers);

  const subject = `${changed ? "Changed answers" : "New answers"}: ${title} (from ${who})`;

  const text = [
    `${who} ${changed ? "changed their answers to" : "answered"} "${title}".`,
    "",
    ...items.flatMap((i) => [`${String(i.n).padStart(2, "0")}. ${i.q}`, ...i.lines.map((l) => "   " + l), ""]),
    `Questionnaire: ${pageUrl}`,
    `In the console: ${consoleUrl}`,
  ].join("\n");

  const rows = items
    .map(
      (i) => `
      <tr><td style="padding:14px 0 4px;color:#5a6080;font-size:13px;">${escape(String(i.n).padStart(2, "0"))}. ${escape(i.q)}</td></tr>
      <tr><td style="padding:0 0 12px;border-bottom:1px solid #e6e8f2;font-size:15px;white-space:pre-wrap;">${i.lines.map(escape).join("<br>")}</td></tr>`
    )
    .join("");

  const html = `
  <div style="font-family:-apple-system,'Segoe UI',Arial,sans-serif;max-width:620px;margin:0 auto;color:#1a1d33;">
    <div style="background:#0c1124;padding:24px 28px;border-radius:12px 12px 0 0;">
      <p style="margin:0;color:#8c98ff;font-size:13px;font-weight:600;">OpenLucid · ${changed ? "changed answers" : "new answers"}</p>
      <h1 style="margin:6px 0 0;color:#f2f3fa;font-size:20px;">${escape(title)}</h1>
      <p style="margin:6px 0 0;color:#a4a9c8;font-size:14px;">From ${escape(who)} · ${items.length} answered</p>
    </div>
    <div style="background:#ffffff;padding:8px 28px 24px;border:1px solid #e6e8f2;border-top:0;border-radius:0 0 12px 12px;">
      <table role="presentation" style="width:100%;border-collapse:collapse;">${rows}</table>
      <p style="margin:20px 0 0;font-size:13px;color:#5a6080;">
        <a href="${escape(pageUrl)}" style="color:#4a56d6;">Open the questionnaire</a> ·
        <a href="${escape(consoleUrl)}" style="color:#4a56d6;">Open it in the console</a> · id ${escape(docId)}
      </p>
    </div>
  </div>`;

  return { subject, text, html };
}

module.exports = { buildEmail, escape, orderedAnswers };
