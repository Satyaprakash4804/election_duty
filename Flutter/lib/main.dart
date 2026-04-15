import 'package:flutter/material.dart';
import 'services/auth_service.dart';

// 🔹 ADMIN PAGES
import 'screens/admin/admin_dashboard.dart';
import 'screens/staff/staff_dashboard_page.dart';
// 🔹 LOGIN PAGE
import 'screens/auth/login_page.dart';
import 'screens/master_admin/master_dashboard.dart';
import 'screens/super_admin/super_dashboard.dart';

// 🔥 Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

// 🔔 LOCAL NOTIFICATIONS (IMPORTANT)
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mappls_gl/mappls_gl.dart';
import 'routes.dart';
import 'screens/admin/map_view.dart';
// ✅ GLOBAL INSTANCE (REQUIRED)
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// 🔥 BACKGROUND HANDLER
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("🔔 Background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
 
  // 🔥 Firebase init
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
 
  // 🔥 Background messages
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
 
  // ── Mappls SDK Keys ──────────────────────────────────────────────────────
  MapplsAccountManager.setMapSDKKey(
    "425ddc32f3f0804e17759093b419b7c1",
  );
  MapplsAccountManager.setRestAPIKey(
    "425ddc32f3f0804e17759093b419b7c1",
  );
  MapplsAccountManager.setAtlasClientId(
    "96dHZVzsAutM-QgqZkpIgMIElHDAROdmtsJMu1Iyfiq7w3cjgvx0IxST_h0Ks0byMFpNX0VkQMmKgbyCnCMdRQ==",
  );
  MapplsAccountManager.setAtlasClientSecret(
    "lrFxI-iSEg8l1bHwBPApQm8q7Bti1e6d786Y0tXnzUV8030fiz4xXymqWP0zMDM1VOoZJefcj85eSXJlY7Tm-r4bz_JFSvXS",
  );
  // ── End Mappls Keys ──────────────────────────────────────────────────────
 
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {

  @override
  void initState() {
    super.initState();

    getToken();

    // 🔐 Permission (important Android 13+)
    FirebaseMessaging.instance.requestPermission();

    setupNotificationChannel();

    // 🔔 FOREGROUND MESSAGE LISTENER
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("🔔 Foreground message received");

      if (message.notification != null) {
        print("Title: ${message.notification!.title}");
        print("Body: ${message.notification!.body}");

        showNotification(message);
      }
    });
  }

  /// 🔑 GET FCM TOKEN
  Future<void> getToken() async {
    String? token = await FirebaseMessaging.instance.getToken();
    print("🔥 FCM TOKEN: $token");
  }

  /// 🔔 CREATE NOTIFICATION CHANNEL (ANDROID)
  Future<void> setupNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'channel_id',
      'channel_name',
      description: 'This channel is used for important notifications',
      importance: Importance.high,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// 🔔 SHOW LOCAL NOTIFICATION
  Future<void> showNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'channel_id',
      'channel_name',
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);

    await flutterLocalNotificationsPlugin.show(
      id: 0,
      title: message.notification?.title ?? "No Title",
      body: message.notification?.body ?? "No Body",
      notificationDetails: notificationDetails,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Election Admin',
      debugShowCheckedModeBanner: false,

      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1565C0),
          foregroundColor: Colors.white,
          elevation: 2,
        ),
      ),

      // ✅ ROUTES
      routes: {
        '/login': (context) => const LoginPage(),
        '/admin': (context) => const AdminDashboard(),
        '/master': (context) => const MasterDashboard(),
        '/super': (context) => const SuperDashboard(),
        '/staff': (context) => const StaffDashboardPage(),
        '/map-view': (context) => const MapViewPage(),
      },

      // ✅ AUTO LOGIN CHECK
      home: const AuthCheck(),
    );
  }
}

/// 🔥 AUTH CHECK (UNCHANGED)
class AuthCheck extends StatelessWidget {
  const AuthCheck({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.wait([
        AuthService.isLoggedIn(),
        AuthService.getRole(),
      ]),
      builder: (context, snapshot) {

        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final isLoggedIn = snapshot.data![0] as bool;
        final role = snapshot.data![1] as String?;

        if (!isLoggedIn) {
          return const LoginPage();
        }

        switch (role) {
          case "MASTER":
            return const MasterDashboard();

          case "SUPER_ADMIN":
            return const SuperDashboard();

          case "ADMIN":
            return const AdminDashboard();

          case "STAFF":
            return const StaffDashboardPage();

          default:
            return const LoginPage();
        }
      },
    );
  }
}