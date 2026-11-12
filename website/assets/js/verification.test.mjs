// Run: node --test website/assets/js/verification.test.mjs
import test from "node:test";
import assert from "node:assert/strict";
import * as V from "./verification.js";

const claim = { id: "c1", quote: "Gamma rises at 40 Hz.", source: { doi: "10.1093/sleep/32.9.1191" } };
const key = V.claimKey(claim);
const full = (agent, extra = {}) => ({ runId: "r1", agent, verdict: "supported", access: "full-text", quoteFound: true, checkedAt: 1000 + agent, contentHash: "h1", claimKey: key, ...extra });
const three = (extra3 = {}) => [full(1), full(2), full(3, extra3)];
const review = (verdict, at = 5, hash = "h1", extra = {}) => ({ createdAt: at, contentHash: hash, reviewerName: "Davor", scope: "all", verdicts: { c1: { verdict, claimKey: key, ...extra } } });

test("three different agents, full text, supported, quote found: agents agree", () => {
  assert.equal(V.claimState(claim, three(), [], "h1").outcome, "agents-agree");
});

test("'could not access' never counts as verified", () => {
  const s = V.claimState(claim, three({ verdict: "could-not-access", access: "none" }), [], "h1");
  assert.equal(s.outcome, "needs-human");
  assert.ok(s.agent.reasons.some((r) => r.includes("could not access")));
});

test("abstract-only access goes to a human", () => {
  assert.equal(V.claimState(claim, three({ access: "abstract-only" }), [], "h1").outcome, "needs-human");
});

test("disagreement goes to a human", () => {
  const s = V.claimState(claim, three({ verdict: "partly" }), [], "h1");
  assert.equal(s.outcome, "needs-human");
  assert.equal(s.agent.reasons[0], "the runs disagree");
});

test("a quote that isn't in the source goes to a human", () => {
  assert.equal(V.claimState(claim, three({ quoteFound: false }), [], "h1").outcome, "needs-human");
});

test("a check with no verdict at all is never 'supported'", () => {
  const noVerdict = [1, 2, 3].map((a) => full(a, { verdict: undefined }));
  assert.equal(V.claimState(claim, noVerdict, [], "h1").outcome, "needs-human");
});

test("one agent retried three times is not three agents", () => {
  const retries = [full(1), full(1, { checkedAt: 1002 }), full(1, { checkedAt: 1003 })];
  const s = V.claimState(claim, retries, [], "h1");
  assert.equal(s.outcome, "needs-human");
  assert.ok(s.agent.reasons.some((r) => r.includes("1 of 3")));
});

test("fewer than three checks goes to a human", () => {
  assert.equal(V.claimState(claim, [full(1), full(2)], [], "h1").outcome, "needs-human");
});

test("a check without a date goes to a human", () => {
  assert.equal(V.claimState(claim, three({ checkedAt: undefined }), [], "h1").outcome, "needs-human");
});

test("only the latest run counts, and latestRun doesn't reorder its input", () => {
  const checks = [full(3, { runId: "r0", checkedAt: 1, verdict: "not-supported" }), ...three()];
  const before = checks.map((c) => c.agent).join();
  assert.equal(V.claimState(claim, checks, [], "h1").outcome, "agents-agree");
  assert.equal(checks.map((c) => c.agent).join(), before);
});

test("a human verdict overrides the agents, latest review wins", () => {
  const s = V.claimState(claim, three(), [review("supported", 1), review("not-supported", 2)], "h1");
  assert.equal(s.outcome, "human-not-supported");
});

test("on a tie, the more cautious human verdict wins", () => {
  assert.equal(V.claimState(claim, [], [review("supported", 2), review("not-supported", 2)], "h1").outcome, "human-not-supported");
});

test("a human 'could not verify' leaves the claim open", () => {
  const s = V.claimState(claim, [], [review("could-not-verify")], "h1");
  assert.equal(s.outcome, "needs-human");
  assert.equal(V.isResolved(s), false);
});

test("editing the claim's sentence or source invalidates earlier verdicts and checks", () => {
  const edited = { ...claim, source: { doi: "10.1000/other" } };
  const s = V.claimState(edited, three(), [review("supported")], "h1");
  assert.equal(s.outcome, "stale");
  assert.equal(V.isResolved(s), false);
});

test("a verdict without a claim key doesn't count", () => {
  const r = { createdAt: 1, contentHash: "h1", verdicts: { c1: { verdict: "supported" } } };
  assert.equal(V.claimState(claim, [], [r], "h1").outcome, "stale");
});

test("a verdict stays valid after unrelated text changes, while the exact sentence is still there", () => {
  const s = V.claimState(claim, [], [review("supported", 5, "h1")], "h2", true);
  assert.equal(s.outcome, "human-supported");
  assert.equal(s.humanTextChanged, true);
});

test("once the sentence is no longer in the text, its verdicts don't count", () => {
  assert.equal(V.claimState(claim, three(), [review("supported")], "h1", false).outcome, "stale");
});

test("malformed verdicts are ignored, never treated as supported", () => {
  const r = { createdAt: 1, contentHash: "h1", verdicts: { c1: "supported" } };
  const r2 = { createdAt: 2, contentHash: "h1", verdicts: { c1: { verdict: "yes", claimKey: key } } };
  assert.equal(V.claimState(claim, [], [r, r2], "h1").outcome, "unchecked");
});

const states = (list, reviews, hash = "h1") => list.map(([c, checks, present = true]) => V.claimState(c, checks, reviews, hash, present));
const c2 = { id: "c2", quote: "Second claim.", source: { url: "https://example.org/a" } };

test("published needs every claim supported and a review with verdicts of the current text", () => {
  const reviews = [review("supported")];
  let sum = V.summarize({ review: { status: "draft" }, states: states([[claim, []], [c2, []]], reviews), humanReviews: reviews, currentHash: "h1" });
  assert.equal(sum.open, 1);
  assert.equal(V.allowedStatuses(sum).published, false);
  assert.equal(V.allowedStatuses(sum)["human-reviewed"], true);

  sum = V.summarize({ review: { status: "draft" }, states: [states([[claim, []]], reviews)[0], V.claimState({ ...c2, state: "removed" }, [], reviews, "h1")], humanReviews: reviews, currentHash: "h1" });
  assert.equal(V.allowedStatuses(sum).published, true);
});

test("a not-supported claim blocks Published even though it is decided", () => {
  const reviews = [review("not-supported")];
  const sum = V.summarize({ review: null, states: states([[claim, []]], reviews), humanReviews: reviews, currentHash: "h1" });
  assert.equal(sum.resolved, 1);
  assert.equal(sum.problems, 1);
  assert.equal(V.allowedStatuses(sum).published, false);
});

test("a review without verdicts unlocks nothing", () => {
  const empty = { createdAt: 9, contentHash: "h1", reviewerName: "X", scope: "looked at it", verdicts: {} };
  const sum = V.summarize({ review: null, states: states([[claim, three()]], [empty]), humanReviews: [empty], currentHash: "h1" });
  assert.equal(sum.humanLabel, null);
  assert.equal(V.allowedStatuses(sum)["human-reviewed"], false);
});

test("a review of older text doesn't allow Human-reviewed or Published", () => {
  const reviews = [review("supported", 5, "h1")];
  const sum = V.summarize({ review: null, states: states([[claim, []]], reviews, "h2"), humanReviews: reviews, currentHash: "h2" });
  assert.equal(sum.humanLabel.stale, true);
  assert.equal(V.allowedStatuses(sum).published, false);
});

test("without a text hash, nothing past Draft is allowed", () => {
  const reviews = [review("supported")];
  const sum = V.summarize({ review: null, states: states([[claim, three()]], reviews, ""), humanReviews: reviews, currentHash: "" });
  assert.deepEqual(V.allowedStatuses(sum), { draft: true, "ai-checked": false, "human-reviewed": false, published: false });
});

test("the shown status is capped by what the data supports now", () => {
  const reviews = [review("supported", 5, "h1")];
  const now = V.summarize({ review: null, states: states([[claim, three()]], reviews, "h1"), humanReviews: reviews, currentHash: "h1" });
  assert.equal(V.shownStatus("published", now), "published");
  const later = V.summarize({ review: null, states: states([[claim, three()]], reviews, "h2"), humanReviews: reviews, currentHash: "h2" });
  assert.equal(V.shownStatus("published", later), "ai-checked");
  assert.equal(V.shownStatus("nonsense", now), "draft");
});

test("the agent label counts complete runs against all claims", () => {
  const sum = V.summarize({ review: null, states: states([[claim, three()], [c2, []]], []), humanReviews: [], currentHash: "h1" });
  assert.deepEqual([sum.agentLabel.claims, sum.agentLabel.checked, sum.agentLabel.agree], [2, 1, 1]);
});

test("source links: DOIs and http(s) only, never javascript:", () => {
  assert.equal(V.sourceLink({ doi: "https://doi.org/10.2466/pms.1981.52.3.727" }), "https://doi.org/10.2466/pms.1981.52.3.727");
  assert.equal(V.sourceLink({ url: "https://example.org/x" }), "https://example.org/x");
  assert.equal(V.sourceLink({ url: "javascript:alert(1)" }), "");
  assert.equal(V.sourceLink({ url: " JavaScript:alert(1)" }), "");
  assert.equal(V.sourceLink({ url: "data:text/html,<script>1</script>" }), "");
  assert.equal(V.normalizeDoi("doi:10.1093/sleep/32.9.1191."), "10.1093/sleep/32.9.1191");
});

test("claim keys change with the sentence or source, not with whitespace or field order", () => {
  assert.equal(V.claimKey({ quote: "a  b", source: { doi: "x", citation: "c" } }), V.claimKey({ quote: "a b", source: { citation: "c", doi: "x" } }));
  assert.notEqual(V.claimKey({ quote: "a b", source: { doi: "x" } }), V.claimKey({ quote: "a b", source: { doi: "y" } }));
  assert.notEqual(V.claimKey({ quote: "a b" }), V.claimKey({ quote: "a c" }));
  assert.match(V.claimKey(claim), /^[0-9a-f]{16}$/);
});

test("content hash ignores line endings and outer whitespace", async () => {
  assert.equal(await V.contentHash("a\r\nb\n"), await V.contentHash("a\nb"));
  assert.notEqual(await V.contentHash("a b"), await V.contentHash("a  b"));
});

test("a newer verdict about another version can't hide a current 'not supported'", () => {
  const otherKey = V.claimKey({ ...claim, source: { doi: "10.9/b" } });
  const reviews = [review("not-supported", 1), { createdAt: 2, contentHash: "h1", reviewerName: "R", scope: "x", verdicts: { c1: { verdict: "supported", claimKey: otherKey } } }];
  const s = V.claimState(claim, three(), reviews, "h1");
  assert.equal(s.outcome, "human-not-supported");
  const sum = V.summarize({ review: null, states: [s], humanReviews: reviews, currentHash: "h1" });
  assert.equal(V.allowedStatuses(sum).published, false);
  assert.equal(sum.agentLabel.agree, 0, "the agent label doesn't count a claim a reviewer rejected");
  assert.equal(sum.agentLabel.overruled, 1);
});

test("the human label goes stale when the claim list changes, even if the text doesn't", () => {
  const reviews = [review("supported", 5)];
  const edited = { ...claim, source: { doi: "10.9/b" } };
  const sum = V.summarize({ review: null, states: [V.claimState(edited, [], reviews, "h1")], humanReviews: reviews, currentHash: "h1" });
  assert.equal(sum.humanLabel, null, "a review whose only verdict no longer matches counts for nothing");
  const added = { id: "c9", quote: "New.", source: {}, createdAt: 10 };
  const sum2 = V.summarize({ review: null, states: [V.claimState(claim, [], reviews, "h1"), V.claimState(added, [], reviews, "h1")], humanReviews: reviews, currentHash: "h1" });
  assert.equal(sum2.humanLabel.stale, true);
  assert.equal(V.allowedStatuses(sum2)["human-reviewed"], false);
});

test("junk or 'could not verify'-only reviews don't make a page Human-reviewed", () => {
  const junk = { createdAt: 5, contentHash: "h1", reviewerName: "X", scope: "x", verdicts: { zzz: "lol" } };
  const cnv = review("could-not-verify", 6);
  const sum = V.summarize({ review: null, states: [V.claimState(claim, [], [junk, cnv], "h1")], humanReviews: [junk, cnv], currentHash: "h1" });
  assert.equal(sum.humanLabel, null);
});

test("AI-checked needs at least one claim all 3 agents could read in full", () => {
  const blocked = [1, 2, 3].map((a) => full(a, { verdict: "could-not-access", access: "none" }));
  const sum = V.summarize({ review: null, states: [V.claimState(claim, blocked, [], "h1")], humanReviews: [], currentHash: "h1" });
  assert.equal(V.allowedStatuses(sum)["ai-checked"], false);
});

test("agent ids '1', 1 and '01' are one agent", () => {
  const s = V.claimState(claim, [full("1"), full(1, { checkedAt: 1002 }), full("01", { checkedAt: 1003 })], [], "h1");
  assert.equal(s.outcome, "needs-human");
});

test("ids for reviews", () => {
  assert.equal(V.reviewIdForPage("/course/11-from-signal/"), "page:course:11-from-signal");
  assert.equal(V.reviewIdForDocument("abc"), "documents:abc");
  assert.equal(V.quoteIn("Some   text here.", "text here"), true);
  assert.equal(V.quoteIn("Some text", ""), false);
});
