import 'package:flutter/material.dart';
import 'routes.dart';
import 'core/theme.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Election Duty App",
      theme: appTheme,
      initialRoute: "/login",
      routes: appRoutes,
    );
  }
}