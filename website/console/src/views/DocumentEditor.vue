<script setup>
import { ref, reactive, computed, onMounted } from "vue";
import { useRoute, useRouter } from "vue-router";
import { doc, getDoc, addDoc, updateDoc, deleteDoc, collection, query, orderBy, getDocs, serverTimestamp } from "firebase/firestore";
import { db } from "../firebase";
import { isAdmin } from "../session";
import { docLink, when } from "../lib/format";

const route = useRoute();
const router = useRouter();
const isNew = computed(() => route.name === "document-new");

const form = reactive({ title: "", audience: "", status: "draft", body: "" });
const loading = ref(!isNew.value);
const problem = ref("");
const saving = ref(false);
const status = ref("");
const savedId = ref(isNew.value ? "" : route.params.id);

const revisions = ref([]);
const revForm = reactive({ summary: "", why: "", section: "", added: "", removed: "", anchor: "" });
const revSaving = ref(false);
const revStatus = ref("");

async function loadRevisions() {
  if (!savedId.value) return;
  const snap = await getDocs(query(collection(db, "documents", savedId.value, "revisions"), orderBy("createdAt", "desc")));
  revisions.value = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
}

onMounted(async () => {
  if (isNew.value) return;
  try {
    const snap = await getDoc(doc(db, "documents", route.params.id));
    if (!snap.exists()) { problem.value = "This document doesn't exist, or it was deleted."; return; }
    Object.assign(form, { title: "", audience: "", status: "draft", ...snap.data() });
    await loadRevisions();
  } catch (e) {
    console.error(e);
    problem.value = "This document couldn't be loaded.";
  } finally {
    loading.value = false;
  }
});

async function addRevision() {
  if (!revForm.summary.trim() || !revForm.why.trim()) { revStatus.value = "A summary and a reason are both needed."; return; }
  revSaving.value = true;
  revStatus.value = "Saving…";
  const data = { summary: revForm.summary.trim(), why: revForm.why.trim(), createdAt: serverTimestamp() };
  if (revForm.section.trim()) data.section = revForm.section.trim();
  if (revForm.added.trim()) data.added = revForm.added.trim();
  if (revForm.removed.trim()) data.removed = revForm.removed.trim();
  if (revForm.anchor.trim()) data.anchor = revForm.anchor.trim();
  try {
    await addDoc(collection(db, "documents", savedId.value, "revisions"), data);
    revForm.summary = ""; revForm.why = ""; revForm.section = ""; revForm.added = ""; revForm.removed = ""; revForm.anchor = "";
    revStatus.value = "";
    await loadRevisions();
  } catch (e) {
    console.error(e);
    revStatus.value = "Saving didn't work. Try again.";
  } finally {
    revSaving.value = false;
  }
}

async function removeRevision(rev) {
  if (!confirm(`Delete the "${rev.summary}" history entry? This can't be undone.`)) return;
  await deleteDoc(doc(db, "documents", savedId.value, "revisions", rev.id));
  revisions.value = revisions.value.filter((r) => r.id !== rev.id);
}

async function save() {
  if (!form.title.trim() || !form.body.trim()) { status.value = "A title and some content are both needed."; return; }
  saving.value = true;
  status.value = "Saving…";
  const data = { title: form.title.trim(), body: form.body, status: form.status, updatedAt: serverTimestamp() };
  if (form.audience.trim()) data.audience = form.audience.trim();
  try {
    if (isNew.value) {
      const ref = await addDoc(collection(db, "documents"), { ...data, createdAt: serverTimestamp() });
      savedId.value = ref.id;
      router.replace(`/documents/${ref.id}/edit`);
    } else {
      await updateDoc(doc(db, "documents", route.params.id), data);
    }
    status.value = "Saved";
  } catch (e) {
    console.error(e);
    status.value = "Saving didn't work. Try again.";
  } finally {
    saving.value = false;
  }
}

const copied = ref(false);
async function copy() {
  try {
    await navigator.clipboard.writeText(docLink(savedId.value));
    copied.value = true;
    setTimeout(() => (copied.value = false), 2000);
  } catch (e) {
    console.error(e);
  }
}
</script>

<template>
  <RouterLink to="/documents" class="back">‹ Back to documents</RouterLink>

  <template v-if="problem">
    <h1>Can't open this document</h1>
    <p class="muted">{{ problem }}</p>
  </template>

  <template v-else-if="loading">
    <p class="muted loading">Loading…</p>
  </template>

  <template v-else>
    <div class="page-head">
      <div>
        <h1>{{ isNew ? "New document" : "Edit document" }}</h1>
        <p class="muted">Written in Markdown. Anyone with the link below can read it — nothing is listed publicly.</p>
      </div>
    </div>

    <form class="edit-form" @submit.prevent="save">
      <div class="card edit-q">
        <label class="field-label" for="doc-title">Title</label>
        <input id="doc-title" v-model="form.title" type="text" maxlength="300" required>

        <label class="field-label" for="doc-audience">Audience (optional)</label>
        <input id="doc-audience" v-model="form.audience" type="text" maxlength="200" placeholder="e.g. a potential co-promotor">

        <label class="field-label" for="doc-status">Status</label>
        <select id="doc-status" v-model="form.status">
          <option value="draft">Draft (still working on it)</option>
          <option value="shared">Shared (link has gone out)</option>
        </select>

        <label class="field-label" for="doc-body">Content (Markdown)</label>
        <textarea id="doc-body" v-model="form.body" rows="24" class="mono"></textarea>
      </div>

      <div class="actions sticky-actions">
        <button type="submit" class="primary" :disabled="saving">Save</button>
        <span class="status">{{ status }}</span>
        <template v-if="savedId">
          <button type="button" class="ghost" @click="copy">{{ copied ? "Copied!" : "Copy link" }}</button>
          <a :href="docLink(savedId)" target="_blank" rel="noopener" class="ghost-link">Open</a>
        </template>
      </div>
    </form>

    <template v-if="savedId">
      <div class="page-head" style="margin-top: 40px">
        <div>
          <h2>History</h2>
          <p class="muted">What changed and why — shown on the public page, like a commit log.</p>
        </div>
      </div>

      <div v-if="revisions.length" class="rev-list">
        <div v-for="r in revisions" :key="r.id" class="card rev-entry">
          <div class="rev-head">
            <span class="pill" v-if="r.section">{{ r.section }}</span>
            <strong>{{ r.summary }}</strong>
            <span class="muted nowrap" style="margin-left: auto">{{ when(r.createdAt) }}</span>
            <button v-if="isAdmin()" type="button" class="ghost small" @click="removeRevision(r)">Delete</button>
          </div>
          <p class="muted">{{ r.why }}</p>
          <p v-if="r.anchor" class="rev-anchor">“{{ r.anchor }}”</p>
          <p v-if="r.added" class="rev-added">+ {{ r.added }}</p>
          <p v-if="r.removed" class="rev-removed">− {{ r.removed }}</p>
        </div>
      </div>
      <p v-else class="muted">No history entries yet.</p>
      <p class="muted small">You can also select text directly on the public page (signed in there as staff) to add an entry anchored to that exact phrase.</p>

      <form class="edit-form" @submit.prevent="addRevision" style="margin-top: 20px">
        <div class="card edit-q">
          <label class="field-label" for="rev-summary">Summary (the commit subject)</label>
          <input id="rev-summary" v-model="revForm.summary" type="text" maxlength="200" placeholder="e.g. Defined &quot;research-usable&quot; precisely">

          <label class="field-label" for="rev-section">Section (optional)</label>
          <input id="rev-section" v-model="revForm.section" type="text" maxlength="50" placeholder="e.g. 2a / 2b">

          <label class="field-label" for="rev-anchor">Anchor text (optional) — the exact phrase in the document, for a marker next to it</label>
          <input id="rev-anchor" v-model="revForm.anchor" type="text" maxlength="1000" placeholder="Paste the exact sentence or phrase this is about">

          <label class="field-label" for="rev-why">Why</label>
          <textarea id="rev-why" v-model="revForm.why" rows="3" maxlength="2000"></textarea>

          <label class="field-label" for="rev-added">What was added (optional)</label>
          <textarea id="rev-added" v-model="revForm.added" rows="3" maxlength="5000"></textarea>

          <label class="field-label" for="rev-removed">What was removed (optional)</label>
          <textarea id="rev-removed" v-model="revForm.removed" rows="3" maxlength="5000"></textarea>
        </div>
        <div class="actions">
          <button type="submit" class="primary" :disabled="revSaving">Add to history</button>
          <span class="status">{{ revStatus }}</span>
        </div>
      </form>
    </template>
  </template>
</template>
