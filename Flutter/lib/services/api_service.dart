import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import 'auth_service.dart';

class ApiService {
  // 🔹 COMMON HEADERS
  static Map<String, String> _headers({String? token}) {
    return {
      "Content-Type": "application/json",
      if (token != null) "Authorization": "Bearer $token",
    };
  }

  // 🔹 GET REQUEST
  static Future<dynamic> get(String endpoint, {String? token}) async {
    final url = Uri.parse("${AppConstants.baseUrl}$endpoint");

    print("🌐 GET: $url");
    print("🔑 TOKEN: $token");

    final response = await http.get(
      url,
      headers: _headers(token: token),
    );

    return _handleResponse(response);
  }

  // 🔹 POST REQUEST
  static Future<dynamic> post(String endpoint, Map data,
      {String? token}) async {
    final url = Uri.parse("${AppConstants.baseUrl}$endpoint");

    print("🌐 POST: $url");
    print("📦 BODY: $data");

    final response = await http.post(
      url,
      headers: _headers(token: token),
      body: jsonEncode(data),
    );

    return _handleResponse(response);
  }

  // 🔹 PUT REQUEST
  static Future<dynamic> put(String endpoint, Map data,
      {String? token}) async {
    final url = Uri.parse("${AppConstants.baseUrl}$endpoint");

    print("🌐 PUT: $url");

    final response = await http.put(
      url,
      headers: _headers(token: token),
      body: jsonEncode(data),
    );

    return _handleResponse(response);
  }

  // 🔹 DELETE REQUEST
  static Future<dynamic> delete(String endpoint, {String? token}) async {
    final url = Uri.parse("${AppConstants.baseUrl}$endpoint");

    print("🌐 DELETE: $url");

    final response = await http.delete(
      url,
      headers: _headers(token: token),
    );

    return _handleResponse(response);
  }

  // 🔥 SAFE RESPONSE HANDLER (FIXED)
  static dynamic _handleResponse(http.Response response) {
    final raw = response.body;

    print("📡 STATUS: ${response.statusCode}");
    print("📨 RAW RESPONSE: $raw");

    // 🚨 FIX 1: Handle HTML response (main bug you had)
    if (raw.startsWith("<!DOCTYPE") || raw.startsWith("<html")) {
      throw Exception(
          "❌ Server returned HTML (Check API URL or Token)");
    }

    // 🚨 FIX 2: Handle empty response
    if (raw.isEmpty) {
      throw Exception("❌ Empty response from server");
    }

    final body = jsonDecode(raw);

    // ✅ SUCCESS
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    // 🔐 AUTO LOGOUT ON 401
    if (response.statusCode == 401) {
      AuthService.logout();
      throw Exception("Session expired. Please login again.");
    }

    // ❌ OTHER ERRORS
    throw Exception(body["message"] ?? "API Error");
  }
}