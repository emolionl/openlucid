import { createRouter, createWebHistory } from "vue-router";
import { session, whenReady } from "./session";

// meta.roles: who may open the page. Pages without roles are open to everyone who is signed in.
const STAFF = ["admin", "researcher"];

const routes = [
  { path: "/signin", name: "signin", component: () => import("./views/SignIn.vue"), meta: { public: true } },
  { path: "/overview", name: "overview", component: () => import("./views/Overview.vue"), meta: { roles: STAFF } },
  { path: "/responses", name: "responses", component: () => import("./views/Responses.vue"), meta: { roles: STAFF } },
  { path: "/responses/:id", name: "response", component: () => import("./views/ResponseDetail.vue") },
  { path: "/responses/:id/edit", name: "edit", component: () => import("./views/EditResponse.vue") },
  { path: "/questionnaires", name: "questionnaires", component: () => import("./views/Questionnaires.vue"), meta: { roles: STAFF } },
  { path: "/users", name: "users", component: () => import("./views/Users.vue"), meta: { roles: ["admin"] } },
  { path: "/documents", name: "documents", component: () => import("./views/Documents.vue"), meta: { roles: STAFF } },
  { path: "/documents/new", name: "document-new", component: () => import("./views/DocumentEditor.vue"), meta: { roles: STAFF } },
  { path: "/documents/:id/edit", name: "document-edit", component: () => import("./views/DocumentEditor.vue"), meta: { roles: STAFF } },
  { path: "/mine", name: "mine", component: () => import("./views/MyAnswers.vue") },
  { path: "/:rest(.*)*", name: "home", redirect: () => ({ name: "overview" }) },
];

export const router = createRouter({ history: createWebHistory("/"), routes });

router.beforeEach(async (to) => {
  await whenReady;
  // A sign-in link from the email lands here with its code in the query string.
  if (to.query.oobCode && to.name !== "signin") return { name: "signin", query: to.query };
  if (to.meta.public) return true;
  if (!session.user) return { name: "signin", query: { next: to.fullPath } };
  if (to.meta.roles && !to.meta.roles.includes(session.role)) return { name: "mine" };
  return true;
});
