import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import 'api_service.dart';

class AuthService {

  // 🔹 LOGIN
  static Future<Map<String, dynamic>> login(
      String id, String password) async {

    final response = await ApiService.post(
      "/login",
      {
        "pno": id,
        "password": password,
      },
    );

    final prefs = await SharedPreferences.getInstance();

    // ✅ SAVE TOKEN
    await prefs.setString(
      AppConstants.tokenKey,
      response["data"]["token"],
    );

    // ✅ SAVE ROLE
    await prefs.setString(
      "role",
      response["data"]["user"]["role"],
    );

    // 🔥 NEW: SAVE FULL USER DATA
    await prefs.setString(
      "user",
      jsonEncode(response["data"]["user"]),
    );

    return response;
  }

  // 🔹 GET TOKEN
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.tokenKey);
  }

  // 🔹 GET ROLE
  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("role");
  }

  // 🔥 NEW: GET USER
  static Future<Map<String, dynamic>?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userStr = prefs.getString("user");

    if (userStr == null) return null;

    return jsonDecode(userStr);
  }

  // 🔹 LOGOUT
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  // 🔹 CHECK LOGIN
  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null;
  }
}