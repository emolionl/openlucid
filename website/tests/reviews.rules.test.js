// Who may do what in reviews/ (and the roles around it). Runs against the Firestore emulator:
//   cd website && firebase emulators:exec --only firestore "npm --prefix tests test"
import { test, before, after, beforeEach } from "node:test";
import { readFileSync } from "node:fs";
import { initializeTestEnvironment, assertSucceeds, assertFails } from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, addDoc, updateDoc, collection, getDocs, serverTimestamp } from "firebase/firestore";

const HASH = "a".repeat(64);
let env;

const people = {
  admin: { role: "admin", displayName: "Ada Admin" },
  researcher: { role: "researcher" },
  reviewer: { role: "reviewer", displayName: "Rita Reviewer" },
  respondent: { role: "respondent" },
};

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "openlucid-rules-test",
    firestore: { rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8") },
  });
});
after(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [uid, data] of Object.entries(people)) await setDoc(doc(db, "users", uid), { email: `${uid}@example.org`, createdAt: new Date(), ...data });
    await setDoc(doc(db, "documents", "d1"), { title: "Doc", body: "Text", status: "draft", createdAt: new Date(), updatedAt: new Date() });
    await setDoc(doc(db, "reviews", "documents:d1"), { title: "Doc", kind: "document", ref: "documents/d1", status: "draft", updatedAt: new Date(), updatedBy: "admin" });
    await setDoc(doc(db, "reviews", "documents:d1", "claims", "c1"), { quote: "Text", source: { doi: "10.1/x" }, order: 1, state: "active", createdAt: new Date(), createdBy: "admin" });
    await setDoc(doc(db, "reviews", "documents:d1", "claims", "c1", "checks", "k1"), { agent: 1, verdict: "supported" });
    await setDoc(doc(db, "reviews", "documents:d1", "humanReviews", "h1"), { reviewerUid: "reviewer", reviewerName: "Rita Reviewer" });
  });
});

const as = (uid) => (uid ? env.authenticatedContext(uid, { email: `${uid}@example.org`, email_verified: true }) : env.unauthenticatedContext()).firestore();
const reviewDoc = (uid, status) => ({ title: "Doc", kind: "document", ref: "documents/d1", status, updatedAt: serverTimestamp(), updatedBy: uid });
const claim = (uid) => ({ quote: "A claim", source: { doi: "10.1/y", citation: "X 2020" }, order: 2, state: "active", createdAt: serverTimestamp(), createdBy: uid });
const human = (uid, name) => ({ reviewerUid: uid, reviewerName: name, createdAt: serverTimestamp(), contentHash: HASH, scope: "claims 1-2", checklist: { fullText: true }, verdicts: { c1: { verdict: "supported", location: "p. 3" } } });

test("anyone can read the review, its claims, checks and human reviews (they feed public labels)", async () => {
  const db = as(null);
  await assertSucceeds(getDoc(doc(db, "reviews", "documents:d1")));
  await assertSucceeds(getDocs(collection(db, "reviews", "documents:d1", "claims")));
  await assertSucceeds(getDocs(collection(db, "reviews", "documents:d1", "claims", "c1", "checks")));
  await assertSucceeds(getDocs(collection(db, "reviews", "documents:d1", "humanReviews")));
});

test("visitors and respondents can't write anything in reviews", async () => {
  for (const uid of [null, "respondent"]) {
    const db = as(uid);
    await assertFails(setDoc(doc(db, "reviews", "documents:d2"), reviewDoc(uid || "x", "draft")));
    await assertFails(addDoc(collection(db, "reviews", "documents:d1", "claims"), claim(uid || "x")));
    await assertFails(addDoc(collection(db, "reviews", "documents:d1", "humanReviews"), human(uid || "x", "Someone")));
  }
});

test("nobody can write agent checks from the browser, not even an admin", async () => {
  for (const uid of ["admin", "reviewer", "researcher"]) {
    await assertFails(setDoc(doc(as(uid), "reviews", "documents:d1", "claims", "c1", "checks", "k2"), { agent: 2, verdict: "supported" }));
    await assertFails(updateDoc(doc(as(uid), "reviews", "documents:d1", "claims", "c1", "checks", "k1"), { verdict: "not-supported" }));
  }
});

test("a researcher adds claims and keeps a page in Draft, but can't move it on", async () => {
  const db = as("researcher");
  await assertSucceeds(addDoc(collection(db, "reviews", "documents:d1", "claims"), claim("researcher")));
  await assertSucceeds(setDoc(doc(db, "reviews", "documents:d1"), reviewDoc("researcher", "draft")));
  await assertFails(setDoc(doc(db, "reviews", "documents:d1"), reviewDoc("researcher", "published")));
  await assertFails(setDoc(doc(db, "reviews", "documents:d1"), reviewDoc("researcher", "human-reviewed")));
});

test("a researcher can't sign off a review", async () => {
  await assertFails(addDoc(collection(as("researcher"), "reviews", "documents:d1", "humanReviews"), human("researcher", "Ren Researcher")));
});

test("a reviewer moves the status and signs off under their own profile name", async () => {
  const db = as("reviewer");
  await assertSucceeds(setDoc(doc(db, "reviews", "documents:d1"), reviewDoc("reviewer", "published")));
  await assertSucceeds(addDoc(collection(db, "reviews", "documents:d1", "humanReviews"), human("reviewer", "Rita Reviewer")));
});

test("a human review must carry your own uid and your own profile name", async () => {
  const db = as("reviewer");
  await assertFails(addDoc(collection(db, "reviews", "documents:d1", "humanReviews"), human("admin", "Rita Reviewer")));
  await assertFails(addDoc(collection(db, "reviews", "documents:d1", "humanReviews"), human("reviewer", "Martin Dresler")));
});

test("a human review needs a 64-character text hash and a scope", async () => {
  const db = as("reviewer");
  await assertFails(addDoc(collection(db, "reviews", "documents:d1", "humanReviews"), { ...human("reviewer", "Rita Reviewer"), contentHash: "abc" }));
  await assertFails(addDoc(collection(db, "reviews", "documents:d1", "humanReviews"), { ...human("reviewer", "Rita Reviewer"), scope: "" }));
});

test("human reviews are append-only, even for admins", async () => {
  for (const uid of ["reviewer", "admin"]) {
    await assertFails(updateDoc(doc(as(uid), "reviews", "documents:d1", "humanReviews", "h1"), { scope: "everything" }));
  }
});

test("someone without a profile name can't sign off", async () => {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), "users", "reviewer"), { role: "reviewer", email: "reviewer@example.org", createdAt: new Date() }));
  await assertFails(addDoc(collection(as("reviewer"), "reviews", "documents:d1", "humanReviews"), human("reviewer", "Rita Reviewer")));
});

test("only an admin sets the name on someone's reviews; nobody sets their own role", async () => {
  await assertFails(updateDoc(doc(as("reviewer"), "users", "reviewer"), { displayName: "Prof. Famous" }));
  await assertFails(updateDoc(doc(as("respondent"), "users", "respondent"), { displayName: "Rob" }));
  await assertFails(updateDoc(doc(as("respondent"), "users", "respondent"), { role: "reviewer" }));
  await assertSucceeds(updateDoc(doc(as("admin"), "users", "reviewer"), { displayName: "Rita R." }));
  await assertSucceeds(updateDoc(doc(as("admin"), "users", "respondent"), { role: "reviewer", displayName: "Rob" }));
});

test("an admin can give someone the reviewer role", async () => {
  await assertSucceeds(updateDoc(doc(as("admin"), "users", "respondent"), { role: "reviewer" }));
});

test("a reviewer sees the documents list but can't edit documents", async () => {
  const db = as("reviewer");
  await assertSucceeds(getDocs(collection(db, "documents")));
  await assertFails(updateDoc(doc(db, "documents", "d1"), { title: "Changed", updatedAt: serverTimestamp() }));
});

test("claims keep who created them and when", async () => {
  await assertFails(updateDoc(doc(as("researcher"), "reviews", "documents:d1", "claims", "c1"), { createdBy: "researcher", updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(doc(as("researcher"), "reviews", "documents:d1", "claims", "c1"), { note: "table 2", updatedAt: serverTimestamp() }));
});

test("a claim's sentence and source can't be changed in place (a change is a new claim)", async () => {
  for (const uid of ["researcher", "reviewer", "admin"]) {
    await assertFails(updateDoc(doc(as(uid), "reviews", "documents:d1", "claims", "c1"), { quote: "Different", updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as(uid), "reviews", "documents:d1", "claims", "c1"), { source: { doi: "10.9/other" }, updatedAt: serverTimestamp() }));
  }
});

test("only reviewers and admins remove or restore a claim", async () => {
  await assertFails(updateDoc(doc(as("researcher"), "reviews", "documents:d1", "claims", "c1"), { state: "removed", updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(doc(as("reviewer"), "reviews", "documents:d1", "claims", "c1"), { state: "removed", updatedAt: serverTimestamp() }));
  await assertFails(addDoc(collection(as("admin"), "reviews", "documents:d1", "claims"), { ...claim("admin"), state: "removed" }));
});

test("source links must be http(s): no javascript: or data: URLs", async () => {
  const db = as("researcher");
  for (const url of ["javascript:alert(1)", "data:text/html,x", "ftp://x"]) {
    await assertFails(addDoc(collection(db, "reviews", "documents:d1", "claims"), { ...claim("researcher"), source: { url } }));
  }
  await assertSucceeds(addDoc(collection(db, "reviews", "documents:d1", "claims"), { ...claim("researcher"), source: { url: "https://example.org/a" } }));
});

test("claims and human reviews need an existing review, and a review's ref must match its id", async () => {
  await assertFails(addDoc(collection(as("researcher"), "reviews", "documents:nope", "claims"), claim("researcher")));
  await assertFails(addDoc(collection(as("reviewer"), "reviews", "documents:nope", "humanReviews"), human("reviewer", "Rita Reviewer")));
  await assertFails(setDoc(doc(as("researcher"), "reviews", "documents:d2"), { ...reviewDoc("researcher", "draft"), ref: "documents/other" }));
  await assertSucceeds(setDoc(doc(as("researcher"), "reviews", "documents:d2"), { ...reviewDoc("researcher", "draft"), ref: "documents/d2" }));
  await assertSucceeds(setDoc(doc(as("researcher"), "reviews", "page:course:11-x"), { ...reviewDoc("researcher", "draft"), kind: "page", ref: "course/11-x" }));
  await assertFails(setDoc(doc(as("researcher"), "reviews", "page:course:11-x"), { ...reviewDoc("researcher", "draft"), kind: "page", ref: "course/other" }));
});

test("a profile can't be created without a verified email", async () => {
  const unverified = env.authenticatedContext("newbie", { email: "n@example.org", email_verified: false }).firestore();
  await assertFails(setDoc(doc(unverified, "users", "newbie"), { email: null, role: "respondent", createdAt: serverTimestamp() }));
});
