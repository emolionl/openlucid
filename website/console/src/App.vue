<script setup>
import { ref, computed, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { signOut } from "firebase/auth";
import { auth } from "./firebase";
import { session } from "./session";
import { SITE } from "./lib/format";

const route = useRoute();
const router = useRouter();
const navOpen = ref(false);

// The sidebar: each link lists who sees it. Add a page here and in router.js.
const groups = [
  {
    title: "Questionnaires",
    links: [
      { to: "/overview", label: "Overview", roles: ["admin", "researcher"], icon: "M4 13h6V4H4zm0 7h6v-5H4zm10 0h6v-9h-6zm0-16v5h6V4z" },
      { to: "/responses", label: "Responses", roles: ["admin", "researcher"], icon: "M5 4h14v16H5zM8 8h8M8 12h8M8 16h5" },
      { to: "/questionnaires", label: "Questionnaires", roles: ["admin", "researcher"], icon: "M9 9a3 3 0 1 1 4 2.8c-.6.3-1 .8-1 1.4V14M12 18h.01M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20z" },
      { to: "/mine", label: "My answers", icon: "M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zm-7 8a7 7 0 0 1 14 0" },
    ],
  },
  {
    title: "Project",
    links: [
      { to: "/users", label: "Users & roles", roles: ["admin"], icon: "M9 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7zM2.5 20a6.5 6.5 0 0 1 13 0M16 4.5a3.5 3.5 0 0 1 0 6.5M18 14a6.5 6.5 0 0 1 3.5 6" },
    ],
  },
];

const visibleGroups = computed(() =>
  groups
    .map((g) => ({ ...g, links: g.links.filter((l) => !l.roles || l.roles.includes(session.role)) }))
    .filter((g) => g.links.length)
);

const signedIn = computed(() => session.ready && session.user);

watch(() => route.fullPath, () => (navOpen.value = false));
watch(navOpen, (open) => document.body.classList.toggle("nav-open", open));

async function leave() {
  await signOut(auth);
  router.push({ name: "signin" });
}
</script>

<template>
  <header class="topbar">
    <button v-if="signedIn" class="nav-toggle" type="button" :aria-expanded="navOpen" aria-controls="sidebar" aria-label="Menu" @click="navOpen = !navOpen"><span aria-hidden="true"></span></button>
    <a class="brand" :href="SITE"><img src="/logo-mark-96.png" alt=""><span>OpenLucid</span></a>
    <span class="topbar-title">Console</span>
    <div v-if="signedIn" class="topbar-user">
      <span class="who">{{ session.user.email }}</span>
      <span class="role-chip">{{ session.role }}</span>
      <button type="button" class="ghost" @click="leave">Sign out</button>
    </div>
  </header>

  <div class="shell" :class="{ 'no-nav': !signedIn }">
    <nav v-if="signedIn" class="sidebar" id="sidebar" aria-label="Console">
      <template v-for="g in visibleGroups" :key="g.title">
        <p class="nav-group">{{ g.title }}</p>
        <RouterLink v-for="l in g.links" :key="l.to" :to="l.to" active-class="active">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path :d="l.icon" /></svg>{{ l.label }}
        </RouterLink>
      </template>
      <a :href="`${SITE}/questions/`" class="external">
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M14 4h6v6M20 4l-9 9M18 14v6H4V6h6" /></svg>Open the website
      </a>
    </nav>

    <main class="content">
      <p v-if="session.problem" class="status err">{{ session.problem }}</p>
      <p v-if="!session.ready" class="muted loading">Loading…</p>
      <RouterView v-else />
    </main>
  </div>
</template>
