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
  static Future<dynamic> post(String endpoint, Map<String, dynamic> data,
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
  static Future<dynamic> put(String endpoint, Map<String, dynamic> data,
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

  // 🔹 PATCH REQUEST
  static Future<dynamic> patch(String endpoint, Map<String, dynamic> data,
      {String? token}) async {
    final url = Uri.parse("${AppConstants.baseUrl}$endpoint");

    print("🌐 PATCH: $url");
    print("📦 BODY: $data");

    try {
      final response = await http
          .patch(
            url,
            headers: await _headers(token: token),
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 20));

      return _handleResponse(response);
    } catch (e) {
      throw Exception("PATCH Error: $e");
    }
  }

  // ✅ FINAL DELETE METHOD (ONLY ONE)
  static Future<dynamic> delete(
    String endpoint, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    final url = Uri.parse("${AppConstants.baseUrl}$endpoint");

    print("🌐 DELETE: $url");

    try {
      final response = await http.delete(
        url,
        headers: await _headers(token: token),
        body: body != null ? jsonEncode(body) : null,
      ).timeout(const Duration(seconds: 20));

      return _handleResponse(response);
    } catch (e) {
      throw Exception("DELETE Error: $e");
    }
  }

  // 🔥 RESPONSE HANDLER
  static dynamic _handleResponse(http.Response response) {
    final raw = response.body;

    print("📡 STATUS: ${response.statusCode}");
    print("📨 RESPONSE: $raw");

    if (raw.startsWith("<!DOCTYPE") || raw.startsWith("<html")) {
      throw Exception("❌ Server returned HTML (Check API URL / Server)");
    }

    if (raw.isEmpty) {
      throw Exception("❌ Empty response from server");
    }

    dynamic body;
    try {
      body = jsonDecode(raw);
    } catch (e) {
      throw Exception("❌ Invalid JSON response");
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    if (response.statusCode == 401) {
      AuthService.logout();
      throw Exception("🔐 Session expired. Please login again.");
    }

    if (response.statusCode >= 500) {
      throw Exception("🔥 Server error (${response.statusCode})");
    }

    throw Exception(body["message"] ?? "❌ API Error");
  }

  static Future<Map<String, dynamic>> getGoswara() async {
    final token = await AuthService.getToken();
    return await get('/admin/goswara', token: token);
  }

  static Future<void> saveNyayPanchayat({
    required String blockName,
    required int nyayCount,
  }) async {
    final token = await AuthService.getToken();
    await post(
      '/admin/goswara/nyay-panchayat',
      {'blockName': blockName, 'nyayCount': nyayCount},
      token: token,
    );
  }
}