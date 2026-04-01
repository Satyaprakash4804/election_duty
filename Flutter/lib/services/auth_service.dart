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

    // 🔥 SAVE TOKEN
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        AppConstants.tokenKey, response["data"]["token"]);

    return response;
  }

  // 🔹 GET TOKEN
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.tokenKey);
  }

  // 🔹 LOGOUT
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.tokenKey);
  }

  // 🔹 CHECK LOGIN
  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null;
  }
}