import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as ex;
import 'package:http/http.dart' as http;
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../core/constants.dart';
import '../core/widgets.dart';

// ── palette ───────────────────────────────────────────────────────────────────
const _kBg      = Color(0xFFFDF6E3);
const _kSurface = Color(0xFFF5E6C8);
const _kPrimary = Color(0xFF8B6914);
const _kAccent  = Color(0xFFB8860B);
const _kDark    = Color(0xFF4A3000);
const _kSubtle  = Color(0xFFAA8844);
const _kBorder  = Color(0xFFD4A843);
const _kError   = Color(0xFFC0392B);
const _kSuccess = Color(0xFF2D6A1E);
const _kInfo    = Color(0xFF1A5276);

const _pageSize = 50;

class StaffPage extends StatefulWidget {
  const StaffPage({super.key});
  @override
  State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  final List<Map> _assigned = [];
  int  _assignedPage        = 1;
  int  _assignedTotal       = 0;
  bool _assignedLoading     = false;
  bool _assignedHasMore     = true;
  final ScrollController _assignedScroll = ScrollController();

  final List<Map> _reserve  = [];
  int  _reservePage         = 1;
  int  _reserveTotal        = 0;
  bool _reserveLoading      = false;
  bool _reserveHasMore      = true;
  final ScrollController _reserveScroll = ScrollController();

  String _q = '';
  Timer? _debounce;
  final _searchCtrl = TextEditingController();

  // Excel button loading state
  bool _excelLoading = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)
      ..addListener(() { if (!_tabs.indexIsChanging) setState(() {}); });
    _assignedScroll.addListener(_onAssignedScroll);
    _reserveScroll.addListener(_onReserveScroll);
    _searchCtrl.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 350), () {
        final q = _searchCtrl.text.trim();
        if (q != _q) { _q = q; _refresh(); }
      });
    });
    _refresh();
  }

  void _onAssignedScroll() {
    if (_assignedScroll.position.pixels >= _assignedScroll.position.maxScrollExtent - 300) _loadAssigned();
  }
  void _onReserveScroll() {
    if (_reserveScroll.position.pixels >= _reserveScroll.position.maxScrollExtent - 300) _loadReserve();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _assignedScroll.removeListener(_onAssignedScroll);
    _reserveScroll.removeListener(_onReserveScroll);
    _assignedScroll.dispose();
    _reserveScroll.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _assigned.clear(); _assignedPage = 1; _assignedHasMore = true;
      _reserve.clear();  _reservePage  = 1; _reserveHasMore  = true;
    });
    _loadAssigned(reset: true);
    _loadReserve(reset: true);
  }

  Future<void> _loadAssigned({bool reset = false}) async {
    if (_assignedLoading || (!_assignedHasMore && !reset)) return;
    if (reset) {
      if (mounted) setState(() { _assigned.clear(); _assignedPage = 1; _assignedHasMore = true; });
    }
    if (mounted) setState(() => _assignedLoading = true);
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.get(
        '/admin/staff?assigned=yes&page=$_assignedPage&limit=$_pageSize&q=${Uri.encodeComponent(_q)}',
        token: token,
      );
      final wrapper = (res['data'] as Map<String, dynamic>?) ?? {};
      final items   = (wrapper['data'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      final total   = (wrapper['total']      as num?)?.toInt() ?? 0;
      final pages   = (wrapper['totalPages'] as num?)?.toInt() ?? 1;
      if (!mounted) return;
      setState(() {
        _assigned.addAll(items);
        _assignedTotal   = total;
        _assignedHasMore = _assignedPage < pages;
        _assignedPage++;
        _assignedLoading = false;
      });
    } catch (e) {
      if (mounted) { setState(() => _assignedLoading = false); _snack(_msg(e), error: true); }
    }
  }

  Future<void> _loadReserve({bool reset = false}) async {
    if (_reserveLoading || (!_reserveHasMore && !reset)) return;
    if (reset) {
      if (mounted) setState(() { _reserve.clear(); _reservePage = 1; _reserveHasMore = true; });
    }
    if (mounted) setState(() => _reserveLoading = true);
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.get(
        '/admin/staff?assigned=no&page=$_reservePage&limit=$_pageSize&q=${Uri.encodeComponent(_q)}',
        token: token,
      );
      final wrapper = (res['data'] as Map<String, dynamic>?) ?? {};
      final items   = (wrapper['data'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      final total   = (wrapper['total']      as num?)?.toInt() ?? 0;
      final pages   = (wrapper['totalPages'] as num?)?.toInt() ?? 1;
      if (!mounted) return;
      setState(() {
        _reserve.addAll(items);
        _reserveTotal   = total;
        _reserveHasMore = _reservePage < pages;
        _reservePage++;
        _reserveLoading = false;
      });
    } catch (e) {
      if (mounted) { setState(() => _reserveLoading = false); _snack(_msg(e), error: true); }
    }
  }

  String _v(dynamic v)  => (v ?? '').toString().trim();
  String _msg(Object e) {
    final s = e.toString();
    return s.contains('Exception:') ? s.split('Exception:').last.trim() : s;
  }
  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? _kError : _kSuccess,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _deleteStaff(Map s) async {
    final ok = await _confirmDialog(title: 'स्टाफ हटाएं', content: '"${_v(s['name'])}" को स्थायी रूप से हटाएं?\nयह वापस नहीं होगा।', confirmText: 'हटाएं');
    if (ok != true) return;
    try {
      final token = await AuthService.getToken();
      await ApiService.delete('/admin/staff/${s['id']}', token: token);
      _snack('${_v(s['name'])} हटाया गया');
      _refresh();
    } catch (e) { _snack(_msg(e), error: true); }
  }

  Future<void> _removeDuty(Map s) async {
    final ok = await _confirmDialog(title: 'ड्यूटी हटाएं', content: '"${_v(s['name'])}" को ${_v(s['centerName'])} से हटाकर रिज़र्व में करें?', confirmText: 'रिज़र्व करें');
    if (ok != true) return;
    try {
      final token = await AuthService.getToken();
      final dutyId = s['dutyId'];
      if (dutyId != null) {
        await ApiService.delete('/admin/duties/$dutyId', token: token);
      } else {
        await ApiService.delete('/admin/staff/${s['id']}/duty', token: token);
      }
      _snack('${_v(s['name'])} रिज़र्व में भेजा गया');
      _refresh();
    } catch (e) { _snack(_msg(e), error: true); }
  }

  Future<bool?> _confirmDialog({required String title, required String content, required String confirmText}) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _kBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _kError, width: 1.2)),
          title: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: _kError, size: 20), const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(color: _kError, fontWeight: FontWeight.w800, fontSize: 15))),
          ]),
          content: Text(content, style: const TextStyle(color: _kDark, fontSize: 13, height: 1.5)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('रद्द', style: TextStyle(color: _kSubtle))),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: _kError, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: Text(confirmText)),
          ],
        ),
      );

  // ══════════════════════════════════════════════════════════════════════════
  //  BULK PROGRESS DIALOG — 3-phase: parse → hash → insert
  // ══════════════════════════════════════════════════════════════════════════

  void _showBulkProgressDialog({
    required BuildContext context,
    required List<Map<String, dynamic>> toUpload,
    required void Function(int added, int skipped) onComplete,
    required void Function(String msg) onError,
  }) {
    int    _phaseIdx  = 0;   // 0=parse 1=hash 2=insert 3=done -1=error
    double _parsePct  = 0;
    double _hashPct   = 0;
    double _insertPct = 0;
    int    _added     = 0;
    int    _total     = toUpload.length;
    String _statusMsg = 'तैयार हो रहा है...';
    bool   _started   = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => StatefulBuilder(builder: (dCtx, dss) {
        if (!_started) {
          _started = true;
          Future.microtask(() async {
            // Animate parse bar quickly (data already in memory)
            for (int i = 1; i <= 10; i++) {
              await Future.delayed(const Duration(milliseconds: 30));
              if (!dCtx.mounted) return;
              dss(() { _parsePct = i / 10.0; _statusMsg = 'Excel तैयार — ${toUpload.length} rows'; });
            }
            if (!dCtx.mounted) return;
            dss(() { _phaseIdx = 1; _statusMsg = 'सर्वर पर भेज रहे हैं...'; });

            http.Client? client;
            try {
              final token = await AuthService.getToken();
              final uri   = Uri.parse('${AppConstants.baseUrl}/admin/staff/bulk');
              final req   = http.Request('POST', uri);
              req.headers['Content-Type']  = 'application/json';
              req.headers['Accept']        = 'text/event-stream';
              req.headers['Cache-Control'] = 'no-cache';
              if (token != null) req.headers['Authorization'] = 'Bearer $token';
              req.body = jsonEncode({'staff': toUpload});

              client = http.Client();
              final resp = await client.send(req);
              if (resp.statusCode != 200) throw Exception('Server error ${resp.statusCode}');

              // Line-buffer to handle partial SSE chunks
              String lineBuf = '';
              await for (final raw in resp.stream.transform(utf8.decoder)) {
                lineBuf += raw;
                while (lineBuf.contains('\n')) {
                  final idx  = lineBuf.indexOf('\n');
                  final line = lineBuf.substring(0, idx).trim();
                  lineBuf    = lineBuf.substring(idx + 1);
                  if (!line.startsWith('data:')) continue;
                  final js = line.substring(5).trim();
                  if (js.isEmpty) continue;
                  Map<String, dynamic> data;
                  try { data = jsonDecode(js) as Map<String, dynamic>; } catch (_) { continue; }
                  if (!dCtx.mounted) { client.close(); return; }

                  dss(() {
                    final phase = data['phase'] as String? ?? '';
                    final pct   = (data['pct']  as num?)?.toDouble() ?? 0;

                    if (phase == 'parse') {
                      _parsePct  = (pct / 100.0).clamp(0.0, 1.0);
                      _phaseIdx  = 0;
                      _statusMsg = data['msg'] as String? ?? 'जांच हो रही है...';

                    } else if (phase == 'hash') {
                      _parsePct  = 1.0;
                      _phaseIdx  = 1;
                      // Backend emits pct 25–55 for hash phase
                      _hashPct   = ((pct - 25.0) / 30.0).clamp(0.0, 1.0);
                      _statusMsg = data['msg'] as String? ?? 'Password hash हो रही है...';

                    } else if (phase == 'insert') {
                      _parsePct  = 1.0;
                      _hashPct   = 1.0;
                      _phaseIdx  = 2;
                      _added     = (data['added'] as num?)?.toInt() ?? 0;
                      _total     = (data['total'] as num?)?.toInt() ?? _total;
                      // Backend emits pct 55–98 for insert phase
                      _insertPct = ((pct - 55.0) / 43.0).clamp(0.0, 1.0);
                      _statusMsg = '$_added / $_total rows डाले गए';

                    } else if (phase == 'done') {
                      _added     = (data['added'] as num?)?.toInt() ?? 0;
                      _parsePct  = 1.0; _hashPct = 1.0; _insertPct = 1.0;
                      _phaseIdx  = 3;
                      _statusMsg = '$_added rows सफलतापूर्वक जोड़े गए!';
                      final sk   = (data['skipped'] as List?)?.length ?? 0;
                      Future.delayed(const Duration(milliseconds: 800), () {
                        client?.close();
                        if (dCtx.mounted) Navigator.pop(dCtx);
                        onComplete(_added, sk);
                      });

                    } else if (phase == 'error') {
                      _phaseIdx  = -1;
                      _statusMsg = data['message'] as String? ?? 'त्रुटि हुई';
                      client?.close();
                    }
                  });
                }
              }
            } catch (e) {
              client?.close();
              if (dCtx.mounted) dss(() { _phaseIdx = -1; _statusMsg = _msg(e); });
              onError(_msg(e));
            }
          });
        }

        final isError = _phaseIdx == -1;
        final isDone  = _phaseIdx == 3;

        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 380,
            decoration: _dlgDec(),
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [

              // Animated icon
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.7, end: 1.0),
                duration: const Duration(milliseconds: 500),
                curve: Curves.elasticOut,
                builder: (_, v, child) => Transform.scale(scale: v, child: child),
                child: Container(
                  width: 62, height: 62,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                      color: isError ? _kError.withOpacity(0.1) : isDone ? _kSuccess.withOpacity(0.1) : _kPrimary.withOpacity(0.1)),
                  child: Icon(
                    isError  ? Icons.error_outline
                    : isDone ? Icons.check_circle_outline
                    : _phaseIdx == 1 ? Icons.lock_clock_outlined
                    : _phaseIdx == 2 ? Icons.storage_outlined
                    : Icons.upload_outlined,
                    color: isError ? _kError : isDone ? _kSuccess : _kPrimary, size: 30),
                ),
              ),
              const SizedBox(height: 14),

              Text(
                isError ? 'अपलोड विफल' : isDone ? 'अपलोड पूर्ण!' : 'बल्क अपलोड',
                style: TextStyle(color: isError ? _kError : isDone ? _kSuccess : _kDark, fontWeight: FontWeight.w800, fontSize: 17),
              ),
              const SizedBox(height: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(_statusMsg, key: ValueKey(_statusMsg),
                    style: const TextStyle(color: _kSubtle, fontSize: 12), textAlign: TextAlign.center),
              ),
              const SizedBox(height: 24),

              // Phase 1 — Parse
              _phaseRow(label: 'चरण 1 — Excel पार्स', pct: _parsePct, color: _kAccent, active: _phaseIdx == 0, done: _parsePct >= 1.0),
              const SizedBox(height: 14),
              // Phase 2 — Hash
              _phaseRow(label: 'चरण 2 — Password Hash', pct: _hashPct, color: _kInfo, active: _phaseIdx == 1, done: _hashPct >= 1.0),
              const SizedBox(height: 14),
              // Phase 3 — Insert
              _phaseRow(label: 'चरण 3 — DB Insert', pct: _insertPct, color: isError ? _kError : _kPrimary, active: _phaseIdx == 2, done: _insertPct >= 1.0 && !isError),
              const SizedBox(height: 10),

              if (_total > 0)
                TweenAnimationBuilder<int>(
                  tween: IntTween(begin: 0, end: _added),
                  duration: const Duration(milliseconds: 400),
                  builder: (_, v, __) => Text('$v / $_total rows',
                      style: const TextStyle(color: _kSubtle, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              const SizedBox(height: 20),

              if (isError || isDone)
                SizedBox(width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () { Navigator.pop(dCtx); if (isError) onError(_statusMsg); },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: isError ? _kError : _kSuccess, foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                    child: Text(isError ? 'बंद करें' : 'ठीक है', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ))
              else
                _PulsingDots(color: _kPrimary),
            ]),
          ),
        );
      }),
    );
  }

  Widget _phaseRow({required String label, required double pct, required Color color, required bool active, required bool done}) {
    final pctInt = (pct * 100).round().clamp(0, 100);
    return AnimatedOpacity(
      opacity: (pct > 0 || active) ? 1.0 : 0.35,
      duration: const Duration(milliseconds: 300),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AnimatedContainer(duration: const Duration(milliseconds: 300), width: 8, height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: done ? _kSuccess : active ? color : _kBorder)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(color: active ? _kDark : _kSubtle, fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.w500))),
          if (done)
            const Icon(Icons.check_circle_rounded, color: _kSuccess, size: 15)
          else if (active || pct > 0)
            Text('$pctInt%', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700))
          else
            Text('—', style: TextStyle(color: _kSubtle.withOpacity(0.4), fontSize: 12)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: pct),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            builder: (_, v, __) => LinearProgressIndicator(
              value: v, minHeight: 9,
              backgroundColor: color.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(done ? _kSuccess : color),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Edit Staff Dialog ─────────────────────────────────────────────────────
  void _showEditDialog(Map s) {
    final nameC   = TextEditingController(text: _v(s['name']));
    final pnoC    = TextEditingController(text: _v(s['pno']));
    final mobileC = TextEditingController(text: _v(s['mobile']));
    final thanaC  = TextEditingController(text: _v(s['thana']));
    final rankC   = TextEditingController(text: _v(s['rank']));
    bool saving   = false;
    final fk      = GlobalKey<FormState>();
    showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460),
          child: Container(decoration: _dlgDec(), child: Column(mainAxisSize: MainAxisSize.min, children: [
            _dlgHeader('स्टाफ संपादित करें', Icons.edit_outlined, ctx),
            Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Form(key: fk, child: Column(children: [
                _field(nameC,   'पूरा नाम *',  Icons.person_outline,        req: true),
                _field(pnoC,    'PNO *',        Icons.badge_outlined,        req: true),
                _field(mobileC, 'मोबाइल',      Icons.phone_outlined,        type: TextInputType.phone),
                _field(thanaC,  'थाना',         Icons.local_police_outlined),
                _field(rankC,   'पद/रैंक',      Icons.military_tech_outlined),
              ])))),
            _dlgActions(ctx, saving, onSave: () async {
              if (!fk.currentState!.validate()) return;
              ss(() => saving = true);
              try {
                final token = await AuthService.getToken();
                await ApiService.put('/admin/staff/${s['id']}', {'name': nameC.text.trim(), 'pno': pnoC.text.trim(), 'mobile': mobileC.text.trim(), 'thana': thanaC.text.trim(), 'rank': rankC.text.trim()}, token: token);
                if (ctx.mounted) Navigator.pop(ctx);
                _snack('स्टाफ अपडेट किया गया'); _refresh();
              } catch (e) { ss(() => saving = false); _snack(_msg(e), error: true); }
            }),
          ]))),
      )),
    );
  }

  // ── Add Staff Dialog ──────────────────────────────────────────────────────
  void _showAddDialog() {
    final pnoC = TextEditingController(); final nameC = TextEditingController();
    final mobileC = TextEditingController(); final thanaC = TextEditingController();
    final distC = TextEditingController(); final rankC = TextEditingController();
    bool saving = false; final fk = GlobalKey<FormState>();
    showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460),
          child: Container(decoration: _dlgDec(), child: Column(mainAxisSize: MainAxisSize.min, children: [
            _dlgHeader('स्टाफ जोड़ें', Icons.person_add_outlined, ctx),
            Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Form(key: fk, child: Column(children: [
                _field(pnoC,    'PNO *',        Icons.badge_outlined,        req: true),
                _field(nameC,   'पूरा नाम *',  Icons.person_outline,        req: true),
                _field(mobileC, 'मोबाइल',      Icons.phone_outlined,        type: TextInputType.phone),
                _field(thanaC,  'थाना',         Icons.local_police_outlined),
                _field(distC,   'जिला',         Icons.location_city_outlined),
                _field(rankC,   'पद/रैंक',      Icons.military_tech_outlined),
              ])))),
            _dlgActions(ctx, saving, saveLabel: 'जोड़ें', onSave: () async {
              if (!fk.currentState!.validate()) return;
              ss(() => saving = true);
              try {
                final token = await AuthService.getToken();
                await ApiService.post('/admin/staff', {'pno': pnoC.text.trim(), 'name': nameC.text.trim(), 'mobile': mobileC.text.trim(), 'thana': thanaC.text.trim(), 'district': distC.text.trim(), 'rank': rankC.text.trim()}, token: token);
                if (ctx.mounted) Navigator.pop(ctx);
                _snack('${nameC.text} जोड़ा गया'); _refresh();
              } catch (e) { ss(() => saving = false); _snack(_msg(e), error: true); }
            }),
          ]))),
      )),
    );
  }

  // ── Assign Duty Dialog ────────────────────────────────────────────────────
  void _showAssignDialog(Map staff) {
    final busCtrl = TextEditingController();
    Map? selectedCenter; String centerQ = ''; Timer? cTimer;
    List centerList = []; bool cLoading = false; bool saving = false;
    int cPage = 1; bool cHasMore = true; final cScroll = ScrollController();

    Future<void> loadCenters({bool reset = false, required StateSetter ss}) async {
      if (cLoading || (!cHasMore && !reset)) return;
      if (reset) { centerList = []; cPage = 1; cHasMore = true; }
      ss(() => cLoading = true);
      try {
        final token = await AuthService.getToken();
        final res = await ApiService.get('/admin/centers/all?q=${Uri.encodeComponent(centerQ)}&page=$cPage&limit=30', token: token);
        final wrapper = (res['data'] as Map<String, dynamic>?) ?? {};
        final data = List<Map>.from((wrapper['data'] as List?) ?? []);
        final total = (wrapper['total'] as num?)?.toInt() ?? 0;
        centerList = [...centerList, ...data]; cHasMore = centerList.length < total; cPage++;
      } catch (_) {}
      ss(() => cLoading = false);
    }

    showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        if (!cScroll.hasListeners) cScroll.addListener(() { if (cScroll.position.pixels >= cScroll.position.maxScrollExtent - 150) loadCenters(ss: ss); });
        if (centerList.isEmpty && !cLoading) loadCenters(reset: true, ss: ss);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 500, maxHeight: MediaQuery.of(ctx).size.height * 0.88),
            child: Container(decoration: _dlgDec(), child: Column(children: [
              _dlgHeader('ड्यूटी असाइन करें', Icons.how_to_vote_outlined, ctx),
              Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _staffInfoCard(staff), const SizedBox(height: 16),
                if (selectedCenter != null) ...[_selectedCenterCard(selectedCenter!, onClear: () => ss(() => selectedCenter = null)), const SizedBox(height: 10)],
                _sectionLabel('मतदान केंद्र चुनें'), const SizedBox(height: 8),
                TextField(onChanged: (v) { cTimer?.cancel(); cTimer = Timer(const Duration(milliseconds: 350), () { centerQ = v; loadCenters(reset: true, ss: ss); }); },
                    style: const TextStyle(color: _kDark, fontSize: 13), decoration: _searchDec('केंद्र, थाना, GP से खोजें...')),
                const SizedBox(height: 8),
                Container(height: 220,
                  decoration: BoxDecoration(border: Border.all(color: _kBorder), borderRadius: BorderRadius.circular(10), color: Colors.white),
                  child: cLoading && centerList.isEmpty
                      ? const Center(child: CircularProgressIndicator(color: _kPrimary, strokeWidth: 2))
                      : centerList.isEmpty ? const Center(child: Text('कोई केंद्र नहीं मिला', style: TextStyle(color: _kSubtle, fontSize: 12)))
                      : ListView.builder(controller: cScroll, padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: centerList.length + (cHasMore ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i >= centerList.length) return const Padding(padding: EdgeInsets.all(10), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary))));
                            final c = centerList[i]; final isSel = selectedCenter?['id'] == c['id'];
                            final type = '${c['centerType'] ?? 'C'}'; final tc = type == 'A' ? _kError : type == 'B' ? _kAccent : _kInfo;
                            return InkWell(onTap: () => ss(() => selectedCenter = Map<String, dynamic>.from(c)),
                              child: AnimatedContainer(duration: const Duration(milliseconds: 120), margin: const EdgeInsets.fromLTRB(6, 3, 6, 3), padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: isSel ? _kPrimary.withOpacity(0.08) : Colors.transparent, borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: isSel ? _kPrimary : _kBorder.withOpacity(0.4), width: isSel ? 1.5 : 1)),
                                child: Row(children: [
                                  _typeBadge(type, tc), const SizedBox(width: 10),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(_v(c['name']), style: TextStyle(color: isSel ? _kPrimary : _kDark, fontWeight: FontWeight.w700, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 2),
                                    Row(children: [
                                      if (_v(c['gpName']).isNotEmpty) ...[const Icon(Icons.account_balance_outlined, size: 10, color: _kSubtle), const SizedBox(width: 2), Flexible(child: Text(_v(c['gpName']), style: const TextStyle(color: _kSubtle, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis)), const SizedBox(width: 6)],
                                      if (_v(c['thana']).isNotEmpty) ...[const Icon(Icons.local_police_outlined, size: 10, color: _kSubtle), const SizedBox(width: 2), Flexible(child: Text(_v(c['thana']), style: const TextStyle(color: _kSubtle, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis))],
                                    ]),
                                    if ((c['dutyCount'] ?? 0) > 0) Text('${c['dutyCount']} स्टाफ असाइन', style: const TextStyle(color: _kInfo, fontSize: 10, fontWeight: FontWeight.w600)),
                                  ])),
                                  if (isSel) const Icon(Icons.check_circle_rounded, color: _kPrimary, size: 18),
                                ]),
                              ));
                          })),
                if (cHasMore && !cLoading) const Padding(padding: EdgeInsets.only(top: 4), child: Text('नीचे स्क्रॉल करें और देखें...', style: TextStyle(color: _kSubtle, fontSize: 10))),
                const SizedBox(height: 14), _sectionLabel('बस संख्या (वैकल्पिक)'), const SizedBox(height: 8),
                TextField(controller: busCtrl, style: const TextStyle(color: _kDark, fontSize: 13),
                  decoration: InputDecoration(hintText: 'बस नंबर दर्ज करें', hintStyle: const TextStyle(color: _kSubtle, fontSize: 12), prefixIcon: const Icon(Icons.directions_bus_outlined, size: 18, color: _kPrimary),
                      filled: true, fillColor: Colors.white, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kPrimary, width: 2)))),
              ]))),
              Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), child: Row(children: [
                Expanded(child: OutlinedButton(onPressed: saving ? null : () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(foregroundColor: _kSubtle, side: const BorderSide(color: _kBorder), padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: const Text('रद्द'))),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: selectedCenter == null ? _kSubtle : _kPrimary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: selectedCenter == null || saving ? null : () async {
                    ss(() => saving = true);
                    try {
                      final token = await AuthService.getToken();
                      await ApiService.post('/admin/duties', {'staffId': staff['id'], 'centerId': selectedCenter!['id'], 'busNo': busCtrl.text.trim()}, token: token);
                      if (ctx.mounted) Navigator.pop(ctx);
                      _snack('${_v(staff['name'])} असाइन किया गया'); _refresh();
                    } catch (e) { ss(() => saving = false); _snack(_msg(e), error: true); }
                  },
                  child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('ड्यूटी असाइन करें', style: TextStyle(fontWeight: FontWeight.w700)),
                )),
              ])),
            ])),
          ),
        );
      }),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  EXCEL UPLOAD — with instant loading feedback on button tap
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _pickExcel() async {
    if (mounted) setState(() => _excelLoading = true);

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls'], withData: true);
    } catch (e) {
      if (mounted) setState(() => _excelLoading = false);
      _snack('File picker error: ${_msg(e)}', error: true); return;
    }
    if (result == null || result.files.isEmpty) {
      if (mounted) setState(() => _excelLoading = false); return;
    }
    final bytes = result.files.single.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) setState(() => _excelLoading = false);
      _snack('फ़ाइल पढ़ने में त्रुटि', error: true); return;
    }

    ex.Excel excel;
    try { excel = ex.Excel.decodeBytes(bytes); }
    catch (e) {
      if (mounted) setState(() => _excelLoading = false);
      _snack('Excel त्रुटि: ${_msg(e)}', error: true); return;
    }
    if (mounted) setState(() => _excelLoading = false);

    if (excel.tables.isEmpty) { _snack('कोई शीट नहीं मिली', error: true); return; }

    final sheetNames = excel.tables.keys.toList();
    String? chosen = sheetNames.length == 1 ? sheetNames.first : await _pickSheet(sheetNames);
    if (chosen == null || !mounted) return;

    final sheet = excel.tables[chosen]!;
    if (sheet.rows.isEmpty) { _snack('शीट खाली है', error: true); return; }

    String cellStr(int ri, int ci) {
      if (ri >= sheet.rows.length) return '';
      final row = sheet.rows[ri];
      if (ci >= row.length) return '';
      return (row[ci]?.value?.toString() ?? '').trim();
    }

    int headerRow = -1; int? iPno, iName, iMobile, iThana, iDistrict, iRank;
    for (int ri = 0; ri < sheet.rows.length.clamp(0, 5); ri++) {
      final vals = sheet.rows[ri].map((c) => (c?.value?.toString() ?? '').trim().toLowerCase()).toList();
      int? p, n, m, t, d, r;
      for (int ci = 0; ci < vals.length; ci++) {
        final h = vals[ci];
        if (p == null && (h.contains('pno') || h.contains('p.no') || h.contains('police no'))) p = ci;
        if (n == null && (h.contains('name') || h.contains('नाम'))) n = ci;
        if (m == null && (h.contains('mobile') || h.contains('mob') || h.contains('phone'))) m = ci;
        if (t == null && (h.contains('thana') || h.contains('थाना') || h == 'ps')) t = ci;
        if (d == null && (h.contains('district') || h.contains('dist') || h.contains('जिला'))) d = ci;
        if (r == null && (h.contains('rank') || h.contains('post') || h.contains('पद'))) r = ci;
      }
      if (p != null || n != null) { headerRow = ri; iPno = p; iName = n; iMobile = m; iThana = t; iDistrict = d; iRank = r; break; }
    }
    final dataStart = headerRow >= 0 ? headerRow + 1 : 0;
    iPno ??= 0; iName ??= 1; iMobile ??= 2; iThana ??= 3; iDistrict ??= 4; iRank ??= 5;

    final preview = <Map<String, dynamic>>[];
    for (int ri = dataStart; ri < sheet.rows.length; ri++) {
      final row = sheet.rows[ri];
      if (row.every((c) => c == null || (c.value?.toString().trim().isEmpty ?? true))) continue;
      final pno = cellStr(ri, iPno!); final name = cellStr(ri, iName!);
      if (pno.isEmpty && name.isEmpty) continue;
      preview.add({'pno': pno, 'name': name, 'mobile': cellStr(ri, iMobile!), 'thana': cellStr(ri, iThana!), 'district': cellStr(ri, iDistrict!), 'rank': cellStr(ri, iRank!), '_row': ri + 1});
    }
    if (preview.isEmpty) { _snack('कोई डेटा नहीं मिला', error: true); return; }
    if (!mounted) return;
    _showExcelPreview(preview);
  }

  Future<String?> _pickSheet(List<String> names) => showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _kBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _kBorder)),
      title: const Text('शीट चुनें', style: TextStyle(color: _kDark, fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, children: names.map((n) => ListTile(title: Text(n, style: const TextStyle(color: _kDark)), trailing: const Icon(Icons.chevron_right, color: _kSubtle), onTap: () => Navigator.pop(ctx, n))).toList()),
    ),
  );

  void _showExcelPreview(List<Map<String, dynamic>> initial) {
    final allRows = List<Map<String, dynamic>>.from(initial);
    final workRows = List<Map<String, dynamic>>.from(initial);
    String previewQ = ''; int previewPage = 1; const previewPageSize = 50;
    bool uploading = false; final previewSearchCtrl = TextEditingController(); Timer? previewDebounce;

    showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        final filtered = previewQ.isEmpty ? workRows : workRows.where((r) {
          final q = previewQ.toLowerCase();
          return (r['name'] as String? ?? '').toLowerCase().contains(q) || (r['pno'] as String? ?? '').toLowerCase().contains(q) || (r['thana'] as String? ?? '').toLowerCase().contains(q) || (r['mobile'] as String? ?? '').toLowerCase().contains(q);
        }).toList();
        final totalPages = ((filtered.length - 1) ~/ previewPageSize) + 1;
        final safePage = previewPage.clamp(1, totalPages.clamp(1, 9999));
        final pageStart = (safePage - 1) * previewPageSize;
        final pageEnd = (pageStart + previewPageSize).clamp(0, filtered.length);
        final pageRows = filtered.sublist(pageStart, pageEnd);
        final valid = workRows.where((r) => (r['pno'] as String? ?? '').isNotEmpty && (r['name'] as String? ?? '').isNotEmpty).length;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.of(ctx).size.height * 0.92),
            child: Container(decoration: _dlgDec(), child: Column(mainAxisSize: MainAxisSize.min, children: [
              _dlgHeader('Preview — ${workRows.length}/${allRows.length} rows', Icons.upload_file_outlined, ctx),
              Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 4), child: Row(children: [
                _pill('$valid मान्य', _kSuccess), const SizedBox(width: 8),
                _pill('${workRows.length - valid} त्रुटि', _kError), const SizedBox(width: 8),
                if (previewQ.isNotEmpty) _pill('${filtered.length} मिले', _kInfo),
                const Spacer(), const Icon(Icons.touch_app_outlined, size: 11, color: _kSubtle), const SizedBox(width: 3),
                const Text('× से हटाएं', style: TextStyle(color: _kSubtle, fontSize: 10)),
              ])),
              Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                child: TextField(controller: previewSearchCtrl, style: const TextStyle(color: _kDark, fontSize: 13),
                  onChanged: (v) { previewDebounce?.cancel(); previewDebounce = Timer(const Duration(milliseconds: 250), () => ss(() { previewQ = v.trim(); previewPage = 1; })); },
                  decoration: _searchDec('नाम, PNO, थाना, मोबाइल से खोजें...', onClear: previewQ.isNotEmpty ? () { previewSearchCtrl.clear(); ss(() { previewQ = ''; previewPage = 1; }); } : null))),
              Flexible(child: pageRows.isEmpty
                  ? Padding(padding: const EdgeInsets.all(24), child: Text(previewQ.isNotEmpty ? '"$previewQ" के लिए कोई row नहीं मिला' : 'कोई rows नहीं', style: const TextStyle(color: _kSubtle), textAlign: TextAlign.center))
                  : ListView.builder(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), itemCount: pageRows.length, itemBuilder: (_, i) {
                      final r = pageRows[i]; final isOk = (r['pno'] as String? ?? '').isNotEmpty && (r['name'] as String? ?? '').isNotEmpty;
                      return Container(margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(color: isOk ? Colors.white : _kError.withOpacity(0.04), borderRadius: BorderRadius.circular(9), border: Border.all(color: isOk ? _kBorder.withOpacity(0.4) : _kError.withOpacity(0.35))),
                        child: Row(children: [
                          Container(width: 36, alignment: Alignment.center, padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(color: isOk ? _kSurface.withOpacity(0.6) : _kError.withOpacity(0.06), borderRadius: const BorderRadius.only(topLeft: Radius.circular(9), bottomLeft: Radius.circular(9))),
                              child: Text('${r['_row']}', style: TextStyle(color: isOk ? _kSubtle : _kError, fontSize: 10, fontWeight: FontWeight.w700))),
                          Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text((r['name'] as String).isNotEmpty ? r['name'] as String : '⚠ नाम आवश्यक', style: TextStyle(color: (r['name'] as String).isNotEmpty ? _kDark : _kError, fontWeight: FontWeight.w700, fontSize: 13)),
                            const SizedBox(height: 3),
                            Wrap(spacing: 8, runSpacing: 2, children: [
                              _miniTag(Icons.badge_outlined, (r['pno'] as String).isNotEmpty ? 'PNO: ${r['pno']}' : '⚠ PNO आवश्यक', (r['pno'] as String).isEmpty ? _kError : null),
                              if ((r['mobile'] as String).isNotEmpty) _miniTag(Icons.phone_outlined, r['mobile'] as String, null),
                              if ((r['thana'] as String).isNotEmpty) _miniTag(Icons.local_police_outlined, r['thana'] as String, null),
                              if ((r['rank'] as String).isNotEmpty) _miniTag(Icons.military_tech_outlined, r['rank'] as String, null),
                            ]),
                          ]))),
                          InkWell(onTap: () => ss(() {
                            workRows.remove(r);
                            final nf = previewQ.isEmpty ? workRows : workRows.where((x) { final q = previewQ.toLowerCase(); return (x['name'] as String? ?? '').toLowerCase().contains(q) || (x['pno'] as String? ?? '').toLowerCase().contains(q); }).toList();
                            final ntp = ((nf.length - 1) ~/ previewPageSize).clamp(0, 9999) + 1;
                            if (previewPage > ntp) previewPage = ntp.clamp(1, 9999);
                          }), borderRadius: const BorderRadius.only(topRight: Radius.circular(9), bottomRight: Radius.circular(9)),
                            child: Container(width: 36, height: 52, alignment: Alignment.center, child: const Icon(Icons.close, size: 15, color: _kError))),
                        ]));
                    })),
              if (totalPages > 1)
                Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: _kSurface.withOpacity(0.5), border: Border(top: BorderSide(color: _kBorder.withOpacity(0.3)))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _pageBtn(Icons.chevron_left, safePage > 1, () => ss(() => previewPage = safePage - 1)),
                    const SizedBox(width: 8),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(color: _kPrimary.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: _kBorder.withOpacity(0.4))),
                        child: Text('$safePage / $totalPages  (${filtered.length} rows)', style: const TextStyle(color: _kDark, fontSize: 12, fontWeight: FontWeight.w700))),
                    const SizedBox(width: 8),
                    _pageBtn(Icons.chevron_right, safePage < totalPages, () => ss(() => previewPage = safePage + 1)),
                    const Spacer(),
                    if (totalPages > 3) ...[
                      _pageJumpBtn('1', safePage != 1, () => ss(() => previewPage = 1)), const SizedBox(width: 4),
                      _pageJumpBtn('$totalPages', safePage != totalPages, () => ss(() => previewPage = totalPages)),
                    ],
                  ])),
              Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 16), child: Row(children: [
                Expanded(child: OutlinedButton(onPressed: uploading ? null : () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(foregroundColor: _kSubtle, side: const BorderSide(color: _kBorder), padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: const Text('रद्द'))),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: valid == 0 ? _kSubtle : _kPrimary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: uploading || valid == 0 ? null : () {
                    ss(() => uploading = true);
                    _showBulkProgressDialog(
                      context: ctx,
                      toUpload: workRows.where((r) => (r['pno'] as String? ?? '').isNotEmpty && (r['name'] as String? ?? '').isNotEmpty).map((r) { final m = Map<String, dynamic>.from(r)..remove('_row'); return m; }).toList(),
                      onComplete: (added, skipped) { if (ctx.mounted) Navigator.pop(ctx); _snack('$added जोड़े गए, $skipped छोड़े गए'); _refresh(); },
                      onError: (msg) { ss(() => uploading = false); _snack(msg, error: true); },
                    );
                  },
                  icon: uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.upload, size: 16),
                  label: Text(uploading ? 'अपलोड हो रहा है...' : '$valid अपलोड करें'),
                )),
              ])),
            ])),
          ),
        );
      }),
    );
  }

  Widget _staffCard(Map s, {required bool assigned}) {
    final name = _v(s['name']);
    final initials = name.trim().split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    final avatarColor = assigned ? _kSuccess : _kAccent;
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _kBorder.withOpacity(0.4)), boxShadow: [BoxShadow(color: _kPrimary.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))]),
        child: Padding(padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(shape: BoxShape.circle, color: avatarColor.withOpacity(0.12), border: Border.all(color: avatarColor.withOpacity(0.35))),
                child: Center(child: Text(initials.isEmpty ? 'S' : initials, style: TextStyle(color: avatarColor, fontWeight: FontWeight.w900, fontSize: initials.length <= 1 ? 18 : 13)))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(name.isNotEmpty ? name : '—', style: const TextStyle(color: _kDark, fontWeight: FontWeight.w700, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 4), _badge(assigned ? 'असाइन' : 'रिज़र्व', assigned ? _kSuccess : _kAccent),
              ]),
              const SizedBox(height: 5),
              Wrap(spacing: 10, runSpacing: 3, children: [
                if (_v(s['pno']).isNotEmpty)      _tag(Icons.badge_outlined,         'PNO: ${_v(s['pno'])}'),
                if (_v(s['mobile']).isNotEmpty)   _tag(Icons.phone_outlined,         _v(s['mobile'])),
                if (_v(s['thana']).isNotEmpty)    _tag(Icons.local_police_outlined,  _v(s['thana'])),
                if (_v(s['district']).isNotEmpty) _tag(Icons.location_city_outlined, _v(s['district'])),
                if (_v(s['rank']).isNotEmpty)     _tag(Icons.military_tech_outlined, _v(s['rank'])),
              ]),
              if (assigned && _v(s['centerName']).isNotEmpty) ...[
                const SizedBox(height: 5),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: _kSuccess.withOpacity(0.06), borderRadius: BorderRadius.circular(6), border: Border.all(color: _kSuccess.withOpacity(0.2))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.location_on_outlined, size: 11, color: _kSuccess), const SizedBox(width: 4),
                    Flexible(child: Text(_v(s['centerName']), style: const TextStyle(color: _kSuccess, fontSize: 11, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis))])),
              ],
            ])),
            const SizedBox(width: 4),
            Column(mainAxisSize: MainAxisSize.min, children: [
              _iconBtn(Icons.edit_outlined,  _kInfo,  () => _showEditDialog(s)),
              const SizedBox(height: 4),
              _iconBtn(Icons.delete_outline, _kError, () => _deleteStaff(s)),
              const SizedBox(height: 4),
              _iconBtn(assigned ? Icons.person_remove_outlined : Icons.how_to_vote_outlined, assigned ? _kError : _kPrimary, () => assigned ? _removeDuty(s) : _showAssignDialog(s)),
            ]),
          ])),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalAll = _assignedTotal + _reserveTotal;
    return Column(children: [
      Container(color: _kSurface, padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(children: [
          Expanded(child: TextField(controller: _searchCtrl, style: const TextStyle(color: _kDark, fontSize: 13),
              decoration: _searchDec('नाम, PNO, मोबाइल, थाना खोजें...', onClear: _q.isNotEmpty ? () { _searchCtrl.clear(); _q = ''; _refresh(); } : null))),
          const SizedBox(width: 8),
          _actionBtn(Icons.person_add_outlined, 'जोड़ें', _kPrimary, _showAddDialog),
          const SizedBox(width: 6),
          // Excel button — shows spinner while file picker is open
          _excelLoading
              ? Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                  decoration: BoxDecoration(color: _kDark, borderRadius: BorderRadius.circular(10)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                    SizedBox(width: 6),
                    Text('लोड...', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ]))
              : _actionBtn(Icons.upload_file_outlined, 'Excel', _kDark, _pickExcel),
        ])),
      Container(color: _kBg, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(children: [
          _summaryChip('कुल', '$totalAll', _kPrimary), const SizedBox(width: 8),
          _summaryChip('असाइन', '$_assignedTotal', _kSuccess), const SizedBox(width: 8),
          _summaryChip('रिज़र्व', '$_reserveTotal', _kAccent),
          const Spacer(),
          if (_q.isNotEmpty) Text('${_assignedTotal + _reserveTotal} results', style: const TextStyle(color: _kSubtle, fontSize: 11)),
          IconButton(icon: const Icon(Icons.refresh_rounded, size: 18, color: _kSubtle), onPressed: _refresh, tooltip: 'रिफ्रेश', padding: EdgeInsets.zero, constraints: const BoxConstraints()),
        ])),
      Container(color: _kBg, child: TabBar(controller: _tabs,
          labelColor: _kPrimary, unselectedLabelColor: _kSubtle,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          indicatorColor: _kPrimary, indicatorWeight: 3,
          tabs: [Tab(text: 'असाइन ($_assignedTotal)'), Tab(text: 'रिज़र्व ($_reserveTotal)')])),
      Expanded(child: TabBarView(controller: _tabs, children: [
        _buildStaffList(items: _assigned, loading: _assignedLoading, hasMore: _assignedHasMore, scroll: _assignedScroll, assigned: true,
            emptyMsg: _q.isNotEmpty ? '"$_q" के लिए कोई result नहीं' : 'कोई असाइन स्टाफ नहीं\nरिज़र्व टैब से असाइन करें', emptyIcon: Icons.how_to_vote_outlined),
        _buildStaffList(items: _reserve, loading: _reserveLoading, hasMore: _reserveHasMore, scroll: _reserveScroll, assigned: false,
            emptyMsg: _q.isNotEmpty ? '"$_q" के लिए कोई result नहीं' : 'सभी स्टाफ असाइन हैं!', emptyIcon: Icons.badge_outlined),
      ])),
    ]);
  }

  Widget _buildStaffList({required List<Map> items, required bool loading, required bool hasMore, required ScrollController scroll, required bool assigned, required String emptyMsg, required IconData emptyIcon}) {
    return RefreshIndicator(onRefresh: () async => _refresh(), color: _kPrimary,
      child: items.isEmpty && loading ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : items.isEmpty ? _emptyState(emptyMsg, emptyIcon)
          : ListView.builder(controller: scroll, padding: const EdgeInsets.fromLTRB(12, 10, 12, 80), addRepaintBoundaries: false,
              itemCount: items.length + (hasMore ? 1 : 0),
              itemBuilder: (_, i) {
                if (i >= items.length) return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary))));
                return _staffCard(items[i], assigned: assigned);
              }));
  }

  // ── Widget helpers ────────────────────────────────────────────────────────
  BoxDecoration _dlgDec() => BoxDecoration(color: _kBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: _kBorder, width: 1.2), boxShadow: [BoxShadow(color: _kPrimary.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 8))]);
  Widget _dlgHeader(String title, IconData icon, BuildContext ctx) => Container(
    padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
    decoration: const BoxDecoration(color: _kDark, borderRadius: BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15))),
    child: Row(children: [
      Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: _kPrimary.withOpacity(0.25), borderRadius: BorderRadius.circular(7)), child: Icon(icon, color: _kBorder, size: 16)),
      const SizedBox(width: 10), Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
      IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, color: Colors.white60, size: 20), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
    ]));
  Widget _dlgActions(BuildContext ctx, bool saving, {String saveLabel = 'अपडेट', required VoidCallback onSave}) =>
      Padding(padding: const EdgeInsets.all(20), child: Row(children: [
        Expanded(child: OutlinedButton(onPressed: saving ? null : () => Navigator.pop(ctx), style: OutlinedButton.styleFrom(foregroundColor: _kSubtle, side: const BorderSide(color: _kBorder), padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('रद्द'))),
        const SizedBox(width: 12),
        Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: saving ? null : onSave,
            child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text(saveLabel, style: const TextStyle(fontWeight: FontWeight.w700)))),
      ]));
  Widget _field(TextEditingController c, String label, IconData icon, {bool req = false, TextInputType? type}) =>
      Padding(padding: const EdgeInsets.only(bottom: 10), child: TextFormField(controller: c, keyboardType: type, style: const TextStyle(color: _kDark, fontSize: 13),
        decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: _kSubtle, fontSize: 12), prefixIcon: Icon(icon, size: 18, color: _kPrimary), filled: true, fillColor: Colors.white, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kPrimary, width: 2)),
            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kError))),
        validator: req ? (v) => (v?.trim().isEmpty ?? true) ? '${label.replaceAll(' *', '')} आवश्यक' : null : null));
  InputDecoration _searchDec(String hint, {VoidCallback? onClear}) => InputDecoration(hintText: hint, hintStyle: const TextStyle(color: _kSubtle, fontSize: 12), prefixIcon: const Icon(Icons.search, color: _kSubtle, size: 18),
      suffixIcon: onClear != null ? IconButton(icon: const Icon(Icons.clear, size: 16, color: _kSubtle), onPressed: onClear) : null,
      filled: true, fillColor: Colors.white, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kPrimary, width: 2)));
  Widget _staffInfoCard(Map s) => Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: _kSurface, borderRadius: BorderRadius.circular(10), border: Border.all(color: _kBorder.withOpacity(0.5))),
    child: Row(children: [
      Container(width: 40, height: 40, decoration: BoxDecoration(shape: BoxShape.circle, color: _kAccent.withOpacity(0.12), border: Border.all(color: _kAccent.withOpacity(0.35))), child: Center(child: Text(_v(s['name']).split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join(), style: const TextStyle(color: _kAccent, fontWeight: FontWeight.w800, fontSize: 14)))),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_v(s['name']), style: const TextStyle(color: _kDark, fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 2),
        Row(children: [const Icon(Icons.badge_outlined, size: 11, color: _kSubtle), const SizedBox(width: 3), Text('PNO: ${_v(s['pno'])}', style: const TextStyle(color: _kSubtle, fontSize: 11)),
          if (_v(s['thana']).isNotEmpty) ...[const SizedBox(width: 8), const Icon(Icons.local_police_outlined, size: 11, color: _kSubtle), const SizedBox(width: 3), Flexible(child: Text(_v(s['thana']), style: const TextStyle(color: _kSubtle, fontSize: 11), overflow: TextOverflow.ellipsis))]]),
      ])),
    ]));
  Widget _selectedCenterCard(Map c, {required VoidCallback onClear}) => Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _kSuccess.withOpacity(0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: _kSuccess.withOpacity(0.3))),
    child: Row(children: [const Icon(Icons.check_circle_rounded, color: _kSuccess, size: 18), const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_v(c['name']), style: const TextStyle(color: _kDark, fontWeight: FontWeight.w700, fontSize: 13)), Text('${_v(c['thana'])} • ${_v(c['gpName'])}', style: const TextStyle(color: _kSubtle, fontSize: 11))])),
      GestureDetector(onTap: onClear, child: const Icon(Icons.close, size: 16, color: _kSubtle))]));
  Widget _sectionLabel(String label) => Row(children: [Container(width: 3, height: 14, decoration: BoxDecoration(color: _kPrimary, borderRadius: BorderRadius.circular(2))), const SizedBox(width: 7), Text(label, style: const TextStyle(color: _kDark, fontSize: 13, fontWeight: FontWeight.w800))]);
  Widget _typeBadge(String type, Color color) => Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.12), border: Border.all(color: color.withOpacity(0.4))), child: Center(child: Text(type, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900))));
  Widget _tag(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 11, color: _kSubtle), const SizedBox(width: 3), Text(text, style: const TextStyle(color: _kSubtle, fontSize: 11, fontWeight: FontWeight.w500))]);
  Widget _miniTag(IconData icon, String text, Color? color) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 10, color: color ?? _kSubtle), const SizedBox(width: 2), Text(text, style: TextStyle(color: color ?? _kSubtle, fontSize: 10))]);
  Widget _badge(String label, Color color) => Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(7), border: Border.all(color: color.withOpacity(0.3))), child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)));
  Widget _pill(String label, Color color) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.3))), child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)));
  Widget _summaryChip(String label, String count, Color color) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.25))), child: RichText(text: TextSpan(children: [TextSpan(text: '$count ', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900)), TextSpan(text: label, style: const TextStyle(color: _kSubtle, fontSize: 11))])));
  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) => GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: Colors.white, size: 14), const SizedBox(width: 4), Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))])));
  Widget _iconBtn(IconData icon, Color color, VoidCallback onTap) => GestureDetector(onTap: onTap, child: Container(width: 34, height: 34, decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.25))), child: Icon(icon, size: 16, color: color)));
  Widget _emptyState(String msg, IconData icon) => Center(child: Padding(padding: const EdgeInsets.all(40), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 52, color: _kSubtle.withOpacity(0.4)), const SizedBox(height: 14), Text(msg, style: const TextStyle(color: _kSubtle, fontSize: 13), textAlign: TextAlign.center)])));
  Widget _pageBtn(IconData icon, bool enabled, VoidCallback onTap) => GestureDetector(onTap: enabled ? onTap : null, child: Container(width: 32, height: 32, decoration: BoxDecoration(color: enabled ? _kPrimary.withOpacity(0.1) : Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: enabled ? _kBorder : Colors.grey.withOpacity(0.3))), child: Icon(icon, size: 18, color: enabled ? _kPrimary : Colors.grey)));
  Widget _pageJumpBtn(String label, bool enabled, VoidCallback onTap) => GestureDetector(onTap: enabled ? onTap : null, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: enabled ? _kAccent.withOpacity(0.1) : Colors.grey.withOpacity(0.05), borderRadius: BorderRadius.circular(6), border: Border.all(color: enabled ? _kBorder : Colors.grey.withOpacity(0.2))), child: Text(label, style: TextStyle(color: enabled ? _kAccent : Colors.grey, fontSize: 11, fontWeight: FontWeight.w700))));
}

// ── Pulsing dots while uploading ──────────────────────────────────────────────
class _PulsingDots extends StatefulWidget {
  final Color color;
  const _PulsingDots({required this.color});
  @override
  State<_PulsingDots> createState() => _PulsingDotsState();
}
class _PulsingDotsState extends State<_PulsingDots> with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;
  late final List<Animation<double>> _anims;
  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(3, (i) => AnimationController(vsync: this, duration: const Duration(milliseconds: 700)));
    _anims = _ctrls.map((c) => Tween<double>(begin: 0.25, end: 1.0).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut))).toList();
    for (int i = 0; i < 3; i++) Future.delayed(Duration(milliseconds: i * 180), () { if (mounted) _ctrls[i].repeat(reverse: true); });
  }
  @override
  void dispose() { for (final c in _ctrls) c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) => Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FadeTransition(opacity: _anims[i], child: Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color))))));
}