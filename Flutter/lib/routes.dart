import 'package:flutter/material.dart';
import 'screens/auth/login_page.dart';
import 'screens/master_admin/master_dashboard.dart';
import 'screens/super_admin/super_dashboard.dart';
import 'screens/admin/admin_dashboard.dart';

final Map<String, WidgetBuilder> appRoutes = {
  "/login": (_) => LoginPage(),
  "/master": (_) => MasterDashboard(),
  "/super": (_) => SuperDashboard(),
  "/admin": (_) => AdminDashboard(),
};