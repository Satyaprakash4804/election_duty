import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import '../models/user_model.dart';
import '../models/staff_model.dart';
import 'auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ApiException
//  Carries structured error info from the backend.
// ─────────────────────────────────────────────────────────────────────────────
class ApiException implements Exception {
  final int     statusCode;
  final String  message;
  final String? errorCode;
  final dynamic body;

  const ApiException({
    required this.statusCode,
    required this.message,
    this.errorCode,
    this.body,
  });

  // ── Election-guard checks ─────────────────────────────────────────────────
  bool get isNoActiveElection => errorCode == 'NO_ACTIVE_ELECTION_CONFIG';
  bool get isElectionFinalized => errorCode == 'ELECTION_FINALIZED';

  /// True when any duty mutation was blocked by the election guard middleware.
  bool get isElectionBlock => isNoActiveElection || isElectionFinalized;

  // ── Convenience checks ────────────────────────────────────────────────────
  bool get isNotFound     => statusCode == 404;
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden    => statusCode == 403;
  bool get isConflict     => statusCode == 409;
  bool get isServerError  => statusCode >= 500;

  // ── User-friendly Hindi messages ──────────────────────────────────────────
  String get friendlyMessage {
    if (isNoActiveElection) {
      return 'इस जनपद के लिए कोई सक्रिय चुनाव कॉन्फ़िगरेशन नहीं है।\n'
             'कृपया master से चुनाव कॉन्फ़िगर करवाएं।';
    }
    if (isElectionFinalized) {
      return 'पिछला चुनाव तिथि के पश्चात स्वतः इतिहास में स्थानांतरित हो चुका है।\n'
             'नई ड्यूटी आवंटन के लिए master से नया चुनाव कॉन्फ़िगर करवाएं।';
    }
    return message;
  }

  String get friendlyTitle {
    if (isNoActiveElection)  return 'सक्रिय चुनाव नहीं है';
    if (isElectionFinalized) return 'चुनाव समाप्त हो चुका है';
    if (isNotFound)          return 'डेटा नहीं मिला';
    if (isForbidden)         return 'अनुमति नहीं है';
    if (isServerError)       return 'सर्वर त्रुटि';
    return 'त्रुटि';
  }

  @override
  String toString() =>
      'ApiException($statusCode${errorCode != null ? "/$errorCode" : ""}): $message';
}

// ─────────────────────────────────────────────────────────────────────────────
//  ApiService
// ─────────────────────────────────────────────────────────────────────────────
class ApiService {
  static String? activeDistrict;

  // ── Timeout config ────────────────────────────────────────────────────────
  static const _defaultTimeout = Duration(seconds: 20);
  static const _uploadTimeout  = Duration(seconds: 60);
  static const _reportTimeout  = Duration(seconds: 30);

  // ── Common headers ────────────────────────────────────────────────────────
  //
  // FIX: HTTP headers must only contain ASCII characters (RFC 7230).
  // Hindi/Devanagari district names like "बागपत" are non-ASCII and cause:
  //   "Invalid HTTP header field value: "बागपत" (at character 1)"
  //
  // Solution: URI-encode the district name so it becomes pure ASCII
  // (e.g. "बागपत" → "%E0%A4%AC%E0%A4%BE%E0%A4%97%E0%A4%AA%E0%A4%A4").
  // The backend decodes it with urllib.parse.unquote() before use.
  //
  static Future<Map<String, String>> _headers({String? token}) async {
    final t = token ?? await AuthService.getToken();

    // URI-encode the district to make it ASCII-safe for HTTP headers.
    // Uri.encodeComponent converts every non-ASCII/non-unreserved byte.
    final encodedDistrict = (activeDistrict != null && activeDistrict!.isNotEmpty)
        ? Uri.encodeComponent(activeDistrict!)
        : null;

    return {
      'Content-Type': 'application/json',
      'Accept':       'application/json',
      if (t != null)                'Authorization':     'Bearer $t',
      if (encodedDistrict != null)  'X-Active-District': encodedDistrict,
    };
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  CORE HTTP METHODS
  // ══════════════════════════════════════════════════════════════════════════

  static Future<dynamic> get(
    String endpoint, {
    String? token,
    Duration? timeout,
  }) async {
    final url = Uri.parse('${AppConstants.baseUrl}$endpoint');
    try {
      final response = await http
          .get(url, headers: await _headers(token: token))
          .timeout(timeout ?? _defaultTimeout);
      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw Exception('GET Error [$endpoint]: $e');
    }
  }

  static Future<dynamic> post(
    String endpoint,
    Map<String, dynamic> data, {
    String? token,
    Duration? timeout,
  }) async {
    final url = Uri.parse('${AppConstants.baseUrl}$endpoint');
    try {
      final response = await http
          .post(url,
              headers: await _headers(token: token),
              body: jsonEncode(data))
          .timeout(timeout ?? _defaultTimeout);
      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw Exception('POST Error [$endpoint]: $e');
    }
  }

  static Future<dynamic> put(
    String endpoint,
    Map<String, dynamic> data, {
    String? token,
    Duration? timeout,
  }) async {
    final url = Uri.parse('${AppConstants.baseUrl}$endpoint');
    try {
      final response = await http
          .put(url,
              headers: await _headers(token: token),
              body: jsonEncode(data))
          .timeout(timeout ?? _defaultTimeout);
      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw Exception('PUT Error [$endpoint]: $e');
    }
  }

  static Future<dynamic> patch(
    String endpoint,
    Map<String, dynamic> data, {
    String? token,
    Duration? timeout,
  }) async {
    final url = Uri.parse('${AppConstants.baseUrl}$endpoint');
    try {
      final response = await http
          .patch(url,
              headers: await _headers(token: token),
              body: jsonEncode(data))
          .timeout(timeout ?? _defaultTimeout);
      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw Exception('PATCH Error [$endpoint]: $e');
    }
  }

  static Future<dynamic> delete(
    String endpoint, {
    String? token,
    Map<String, dynamic>? body,
    Duration? timeout,
  }) async {
    final url = Uri.parse('${AppConstants.baseUrl}$endpoint');
    try {
      final response = await http
          .delete(
            url,
            headers: await _headers(token: token),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeout ?? _defaultTimeout);
      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw Exception('DELETE Error [$endpoint]: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  RESPONSE HANDLER
  // ══════════════════════════════════════════════════════════════════════════

  static dynamic _handleResponse(http.Response response) {
    final raw = response.body;

    if (raw.startsWith('<!DOCTYPE') || raw.startsWith('<html')) {
      throw Exception('❌ Server returned HTML — check API URL / server status');
    }
    if (raw.isEmpty) {
      throw Exception('❌ Empty response from server (${response.statusCode})');
    }

    dynamic body;
    try {
      body = jsonDecode(raw);
    } catch (_) {
      throw Exception('❌ Invalid JSON response from server');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    if (response.statusCode == 401) {
      AuthService.logout();
      throw ApiException(
        statusCode: 401,
        message:    'सत्र समाप्त हो गया। कृपया पुनः लॉगिन करें।',
        errorCode:  'SESSION_EXPIRED',
        body:       body,
      );
    }

    if (response.statusCode >= 400 && response.statusCode < 500) {
      String? code;
      String  msg = 'API Error (${response.statusCode})';
      if (body is Map) {
        code = body['errorCode']?.toString();
        msg  = body['message']?.toString() ?? msg;
      }
      throw ApiException(
        statusCode: response.statusCode,
        message:    msg,
        errorCode:  code,
        body:       body,
      );
    }

    if (response.statusCode >= 500) {
      final msg = body is Map
          ? (body['message']?.toString() ?? 'Internal Server Error')
          : 'Internal Server Error';
      throw ApiException(
        statusCode: response.statusCode,
        message:    msg,
        body:       body,
      );
    }

    throw Exception(
        body is Map ? (body['message'] ?? 'Unknown API Error') : 'Unknown API Error');
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ❶  ELECTION STATUS & CONFIG
  // ══════════════════════════════════════════════════════════════════════════

  static Future<ActiveElectionStatus> getActiveElectionStatus({
    String? token,
  }) async {
    final res = await get('/admin/election/finalize/status');
    return ActiveElectionStatus.fromJson(res as Map<String, dynamic>);
  }

  static Future<List<Map<String, dynamic>>> getElectionList({
    String? district,
    bool includeArchived = false,
  }) async {
    final role = await AuthService.getRole() ?? '';

    String endpoint;
    if (role == 'master') {
      final params = <String, String>{
        if (district != null && district.isNotEmpty) 'district': district,
        if (includeArchived) 'includeArchived': 'true',
      };
      endpoint = _buildQuery('/master/elections', params);
    } else {
      final params = <String, String>{
        if (includeArchived) 'includeArchived': 'true',
      };
      endpoint = _buildQuery('/admin/elections', params);
    }

    final res  = await get(endpoint);
    final list = (res['data'] ?? res) as List? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> getMasterElectionStatusSummary() async {
    final res  = await get('/master/elections/status-summary');
    final list = (res['data'] ?? res) as List? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  static Future<ActiveElectionStatus> getElectionStatusForDistrict(
      String district) async {
    final res = await get(
        '/master/elections/status-summary?district=${Uri.encodeComponent(district)}');
    final data = res['data'];
    if (data is List && data.isNotEmpty) {
      return ActiveElectionStatus.fromJson(
          Map<String, dynamic>.from(data.first));
    }
    return ActiveElectionStatus.fromJson(
        (data as Map<String, dynamic>?) ?? {});
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ❷  ELECTION HISTORY
  // ══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> getElectionHistoryList({
    String? district,
    int page  = 1,
    int limit = 20,
  }) async {
    final role = await AuthService.getRole() ?? '';
    final params = <String, String>{
      'page':  page.toString(),
      'limit': limit.toString(),
      if (role == 'master' && district != null && district.isNotEmpty)
        'district': district,
    };
    final base     = role == 'master' ? '/master/election/history/list'
                                      : '/admin/election/history/list';
    final endpoint = _buildQuery(base, params);
    final res      = await get(endpoint);
    return res as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getBoothDutyHistory({
    required int electionId,
    String? district,
    int page  = 1,
    int limit = 30,
    String q  = '',
  }) async {
    final params = <String, String>{
      'page':  page.toString(),
      'limit': limit.toString(),
      if (q.isNotEmpty) 'q': q,
      if (district != null && district.isNotEmpty) 'district': district,
    };
    final endpoint = _buildQuery(
        '/admin/election/history/$electionId/booth-duties', params);
    final res = await get(endpoint, timeout: _reportTimeout);
    return res as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getDistrictDutyHistory({
    required int electionId,
    String? district,
    int page  = 1,
    int limit = 30,
    String q  = '',
  }) async {
    final params = <String, String>{
      'page':  page.toString(),
      'limit': limit.toString(),
      if (q.isNotEmpty) 'q': q,
      if (district != null && district.isNotEmpty) 'district': district,
    };
    final endpoint = _buildQuery(
        '/admin/election/history/$electionId/district-duties', params);
    final res = await get(endpoint, timeout: _reportTimeout);
    return res as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getBoothRulesHistory({
    required int electionId,
    String? district,
  }) async {
    final params = <String, String>{
      if (district != null && district.isNotEmpty) 'district': district,
    };
    final endpoint = _buildQuery(
        '/admin/election/history/$electionId/booth-rules', params);
    final res = await get(endpoint);
    return res as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getDistrictRulesHistory({
    required int electionId,
    String? district,
  }) async {
    final params = <String, String>{
      if (district != null && district.isNotEmpty) 'district': district,
    };
    final endpoint = _buildQuery(
        '/admin/election/history/$electionId/district-rules', params);
    final res = await get(endpoint);
    return res as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getOfficerHistory({
    required int    electionId,
    required String level,
    String? district,
    int page  = 1,
    int limit = 30,
  }) async {
    assert(['kshetra', 'zonal', 'sector'].contains(level),
        'level must be kshetra, zonal, or sector');
    final params = <String, String>{
      'page':  page.toString(),
      'limit': limit.toString(),
      if (district != null && district.isNotEmpty) 'district': district,
    };
    final endpoint = _buildQuery(
        '/admin/election/history/$electionId/$level-officers', params);
    final res = await get(endpoint, timeout: _reportTimeout);
    return res as Map<String, dynamic>;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ❸  ELECTION FINALIZATION
  // ══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> finalizeElection({
    required int electionId,
  }) async {
    final res = await post(
      '/master/election/finalize/$electionId',
      {'confirm': true},
    );
    return res as Map<String, dynamic>;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ❹  GOSWARA / NYAY PANCHAYAT
  // ══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> getGoswara() async =>
      (await get('/admin/goswara')) as Map<String, dynamic>;

  static Future<void> saveNyayPanchayat({
    required String blockName,
    required int    nyayCount,
  }) async {
    await post('/admin/goswara/nyay-panchayat',
        {'blockName': blockName, 'nyayCount': nyayCount});
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ❺  BOOTH DUTY ASSIGNMENTS
  // ══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> assignBoothDuty({
    required int    staffId,
    required int    centerId,
    required int    electionId,
    String busNo        = '',
    String mode         = '',
    String electionDate = '',
  }) async {
    final res = await post('/admin/duty/assign', {
      'staffId':      staffId,
      'centerId':     centerId,
      'electionId':   electionId,
      if (busNo.isNotEmpty)        'busNo':        busNo,
      if (mode.isNotEmpty)         'mode':         mode,
      if (electionDate.isNotEmpty) 'electionDate': electionDate,
    });
    return res as Map<String, dynamic>;
  }

  static Future<void> removeBoothDuty({
    required int staffId,
    required int centerId,
  }) async {
    await delete('/admin/duty/remove', body: {
      'staffId':  staffId,
      'centerId': centerId,
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ❻  DISTRICT DUTY ASSIGNMENTS
  // ══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> assignDistrictDuty({
    required int    staffId,
    required String dutyType,
    required int    electionId,
    int    batchNo       = 1,
    String busNo         = '',
    String note          = '',
  }) async {
    final res = await post('/admin/district-duties/assign', {
      'staffId':    staffId,
      'dutyType':   dutyType,
      'electionId': electionId,
      'batchNo':    batchNo,
      if (busNo.isNotEmpty) 'busNo': busNo,
      if (note.isNotEmpty)  'note':  note,
    });
    return res as Map<String, dynamic>;
  }

  static Future<void> removeDistrictDuty({
    required int    staffId,
    required String dutyType,
  }) async {
    await delete('/admin/district-duties/remove', body: {
      'staffId':  staffId,
      'dutyType': dutyType,
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ❼  BOOTH MANAK (rules)
  // ══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> saveBoothRule({
    required String sensitivity,
    required int    boothCount,
    required int    electionId,
    required Map<String, dynamic> counts,
  }) async {
    final res = await post('/admin/booth-rules', {
      'sensitivity': sensitivity,
      'boothCount':  boothCount,
      'electionId':  electionId,
      ...counts,
    });
    return res as Map<String, dynamic>;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ❽  DISTRICT MANAK (rules)
  // ══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> saveDistrictRule({
    required String dutyType,
    required String dutyLabelHi,
    required int    sankhya,
    required int    electionId,
    required Map<String, dynamic> counts,
    int    sortOrder = 0,
  }) async {
    final res = await post('/admin/district-rules', {
      'dutyType':   dutyType,
      'dutyLabelHi':dutyLabelHi,
      'sankhya':    sankhya,
      'electionId': electionId,
      'sortOrder':  sortOrder,
      ...counts,
    });
    return res as Map<String, dynamic>;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ❾  OFFICER ASSIGNMENTS
  // ══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> assignKshetraOfficer({
    required int    superZoneId,
    required int    userId,
    required int    electionId,
    String name     = '',
    String pno      = '',
    String mobile   = '',
    String userRank = '',
  }) async {
    final res = await post('/admin/kshetra-officers', {
      'superZoneId': superZoneId,
      'userId':      userId,
      'electionId':  electionId,
      if (name.isNotEmpty)     'name':     name,
      if (pno.isNotEmpty)      'pno':      pno,
      if (mobile.isNotEmpty)   'mobile':   mobile,
      if (userRank.isNotEmpty) 'userRank': userRank,
    });
    return res as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> assignZonalOfficer({
    required int    zoneId,
    required int    userId,
    required int    electionId,
    String name     = '',
    String pno      = '',
    String mobile   = '',
    String userRank = '',
  }) async {
    final res = await post('/admin/zonal-officers', {
      'zoneId':     zoneId,
      'userId':     userId,
      'electionId': electionId,
      if (name.isNotEmpty)     'name':     name,
      if (pno.isNotEmpty)      'pno':      pno,
      if (mobile.isNotEmpty)   'mobile':   mobile,
      if (userRank.isNotEmpty) 'userRank': userRank,
    });
    return res as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> assignSectorOfficer({
    required int    sectorId,
    required int    userId,
    required int    electionId,
    String name     = '',
    String pno      = '',
    String mobile   = '',
    String userRank = '',
  }) async {
    final res = await post('/admin/sector-officers', {
      'sectorId':   sectorId,
      'userId':     userId,
      'electionId': electionId,
      if (name.isNotEmpty)     'name':     name,
      if (pno.isNotEmpty)      'pno':      pno,
      if (mobile.isNotEmpty)   'mobile':   mobile,
      if (userRank.isNotEmpty) 'userRank': userRank,
    });
    return res as Map<String, dynamic>;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ❿  UTILITY
  // ══════════════════════════════════════════════════════════════════════════

  static String _buildQuery(String path, Map<String, String> params) {
    if (params.isEmpty) return path;
    final q = params.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}'
                    '=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$path?$q';
  }
}


// ═════════════════════════════════════════════════════════════════════════════
//  showApiError
// ═════════════════════════════════════════════════════════════════════════════
Future<bool> showApiError(
  BuildContext context,
  Object e, {
  VoidCallback? onElectionBlockDismissed,
}) async {
  if (!context.mounted) return false;

  if (e is ApiException && e.isElectionBlock) {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ElectionBlockDialog(error: e),
    );
    onElectionBlockDismissed?.call();
    return true;
  }

  String msg;
  if (e is ApiException) {
    msg = e.friendlyMessage;
  } else {
    final s = e.toString();
    msg = s.contains('Exception:') ? s.split('Exception:').last.trim() : s;
  }
  if (!context.mounted) return false;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: const Color(0xFFDC2626),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 4),
    ));
  return false;
}


// ═════════════════════════════════════════════════════════════════════════════
//  handleElectionGuard
// ═════════════════════════════════════════════════════════════════════════════
Future<bool> handleElectionGuard(
  BuildContext context,
  Future<void> Function() action, {
  VoidCallback? onElectionBlockDismissed,
}) async {
  try {
    await action();
    return true;
  } on ApiException catch (e) {
    if (e.isElectionBlock) {
      await showApiError(
        context, e,
        onElectionBlockDismissed: onElectionBlockDismissed,
      );
      return false;
    }
    rethrow;
  }
}


// ═════════════════════════════════════════════════════════════════════════════
//  _ElectionBlockDialog
// ═════════════════════════════════════════════════════════════════════════════
class _ElectionBlockDialog extends StatelessWidget {
  final ApiException error;
  const _ElectionBlockDialog({required this.error});

  @override
  Widget build(BuildContext context) {
    final isFinalized = error.isElectionFinalized;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: const Color(0xFFFFF8F8),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      title: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFDC2626).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isFinalized
                ? Icons.event_busy_rounded
                : Icons.event_repeat_outlined,
            color: const Color(0xFFDC2626),
            size: 22,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            error.friendlyTitle,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 20),
          Text(
            error.friendlyMessage,
            style: const TextStyle(
              height: 1.6,
              fontSize: 14,
              color: Color(0xFF444444),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3CD),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD4A843).withOpacity(0.5)),
            ),
            child: Row(children: const [
              Icon(Icons.info_outline, size: 14, color: Color(0xFF856404)),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'यह नियंत्रण master admin के पास है।',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF856404),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFDC2626),
            backgroundColor: const Color(0xFFDC2626).withOpacity(0.08),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text(
            'ठीक है',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
      ],
    );
  }
}