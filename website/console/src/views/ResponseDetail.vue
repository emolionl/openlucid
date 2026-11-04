<script setup>
import { ref, computed, onMounted } from "vue";
import { useRoute, useRouter } from "vue-router";
import { doc, getDoc, deleteDoc } from "firebase/firestore";
import { db } from "../firebase";
import { session, isAdmin, seesAll } from "../session";
import { when, orderedAnswers, editUrl, SITE } from "../lib/format";

const route = useRoute();
const router = useRouter();
const r = ref(null);
const missing = ref(false);
const confirming = ref(false);
const status = ref("");

const mine = computed(() => r.value && session.user && r.value.email === session.user.email);
const items = computed(() => (r.value ? orderedAnswers(r.value.answers) : []));
const backTo = computed(() => (seesAll() ? "/responses" : "/mine"));

onMounted(async () => {
  try {
    const snap = await getDoc(doc(db, "responses", route.params.id));
    if (snap.exists()) r.value = { id: snap.id, ...snap.data() };
    else missing.value = true;
  } catch (e) {
    // The rules answer "not allowed" for someone else's response; show it the same as missing.
    missing.value = true;
  }
});

async function remove() {
  status.value = "Deleting…";
  try {
    await deleteDoc(doc(db, "responses", r.value.id));
    router.replace(backTo.value);
  } catch (e) {
    console.error(e);
    status.value = "Deleting didn't work. Reload and try again.";
  }
}
</script>

<template>
  <RouterLink :to="backTo" class="back">‹ {{ seesAll() ? "Responses" : "My answers" }}</RouterLink>

  <template v-if="missing">
    <h1>Response not found</h1>
    <p class="muted">It may have been deleted, or it belongs to someone else.</p>
  </template>

  <template v-else-if="r">
    <div class="page-head">
      <div>
        <h1>{{ r.name || "Response without a name" }}</h1>
        <p class="muted">{{ r.title }}</p>
      </div>
    </div>

    <dl class="meta-list">
      <dt>Sent</dt><dd>{{ when(r.sentAt) }}</dd>
      <template v-if="r.updatedAt"><dt>Last changed</dt><dd>{{ when(r.updatedAt) }}</dd></template>
      <dt>Email</dt><dd>{{ r.email || "Not given" }}</dd>
      <dt>Questionnaire</dt><dd><a :href="`${SITE}/questions/${r.questionnaire}/`">{{ r.questionnaire }}</a></dd>
      <dt>Id</dt><dd class="mono">{{ r.id }}</dd>
    </dl>

    <div class="card answers">
      <div v-for="i in items" :key="i.id" class="answer">
        <div class="q"><span class="mono">{{ String(i.n).padStart(2, "0") }}</span>{{ i.q }}</div>
        <div class="a">{{ i.lines.join("\n") }}</div>
      </div>
    </div>

    <div class="actions">
      <RouterLink v-if="mine || isAdmin()" :to="editUrl(r)" class="link-button">Change answers</RouterLink>
      <template v-if="isAdmin()">
        <button v-if="!confirming" type="button" class="danger" @click="confirming = true">Delete</button>
        <template v-else>
          <span class="muted">Delete this response for good?</span>
          <button type="button" class="danger" @click="remove">Yes, delete</button>
          <button type="button" class="ghost" @click="confirming = false">Keep it</button>
        </template>
      </template>
      <span class="status">{{ status }}</span>
    </div>
  </template>

  <p v-else class="muted loading">Loading…</p>
</template>
