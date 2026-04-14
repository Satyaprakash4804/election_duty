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

// ── Palette ───────────────────────────────────────────────────────────────────
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
const _kArmed   = Color(0xFF1B5E20);   // dark green for सशस्त्र
const _kUnarmed = Color(0xFF37474F);   // blue-grey for निःशस्त्र

const _pageSize = 50;

const _kAllRanks = [
  'All', 'SP', 'ASP', 'DSP', 'Inspector', 'SI', 'ASI', 'Head Constable', 'Constable',
];

// Required Excel/CSV headers hint
const _kRequiredHeaders = [
  {'col': 'pno',      'hi': 'PNO / बैज नंबर',   'req': true},
  {'col': 'name',     'hi': 'नाम',               'req': true},
  {'col': 'mobile',   'hi': 'मोबाइल',             'req': false},
  {'col': 'thana',    'hi': 'थाना',               'req': false},
  {'col': 'district', 'hi': 'जिला',               'req': false},
  {'col': 'rank',     'hi': 'पद / रैंक',           'req': false},
  {'col': 'sastra',   'hi': 'सशस्त्र (1/yes/हाँ)', 'req': false},
];

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
        final overall = ((up.parsePct * 0.15) + (up.hashPct * 0.30) +
            (up.insertPct * 0.55)).clamp(0.0, 1.0);

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
              child: Column(mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  SizedBox(width: 24, height: 24,
                    child: isErr
                        ? const Icon(Icons.error_outline, color: _kError, size: 20)
                        : isDone
                            ? const Icon(Icons.check_circle_outline,
                                color: _kSuccess, size: 20)
                            : _SpinIcon(color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      isErr ? 'अपलोड विफल'
                          : isDone ? 'अपलोड पूर्ण!'
                          : 'बल्क अपलोड',
                      style: TextStyle(color: color,
                          fontWeight: FontWeight.w800, fontSize: 13)),
                    Text(up.statusMsg,
                        style: const TextStyle(color: Colors.white60, fontSize: 11),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
                  if (up.total > 0)
                    Text('${up.added}/${up.total}',
                        style: TextStyle(color: color,
                            fontWeight: FontWeight.w900, fontSize: 12)),
                  const SizedBox(width: 8),
                  if (isDone || isErr)
                    GestureDetector(
                        onTap: UploadProgress.instance.reset,
                        child: const Icon(Icons.close,
                            color: Colors.white54, size: 18)),
                ]),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
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
                  ),
                ),
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
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 9)),
        const Spacer(),
        Text('${(pct * 100).round()}%',
            style: TextStyle(color: color, fontSize: 9,
                fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 2),
      ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: pct, minHeight: 3,
          backgroundColor: color.withOpacity(0.15),
          valueColor: AlwaysStoppedAnimation(
              pct >= 1.0 ? _kSuccess : color)),
      ),
    ]),
  );
}

class _SpinIcon extends StatefulWidget {
  final Color color;
  const _SpinIcon({required this.color});
  @override
  State<_SpinIcon> createState() => _SpinIconState();
}

class _SpinIconState extends State<_SpinIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(seconds: 1))
      ..repeat();
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => RotationTransition(
      turns: _c,
      child: Icon(Icons.upload_rounded, color: widget.color, size: 18));
}

// ══════════════════════════════════════════════════════════════════════════════
//  STAFF PAGE
// ══════════════════════════════════════════════════════════════════════════════

class StaffPage extends StatefulWidget {
  const StaffPage({super.key});
  @override
  State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  // Filters
  String  _selectedRank  = 'All';
  String  _armedFilter   = 'All'; // 'All' | 'Armed' | 'Unarmed'

  // Lists
  final List<Map> _assigned = [];
  int  _assignedPage = 1, _assignedTotal = 0;
  bool _assignedLoading = false, _assignedHasMore = true;
  final ScrollController _assignedScroll = ScrollController();

  final List<Map> _reserve  = [];
  int  _reservePage = 1, _reserveTotal = 0;
  bool _reserveLoading = false, _reserveHasMore = true;
  final ScrollController _reserveScroll = ScrollController();

  final Set<int> _selected = {};
  bool get _selectMode => _selected.isNotEmpty;

  String _q = '';
  Timer? _debounce;
  final _searchCtrl = TextEditingController();

  bool _fileLoading = false;
  _UploadPhase _lastSeenPhase = _UploadPhase.idle;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)
      ..addListener(() { if (!_tabs.indexIsChanging) setState(() {}); });
    _assignedScroll.addListener(() {
      if (_assignedScroll.position.pixels >=
          _assignedScroll.position.maxScrollExtent - 300) _loadAssigned();
    });
    _reserveScroll.addListener(() {
      if (_reserveScroll.position.pixels >=
          _reserveScroll.position.maxScrollExtent - 300) _loadReserve();
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
    if (up.phase == _UploadPhase.done &&
        _lastSeenPhase != _UploadPhase.done) {
      _lastSeenPhase = _UploadPhase.done;
      if (mounted) { _refresh(); _snack(up.statusMsg); }
    } else if (up.phase == _UploadPhase.error &&
        _lastSeenPhase != _UploadPhase.error) {
      _lastSeenPhase = _UploadPhase.error;
      if (mounted)
        _snack(
            up.errorMsg.isNotEmpty ? up.errorMsg : 'अपलोड विफल',
            error: true);
    } else if (up.phase == _UploadPhase.idle) {
      _lastSeenPhase = _UploadPhase.idle;
    }
  }

  @override
  void dispose() {
    UploadProgress.instance.removeListener(_onUploadChanged);
    _tabs.dispose();
    _assignedScroll.dispose();
    _reserveScroll.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── Query helpers ─────────────────────────────────────────────────────────
  String get _rankParam =>
      _selectedRank == 'All' ? '' : _selectedRank;

  String get _armedParam {
    if (_armedFilter == 'Armed')   return 'yes';
    if (_armedFilter == 'Unarmed') return 'no';
    return '';
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
    if (reset && mounted)
      setState(() {
        _assigned.clear(); _assignedPage = 1; _assignedHasMore = true;
      });
    if (mounted) setState(() => _assignedLoading = true);
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.get(
        '/admin/staff?assigned=yes&page=$_assignedPage&limit=$_pageSize'
        '&q=${Uri.encodeComponent(_q)}'
        '&rank=${Uri.encodeComponent(_rankParam)}'
        '&armed=${Uri.encodeComponent(_armedParam)}',
        token: token,
      );
      final w     = (res['data'] as Map<String, dynamic>?) ?? {};
      final items = (w['data'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      final total = (w['total'] as num?)?.toInt() ?? 0;
      final pages = (w['totalPages'] as num?)?.toInt() ?? 1;
      if (!mounted) return;
      setState(() {
        _assigned.addAll(items);
        _assignedTotal   = total;
        _assignedHasMore = _assignedPage < pages;
        _assignedPage++;
        _assignedLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _assignedLoading = false);
        _snack(_msg(e), error: true);
      }
    }
  }

  Future<void> _loadReserve({bool reset = false}) async {
    if (_reserveLoading || (!_reserveHasMore && !reset)) return;
    if (reset && mounted)
      setState(() {
        _reserve.clear(); _reservePage = 1; _reserveHasMore = true;
      });
    if (mounted) setState(() => _reserveLoading = true);
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.get(
        '/admin/staff?assigned=no&page=$_reservePage&limit=$_pageSize'
        '&q=${Uri.encodeComponent(_q)}'
        '&rank=${Uri.encodeComponent(_rankParam)}'
        '&armed=${Uri.encodeComponent(_armedParam)}',
        token: token,
      );
      final w     = (res['data'] as Map<String, dynamic>?) ?? {};
      final items = (w['data'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      final total = (w['total'] as num?)?.toInt() ?? 0;
      final pages = (w['totalPages'] as num?)?.toInt() ?? 1;
      if (!mounted) return;
      setState(() {
        _reserve.addAll(items);
        _reserveTotal   = total;
        _reserveHasMore = _reservePage < pages;
        _reservePage++;
        _reserveLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _reserveLoading = false);
        _snack(_msg(e), error: true);
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _v(dynamic v) => (v ?? '').toString().trim();
  String _msg(Object e) {
    final s = e.toString();
    return s.contains('Exception:')
        ? s.split('Exception:').last.trim()
        : s;
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? _kError : _kSuccess,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
    ));
  }

  bool _isArmed(Map s) => s['isArmed'] == true || s['isArmed'] == 1;

  // ── CRUD ──────────────────────────────────────────────────────────────────
  Future<void> _deleteStaff(Map s) async {
    final ok = await _confirm(
        'स्टाफ हटाएं',
        '"${_v(s['name'])}" को स्थायी रूप से हटाएं?',
        'हटाएं');
    if (ok != true) return;
    try {
      await ApiService.delete('/admin/staff/${s['id']}',
          token: await AuthService.getToken());
      _snack('${_v(s['name'])} हटाया गया');
      _refresh();
    } catch (e) { _snack(_msg(e), error: true); }
  }

  Future<void> _removeDuty(Map s) async {
    final type = _v(s['assignType']);
    if (type != 'booth') {
      _snack('अधिकारी असाइनमेंट संरचना पेज से बदलें', error: true);
      return;
    }
    final ok = await _confirm(
        'ड्यूटी हटाएं',
        '"${_v(s['name'])}" को रिज़र्व में करें?',
        'रिज़र्व करें');
    if (ok != true) return;
    try {
      final token = await AuthService.getToken();
      if (s['dutyId'] != null) {
        await ApiService.delete('/admin/duties/${s['dutyId']}',
            token: token);
      } else {
        await ApiService.delete('/admin/staff/${s['id']}/duty',
            token: token);
      }
      _snack('${_v(s['name'])} रिज़र्व में भेजा गया');
      _refresh();
    } catch (e) { _snack(_msg(e), error: true); }
  }

  // ── Multi-select ──────────────────────────────────────────────────────────
  void _toggleSelect(int id) => setState(() {
    if (_selected.contains(id)) _selected.remove(id);
    else _selected.add(id);
  });

  void _selectAll() {
    setState(() {
      final l = _tabs.index == 0 ? _assigned : _reserve;
      for (final s in l) _selected.add(s['id'] as int);
    });
  }

  void _clearSelection() => setState(() => _selected.clear());

  Future<void> _bulkDelete() async {
    final count = _selected.length;
    final ok = await _confirm(
        '$count स्टाफ हटाएं',
        '$count स्टाफ को स्थायी रूप से हटाएं?',
        'हटाएं');
    if (ok != true) return;
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.post(
          '/admin/staff/bulk-delete',
          {'staffIds': _selected.toList()},
          token: token);
      _snack('${res['data']?['deleted'] ?? 0} स्टाफ हटाए गए');
      _clearSelection();
      _refresh();
    } catch (e) { _snack(_msg(e), error: true); }
  }

  Future<void> _bulkUnassign() async {
    final currentList = _tabs.index == 0 ? _assigned : _reserve;
    final boothIds = currentList
        .where((s) =>
            _selected.contains(s['id']) &&
            _v(s['assignType']) == 'booth')
        .map<int>((s) => s['id'] as int)
        .toList();
    if (boothIds.isEmpty) {
      _snack('केवल बूथ स्टाफ ही हटाए जा सकते हैं', error: true);
      return;
    }
    final ok = await _confirm(
        '${boothIds.length} ड्यूटी हटाएं',
        '${boothIds.length} बूथ स्टाफ रिज़र्व में जाएंगे।',
        'हटाएं');
    if (ok != true) return;
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.post(
          '/admin/staff/bulk-unassign',
          {'staffIds': boothIds},
          token: token);
      _snack('${res['data']?['removed'] ?? 0} बूथ स्टाफ रिज़र्व में');
      _clearSelection();
      _refresh();
    } catch (e) { _snack(_msg(e), error: true); }
  }

  void _bulkAssignDialog() {
    final selectedIds = _selected.toList();
    final busCtrl     = TextEditingController();
    Map?  selectedCenter;
    String centerQ = '';
    Timer? cTimer;
    List   centerList = [];
    bool   cLoading = false, saving = false, cHasMore = true;
    int    cPage = 1;
    final  cScroll = ScrollController();

    Future<void> loadCenters(
        {bool reset = false, required StateSetter ss}) async {
      if (cLoading || (!cHasMore && !reset)) return;
      if (reset) { centerList = []; cPage = 1; cHasMore = true; }
      ss(() => cLoading = true);
      try {
        final token = await AuthService.getToken();
        final res = await ApiService.get(
            '/admin/centers/all?q=${Uri.encodeComponent(centerQ)}&page=$cPage&limit=30',
            token: token);
        final w    = (res['data'] as Map<String, dynamic>?) ?? {};
        final data = List<Map>.from((w['data'] as List?) ?? []);
        final total = (w['total'] as num?)?.toInt() ?? 0;
        centerList = [...centerList, ...data];
        cHasMore   = centerList.length < total;
        cPage++;
      } catch (_) {}
      ss(() => cLoading = false);
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        if (!cScroll.hasListeners) {
          cScroll.addListener(() {
            if (cScroll.position.pixels >=
                cScroll.position.maxScrollExtent - 150)
              loadCenters(ss: ss);
          });
        }
        if (centerList.isEmpty && !cLoading) loadCenters(reset: true, ss: ss);
        return _AssignDialog(
          title: '${selectedIds.length} स्टाफ को असाइन करें',
          selectedCenter: selectedCenter,
          centerList: centerList,
          cLoading: cLoading,
          cHasMore: cHasMore,
          cScroll: cScroll,
          busCtrl: busCtrl,
          saving: saving,
          onSearchChanged: (v) {
            cTimer?.cancel();
            cTimer = Timer(const Duration(milliseconds: 350), () {
              centerQ = v;
              loadCenters(reset: true, ss: ss);
            });
          },
          onCenterTap: (c) => ss(() => selectedCenter = c),
          onClearCenter: () => ss(() => selectedCenter = null),
          onCancel: () => Navigator.pop(ctx),
          onAssign: selectedCenter == null || saving
              ? null
              : () async {
                  ss(() => saving = true);
                  try {
                    final token = await AuthService.getToken();
                    final res = await ApiService.post(
                        '/admin/staff/bulk-assign',
                        {
                          'staffIds': selectedIds,
                          'centerId': selectedCenter!['id'],
                          'busNo': busCtrl.text.trim(),
                        },
                        token: token);
                    if (ctx.mounted) Navigator.pop(ctx);
                    _snack('${res['data']?['assigned'] ?? 0} स्टाफ असाइन');
                    _clearSelection();
                    _refresh();
                  } catch (e) {
                    ss(() => saving = false);
                    _snack(_msg(e), error: true);
                  }
                },
          assignLabel: '${selectedIds.length} असाइन करें',
        );
      }),
    );
  }

  Future<bool?> _confirm(
          String title, String content, String confirmText) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _kBg,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: _kError, width: 1.2)),
          title: Row(children: [
            const Icon(Icons.warning_amber_rounded,
                color: _kError, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      color: _kError,
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
            ),
          ]),
          content: Text(content,
              style: const TextStyle(
                  color: _kDark, fontSize: 13, height: 1.5)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('रद्द',
                    style: TextStyle(color: _kSubtle))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _kError,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
              child: Text(confirmText),
            ),
          ],
        ),
      );

  // ── Assign single ─────────────────────────────────────────────────────────
  void _showAssignDialog(Map staff) {
    final busCtrl = TextEditingController();
    Map?  selectedCenter;
    String centerQ = '';
    Timer? cTimer;
    List   centerList = [];
    bool   cLoading = false, saving = false, cHasMore = true;
    int    cPage = 1;
    final  cScroll = ScrollController();

    Future<void> loadCenters(
        {bool reset = false, required StateSetter ss}) async {
      if (cLoading || (!cHasMore && !reset)) return;
      if (reset) { centerList = []; cPage = 1; cHasMore = true; }
      ss(() => cLoading = true);
      try {
        final token = await AuthService.getToken();
        final res = await ApiService.get(
            '/admin/centers/all?q=${Uri.encodeComponent(centerQ)}&page=$cPage&limit=30',
            token: token);
        final w    = (res['data'] as Map<String, dynamic>?) ?? {};
        final data = List<Map>.from((w['data'] as List?) ?? []);
        final total = (w['total'] as num?)?.toInt() ?? 0;
        centerList = [...centerList, ...data];
        cHasMore   = centerList.length < total;
        cPage++;
      } catch (_) {}
      ss(() => cLoading = false);
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        if (!cScroll.hasListeners) {
          cScroll.addListener(() {
            if (cScroll.position.pixels >=
                cScroll.position.maxScrollExtent - 150)
              loadCenters(ss: ss);
          });
        }
        if (centerList.isEmpty && !cLoading) loadCenters(reset: true, ss: ss);
        return _AssignDialog(
          title: 'ड्यूटी असाइन करें',
          staffCard: _staffInfoCard(staff),
          selectedCenter: selectedCenter,
          centerList: centerList,
          cLoading: cLoading,
          cHasMore: cHasMore,
          cScroll: cScroll,
          busCtrl: busCtrl,
          saving: saving,
          onSearchChanged: (v) {
            cTimer?.cancel();
            cTimer = Timer(const Duration(milliseconds: 350), () {
              centerQ = v;
              loadCenters(reset: true, ss: ss);
            });
          },
          onCenterTap: (c) => ss(() => selectedCenter = c),
          onClearCenter: () => ss(() => selectedCenter = null),
          onCancel: () => Navigator.pop(ctx),
          onAssign: selectedCenter == null || saving
              ? null
              : () async {
                  ss(() => saving = true);
                  try {
                    await ApiService.post(
                        '/admin/duties',
                        {
                          'staffId': staff['id'],
                          'centerId': selectedCenter!['id'],
                          'busNo': busCtrl.text.trim(),
                        },
                        token: await AuthService.getToken());
                    if (ctx.mounted) Navigator.pop(ctx);
                    _snack('${_v(staff['name'])} असाइन किया गया');
                    _refresh();
                  } catch (e) {
                    ss(() => saving = false);
                    _snack(_msg(e), error: true);
                  }
                },
          assignLabel: 'ड्यूटी असाइन करें',
        );
      }),
    );
  }

  // ── Edit dialog ───────────────────────────────────────────────────────────
  void _showEditDialog(Map s) {
    final nc  = TextEditingController(text: _v(s['name']));
    final pc  = TextEditingController(text: _v(s['pno']));
    final mc  = TextEditingController(text: _v(s['mobile']));
    final tc  = TextEditingController(text: _v(s['thana']));
    final rc  = TextEditingController(text: _v(s['rank']));
    bool isArmed = _isArmed(s);
    bool saving  = false;
    final fk = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            decoration: _dlgDec(),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _dlgHeader('स्टाफ संपादित करें',
                  Icons.edit_outlined, ctx),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Form(
                    key: fk,
                    child: Column(children: [
                      _field(nc, 'पूरा नाम *',
                          Icons.person_outline, req: true),
                      _field(pc, 'PNO *',
                          Icons.badge_outlined, req: true),
                      _field(mc, 'मोबाइल',
                          Icons.phone_outlined,
                          type: TextInputType.phone),
                      _field(tc, 'थाना',
                          Icons.local_police_outlined),
                      _field(rc, 'पद/रैंक',
                          Icons.military_tech_outlined),
                      // Armed toggle
                      _armedToggle(
                        value: isArmed,
                        onChanged: (v) => ss(() => isArmed = v),
                      ),
                    ]),
                  ),
                ),
              ),
              _dlgActions(ctx, saving, onSave: () async {
                if (!fk.currentState!.validate()) return;
                ss(() => saving = true);
                try {
                  await ApiService.put(
                      '/admin/staff/${s['id']}',
                      {
                        'name':    nc.text.trim(),
                        'pno':     pc.text.trim(),
                        'mobile':  mc.text.trim(),
                        'thana':   tc.text.trim(),
                        'rank':    rc.text.trim(),
                        'isArmed': isArmed,
                      },
                      token: await AuthService.getToken());
                  if (ctx.mounted) Navigator.pop(ctx);
                  _snack('स्टाफ अपडेट किया गया');
                  _refresh();
                } catch (e) {
                  ss(() => saving = false);
                  _snack(_msg(e), error: true);
                }
              }),
            ]),
          ),
        ),
      )),
    );
  }

  // ── Add dialog ────────────────────────────────────────────────────────────
  void _showAddDialog() {
    final pc = TextEditingController();
    final nc = TextEditingController();
    final mc = TextEditingController();
    final tc = TextEditingController();
    final dc = TextEditingController();
    final rc = TextEditingController();
    bool isArmed = false;
    bool saving  = false;
    final fk = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            decoration: _dlgDec(),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _dlgHeader('स्टाफ जोड़ें',
                  Icons.person_add_outlined, ctx),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Form(
                    key: fk,
                    child: Column(children: [
                      _field(pc, 'PNO *',
                          Icons.badge_outlined, req: true),
                      _field(nc, 'पूरा नाम *',
                          Icons.person_outline, req: true),
                      _field(mc, 'मोबाइल',
                          Icons.phone_outlined,
                          type: TextInputType.phone),
                      _field(tc, 'थाना',
                          Icons.local_police_outlined),
                      _field(dc, 'जिला',
                          Icons.location_city_outlined),
                      _field(rc, 'पद/रैंक',
                          Icons.military_tech_outlined),
                      _armedToggle(
                        value: isArmed,
                        onChanged: (v) => ss(() => isArmed = v),
                      ),
                    ]),
                  ),
                ),
              ),
              _dlgActions(ctx, saving,
                  saveLabel: 'जोड़ें',
                  onSave: () async {
                if (!fk.currentState!.validate()) return;
                ss(() => saving = true);
                try {
                  await ApiService.post(
                      '/admin/staff',
                      {
                        'pno':     pc.text.trim(),
                        'name':    nc.text.trim(),
                        'mobile':  mc.text.trim(),
                        'thana':   tc.text.trim(),
                        'district': dc.text.trim(),
                        'rank':    rc.text.trim(),
                        'isArmed': isArmed,
                      },
                      token: await AuthService.getToken());
                  if (ctx.mounted) Navigator.pop(ctx);
                  _snack('${nc.text} जोड़ा गया');
                  _refresh();
                } catch (e) {
                  ss(() => saving = false);
                  _snack(_msg(e), error: true);
                }
              }),
            ]),
          ),
        ),
      )),
    );
  }

  // ── Upload helpers ────────────────────────────────────────────────────────

  /// Shows the required headers hint before file picker opens
  Future<bool> _showUploadHint() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            decoration: _dlgDec(),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _dlgHeader('फ़ाइल अपलोड करें',
                  Icons.upload_file_outlined, ctx),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // Format chips
                  Row(children: [
                    _formatChip('Excel', '.xlsx / .xls',
                        Icons.table_chart, _kSuccess),
                    const SizedBox(width: 8),
                    _formatChip('CSV', '.csv',
                        Icons.description_outlined, _kInfo),
                  ]),
                  const SizedBox(height: 14),
                  const Text('आवश्यक कॉलम / Required Columns',
                      style: TextStyle(
                          color: _kDark,
                          fontWeight: FontWeight.w800,
                          fontSize: 13)),
                  const SizedBox(height: 8),
                  // Headers table
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: _kBorder.withOpacity(0.4)),
                    ),
                    child: Column(
                      children: _kRequiredHeaders
                          .asMap()
                          .entries
                          .map((e) {
                        final idx = e.key;
                        final h   = e.value;
                        final req = h['req'] as bool;
                        return Container(
                          decoration: BoxDecoration(
                            color: idx.isEven
                                ? Colors.transparent
                                : _kSurface.withOpacity(0.3),
                            borderRadius: idx == 0
                                ? const BorderRadius.only(
                                    topLeft: Radius.circular(9),
                                    topRight: Radius.circular(9))
                                : idx ==
                                        _kRequiredHeaders.length - 1
                                    ? const BorderRadius.only(
                                        bottomLeft:
                                            Radius.circular(9),
                                        bottomRight:
                                            Radius.circular(9))
                                    : null,
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2C3E50)
                                    .withOpacity(0.08),
                                borderRadius:
                                    BorderRadius.circular(4),
                              ),
                              child: Text(
                                h['col'] as String,
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    color: Color(0xFF2C3E50),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(h['hi'] as String,
                                  style: const TextStyle(
                                      color: _kDark, fontSize: 12)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: req
                                    ? _kError.withOpacity(0.1)
                                    : _kSuccess.withOpacity(0.1),
                                borderRadius:
                                    BorderRadius.circular(4),
                              ),
                              child: Text(
                                req ? 'ज़रूरी' : 'वैकल्पिक',
                                style: TextStyle(
                                    color: req
                                        ? _kError
                                        : _kSuccess,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ]),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // sastra hint
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _kArmed.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _kArmed.withOpacity(0.2)),
                    ),
                    child: Row(children: [
                      Icon(Icons.info_outline,
                          size: 14, color: _kArmed),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'sastra कॉलम में: 1, yes, हाँ, सशस्त्र, armed → सशस्त्र\n'
                          'बाकी सब या खाली → निःशस्त्र',
                          style: TextStyle(
                              color: _kDark, fontSize: 11),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: _kSubtle,
                          side: const BorderSide(color: _kBorder),
                          padding: const EdgeInsets.symmetric(
                              vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(10))),
                      child: const Text('रद्द'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.upload_file, size: 16),
                      label: const Text('फ़ाइल चुनें'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(10))),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
    return result == true;
  }

  Widget _formatChip(
      String format, String ext, IconData icon, Color color) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(format,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 12)),
              Text(ext,
                  style: const TextStyle(
                      color: _kSubtle, fontSize: 10)),
            ]),
          ]),
        ),
      );

  Future<void> _pickFile() async {
    // Show hint first
    final proceed = await _showUploadHint();
    if (!proceed || !mounted) return;

    if (mounted) setState(() => _fileLoading = true);

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        withData: true,
      );
    } catch (e) {
      if (mounted) setState(() => _fileLoading = false);
      _snack('File picker: ${_msg(e)}', error: true);
      return;
    }

    if (result == null || result.files.isEmpty) {
      if (mounted) setState(() => _fileLoading = false);
      return;
    }

    final file  = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) setState(() => _fileLoading = false);
      _snack('फ़ाइल त्रुटि', error: true);
      return;
    }

    if (mounted) setState(() => _fileLoading = false);

    // Route by extension
    final ext = (file.extension ?? '').toLowerCase();
    if (ext == 'csv') {
      await _processCSV(bytes);
    } else {
      await _processExcel(bytes);
    }
  }

  // ── CSV processing ────────────────────────────────────────────────────────
  Future<void> _processCSV(List<int> bytes) async {
    UploadProgress.instance.update(
        p: _UploadPhase.parsing,
        msg: 'CSV पार्स हो रही है...',
        pp: 0.1, hp: 0, ip: 0, a: 0, t: 0);

    await Future.delayed(const Duration(milliseconds: 16));

    String content;
    try {
      content = utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      try {
        content = latin1.decode(bytes);
      } catch (e) {
        UploadProgress.instance.reset();
        _snack('CSV encoding त्रुटि', error: true);
        return;
      }
    }

    // Remove BOM if present
    if (content.startsWith('\uFEFF')) {
      content = content.substring(1);
    }

    final lines = content.split(RegExp(r'\r?\n'));
    if (lines.isEmpty) {
      UploadProgress.instance.reset();
      _snack('CSV खाली है', error: true);
      return;
    }

    // Parse header
    List<String> parseCSVLine(String line) {
      final result = <String>[];
      bool inQuote = false;
      final buf = StringBuffer();
      for (int i = 0; i < line.length; i++) {
        final ch = line[i];
        if (ch == '"') {
          if (inQuote && i + 1 < line.length && line[i + 1] == '"') {
            buf.write('"');
            i++;
          } else {
            inQuote = !inQuote;
          }
        } else if (ch == ',' && !inQuote) {
          result.add(buf.toString().trim());
          buf.clear();
        } else {
          buf.write(ch);
        }
      }
      result.add(buf.toString().trim());
      return result;
    }

    final headers = parseCSVLine(lines.first)
        .map((h) => h.toLowerCase().trim())
        .toList();

    int? iPno, iName, iMob, iThana, iDist, iRank, iArmed;
    for (int ci = 0; ci < headers.length; ci++) {
      final h = headers[ci];
      if (iPno   == null && (h.contains('pno') || h.contains('p.no'))) iPno = ci;
      if (iName  == null && (h.contains('name') || h.contains('नाम'))) iName = ci;
      if (iMob   == null && (h.contains('mobile') || h.contains('mob') || h.contains('phone'))) iMob = ci;
      if (iThana == null && (h.contains('thana') || h.contains('थाना') || h == 'ps')) iThana = ci;
      if (iDist  == null && (h.contains('district') || h.contains('dist') || h.contains('जिला'))) iDist = ci;
      if (iRank  == null && (h.contains('rank') || h.contains('post') || h.contains('पद'))) iRank = ci;
      if (iArmed == null && (h.contains('sastra') || h.contains('armed') || h.contains('weapon') || h.contains('सशस्त्र'))) iArmed = ci;
    }

    iPno  ??= 0; iName ??= 1; iMob   ??= 2;
    iThana ??= 3; iDist  ??= 4; iRank  ??= 5;

    const armedVals = {'1', 'yes', 'हाँ', 'han', 'sastra', 'सशस्त्र', 'armed', 'true'};

    String cell(List<String> row, int? idx) {
      if (idx == null || idx >= row.length) return '';
      return row[idx].trim();
    }

    final preview = <Map<String, dynamic>>[];
    final dataLines = lines.skip(1).toList();
    final total = dataLines.length;

    UploadProgress.instance.update(
        msg: 'Rows पढ़ रहे हैं...', pp: 0.2, t: total);

    for (int ri = 0; ri < dataLines.length; ri++) {
      final line = dataLines[ri].trim();
      if (line.isEmpty) continue;
      final row = parseCSVLine(line);
      final pno  = cell(row, iPno);
      final name = cell(row, iName);
      if (pno.isEmpty && name.isEmpty) continue;

      final armedRaw = iArmed != null
          ? cell(row, iArmed).toLowerCase()
          : '';
      final isArmed = armedVals.contains(armedRaw) ? 1 : 0;

      preview.add({
        'pno':      pno,
        'name':     name,
        'mobile':   cell(row, iMob),
        'thana':    cell(row, iThana),
        'district': cell(row, iDist),
        'rank':     cell(row, iRank),
        'is_armed': isArmed,
        '_row':     ri + 2,
      });

      if (ri % 200 == 0) {
        UploadProgress.instance.update(
            pp: (0.2 + (ri / total.clamp(1, 999999)) * 0.8)
                .clamp(0, 1),
            a: preview.length,
            msg: '${preview.length} rows मिले...');
        await Future.delayed(Duration.zero);
      }
    }

    UploadProgress.instance.reset();
    if (preview.isEmpty) {
      _snack('CSV में कोई डेटा नहीं', error: true);
      return;
    }
    if (!mounted) return;
    _showPreviewDialog(preview);
  }

  // ── Excel processing ──────────────────────────────────────────────────────
  Future<void> _processExcel(List<int> bytes) async {
    UploadProgress.instance.update(
        p: _UploadPhase.parsing,
        msg: 'Excel पार्स हो रही है...',
        pp: 0.1, hp: 0, ip: 0, a: 0, t: 0);

    await Future.delayed(const Duration(milliseconds: 16));

    ex.Excel excel;
    try {
      excel = ex.Excel.decodeBytes(bytes);
    } catch (e) {
      UploadProgress.instance.reset();
      _snack('Excel त्रुटि: ${_msg(e)}', error: true);
      return;
    }

    if (excel.tables.isEmpty) {
      UploadProgress.instance.reset();
      _snack('कोई शीट नहीं', error: true);
      return;
    }

    final sheetNames = excel.tables.keys.toList();
    String? chosen = sheetNames.length == 1
        ? sheetNames.first
        : await _pickSheet(sheetNames);
    if (chosen == null || !mounted) {
      UploadProgress.instance.reset();
      return;
    }

    final sheet = excel.tables[chosen]!;
    if (sheet.rows.isEmpty) {
      UploadProgress.instance.reset();
      _snack('शीट खाली', error: true);
      return;
    }

    String cs(int ri, int ci) {
      if (ri >= sheet.rows.length) return '';
      final row = sheet.rows[ri];
      if (ci >= row.length) return '';
      return (row[ci]?.value?.toString() ?? '').trim();
    }

    int hRow = -1;
    int? iPno, iName, iMob, iThana, iDist, iRank, iArmed;

    for (int ri = 0; ri < sheet.rows.length.clamp(0, 5); ri++) {
      final vals = sheet.rows[ri]
          .map((c) => (c?.value?.toString() ?? '').trim().toLowerCase())
          .toList();
      int? p, n, m, t, d, r, a;
      for (int ci = 0; ci < vals.length; ci++) {
        final h = vals[ci];
        if (p == null && (h.contains('pno') || h.contains('p.no'))) p = ci;
        if (n == null && (h.contains('name') || h.contains('नाम'))) n = ci;
        if (m == null && (h.contains('mobile') || h.contains('mob') || h.contains('phone'))) m = ci;
        if (t == null && (h.contains('thana') || h.contains('थाना') || h == 'ps')) t = ci;
        if (d == null && (h.contains('district') || h.contains('dist') || h.contains('जिला'))) d = ci;
        if (r == null && (h.contains('rank') || h.contains('post') || h.contains('पद'))) r = ci;
        if (a == null && (h.contains('sastra') || h.contains('armed') || h.contains('weapon') || h.contains('सशस्त्र'))) a = ci;
      }
      if (p != null || n != null) {
        hRow = ri;
        iPno = p; iName = n; iMob = m;
        iThana = t; iDist = d; iRank = r; iArmed = a;
        break;
      }
    }

    final dataStart = hRow >= 0 ? hRow + 1 : 0;
    iPno  ??= 0; iName ??= 1; iMob   ??= 2;
    iThana ??= 3; iDist  ??= 4; iRank  ??= 5;

    const armedVals = {'1', 'yes', 'हाँ', 'han', 'sastra', 'सशस्त्र', 'armed', 'true'};

    final preview = <Map<String, dynamic>>[];
    const chunk   = 500;
    final totalRows = sheet.rows.length - dataStart;

    UploadProgress.instance
        .update(msg: 'Rows पढ़ रहे हैं...', pp: 0.2, t: totalRows);

    for (int ri = dataStart; ri < sheet.rows.length; ri += chunk) {
      final end = (ri + chunk).clamp(0, sheet.rows.length);
      for (int r = ri; r < end; r++) {
        final row = sheet.rows[r];
        if (row.every(
            (c) => c == null || (c.value?.toString().trim().isEmpty ?? true)))
          continue;
        final pno  = cs(r, iPno!);
        final name = cs(r, iName!);
        if (pno.isEmpty && name.isEmpty) continue;

        final armedRaw = iArmed != null
            ? cs(r, iArmed!).toLowerCase()
            : '';
        final isArmed  = armedVals.contains(armedRaw) ? 1 : 0;

        preview.add({
          'pno':      pno,
          'name':     name,
          'mobile':   cs(r, iMob!),
          'thana':    cs(r, iThana!),
          'district': cs(r, iDist!),
          'rank':     cs(r, iRank!),
          'is_armed': isArmed,
          '_row':     r + 1,
        });
      }
      await Future.delayed(Duration.zero);
      UploadProgress.instance.update(
          pp: (0.2 + ((end - dataStart) / totalRows.clamp(1, 999999)) * 0.8)
              .clamp(0, 1),
          a: preview.length,
          msg: '${preview.length} rows मिले...');
    }

    UploadProgress.instance.reset();
    if (preview.isEmpty) {
      _snack('कोई डेटा नहीं', error: true);
      return;
    }
    if (!mounted) return;
    _showPreviewDialog(preview);
  }

  Future<String?> _pickSheet(List<String> names) =>
      showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _kBg,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: _kBorder)),
          title: const Text('शीट चुनें',
              style: TextStyle(
                  color: _kDark, fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: names
                .map((n) => ListTile(
                      title: Text(n,
                          style: const TextStyle(color: _kDark)),
                      trailing: const Icon(Icons.chevron_right,
                          color: _kSubtle),
                      onTap: () => Navigator.pop(ctx, n),
                    ))
                .toList(),
          ),
        ),
      );

  // ── Preview dialog ────────────────────────────────────────────────────────
  void _showPreviewDialog(List<Map<String, dynamic>> initial) {
    final allRows  = List<Map<String, dynamic>>.from(initial);
    final workRows = List<Map<String, dynamic>>.from(initial);
    String previewQ = '';
    int    previewPage = 1;
    const  ppSize = 50;
    final  psCtrl = TextEditingController();
    Timer? pdebounce;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        final filtered = previewQ.isEmpty
            ? workRows
            : workRows.where((r) {
                final q = previewQ.toLowerCase();
                return (r['name'] as String? ?? '')
                        .toLowerCase()
                        .contains(q) ||
                    (r['pno'] as String? ?? '')
                        .toLowerCase()
                        .contains(q) ||
                    (r['thana'] as String? ?? '')
                        .toLowerCase()
                        .contains(q);
              }).toList();

        final totalPages =
            ((filtered.length - 1) ~/ ppSize) + 1;
        final sp =
            previewPage.clamp(1, totalPages.clamp(1, 9999));
        final ps = (sp - 1) * ppSize;
        final pe = (ps + ppSize).clamp(0, filtered.length);
        final pageRows = filtered.sublist(ps, pe);

        final valid = workRows
            .where((r) =>
                (r['pno'] as String? ?? '').isNotEmpty &&
                (r['name'] as String? ?? '').isNotEmpty)
            .length;

        final armedCount =
            workRows.where((r) => r['is_armed'] == 1).length;
        final unarmedCount = workRows.length - armedCount;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight:
                  MediaQuery.of(ctx).size.height * 0.92,
            ),
            child: Container(
              decoration: _dlgDec(),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                _dlgHeader(
                    'Preview — ${workRows.length}/${allRows.length} rows',
                    Icons.upload_file_outlined,
                    ctx),

                // Stats row
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(14, 10, 14, 4),
                  child: Row(children: [
                    _pill('$valid मान्य', _kSuccess),
                    const SizedBox(width: 6),
                    _pill(
                        '${workRows.length - valid} त्रुटि',
                        _kError),
                    const SizedBox(width: 6),
                    _armedPill(armedCount, true),
                    const SizedBox(width: 6),
                    _armedPill(unarmedCount, false),
                    const Spacer(),
                    const Icon(Icons.touch_app_outlined,
                        size: 11, color: _kSubtle),
                    const SizedBox(width: 3),
                    const Text('× से हटाएं',
                        style: TextStyle(
                            color: _kSubtle, fontSize: 10)),
                  ]),
                ),

                // Search
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(12, 4, 12, 6),
                  child: TextField(
                    controller: psCtrl,
                    style: const TextStyle(
                        color: _kDark, fontSize: 13),
                    onChanged: (v) {
                      pdebounce?.cancel();
                      pdebounce = Timer(
                          const Duration(milliseconds: 250),
                          () {
                        ss(() {
                          previewQ = v.trim();
                          previewPage = 1;
                        });
                      });
                    },
                    decoration: _searchDec(
                        'नाम, PNO, थाना से खोजें...',
                        onClear: previewQ.isNotEmpty
                            ? () {
                                psCtrl.clear();
                                ss(() {
                                  previewQ = '';
                                  previewPage = 1;
                                });
                              }
                            : null),
                  ),
                ),

                // List
                Flexible(
                  child: pageRows.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('कोई row नहीं',
                              style: const TextStyle(
                                  color: _kSubtle),
                              textAlign: TextAlign.center),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          itemCount: pageRows.length,
                          itemBuilder: (_, i) {
                            final r = pageRows[i];
                            final isOk =
                                (r['pno'] as String? ?? '')
                                        .isNotEmpty &&
                                    (r['name'] as String? ?? '')
                                        .isNotEmpty;
                            final armed = r['is_armed'] == 1;
                            return Container(
                              margin: const EdgeInsets.only(
                                  bottom: 6),
                              decoration: BoxDecoration(
                                color: isOk
                                    ? Colors.white
                                    : _kError
                                        .withOpacity(0.04),
                                borderRadius:
                                    BorderRadius.circular(9),
                                border: Border.all(
                                    color: isOk
                                        ? _kBorder
                                            .withOpacity(0.4)
                                        : _kError
                                            .withOpacity(0.35)),
                              ),
                              child: Row(children: [
                                // Row number
                                Container(
                                  width: 32,
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets
                                      .symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isOk
                                        ? _kSurface
                                            .withOpacity(0.6)
                                        : _kError
                                            .withOpacity(0.06),
                                    borderRadius:
                                        const BorderRadius.only(
                                      topLeft:
                                          Radius.circular(9),
                                      bottomLeft:
                                          Radius.circular(9),
                                    ),
                                  ),
                                  child: Text(
                                      '${r['_row']}',
                                      style: TextStyle(
                                          color: isOk
                                              ? _kSubtle
                                              : _kError,
                                          fontSize: 10,
                                          fontWeight:
                                              FontWeight.w700)),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment
                                                .start,
                                        children: [
                                      Row(children: [
                                        Expanded(
                                          child: Text(
                                            (r['name'] as String)
                                                    .isNotEmpty
                                                ? r['name']
                                                    as String
                                                : '⚠ नाम आवश्यक',
                                            style: TextStyle(
                                              color: (r['name']
                                                          as String)
                                                      .isNotEmpty
                                                  ? _kDark
                                                  : _kError,
                                              fontWeight:
                                                  FontWeight.w700,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        // Armed badge
                                        Container(
                                          padding: const EdgeInsets
                                              .symmetric(
                                              horizontal: 6,
                                              vertical: 2),
                                          decoration:
                                              BoxDecoration(
                                            color: armed
                                                ? _kArmed
                                                    .withOpacity(
                                                        0.12)
                                                : _kUnarmed
                                                    .withOpacity(
                                                        0.08),
                                            borderRadius:
                                                BorderRadius
                                                    .circular(4),
                                          ),
                                          child: Text(
                                            armed
                                                ? '🔫 सशस्त्र'
                                                : '🛡 निःशस्त्र',
                                            style: TextStyle(
                                                color: armed
                                                    ? _kArmed
                                                    : _kUnarmed,
                                                fontSize: 9,
                                                fontWeight:
                                                    FontWeight
                                                        .w700),
                                          ),
                                        ),
                                      ]),
                                      const SizedBox(height: 3),
                                      Wrap(
                                          spacing: 8,
                                          runSpacing: 2,
                                          children: [
                                        _miniTag(
                                            Icons.badge_outlined,
                                            (r['pno'] as String)
                                                    .isNotEmpty
                                                ? 'PNO: ${r['pno']}'
                                                : '⚠ PNO आवश्यक',
                                            (r['pno'] as String)
                                                    .isEmpty
                                                ? _kError
                                                : null),
                                        if ((r['mobile']
                                                    as String)
                                                .isNotEmpty)
                                          _miniTag(
                                              Icons.phone_outlined,
                                              r['mobile'] as String,
                                              null),
                                        if ((r['thana'] as String)
                                            .isNotEmpty)
                                          _miniTag(
                                              Icons
                                                  .local_police_outlined,
                                              r['thana'] as String,
                                              null),
                                        if ((r['rank'] as String)
                                            .isNotEmpty)
                                          _miniTag(
                                              Icons
                                                  .military_tech_outlined,
                                              r['rank'] as String,
                                              _kInfo),
                                      ]),
                                    ]),
                                  ),
                                ),
                                // Remove button
                                InkWell(
                                  onTap: () => ss(() {
                                    workRows.remove(r);
                                    final nf = previewQ.isEmpty
                                        ? workRows
                                        : workRows
                                            .where((x) =>
                                                (x['name'] as String? ??
                                                        '')
                                                    .toLowerCase()
                                                    .contains(previewQ
                                                        .toLowerCase()) ||
                                                (x['pno'] as String? ??
                                                        '')
                                                    .toLowerCase()
                                                    .contains(previewQ
                                                        .toLowerCase()))
                                            .toList();
                                    final ntp =
                                        ((nf.length - 1) ~/ ppSize)
                                                .clamp(0, 9999) +
                                            1;
                                    if (previewPage > ntp)
                                      previewPage =
                                          ntp.clamp(1, 9999);
                                  }),
                                  borderRadius:
                                      const BorderRadius.only(
                                    topRight: Radius.circular(9),
                                    bottomRight:
                                        Radius.circular(9),
                                  ),
                                  child: Container(
                                    width: 36,
                                    height: 52,
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.close,
                                        size: 15, color: _kError),
                                  ),
                                ),
                              ]),
                            );
                          },
                        ),
                ),

                // Pagination
                if (totalPages > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _kSurface.withOpacity(0.5),
                      border: Border(
                          top: BorderSide(
                              color: _kBorder
                                  .withOpacity(0.3))),
                    ),
                    child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                      _pageBtn(Icons.chevron_left, sp > 1,
                          () => ss(() => previewPage = sp - 1)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: _kPrimary.withOpacity(0.1),
                          borderRadius:
                              BorderRadius.circular(8),
                          border: Border.all(
                              color: _kBorder.withOpacity(0.4)),
                        ),
                        child: Text(
                            '$sp / $totalPages  (${filtered.length} rows)',
                            style: const TextStyle(
                                color: _kDark,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 8),
                      _pageBtn(
                          Icons.chevron_right,
                          sp < totalPages,
                          () => ss(() => previewPage = sp + 1)),
                    ]),
                  ),

                // Upload button
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      14, 8, 14, 16),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: _kSubtle,
                            side: const BorderSide(
                                color: _kBorder),
                            padding: const EdgeInsets.symmetric(
                                vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(10))),
                        child: const Text('रद्द'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: valid == 0
                                ? _kSubtle
                                : _kPrimary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(10))),
                        onPressed: valid == 0
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                final toUpload = workRows
                                    .where((r) =>
                                        (r['pno'] as String? ?? '')
                                            .isNotEmpty &&
                                        (r['name'] as String? ?? '')
                                            .isNotEmpty)
                                    .map((r) {
                                  final m =
                                      Map<String, dynamic>.from(r)
                                        ..remove('_row');
                                  return m;
                                }).toList();
                                _startBackgroundUpload(toUpload);
                              },
                        icon: const Icon(Icons.upload, size: 16),
                        label: Text('$valid अपलोड करें'),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }

  // ── Background SSE upload ─────────────────────────────────────────────────
  Future<void> _startBackgroundUpload(
      List<Map<String, dynamic>> toUpload) async {
    final up = UploadProgress.instance;
    up.update(
        p: _UploadPhase.uploading,
        t: toUpload.length,
        pp: 0, hp: 0, ip: 0, a: 0,
        msg: 'सर्वर पर भेज रहे हैं...');
    http.Client? client;
    try {
      final token = await AuthService.getToken();
      final uri =
          Uri.parse('${AppConstants.baseUrl}/admin/staff/bulk');
      final req = http.Request('POST', uri)
        ..headers['Content-Type']  = 'application/json'
        ..headers['Accept']        = 'text/event-stream'
        ..headers['Cache-Control'] = 'no-cache';
      if (token != null)
        req.headers['Authorization'] = 'Bearer $token';
      req.body = jsonEncode({'staff': toUpload});
      client = http.Client();
      final resp = await client.send(req);
      if (resp.statusCode != 200)
        throw Exception('Server error ${resp.statusCode}');
      String buf = '';
      await for (final raw
          in resp.stream.transform(utf8.decoder)) {
        buf += raw;
        while (buf.contains('\n')) {
          final idx  = buf.indexOf('\n');
          final line = buf.substring(0, idx).trim();
          buf = buf.substring(idx + 1);
          if (!line.startsWith('data:')) continue;
          final js = line.substring(5).trim();
          if (js.isEmpty) continue;
          Map<String, dynamic> data;
          try {
            data = jsonDecode(js) as Map<String, dynamic>;
          } catch (_) { continue; }
          final phase = data['phase'] as String? ?? '';
          final pct   = (data['pct'] as num?)?.toDouble() ?? 0;
          if (phase == 'parse') {
            up.update(
                p: _UploadPhase.uploading,
                pp: (pct / 100.0).clamp(0, 1),
                msg: data['msg'] as String? ?? '...');
          } else if (phase == 'hash') {
            up.update(
                pp: 1.0,
                hp: ((pct - 25.0) / 30.0).clamp(0, 1),
                msg: data['msg'] as String? ?? '...');
          } else if (phase == 'insert') {
            up.update(
                pp: 1.0,
                hp: 1.0,
                ip: ((pct - 55.0) / 43.0).clamp(0, 1),
                a: (data['added'] as num?)?.toInt() ?? 0,
                t: (data['total'] as num?)?.toInt() ??
                    toUpload.length,
                msg:
                    '${data['added'] ?? 0}/${data['total'] ?? toUpload.length} rows');
          } else if (phase == 'done') {
            final added =
                (data['added'] as num?)?.toInt() ?? 0;
            final skipped =
                (data['skipped'] as List?)?.length ?? 0;
            up.update(
                p: _UploadPhase.done,
                pp: 1.0,
                hp: 1.0,
                ip: 1.0,
                a: added,
                msg: '$added जोड़े गए, $skipped छोड़े गए');
            client.close();
            return;
          } else if (phase == 'error') {
            throw Exception(
                data['message'] as String? ?? 'Server error');
          }
        }
      }
    } catch (e) {
      client?.close();
      UploadProgress.instance.update(
          p: _UploadPhase.error,
          msg: _msg(e),
          err: _msg(e));
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  WIDGETS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _assignmentChip(Map s) {
    final type   = _v(s['assignType']);
    final label  = _v(s['assignLabel']);
    final detail = _v(s['assignDetail']);
    final config = switch (type) {
      'booth'   => (Icons.location_on_outlined,    _kSuccess,              'बूथ'),
      'kshetra' => (Icons.layers_outlined,          const Color(0xFF6A1B9A), 'क्षेत्र'),
      'zone'    => (Icons.grid_view_outlined,       const Color(0xFF1565C0), 'जोन'),
      'sector'  => (Icons.view_module_outlined,     const Color(0xFF2E7D32), 'सेक्टर'),
      _         => (Icons.how_to_vote_outlined,     _kSuccess,              ''),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: config.$2.withOpacity(0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: config.$2.withOpacity(0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(config.$1, size: 11, color: config.$2),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: config.$2.withOpacity(0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(config.$3,
              style: TextStyle(
                  color: config.$2,
                  fontSize: 9,
                  fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(label,
              style: TextStyle(
                  color: config.$2,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        if (detail.isNotEmpty) ...[
          Text('  •  ',
              style: TextStyle(
                  color: config.$2.withOpacity(0.5),
                  fontSize: 10)),
          Flexible(
            child: Text(detail,
                style: TextStyle(
                    color: config.$2.withOpacity(0.7),
                    fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ]),
    );
  }

  Widget _staffCard(Map s, {required bool assigned}) {
    final id        = s['id'] as int;
    final isSelected = _selected.contains(id);
    final name      = _v(s['name']);
    final initials  = name.trim()
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    final avatarColor = assigned ? _kSuccess : _kAccent;
    final assignType  = _v(s['assignType']);
    final armed       = _isArmed(s);

    return RepaintBoundary(
      child: GestureDetector(
        onLongPress: () {
          HapticFeedback.mediumImpact();
          _toggleSelect(id);
        },
        onTap: _selectMode ? () => _toggleSelect(id) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? _kPrimary.withOpacity(0.06)
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isSelected
                    ? _kPrimary
                    : _kBorder.withOpacity(0.4),
                width: isSelected ? 2 : 1),
            boxShadow: [
              BoxShadow(
                  color: _kPrimary.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [

              // Avatar / Checkbox
              GestureDetector(
                onTap: () => _toggleSelect(id),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _selectMode
                      ? Container(
                          key: const ValueKey('cb'),
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? _kPrimary
                                : Colors.white,
                            border: Border.all(
                                color: isSelected
                                    ? _kPrimary
                                    : _kBorder,
                                width: 2),
                          ),
                          child: Icon(
                              isSelected ? Icons.check : null,
                              color: Colors.white,
                              size: 22))
                      : Container(
                          key: const ValueKey('av'),
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: avatarColor
                                .withOpacity(0.12),
                            border: Border.all(
                                color: avatarColor
                                    .withOpacity(0.35)),
                          ),
                          child: Center(
                            child: Text(
                              initials.isEmpty
                                  ? 'S'
                                  : initials,
                              style: TextStyle(
                                  color: avatarColor,
                                  fontWeight:
                                      FontWeight.w900,
                                  fontSize:
                                      initials.length <= 1
                                          ? 18
                                          : 13),
                            ),
                          )),
                ),
              ),
              const SizedBox(width: 10),

              // Info
              Expanded(
                child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        name.isNotEmpty ? name : '—',
                        style: const TextStyle(
                            color: _kDark,
                            fontWeight: FontWeight.w700,
                            fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Assigned badge
                    _badge(
                        assigned ? 'असाइन' : 'रिज़र्व',
                        assigned ? _kSuccess : _kAccent),
                    const SizedBox(width: 4),
                    // Armed badge
                    _armedBadge(armed),
                  ]),
                  const SizedBox(height: 5),
                  Wrap(spacing: 8, runSpacing: 3, children: [
                    if (_v(s['pno']).isNotEmpty)
                      _tag(Icons.badge_outlined,
                          'PNO: ${_v(s['pno'])}'),
                    if (_v(s['mobile']).isNotEmpty)
                      _tag(Icons.phone_outlined,
                          _v(s['mobile'])),
                    if (_v(s['thana']).isNotEmpty)
                      _tag(Icons.local_police_outlined,
                          _v(s['thana'])),
                    if (_v(s['district']).isNotEmpty)
                      _tag(Icons.location_city_outlined,
                          _v(s['district'])),
                    if (_v(s['rank']).isNotEmpty)
                      _tag(Icons.military_tech_outlined,
                          _v(s['rank'])),
                  ]),
                  if (_v(s['assignLabel']).isNotEmpty) ...[
                    const SizedBox(height: 5),
                    _assignmentChip(s),
                  ],
                ]),
              ),

              const SizedBox(width: 4),

              // Actions
              Column(mainAxisSize: MainAxisSize.min, children: [
                _iconBtn(Icons.edit_outlined, _kInfo,
                    () => _showEditDialog(s)),
                const SizedBox(height: 4),
                _iconBtn(Icons.delete_outline, _kError,
                    () => _deleteStaff(s)),
                const SizedBox(height: 4),
                if (!assigned)
                  _iconBtn(Icons.how_to_vote_outlined,
                      _kPrimary, () => _showAssignDialog(s))
                else if (assignType == 'booth')
                  _iconBtn(Icons.person_remove_outlined,
                      _kError, () => _removeDuty(s))
                else
                  _iconBtn(
                      Icons.lock_outline,
                      _kSubtle.withOpacity(0.5),
                      () => _snack(
                          'अधिकारी असाइनमेंट संरचना पेज से बदलें')),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Selection bar ─────────────────────────────────────────────────────────
  Widget _selectionBar() {
    if (!_selectMode) return const SizedBox.shrink();
    final isAssignedTab = _tabs.index == 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _kDark,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: _kDark.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _kBorder.withOpacity(0.25),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('${_selected.length} चुने',
              style: const TextStyle(
                  color: _kBorder,
                  fontWeight: FontWeight.w800,
                  fontSize: 13)),
        ),
        const SizedBox(width: 6),
        _miniActionBtn('सभी', Icons.select_all,
            Colors.white70, _selectAll),
        const Spacer(),
        if (!isAssignedTab) ...[
          _miniActionBtn('असाइन',
              Icons.how_to_vote_outlined, _kBorder,
              _bulkAssignDialog),
          const SizedBox(width: 6),
        ],
        if (isAssignedTab) ...[
          _miniActionBtn('रिज़र्व',
              Icons.person_remove_outlined, _kAccent,
              _bulkUnassign),
          const SizedBox(width: 6),
        ],
        _miniActionBtn('हटाएं', Icons.delete_outline,
            _kError, _bulkDelete),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: _clearSelection,
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.close,
                size: 16, color: Colors.white70),
          ),
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final totalAll = _assignedTotal + _reserveTotal;

    return Stack(children: [
      Column(children: [

        // ── Top toolbar ──────────────────────────────────────────────────
        Container(
          color: _kSurface,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(
                    color: _kDark, fontSize: 13),
                decoration: _searchDec(
                    'नाम, PNO, मोबाइल, थाना खोजें...',
                    onClear: _q.isNotEmpty
                        ? () {
                            _searchCtrl.clear();
                            _q = '';
                            _refresh();
                          }
                        : null),
              ),
            ),
            const SizedBox(width: 8),
            _actionBtn(Icons.person_add_outlined,
                'जोड़ें', _kPrimary, _showAddDialog),
            const SizedBox(width: 6),
            // Upload button (Excel + CSV)
            AnimatedBuilder(
              animation: UploadProgress.instance,
              builder: (_, __) {
                final up = UploadProgress.instance;
                if (_fileLoading ||
                    up.phase == _UploadPhase.parsing) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 9),
                    decoration: BoxDecoration(
                        color: _kDark,
                        borderRadius:
                            BorderRadius.circular(10)),
                    child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2)),
                      SizedBox(width: 6),
                      Text('लोड...',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ]),
                  );
                }
                if (up.isActive) {
                  final overall = ((up.parsePct * 0.15) +
                          (up.hashPct * 0.30) +
                          (up.insertPct * 0.55))
                      .clamp(0.0, 1.0);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 9),
                    decoration: BoxDecoration(
                        color: _kDark,
                        borderRadius:
                            BorderRadius.circular(10)),
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              value: overall,
                              color: _kBorder,
                              strokeWidth: 2)),
                      const SizedBox(width: 6),
                      Text(
                          '${(overall * 100).round()}%',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight:
                                  FontWeight.w700)),
                    ]),
                  );
                }
                return _actionBtn(
                    Icons.upload_file_outlined,
                    'Upload',
                    _kDark,
                    _pickFile);
              },
            ),
          ]),
        ),

        // ── Rank filter chips ────────────────────────────────────────────
        Container(
          color: _kBg,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _kAllRanks.map((rank) {
                final isSel = _selectedRank == rank;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedRank = rank);
                    _refresh();
                  },
                  child: AnimatedContainer(
                    duration:
                        const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color:
                          isSel ? _kPrimary : Colors.white,
                      borderRadius:
                          BorderRadius.circular(20),
                      border: Border.all(
                          color: isSel
                              ? _kPrimary
                              : _kBorder.withOpacity(0.5)),
                      boxShadow: isSel
                          ? [
                              BoxShadow(
                                  color: _kPrimary
                                      .withOpacity(0.2),
                                  blurRadius: 4,
                                  offset:
                                      const Offset(0, 2))
                            ]
                          : [],
                    ),
                    child: Text(rank,
                        style: TextStyle(
                            color: isSel
                                ? Colors.white
                                : _kDark,
                            fontSize: 11,
                            fontWeight: isSel
                                ? FontWeight.w800
                                : FontWeight.w500)),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // ── Armed filter chips ───────────────────────────────────────────
        Container(
          color: _kBg,
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
          child: Row(children: [
            const Icon(Icons.shield_outlined,
                size: 13, color: _kSubtle),
            const SizedBox(width: 6),
            ...['All', 'Armed', 'Unarmed']
                .map((opt) {
              final isSel = _armedFilter == opt;
              final color = opt == 'Armed'
                  ? _kArmed
                  : opt == 'Unarmed'
                      ? _kUnarmed
                      : _kSubtle;
              final label = opt == 'All'
                  ? 'सभी'
                  : opt == 'Armed'
                      ? '🔫 सशस्त्र'
                      : '🛡 निःशस्त्र';
              return GestureDetector(
                onTap: () {
                  setState(() => _armedFilter = opt);
                  _refresh();
                },
                child: AnimatedContainer(
                  duration:
                      const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isSel
                        ? color.withOpacity(0.15)
                        : Colors.white,
                    borderRadius:
                        BorderRadius.circular(16),
                    border: Border.all(
                        color: isSel
                            ? color
                            : _kBorder.withOpacity(0.4),
                        width: isSel ? 1.5 : 1),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          color: isSel ? color : _kSubtle,
                          fontSize: 11,
                          fontWeight: isSel
                              ? FontWeight.w800
                              : FontWeight.w500)),
                ),
              );
            }).toList(),
          ]),
        ),

        // ── Summary ──────────────────────────────────────────────────────
        Container(
          color: _kBg,
          padding:
              const EdgeInsets.fromLTRB(12, 2, 12, 6),
          child: Row(children: [
            _summaryChip(
                'कुल', '$totalAll', _kPrimary),
            const SizedBox(width: 8),
            _summaryChip(
                'असाइन', '$_assignedTotal', _kSuccess),
            const SizedBox(width: 8),
            _summaryChip(
                'रिज़र्व', '$_reserveTotal', _kAccent),
            const Spacer(),
            if (_q.isNotEmpty ||
                _selectedRank != 'All' ||
                _armedFilter != 'All')
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kInfo.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: _kInfo.withOpacity(0.2)),
                ),
                child: const Text('फ़िल्टर सक्रिय',
                    style: TextStyle(
                        color: _kInfo,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded,
                  size: 18, color: _kSubtle),
              onPressed: _refresh,
              tooltip: 'रिफ्रेश',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ]),
        ),

        // ── Tab bar ──────────────────────────────────────────────────────
        Container(
          color: _kBg,
          child: TabBar(
            controller: _tabs,
            labelColor: _kPrimary,
            unselectedLabelColor: _kSubtle,
            labelStyle: const TextStyle(
                fontWeight: FontWeight.w800, fontSize: 12),
            unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500, fontSize: 12),
            indicatorColor: _kPrimary,
            indicatorWeight: 3,
            tabs: [
              Tab(text: 'असाइन ($_assignedTotal)'),
              Tab(text: 'रिज़र्व ($_reserveTotal)'),
            ],
          ),
        ),

        // ── Selection bar ─────────────────────────────────────────────────
        _selectionBar(),

        // ── Lists ─────────────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildList(
                items: _assigned,
                loading: _assignedLoading,
                hasMore: _assignedHasMore,
                scroll: _assignedScroll,
                assigned: true,
                emptyMsg: _q.isNotEmpty
                    ? '"$_q" के लिए कोई result नहीं'
                    : 'कोई असाइन स्टाफ नहीं',
                emptyIcon: Icons.how_to_vote_outlined,
              ),
              _buildList(
                items: _reserve,
                loading: _reserveLoading,
                hasMore: _reserveHasMore,
                scroll: _reserveScroll,
                assigned: false,
                emptyMsg: _q.isNotEmpty
                    ? '"$_q" के लिए कोई result नहीं'
                    : 'सभी स्टाफ असाइन हैं!',
                emptyIcon: Icons.badge_outlined,
              ),
            ],
          ),
        ),
      ]),

      const UploadProgressBanner(),
    ]);
  }

  Widget _buildList({
    required List<Map> items,
    required bool loading,
    required bool hasMore,
    required ScrollController scroll,
    required bool assigned,
    required String emptyMsg,
    required IconData emptyIcon,
  }) {
    if (items.isEmpty && loading)
      return const Center(
          child:
              CircularProgressIndicator(color: _kPrimary));
    if (items.isEmpty) return _emptyState(emptyMsg, emptyIcon);
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      color: _kPrimary,
      child: Scrollbar(
        controller: scroll,
        thumbVisibility: true,
        thickness: 6,
        radius: const Radius.circular(3),
        child: ListView.builder(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(
              12, 10, 12, 100),
          addRepaintBoundaries: false,
          itemCount: items.length + (hasMore ? 1 : 0),
          itemBuilder: (_, i) {
            if (i >= items.length)
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _kPrimary))),
              );
            return _staffCard(items[i], assigned: assigned);
          },
        ),
      ),
    );
  }

  // ── Widget helpers ────────────────────────────────────────────────────────
  BoxDecoration _dlgDec() => BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
              color: _kPrimary.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 8))
        ],
      );

  Widget _dlgHeader(String title, IconData icon, BuildContext ctx) =>
      Container(
        padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
        decoration: const BoxDecoration(
          color: _kDark,
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(15),
              topRight: Radius.circular(15)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: _kPrimary.withOpacity(0.25),
                borderRadius: BorderRadius.circular(7)),
            child: Icon(icon, color: _kBorder, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          ),
          IconButton(
            onPressed: () => Navigator.pop(ctx),
            icon: const Icon(Icons.close,
                color: Colors.white60, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ]),
      );

  Widget _dlgActions(BuildContext ctx, bool saving,
      {String saveLabel = 'अपडेट',
      required VoidCallback onSave}) =>
      Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed:
                  saving ? null : () => Navigator.pop(ctx),
              style: OutlinedButton.styleFrom(
                  foregroundColor: _kSubtle,
                  side: const BorderSide(color: _kBorder),
                  padding: const EdgeInsets.symmetric(
                      vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(10))),
              child: const Text('रद्द'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(10))),
              onPressed: saving ? null : onSave,
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2))
                  : Text(saveLabel,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      );

  Widget _field(TextEditingController c, String label,
          IconData icon,
          {bool req = false, TextInputType? type}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: c,
          keyboardType: type,
          style: const TextStyle(
              color: _kDark, fontSize: 13),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(
                color: _kSubtle, fontSize: 12),
            prefixIcon:
                Icon(icon, size: 18, color: _kPrimary),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 11),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: _kBorder)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: _kBorder)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                    color: _kPrimary, width: 2)),
            errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: _kError)),
          ),
          validator: req
              ? (v) => (v?.trim().isEmpty ?? true)
                  ? '${label.replaceAll(' *', '')} आवश्यक'
                  : null
              : null,
        ),
      );

  /// Armed / Unarmed toggle widget
  Widget _armedToggle({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: value
              ? _kArmed.withOpacity(0.06)
              : _kUnarmed.withOpacity(0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: value
                  ? _kArmed.withOpacity(0.3)
                  : _kBorder.withOpacity(0.5)),
        ),
        child: Row(children: [
          Icon(
            value
                ? Icons.security
                : Icons.shield_outlined,
            size: 20,
            color: value ? _kArmed : _kUnarmed,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
              Text(
                value ? 'सशस्त्र पुलिस' : 'निःशस्त्र पुलिस',
                style: TextStyle(
                    color: value ? _kArmed : _kUnarmed,
                    fontWeight: FontWeight.w700,
                    fontSize: 13),
              ),
              Text(
                value ? 'Armed Police' : 'Unarmed Police',
                style: const TextStyle(
                    color: _kSubtle, fontSize: 10),
              ),
            ]),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: _kArmed,
            inactiveThumbColor: _kUnarmed,
          ),
        ]),
      );

  InputDecoration _searchDec(String hint,
          {VoidCallback? onClear}) =>
      InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: _kSubtle, fontSize: 12),
        prefixIcon: const Icon(Icons.search,
            color: _kSubtle, size: 18),
        suffixIcon: onClear != null
            ? IconButton(
                icon: const Icon(Icons.clear,
                    size: 16, color: _kSubtle),
                onPressed: onClear)
            : null,
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: _kBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: _kBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
                color: _kPrimary, width: 2)),
      );

  Widget _staffInfoCard(Map s) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: _kBorder.withOpacity(0.5)),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kAccent.withOpacity(0.12),
              border: Border.all(
                  color: _kAccent.withOpacity(0.35)),
            ),
            child: Center(
              child: Text(
                _v(s['name'])
                    .split(' ')
                    .where((w) => w.isNotEmpty)
                    .take(2)
                    .map((w) => w[0].toUpperCase())
                    .join(),
                style: const TextStyle(
                    color: _kAccent,
                    fontWeight: FontWeight.w800,
                    fontSize: 14),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
              Row(children: [
                Expanded(
                  child: Text(_v(s['name']),
                      style: const TextStyle(
                          color: _kDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ),
                _armedBadge(_isArmed(s)),
              ]),
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.badge_outlined,
                    size: 11, color: _kSubtle),
                const SizedBox(width: 3),
                Text('PNO: ${_v(s['pno'])}',
                    style: const TextStyle(
                        color: _kSubtle, fontSize: 11)),
                if (_v(s['thana']).isNotEmpty) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.local_police_outlined,
                      size: 11, color: _kSubtle),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(_v(s['thana']),
                        style: const TextStyle(
                            color: _kSubtle, fontSize: 11),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ]),
            ]),
          ),
        ]),
      );

  // ── Small reusable widgets ─────────────────────────────────────────────────
  Widget _armedBadge(bool armed) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: armed
              ? _kArmed.withOpacity(0.1)
              : _kUnarmed.withOpacity(0.08),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
              color: armed
                  ? _kArmed.withOpacity(0.3)
                  : _kUnarmed.withOpacity(0.2)),
        ),
        child: Text(
          armed ? '🔫 सशस्त्र' : '🛡 निःशस्त्र',
          style: TextStyle(
              color: armed ? _kArmed : _kUnarmed,
              fontSize: 9,
              fontWeight: FontWeight.w700),
        ),
      );

  Widget _armedPill(int count, bool armed) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: armed
              ? _kArmed.withOpacity(0.1)
              : _kUnarmed.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: armed
                  ? _kArmed.withOpacity(0.3)
                  : _kUnarmed.withOpacity(0.2)),
        ),
        child: Text(
          armed ? '🔫 $count सशस्त्र' : '🛡 $count निःशस्त्र',
          style: TextStyle(
              color: armed ? _kArmed : _kUnarmed,
              fontSize: 10,
              fontWeight: FontWeight.w700),
        ),
      );

  Widget _tag(IconData icon, String text) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: _kSubtle),
        const SizedBox(width: 3),
        Text(text,
            style: const TextStyle(
                color: _kSubtle,
                fontSize: 11,
                fontWeight: FontWeight.w500)),
      ]);

  Widget _miniTag(IconData icon, String text, Color? color) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: color ?? _kSubtle),
        const SizedBox(width: 2),
        Text(text,
            style: TextStyle(
                color: color ?? _kSubtle, fontSize: 10)),
      ]);

  Widget _badge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800)),
      );

  Widget _pill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      );

  Widget _summaryChip(
          String label, String count, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: color.withOpacity(0.25)),
        ),
        child: RichText(
          text: TextSpan(children: [
            TextSpan(
                text: '$count ',
                style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w900)),
            TextSpan(
                text: label,
                style: const TextStyle(
                    color: _kSubtle, fontSize: 11)),
          ]),
        ),
      );

  Widget _actionBtn(IconData icon, String label,
          Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10)),
          child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  Widget _iconBtn(
          IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: color.withOpacity(0.25)),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      );

  Widget _emptyState(String msg, IconData icon) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
            Icon(icon,
                size: 52,
                color: _kSubtle.withOpacity(0.4)),
            const SizedBox(height: 14),
            Text(msg,
                style: const TextStyle(
                    color: _kSubtle, fontSize: 13),
                textAlign: TextAlign.center),
          ]),
        ),
      );

  Widget _pageBtn(
          IconData icon, bool enabled, VoidCallback onTap) =>
      GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: enabled
                ? _kPrimary.withOpacity(0.1)
                : Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: enabled
                    ? _kBorder
                    : Colors.grey.withOpacity(0.3)),
          ),
          child: Icon(icon,
              size: 18,
              color: enabled ? _kPrimary : Colors.grey),
        ),
      );

  Widget _miniActionBtn(String label, IconData icon,
          Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: color.withOpacity(0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min,
              children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  ASSIGN DIALOG — reusable for single + bulk assign
// ══════════════════════════════════════════════════════════════════════════════
class _AssignDialog extends StatelessWidget {
  final String title;
  final Widget? staffCard;
  final Map? selectedCenter;
  final List centerList;
  final bool cLoading, cHasMore, saving;
  final ScrollController cScroll;
  final TextEditingController busCtrl;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<Map> onCenterTap;
  final VoidCallback onClearCenter, onCancel;
  final VoidCallback? onAssign;
  final String assignLabel;

  const _AssignDialog({
    required this.title,
    this.staffCard,
    required this.selectedCenter,
    required this.centerList,
    required this.cLoading,
    required this.cHasMore,
    required this.cScroll,
    required this.busCtrl,
    required this.saving,
    required this.onSearchChanged,
    required this.onCenterTap,
    required this.onClearCenter,
    required this.onCancel,
    required this.onAssign,
    required this.assignLabel,
  });

  @override
  Widget build(BuildContext context) {
    final dlgDec = BoxDecoration(
      color: _kBg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _kBorder, width: 1.2),
      boxShadow: [
        BoxShadow(
            color: _kPrimary.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8))
      ],
    );

    String _v(dynamic v) => (v ?? '').toString().trim();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight:
              MediaQuery.of(context).size.height * 0.88,
        ),
        child: Container(
          decoration: dlgDec,
          child: Column(children: [
            // Header
            Container(
              padding:
                  const EdgeInsets.fromLTRB(16, 13, 12, 13),
              decoration: const BoxDecoration(
                color: _kDark,
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(15),
                    topRight: Radius.circular(15)),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: _kPrimary.withOpacity(0.25),
                      borderRadius:
                          BorderRadius.circular(7)),
                  child: const Icon(
                      Icons.how_to_vote_outlined,
                      color: _kBorder,
                      size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ),
                IconButton(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close,
                      color: Colors.white60, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                  if (staffCard != null) ...[
                    staffCard!,
                    const SizedBox(height: 16),
                  ],

                  // Selected center
                  if (selectedCenter != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _kSuccess.withOpacity(0.05),
                        borderRadius:
                            BorderRadius.circular(10),
                        border: Border.all(
                            color:
                                _kSuccess.withOpacity(0.3)),
                      ),
                      child: Row(children: [
                        const Icon(
                            Icons.check_circle_rounded,
                            color: _kSuccess,
                            size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                            Text(
                                _v(selectedCenter!['name']),
                                style: const TextStyle(
                                    color: _kDark,
                                    fontWeight:
                                        FontWeight.w700,
                                    fontSize: 13)),
                            Text(
                                '${_v(selectedCenter!['thana'])} • ${_v(selectedCenter!['gpName'])}',
                                style: const TextStyle(
                                    color: _kSubtle,
                                    fontSize: 11)),
                          ]),
                        ),
                        GestureDetector(
                          onTap: onClearCenter,
                          child: const Icon(Icons.close,
                              size: 16, color: _kSubtle),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Center search label
                  Row(children: [
                    Container(
                        width: 3,
                        height: 14,
                        decoration: BoxDecoration(
                            color: _kPrimary,
                            borderRadius:
                                BorderRadius.circular(2))),
                    const SizedBox(width: 7),
                    const Text('मतदान केंद्र चुनें',
                        style: TextStyle(
                            color: _kDark,
                            fontSize: 13,
                            fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 8),

                  // Center search
                  TextField(
                    onChanged: onSearchChanged,
                    style: const TextStyle(
                        color: _kDark, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'केंद्र, थाना, GP से खोजें...',
                      hintStyle: const TextStyle(
                          color: _kSubtle, fontSize: 12),
                      prefixIcon: const Icon(Icons.search,
                          color: _kSubtle, size: 18),
                      filled: true,
                      fillColor: Colors.white,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: _kBorder)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: _kBorder)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: _kPrimary, width: 2)),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Center list
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      border:
                          Border.all(color: _kBorder),
                      borderRadius:
                          BorderRadius.circular(10),
                      color: Colors.white,
                    ),
                    child: cLoading && centerList.isEmpty
                        ? const Center(
                            child:
                                CircularProgressIndicator(
                                    color: _kPrimary,
                                    strokeWidth: 2))
                        : centerList.isEmpty
                            ? const Center(
                                child: Text(
                                    'कोई केंद्र नहीं मिला',
                                    style: TextStyle(
                                        color: _kSubtle,
                                        fontSize: 12)))
                            : ListView.builder(
                                controller: cScroll,
                                padding:
                                    const EdgeInsets
                                        .symmetric(
                                        vertical: 4),
                                itemCount:
                                    centerList.length +
                                        (cHasMore ? 1 : 0),
                                itemBuilder: (_, i) {
                                  if (i >= centerList.length)
                                    return const Padding(
                                      padding:
                                          EdgeInsets.all(10),
                                      child: Center(
                                          child: SizedBox(
                                              width: 18,
                                              height: 18,
                                              child:
                                                  CircularProgressIndicator(
                                                      strokeWidth:
                                                          2,
                                                      color:
                                                          _kPrimary))),
                                    );
                                  final c = centerList[i];
                                  final isSel =
                                      selectedCenter?['id'] ==
                                          c['id'];
                                  final type =
                                      '${c['centerType'] ?? 'C'}';
                                  final tc = type == 'A'
                                      ? _kError
                                      : type == 'B'
                                          ? _kAccent
                                          : _kInfo;
                                  return InkWell(
                                    onTap: () => onCenterTap(Map<String, dynamic>.from(c)),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                          milliseconds: 120),
                                      margin: const EdgeInsets
                                          .fromLTRB(
                                          6, 3, 6, 3),
                                      padding:
                                          const EdgeInsets
                                              .all(10),
                                      decoration:
                                          BoxDecoration(
                                        color: isSel
                                            ? _kPrimary
                                                .withOpacity(
                                                    0.08)
                                            : Colors
                                                .transparent,
                                        borderRadius:
                                            BorderRadius
                                                .circular(8),
                                        border: Border.all(
                                            color: isSel
                                                ? _kPrimary
                                                : _kBorder
                                                    .withOpacity(
                                                        0.4),
                                            width:
                                                isSel ? 1.5 : 1),
                                      ),
                                      child: Row(children: [
                                        Container(
                                          width: 28,
                                          height: 28,
                                          decoration:
                                              BoxDecoration(
                                            shape:
                                                BoxShape.circle,
                                            color: tc
                                                .withOpacity(
                                                    0.12),
                                            border: Border.all(
                                                color: tc
                                                    .withOpacity(
                                                        0.4)),
                                          ),
                                          child: Center(
                                              child: Text(
                                                  type,
                                                  style: TextStyle(
                                                      color: tc,
                                                      fontSize:
                                                          10,
                                                      fontWeight:
                                                          FontWeight
                                                              .w900))),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment
                                                      .start,
                                              children: [
                                            Text(
                                                _v(c['name']),
                                                style: TextStyle(
                                                    color: isSel
                                                        ? _kPrimary
                                                        : _kDark,
                                                    fontWeight:
                                                        FontWeight
                                                            .w700,
                                                    fontSize: 13),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow
                                                        .ellipsis),
                                            Text(
                                                '${_v(c['thana'])} • ${_v(c['gpName'])}',
                                                style: const TextStyle(
                                                    color: _kSubtle,
                                                    fontSize: 10),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow
                                                        .ellipsis),
                                          ]),
                                        ),
                                        if (isSel)
                                          const Icon(
                                              Icons
                                                  .check_circle_rounded,
                                              color: _kPrimary,
                                              size: 18),
                                      ]),
                                    ),
                                  );
                                },
                              ),
                  ),
                  const SizedBox(height: 14),

                  // Bus number
                  Row(children: [
                    Container(
                        width: 3,
                        height: 14,
                        decoration: BoxDecoration(
                            color: _kPrimary,
                            borderRadius:
                                BorderRadius.circular(2))),
                    const SizedBox(width: 7),
                    const Text('बस संख्या (वैकल्पिक)',
                        style: TextStyle(
                            color: _kDark,
                            fontSize: 13,
                            fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                    controller: busCtrl,
                    style: const TextStyle(
                        color: _kDark, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'बस नंबर',
                      hintStyle: const TextStyle(
                          color: _kSubtle, fontSize: 12),
                      prefixIcon: const Icon(
                          Icons.directions_bus_outlined,
                          size: 18,
                          color: _kPrimary),
                      filled: true,
                      fillColor: Colors.white,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: _kBorder)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: _kBorder)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: _kPrimary, width: 2)),
                    ),
                  ),
                ]),
              ),
            ),

            // Footer buttons
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        saving ? null : onCancel,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: _kSubtle,
                        side: const BorderSide(
                            color: _kBorder),
                        padding: const EdgeInsets.symmetric(
                            vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10))),
                    child: const Text('रद्द'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor:
                            selectedCenter == null
                                ? _kSubtle
                                : _kPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10))),
                    onPressed: onAssign,
                    child: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2))
                        : Text(assignLabel,
                            style: const TextStyle(
                                fontWeight:
                                    FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}