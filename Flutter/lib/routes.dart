import 'screens/admin/map_view.dart';
import 'package:flutter/material.dart';
import 'screens/auth/login_page.dart';
import 'screens/master_admin/master_dashboard.dart';
import 'screens/super_admin/super_dashboard.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/admin/map_view.dart';        // ← NEW

final Map<String, WidgetBuilder> appRoutes = {
  '/login':    (_) => const LoginPage(),
  '/master':   (_) => const MasterDashboard(),
  '/super':    (_) => const SuperDashboard(),
  '/admin':    (_) => const AdminDashboard(),
  '/map-view': (_) => const MapViewPage(),   // ← NEW
};