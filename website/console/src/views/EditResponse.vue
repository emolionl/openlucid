<script setup>
import { ref, reactive, computed, onMounted } from "vue";
import { useRoute, useRouter } from "vue-router";
import { doc, getDoc, updateDoc, serverTimestamp, deleteField } from "firebase/firestore";
import { db } from "../firebase";
import { session, isAdmin } from "../session";
import { loadQuestionnaires, SITE } from "../lib/format";

// Change a response with the same questions as on the website (from /questions/index.json).
// The rules let the owner change only answers and name; admins can change anything.
const route = useRoute();
const router = useRouter();
const r = ref(null);
const sections = ref([]);
const form = reactive({});
const problem = ref("");
const status = ref("");
const saving = ref(false);

const items = computed(() => sections.value.flatMap((s) => s.items));

onMounted(async () => {
  try {
    const [snap, qs] = await Promise.all([getDoc(doc(db, "responses", route.params.id)), loadQuestionnaires()]);
    if (!snap.exists()) { problem.value = "This response doesn't exist, or it belongs to someone else."; return; }
    r.value = { id: snap.id, ...snap.data() };
    if (!(isAdmin() || r.value.email === session.user.email)) { problem.value = "Only the person who sent these answers can change them."; return; }
    const q = qs.find((x) => x.slug === r.value.questionnaire);
    if (!q || !q.sections) { problem.value = "This questionnaire isn't on the website anymore, so its answers can't be changed here."; return; }
    sections.value = q.sections;
    for (const item of items.value) {
      const a = r.value.answers?.[item.id] || {};
      form[item.id] = { picked: [...(a.picked || [])], choice: (a.picked || [])[0] || "", other: a.other || "", comment: a.comment || "", text: a.text || "" };
    }
  } catch (e) {
    console.error(e);
    problem.value = "This response couldn't be loaded.";
  }
});

function collect() {
  const answers = {};
  items.value.forEach((item, i) => {
    const f = form[item.id];
    const a = {};
    const picked = item.type === "choice" ? (f.choice ? [f.choice] : []) : item.type === "multi" ? f.picked : [];
    if (picked.length) a.picked = picked;
    for (const part of ["other", "comment", "text"]) if (f[part].trim()) a[part] = f[part].trim();
    if (Object.keys(a).length) answers[item.id] = { n: i + 1, q: item.q, ...a };
  });
  return answers;
}

async function save() {
  const answers = collect();
  if (!Object.keys(answers).length) { status.value = "Keep at least one answer. To remove everything, ask the maintainer."; return; }
  saving.value = true;
  status.value = "Saving…";
  const name = answers.who_name?.text?.slice(0, 200);
  try {
    await updateDoc(doc(db, "responses", r.value.id), { answers, name: name || deleteField(), updatedAt: serverTimestamp() });
    router.replace(`/responses/${r.value.id}`);
  } catch (e) {
    console.error(e);
    saving.value = false;
    status.value = "Saving didn't work. Reload the page and try again.";
  }
}
</script>

<template>
  <RouterLink :to="`/responses/${route.params.id}`" class="back">‹ Back to the answers</RouterLink>

  <template v-if="problem">
    <h1>Can't change these answers</h1>
    <p class="muted">{{ problem }}</p>
  </template>

  <template v-else-if="r && sections.length">
    <div class="page-head">
      <div>
        <h1>Change your answers</h1>
        <p class="muted">{{ r.title }} · <a :href="`${SITE}/questions/${r.questionnaire}/`">see the questionnaire</a></p>
      </div>
    </div>

    <form class="edit-form" @submit.prevent="save">
      <section v-for="s in sections" :key="s.title" class="edit-section">
        <h2>{{ s.title }}</h2>
        <div v-for="item in s.items" :key="item.id" class="card edit-q">
          <p class="edit-title">{{ item.q }}</p>
          <p v-if="item.why" class="muted small">{{ item.why }}</p>

          <template v-if="item.type === 'choice' || item.type === 'multi'">
            <label v-for="(o, i) in item.options" :key="o" class="opt" :for="`${item.id}_${i}`">
              <input v-if="item.type === 'choice'" :id="`${item.id}_${i}`" v-model="form[item.id].choice" type="radio" :name="item.id" :value="o">
              <input v-else :id="`${item.id}_${i}`" v-model="form[item.id].picked" type="checkbox" :value="o">
              <span>{{ o }}</span>
            </label>
            <button v-if="item.type === 'choice' && form[item.id].choice" type="button" class="ghost small" @click="form[item.id].choice = ''">Clear choice</button>
            <template v-if="item.other">
              <label class="field-label" :for="`${item.id}_other`">Other</label>
              <input :id="`${item.id}_other`" v-model="form[item.id].other" type="text" maxlength="300">
            </template>
            <template v-if="item.comment">
              <label class="field-label" :for="`${item.id}_comment`">{{ item.comment }}</label>
              <textarea :id="`${item.id}_comment`" v-model="form[item.id].comment" rows="3" maxlength="4000"></textarea>
            </template>
          </template>
          <input v-else-if="item.type === 'short'" v-model="form[item.id].text" type="text" maxlength="200" :aria-label="item.q">
          <textarea v-else v-model="form[item.id].text" rows="4" maxlength="4000" :aria-label="item.q"></textarea>
        </div>
      </section>

      <div class="actions sticky-actions">
        <button type="submit" class="primary" :disabled="saving">Save changes</button>
        <RouterLink :to="`/responses/${r.id}`" class="ghost-link">Cancel</RouterLink>
        <span class="status">{{ status }}</span>
      </div>
    </form>
  </template>

  <p v-else class="muted loading">Loading…</p>
</template>
