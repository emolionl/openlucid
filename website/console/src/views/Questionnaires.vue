<script setup>
import { ref, onMounted } from "vue";
import { collection, getDocs } from "firebase/firestore";
import { db } from "../firebase";
import { loadQuestionnaires, SITE } from "../lib/format";

// The list comes from the website itself; to add a questionnaire, add a file to website/content/questions/.
const rows = ref([]);
const loading = ref(true);

onMounted(async () => {
  const [qs, snap] = await Promise.all([loadQuestionnaires(), getDocs(collection(db, "responses")).catch(() => null)]);
  const counts = {};
  snap?.docs.forEach((d) => { const s = d.data().questionnaire; counts[s] = (counts[s] || 0) + 1; });
  rows.value = qs.map((q) => ({ ...q, responses: counts[q.slug] || 0 }));
  loading.value = false;
});
</script>

<template>
  <div class="page-head">
    <div>
      <h1>Questionnaires</h1>
      <p class="muted">Published on openlucid.nl/questions/. Add one by copying a file in <span class="mono">website/content/questions/</span>.</p>
    </div>
  </div>

  <div class="card">
    <div class="table-wrap">
      <p v-if="loading" class="empty">Loading…</p>
      <table v-else-if="rows.length">
        <thead><tr><th>Questionnaire</th><th>Status</th><th>Published</th><th>Questions</th><th>Responses</th><th></th></tr></thead>
        <tbody>
          <tr v-for="q in rows" :key="q.slug">
            <td>{{ q.title }}<div class="muted" v-if="q.audience">For {{ q.audience }}</div></td>
            <td><span class="pill" :class="q.status === 'closed' ? 'closed' : 'open'">{{ q.status === "closed" ? "Closed" : "Open" }}</span></td>
            <td class="nowrap">{{ q.date }}</td>
            <td class="num">{{ q.questions }}</td>
            <td class="num"><RouterLink :to="{ path: '/responses', query: { q: q.slug } }">{{ q.responses }}</RouterLink></td>
            <td class="nowrap"><a :href="SITE + q.url">View page</a></td>
          </tr>
        </tbody>
      </table>
      <p v-else class="empty">No questionnaires published yet.</p>
    </div>
  </div>
</template>
