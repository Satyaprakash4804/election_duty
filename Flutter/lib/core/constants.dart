class AppConstants {
  // 🔥 BASE URL (change when deploying)
  static const String baseUrl = "http://192.168.1.11:5000/api";

  // 🔐 AUTH
  static const String login = "$baseUrl/login";

  // 🔑 TOKEN KEY (for storage)
  static const String tokenKey = "AUTH_TOKEN";

  // 👤 ROLES
  static const String roleMaster = "MASTER";
  static const String roleSuperAdmin = "SUPER_ADMIN";
  static const String roleAdmin = "ADMIN";
  static const String roleUser = "STAFF";  
}