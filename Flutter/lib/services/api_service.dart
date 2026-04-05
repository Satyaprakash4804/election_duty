import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import 'auth_service.dart';

class ApiService {

  // 🔹 COMMON HEADERS
  static Future<Map<String, String>> _headers({String? token}) async {
    final t = token ?? await AuthService.getToken();

    return {
      "Content-Type": "application/json",
      if (t != null) "Authorization": "Bearer $t",
    };
  }

  // 🔹 GET REQUEST
  static Future<dynamic> get(String endpoint, {String? token}) async {
    final url = Uri.parse("${AppConstants.baseUrl}$endpoint");

    print("🌐 GET: $url");

    try {
      final response = await http
          .get(url, headers: await _headers(token: token))
          .timeout(const Duration(seconds: 20));

      return _handleResponse(response);
    } catch (e) {
      throw Exception("GET Error: $e");
    }
  }

  // 🔹 POST REQUEST
  static Future<dynamic> post(String endpoint, Map data,
      {String? token}) async {
    final url = Uri.parse("${AppConstants.baseUrl}$endpoint");

    print("🌐 POST: $url");
    print("📦 BODY: $data");

    try {
      final response = await http
          .post(
            url,
            headers: await _headers(token: token),
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 20));

      return _handleResponse(response);
    } catch (e) {
      throw Exception("POST Error: $e");
    }
  }

  // 🔹 PUT REQUEST
  static Future<dynamic> put(String endpoint, Map data,
      {String? token}) async {
    final url = Uri.parse("${AppConstants.baseUrl}$endpoint");

    print("🌐 PUT: $url");

    try {
      final response = await http
          .put(
            url,
            headers: await _headers(token: token),
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 20));

      return _handleResponse(response);
    } catch (e) {
      throw Exception("PUT Error: $e");
    }
  }

  // 🔹 DELETE REQUEST
  static Future<dynamic> delete(String endpoint, {String? token}) async {
    final url = Uri.parse("${AppConstants.baseUrl}$endpoint");

    print("🌐 DELETE: $url");

    try {
      final response = await http
          .delete(url, headers: await _headers(token: token))
          .timeout(const Duration(seconds: 20));

      return _handleResponse(response);
    } catch (e) {
      throw Exception("DELETE Error: $e");
    }
  }

  // 🔥 RESPONSE HANDLER (ADVANCED)
  static dynamic _handleResponse(http.Response response) {
    final raw = response.body;

    print("📡 STATUS: ${response.statusCode}");
    print("📨 RESPONSE: $raw");

    // 🚨 HTML ERROR (wrong URL / backend down)
    if (raw.startsWith("<!DOCTYPE") || raw.startsWith("<html")) {
      throw Exception("❌ Server returned HTML (Check API URL / Server)");
    }

    // 🚨 EMPTY RESPONSE
    if (raw.isEmpty) {
      throw Exception("❌ Empty response from server");
    }

    dynamic body;
    try {
      body = jsonDecode(raw);
    } catch (e) {
      throw Exception("❌ Invalid JSON response");
    }

    // ✅ SUCCESS
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    // 🔐 UNAUTHORIZED → AUTO LOGOUT
    if (response.statusCode == 401) {
      AuthService.logout();
      throw Exception("🔐 Session expired. Please login again.");
    }

    // ❌ SERVER ERROR
    if (response.statusCode >= 500) {
      throw Exception("🔥 Server error (${response.statusCode})");
    }

    // ❌ CLIENT ERROR
    throw Exception(body["message"] ?? "❌ API Error");
  }
}