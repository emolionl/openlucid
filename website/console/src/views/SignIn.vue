<script setup>
import { ref, onMounted } from "vue";
import { useRoute, useRouter } from "vue-router";
import { sendSignInLinkToEmail, isSignInWithEmailLink, signInWithEmailLink, signInWithPopup, GoogleAuthProvider } from "firebase/auth";
import { auth } from "../firebase";
import { session } from "../session";

// Two ways in, both without a password here: Google, or a link we email you. The email is remembered
// in this browser so the link can finish the sign-in; on another device we ask for it once more.
// Answers are matched to you by email, so sign in with the address you gave on the questionnaire.
const KEY = "openlucid-signin-email";
const route = useRoute();
const router = useRouter();

const email = ref("");
const status = ref("");
const kind = ref("");
const busy = ref(false);
const finishing = ref(false);

const remember = (v) => { try { localStorage.setItem(KEY, v); } catch (e) {} };
const recall = () => { try { return localStorage.getItem(KEY) || ""; } catch (e) { return ""; } };
const forget = () => { try { localStorage.removeItem(KEY); } catch (e) {} };

const nextPage = () => (typeof route.query.next === "string" && route.query.next.startsWith("/") ? route.query.next : "/");

async function google() {
  busy.value = true;
  kind.value = "";
  status.value = "Opening Google…";
  try {
    await signInWithPopup(auth, new GoogleAuthProvider());
    const wait = () => new Promise((r) => { const t = setInterval(() => { if (session.user && session.role) { clearInterval(t); r(); } }, 50); });
    await wait();
    router.replace(nextPage());
  } catch (e) {
    console.error(e);
    busy.value = false;
    kind.value = "err";
    status.value = e.code === "auth/popup-closed-by-user" || e.code === "auth/cancelled-popup-request"
      ? ""
      : e.code === "auth/popup-blocked"
        ? "Your browser blocked the Google window. Allow pop-ups for this site, or use the email link."
        : e.code === "auth/account-exists-with-different-credential"
          ? "This email already signs in another way. Use the email link instead."
          : "Signing in with Google didn't work. Try again, or use the email link.";
  }
}

async function finish(address) {
  busy.value = true;
  status.value = "Signing you in…";
  kind.value = "";
  try {
    await signInWithEmailLink(auth, address, window.location.href);
    forget();
    // session.js picks up the new user; wait until the role is known before moving on.
    const wait = () => new Promise((r) => { const t = setInterval(() => { if (session.user && session.role) { clearInterval(t); r(); } }, 50); });
    await wait();
    router.replace(nextPage());
  } catch (e) {
    console.error(e);
    busy.value = false;
    kind.value = "err";
    status.value = e.code === "auth/invalid-action-code" || e.code === "auth/expired-action-code"
      ? "This sign-in link has expired or was already used. Ask for a new one below."
      : e.code === "auth/invalid-email"
        ? "That email doesn't match the one the link was sent to."
        : "Signing in didn't work. Ask for a new link below.";
    finishing.value = false;
  }
}

async function send() {
  const address = email.value.trim().toLowerCase();
  if (!address.includes("@")) { kind.value = "err"; status.value = "Enter your email address."; return; }
  if (finishing.value) return finish(address);
  busy.value = true;
  status.value = "Sending…";
  kind.value = "";
  try {
    await sendSignInLinkToEmail(auth, address, {
      url: `${window.location.origin}/signin${route.query.next ? "?next=" + encodeURIComponent(nextPage()) : ""}`,
      handleCodeInApp: true,
    });
    remember(address);
    kind.value = "ok";
    status.value = `Check your inbox at ${address} and open the link. It can take a minute; look in spam too.`;
  } catch (e) {
    console.error(e);
    kind.value = "err";
    status.value = e.code === "auth/too-many-requests" ? "Too many links asked for. Wait a few minutes and try again." : "The link couldn't be sent. Check the address and try again.";
  } finally {
    busy.value = false;
  }
}

onMounted(() => {
  if (session.user) { router.replace(nextPage()); return; }
  if (isSignInWithEmailLink(auth, window.location.href)) {
    finishing.value = true;
    const saved = recall();
    if (saved) finish(saved);
    else status.value = "You opened the link on another device or browser. Enter your email once more to finish signing in.";
  }
});
</script>

<template>
  <section class="signin">
    <h1>Sign in</h1>
    <p class="muted">No password needed. To see or change your answers, sign in with the email address you gave with them.</p>
    <div v-if="!finishing" class="stack">
      <button type="button" class="google" :disabled="busy" @click="google">
        <svg viewBox="0 0 24 24" aria-hidden="true"><path fill="#4285F4" d="M22.6 12.2c0-.8-.1-1.5-.2-2.2H12v4.2h6a5.1 5.1 0 0 1-2.2 3.4v2.8h3.6c2.1-1.9 3.2-4.8 3.2-8.2z"/><path fill="#34A853" d="M12 23c3 0 5.5-1 7.4-2.7l-3.6-2.8c-1 .7-2.3 1.1-3.8 1.1-2.9 0-5.4-2-6.3-4.6H2v2.9A11 11 0 0 0 12 23z"/><path fill="#FBBC05" d="M5.7 14c-.2-.7-.4-1.4-.4-2s.1-1.4.4-2V7.1H2a11 11 0 0 0 0 9.8L5.7 14z"/><path fill="#EA4335" d="M12 5.4c1.6 0 3.1.6 4.3 1.7l3.2-3.2A11 11 0 0 0 2 7.1L5.7 10c.9-2.7 3.4-4.6 6.3-4.6z"/></svg>
        Sign in with Google
      </button>
      <p class="or"><span>or</span></p>
    </div>
    <form class="stack" @submit.prevent="send">
      <label for="signin-email">Email</label>
      <input id="signin-email" v-model="email" type="email" autocomplete="email" maxlength="200" required>
      <button type="submit" class="primary" :disabled="busy">{{ finishing ? "Finish signing in" : "Email me a sign-in link" }}</button>
      <p class="status" :class="kind" role="status" aria-live="polite">{{ status }}</p>
    </form>
  </section>
</template>
