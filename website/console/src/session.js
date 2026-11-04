import { reactive } from "vue";
import { onAuthStateChanged } from "firebase/auth";
import { doc, getDoc, setDoc, serverTimestamp } from "firebase/firestore";
import { auth, db } from "./firebase";

// Who is signed in, and their role from users/{uid}. A first sign-in creates that doc as "respondent";
// only an admin can raise a role (see firestore.rules).
export const ROLES = ["admin", "researcher", "client", "respondent"];

export const session = reactive({ ready: false, user: null, role: null, problem: "" });

let markReady;
export const whenReady = new Promise((resolve) => (markReady = resolve));

onAuthStateChanged(auth, async (user) => {
  session.user = user;
  session.role = null;
  session.problem = "";
  if (user) {
    const ref = doc(db, "users", user.uid);
    try {
      const snap = await getDoc(ref);
      if (snap.exists()) {
        session.role = snap.data().role;
      } else {
        await setDoc(ref, { email: user.email, role: "respondent", createdAt: serverTimestamp() });
        session.role = "respondent";
      }
    } catch (e) {
      console.error(e);
      session.role = "respondent";
      session.problem = "Your profile couldn't be loaded, so you only see your own answers for now.";
    }
  }
  session.ready = true;
  markReady();
});

export const seesAll = () => session.role === "admin" || session.role === "researcher";
export const isAdmin = () => session.role === "admin";
