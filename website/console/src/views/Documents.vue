<script setup>
import { ref, onMounted } from "vue";
import { collection, getDocs, deleteDoc, doc, orderBy, query } from "firebase/firestore";
import { db } from "../firebase";
import { isAdmin } from "../session";
import { when, docLink } from "../lib/format";

// Working documents (e.g. a PhD proposal draft): readable by anyone with the link (rules: firestore.rules),
// but only staff can see this list, and only staff can create/edit/delete. To add one: "New document".
const rows = ref([]);
const loading = ref(true);
const copied = ref("");

onMounted(load);

async function load() {
  loading.value = true;
  try {
    const snap = await getDocs(query(collection(db, "documents"), orderBy("updatedAt", "desc")));
    rows.value = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  } finally {
    loading.value = false;
  }
}

async function copy(id) {
  try {
    await navigator.clipboard.writeText(docLink(id));
    copied.value = id;
    setTimeout(() => { if (copied.value === id) copied.value = ""; }, 2000);
  } catch (e) {
    console.error(e);
  }
}

async function remove(row) {
  if (!confirm(`Delete "${row.title}"? This can't be undone.`)) return;
  await deleteDoc(doc(db, "documents", row.id));
  rows.value = rows.value.filter((r) => r.id !== row.id);
}
</script>

<template>
  <div class="page-head">
    <div>
      <h1>Documents</h1>
      <p class="muted">Working documents, each readable by anyone who has its link — nothing here is public otherwise.</p>
    </div>
    <RouterLink to="/documents/new" class="button">New document</RouterLink>
  </div>

  <div class="card">
    <div class="table-wrap">
      <p v-if="loading" class="empty">Loading…</p>
      <table v-else-if="rows.length">
        <thead><tr><th>Title</th><th>Status</th><th>Updated</th><th></th></tr></thead>
        <tbody>
          <tr v-for="r in rows" :key="r.id">
            <td>{{ r.title }}<div class="muted" v-if="r.audience">For {{ r.audience }}</div></td>
            <td><span class="pill" :class="r.status === 'shared' ? 'open' : 'closed'">{{ r.status === "shared" ? "Shared" : "Draft" }}</span></td>
            <td class="nowrap">{{ when(r.updatedAt) }}</td>
            <td class="nowrap">
              <button type="button" class="ghost small" @click="copy(r.id)">{{ copied === r.id ? "Copied!" : "Copy link" }}</button>
              <RouterLink :to="`/documents/${r.id}/edit`" class="ghost small">Edit</RouterLink>
              <button v-if="isAdmin()" type="button" class="ghost small" @click="remove(r)">Delete</button>
            </td>
          </tr>
        </tbody>
      </table>
      <p v-else class="empty">No documents yet.</p>
    </div>
  </div>
</template>
