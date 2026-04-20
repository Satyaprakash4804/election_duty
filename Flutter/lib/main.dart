import 'package:flutter/material.dart';
import 'services/auth_service.dart';

// 🔹 ADMIN PAGES
import 'screens/admin/admin_dashboard.dart';
import 'screens/staff/staff_dashboard_page.dart';

// 🔹 AUTH / LOGIN
import 'screens/auth/login_page.dart';
import 'screens/master_admin/master_dashboard.dart';
import 'screens/super_admin/super_dashboard.dart';

// 🔥 Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

// 🔔 LOCAL NOTIFICATIONS
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mappls_gl/mappls_gl.dart';

import 'routes.dart';
import 'screens/admin/map_view.dart';

// ✅ GLOBAL INSTANCE
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// 🔥 BACKGROUND HANDLER
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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

  // 🔔 Initialize local notifications
  const AndroidInitializationSettings androidInit =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings =
      InitializationSettings(android: androidInit);
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  // ── Mappls SDK Keys ─────────────────────
  MapplsAccountManager.setMapSDKKey("YOUR_KEY");
  MapplsAccountManager.setRestAPIKey("YOUR_KEY");
  MapplsAccountManager.setAtlasClientId("YOUR_ID");
  MapplsAccountManager.setAtlasClientSecret("YOUR_SECRET");
  // ────────────────────────────────────────

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
    requestPermission();
    getToken();
    setupNotificationChannel();

    // 🔔 Foreground listener
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        showNotification(message);
      }
    });
  }

  /// 🔐 REQUEST PERMISSION
  Future<void> requestPermission() async {
    NotificationSettings settings =
        await FirebaseMessaging.instance.requestPermission();
    print("Permission status: ${settings.authorizationStatus}");
  }

  /// 🔑 GET TOKEN
  Future<void> getToken() async {
    String? token = await FirebaseMessaging.instance.getToken();
    print("🔥 FCM TOKEN: $token");
  }

  /// 🔔 CREATE CHANNEL
  Future<void> setupNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'channel_id',
      'channel_name',
      description: 'Important notifications',
      importance: Importance.high,
    );
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// 🔔 SHOW NOTIFICATION
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
      0,
      message.notification?.title ?? "No Title",
      message.notification?.body ?? "No Body",
      notificationDetails,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Election Admin',
      debugShowCheckedModeBanner: false,

      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),

      // ✅ FIX: initialRoute only — no home: property
      // '/splash' → OfficerSplashPage (cold-start entry)
      // '/'       → AuthCheck (checks if already logged in)
      // After login success → PostLoginSplashPage → dashboard
      initialRoute: '/splash',

      routes: {
        '/splash':   (_) => const OfficerSplashPage(),      // 🎖️ Cold-start splash
        '/':         (_) => const AuthCheck(),              // 🔐 Auth gate
        '/login':    (_) => const LoginPage(),
        '/admin':    (_) => const AdminDashboard(),
        '/master':   (_) => const MasterDashboard(),
        '/super':    (_) => const SuperDashboard(),
        '/staff':    (_) => const StaffDashboardPage(),
        '/map-view': (_) => const MapViewPage(),
      },

      // ❌ DO NOT add: home: const AuthCheck()
      // It conflicts with routes['/'] and causes a crash
    );
  }
}

// ═════════════════════════════════════════════
//  AUTH CHECK
//  Checks SharedPreferences for saved login token.
//  If logged in  → go directly to role dashboard (no splash again)
//  If not logged → show LoginPage
// ═════════════════════════════════════════════
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
        final role       = snapshot.data![1] as String?;

        if (!isLoggedIn) return const LoginPage();

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