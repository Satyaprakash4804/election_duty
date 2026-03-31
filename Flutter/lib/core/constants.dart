class AppConstants {
  // 🔥 BASE URL (change when deploying)
  static const String baseUrl = "http://192.168.1.14:5000/api";

  // 🔐 AUTH
  static const String login = "$baseUrl/login";

  // 🔑 TOKEN KEY (for storage)
  static const String tokenKey = "AUTH_TOKEN";

  // 👤 ROLES
  static const String roleMaster = "master";
  static const String roleSuperAdmin = "super_admin";
  static const String roleAdmin = "admin";
  static const String roleUser = "user";
}