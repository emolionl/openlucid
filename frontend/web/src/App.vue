<script setup>
import { ref } from 'vue'

// Where the Diary Keeper (the backend) lives.
const diaryKeeperUrl = import.meta.env.VITE_DIARY_KEEPER_URL ?? 'http://localhost:8000'

const reply = ref('Not asked yet.')
const asking = ref(false)

// Checkpoint 00: the web app waves, the Diary Keeper waves back.
async function wave() {
  asking.value = true
  try {
    const response = await fetch(`${diaryKeeperUrl}/health`)
    const body = await response.json()
    reply.value = `${body.message} (${body.time})`
  } catch {
    reply.value = 'No answer. Is the Diary Keeper running? Start the backend first.'
  } finally {
    asking.value = false
  }
}
</script>

<template>
  <main>
    <h1>Lucid</h1>
    <p>Your nights, in the morning.</p>
    <button :disabled="asking" @click="wave">👋 Wave at the Diary Keeper</button>
    <p class="reply">{{ reply }}</p>
  </main>
</template>

<style scoped>
main {
  text-align: center;
  padding: 24px;
}

.reply {
  margin-top: 1.5em;
  opacity: 0.85;
}
</style>
