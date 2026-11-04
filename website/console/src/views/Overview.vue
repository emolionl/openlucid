<script setup>
import { ref, onMounted } from "vue";
import { collection, getDocs, query, orderBy, limit, getCountFromServer } from "firebase/firestore";
import { db } from "../firebase";
import { isAdmin } from "../session";
import { when, answeredCount, loadQuestionnaires } from "../lib/format";

const total = ref(null);
const users = ref(null);
const open = ref(null);
const latest = ref([]);
const error = ref("");

onMounted(async () => {
  try {
    const [count, recent, qs] = await Promise.all([
      getCountFromServer(collection(db, "responses")),
      getDocs(query(collection(db, "responses"), orderBy("sentAt", "desc"), limit(6))),
      loadQuestionnaires(),
    ]);
    total.value = count.data().count;
    latest.value = recent.docs.map((d) => ({ id: d.id, ...d.data() }));
    open.value = qs.filter((q) => q.status !== "closed").length;
    if (isAdmin()) users.value = (await getCountFromServer(collection(db, "users"))).data().count;
  } catch (e) {
    console.error(e);
    error.value = "The overview couldn't be loaded. Reload the page to try again.";
  }
});
</script>

<template>
  <div class="page-head">
    <div>
      <h1>Overview</h1>
      <p class="muted">Answers to the questionnaires on openlucid.nl/questions/.</p>
    </div>
  </div>
  <p v-if="error" class="status err">{{ error }}</p>

  <div class="stats">
    <div class="stat"><div class="label">Responses</div><div class="value">{{ total ?? "–" }}</div></div>
    <div class="stat"><div class="label">Open questionnaires</div><div class="value">{{ open ?? "–" }}</div></div>
    <div v-if="isAdmin()" class="stat"><div class="label">People signed in</div><div class="value">{{ users ?? "–" }}</div></div>
  </div>

  <h2>Latest responses</h2>
  <div class="card">
    <div class="table-wrap">
      <table v-if="latest.length">
        <thead><tr><th>Sent</th><th>Questionnaire</th><th>From</th><th>Answered</th></tr></thead>
        <tbody>
          <tr v-for="r in latest" :key="r.id" class="clickable" @click="$router.push(`/responses/${r.id}`)">
            <td class="nowrap">{{ when(r.sentAt) }}</td>
            <td>{{ r.title }}</td>
            <td>{{ r.name || r.email || "No name" }}</td>
            <td class="num">{{ answeredCount(r) }}</td>
          </tr>
        </tbody>
      </table>
      <p v-else class="empty">No responses yet. They appear here as soon as someone answers a questionnaire.</p>
    </div>
  </div>
</template>
