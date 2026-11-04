import { initializeApp } from "firebase/app";
import { getAuth } from "firebase/auth";
import { getFirestore } from "firebase/firestore";

// Public web config, the same as in website/hugo.toml. Access is decided by website/firestore.rules.
export const app = initializeApp({
  apiKey: "AIzaSyDTfhXqUfU05alHQMcYX-EuG2SG5HfPCIQ",
  authDomain: "openlucid.firebaseapp.com",
  projectId: "openlucid",
  appId: "1:655847610145:web:0fa5f6e4067766fd0f1060",
});

export const auth = getAuth(app);
export const db = getFirestore(app);
