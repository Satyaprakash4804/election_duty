import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import 'auth_service.dart'; // 🔥 IMPORTANT

class ApiService {
  static Map<String, String> _headers({String? token}) {
    return {
      "Content-Type": "application/json",
      if (token != null) "Authorization": "Bearer $token",
    };
  }

  // 🔹 GET REQUEST
  static Future<dynamic> get(String endpoint, {String? token}) async {
    final response = await http.get(
      Uri.parse("${AppConstants.baseUrl}$endpoint"),
      headers: _headers(token: token),
    );

    return _handleResponse(response);
  }

  // 🔹 POST REQUEST
  static Future<dynamic> post(String endpoint, Map data,
      {String? token}) async {
    final response = await http.post(
      Uri.parse("${AppConstants.baseUrl}$endpoint"),
      headers: _headers(token: token),
      body: jsonEncode(data),
    );

    return _handleResponse(response);
  }

  // 🔹 PUT REQUEST
  static Future<dynamic> put(String endpoint, Map data,
      {String? token}) async {
    final response = await http.put(
      Uri.parse("${AppConstants.baseUrl}$endpoint"),
      headers: _headers(token: token),
      body: jsonEncode(data),
    );

    return _handleResponse(response);
  }

  // 🔹 DELETE REQUEST
  static Future<dynamic> delete(String endpoint, {String? token}) async {
    final response = await http.delete(
      Uri.parse("${AppConstants.baseUrl}$endpoint"),
      headers: _headers(token: token),
    );

    return _handleResponse(response);
  }

  // 🔥 COMMON RESPONSE HANDLER (UPDATED)
  static dynamic _handleResponse(http.Response response) {
    final body = jsonDecode(response.body);

    // ✅ SUCCESS
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    // 🔥 AUTO LOGOUT ON 401
    if (response.statusCode == 401) {
      AuthService.logout(); // clear token
      throw Exception("Session expired");
    }

    // ❌ OTHER ERRORS
    throw Exception(body["message"] ?? "API Error");
  }
}