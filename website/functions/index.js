// Cloud Functions for openlucid.nl.
//
// notifyNewResponse:     a questionnaire response was added on openlucid.nl/questions/ -> email it
// notifyChangedResponse: someone changed their answers at user.openlucid.nl            -> email it
// Both go to the maintainer through Brevo's transactional email API (same setup as emolio.nl).
//
// Secret:  BREVO_API_KEY   set with: firebase functions:secrets:set BREVO_API_KEY
// Params:  NOTIFY_EMAIL    who gets the email (functions/.env)

const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { defineSecret, defineString } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const { buildEmail } = require("./email");

const BREVO_API_KEY = defineSecret("BREVO_API_KEY");
const NOTIFY_EMAIL = defineString("NOTIFY_EMAIL", { default: "info@emolio.nl" });

const SENDER = { name: "OpenLucid", email: "info@emolio.nl" };
const CONSOLE = "https://user.openlucid.nl";
const options = { document: "responses/{id}", region: "europe-west1", secrets: [BREVO_API_KEY], retry: false };

async function notify(response, docId, changed) {
  const email = buildEmail(response, {
    docId,
    changed,
    pageUrl: `https://openlucid.nl/questions/${encodeURIComponent(response.questionnaire || "")}/`,
    consoleUrl: `${CONSOLE}/responses/${encodeURIComponent(docId)}`,
  });

  const res = await fetch("https://api.brevo.com/v3/smtp/email", {
    method: "POST",
    headers: { "api-key": BREVO_API_KEY.value(), "content-type": "application/json", accept: "application/json" },
    body: JSON.stringify({
      sender: SENDER,
      to: [{ email: NOTIFY_EMAIL.value() }],
      subject: email.subject,
      htmlContent: email.html,
      textContent: email.text,
      tags: ["openlucid-questions"],
    }),
  });

  if (!res.ok) {
    // The response itself is safe in Firestore; only the notification failed.
    logger.error("Brevo refused the notification", { status: res.status, body: await res.text(), docId });
    return;
  }
  logger.info("Notification sent", { docId, questionnaire: response.questionnaire, changed });
}

exports.notifyNewResponse = onDocumentCreated(options, async (event) => {
  const response = event.data?.data();
  if (response) await notify(response, event.params.id, false);
});

exports.notifyChangedResponse = onDocumentUpdated(options, async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!after || JSON.stringify(before?.answers) === JSON.stringify(after.answers)) return;
  await notify(after, event.params.id, true);
});
