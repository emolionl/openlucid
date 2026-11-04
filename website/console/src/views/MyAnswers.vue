<script setup>
import { ref, onMounted } from "vue";
import { collection, getDocs, query, where } from "firebase/firestore";
import { db } from "../firebase";
import { session } from "../session";
import { when, answeredCount, editUrl, SITE } from "../lib/format";

// The responses sent with your email address. The rules only return those.
const rows = ref([]);
const loading = ref(true);
const error = ref("");

onMounted(async () => {
  try {
    const snap = await getDocs(query(collection(db, "responses"), where("email", "==", session.user.email)));
    rows.value = snap.docs
      .map((d) => ({ id: d.id, ...d.data() }))
      .sort((a, b) => (b.sentAt?.seconds || 0) - (a.sentAt?.seconds || 0));
  } catch (e) {
    console.error(e);
    error.value = "Your answers couldn't be loaded. Reload the page to try again.";
  } finally {
    loading.value = false;
  }
});
</script>

<template>
  <div class="page-head">
    <div>
      <h1>My answers</h1>
      <p class="muted">Answers sent with {{ session.user.email }}. You can read and change them.</p>
    </div>
  </div>
  <p v-if="error" class="status err">{{ error }}</p>

  <div class="card">
    <div class="table-wrap">
      <p v-if="loading" class="empty">Loading…</p>
      <table v-else-if="rows.length">
        <thead><tr><th>Questionnaire</th><th>Sent</th><th>Answered</th><th></th></tr></thead>
        <tbody>
          <tr v-for="r in rows" :key="r.id">
            <td><RouterLink :to="`/responses/${r.id}`">{{ r.title }}</RouterLink></td>
            <td class="nowrap">{{ when(r.sentAt) }}<span v-if="r.updatedAt" class="muted"> · changed {{ when(r.updatedAt) }}</span></td>
            <td class="num">{{ answeredCount(r) }}</td>
            <td class="nowrap"><RouterLink :to="editUrl(r)">Change</RouterLink></td>
          </tr>
        </tbody>
      </table>
      <p v-else class="empty">
        No answers with this email yet. When you answer a <a :href="`${SITE}/questions/`">questionnaire</a>, fill in this email address to find your answers here.
      </p>
    </div>
  </div>
</template>
