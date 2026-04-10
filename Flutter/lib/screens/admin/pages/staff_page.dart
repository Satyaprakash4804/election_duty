import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
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

// ══════════════════════════════════════════════════════════════════════════════
//  UPLOAD PROGRESS SINGLETON
// ══════════════════════════════════════════════════════════════════════════════

enum _UploadPhase { idle, parsing, uploading, done, error }

class UploadProgress extends ChangeNotifier {
  static final UploadProgress instance = UploadProgress._();
  UploadProgress._();

  _UploadPhase phase = _UploadPhase.idle;
  double parsePct = 0, hashPct = 0, insertPct = 0;
  int    added = 0, total = 0;
  String statusMsg = '', errorMsg = '';

  bool get isActive =>
      phase != _UploadPhase.idle &&
      phase != _UploadPhase.done &&
      phase != _UploadPhase.error;

  void reset() {
    phase = _UploadPhase.idle;
    parsePct = hashPct = insertPct = 0;
    added = total = 0;
    statusMsg = errorMsg = '';
    notifyListeners();
  }

  void update({
    _UploadPhase? p, double? pp, double? hp, double? ip,
    int? a, int? t, String? msg, String? err,
  }) {
    if (p   != null) phase     = p;
    if (pp  != null) parsePct  = pp;
    if (hp  != null) hashPct   = hp;
    if (ip  != null) insertPct = ip;
    if (a   != null) added     = a;
    if (t   != null) total     = t;
    if (msg != null) statusMsg = msg;
    if (err != null) errorMsg  = err;
    notifyListeners();
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  FLOATING PROGRESS BANNER
// ══════════════════════════════════════════════════════════════════════════════

class UploadProgressBanner extends StatelessWidget {
  const UploadProgressBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: UploadProgress.instance,
      builder: (_, __) {
        final up = UploadProgress.instance;
        if (up.phase == _UploadPhase.idle) return const SizedBox.shrink();
        final isErr  = up.phase == _UploadPhase.error;
        final isDone = up.phase == _UploadPhase.done;
        final color  = isErr ? _kError : isDone ? _kSuccess : _kPrimary;
        final overall = ((up.parsePct * 0.15) + (up.hashPct * 0.30) + (up.insertPct * 0.55)).clamp(0.0, 1.0);

        return Positioned(
          bottom: 16, left: 12, right: 12,
          child: Material(
            elevation: 10,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                color: _kDark, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withOpacity(0.6), width: 1.5),
              ),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  SizedBox(width: 24, height: 24,
                    child: isErr
                        ? const Icon(Icons.error_outline, color: _kError, size: 20)
                        : isDone
                            ? const Icon(Icons.check_circle_outline, color: _kSuccess, size: 20)
                            : _SpinIcon(color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(isErr ? 'अपलोड विफल' : isDone ? 'अपलोड पूर्ण!' : 'बल्क अपलोड',
                        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
                    Text(up.statusMsg, style: const TextStyle(color: Colors.white60, fontSize: 11),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
                  if (up.total > 0)
                    Text('${up.added}/${up.total}',
                        style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12)),
                  const SizedBox(width: 8),
                  if (isDone || isErr)
                    GestureDetector(onTap: UploadProgress.instance.reset,
                        child: const Icon(Icons.close, color: Colors.white54, size: 18)),
                ]),
                const SizedBox(height: 8),
                ClipRRect(borderRadius: BorderRadius.circular(4),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: overall),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    builder: (_, v, __) => LinearProgressIndicator(
                      value: v, minHeight: 6,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          isErr ? _kError : isDone ? _kSuccess : color),
                    ),
                  )),
                if (!isErr && !isDone) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    _miniPhase('Parse',  up.parsePct,  _kAccent),
                    const SizedBox(width: 8),
                    _miniPhase('Hash',   up.hashPct,   _kInfo),
                    const SizedBox(width: 8),
                    _miniPhase('Insert', up.insertPct, _kPrimary),
                  ]),
                ],
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _miniPhase(String label, double pct, Color color) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9)),
        const Spacer(),
        Text('${(pct * 100).round()}%',
            style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 2),
      ClipRRect(borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(value: pct, minHeight: 3,
              backgroundColor: color.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation(pct >= 1.0 ? _kSuccess : color))),
    ]),
  );
}

class _SpinIcon extends StatefulWidget {
  final Color color;
  const _SpinIcon({required this.color});
  @override State<_SpinIcon> createState() => _SpinIconState();
}
class _SpinIconState extends State<_SpinIcon> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => RotationTransition(turns: _c,
      child: Icon(Icons.upload_rounded, color: widget.color, size: 18));
}

// ══════════════════════════════════════════════════════════════════════════════
//  STAFF PAGE
// ══════════════════════════════════════════════════════════════════════════════

class StaffPage extends StatefulWidget {
  const StaffPage({super.key});
  @override State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage> with SingleTickerProviderStateMixin {
  late TabController _tabs;

  // ── List data ─────────────────────────────────────────────────────────────
  final List<Map> _assigned = [];
  int  _assignedPage = 1, _assignedTotal = 0;
  bool _assignedLoading = false, _assignedHasMore = true;
  final ScrollController _assignedScroll = ScrollController();

  final List<Map> _reserve  = [];
  int  _reservePage = 1, _reserveTotal = 0;
  bool _reserveLoading = false, _reserveHasMore = true;
  final ScrollController _reserveScroll = ScrollController();

  // ── Multi-select ──────────────────────────────────────────────────────────
  final Set<int> _selected = {};
  bool get _selectMode => _selected.isNotEmpty;

  // ── Search ────────────────────────────────────────────────────────────────
  String _q = '';
  Timer? _debounce;
  final _searchCtrl = TextEditingController();

  bool _excelLoading = false;
  _UploadPhase _lastSeenPhase = _UploadPhase.idle;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)
      ..addListener(() { if (!_tabs.indexIsChanging) setState(() {}); });
    _assignedScroll.addListener(() {
      if (_assignedScroll.position.pixels >= _assignedScroll.position.maxScrollExtent - 300) _loadAssigned();
    });
    _reserveScroll.addListener(() {
      if (_reserveScroll.position.pixels >= _reserveScroll.position.maxScrollExtent - 300) _loadReserve();
    });
    _searchCtrl.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 350), () {
        final q = _searchCtrl.text.trim();
        if (q != _q) { _q = q; _refresh(); }
      });
    });
    UploadProgress.instance.addListener(_onUploadChanged);
    _refresh();
  }

  void _onUploadChanged() {
    final up = UploadProgress.instance;
    if (up.phase == _UploadPhase.done && _lastSeenPhase != _UploadPhase.done) {
      _lastSeenPhase = _UploadPhase.done;
      if (mounted) { _refresh(); _snack(up.statusMsg); }
    } else if (up.phase == _UploadPhase.error && _lastSeenPhase != _UploadPhase.error) {
      _lastSeenPhase = _UploadPhase.error;
      if (mounted) _snack(up.errorMsg.isNotEmpty ? up.errorMsg : 'अपलोड विफल', error: true);
    } else if (up.phase == _UploadPhase.idle) {
      _lastSeenPhase = _UploadPhase.idle;
    }
  }

  @override
  void dispose() {
    UploadProgress.instance.removeListener(_onUploadChanged);
    _tabs.dispose();
    _assignedScroll.dispose(); _reserveScroll.dispose();
    _searchCtrl.dispose(); _debounce?.cancel();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────
  void _refresh() {
    _selected.clear();
    setState(() {
      _assigned.clear(); _assignedPage = 1; _assignedHasMore = true;
      _reserve.clear();  _reservePage  = 1; _reserveHasMore  = true;
    });
    _loadAssigned(reset: true);
    _loadReserve(reset: true);
  }

  Future<void> _loadAssigned({bool reset = false}) async {
    if (_assignedLoading || (!_assignedHasMore && !reset)) return;
    if (reset && mounted) setState(() { _assigned.clear(); _assignedPage = 1; _assignedHasMore = true; });
    if (mounted) setState(() => _assignedLoading = true);
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.get(
        '/admin/staff?assigned=yes&page=$_assignedPage&limit=$_pageSize&q=${Uri.encodeComponent(_q)}',
        token: token);
      final w = (res['data'] as Map<String, dynamic>?) ?? {};
      final items = (w['data'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      final total = (w['total'] as num?)?.toInt() ?? 0;
      final pages = (w['totalPages'] as num?)?.toInt() ?? 1;
      if (!mounted) return;
      setState(() {
        _assigned.addAll(items); _assignedTotal = total;
        _assignedHasMore = _assignedPage < pages; _assignedPage++;
        _assignedLoading = false;
      });
    } catch (e) {
      if (mounted) { setState(() => _assignedLoading = false); _snack(_msg(e), error: true); }
    }
  }

  Future<void> _loadReserve({bool reset = false}) async {
    if (_reserveLoading || (!_reserveHasMore && !reset)) return;
    if (reset && mounted) setState(() { _reserve.clear(); _reservePage = 1; _reserveHasMore = true; });
    if (mounted) setState(() => _reserveLoading = true);
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.get(
        '/admin/staff?assigned=no&page=$_reservePage&limit=$_pageSize&q=${Uri.encodeComponent(_q)}',
        token: token);
      final w = (res['data'] as Map<String, dynamic>?) ?? {};
      final items = (w['data'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      final total = (w['total'] as num?)?.toInt() ?? 0;
      final pages = (w['totalPages'] as num?)?.toInt() ?? 1;
      if (!mounted) return;
      setState(() {
        _reserve.addAll(items); _reserveTotal = total;
        _reserveHasMore = _reservePage < pages; _reservePage++;
        _reserveLoading = false;
      });
    } catch (e) {
      if (mounted) { setState(() => _reserveLoading = false); _snack(_msg(e), error: true); }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _v(dynamic v) => (v ?? '').toString().trim();
  String _msg(Object e) {
    final s = e.toString();
    return s.contains('Exception:') ? s.split('Exception:').last.trim() : s;
  }
  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: error ? _kError : _kSuccess,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Single CRUD ───────────────────────────────────────────────────────────
  Future<void> _deleteStaff(Map s) async {
    final ok = await _confirm('स्टाफ हटाएं', '"${_v(s['name'])}" को स्थायी रूप से हटाएं?', 'हटाएं');
    if (ok != true) return;
    try {
      await ApiService.delete('/admin/staff/${s['id']}', token: await AuthService.getToken());
      _snack('${_v(s['name'])} हटाया गया'); _refresh();
    } catch (e) { _snack(_msg(e), error: true); }
  }

  Future<void> _removeDuty(Map s) async {
    final ok = await _confirm('ड्यूटी हटाएं',
        '"${_v(s['name'])}" को ${_v(s['centerName'])} से हटाकर रिज़र्व में करें?', 'रिज़र्व करें');
    if (ok != true) return;
    try {
      final token = await AuthService.getToken();
      if (s['dutyId'] != null) {
        await ApiService.delete('/admin/duties/${s['dutyId']}', token: token);
      } else {
        await ApiService.delete('/admin/staff/${s['id']}/duty', token: token);
      }
      _snack('${_v(s['name'])} रिज़र्व में भेजा गया'); _refresh();
    } catch (e) { _snack(_msg(e), error: true); }
  }

  // ── Multi-select actions ──────────────────────────────────────────────────
  void _toggleSelect(int id) {
    setState(() {
      if (_selected.contains(id)) _selected.remove(id);
      else _selected.add(id);
    });
  }

  void _selectAll() {
    setState(() {
      final currentList = _tabs.index == 0 ? _assigned : _reserve;
      for (final s in currentList) _selected.add(s['id'] as int);
    });
  }

  void _clearSelection() => setState(() => _selected.clear());

  Future<void> _bulkDelete() async {
    final count = _selected.length;
    final ok = await _confirm('$count स्टाफ हटाएं',
        'चुने गए $count स्टाफ को स्थायी रूप से हटाएं?\nयह वापस नहीं होगा।', 'हटाएं');
    if (ok != true) return;
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.post('/admin/staff/bulk-delete',
          {'staffIds': _selected.toList()}, token: token);
      final deleted = (res['data']?['deleted'] ?? 0);
      _snack('$deleted स्टाफ हटाए गए');
      _clearSelection(); _refresh();
    } catch (e) { _snack(_msg(e), error: true); }
  }

  Future<void> _bulkUnassign() async {
    final count = _selected.length;
    final ok = await _confirm('$count ड्यूटी हटाएं',
        'चुने गए $count स्टाफ की ड्यूटी हटाएं?', 'हटाएं');
    if (ok != true) return;
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.post('/admin/staff/bulk-unassign',
          {'staffIds': _selected.toList()}, token: token);
      final removed = (res['data']?['removed'] ?? 0);
      _snack('$removed ड्यूटी हटाई गईं');
      _clearSelection(); _refresh();
    } catch (e) { _snack(_msg(e), error: true); }
  }

  void _bulkAssignDialog() {
    final selectedIds = _selected.toList();
    final busCtrl = TextEditingController();
    Map? selectedCenter;
    String centerQ = '';
    Timer? cTimer;
    List centerList = [];
    bool cLoading = false, saving = false, cHasMore = true;
    int cPage = 1;
    final cScroll = ScrollController();

    Future<void> loadCenters({bool reset = false, required StateSetter ss}) async {
      if (cLoading || (!cHasMore && !reset)) return;
      if (reset) { centerList = []; cPage = 1; cHasMore = true; }
      ss(() => cLoading = true);
      try {
        final token = await AuthService.getToken();
        final res = await ApiService.get(
            '/admin/centers/all?q=${Uri.encodeComponent(centerQ)}&page=$cPage&limit=30', token: token);
        final w = (res['data'] as Map<String, dynamic>?) ?? {};
        final data = List<Map>.from((w['data'] as List?) ?? []);
        final total = (w['total'] as num?)?.toInt() ?? 0;
        centerList = [...centerList, ...data];
        cHasMore = centerList.length < total;
        cPage++;
      } catch (_) {}
      ss(() => cLoading = false);
    }

    showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        if (!cScroll.hasListeners) {
          cScroll.addListener(() {
            if (cScroll.position.pixels >= cScroll.position.maxScrollExtent - 150) loadCenters(ss: ss);
          });
        }
        if (centerList.isEmpty && !cLoading) loadCenters(reset: true, ss: ss);

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 500, maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            child: Container(decoration: _dlgDec(), child: Column(children: [
              _dlgHeader('${selectedIds.length} स्टाफ को असाइन करें', Icons.how_to_vote_outlined, ctx),

              Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  // Selected count banner
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: _kPrimary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _kBorder.withOpacity(0.4))),
                    child: Row(children: [
                      const Icon(Icons.people_outline, size: 16, color: _kPrimary),
                      const SizedBox(width: 8),
                      Text('${selectedIds.length} स्टाफ चुने गए',
                          style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                    ]),
                  ),
                  const SizedBox(height: 14),

                  if (selectedCenter != null) ...[
                    _selectedCenterCard(selectedCenter!, onClear: () => ss(() => selectedCenter = null)),
                    const SizedBox(height: 10),
                  ],

                  _sectionLabel('मतदान केंद्र चुनें'), const SizedBox(height: 8),
                  TextField(
                    onChanged: (v) {
                      cTimer?.cancel();
                      cTimer = Timer(const Duration(milliseconds: 350), () {
                        centerQ = v; loadCenters(reset: true, ss: ss);
                      });
                    },
                    style: const TextStyle(color: _kDark, fontSize: 13),
                    decoration: _searchDec('केंद्र, थाना, GP से खोजें...'),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(border: Border.all(color: _kBorder),
                        borderRadius: BorderRadius.circular(10), color: Colors.white),
                    child: cLoading && centerList.isEmpty
                        ? const Center(child: CircularProgressIndicator(color: _kPrimary, strokeWidth: 2))
                        : centerList.isEmpty
                            ? const Center(child: Text('कोई केंद्र नहीं मिला', style: TextStyle(color: _kSubtle, fontSize: 12)))
                            : ListView.builder(
                                controller: cScroll,
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                itemCount: centerList.length + (cHasMore ? 1 : 0),
                                itemBuilder: (_, i) {
                                  if (i >= centerList.length) return const Padding(padding: EdgeInsets.all(10),
                                      child: Center(child: SizedBox(width: 18, height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary))));
                                  final c = centerList[i];
                                  final isSel = selectedCenter?['id'] == c['id'];
                                  final type = '${c['centerType'] ?? 'C'}';
                                  final tc = type == 'A' ? _kError : type == 'B' ? _kAccent : _kInfo;
                                  return InkWell(
                                    onTap: () => ss(() => selectedCenter = Map<String, dynamic>.from(c)),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 120),
                                      margin: const EdgeInsets.fromLTRB(6, 3, 6, 3),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isSel ? _kPrimary.withOpacity(0.08) : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: isSel ? _kPrimary : _kBorder.withOpacity(0.4), width: isSel ? 1.5 : 1),
                                      ),
                                      child: Row(children: [
                                        _typeBadge(type, tc), const SizedBox(width: 10),
                                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Text(_v(c['name']), style: TextStyle(color: isSel ? _kPrimary : _kDark,
                                              fontWeight: FontWeight.w700, fontSize: 13),
                                              maxLines: 1, overflow: TextOverflow.ellipsis),
                                          const SizedBox(height: 2),
                                          Text('${_v(c['thana'])} • ${_v(c['gpName'])}',
                                              style: const TextStyle(color: _kSubtle, fontSize: 10),
                                              maxLines: 1, overflow: TextOverflow.ellipsis),
                                          if ((c['dutyCount'] ?? 0) > 0)
                                            Text('${c['dutyCount']} स्टाफ असाइन',
                                                style: const TextStyle(color: _kInfo, fontSize: 10, fontWeight: FontWeight.w600)),
                                        ])),
                                        if (isSel) const Icon(Icons.check_circle_rounded, color: _kPrimary, size: 18),
                                      ]),
                                    ),
                                  );
                                }),
                  ),
                  const SizedBox(height: 14),
                  _sectionLabel('बस संख्या (वैकल्पिक)'), const SizedBox(height: 8),
                  TextField(
                    controller: busCtrl,
                    style: const TextStyle(color: _kDark, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'बस नंबर (सभी के लिए)',
                      hintStyle: const TextStyle(color: _kSubtle, fontSize: 12),
                      prefixIcon: const Icon(Icons.directions_bus_outlined, size: 18, color: _kPrimary),
                      filled: true, fillColor: Colors.white, isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kPrimary, width: 2)),
                    ),
                  ),
                ]),
              )),

              Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), child: Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(foregroundColor: _kSubtle, side: const BorderSide(color: _kBorder),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text('रद्द'),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selectedCenter == null ? _kSubtle : _kPrimary,
                    foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: selectedCenter == null || saving ? null : () async {
                    ss(() => saving = true);
                    try {
                      final token = await AuthService.getToken();
                      final res = await ApiService.post('/admin/staff/bulk-assign', {
                        'staffIds': selectedIds, 'centerId': selectedCenter!['id'], 'busNo': busCtrl.text.trim(),
                      }, token: token);
                      if (ctx.mounted) Navigator.pop(ctx);
                      final assigned = (res['data']?['assigned'] ?? 0);
                      _snack('$assigned स्टाफ असाइन किए गए');
                      _clearSelection(); _refresh();
                    } catch (e) { ss(() => saving = false); _snack(_msg(e), error: true); }
                  },
                  child: saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('${selectedIds.length} असाइन करें', style: const TextStyle(fontWeight: FontWeight.w700)),
                )),
              ])),
            ])),
          ),
        );
      }),
    );
  }

  Future<bool?> _confirm(String title, String content, String confirmText) =>
      showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
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
              style: ElevatedButton.styleFrom(backgroundColor: _kError, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: Text(confirmText)),
        ],
      ));

  // ── Single assign dialog ──────────────────────────────────────────────────
  void _showAssignDialog(Map staff) {
    final busCtrl = TextEditingController();
    Map? selectedCenter;
    String centerQ = ''; Timer? cTimer;
    List centerList = []; bool cLoading = false, saving = false, cHasMore = true;
    int cPage = 1; final cScroll = ScrollController();

    Future<void> loadCenters({bool reset = false, required StateSetter ss}) async {
      if (cLoading || (!cHasMore && !reset)) return;
      if (reset) { centerList = []; cPage = 1; cHasMore = true; }
      ss(() => cLoading = true);
      try {
        final token = await AuthService.getToken();
        final res = await ApiService.get(
            '/admin/centers/all?q=${Uri.encodeComponent(centerQ)}&page=$cPage&limit=30', token: token);
        final w = (res['data'] as Map<String, dynamic>?) ?? {};
        final data = List<Map>.from((w['data'] as List?) ?? []);
        final total = (w['total'] as num?)?.toInt() ?? 0;
        centerList = [...centerList, ...data];
        cHasMore = centerList.length < total;
        cPage++;
      } catch (_) {}
      ss(() => cLoading = false);
    }

    showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        if (!cScroll.hasListeners) {
          cScroll.addListener(() {
            if (cScroll.position.pixels >= cScroll.position.maxScrollExtent - 150) loadCenters(ss: ss);
          });
        }
        if (centerList.isEmpty && !cLoading) loadCenters(reset: true, ss: ss);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 500, maxHeight: MediaQuery.of(ctx).size.height * 0.88),
            child: Container(decoration: _dlgDec(), child: Column(children: [
              _dlgHeader('ड्यूटी असाइन करें', Icons.how_to_vote_outlined, ctx),
              Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _staffInfoCard(staff), const SizedBox(height: 16),
                  if (selectedCenter != null) ...[
                    _selectedCenterCard(selectedCenter!, onClear: () => ss(() => selectedCenter = null)),
                    const SizedBox(height: 10),
                  ],
                  _sectionLabel('मतदान केंद्र चुनें'), const SizedBox(height: 8),
                  TextField(
                    onChanged: (v) { cTimer?.cancel(); cTimer = Timer(const Duration(milliseconds: 350), () { centerQ = v; loadCenters(reset: true, ss: ss); }); },
                    style: const TextStyle(color: _kDark, fontSize: 13),
                    decoration: _searchDec('केंद्र, थाना, GP से खोजें...'),
                  ),
                  const SizedBox(height: 8),
                  Container(height: 220, decoration: BoxDecoration(border: Border.all(color: _kBorder),
                      borderRadius: BorderRadius.circular(10), color: Colors.white),
                    child: cLoading && centerList.isEmpty
                        ? const Center(child: CircularProgressIndicator(color: _kPrimary, strokeWidth: 2))
                        : centerList.isEmpty
                            ? const Center(child: Text('कोई केंद्र नहीं मिला', style: TextStyle(color: _kSubtle, fontSize: 12)))
                            : ListView.builder(
                                controller: cScroll,
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                itemCount: centerList.length + (cHasMore ? 1 : 0),
                                itemBuilder: (_, i) {
                                  if (i >= centerList.length) return const Padding(padding: EdgeInsets.all(10),
                                      child: Center(child: SizedBox(width: 18, height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary))));
                                  final c = centerList[i];
                                  final isSel = selectedCenter?['id'] == c['id'];
                                  final type = '${c['centerType'] ?? 'C'}';
                                  final tc = type == 'A' ? _kError : type == 'B' ? _kAccent : _kInfo;
                                  return InkWell(
                                    onTap: () => ss(() => selectedCenter = Map<String, dynamic>.from(c)),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 120),
                                      margin: const EdgeInsets.fromLTRB(6, 3, 6, 3),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isSel ? _kPrimary.withOpacity(0.08) : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: isSel ? _kPrimary : _kBorder.withOpacity(0.4), width: isSel ? 1.5 : 1),
                                      ),
                                      child: Row(children: [
                                        _typeBadge(type, tc), const SizedBox(width: 10),
                                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Text(_v(c['name']), style: TextStyle(color: isSel ? _kPrimary : _kDark,
                                              fontWeight: FontWeight.w700, fontSize: 13),
                                              maxLines: 1, overflow: TextOverflow.ellipsis),
                                          const SizedBox(height: 2),
                                          Text('${_v(c['thana'])} • ${_v(c['gpName'])}',
                                              style: const TextStyle(color: _kSubtle, fontSize: 10),
                                              maxLines: 1, overflow: TextOverflow.ellipsis),
                                          if ((c['dutyCount'] ?? 0) > 0)
                                            Text('${c['dutyCount']} स्टाफ असाइन',
                                                style: const TextStyle(color: _kInfo, fontSize: 10, fontWeight: FontWeight.w600)),
                                        ])),
                                        if (isSel) const Icon(Icons.check_circle_rounded, color: _kPrimary, size: 18),
                                      ]),
                                    ),
                                  );
                                }),
                  ),
                  const SizedBox(height: 14),
                  _sectionLabel('बस संख्या (वैकल्पिक)'), const SizedBox(height: 8),
                  TextField(controller: busCtrl, style: const TextStyle(color: _kDark, fontSize: 13),
                    decoration: InputDecoration(hintText: 'बस नंबर', hintStyle: const TextStyle(color: _kSubtle, fontSize: 12),
                      prefixIcon: const Icon(Icons.directions_bus_outlined, size: 18, color: _kPrimary),
                      filled: true, fillColor: Colors.white, isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kPrimary, width: 2))),
                  ),
                ]),
              )),
              Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), child: Row(children: [
                Expanded(child: OutlinedButton(onPressed: saving ? null : () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(foregroundColor: _kSubtle, side: const BorderSide(color: _kBorder),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: const Text('रद्द'))),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: selectedCenter == null ? _kSubtle : _kPrimary,
                      foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: selectedCenter == null || saving ? null : () async {
                    ss(() => saving = true);
                    try {
                      await ApiService.post('/admin/duties', {'staffId': staff['id'],
                          'centerId': selectedCenter!['id'], 'busNo': busCtrl.text.trim()},
                          token: await AuthService.getToken());
                      if (ctx.mounted) Navigator.pop(ctx);
                      _snack('${_v(staff['name'])} असाइन किया गया'); _refresh();
                    } catch (e) { ss(() => saving = false); _snack(_msg(e), error: true); }
                  },
                  child: saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('ड्यूटी असाइन करें', style: TextStyle(fontWeight: FontWeight.w700)),
                )),
              ])),
            ])),
          ),
        );
      }),
    );
  }

  // ── Edit dialog ───────────────────────────────────────────────────────────
  void _showEditDialog(Map s) {
    final nc = TextEditingController(text: _v(s['name']));
    final pc = TextEditingController(text: _v(s['pno']));
    final mc = TextEditingController(text: _v(s['mobile']));
    final tc = TextEditingController(text: _v(s['thana']));
    final rc = TextEditingController(text: _v(s['rank']));
    bool saving = false; final fk = GlobalKey<FormState>();
    showDialog(context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460),
          child: Container(decoration: _dlgDec(), child: Column(mainAxisSize: MainAxisSize.min, children: [
            _dlgHeader('स्टाफ संपादित करें', Icons.edit_outlined, ctx),
            Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Form(key: fk, child: Column(children: [
                _field(nc, 'पूरा नाम *', Icons.person_outline, req: true),
                _field(pc, 'PNO *', Icons.badge_outlined, req: true),
                _field(mc, 'मोबाइल', Icons.phone_outlined, type: TextInputType.phone),
                _field(tc, 'थाना', Icons.local_police_outlined),
                _field(rc, 'पद/रैंक', Icons.military_tech_outlined),
              ])))),
            _dlgActions(ctx, saving, onSave: () async {
              if (!fk.currentState!.validate()) return;
              ss(() => saving = true);
              try {
                await ApiService.put('/admin/staff/${s['id']}',
                    {'name': nc.text.trim(), 'pno': pc.text.trim(), 'mobile': mc.text.trim(),
                     'thana': tc.text.trim(), 'rank': rc.text.trim()},
                    token: await AuthService.getToken());
                if (ctx.mounted) Navigator.pop(ctx);
                _snack('स्टाफ अपडेट किया गया'); _refresh();
              } catch (e) { ss(() => saving = false); _snack(_msg(e), error: true); }
            }),
          ]))),
      )));
  }

  // ── Add dialog ────────────────────────────────────────────────────────────
  void _showAddDialog() {
    final pc = TextEditingController(); final nc = TextEditingController();
    final mc = TextEditingController(); final tc = TextEditingController();
    final dc = TextEditingController(); final rc = TextEditingController();
    bool saving = false; final fk = GlobalKey<FormState>();
    showDialog(context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460),
          child: Container(decoration: _dlgDec(), child: Column(mainAxisSize: MainAxisSize.min, children: [
            _dlgHeader('स्टाफ जोड़ें', Icons.person_add_outlined, ctx),
            Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Form(key: fk, child: Column(children: [
                _field(pc, 'PNO *', Icons.badge_outlined, req: true),
                _field(nc, 'पूरा नाम *', Icons.person_outline, req: true),
                _field(mc, 'मोबाइल', Icons.phone_outlined, type: TextInputType.phone),
                _field(tc, 'थाना', Icons.local_police_outlined),
                _field(dc, 'जिला', Icons.location_city_outlined),
                _field(rc, 'पद/रैंक', Icons.military_tech_outlined),
              ])))),
            _dlgActions(ctx, saving, saveLabel: 'जोड़ें', onSave: () async {
              if (!fk.currentState!.validate()) return;
              ss(() => saving = true);
              try {
                await ApiService.post('/admin/staff',
                    {'pno': pc.text.trim(), 'name': nc.text.trim(), 'mobile': mc.text.trim(),
                     'thana': tc.text.trim(), 'district': dc.text.trim(), 'rank': rc.text.trim()},
                    token: await AuthService.getToken());
                if (ctx.mounted) Navigator.pop(ctx);
                _snack('${nc.text} जोड़ा गया'); _refresh();
              } catch (e) { ss(() => saving = false); _snack(_msg(e), error: true); }
            }),
          ]))),
      )));
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BACKGROUND SSE UPLOAD
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _startBackgroundUpload(List<Map<String, dynamic>> toUpload) async {
    final up = UploadProgress.instance;
    up.update(p: _UploadPhase.uploading, t: toUpload.length, pp: 0, hp: 0, ip: 0, a: 0, msg: 'सर्वर पर भेज रहे हैं...');
    http.Client? client;
    try {
      final token = await AuthService.getToken();
      final uri = Uri.parse('${AppConstants.baseUrl}/admin/staff/bulk');
      final req = http.Request('POST', uri)
        ..headers['Content-Type']  = 'application/json'
        ..headers['Accept']        = 'text/event-stream'
        ..headers['Cache-Control'] = 'no-cache';
      if (token != null) req.headers['Authorization'] = 'Bearer $token';
      req.body = jsonEncode({'staff': toUpload});

      client = http.Client();
      final resp = await client.send(req);
      if (resp.statusCode != 200) throw Exception('Server error ${resp.statusCode}');

      String buf = '';
      await for (final raw in resp.stream.transform(utf8.decoder)) {
        buf += raw;
        while (buf.contains('\n')) {
          final idx  = buf.indexOf('\n');
          final line = buf.substring(0, idx).trim();
          buf        = buf.substring(idx + 1);
          if (!line.startsWith('data:')) continue;
          final js = line.substring(5).trim();
          if (js.isEmpty) continue;
          Map<String, dynamic> data;
          try { data = jsonDecode(js) as Map<String, dynamic>; } catch (_) { continue; }

          final phase = data['phase'] as String? ?? '';
          final pct   = (data['pct']  as num?)?.toDouble() ?? 0;

          if (phase == 'parse') {
            up.update(p: _UploadPhase.uploading, pp: (pct / 100.0).clamp(0, 1),
                msg: data['msg'] as String? ?? '...');
          } else if (phase == 'hash') {
            up.update(pp: 1.0, hp: ((pct - 25.0) / 30.0).clamp(0, 1),
                msg: data['msg'] as String? ?? '...');
          } else if (phase == 'insert') {
            up.update(pp: 1.0, hp: 1.0,
                ip: ((pct - 55.0) / 43.0).clamp(0, 1),
                a: (data['added'] as num?)?.toInt() ?? 0,
                t: (data['total'] as num?)?.toInt() ?? toUpload.length,
                msg: '${data['added'] ?? 0}/${data['total'] ?? toUpload.length} rows');
          } else if (phase == 'done') {
            final added   = (data['added']   as num?)?.toInt() ?? 0;
            final skipped = (data['skipped'] as List?)?.length ?? 0;
            up.update(p: _UploadPhase.done, pp: 1.0, hp: 1.0, ip: 1.0, a: added,
                msg: '$added जोड़े गए, $skipped छोड़े गए');
            client.close(); return;
          } else if (phase == 'error') {
            throw Exception(data['message'] as String? ?? 'Server error');
          }
        }
      }
    } catch (e) {
      client?.close();
      UploadProgress.instance.update(p: _UploadPhase.error, msg: _msg(e), err: _msg(e));
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  EXCEL UPLOAD
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _pickExcel() async {
    if (mounted) setState(() => _excelLoading = true);
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls'], withData: true);
    } catch (e) {
      if (mounted) setState(() => _excelLoading = false);
      _snack('File picker: ${_msg(e)}', error: true); return;
    }
    if (result == null || result.files.isEmpty) { if (mounted) setState(() => _excelLoading = false); return; }
    final bytes = result.files.single.bytes;
    if (bytes == null || bytes.isEmpty) { if (mounted) setState(() => _excelLoading = false); _snack('फ़ाइल त्रुटि', error: true); return; }

    UploadProgress.instance.update(p: _UploadPhase.parsing, msg: 'Excel पार्स हो रही है...', pp: 0.1, hp: 0, ip: 0, a: 0, t: 0);
    if (mounted) setState(() => _excelLoading = false);
    await Future.delayed(const Duration(milliseconds: 16));

    ex.Excel excel;
    try { excel = ex.Excel.decodeBytes(bytes); }
    catch (e) { UploadProgress.instance.reset(); _snack('Excel त्रुटि: ${_msg(e)}', error: true); return; }

    if (excel.tables.isEmpty) { UploadProgress.instance.reset(); _snack('कोई शीट नहीं', error: true); return; }

    final sheetNames = excel.tables.keys.toList();
    String? chosen = sheetNames.length == 1 ? sheetNames.first : await _pickSheet(sheetNames);
    if (chosen == null || !mounted) { UploadProgress.instance.reset(); return; }

    final sheet = excel.tables[chosen]!;
    if (sheet.rows.isEmpty) { UploadProgress.instance.reset(); _snack('शीट खाली', error: true); return; }

    String cs(int ri, int ci) {
      if (ri >= sheet.rows.length) return '';
      final row = sheet.rows[ri];
      if (ci >= row.length) return '';
      return (row[ci]?.value?.toString() ?? '').trim();
    }

    int hRow = -1; int? iPno, iName, iMob, iThana, iDist, iRank;
    for (int ri = 0; ri < sheet.rows.length.clamp(0, 5); ri++) {
      final vals = sheet.rows[ri].map((c) => (c?.value?.toString() ?? '').trim().toLowerCase()).toList();
      int? p, n, m, t, d, r;
      for (int ci = 0; ci < vals.length; ci++) {
        final h = vals[ci];
        if (p == null && (h.contains('pno') || h.contains('p.no'))) p = ci;
        if (n == null && (h.contains('name') || h.contains('नाम'))) n = ci;
        if (m == null && (h.contains('mobile') || h.contains('mob') || h.contains('phone'))) m = ci;
        if (t == null && (h.contains('thana') || h.contains('थाना') || h == 'ps')) t = ci;
        if (d == null && (h.contains('district') || h.contains('dist') || h.contains('जिला'))) d = ci;
        if (r == null && (h.contains('rank') || h.contains('post') || h.contains('पद'))) r = ci;
      }
      if (p != null || n != null) { hRow = ri; iPno = p; iName = n; iMob = m; iThana = t; iDist = d; iRank = r; break; }
    }
    final dataStart = hRow >= 0 ? hRow + 1 : 0;
    iPno ??= 0; iName ??= 1; iMob ??= 2; iThana ??= 3; iDist ??= 4; iRank ??= 5;

    final preview = <Map<String, dynamic>>[];
    const chunk = 500;
    final totalRows = sheet.rows.length - dataStart;
    UploadProgress.instance.update(msg: 'Rows पढ़ रहे हैं...', pp: 0.2, t: totalRows);

    for (int ri = dataStart; ri < sheet.rows.length; ri += chunk) {
      final end = (ri + chunk).clamp(0, sheet.rows.length);
      for (int r = ri; r < end; r++) {
        final row = sheet.rows[r];
        if (row.every((c) => c == null || (c.value?.toString().trim().isEmpty ?? true))) continue;
        final pno = cs(r, iPno!); final name = cs(r, iName!);
        if (pno.isEmpty && name.isEmpty) continue;
        preview.add({'pno': pno, 'name': name, 'mobile': cs(r, iMob!),
            'thana': cs(r, iThana!), 'district': cs(r, iDist!), 'rank': cs(r, iRank!), '_row': r + 1});
      }
      await Future.delayed(Duration.zero);
      UploadProgress.instance.update(pp: (0.2 + ((end - dataStart) / totalRows.clamp(1, 999999)) * 0.8).clamp(0, 1),
          a: preview.length, msg: '${preview.length} rows मिले...');
    }

    UploadProgress.instance.reset();
    if (preview.isEmpty) { _snack('कोई डेटा नहीं', error: true); return; }
    if (!mounted) return;
    _showExcelPreview(preview);
  }

  Future<String?> _pickSheet(List<String> names) => showDialog<String>(
    context: context, builder: (ctx) => AlertDialog(
      backgroundColor: _kBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _kBorder)),
      title: const Text('शीट चुनें', style: TextStyle(color: _kDark, fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min,
          children: names.map((n) => ListTile(title: Text(n, style: const TextStyle(color: _kDark)),
              trailing: const Icon(Icons.chevron_right, color: _kSubtle), onTap: () => Navigator.pop(ctx, n))).toList()),
    ));

  void _showExcelPreview(List<Map<String, dynamic>> initial) {
    final allRows = List<Map<String, dynamic>>.from(initial);
    final workRows = List<Map<String, dynamic>>.from(initial);
    String previewQ = ''; int previewPage = 1; const ppSize = 50;
    final psCtrl = TextEditingController(); Timer? pdebounce;

    showDialog(context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        final filtered = previewQ.isEmpty ? workRows : workRows.where((r) {
          final q = previewQ.toLowerCase();
          return (r['name'] as String? ?? '').toLowerCase().contains(q)
              || (r['pno'] as String? ?? '').toLowerCase().contains(q)
              || (r['thana'] as String? ?? '').toLowerCase().contains(q);
        }).toList();
        final totalPages = ((filtered.length - 1) ~/ ppSize) + 1;
        final sp = previewPage.clamp(1, totalPages.clamp(1, 9999));
        final ps = (sp - 1) * ppSize;
        final pe = (ps + ppSize).clamp(0, filtered.length);
        final pageRows = filtered.sublist(ps, pe);
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
                _pill('${workRows.length - valid} त्रुटि', _kError),
                const Spacer(),
                const Icon(Icons.touch_app_outlined, size: 11, color: _kSubtle), const SizedBox(width: 3),
                const Text('× से हटाएं', style: TextStyle(color: _kSubtle, fontSize: 10)),
              ])),
              Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                child: TextField(controller: psCtrl, style: const TextStyle(color: _kDark, fontSize: 13),
                  onChanged: (v) { pdebounce?.cancel(); pdebounce = Timer(const Duration(milliseconds: 250), () { ss(() { previewQ = v.trim(); previewPage = 1; }); }); },
                  decoration: _searchDec('नाम, PNO, थाना से खोजें...',
                    onClear: previewQ.isNotEmpty ? () { psCtrl.clear(); ss(() { previewQ = ''; previewPage = 1; }); } : null))),
              Flexible(child: pageRows.isEmpty
                  ? Padding(padding: const EdgeInsets.all(24), child: Text('कोई row नहीं', style: const TextStyle(color: _kSubtle), textAlign: TextAlign.center))
                  : ListView.builder(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: pageRows.length, itemBuilder: (_, i) {
                      final r = pageRows[i];
                      final isOk = (r['pno'] as String? ?? '').isNotEmpty && (r['name'] as String? ?? '').isNotEmpty;
                      return Container(margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(color: isOk ? Colors.white : _kError.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: isOk ? _kBorder.withOpacity(0.4) : _kError.withOpacity(0.35))),
                        child: Row(children: [
                          Container(width: 36, alignment: Alignment.center, padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(color: isOk ? _kSurface.withOpacity(0.6) : _kError.withOpacity(0.06),
                                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(9), bottomLeft: Radius.circular(9))),
                              child: Text('${r['_row']}', style: TextStyle(color: isOk ? _kSubtle : _kError, fontSize: 10, fontWeight: FontWeight.w700))),
                          Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text((r['name'] as String).isNotEmpty ? r['name'] as String : '⚠ नाम आवश्यक',
                                  style: TextStyle(color: (r['name'] as String).isNotEmpty ? _kDark : _kError, fontWeight: FontWeight.w700, fontSize: 13)),
                              const SizedBox(height: 3),
                              Wrap(spacing: 8, runSpacing: 2, children: [
                                _miniTag(Icons.badge_outlined, (r['pno'] as String).isNotEmpty ? 'PNO: ${r['pno']}' : '⚠ PNO आवश्यक', (r['pno'] as String).isEmpty ? _kError : null),
                                if ((r['mobile'] as String).isNotEmpty) _miniTag(Icons.phone_outlined, r['mobile'] as String, null),
                                if ((r['thana'] as String).isNotEmpty) _miniTag(Icons.local_police_outlined, r['thana'] as String, null),
                              ]),
                            ]))),
                          InkWell(onTap: () => ss(() { workRows.remove(r); final nf = previewQ.isEmpty ? workRows : workRows.where((x) => (x['name'] as String? ?? '').toLowerCase().contains(previewQ.toLowerCase()) || (x['pno'] as String? ?? '').toLowerCase().contains(previewQ.toLowerCase())).toList(); final ntp = ((nf.length - 1) ~/ ppSize).clamp(0, 9999) + 1; if (previewPage > ntp) previewPage = ntp.clamp(1, 9999); }),
                              borderRadius: const BorderRadius.only(topRight: Radius.circular(9), bottomRight: Radius.circular(9)),
                              child: Container(width: 36, height: 52, alignment: Alignment.center, child: const Icon(Icons.close, size: 15, color: _kError))),
                        ]));
                    })),
              if (totalPages > 1)
                Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: _kSurface.withOpacity(0.5), border: Border(top: BorderSide(color: _kBorder.withOpacity(0.3)))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _pageBtn(Icons.chevron_left, sp > 1, () => ss(() => previewPage = sp - 1)),
                    const SizedBox(width: 8),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(color: _kPrimary.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: _kBorder.withOpacity(0.4))),
                        child: Text('$sp / $totalPages  (${filtered.length} rows)', style: const TextStyle(color: _kDark, fontSize: 12, fontWeight: FontWeight.w700))),
                    const SizedBox(width: 8),
                    _pageBtn(Icons.chevron_right, sp < totalPages, () => ss(() => previewPage = sp + 1)),
                  ])),
              Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 16), child: Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(foregroundColor: _kSubtle, side: const BorderSide(color: _kBorder),
                        padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: const Text('रद्द'))),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: valid == 0 ? _kSubtle : _kPrimary,
                      foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: valid == 0 ? null : () {
                    Navigator.pop(ctx);
                    final toUpload = workRows.where((r) => (r['pno'] as String? ?? '').isNotEmpty && (r['name'] as String? ?? '').isNotEmpty)
                        .map((r) { final m = Map<String, dynamic>.from(r)..remove('_row'); return m; }).toList();
                    _startBackgroundUpload(toUpload);
                  },
                  icon: const Icon(Icons.upload, size: 16),
                  label: Text('$valid अपलोड करें'),
                )),
              ])),
            ])),
          ),
        );
      }));
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  STAFF CARD  (with long-press to enter select mode)
  // ══════════════════════════════════════════════════════════════════════════

  Widget _staffCard(Map s, {required bool assigned}) {
    final id = s['id'] as int;
    final isSelected = _selected.contains(id);
    final name = _v(s['name']);
    final initials = name.trim().split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    final avatarColor = assigned ? _kSuccess : _kAccent;

    return RepaintBoundary(
      child: GestureDetector(
        onLongPress: () { HapticFeedback.mediumImpact(); _toggleSelect(id); },
        onTap: _selectMode ? () => _toggleSelect(id) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isSelected ? _kPrimary.withOpacity(0.06) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? _kPrimary : _kBorder.withOpacity(0.4), width: isSelected ? 2 : 1),
            boxShadow: [BoxShadow(color: _kPrimary.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Checkbox or Avatar
              GestureDetector(
                onTap: () => _toggleSelect(id),
                child: AnimatedSwitcher(duration: const Duration(milliseconds: 200),
                  child: _selectMode
                      ? Container(key: const ValueKey('cb'), width: 44, height: 44,
                          decoration: BoxDecoration(shape: BoxShape.circle,
                              color: isSelected ? _kPrimary : Colors.white,
                              border: Border.all(color: isSelected ? _kPrimary : _kBorder, width: 2)),
                          child: Icon(isSelected ? Icons.check : null, color: Colors.white, size: 22))
                      : Container(key: const ValueKey('av'), width: 44, height: 44,
                          decoration: BoxDecoration(shape: BoxShape.circle,
                              color: avatarColor.withOpacity(0.12),
                              border: Border.all(color: avatarColor.withOpacity(0.35))),
                          child: Center(child: Text(initials.isEmpty ? 'S' : initials,
                              style: TextStyle(color: avatarColor, fontWeight: FontWeight.w900,
                                  fontSize: initials.length <= 1 ? 18 : 13)))),
                ),
              ),
              const SizedBox(width: 10),

              // Info
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(name.isNotEmpty ? name : '—',
                      style: const TextStyle(color: _kDark, fontWeight: FontWeight.w700, fontSize: 14),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 4),
                  _badge(assigned ? 'असाइन' : 'रिज़र्व', assigned ? _kSuccess : _kAccent),
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: _kSuccess.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(6), border: Border.all(color: _kSuccess.withOpacity(0.2))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.location_on_outlined, size: 11, color: _kSuccess), const SizedBox(width: 4),
                      Flexible(child: Text(_v(s['centerName']),
                          style: const TextStyle(color: _kSuccess, fontSize: 11, fontWeight: FontWeight.w600),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
                ],
              ])),

              // Action buttons (always visible — not hidden during select mode)
              const SizedBox(width: 4),
              Column(mainAxisSize: MainAxisSize.min, children: [
                _iconBtn(Icons.edit_outlined,  _kInfo,  () => _showEditDialog(s)),
                const SizedBox(height: 4),
                _iconBtn(Icons.delete_outline, _kError, () => _deleteStaff(s)),
                const SizedBox(height: 4),
                _iconBtn(
                  assigned ? Icons.person_remove_outlined : Icons.how_to_vote_outlined,
                  assigned ? _kError : _kPrimary,
                  () => assigned ? _removeDuty(s) : _showAssignDialog(s),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  MULTI-SELECT ACTION BAR
  // ══════════════════════════════════════════════════════════════════════════

  Widget _selectionBar() {
    final isAssignedTab = _tabs.index == 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: _selectMode ? null : 0,
      child: _selectMode
          ? Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _kDark,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: _kDark.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Row(children: [
                // Count
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: _kBorder.withOpacity(0.25), borderRadius: BorderRadius.circular(20)),
                    child: Text('${_selected.length} चुने', style: const TextStyle(color: _kBorder, fontWeight: FontWeight.w800, fontSize: 13))),
                const SizedBox(width: 6),
                // Select all
                _miniActionBtn('सभी', Icons.select_all, Colors.white70, _selectAll),
                const Spacer(),
                // Bulk assign (only on reserve tab)
                if (!isAssignedTab) ...[
                  _miniActionBtn('असाइन', Icons.how_to_vote_outlined, _kBorder, _bulkAssignDialog),
                  const SizedBox(width: 6),
                ],
                // Bulk unassign (only on assigned tab)
                if (isAssignedTab) ...[
                  _miniActionBtn('रिज़र्व', Icons.person_remove_outlined, _kAccent, _bulkUnassign),
                  const SizedBox(width: 6),
                ],
                // Bulk delete
                _miniActionBtn('हटाएं', Icons.delete_outline, _kError, _bulkDelete),
                const SizedBox(width: 6),
                // Cancel
                GestureDetector(onTap: _clearSelection,
                    child: Container(padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.close, size: 16, color: Colors.white70))),
              ]),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _miniActionBtn(String label, IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(onTap: onTap, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.4))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color), const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      ));

  // ══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final totalAll = _assignedTotal + _reserveTotal;

    return Stack(children: [
      Column(children: [
        // Toolbar
        Container(color: _kSurface, padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(children: [
            Expanded(child: TextField(controller: _searchCtrl, style: const TextStyle(color: _kDark, fontSize: 13),
                decoration: _searchDec('नाम, PNO, मोबाइल, थाना खोजें...',
                    onClear: _q.isNotEmpty ? () { _searchCtrl.clear(); _q = ''; _refresh(); } : null))),
            const SizedBox(width: 8),
            _actionBtn(Icons.person_add_outlined, 'जोड़ें', _kPrimary, _showAddDialog),
            const SizedBox(width: 6),
            // Excel button with upload state
            AnimatedBuilder(
              animation: UploadProgress.instance,
              builder: (_, __) {
                final up = UploadProgress.instance;
                if (_excelLoading || up.phase == _UploadPhase.parsing) {
                  return Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                      decoration: BoxDecoration(color: _kDark, borderRadius: BorderRadius.circular(10)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                        SizedBox(width: 6),
                        Text('लोड...', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ]));
                }
                if (up.isActive) {
                  final overall = ((up.parsePct * 0.15) + (up.hashPct * 0.30) + (up.insertPct * 0.55)).clamp(0.0, 1.0);
                  return Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                      decoration: BoxDecoration(color: _kDark, borderRadius: BorderRadius.circular(10)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(value: overall, color: _kBorder, strokeWidth: 2)),
                        const SizedBox(width: 6),
                        Text('${(overall * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ]));
                }
                return _actionBtn(Icons.upload_file_outlined, 'Excel', _kDark, _pickExcel);
              },
            ),
          ]),
        ),

        // Summary chips
        Container(color: _kBg, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(children: [
            _summaryChip('कुल', '$totalAll', _kPrimary), const SizedBox(width: 8),
            _summaryChip('असाइन', '$_assignedTotal', _kSuccess), const SizedBox(width: 8),
            _summaryChip('रिज़र्व', '$_reserveTotal', _kAccent),
            const Spacer(),
            if (_q.isNotEmpty) Text('${_assignedTotal + _reserveTotal} results', style: const TextStyle(color: _kSubtle, fontSize: 11)),
            IconButton(icon: const Icon(Icons.refresh_rounded, size: 18, color: _kSubtle),
                onPressed: _refresh, tooltip: 'रिफ्रेश', padding: EdgeInsets.zero, constraints: const BoxConstraints()),
          ]),
        ),

        // Tab bar
        Container(color: _kBg, child: TabBar(
          controller: _tabs,
          labelColor: _kPrimary, unselectedLabelColor: _kSubtle,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          indicatorColor: _kPrimary, indicatorWeight: 3,
          tabs: [Tab(text: 'असाइन ($_assignedTotal)'), Tab(text: 'रिज़र्व ($_reserveTotal)')],
        )),

        // Selection bar
        _selectionBar(),

        // List
        Expanded(child: TabBarView(controller: _tabs, children: [
          _buildList(items: _assigned, loading: _assignedLoading, hasMore: _assignedHasMore,
              scroll: _assignedScroll, assigned: true,
              emptyMsg: _q.isNotEmpty ? '"$_q" के लिए कोई result नहीं' : 'कोई असाइन स्टाफ नहीं',
              emptyIcon: Icons.how_to_vote_outlined),
          _buildList(items: _reserve, loading: _reserveLoading, hasMore: _reserveHasMore,
              scroll: _reserveScroll, assigned: false,
              emptyMsg: _q.isNotEmpty ? '"$_q" के लिए कोई result नहीं' : 'सभी स्टाफ असाइन हैं!',
              emptyIcon: Icons.badge_outlined),
        ])),
      ]),

      // Floating progress banner
      const UploadProgressBanner(),
    ]);
  }

  Widget _buildList({required List<Map> items, required bool loading, required bool hasMore,
      required ScrollController scroll, required bool assigned, required String emptyMsg, required IconData emptyIcon}) {
    if (items.isEmpty && loading) return const Center(child: CircularProgressIndicator(color: _kPrimary));
    if (items.isEmpty) return _emptyState(emptyMsg, emptyIcon);
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      color: _kPrimary,
      child: Scrollbar(controller: scroll, thumbVisibility: true, thickness: 6, radius: const Radius.circular(3),
        child: ListView.builder(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 100),
          addRepaintBoundaries: false,
          itemCount: items.length + (hasMore ? 1 : 0),
          itemBuilder: (_, i) {
            if (i >= items.length) return const Padding(padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary))));
            return _staffCard(items[i], assigned: assigned);
          }),
      ),
    );
  }

  // ── Widget helpers ────────────────────────────────────────────────────────
  BoxDecoration _dlgDec() => BoxDecoration(color: _kBg, borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _kBorder, width: 1.2),
      boxShadow: [BoxShadow(color: _kPrimary.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 8))]);

  Widget _dlgHeader(String title, IconData icon, BuildContext ctx) => Container(
    padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
    decoration: const BoxDecoration(color: _kDark, borderRadius: BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15))),
    child: Row(children: [
      Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: _kPrimary.withOpacity(0.25), borderRadius: BorderRadius.circular(7)), child: Icon(icon, color: _kBorder, size: 16)),
      const SizedBox(width: 10),
      Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
      IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, color: Colors.white60, size: 20), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
    ]));

  Widget _dlgActions(BuildContext ctx, bool saving, {String saveLabel = 'अपडेट', required VoidCallback onSave}) =>
      Padding(padding: const EdgeInsets.all(20), child: Row(children: [
        Expanded(child: OutlinedButton(onPressed: saving ? null : () => Navigator.pop(ctx),
            style: OutlinedButton.styleFrom(foregroundColor: _kSubtle, side: const BorderSide(color: _kBorder),
                padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('रद्द'))),
        const SizedBox(width: 12),
        Expanded(child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: saving ? null : onSave,
            child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text(saveLabel, style: const TextStyle(fontWeight: FontWeight.w700)))),
      ]));

  Widget _field(TextEditingController c, String label, IconData icon, {bool req = false, TextInputType? type}) =>
      Padding(padding: const EdgeInsets.only(bottom: 10), child: TextFormField(controller: c, keyboardType: type,
        style: const TextStyle(color: _kDark, fontSize: 13),
        decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: _kSubtle, fontSize: 12),
          prefixIcon: Icon(icon, size: 18, color: _kPrimary), filled: true, fillColor: Colors.white, isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kPrimary, width: 2)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kError))),
        validator: req ? (v) => (v?.trim().isEmpty ?? true) ? '${label.replaceAll(' *', '')} आवश्यक' : null : null));

  InputDecoration _searchDec(String hint, {VoidCallback? onClear}) => InputDecoration(
    hintText: hint, hintStyle: const TextStyle(color: _kSubtle, fontSize: 12),
    prefixIcon: const Icon(Icons.search, color: _kSubtle, size: 18),
    suffixIcon: onClear != null ? IconButton(icon: const Icon(Icons.clear, size: 16, color: _kSubtle), onPressed: onClear) : null,
    filled: true, fillColor: Colors.white, isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kPrimary, width: 2)));

  Widget _staffInfoCard(Map s) => Container(padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: _kSurface, borderRadius: BorderRadius.circular(10), border: Border.all(color: _kBorder.withOpacity(0.5))),
    child: Row(children: [
      Container(width: 40, height: 40, decoration: BoxDecoration(shape: BoxShape.circle, color: _kAccent.withOpacity(0.12), border: Border.all(color: _kAccent.withOpacity(0.35))),
          child: Center(child: Text(_v(s['name']).split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join(), style: const TextStyle(color: _kAccent, fontWeight: FontWeight.w800, fontSize: 14)))),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_v(s['name']), style: const TextStyle(color: _kDark, fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 2),
        Row(children: [
          const Icon(Icons.badge_outlined, size: 11, color: _kSubtle), const SizedBox(width: 3),
          Text('PNO: ${_v(s['pno'])}', style: const TextStyle(color: _kSubtle, fontSize: 11)),
          if (_v(s['thana']).isNotEmpty) ...[const SizedBox(width: 8), const Icon(Icons.local_police_outlined, size: 11, color: _kSubtle), const SizedBox(width: 3),
            Flexible(child: Text(_v(s['thana']), style: const TextStyle(color: _kSubtle, fontSize: 11), overflow: TextOverflow.ellipsis))],
        ]),
      ])),
    ]));

  Widget _selectedCenterCard(Map c, {required VoidCallback onClear}) => Container(padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: _kSuccess.withOpacity(0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: _kSuccess.withOpacity(0.3))),
    child: Row(children: [
      const Icon(Icons.check_circle_rounded, color: _kSuccess, size: 18), const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_v(c['name']), style: const TextStyle(color: _kDark, fontWeight: FontWeight.w700, fontSize: 13)),
        Text('${_v(c['thana'])} • ${_v(c['gpName'])}', style: const TextStyle(color: _kSubtle, fontSize: 11)),
      ])),
      GestureDetector(onTap: onClear, child: const Icon(Icons.close, size: 16, color: _kSubtle)),
    ]));

  Widget _sectionLabel(String label) => Row(children: [
    Container(width: 3, height: 14, decoration: BoxDecoration(color: _kPrimary, borderRadius: BorderRadius.circular(2))), const SizedBox(width: 7),
    Text(label, style: const TextStyle(color: _kDark, fontSize: 13, fontWeight: FontWeight.w800))]);

  Widget _typeBadge(String type, Color color) => Container(width: 28, height: 28,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.12), border: Border.all(color: color.withOpacity(0.4))),
      child: Center(child: Text(type, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900))));

  Widget _tag(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 11, color: _kSubtle), const SizedBox(width: 3),
    Text(text, style: const TextStyle(color: _kSubtle, fontSize: 11, fontWeight: FontWeight.w500))]);

  Widget _miniTag(IconData icon, String text, Color? color) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 10, color: color ?? _kSubtle), const SizedBox(width: 2),
    Text(text, style: TextStyle(color: color ?? _kSubtle, fontSize: 10))]);

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(7), border: Border.all(color: color.withOpacity(0.3))),
    child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)));

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.3))),
    child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)));

  Widget _summaryChip(String label, String count, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.25))),
    child: RichText(text: TextSpan(children: [
      TextSpan(text: '$count ', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900)),
      TextSpan(text: label, style: const TextStyle(color: _kSubtle, fontSize: 11))])));

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) =>
      GestureDetector(onTap: onTap, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 14), const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))])));

  Widget _iconBtn(IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(onTap: onTap, child: Container(width: 34, height: 34,
        decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.25))),
        child: Icon(icon, size: 16, color: color)));

  Widget _emptyState(String msg, IconData icon) => Center(child: Padding(padding: const EdgeInsets.all(40),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 52, color: _kSubtle.withOpacity(0.4)), const SizedBox(height: 14),
      Text(msg, style: const TextStyle(color: _kSubtle, fontSize: 13), textAlign: TextAlign.center)])));

  Widget _pageBtn(IconData icon, bool enabled, VoidCallback onTap) =>
      GestureDetector(onTap: enabled ? onTap : null, child: Container(width: 32, height: 32,
        decoration: BoxDecoration(color: enabled ? _kPrimary.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8), border: Border.all(color: enabled ? _kBorder : Colors.grey.withOpacity(0.3))),
        child: Icon(icon, size: 18, color: enabled ? _kPrimary : Colors.grey)));
}

