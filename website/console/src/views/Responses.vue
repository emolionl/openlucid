<script setup>
import { ref, computed, onMounted } from "vue";
import { useRoute, useRouter } from "vue-router";
import { collection, getDocs, query, orderBy, limit } from "firebase/firestore";
import { db } from "../firebase";
import { when, answeredCount, loadQuestionnaires } from "../lib/format";

const route = useRoute();
const router = useRouter();
const rows = ref([]);
const questionnaires = ref([]);
const loading = ref(true);
const error = ref("");

// ?q=<slug> filters on one questionnaire, so a filtered list can be bookmarked.
const filter = computed({
  get: () => (typeof route.query.q === "string" ? route.query.q : ""),
  set: (v) => router.replace({ query: v ? { q: v } : {} }),
});
const shown = computed(() => (filter.value ? rows.value.filter((r) => r.questionnaire === filter.value) : rows.value));

onMounted(async () => {
  try {
    const [snap, qs] = await Promise.all([
      getDocs(query(collection(db, "responses"), orderBy("sentAt", "desc"), limit(500))),
      loadQuestionnaires(),
    ]);
    rows.value = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    questionnaires.value = qs;
  } catch (e) {
    console.error(e);
    error.value = "The responses couldn't be loaded. Reload the page to try again.";
  } finally {
    loading.value = false;
  }
});
</script>

<template>
  <div class="page-head">
    <div>
      <h1>Responses</h1>
      <p class="muted">{{ shown.length }} {{ shown.length === 1 ? "response" : "responses" }}, newest first.</p>
    </div>
  </div>

  <div class="toolbar">
    <label for="filter" class="muted">Questionnaire</label>
    <select id="filter" v-model="filter">
      <option value="">All questionnaires</option>
      <option v-for="q in questionnaires" :key="q.slug" :value="q.slug">{{ q.title }}</option>
    </select>
  </div>
  <p v-if="error" class="status err">{{ error }}</p>

  <div class="card">
    <div class="table-wrap">
      <p v-if="loading" class="empty">Loading…</p>
      <table v-else-if="shown.length">
        <thead><tr><th>Sent</th><th>Questionnaire</th><th>From</th><th>Email</th><th>Answered</th></tr></thead>
        <tbody>
          <tr v-for="r in shown" :key="r.id" class="clickable" @click="router.push(`/responses/${r.id}`)">
            <td class="nowrap">{{ when(r.sentAt) }}<span v-if="r.updatedAt" class="muted"> · edited</span></td>
            <td>{{ r.title }}</td>
            <td>{{ r.name || "No name" }}</td>
            <td>{{ r.email || "–" }}</td>
            <td class="num">{{ answeredCount(r) }}</td>
          </tr>
        </tbody>
      </table>
      <p v-else class="empty">No responses {{ filter ? "to this questionnaire " : "" }}yet.</p>
    </div>
  </div>
</template>
