<script setup>
import { ref, onMounted } from "vue";
import { collection, getDocs, doc, updateDoc } from "firebase/firestore";
import { db } from "../firebase";
import { session, ROLES } from "../session";
import { when } from "../lib/format";

// Everyone who has signed in at least once. Only admins see this page and can change roles.
const DESCRIPTIONS = {
  admin: "Everything, including roles",
  researcher: "Reads all responses, writes documents",
  reviewer: "Reviews sources and signs off pages",
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

// The name shown on someone's reviews ("Reviewed by …"). Only admins set it, so it's an identity the
// project vouches for, not something a reviewer can pick for themselves.
async function setName(u, value) {
  const name = value.trim();
  if (!name || name === u.displayName) return;
  status.value = { ...status.value, [u.id]: "Saving…" };
  try {
    await updateDoc(doc(db, "users", u.id), { displayName: name });
    u.displayName = name;
    status.value = { ...status.value, [u.id]: "Saved" };
  } catch (e) {
    console.error(e);
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
        <thead><tr><th>Email</th><th>Name on reviews</th><th>Role</th><th>First sign-in</th><th></th></tr></thead>
        <tbody>
          <tr v-for="u in rows" :key="u.id">
            <td>{{ u.email }}<span v-if="u.id === session.user.uid" class="muted"> (you)</span></td>
            <td>
              <input type="text" maxlength="120" :value="u.displayName || ''" placeholder="Set before reviewing"
                :aria-label="`Name on reviews for ${u.email}`"
                @change="setName(u, $event.target.value)" @keydown.enter.prevent="setName(u, $event.target.value)">
            </td>
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
  <p class="muted" style="margin-top: 14px">
    You can't change your own role here, so the console always keeps at least one admin.
    The name on reviews is what the public labels show ("Reviewed by …"); only admins can set it, so check who someone is before giving them a name and the reviewer role.
  </p>
</template>
