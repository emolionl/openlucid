<script setup>
import { ref, onMounted } from "vue";
import { collection, getDocs, doc, updateDoc } from "firebase/firestore";
import { db } from "../firebase";
import { session, ROLES } from "../session";
import { when } from "../lib/format";

// Everyone who has signed in at least once. Only admins see this page and can change roles.
const DESCRIPTIONS = {
  admin: "Everything, including roles",
  researcher: "Reads all responses",
  client: "Own answers (more later)",
  respondent: "Own answers",
};

const rows = ref([]);
const loading = ref(true);
const status = ref({});

onMounted(async () => {
  try {
    const snap = await getDocs(collection(db, "users"));
    rows.value = snap.docs
      .map((d) => ({ id: d.id, ...d.data() }))
      .sort((a, b) => (b.createdAt?.seconds || 0) - (a.createdAt?.seconds || 0));
  } finally {
    loading.value = false;
  }
});

async function setRole(u, role) {
  const before = u.role;
  u.role = role;
  status.value = { ...status.value, [u.id]: "Saving…" };
  try {
    await updateDoc(doc(db, "users", u.id), { role });
    status.value = { ...status.value, [u.id]: "Saved" };
  } catch (e) {
    console.error(e);
    u.role = before;
    status.value = { ...status.value, [u.id]: "Not saved" };
  }
}
</script>

<template>
  <div class="page-head">
    <div>
      <h1>Users &amp; roles</h1>
      <p class="muted">Everyone who has signed in. People appear here after their first sign-in, as respondents.</p>
    </div>
  </div>

  <div class="card">
    <div class="table-wrap">
      <p v-if="loading" class="empty">Loading…</p>
      <table v-else>
        <thead><tr><th>Email</th><th>Role</th><th>First sign-in</th><th></th></tr></thead>
        <tbody>
          <tr v-for="u in rows" :key="u.id">
            <td>{{ u.email }}<span v-if="u.id === session.user.uid" class="muted"> (you)</span></td>
            <td>
              <select :value="u.role" :disabled="u.id === session.user.uid" :aria-label="`Role of ${u.email}`" @change="setRole(u, $event.target.value)">
                <option v-for="r in ROLES" :key="r" :value="r">{{ r }} · {{ DESCRIPTIONS[r] }}</option>
              </select>
            </td>
            <td class="nowrap">{{ when(u.createdAt) }}</td>
            <td class="muted">{{ status[u.id] }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
  <p class="muted" style="margin-top: 14px">You can't change your own role here, so the console always keeps at least one admin.</p>
</template>
