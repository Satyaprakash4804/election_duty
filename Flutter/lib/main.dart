import 'package:flutter/material.dart';
import 'services/auth_service.dart';

// 🔹 ADMIN PAGES
import 'screens/admin/admin_dashboard.dart';

// 🔹 LOGIN PAGE (CREATE THIS FILE IF NOT EXISTS)
import 'screens/auth/login_page.dart';
import 'screens/master_admin/master_dashboard.dart';
import 'screens/super_admin/super_dashboard.dart';
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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

      // ✅ ROUTES (VERY IMPORTANT)
      routes: {
        '/login': (context) => const LoginPage(),
        '/admin': (context) => const AdminDashboard(),
        '/master': (context) => const MasterDashboard(),
        '/super': (context) => const SuperDashboard(),
      
      },

      // ✅ AUTO LOGIN CHECK
      home: const AuthCheck(),
    );
  }
}

//
// 🔥 AUTH CHECK (DECIDES WHERE TO GO)
//
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

        // 🔥 ROLE BASED REDIRECT
        switch (role) {
          case "MASTER":
            return const MasterDashboard();

          case "SUPER_ADMIN":
            return const SuperDashboard();

          case "ADMIN":
            return const AdminDashboard();

          

          default:
            return const LoginPage();
        }
      },
    );
  }
}