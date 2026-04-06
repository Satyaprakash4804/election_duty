importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyB-Whwa3Frajx7-IldPe3dwO4QLjLJaMjQ",
  authDomain: "election-duty-management.firebaseapp.com",
  projectId: "election-duty-management",
  messagingSenderId: "791596517361",
  appId: "1:791596517361:web:2a963c00664f1997112650",
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function (payload) {
  console.log("Background message:", payload);

  self.registration.showNotification(payload.notification.title, {
    body: payload.notification.body,
    icon: "/logo.png",
  });
});