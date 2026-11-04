const test = require("node:test");
const assert = require("node:assert");
const { buildEmail } = require("./email");

const ctx = { docId: "abc123", pageUrl: "https://openlucid.nl/questions/muse-dry-contact/", consoleUrl: "https://console.example/abc123" };

test("answers come out in question order, with every part", () => {
  const { text } = buildEmail(
    {
      questionnaire: "muse-dry-contact",
      title: "Questions for EEG and sleep experts",
      name: "A. Expert",
      answers: {
        p_read: { n: 13, q: "Papers?", text: "Read Esfahani 2023" },
        c_method: { n: 3, q: "Which methods?", picked: ["Gel", "Hydrogel"], other: "Ten20", comment: "thin layer" },
      },
    },
    ctx
  );
  assert.ok(text.indexOf("03. Which methods?") < text.indexOf("13. Papers?"));
  assert.match(text, /Gel; Hydrogel/);
  assert.match(text, /Other: Ten20/);
  assert.match(text, /Note: thin layer/);
});

test("visitor text is escaped in the HTML and kept to one line in the subject", () => {
  const { html, subject } = buildEmail(
    { questionnaire: "x", title: "T", name: "<b>Eve</b>\nBcc: x@y", answers: { a: { n: 1, q: "<script>", text: "<img src=x onerror=alert(1)>" } } },
    ctx
  );
  assert.ok(!html.includes("<script>"));
  assert.ok(!html.includes("<img src=x"));
  assert.ok(!html.includes("<b>Eve</b>"));
  assert.ok(!subject.includes("\n"));
});

test("a response without a name still reads well", () => {
  const { subject } = buildEmail({ questionnaire: "x", title: "T", answers: { a: { n: 1, q: "Q", text: "yes" } } }, ctx);
  assert.match(subject, /someone who didn't give a name/);
});

test("changed answers say so in the subject", () => {
  const { subject, text } = buildEmail({ questionnaire: "x", title: "T", name: "A", answers: { a: { n: 1, q: "Q", text: "yes" } } }, { ...ctx, changed: true });
  assert.match(subject, /^Changed answers: T/);
  assert.match(text, /changed their answers to/);
});
