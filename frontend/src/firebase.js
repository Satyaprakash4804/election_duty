import { initializeApp } from "firebase/app";
import { getMessaging, getToken, onMessage } from "firebase/messaging";

const firebaseConfig = {
  apiKey: "AIzaSyB-Whwa3Frajx7-IldPe3dwO4QLjLJaMjQ",
  authDomain: "election-duty-management.firebaseapp.com",
  projectId: "election-duty-management",
  storageBucket: "election-duty-management.firebasestorage.app",
  messagingSenderId: "791596517361",
  appId: "1:791596517361:web:2a963c00664f1997112650",
};

const app = initializeApp(firebaseConfig);
const messaging = getMessaging(app);

export { messaging, getToken, onMessage };