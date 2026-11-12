<script setup>
import { ref, reactive, computed, onMounted } from "vue";
import { useRoute } from "vue-router";
import { doc, getDoc, getDocs, setDoc, addDoc, updateDoc, collection, serverTimestamp, deleteField, runTransaction } from "firebase/firestore";
import { db } from "../firebase";
import { session, canSignOff, isAdmin } from "../session";
import { when, docLink } from "../lib/format";
import * as V from "../../../assets/js/verification.js";
import { marked } from "marked";

// Review one document: list the claims and their sources, see what the agents found, and sign off
// what you checked yourself. Everything shown on the public page's labels comes from here
// (rules: firestore.rules -> reviews; logic: assets/js/verification.js).
const route = useRoute();
const docId = route.params.id;
const rid = V.reviewIdForDocument(docId);

const loading = ref(true);
const problem = ref("");
const document = ref(null);
const review = ref(null);
const claims = ref([]);
const checks = ref({});
const humanReviews = ref([]);
const hash = ref("");
const myName = ref("");
const status = ref("");

// quoteIn: a verdict only counts while its exact sentence is still in the text (see verification.js).
const states = computed(() => claims.value.map((c) => V.claimState(c, checks.value[c.id] || [], humanReviews.value, hash.value, V.quoteIn(plainBody.value, c.quote))));
const activeStates = computed(() => states.value.filter((s) => s.outcome !== "removed"));
const summary = computed(() => V.summarize({ review: review.value, states: activeStates.value, humanReviews: humanReviews.value, currentHash: hash.value }));
const allowed = computed(() => V.allowedStatuses(summary.value));
// What the public page shows: the stored status, capped by what the review data still supports.
const shownStatus = computed(() => (review.value ? V.shownStatus(review.value.status, summary.value) : null));

onMounted(() => load());

// The first load shows "Loading…"; reloads after a save happen quietly, keeping scroll and open panels.
async function load({ quiet = false } = {}) {
  if (!quiet) loading.value = true;
  problem.value = "";
  try {
    const [d, r, c, h, me] = await Promise.all([
      getDoc(doc(db, "documents", docId)),
      getDoc(doc(db, "reviews", rid)),
      getDocs(collection(db, "reviews", rid, "claims")),
      getDocs(collection(db, "reviews", rid, "humanReviews")),
      getDoc(doc(db, "users", session.user.uid)),
    ]);
    if (!d.exists()) { problem.value = "This document doesn't exist."; return; }
    document.value = { id: d.id, ...d.data() };
    review.value = r.exists() ? r.data() : null;
    claims.value = c.docs.map((x) => ({ id: x.id, ...x.data() })).sort((a, b) => (a.order || 0) - (b.order || 0));
    humanReviews.value = h.docs.map((x) => ({ id: x.id, ...x.data() })).sort((a, b) => V.millis(b.createdAt) - V.millis(a.createdAt));
    myName.value = me.exists() ? me.data().displayName || "" : "";
    const all = await Promise.all(claims.value.map((x) => getDocs(collection(db, "reviews", rid, "claims", x.id, "checks"))));
    checks.value = Object.fromEntries(claims.value.map((x, i) => [x.id, all[i].docs.map((y) => ({ id: y.id, ...y.data() }))]));
    hash.value = await V.contentHash(document.value.body || "");
    // Verdicts typed for claims that are gone or changed since must not be submitted.
    const active = new Set(claims.value.filter((x) => x.state !== "removed").map((x) => x.id));
    for (const id of Object.keys(form.verdicts)) if (!active.has(id)) delete form.verdicts[id];
  } catch (e) {
    console.error(e);
    problem.value = "This review couldn't be loaded.";
  } finally {
    loading.value = false;
  }
}

// ---- Status ----

async function saveReviewDoc(nextStatus) {
  await setDoc(doc(db, "reviews", rid), {
    title: document.value.title,
    kind: "document",
    ref: `documents/${docId}`,
    status: nextStatus,
    updatedAt: serverTimestamp(),
    updatedBy: session.user.uid,
  });
  review.value = { ...(review.value || {}), status: nextStatus };
}

// Makes sure reviews/<id> exists before the first claim or review, without ever overwriting a status
// someone else set in the meantime.
async function ensureReviewDoc() {
  const ref = doc(db, "reviews", rid);
  await runTransaction(db, async (t) => {
    const snap = await t.get(ref);
    if (snap.exists()) return;
    t.set(ref, { title: document.value.title, kind: "document", ref: `documents/${docId}`, status: "draft", updatedAt: serverTimestamp(), updatedBy: session.user.uid });
  });
}

async function setStatus(next) {
  status.value = "Saving…";
  try {
    await saveReviewDoc(next);
    status.value = `Status is now ${V.STATUS_LABELS[next]}.`;
  } catch (e) {
    console.error(e);
    status.value = "The status couldn't be changed. Only reviewers and admins can move a page past Draft.";
  }
}

const statusReason = {
  draft: "",
  "ai-checked": "needs at least one complete agent run",
  "human-reviewed": "needs a human review of the current text with at least one verdict",
  published: "needs every claim supported as it stands now, and a human review of the current text",
};

// ---- Claims ----

// Exactly what a reader sees of some Markdown: rendered with the same marked version as the public
// /d/ page, then its text. So "is this sentence in the text" means the same thing here and there.
const plain = (md) =>
  (new DOMParser().parseFromString(marked.parse(String(md || "")), "text/html").body.textContent || "")
    .replace(/\s+/g, " ")
    .trim();

const plainBody = computed(() => plain(document.value?.body));

const quoteInText = (q) => V.quoteIn(plainBody.value, q);

// Splits into sentences, but not after "et al.", "e.g.", "p.", "Fig." and similar.
const NO_BREAK = /(?:\bet al|\be\.g|\bi\.e|\bcf|\bvs|\bFig|\bFigs|\bp|\bpp|\bvol|\bno|\bDr|\bProf|\bapprox|\bca)\.$/i;
function sentences(text) {
  const out = [];
  let start = 0;
  for (const m of text.matchAll(/[.!?]\s+(?=[A-Z0-9(“"])/g)) {
    const end = m.index + 1;
    if (NO_BREAK.test(text.slice(start, end))) continue;
    out.push(text.slice(start, end).trim());
    start = m.index + m[0].length;
  }
  out.push(text.slice(start).trim());
  return out.filter(Boolean);
}

// Sentences in the document that cite a link or a DOI: a quick start for the claim list.
const suggestions = computed(() => {
  const body = document.value?.body || "";
  const out = [];
  const seen = new Set(claims.value.map((c) => V.sourceLink(c.source)));
  for (const para of body.split(/\n{2,}/)) {
    const links = [...para.matchAll(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g)];
    const dois = [...para.matchAll(/\b10\.\d{4,9}\/[^\s)\]]+/g)].map((m) => m[0]);
    const targets = [...links.map((m) => ({ text: m[1], url: m[2] })), ...dois.map((d) => ({ text: d, url: `https://doi.org/${V.normalizeDoi(d)}` }))];
    for (const t of targets) {
      const doi = V.normalizeDoi(t.url);
      const link = doi ? `https://doi.org/${doi}` : t.url;
      if (seen.has(link)) continue;
      seen.add(link);
      const text = plain(para);
      const sentence = sentences(text).find((s) => s.includes(t.text)) || text;
      // Never cut a quote short: a shortened sentence isn't what the document says.
      if (sentence.length > 2000) continue;
      out.push({ quote: sentence, doi, url: doi ? "" : t.url, citation: t.text });
    }
  }
  return out;
});

const draft = reactive({ quote: "", doi: "", url: "", citation: "", note: "" });
const editing = ref(null);
const claimStatus = ref("");

function useSuggestion(s) {
  Object.assign(draft, { quote: s.quote, doi: s.doi, url: s.url, citation: s.citation, note: "" });
  editing.value = null;
  window.scrollTo({ top: window.document.getElementById("claim-form").offsetTop - 80, behavior: "smooth" });
}

function sourceFromDraft() {
  const source = {};
  const doi = V.normalizeDoi(draft.doi);
  if (doi) source.doi = doi;
  if (draft.url.trim()) source.url = draft.url.trim();
  if (draft.citation.trim()) source.citation = draft.citation.trim();
  return source;
}

async function saveClaim() {
  if (!draft.quote.trim()) { claimStatus.value = "Copy the exact sentence from the document into the claim."; return; }
  const source = sourceFromDraft();
  claimStatus.value = "Saving…";
  try {
    await ensureReviewDoc();
    const old = editing.value ? claims.value.find((c) => c.id === editing.value) : null;
    const sameClaim = old && old.quote === draft.quote.trim() && JSON.stringify(V.sortedSource(old.source)) === JSON.stringify(V.sortedSource(source));
    if (sameClaim) {
      // Only the note changed: the verdicts and checks still apply to this exact claim.
      await updateDoc(doc(db, "reviews", rid, "claims", old.id), { note: draft.note.trim() || deleteField(), updatedAt: serverTimestamp() });
    } else {
      // A new sentence or a new source is a new claim: earlier verdicts were about something else.
      // The old claim stays in the record as removed, so its history isn't lost.
      const order = old ? old.order : Math.max(0, ...claims.value.map((c) => c.order || 0)) + 1;
      const data = { quote: draft.quote.trim(), source, order, state: "active", createdAt: serverTimestamp(), createdBy: session.user.uid };
      if (draft.note.trim()) data.note = draft.note.trim();
      await addDoc(collection(db, "reviews", rid, "claims"), data);
      // Only reviewers and admins may take a claim off the list (rules); for anyone else the old
      // wording stays until a reviewer removes it, and it can't count as supported meanwhile.
      if (old && canSignOff()) await updateDoc(doc(db, "reviews", rid, "claims", old.id), { state: "removed", updatedAt: serverTimestamp() });
    }
    Object.assign(draft, { quote: "", doi: "", url: "", citation: "", note: "" });
    editing.value = null;
    claimStatus.value = sameClaim || !old ? ""
      : canSignOff() ? "Saved as a new claim; the old wording is kept as removed, and earlier verdicts don't carry over."
      : "Saved as a new claim; earlier verdicts don't carry over. A reviewer still needs to remove the old wording.";
    await load({ quiet: true });
  } catch (e) {
    console.error(e);
    claimStatus.value = "The claim couldn't be saved.";
  }
}

function editClaim(c) {
  editing.value = c.id;
  Object.assign(draft, { quote: c.quote, doi: c.source?.doi || "", url: c.source?.url || "", citation: c.source?.citation || "", note: c.note || "" });
  window.scrollTo({ top: window.document.getElementById("claim-form").offsetTop - 80, behavior: "smooth" });
}

async function setClaimState(c, state) {
  claimStatus.value = "Saving…";
  try {
    await updateDoc(doc(db, "reviews", rid, "claims", c.id), { state, updatedAt: serverTimestamp() });
    delete form.verdicts[c.id];
    claimStatus.value = "";
    await load({ quiet: true });
  } catch (e) {
    console.error(e);
    claimStatus.value = "The claim couldn't be changed.";
  }
}

// ---- Human review ----

const form = reactive({ scope: "", checklist: {}, verdicts: {}, notes: "", name: "" });
const reviewStatus = ref("");
const sending = ref(false);

function verdictFor(id) {
  form.verdicts[id] ||= { verdict: "", location: "", note: "" };
  return form.verdicts[id];
}

// Only verdicts for claims that are still on the list count.
const activeIds = computed(() => new Set(activeStates.value.map((s) => s.claim.id)));
const chosenVerdicts = computed(() => Object.entries(form.verdicts).filter(([id, v]) => v.verdict && activeIds.value.has(id)));
const reviewedCount = computed(() => chosenVerdicts.value.length);

const changingName = ref(false);

async function saveName() {
  const name = form.name.trim();
  if (!name) { reviewStatus.value = "Type the name to show on your reviews."; return; }
  try {
    await updateDoc(doc(db, "users", session.user.uid), { displayName: name });
    myName.value = name;
    changingName.value = false;
    reviewStatus.value = "";
  } catch (e) {
    console.error(e);
    reviewStatus.value = "Your name couldn't be saved.";
  }
}

async function submitReview() {
  if (!myName.value || changingName.value) { reviewStatus.value = "Save the name to show on your review first."; return; }
  if (!form.scope.trim()) { reviewStatus.value = "Say what you checked, e.g. \"claims 1–12 against their sources\"."; return; }
  if (!reviewedCount.value) { reviewStatus.value = "Give a verdict for at least one claim. A review without verdicts doesn't verify anything."; return; }
  const verdicts = {};
  for (const [id, v] of chosenVerdicts.value) {
    const claim = claims.value.find((c) => c.id === id);
    verdicts[id] = { verdict: v.verdict, claimKey: V.claimKey(claim) };
    if (v.location.trim()) verdicts[id].location = v.location.trim();
    if (v.note.trim()) verdicts[id].note = v.note.trim();
  }
  sending.value = true;
  reviewStatus.value = "Saving…";
  try {
    await ensureReviewDoc();
    const data = {
      reviewerUid: session.user.uid,
      reviewerName: myName.value,
      createdAt: serverTimestamp(),
      contentHash: hash.value,
      scope: form.scope.trim(),
      checklist: Object.fromEntries(V.CHECKLIST.map((x) => [x.key, Boolean(form.checklist[x.key])])),
      verdicts,
    };
    if (form.notes.trim()) data.notes = form.notes.trim();
    await addDoc(collection(db, "reviews", rid, "humanReviews"), data);
    Object.assign(form, { scope: "", checklist: {}, verdicts: {}, notes: "" });
    reviewStatus.value = "Your review is saved. It can't be changed afterwards; a new review replaces it on the label.";
    await load({ quiet: true });
  } catch (e) {
    console.error(e);
    reviewStatus.value = "Your review couldn't be saved.";
  } finally {
    sending.value = false;
  }
}

const outcomeClass = (o) => (o === "agents-agree" || o === "human-supported" ? "open" : o === "human-not-supported" ? "bad" : o === "stale" || o === "needs-human" || o === "human-partly" ? "warn" : "closed");
const accessLabel = (a) => ({ "full-text": "full text", "abstract-only": "abstract only", none: "no access" }[a] || a);
</script>

<template>
  <RouterLink to="/documents" class="back">‹ Documents</RouterLink>
  <p v-if="loading" class="muted loading">Loading…</p>
  <template v-else-if="problem">
    <h1>Can't review this</h1>
    <p class="muted">{{ problem }}</p>
  </template>

  <template v-else>
    <div class="page-head">
      <div>
        <h1>Review: {{ document.title }}</h1>
        <p class="muted"><a :href="docLink(docId)" target="_blank" rel="noopener">Open the public page</a> · labels there update from this review.</p>
      </div>
    </div>

    <!-- Status -->
    <div class="card review-status">
      <div class="review-status-row">
        <div>
          <p class="field-label">Status</p>
          <p class="review-status-now">{{ review ? V.STATUS_LABELS[review.status] || review.status : "Not yet verified" }}</p>
          <p v-if="review && shownStatus !== review.status" class="warn-text small">
            The public page shows {{ V.STATUS_LABELS[shownStatus] }} instead: {{ statusReason[review.status] }}, which isn't true any more.
          </p>
        </div>
        <div class="review-counts">
          <span><strong>{{ summary.claims }}</strong> claims</span>
          <span><strong>{{ summary.supported }}</strong> supported</span>
          <span><strong>{{ summary.problems }}</strong> not or partly supported</span>
          <span><strong>{{ summary.open }}</strong> open</span>
        </div>
      </div>
      <div class="review-steps">
        <button v-for="s in V.STATUSES" :key="s" type="button"
          :class="{ primary: review?.status === s }"
          :disabled="review?.status === s || !allowed[s] || (s !== 'draft' && !canSignOff())"
          :title="!allowed[s] ? `${V.STATUS_LABELS[s]} ${statusReason[s]}` : ''"
          @click="setStatus(s)">{{ V.STATUS_LABELS[s] }}</button>
      </div>
      <p class="muted small">
        Moving past Draft is for reviewers and admins. Published needs every claim supported, and a human review (with verdicts) of the current text.
        A verdict is about one exact sentence and its source; it stops counting when either changes.
        <template v-if="summary.humanLabel?.stale"><br><strong class="warn-text">The text or the list of claims has changed since the last human review, so Human-reviewed and Published need a new review.</strong></template>
      </p>
      <p class="status">{{ status }}</p>
    </div>

    <!-- Claims -->
    <h2>Claims and sources</h2>
    <p class="muted">Each claim is an exact sentence from the document plus the source that should back it. The agents and reviewers check these, nothing else.</p>

    <div class="card">
      <div class="table-wrap">
        <table v-if="states.length">
          <thead><tr><th>#</th><th>Claim</th><th>Source</th><th>Agents</th><th>Outcome</th><th></th></tr></thead>
          <tbody>
            <tr v-for="(s, i) in states" :key="s.claim.id" :class="{ removed: s.outcome === 'removed' }">
              <td class="num">{{ i + 1 }}</td>
              <td class="claim-quote">
                {{ s.claim.quote }}
                <div v-if="!quoteInText(s.claim.quote)" class="warn-text small">Not found word-for-word in the current text.</div>
                <div v-if="s.claim.note" class="muted small">{{ s.claim.note }}</div>
              </td>
              <td class="claim-source">
                <a v-if="V.sourceLink(s.claim.source)" :href="V.sourceLink(s.claim.source)" target="_blank" rel="noopener">{{ s.claim.source?.citation || V.sourceLink(s.claim.source) }}</a>
                <span v-else class="warn-text">No source</span>
              </td>
              <td class="claim-agents">
                <template v-if="s.run">
                  <div v-for="c in s.run.checks" :key="c.id" class="small">
                    Run {{ c.agent }}: {{ V.VERDICT_LABELS[c.verdict] || c.verdict }} · {{ accessLabel(c.access) }}<template v-if="c.location"> · {{ c.location }}</template>
                  </div>
                  <div v-if="s.agent.outcome === 'needs-human'" class="warn-text small">{{ s.agent.reasons.join("; ") }}</div>
                </template>
                <span v-else class="muted small">Not run yet</span>
              </td>
              <td><span class="pill" :class="outcomeClass(s.outcome)">{{ V.OUTCOME_LABELS[s.outcome] }}</span></td>
              <td class="nowrap">
                <button type="button" class="ghost small" @click="editClaim(s.claim)">Edit</button>
                <template v-if="canSignOff()">
                  <button v-if="s.outcome !== 'removed'" type="button" class="ghost small" @click="setClaimState(s.claim, 'removed')">Remove</button>
                  <button v-else type="button" class="ghost small" @click="setClaimState(s.claim, 'active')">Restore</button>
                </template>
              </td>
            </tr>
          </tbody>
        </table>
        <p v-else class="empty">No claims yet. Add the sentences that cite a source, or pick from the suggestions below.</p>
      </div>
    </div>

    <div class="actions">
      <button type="button" disabled title="Step 2: three independent Claude runs per claim">Run the 3 Claude checks (coming next)</button>
    </div>

    <details v-if="suggestions.length" class="card suggestions">
      <summary>{{ suggestions.length }} cited sources found in the text that aren't claims yet</summary>
      <ul>
        <li v-for="(s, i) in suggestions" :key="i">
          <span class="small">{{ s.quote }}</span>
          <span class="muted small"> · {{ s.citation }}</span>
          <button type="button" class="ghost small" @click="useSuggestion(s)">Use as claim</button>
        </li>
      </ul>
    </details>

    <form id="claim-form" class="card edit-q claim-form" @submit.prevent="saveClaim">
      <p class="edit-title">{{ editing ? "Edit claim" : "Add a claim" }}</p>
      <label class="field-label" for="claim-quote">The exact sentence from the document</label>
      <textarea id="claim-quote" v-model="draft.quote" rows="3" maxlength="2000"></textarea>
      <p v-if="draft.quote && !quoteInText(draft.quote)" class="warn-text small">This isn't word-for-word in the document, so the public page can't point to it.</p>
      <div class="claim-source-fields">
        <div>
          <label class="field-label" for="claim-doi">DOI</label>
          <input id="claim-doi" v-model="draft.doi" type="text" maxlength="300" placeholder="10.1093/sleep/32.9.1191">
        </div>
        <div>
          <label class="field-label" for="claim-url">Or a link (when there's no DOI)</label>
          <input id="claim-url" v-model="draft.url" type="text" maxlength="2000" placeholder="https://…">
        </div>
      </div>
      <label class="field-label" for="claim-citation">Citation as shown to readers</label>
      <input id="claim-citation" v-model="draft.citation" type="text" maxlength="1000" placeholder="Voss et al. 2009, Sleep 32(9)">
      <label class="field-label" for="claim-note">Note (optional)</label>
      <input id="claim-note" v-model="draft.note" type="text" maxlength="2000" placeholder="e.g. statistic in table 2">
      <div class="actions">
        <button type="submit" class="primary">{{ editing ? "Save claim" : "Add claim" }}</button>
        <button v-if="editing" type="button" class="ghost" @click="editing = null; Object.assign(draft, { quote: '', doi: '', url: '', citation: '', note: '' })">Cancel</button>
        <span class="status">{{ claimStatus }}</span>
      </div>
    </form>

    <!-- Human review -->
    <h2>Your review</h2>
    <template v-if="!canSignOff()">
      <p class="muted">Signing off is for reviewers and admins. Ask an admin for the reviewer role.</p>
    </template>
    <form v-else class="card edit-q" @submit.prevent="submitReview">
      <!-- Reviewer names are set by an admin (rules: users/{uid}), so nobody can sign as someone else. -->
      <template v-if="!myName || changingName">
        <template v-if="isAdmin()">
          <label class="field-label" for="rev-name">Your name, as it will show on the label</label>
          <div class="toolbar">
            <input id="rev-name" v-model="form.name" type="text" maxlength="120" placeholder="e.g. Davor Radić" @keydown.enter.prevent="saveName">
            <button type="button" @click="saveName">Save name</button>
            <button v-if="myName" type="button" class="ghost" @click="changingName = false">Cancel</button>
          </div>
        </template>
        <p v-else class="warn-text small">You don't have a reviewer name yet. An admin sets it under Users &amp; roles, so nobody can sign a review under someone else's name.</p>
      </template>
      <p v-else class="muted small">
        Signing as <strong>{{ myName }}</strong><button v-if="isAdmin()" type="button" class="ghost small" @click="changingName = true; form.name = myName">change</button>.
        Your review records the exact version of the text, and of each claim, that you checked.
      </p>

      <label class="field-label" for="rev-scope">What you checked (shown on the label)</label>
      <input id="rev-scope" v-model="form.scope" type="text" maxlength="1000" placeholder="e.g. claims 1–12 against their sources">

      <p class="field-label">How you checked (from “How to verify a source”)</p>
      <label v-for="x in V.CHECKLIST" :key="x.key" class="opt" :for="`chk-${x.key}`">
        <input :id="`chk-${x.key}`" v-model="form.checklist[x.key]" type="checkbox">
        <span>{{ x.label }}</span>
      </label>

      <p class="field-label">Your verdict per claim (leave empty for claims you didn't check)</p>
      <div v-for="(s, i) in activeStates" :key="s.claim.id" class="verdict-row">
        <div class="small"><strong>{{ i + 1 }}.</strong> {{ s.claim.quote }}</div>
        <div class="verdict-fields">
          <select v-model="verdictFor(s.claim.id).verdict" :aria-label="`Verdict for claim ${i + 1}`">
            <option value="">Not checked</option>
            <option v-for="v in V.HUMAN_VERDICTS" :key="v" :value="v">{{ V.VERDICT_LABELS[v] }}</option>
          </select>
          <input v-model="verdictFor(s.claim.id).location" type="text" maxlength="200" placeholder="Page or section" :aria-label="`Where in the source, claim ${i + 1}`">
          <input v-model="verdictFor(s.claim.id).note" type="text" maxlength="1000" placeholder="Note" :aria-label="`Note, claim ${i + 1}`">
        </div>
      </div>

      <label class="field-label" for="rev-notes">Anything else (optional)</label>
      <textarea id="rev-notes" v-model="form.notes" rows="3" maxlength="5000"></textarea>

      <div class="actions">
        <button type="submit" class="primary" :disabled="sending || !myName">Sign off {{ reviewedCount }} {{ reviewedCount === 1 ? "claim" : "claims" }}</button>
        <span class="status">{{ reviewStatus }}</span>
      </div>
    </form>

    <template v-if="humanReviews.length">
      <h2>Earlier reviews</h2>
      <div class="card answers">
        <div v-for="r in humanReviews" :key="r.id" class="answer">
          <div class="q"><strong>{{ r.reviewerName }}</strong> · {{ when(r.createdAt) }}<span v-if="r.contentHash !== hash" class="warn-text"> · reviewed an earlier version of the text</span></div>
          <div class="a">Checked: {{ r.scope }} · {{ Object.keys(r.verdicts || {}).length }} claim verdicts<template v-if="r.notes"><br>{{ r.notes }}</template></div>
        </div>
      </div>
    </template>
  </template>
</template>

<style scoped>
.review-status { padding: 18px 20px; display: grid; gap: 12px; }
.review-status-row { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 12px; align-items: flex-end; }
.review-status-now { margin: 2px 0 0; font-size: 1.3rem; font-weight: 650; }
.review-counts { display: flex; gap: 18px; color: var(--muted); }
.review-counts strong { color: var(--text); font-variant-numeric: tabular-nums; }
.review-steps { display: flex; flex-wrap: wrap; gap: 8px; }
.claim-quote { min-width: 260px; }
.claim-source { min-width: 160px; overflow-wrap: anywhere; }
.claim-agents { min-width: 180px; }
tr.removed td { opacity: 0.5; text-decoration: line-through; }
tr.removed td:last-child { text-decoration: none; opacity: 1; }
.pill.bad { background: rgba(255, 138, 138, 0.14); color: var(--danger); }
.pill.warn { background: rgba(240, 196, 104, 0.14); color: var(--moonlight); }
.warn-text { color: var(--moonlight); }
.suggestions { padding: 14px 18px; margin-top: 14px; }
.suggestions summary { cursor: pointer; color: var(--lavender); font-weight: 600; }
.suggestions ul { margin: 10px 0 0; padding-left: 18px; display: grid; gap: 8px; }
.claim-form { margin-top: 14px; }
.claim-source-fields { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
.claim-source-fields > div { display: grid; gap: 6px; }
@media (max-width: 640px) { .claim-source-fields { grid-template-columns: 1fr; } }
.verdict-row { display: grid; gap: 6px; padding: 10px 0; border-bottom: 1px solid var(--line); }
.verdict-fields { display: grid; grid-template-columns: 170px 1fr 1.5fr; gap: 8px; }
@media (max-width: 640px) { .verdict-fields { grid-template-columns: 1fr; } }
.verdict-fields input, .verdict-fields select { width: 100%; }
</style>
