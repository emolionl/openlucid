<script setup>
import { ref, reactive, computed, onMounted } from "vue";
import { useRoute, useRouter } from "vue-router";
import { doc, getDoc, addDoc, updateDoc, collection, serverTimestamp } from "firebase/firestore";
import { db } from "../firebase";
import { docLink } from "../lib/format";

const route = useRoute();
const router = useRouter();
const isNew = computed(() => route.name === "document-new");

const form = reactive({ title: "", audience: "", status: "draft", body: "" });
const loading = ref(!isNew.value);
const problem = ref("");
const saving = ref(false);
const status = ref("");
const savedId = ref(isNew.value ? "" : route.params.id);

onMounted(async () => {
  if (isNew.value) return;
  try {
    const snap = await getDoc(doc(db, "documents", route.params.id));
    if (!snap.exists()) { problem.value = "This document doesn't exist, or it was deleted."; return; }
    Object.assign(form, { title: "", audience: "", status: "draft", ...snap.data() });
  } catch (e) {
    console.error(e);
    problem.value = "This document couldn't be loaded.";
  } finally {
    loading.value = false;
  }
});

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
  </template>
</template>
