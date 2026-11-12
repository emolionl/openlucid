// What counts as verified on OpenLucid. One module, used by the public pages (/d/) and the console,
// so a label can never claim more than the review data supports.
//
// Data (Firestore, see website/firestore.rules):
//   reviews/{contentId}                        status, title, kind, ref
//   reviews/{contentId}/claims/{claimId}       quote (exact text on our page), source {doi, url, citation}
//   .../claims/{claimId}/checks/{checkId}      one agent's check, written only by the server
//   reviews/{contentId}/humanReviews/{id}      one person's review, append-only
//
// The rules that matter:
//   - A verdict is about one exact sentence and one exact source (the claim key). It stays valid only
//     while that sentence is still word-for-word in the text and the claim's source is unchanged.
//   - A claim is agent-verified only if the latest run has checks from 3 different agents, and every
//     one of them explicitly found it supported, read the full text, and quoted a passage that really
//     occurs in the source. Anything else, including a missing field, goes to a human.
//   - "Could not access" and "abstract only" never count as verified.
//   - A current human verdict overrides the agents for that claim.
//   - Published needs every claim supported (not just decided), and a human review of the current text.
//   - The status a page shows is capped by what the data supports right now.

export const STATUSES = ["draft", "ai-checked", "human-reviewed", "published"];

export const STATUS_LABELS = {
  draft: "Draft",
  "ai-checked": "AI-checked",
  "human-reviewed": "Human-reviewed",
  published: "Published",
};

export const AGENT_VERDICTS = ["supported", "not-supported", "partly", "could-not-access"];
export const HUMAN_VERDICTS = ["supported", "not-supported", "partly", "could-not-verify"];
export const ACCESS = ["full-text", "abstract-only", "none"];

export const VERDICT_LABELS = {
  supported: "Supported",
  "not-supported": "Not supported",
  partly: "Partly supported",
  "could-not-access": "Could not access",
  "could-not-verify": "Could not verify",
};

// The per-claim outcome after combining agents and people.
export const OUTCOME_LABELS = {
  unchecked: "Not checked yet",
  stale: "Checked an earlier version",
  "agents-agree": "Supported (3 Claude runs agree)",
  "needs-human": "Needs a human",
  "human-supported": "Supported (human-checked)",
  "human-partly": "Partly supported (human-checked)",
  "human-not-supported": "Not supported (human-checked)",
  removed: "Removed from the page",
};

// The steps of "How to verify a source"; a human review records which of them were done.
export const CHECKLIST = [
  { key: "original", label: "Found the original publication (via the DOI), not a summary of it" },
  { key: "fullText", label: "Read the full text, not just the abstract" },
  { key: "exactPlace", label: "Found the exact page or section that supports each claim" },
  { key: "numbers", label: "Checked every number exactly against the source" },
  { key: "notStronger", label: "Checked that our wording is not stronger than the source" },
  { key: "retractions", label: "Checked for retractions and corrections" },
];

export const AGENT_RUNS_REQUIRED = 3;

const collapse = (s) => String(s ?? "").replace(/\s+/g, " ").trim();

/** SHA-256 (hex) of the text as checked. Line endings and outer whitespace don't count as changes. */
export async function contentHash(text) {
  const normalized = String(text ?? "").replace(/\r\n?/g, "\n").trim();
  const bytes = new TextEncoder().encode(normalized);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Firestore Timestamp, Date, ISO string or millis -> millis (0 when missing). */
export function millis(t) {
  if (!t) return 0;
  if (typeof t.toMillis === "function") return t.toMillis();
  if (t instanceof Date) return t.getTime();
  if (typeof t === "number") return t;
  if (typeof t.seconds === "number") return t.seconds * 1000;
  const n = Date.parse(t);
  return Number.isNaN(n) ? 0 : n;
}

/** "doi:10.x/y", "https://doi.org/10.x/y" or a bare "10.x/y" -> "10.x/y" (or "" when none). */
export function normalizeDoi(s) {
  const m = String(s ?? "").trim().match(/10\.\d{4,9}\/\S+/);
  return m ? m[0].replace(/[.,;)\]]+$/, "") : "";
}

/** A safe link for a source: the DOI, or an http(s) URL. Anything else (javascript:, data:) gives "". */
export function sourceLink(source) {
  const doi = normalizeDoi(source?.doi);
  if (doi) return `https://doi.org/${encodeURI(doi)}`;
  try {
    const u = new URL(String(source?.url || ""));
    return u.protocol === "https:" || u.protocol === "http:" ? u.href : "";
  } catch (e) {
    return "";
  }
}

/** The source with its fields in a fixed order and empty ones left out, for comparing two sources. */
export function sortedSource(source) {
  const out = {};
  for (const k of ["citation", "doi", "url"]) if (source?.[k]) out[k] = String(source[k]).trim();
  return out;
}

/**
 * A short fingerprint of exactly what a verdict is about: the sentence and the source. Stored with
 * every human verdict and agent check; when the claim is edited, old verdicts no longer match.
 */
export function claimKey(claim) {
  const s = [collapse(claim?.quote), JSON.stringify(sortedSource(claim?.source))].join("\u0001");
  // Two 32-bit FNV-1a variants -> 16 hex characters. Not secret, only needs to change when the claim does.
  let a = 0x811c9dc5, b = 0x01000193 ^ 0x5bd1e995;
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    a = Math.imul(a ^ c, 0x01000193) >>> 0;
    b = Math.imul(b ^ c, 0x01000193 + 2) >>> 0;
  }
  return a.toString(16).padStart(8, "0") + b.toString(16).padStart(8, "0");
}

/** Is this exact sentence (whitespace aside) in the text a reader sees? */
export const quoteIn = (plainText, quote) => Boolean(collapse(quote)) && collapse(plainText).includes(collapse(quote));

/** The checks of the most recent agent run for one claim (checks carry a runId). Doesn't change its input. */
export function latestRun(checks) {
  if (!checks?.length) return null;
  const runs = new Map();
  for (const c of checks) {
    const id = c.runId || "run";
    if (!runs.has(id)) runs.set(id, []);
    runs.get(id).push(c);
  }
  let best = null;
  for (const [runId, list] of runs) {
    const at = Math.max(...list.map((c) => millis(c.checkedAt)));
    if (!best || at > best.at) best = { runId, at, checks: [...list].sort((x, y) => (x.agent || 0) - (y.agent || 0)) };
  }
  return best;
}

/** The agents' combined verdict for one run, with plain reasons when a human is needed. */
export function agentOutcome(run) {
  if (!run) return { outcome: "unchecked", reasons: [] };
  const reasons = [];
  const checks = run.checks;
  // "1", 1 and "01" are the same agent.
  const agents = new Set(checks.map((c) => String(Number(c.agent))));
  if (agents.size < AGENT_RUNS_REQUIRED) reasons.push(`only ${agents.size} of ${AGENT_RUNS_REQUIRED} independent runs finished`);
  if (agents.size < checks.length) reasons.push("one run was counted more than once");
  checks.forEach((c) => {
    const who = `Run ${c.agent ?? "?"}`;
    if (!millis(c.checkedAt)) reasons.push(`${who} has no date`);
    if (c.verdict === "could-not-access" || c.access === "none") reasons.push(`${who} could not access the source`);
    else if (c.access !== "full-text") reasons.push(`${who} could only read ${c.access === "abstract-only" ? "the abstract" : "part of the source"}`);
    if (c.verdict !== "supported" && c.verdict !== "could-not-access") reasons.push(`${who}: ${VERDICT_LABELS[c.verdict] || "no verdict"}`);
    if (c.verdict === "supported" && c.quoteFound !== true) reasons.push(`${who}'s quoted passage was not found in the source text`);
  });
  if (new Set(checks.map((c) => c.verdict)).size > 1) reasons.unshift("the runs disagree");
  return { outcome: reasons.length ? "needs-human" : "agents-agree", reasons: [...new Set(reasons)] };
}

// When two verdicts are equally recent, the more cautious one wins.
const CAUTION = { "not-supported": 4, partly: 3, "could-not-verify": 2, supported: 1 };

/**
 * The most recent human verdict for one claim, with the review it came from. With a claim key, only
 * verdicts about exactly that version of the claim count, so a newer verdict about a different
 * wording can't hide an older verdict about this one.
 */
export function latestHumanVerdict(claimId, humanReviews, key = null) {
  let best = null;
  for (const r of humanReviews || []) {
    const v = r.verdicts?.[claimId];
    if (!v || typeof v !== "object" || !HUMAN_VERDICTS.includes(v.verdict)) continue;
    if (key !== null && v.claimKey !== key) continue;
    const at = millis(r.createdAt);
    const better = !best || at > best.at || (at === best.at && (CAUTION[v.verdict] || 0) > (CAUTION[best.verdict] || 0));
    if (better) best = { ...v, review: r, at };
  }
  return best;
}

const HUMAN_OUTCOME = {
  supported: "human-supported",
  partly: "human-partly",
  "not-supported": "human-not-supported",
  "could-not-verify": "needs-human",
};

/**
 * Everything a page needs to show about one claim.
 * quotePresent: whether the claim's sentence is still word-for-word in the current text.
 */
export function claimState(claim, checks, humanReviews, currentHash, quotePresent = true) {
  const key = claimKey(claim);
  if (claim.state === "removed") return { claim, key, outcome: "removed", agent: { outcome: "unchecked", reasons: [] }, run: null, human: null, quotePresent };

  const run = latestRun(checks);
  const agent = agentOutcome(run);
  // A run or verdict is about the claim as it was; it no longer counts once the sentence or source changed.
  const agentStale = Boolean(run) && (!quotePresent || run.checks.some((c) => c.claimKey !== key));
  const agentTextChanged = Boolean(run) && run.checks.some((c) => !currentHash || c.contentHash !== currentHash);

  // Prefer a verdict about this exact version of the claim; otherwise show the latest one, as stale.
  const current = latestHumanVerdict(claim.id, humanReviews, key);
  const human = current || latestHumanVerdict(claim.id, humanReviews);
  const humanStale = Boolean(human) && (!quotePresent || !current);
  const humanTextChanged = Boolean(human) && (!currentHash || human.review.contentHash !== currentHash);

  let outcome;
  if (human && !humanStale) outcome = HUMAN_OUTCOME[human.verdict] || "needs-human";
  else if (run && !agentStale) outcome = agent.outcome;
  else if (run || human) outcome = "stale";
  else outcome = "unchecked";

  return { claim, key, outcome, agent, run, human, agentStale, humanStale, agentTextChanged, humanTextChanged, quotePresent };
}

/** Decided (by agents or a person) for the claim as it stands now. */
export const isResolved = (s) => s.outcome === "removed" || s.outcome === "agents-agree" || s.outcome.startsWith("human-");
/** Supported for the claim as it stands now: the only outcomes that allow Published. */
export const isSupported = (s) => s.outcome === "agents-agree" || s.outcome === "human-supported";

// The verdicts of one review that are about a claim exactly as it stands now.
function currentVerdicts(review, keysById) {
  return Object.entries(review?.verdicts || {}).filter(([id, v]) => v && typeof v === "object" && HUMAN_VERDICTS.includes(v.verdict) && keysById.get(id) === v.claimKey);
}

// A review counts as a review only if it judged at least one current claim (not just "couldn't verify").
const judgesSomething = (review, keysById) => currentVerdicts(review, keysById).some(([, v]) => v.verdict !== "could-not-verify");

/**
 * The labels for a page: status, the agent label and the human label, each saying exactly what it
 * covers. Returns null fields for labels that don't apply yet.
 */
export function summarize({ review, states, humanReviews, currentHash }) {
  const active = states.filter((s) => s.outcome !== "removed");
  const keysById = new Map(active.filter((s) => s.quotePresent !== false).map((s) => [s.claim.id, s.key]));
  const complete = active.filter((s) => s.run && !s.agentStale && new Set(s.run.checks.map((c) => String(Number(c.agent)))).size >= AGENT_RUNS_REQUIRED);
  // A reviewer's current verdict other than "supported" overrules the agents for that claim.
  const overruled = (s) => s.human && !s.humanStale && s.human.verdict !== "supported";

  const agentLabel = active.some((s) => s.run)
    ? {
        claims: active.length,
        checked: complete.length,
        fullText: complete.filter((s) => s.run.checks.every((c) => c.access === "full-text")).length,
        agree: complete.filter((s) => s.agent.outcome === "agents-agree" && !overruled(s)).length,
        overruled: complete.filter((s) => s.agent.outcome === "agents-agree" && overruled(s)).length,
        toHuman: complete.filter((s) => s.agent.outcome === "needs-human").length,
        stale: active.some((s) => s.run && (s.agentStale || s.agentTextChanged)),
        lastAt: Math.max(0, ...active.filter((s) => s.run).map((s) => s.run.at)),
      }
    : null;

  // Only reviews that judged at least one current claim count as reviews on the label.
  const counted = (humanReviews || []).filter((r) => judgesSomething(r, keysById));
  const latest = [...counted].sort((a, b) => millis(b.createdAt) - millis(a.createdAt))[0];
  let humanLabel = null;
  if (latest) {
    const now = currentVerdicts(latest, keysById);
    const all = Object.keys(latest.verdicts || {}).length;
    // Claims added after the review weren't part of it.
    const addedSince = active.filter((s) => millis(s.claim.createdAt) > millis(latest.createdAt)).length;
    humanLabel = {
      name: latest.reviewerName,
      at: millis(latest.createdAt),
      scope: latest.scope,
      verdicts: now.length,
      supported: now.filter(([, v]) => v.verdict === "supported").length,
      stale: !currentHash || latest.contentHash !== currentHash || now.length < all || addedSince > 0,
      addedSince,
      reviewers: [...new Set(counted.map((r) => r.reviewerName))],
    };
  }

  return {
    status: review?.status || null,
    hasReview: Boolean(review),
    claims: active.length,
    resolved: active.filter(isResolved).length,
    supported: active.filter(isSupported).length,
    open: active.filter((s) => !isResolved(s)).length,
    problems: active.filter((s) => isResolved(s) && !isSupported(s)).length,
    agentLabel,
    humanLabel,
    currentHash: currentHash || "",
  };
}

/**
 * Which statuses a page may have now.
 *   AI-checked:     at least one claim with a complete, current run of 3 agents that all read the full text.
 *   Human-reviewed: a human review that judged current claims, of the current text and claim list.
 *   Published:      that, and every claim supported for the claim as it stands now.
 */
export function allowedStatuses(summary) {
  if (!summary.currentHash) return { draft: true, "ai-checked": false, "human-reviewed": false, published: false };
  const reviewedNow = Boolean(summary.humanLabel && !summary.humanLabel.stale);
  return {
    draft: true,
    // At least one claim that 3 agents could actually read in full.
    "ai-checked": Boolean(summary.agentLabel && summary.agentLabel.fullText > 0),
    "human-reviewed": reviewedNow,
    published: reviewedNow && summary.claims > 0 && summary.supported === summary.claims,
  };
}

/** The status to show: the stored one, or the highest lower one the data still supports. */
export function shownStatus(stored, summary) {
  const allowed = allowedStatuses(summary);
  const i = STATUSES.indexOf(stored);
  if (i < 0) return "draft";
  for (let j = i; j >= 0; j--) if (allowed[STATUSES[j]]) return STATUSES[j];
  return "draft";
}

/** The id under reviews/ for a Firestore document or a Hugo page (Firestore ids can't contain "/"). */
export const reviewIdForDocument = (docId) => `documents:${docId}`;
export const reviewIdForPage = (path) => `page:${String(path).replace(/^\/+|\/+$/g, "").replace(/\//g, ":")}`;
