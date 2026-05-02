import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';
import 'manak_rank_editor_page.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const kBg            = Color(0xFFFDF6E3);
const kSurface       = Color(0xFFF5E6C8);
const kPrimary       = Color(0xFF8B6914);
const kDark          = Color(0xFF4A3000);
const kSubtle        = Color(0xFFAA8844);
const kBorder        = Color(0xFFD4A843);
const kError         = Color(0xFFC0392B);
const kSuccess       = Color(0xFF2D6A1E);
const kDistrictColor = Color(0xFF6C3483);
const kCustomColor   = Color(0xFF00796B);
const kAssignColor   = Color(0xFF1565C0);
const kOrange        = Color(0xFFE65100);

// ── Responsive Scale Helper ──────────────────────────────────────────────────
class RScale {
  final double width;
  RScale(this.width);

  /// 0..1 ratio: 0 at <=320px, 1 at >=480px
  double get t {
    if (width <= 320) return 0.0;
    if (width >= 480) return 1.0;
    return (width - 320) / 160;
  }

  /// Returns base on small screens, max on large (linear interp).
  double s(double small, double large) => small + (large - small) * t;

  /// Compact / normal / wide buckets
  bool get isCompact => width < 360;
  bool get isWide    => width >= 600;

  EdgeInsets pad(double h, double v) =>
      EdgeInsets.symmetric(horizontal: h, vertical: v);
}

RScale rOf(BuildContext c) => RScale(MediaQuery.of(c).size.width);

// ── Icon map ──────────────────────────────────────────────────────────────────
const Map<String, IconData> _kDefaultIcons = {
  'cluster_mobile':        Icons.directions_car_outlined,
  'thana_mobile':          Icons.local_police_outlined,
  'thana_reserve':         Icons.savings_outlined,
  'thana_extra_mobile':    Icons.add_road_outlined,
  'sector_pol_mag_mobile': Icons.gavel_outlined,
  'zonal_pol_mag_mobile':  Icons.account_tree_outlined,
  'sdm_co_mobile':         Icons.admin_panel_settings_outlined,
  'chowki_mobile':         Icons.home_work_outlined,
  'barrier_picket':        Icons.block_outlined,
  'evm_security':          Icons.how_to_vote_outlined,
  'adm_sp_mobile':         Icons.shield_outlined,
  'dm_sp_mobile':          Icons.workspace_premium_outlined,
  'observer_security':     Icons.visibility_outlined,
  'hq_reserve':            Icons.business_outlined,
};

// ── Duty entry model ──────────────────────────────────────────────────────────
class _DutyEntry {
  final String   type;
  String         label;
  final IconData icon;
  final bool     isDefault;
  int            sankhya;
  int            totalAssigned;
  int            batchCount;

  _DutyEntry({
    required this.type,
    required this.label,
    required this.icon,
    required this.isDefault,
    this.sankhya       = 0,
    this.totalAssigned = 0,
    this.batchCount    = 0,
  });

  factory _DutyEntry.fromRule(Map<String, dynamic> r, {Map<String, dynamic>? summary}) {
    final type      = (r['dutyType'] ?? '') as String;
    final isDefault = (r['isDefault'] ?? false) as bool;
    final s         = summary ?? {};
    return _DutyEntry(
      type:          type,
      label:         (r['dutyLabelHi'] ?? '') as String,
      icon:          _kDefaultIcons[type] ?? Icons.assignment_outlined,
      isDefault:     isDefault,
      sankhya:       ((r['sankhya'] ?? 0) as num).toInt(),
      totalAssigned: ((s['totalAssigned'] ?? 0) as num).toInt(),
      batchCount:    ((s['batchCount'] ?? 0) as num).toInt(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  MAIN PAGE
// ══════════════════════════════════════════════════════════════════════════════
class ManakDistrictPage extends StatefulWidget {
  final List<Map<String, dynamic>> initialRules;
  const ManakDistrictPage({super.key, required this.initialRules});

  @override
  State<ManakDistrictPage> createState() => _ManakDistrictPageState();
}

class _ManakDistrictPageState extends State<ManakDistrictPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  final List<_DutyEntry>                  _duties  = [];
  final Map<String, Map<String, dynamic>> _byDuty  = {};
  final Map<String, Map<String, dynamic>> _summary = {};

  bool _loading  = true;
  bool _saving   = false;
  bool _changed  = false;
  bool _disposed = false;

  int?   _autoJobId;
  String _autoJobStatus = '';
  int    _autoJobPct    = 0;
  int    _autoAssigned  = 0;
  int    _autoSkipped   = 0;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _tabCtrl.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!_disposed && mounted) setState(fn);
  }

  Future<void> _loadAll() async {
    _safeSetState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      if (_disposed) return;
      final futures = await Future.wait([
        ApiService.get('/admin/district-rules', token: token),
        ApiService.get('/admin/district-duty/summary', token: token),
        ApiService.get('/admin/district-duty/auto-assign/latest', token: token),
      ]);
      final rulesRes   = futures[0];
      final summaryRes = futures[1];
      final latestJob  = futures[2];
      final list = (rulesRes is List) ? rulesRes
          : ((rulesRes['data'] is List) ? rulesRes['data'] as List : []);
      final summaryData = (summaryRes['data'] is Map)
          ? Map<String, dynamic>.from(summaryRes['data'] as Map)
          : <String, dynamic>{};
      _duties.clear(); _byDuty.clear(); _summary.clear();
      summaryData.forEach((key, val) {
        _summary[key] = Map<String, dynamic>.from(val as Map);
      });
      for (final item in list) {
        final r     = Map<String, dynamic>.from(item as Map);
        final entry = _DutyEntry.fromRule(r, summary: _summary[r['dutyType']]);
        _duties.add(entry);
        _byDuty[entry.type] = r;
      }
      final jobData = latestJob['data'];
      if (jobData is Map) {
        final status = jobData['status'] as String? ?? '';
        if (status == 'running' || status == 'pending') {
          _autoJobId     = (jobData['jobId'] as num?)?.toInt();
          _autoJobStatus = status;
          _autoJobPct    = (jobData['pct'] as num?)?.toInt() ?? 0;
          if (token != null) _startPolling(token);
        }
      }
    } catch (e) {
      if (!_disposed && mounted) showSnack(context, 'लोड विफल: $e', error: true);
    } finally {
      _safeSetState(() => _loading = false);
    }
  }

  bool _hasAny(Map<String, dynamic>? r) {
    if (r == null) return false;
    for (final key in ['siArmedCount','siUnarmedCount','hcArmedCount',
        'hcUnarmedCount','constArmedCount','constUnarmedCount',
        'auxArmedCount','auxUnarmedCount','pacCount']) {
      if (((r[key] ?? 0) as num) > 0) return true;
    }
    return false;
  }

  int _totalStaff(Map<String, dynamic>? r) {
    if (r == null) return 0;
    int t = 0;
    for (final key in ['siArmedCount','siUnarmedCount','hcArmedCount',
        'hcUnarmedCount','constArmedCount','constUnarmedCount',
        'auxArmedCount','auxUnarmedCount']) {
      t += ((r[key] ?? 0) as num).toInt();
    }
    return t;
  }

  Future<void> _startAutoAssign() async {
    final r = rOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: kDistrictColor.withOpacity(0.5)),
        ),
        title: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: kDistrictColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.auto_fix_high, color: kDistrictColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Auto Assign District Duty',
              style: TextStyle(color: kDark, fontSize: r.s(13, 15), fontWeight: FontWeight.w800)),
          ),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('मानक के अनुसार सभी ड्यूटी प्रकारों पर स्टाफ auto-assign होगा।',
              style: TextStyle(color: kDark, fontSize: r.s(12, 13))),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kOrange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kOrange.withOpacity(0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 13, color: kOrange),
              const SizedBox(width: 6),
              Expanded(
                child: Text('यह background में चलेगा। पहले के assignments हट जाएंगे।',
                    style: TextStyle(color: kOrange, fontSize: r.s(10, 11))),
              ),
            ]),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('रद्द', style: TextStyle(color: kSubtle))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: kDistrictColor, foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Start करें')),
        ],
      ),
    );

    if (confirmed != true || _disposed) return;

    try {
      final token = await AuthService.getToken();
      final res = await ApiService.post(
        '/admin/district-duty/auto-assign/start', {}, token: token);
      final jobId = ((res['data'] ?? res)['jobId'] as num?)?.toInt();
      if (jobId == null || jobId <= 0) {
        if (!_disposed && mounted) showSnack(context, 'Job शुरू नहीं हुआ', error: true);
        return;
      }
      _safeSetState(() {
        _autoJobId = jobId; _autoJobStatus = 'running';
        _autoJobPct = 0; _autoAssigned = 0; _autoSkipped = 0;
      });
      if (token != null) _startPolling(token);
      if (!_disposed && mounted) showSnack(context, 'Auto-assign शुरू हो गई!');
    } catch (e) {
      if (!_disposed && mounted) showSnack(context, 'Error: $e', error: true);
    }
  }

  void _startPolling(String token) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_disposed || _autoJobId == null) return;
      try {
        final res = await ApiService.get(
            '/admin/district-duty/auto-assign/status/$_autoJobId', token: token);
        final d = (res['data'] ?? res) as Map;
        final status   = d['status']   as String? ?? '';
        final pct      = (d['pct']      as num?)?.toInt() ?? 0;
        final assigned = (d['assigned'] as num?)?.toInt() ?? 0;
        final skipped  = (d['skipped']  as num?)?.toInt() ?? 0;
        _safeSetState(() {
          _autoJobStatus = status; _autoJobPct = pct;
          _autoAssigned = assigned; _autoSkipped = skipped;
        });
        if (status == 'done' || status == 'error') {
          _pollTimer?.cancel();
          if (status == 'done') {
            await _loadAll();
            if (!_disposed && mounted) showSnack(context, '$assigned staff assign हुए ✓');
          } else {
            final err = d['errorMsg'] as String? ?? 'Unknown error';
            if (!_disposed && mounted) showSnack(context, 'Error: $err', error: true);
          }
        }
      } catch (_) {}
    });
  }

  Future<void> _clearAllAssignments() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: kError, width: 1.2)),
        title: const Row(children: [
          Icon(Icons.refresh, color: kError, size: 20), SizedBox(width: 8),
          Expanded(
            child: Text('ड्यूटी रीफ्रेश करें?',
                style: TextStyle(color: kError, fontWeight: FontWeight.w800, fontSize: 14)),
          ),
        ]),
        content: const Text(
            'सभी ड्यूटी assignments हट जाएंगे और system reset हो जाएगा.\n\nआप दोबारा Auto Assign कर सकते हैं।',
            style: TextStyle(color: kDark, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('रद्द', style: TextStyle(color: kSubtle))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kError,
                foregroundColor: Colors.white, elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('रीफ्रेश करें')),
        ],
      ),
    );
    if (confirmed != true || _disposed) return;
    try {
      final token = await AuthService.getToken();
      await ApiService.delete('/admin/district-duty/auto-assign/clear-all', token: token);
      if (!_disposed && mounted) {
        showSnack(context, 'ड्यूटी सफलतापूर्वक रीफ्रेश हो गई ✓');
        _loadAll();
      }
    } catch (e) {
      if (!_disposed && mounted) showSnack(context, 'Error: $e', error: true);
    }
  }

  void _openRankEditor(_DutyEntry entry, int sortOrder) async {
    final existing = Map<String, dynamic>.from(_byDuty[entry.type] ?? {
      'dutyType': entry.type, 'dutyLabelHi': entry.label,
      'sortOrder': sortOrder, 'isDefault': entry.isDefault,
    });
    final updated = await Navigator.push<Map<String, dynamic>>(context,
      MaterialPageRoute(builder: (_) => ManakRankEditorPage(
        title: entry.label, subtitle: 'जनपदीय कानून व्यवस्था',
        color: entry.isDefault ? kDistrictColor : kCustomColor,
        initial: existing, showSankhya: true)));
    if (updated != null) {
      updated['dutyType'] = entry.type; updated['dutyLabelHi'] = entry.label;
      updated['sortOrder'] = sortOrder; updated['isDefault'] = entry.isDefault;
      _safeSetState(() {
        _byDuty[entry.type] = updated;
        final idx = _duties.indexWhere((d) => d.type == entry.type);
        if (idx >= 0) _duties[idx].sankhya = ((updated['sankhya'] ?? 0) as num).toInt();
        _changed = true;
      });
    }
  }

  void _openDutyDetail(_DutyEntry entry) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => _DutyDetailPage(
          entry: entry, rule: _byDuty[entry.type], onRefresh: _loadAll)));
    _loadAll();
  }

  // ── Open print report page ─────────────────────────────────────────────────
  void _openPrintReport() async {
    _safeSetState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final Map<String, List<Map<String, dynamic>>> allBatches = {};
      for (final duty in _duties) {
        try {
          final res = await ApiService.get(
              '/admin/district-duty/${duty.type}/batches', token: token);
          final data = res['data'];
          allBatches[duty.type] = (data is List)
              ? data.map((e) => Map<String, dynamic>.from(e as Map)).toList()
              : [];
        } catch (_) {
          allBatches[duty.type] = [];
        }
      }
      if (!_disposed && mounted) {
        _safeSetState(() => _loading = false);
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DistrictDutyPrintPage(
              duties: _duties,
              byDuty: _byDuty,
              summary: _summary,
              allBatches: allBatches,
            ),
          ),
        );
      }
    } catch (e) {
      _safeSetState(() => _loading = false);
      if (!_disposed && mounted) showSnack(context, 'रिपोर्ट लोड विफल: $e', error: true);
    }
  }

  Future<void> _saveAll() async {
    _safeSetState(() => _saving = true);
    try {
      final token = await AuthService.getToken();
      final rules = <Map<String, dynamic>>[];
      for (int i = 0; i < _duties.length; i++) {
        final d = _duties[i];
        final base = _byDuty[d.type] ?? {
          'dutyType': d.type, 'dutyLabelHi': d.label, 'sankhya': 0,
          'siArmedCount': 0, 'siUnarmedCount': 0, 'hcArmedCount': 0,
          'hcUnarmedCount': 0, 'constArmedCount': 0, 'constUnarmedCount': 0,
          'auxArmedCount': 0, 'auxUnarmedCount': 0, 'pacCount': 0.0,
        };
        final r = Map<String, dynamic>.from(base);
        r['dutyType'] = d.type; r['dutyLabelHi'] = d.label;
        r['sortOrder'] = (i + 1) * 10;
        rules.add(r);
      }
      await ApiService.post('/admin/district-rules', {'rules': rules}, token: token);
      if (!_disposed && mounted) {
        _safeSetState(() => _changed = false);
        showSnack(context, 'जनपदीय मानक सेव हो गया ✓');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!_disposed && mounted) showSnack(context, 'सेव विफल: $e', error: true);
    } finally {
      _safeSetState(() => _saving = false);
    }
  }

  Future<void> _showAddDialog({_DutyEntry? editing}) async {
    final ctrl = TextEditingController(text: editing?.label ?? '');
    final isEdit = editing != null;
    final confirmed = await showDialog<bool>(
      context: context, barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(width: 36, height: 36,
              decoration: BoxDecoration(color: kCustomColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(isEdit ? Icons.edit_outlined : Icons.add_box_outlined,
                  color: kCustomColor, size: 20)),
          const SizedBox(width: 10),
          Expanded(child: Text(
              isEdit ? 'ड्यूटी प्रकार संपादित करें' : 'नया ड्यूटी प्रकार जोड़ें',
              style: const TextStyle(color: kDark, fontSize: 14, fontWeight: FontWeight.w800))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('ड्यूटी का नाम (हिंदी में)',
              style: TextStyle(color: kSubtle, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kBorder.withOpacity(0.6))),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: TextField(controller: ctrl, autofocus: true,
              style: const TextStyle(color: kDark, fontSize: 15, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(border: InputBorder.none,
                  hintText: 'जैसे: विशेष मोबाईल ड्यूटी',
                  hintStyle: TextStyle(color: kSubtle)))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('रद्द करें', style: TextStyle(color: kSubtle))),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: kCustomColor,
                foregroundColor: Colors.white, elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: Text(isEdit ? 'अपडेट करें' : 'जोड़ें')),
        ],
      ),
    );
    if (confirmed != true) return;
    final label = ctrl.text.trim();
    if (label.isEmpty) return;
    try {
      final token = await AuthService.getToken();
      if (isEdit) {
        await ApiService.put('/admin/district-rules/custom/${editing!.type}',
            {'labelHi': label}, token: token);
        _safeSetState(() {
          editing.label = label;
          if (_byDuty.containsKey(editing.type)) {
            _byDuty[editing.type]!['dutyLabelHi'] = label;
          }
        });
        if (!_disposed && mounted) showSnack(context, 'नाम अपडेट हो गया ✓');
      } else {
        final res  = await ApiService.post(
            '/admin/district-rules/custom', {'labelHi': label}, token: token);
        final data = (res['data'] ?? res) as Map<String, dynamic>;
        final entry = _DutyEntry(
            type: data['dutyType'] as String,
            label: data['dutyLabelHi'] as String,
            icon: Icons.assignment_outlined, isDefault: false);
        _safeSetState(() {
          _duties.add(entry);
          _byDuty[entry.type] = Map<String, dynamic>.from(data);
        });
        if (!_disposed && mounted) showSnack(context, 'नया ड्यूटी प्रकार जोड़ा गया ✓');
      }
    } catch (e) {
      if (!_disposed && mounted) showSnack(context, 'विफल: $e', error: true);
    }
  }

  Future<void> _deleteCustomDuty(_DutyEntry entry) async {
    final hasRule = _hasAny(_byDuty[entry.type]);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('ड्यूटी प्रकार हटाएं?',
            style: TextStyle(color: kDark, fontWeight: FontWeight.w800)),
        content: Text(hasRule
            ? '"${entry.label}" और इसका मानक दोनों हटा दिए जाएंगे।'
            : '"${entry.label}" को हटाया जाएगा।',
            style: const TextStyle(color: kDark)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('रद्द करें', style: TextStyle(color: kSubtle))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kError,
                foregroundColor: Colors.white, elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('हटाएं')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final token = await AuthService.getToken();
      await ApiService.delete(
          '/admin/district-rules/custom/${entry.type}', token: token);
      _safeSetState(() {
        _duties.removeWhere((d) => d.type == entry.type);
        _byDuty.remove(entry.type);
      });
      if (!_disposed && mounted) showSnack(context, 'हटाया गया ✓');
    } catch (e) {
      if (!_disposed && mounted) showSnack(context, 'विफल: $e', error: true);
    }
  }

  Future<bool> _onWillPop() async {
    if (!_changed) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBg,
        title: const Text('बदलाव सहेजे नहीं गए',
            style: TextStyle(color: kDark, fontWeight: FontWeight.w800)),
        content: const Text(
            'आपने कुछ बदलाव किए हैं। क्या आप बिना सेव के बाहर निकलना चाहते हैं?',
            style: TextStyle(color: kDark)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('रद्द करें', style: TextStyle(color: kSubtle))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: kError, foregroundColor: Colors.white),
            child: const Text('बाहर निकलें')),
        ],
      ),
    );
    return discard == true;
  }

  @override
  Widget build(BuildContext context) {
    final r = rOf(context);
    final filledCount = _duties.where((d) => _hasAny(_byDuty[d.type])).length;
    final totalAll    = _duties.where((d) => _hasAny(_byDuty[d.type]))
        .fold<int>(0, (s, d) => s + _totalStaff(_byDuty[d.type]));
    final assignedAll = _duties.fold<int>(0, (s, d) => s + d.totalAssigned);
    final isJobRunning =
        _autoJobStatus == 'running' || _autoJobStatus == 'pending';

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          backgroundColor: kDistrictColor,
          foregroundColor: Colors.white,
          elevation: 0,
          titleSpacing: 0,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('जनपदीय कानून व्यवस्था',
                style: TextStyle(fontSize: r.s(14, 16), fontWeight: FontWeight.w800),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('मानक + ड्यूटी असाइनमेंट',
                style: TextStyle(fontSize: r.s(10, 11.5), color: Colors.white70),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
          actions: [
            IconButton(
              icon: const Icon(Icons.print_outlined, size: 20),
              tooltip: 'रिपोर्ट प्रिंट करें',
              onPressed: _loading ? null : _openPrintReport),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: 'पुनः लोड करें',
              onPressed: _loadAll),
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, size: 20),
              tooltip: 'सभी Assignments हटाएं',
              onPressed: isJobRunning ? null : _clearAllAssignments),
            if (_changed)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Center(child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(20)),
                    child: const Text('अनसेव्ड',
                        style: TextStyle(color: Colors.white, fontSize: 10,
                            fontWeight: FontWeight.w800))))),
          ],
          bottom: TabBar(
            controller: _tabCtrl,
            indicatorColor: Colors.white, labelColor: Colors.white,
            unselectedLabelColor: Colors.white70, indicatorWeight: 3,
            labelStyle: TextStyle(fontSize: r.s(11.5, 13), fontWeight: FontWeight.w800),
            unselectedLabelStyle:
                TextStyle(fontSize: r.s(11, 12.5), fontWeight: FontWeight.w500),
            tabs: const [Tab(text: 'मानक'), Tab(text: 'ड्यूटी')],
          ),
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: kDistrictColor))
            : Column(children: [
                if (isJobRunning || _autoJobStatus == 'done')
                  _AutoAssignBanner(
                    status: _autoJobStatus, pct: _autoJobPct,
                    assigned: _autoAssigned, skipped: _autoSkipped,
                    onDismiss: () => _safeSetState(() => _autoJobStatus = '')),
                Expanded(child: TabBarView(controller: _tabCtrl, children: [
                  _ManakvTab(
                    duties: _duties, byDuty: _byDuty,
                    filledCount: filledCount, totalAll: totalAll,
                    hasAny: _hasAny, totalStaff: _totalStaff,
                    onEdit: _openRankEditor,
                    onAdd: () => _showAddDialog(),
                    onEditCustom: (e) => _showAddDialog(editing: e),
                    onDelete: _deleteCustomDuty),
                  _DutyTab(
                    duties: _duties, summary: _summary,
                    assignedAll: assignedAll,
                    onOpenDetail: _openDutyDetail, onRefresh: _loadAll),
                ])),
              ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(r.s(10, 14), 8, r.s(10, 14), 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(height: r.s(44, 48),
                child: ElevatedButton.icon(
                  onPressed: isJobRunning ? null : _startAutoAssign,
                  icon: isJobRunning
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_fix_high, size: 17),
                  label: FittedBox(child: Text(
                      isJobRunning
                          ? 'Running... $_autoJobPct%'
                          : 'Auto Assign',
                      style: TextStyle(
                          fontSize: r.s(12, 13.5), fontWeight: FontWeight.w800))),
                  style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isJobRunning ? kSubtle : kOrange,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0))),
              const SizedBox(height: 8),
              Row(children: [
                GestureDetector(
                  onTap: () => _showAddDialog(),
                  child: Container(
                    height: r.s(46, 50),
                    padding: EdgeInsets.symmetric(horizontal: r.s(10, 14)),
                    decoration: BoxDecoration(
                        color: kCustomColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kCustomColor.withOpacity(0.4))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add_circle_outline, color: kCustomColor, size: r.s(18, 20)),
                      const SizedBox(width: 6),
                      Text('नया जोड़ें', style: TextStyle(
                          color: kCustomColor, fontSize: r.s(11.5, 13),
                          fontWeight: FontWeight.w700)),
                    ]))),
                const SizedBox(width: 10),
                Expanded(child: SizedBox(height: r.s(46, 50),
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _saveAll,
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Icon(Icons.save_rounded, size: r.s(16, 18)),
                    label: FittedBox(child: Text(_saving ? 'सेव हो रहा है...' : 'मानक सेव करें',
                        style: TextStyle(
                            fontSize: r.s(12.5, 14), fontWeight: FontWeight.w800))),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _saving ? kSubtle : kDistrictColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0)))),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DISTRICT DUTY PRINT PAGE
// ══════════════════════════════════════════════════════════════════════════════
class DistrictDutyPrintPage extends StatefulWidget {
  final List<_DutyEntry>                        duties;
  final Map<String, Map<String, dynamic>>       byDuty;
  final Map<String, Map<String, dynamic>>       summary;
  final Map<String, List<Map<String, dynamic>>> allBatches;

  const DistrictDutyPrintPage({
    super.key,
    required this.duties,
    required this.byDuty,
    required this.summary,
    required this.allBatches,
  });

  @override
  State<DistrictDutyPrintPage> createState() => _DistrictDutyPrintPageState();
}

class _DistrictDutyPrintPageState extends State<DistrictDutyPrintPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _generating = false;

  final _searchCtrl = TextEditingController();
  String _searchQ   = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _searchCtrl.addListener(
        () => setState(() => _searchQ = _searchCtrl.text.trim()));
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── helpers ────────────────────────────────────────────────────────────────
  int _n(Map<String, dynamic>? r, String k) =>
      r == null ? 0 : ((r[k] ?? 0) as num).toInt();

  int _totalStaffRule(Map<String, dynamic>? r) {
    if (r == null) return 0;
    int t = 0;
    for (final k in [
      'siArmedCount', 'siUnarmedCount', 'hcArmedCount', 'hcUnarmedCount',
      'constArmedCount', 'constUnarmedCount', 'auxArmedCount', 'auxUnarmedCount'
    ]) t += ((r[k] ?? 0) as num).toInt();
    return t;
  }

  String get _dateStr {
    final n = DateTime.now();
    return '${n.day.toString().padLeft(2, '0')}/'
        '${n.month.toString().padLeft(2, '0')}/${n.year}'
        '  ${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  String _ns(int v) => v == 0 ? '-' : '$v';

  List<_DutyEntry> get _filteredDuties {
    if (_searchQ.isEmpty) return widget.duties;
    final q = _searchQ.toLowerCase();
    return widget.duties
        .where((d) => d.label.toLowerCase().contains(q))
        .toList();
  }

  // ── grand totals ───────────────────────────────────────────────────────────
  Map<String, dynamic> get _totals {
    int san = 0, siA = 0, siU = 0, hcA = 0, hcU = 0,
        cA = 0, cU = 0, auxA = 0, auxU = 0, asgn = 0, batch = 0;
    double pac = 0;
    for (final d in widget.duties) {
      final r = widget.byDuty[d.type];
      san  += d.sankhya;
      siA  += _n(r, 'siArmedCount');   siU  += _n(r, 'siUnarmedCount');
      hcA  += _n(r, 'hcArmedCount');   hcU  += _n(r, 'hcUnarmedCount');
      cA   += _n(r, 'constArmedCount');cU   += _n(r, 'constUnarmedCount');
      auxA += _n(r, 'auxArmedCount');  auxU += _n(r, 'auxUnarmedCount');
      pac  += ((r?['pacCount'] ?? 0) as num).toDouble();
      final s = widget.summary[d.type] ?? {};
      asgn  += ((s['totalAssigned'] ?? 0) as num).toInt();
      batch += ((s['batchCount']    ?? 0) as num).toInt();
    }
    return {
      'sankhya': san, 'siA': siA, 'siU': siU, 'hcA': hcA, 'hcU': hcU,
      'cA': cA, 'cU': cU, 'auxA': auxA, 'auxU': auxU, 'pac': pac,
      'assigned': asgn, 'batches': batch,
    };
  }

  String _ruleStr(Map<String, dynamic> r) {
    final parts = <String>[];
    final siA = _n(r,'siArmedCount'), siU = _n(r,'siUnarmedCount');
    final hcA = _n(r,'hcArmedCount'), hcU = _n(r,'hcUnarmedCount');
    final cA  = _n(r,'constArmedCount'), cU = _n(r,'constUnarmedCount');
    final aA  = _n(r,'auxArmedCount'), aU = _n(r,'auxUnarmedCount');
    final pac = ((r['pacCount'] ?? 0) as num).toInt();
    if (siA > 0) parts.add('SI स. $siA');
    if (siU > 0) parts.add('SI नि. $siU');
    if (hcA > 0) parts.add('HC स. $hcA');
    if (hcU > 0) parts.add('HC नि. $hcU');
    if (cA  > 0) parts.add('Con स. $cA');
    if (cU  > 0) parts.add('Con नि. $cU');
    if (aA  > 0) parts.add('Aux स. $aA');
    if (aU  > 0) parts.add('Aux नि. $aU');
    if (pac > 0) parts.add('PAC $pac');
    return parts.join('  |  ');
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  PDF BUILDER
  // ════════════════════════════════════════════════════════════════════════════
  Future<Uint8List> _buildPdf({String section = 'all'}) async {
    final font = await PdfGoogleFonts.notoSansDevanagariRegular();
    final bold = await PdfGoogleFonts.notoSansDevanagariBold();
    final doc  = pw.Document();

    final tot = _totals;

    // ── text styles ──────────────────────────────────────────────────────────
    final tBase = pw.TextStyle(font: font, fontSize: 8);
    final tBold = pw.TextStyle(font: bold, fontSize: 8, fontWeight: pw.FontWeight.bold);
    final tHdr  = pw.TextStyle(font: bold, fontSize: 12, fontWeight: pw.FontWeight.bold);
    final tSm   = pw.TextStyle(font: font, fontSize: 7);
    final tSmB  = pw.TextStyle(font: bold, fontSize: 7, fontWeight: pw.FontWeight.bold);

    // ── cell builders ────────────────────────────────────────────────────────
    pw.Widget thCell(String t, {double? w}) => pw.Container(
      width: w,
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1A1A2E)),
      child: pw.Text(t,
          style: pw.TextStyle(font: bold, fontSize: 7.5,
              color: PdfColors.white, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center),
    );

    pw.Widget tdCell(String t, {double? w, bool left = false,
        pw.TextStyle? style, PdfColor? bg}) => pw.Container(
      width: w,
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      decoration: pw.BoxDecoration(color: bg),
      child: pw.Text(t,
          style: style ?? tBase,
          textAlign: left ? pw.TextAlign.left : pw.TextAlign.center,
          maxLines: 2),
    );

    pw.Widget secBar(String t) => pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF3A3A5C)),
      child: pw.Text(t, style: pw.TextStyle(font: bold, fontSize: 9,
          color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
    );

    pw.Widget statBox(String label, String value) => pw.Container(
      margin: const pw.EdgeInsets.only(right: 12),
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 0.6),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        color: PdfColor.fromInt(0xFFF8F8FF),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 14,
            fontWeight: pw.FontWeight.bold)),
        pw.Text(label, style: tSm),
      ]),
    );

    // ── page header / footer ─────────────────────────────────────────────────
    pw.Widget docHeader(String title, {String? subtitle}) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('जनपदीय कानून व्यवस्था — ड्यूटी विवरण', style: tHdr),
            pw.Text(title, style: pw.TextStyle(font: bold, fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromInt(0xFF3A3A5C))),
            if (subtitle != null)
              pw.Text(subtitle, style: tSm),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('दिनांक: $_dateStr', style: tSm),
            pw.Text('गोपनीय', style: tSmB),
          ]),
        ]),
        pw.SizedBox(height: 4),
        pw.Container(height: 2, color: PdfColors.black),
        pw.SizedBox(height: 1),
        pw.Container(height: 0.5, color: PdfColors.grey600),
        pw.SizedBox(height: 8),
      ],
    );

    pw.Widget footer(pw.Context ctx) => pw.Container(
      padding: const pw.EdgeInsets.only(top: 4),
      decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(
              color: PdfColors.grey400, width: 0.5))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('जनपदीय कानून व्यवस्था — गोपनीय', style: tSm),
          pw.Text('पृष्ठ ${ctx.pageNumber} / ${ctx.pagesCount}', style: tSm),
        ]),
    );

    final stripe1 = PdfColors.white;
    final stripe2 = PdfColor.fromInt(0xFFF6F3FF);
    final footerBg = PdfColor.fromInt(0xFFE8E0F5);
    final batchBg  = PdfColor.fromInt(0xFFEDE3F8);

    // ════════════════════════════════════════════════════════════════════════
    //  PAGE 1 — मानक विवरण
    // ════════════════════════════════════════════════════════════════════════
    if (section == 'all' || section == 'manak') {
      final rows = <pw.TableRow>[
        pw.TableRow(children: [
          thCell('क्र.',       w: 22), thCell('ड्यूटी प्रकार', w: 115),
          thCell('संख्या',     w: 36),
          thCell('SI\nस.',     w: 26), thCell('SI\nनि.',   w: 26),
          thCell('HC\nस.',     w: 26), thCell('HC\nनि.',   w: 26),
          thCell('Con\nस.',    w: 28), thCell('Con\nनि.',  w: 28),
          thCell('Aux\nस.',    w: 26), thCell('Aux\nनि.',  w: 26),
          thCell('PAC',        w: 26), thCell('कुल',        w: 30),
        ]),
      ];
      int srl = 0;
      for (final d in widget.duties) {
        srl++;
        final r   = widget.byDuty[d.type];
        final pac = r == null ? 0.0 : ((r['pacCount'] ?? 0) as num).toDouble();
        final bg  = srl % 2 == 0 ? stripe2 : stripe1;
        rows.add(pw.TableRow(children: [
          tdCell('$srl',          w: 22,  bg: bg),
          tdCell(d.label,         w: 115, left: true, bg: bg),
          tdCell(d.sankhya > 0 ? '${d.sankhya}' : '-', w: 36,
              style: d.sankhya > 0 ? tBold : tBase, bg: bg),
          tdCell(_ns(_n(r,'siArmedCount')),     w: 26, bg: bg),
          tdCell(_ns(_n(r,'siUnarmedCount')),   w: 26, bg: bg),
          tdCell(_ns(_n(r,'hcArmedCount')),     w: 26, bg: bg),
          tdCell(_ns(_n(r,'hcUnarmedCount')),   w: 26, bg: bg),
          tdCell(_ns(_n(r,'constArmedCount')),  w: 28, bg: bg),
          tdCell(_ns(_n(r,'constUnarmedCount')),w: 28, bg: bg),
          tdCell(_ns(_n(r,'auxArmedCount')),    w: 26, bg: bg),
          tdCell(_ns(_n(r,'auxUnarmedCount')),  w: 26, bg: bg),
          tdCell(pac == 0 ? '-' : '${pac.toInt()}', w: 26, bg: bg),
          tdCell(r == null ? '-' : '${_totalStaffRule(r)}', w: 30,
              style: tBold, bg: bg),
        ]));
      }
      // totals
      rows.add(pw.TableRow(children: [
        tdCell('',    w: 22,  bg: footerBg, style: tBold),
        tdCell('योग', w: 115, bg: footerBg, left: true, style: tBold),
        tdCell('${tot['sankhya']}', w: 36, bg: footerBg, style: tBold),
        tdCell('${tot['siA']}',  w: 26, bg: footerBg, style: tBold),
        tdCell('${tot['siU']}',  w: 26, bg: footerBg, style: tBold),
        tdCell('${tot['hcA']}',  w: 26, bg: footerBg, style: tBold),
        tdCell('${tot['hcU']}',  w: 26, bg: footerBg, style: tBold),
        tdCell('${tot['cA']}',   w: 28, bg: footerBg, style: tBold),
        tdCell('${tot['cU']}',   w: 28, bg: footerBg, style: tBold),
        tdCell('${tot['auxA']}', w: 26, bg: footerBg, style: tBold),
        tdCell('${tot['auxU']}', w: 26, bg: footerBg, style: tBold),
        tdCell((tot['pac'] as double) == 0
            ? '-' : '${(tot['pac'] as double).toInt()}',
            w: 26, bg: footerBg, style: tBold),
        tdCell('${(tot['siA'] as int) + (tot['siU'] as int) + (tot['hcA'] as int) + (tot['hcU'] as int) + (tot['cA'] as int) + (tot['cU'] as int) + (tot['auxA'] as int) + (tot['auxU'] as int)}',
            w: 30, bg: footerBg, style: tBold),
      ]));

      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(18, 18, 18, 24),
        footer: footer,
        build: (_) => [
          docHeader('मानक विवरण — पृष्ठ १'),
          pw.Row(children: [
            statBox('कुल ड्यूटी', '${widget.duties.length}'),
            statBox('संख्या योग', '${tot['sankhya']}'),
            statBox('पुलिस बल',
                '${(tot['siA'] as int) + (tot['siU'] as int) + (tot['hcA'] as int) + (tot['hcU'] as int) + (tot['cA'] as int) + (tot['cU'] as int) + (tot['auxA'] as int) + (tot['auxU'] as int)}'),
          ]),
          pw.SizedBox(height: 10),
          secBar('ड्यूटी प्रकारवार पुलिस बल मानक'),
          pw.SizedBox(height: 4),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
            children: rows),
        ],
      ));
    }

    // ════════════════════════════════════════════════════════════════════════
    //  PAGE 2 — असाइनमेंट सारांश
    // ════════════════════════════════════════════════════════════════════════
    if (section == 'all' || section == 'assign') {
      final rows = <pw.TableRow>[
        pw.TableRow(children: [
          thCell('क्र.',      w: 22), thCell('ड्यूटी प्रकार', w: 135),
          thCell('आवश्यक',   w: 50), thCell('Assigned', w: 55),
          thCell('Batches',  w: 50), thCell('शेष',      w: 44),
          thCell('स्थिति',   w: 60),
        ]),
      ];
      int srl = 0;
      for (final d in widget.duties) {
        srl++;
        final s     = widget.summary[d.type] ?? {};
        final asgn  = ((s['totalAssigned'] ?? 0) as num).toInt();
        final batch = ((s['batchCount'] ?? 0) as num).toInt();
        final req   = d.sankhya;
        final rem   = (req - asgn).clamp(0, 999999);
        final bg    = srl % 2 == 0 ? stripe2 : stripe1;
        String status;
        if (req == 0)        status = 'मानक नहीं';
        else if (asgn > req) status = 'अधिक';
        else if (asgn >= req)status = 'पूर्ण ✓';
        else if (asgn == 0)  status = 'खाली';
        else                 status = 'आंशिक';
        rows.add(pw.TableRow(children: [
          tdCell('$srl',   w: 22,  bg: bg),
          tdCell(d.label,  w: 135, left: true, bg: bg),
          tdCell(req > 0 ? '$req' : '-', w: 50, bg: bg),
          tdCell('$asgn',  w: 55, style: asgn > 0 ? tBold : tBase, bg: bg),
          tdCell('$batch', w: 50, bg: bg),
          tdCell(req > 0 ? '$rem' : '-', w: 44, bg: bg),
          tdCell(status,   w: 60, bg: bg),
        ]));
      }
      rows.add(pw.TableRow(children: [
        tdCell('',    w: 22,  bg: footerBg, style: tBold),
        tdCell('योग', w: 135, bg: footerBg, left: true, style: tBold),
        tdCell('${tot['sankhya']}', w: 50, bg: footerBg, style: tBold),
        tdCell('${tot['assigned']}',w: 55, bg: footerBg, style: tBold),
        tdCell('${tot['batches']}', w: 50, bg: footerBg, style: tBold),
        tdCell('${((tot['sankhya'] as int) - (tot['assigned'] as int)).clamp(0, 999999)}',
            w: 44, bg: footerBg, style: tBold),
        tdCell('', w: 60, bg: footerBg, style: tBold),
      ]));

      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(18, 18, 18, 24),
        footer: footer,
        build: (_) => [
          docHeader('असाइनमेंट सारांश — पृष्ठ २'),
          pw.Row(children: [
            statBox('आवश्यक',    '${tot['sankhya']}'),
            statBox('Assigned', '${tot['assigned']}'),
            statBox('Batches',  '${tot['batches']}'),
            statBox('शेष',
                '${((tot['sankhya'] as int) - (tot['assigned'] as int)).clamp(0, 999999)}'),
          ]),
          pw.SizedBox(height: 10),
          secBar('ड्यूटी असाइनमेंट स्थिति'),
          pw.SizedBox(height: 4),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
            children: rows),
        ],
      ));
    }

    // ════════════════════════════════════════════════════════════════════════
    //  PAGES 3+ — Per-duty BATCH-GROUPED table
    //  Each batch gets a header row + staff rows below it
    // ════════════════════════════════════════════════════════════════════════
    final dutiesToPrint = (section == 'all' || section == 'duty')
        ? widget.duties
        : widget.duties.where((d) => d.type == section).toList();

    for (final d in dutiesToPrint) {
      final batches = widget.allBatches[d.type] ?? [];
      if (batches.isEmpty) continue;
      final rule  = widget.byDuty[d.type];
      final total = batches.fold<int>(
          0, (s, b) => s + ((b['staffCount'] ?? 0) as num).toInt());
      final rStr  = rule != null ? _ruleStr(rule) : '';

      final staffRows = <pw.TableRow>[
        // Outer header
        pw.TableRow(children: [
          thCell('क्र.',    w: 24), thCell('नाम',    w: 100),
          thCell('PNO',      w: 56), thCell('पद',     w: 64),
          thCell('थाना',     w: 72), thCell('मोबाइल', w: 70),
          thCell('Armed',    w: 36), thCell('बस',     w: 36),
        ]),
      ];

      int globalSrl = 0;
      for (int bi = 0; bi < batches.length; bi++) {
        final b     = batches[bi];
        final bNo   = b['batchNo'] as int? ?? (bi + 1);
        final staff = (b['staff'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final busNo = b['busNo'] as String? ?? '';
        final note  = b['note']  as String? ?? '';

        // Batch header row (spans visually via single cell + bg)
        staffRows.add(pw.TableRow(
          decoration: pw.BoxDecoration(color: batchBg),
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEDE3F8)),
              child: pw.Text('B$bNo',
                  style: pw.TextStyle(font: bold, fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromInt(0xFF6C3483)),
                  textAlign: pw.TextAlign.center),
            ),
            // Span: name col gets the batch label
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEDE3F8)),
              child: pw.Text(
                  'Batch $bNo  •  ${staff.length} staff'
                  '${busNo.isNotEmpty ? '  •  Bus: $busNo' : ''}'
                  '${note.isNotEmpty ? '  •  $note' : ''}',
                  style: pw.TextStyle(font: bold, fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromInt(0xFF4A2A6A))),
            ),
            // Empty cells filling the rest of the row
            for (int i = 0; i < 6; i++)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 5),
                decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEDE3F8)),
                child: pw.Text(''),
              ),
          ],
        ));

        // Staff rows for this batch
        for (final s in staff) {
          globalSrl++;
          final isArmed = (s['isArmed'] as bool?) == true;
          final bg = globalSrl % 2 == 0 ? stripe2 : stripe1;
          staffRows.add(pw.TableRow(children: [
            tdCell('$globalSrl',                     w: 24, bg: bg),
            tdCell(s['name']   as String? ?? '-',    w: 100, left: true, bg: bg),
            tdCell(s['pno']    as String? ?? '-',    w: 56, bg: bg),
            tdCell(s['rank']   as String? ?? '-',    w: 64, bg: bg),
            tdCell(s['thana']  as String? ?? '-',    w: 72, left: true, bg: bg),
            tdCell(s['mobile'] as String? ?? '-',    w: 70, bg: bg),
            tdCell(isArmed ? 'हाँ' : 'नहीं',          w: 36, bg: bg),
            tdCell(busNo.isEmpty ? '-' : busNo,      w: 36, bg: bg),
          ]));
        }
      }

      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(18, 18, 18, 24),
        footer: footer,
        build: (_) => [
          docHeader(d.label,
              subtitle: '${batches.length} Batches  •  $total Assigned'
                  '  •  संख्या: ${d.sankhya}'),
          pw.Row(children: [
            statBox('संख्या',   '${d.sankhya}'),
            statBox('Assigned', '$total'),
            statBox('Batches',  '${batches.length}'),
            statBox('स्थिति',
                total >= d.sankhya && d.sankhya > 0 ? 'पूर्ण ✓' : 'आंशिक'),
          ]),
          if (rStr.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Container(
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                color: PdfColor.fromInt(0xFFF8F8FF),
              ),
              child: pw.Text('पुलिस बल मानक: $rStr', style: tSm)),
          ],
          pw.SizedBox(height: 8),
          secBar('${d.label} — Batch-wise Staff विवरण'),
          pw.SizedBox(height: 4),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
            children: staffRows),
        ],
      ));
    }

    if (doc.document.pdfPageList.pages.isEmpty) {
      doc.addPage(pw.Page(build: (_) => pw.Center(
          child: pw.Text('कोई डेटा नहीं',
              style: pw.TextStyle(font: bold, fontSize: 14)))));
    }

    return Uint8List.fromList(await doc.save());
  }

  // ── trigger print ──────────────────────────────────────────────────────────
  Future<void> _print({String section = 'all'}) async {
    setState(() => _generating = true);
    try {
      await Printing.layoutPdf(
        onLayout: (_) async => _buildPdf(section: section),
        name: 'जनपदीय_ड्यूटी_विवरण',
        format: PdfPageFormat.a4,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Print विफल: $e'), backgroundColor: kError));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final r = rOf(context);
    final t = _totals;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kDistrictColor,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('प्रिंट रिपोर्ट',
              style: TextStyle(fontSize: r.s(14, 16), fontWeight: FontWeight.w800)),
          Text('सेक्शन चुनें → प्रिंट करें',
              style: TextStyle(fontSize: r.s(10, 11.5), color: Colors.white70)),
        ]),
        actions: [
          if (_generating)
            const Padding(padding: EdgeInsets.all(14),
              child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)))
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () => _print(section: 'all'),
                icon: const Icon(Icons.print_outlined, color: Colors.white, size: 18),
                label: const Text('सभी',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white, indicatorWeight: 3,
          labelColor: Colors.white, unselectedLabelColor: Colors.white60,
          labelStyle: TextStyle(fontSize: r.s(10.5, 12), fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'मानक'),
            Tab(text: 'असाइनमेंट'),
            Tab(text: 'ड्यूटी विवरण'),
          ],
        ),
      ),
      body: TabBarView(controller: _tab, children: [
        _buildManakTab(t),
        _buildAssignTab(t),
        _buildDutyTab(),
      ]),
    );
  }

  // ── Tab 1 ──────────────────────────────────────────────────────────────────
  Widget _buildManakTab(Map<String, dynamic> t) {
    final r = rOf(context);
    return Column(children: [
      _PrintSectionBar(
        title: 'मानक विवरण — पृष्ठ १',
        subtitle: '${widget.duties.length} ड्यूटी  •  संख्या: ${t['sankhya']}',
        icon: Icons.shield_outlined, color: kDistrictColor,
        onPrint: _generating ? null : () => _print(section: 'manak')),
      Expanded(child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(r.s(8, 12), 12, r.s(8, 12), 24),
        child: Column(children: [
          _StatRow(items: [
            _SI('${widget.duties.length}', 'ड्यूटी', kDistrictColor),
            _SI('${t['sankhya']}', 'संख्या', kOrange),
            _SI('${(t['siA'] as int)+(t['siU'] as int)+(t['hcA'] as int)+(t['hcU'] as int)+(t['cA'] as int)+(t['cU'] as int)+(t['auxA'] as int)+(t['auxU'] as int)}',
                'पुलिस बल', kAssignColor),
          ]),
          const SizedBox(height: 12),
          _GovTable(
            headers: const ['क्र.', 'ड्यूटी', 'संख्या', 'SI', 'HC', 'Con', 'Aux', 'PAC', 'कुल'],
            widths:  const [32, null, 52, 60, 60, 60, 60, 44, 52],
            rows: widget.duties.asMap().entries.map((e) {
              final d   = e.value;
              final r2  = widget.byDuty[d.type];
              final pac = r2 == null ? 0.0 : ((r2['pacCount'] ?? 0) as num).toDouble();
              return [
                '${e.key+1}', d.label,
                d.sankhya > 0 ? '${d.sankhya}' : '-',
                _ns(_n(r2,'siArmedCount') + _n(r2,'siUnarmedCount')),
                _ns(_n(r2,'hcArmedCount') + _n(r2,'hcUnarmedCount')),
                _ns(_n(r2,'constArmedCount') + _n(r2,'constUnarmedCount')),
                _ns(_n(r2,'auxArmedCount') + _n(r2,'auxUnarmedCount')),
                pac == 0 ? '-' : '${pac.toInt()}',
                r2 == null ? '-' : '${_totalStaffRule(r2)}',
              ];
            }).toList(),
            footerRow: [
              '', 'योग', '${t['sankhya']}',
              '${(t['siA'] as int)+(t['siU'] as int)}',
              '${(t['hcA'] as int)+(t['hcU'] as int)}',
              '${(t['cA'] as int)+(t['cU'] as int)}',
              '${(t['auxA'] as int)+(t['auxU'] as int)}',
              (t['pac'] as double) == 0 ? '-' : '${(t['pac'] as double).toInt()}',
              '${(t['siA'] as int)+(t['siU'] as int)+(t['hcA'] as int)+(t['hcU'] as int)+(t['cA'] as int)+(t['cU'] as int)+(t['auxA'] as int)+(t['auxU'] as int)}',
            ],
          ),
        ]),
      )),
    ]);
  }

  // ── Tab 2 ──────────────────────────────────────────────────────────────────
  Widget _buildAssignTab(Map<String, dynamic> t) {
    final r = rOf(context);
    return Column(children: [
      _PrintSectionBar(
        title: 'असाइनमेंट सारांश — पृष्ठ २',
        subtitle: '${t['assigned']} Assigned  •  ${t['batches']} Batches',
        icon: Icons.people_outlined, color: kAssignColor,
        onPrint: _generating ? null : () => _print(section: 'assign')),
      Expanded(child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(r.s(8, 12), 12, r.s(8, 12), 24),
        child: Column(children: [
          _StatRow(items: [
            _SI('${t['sankhya']}',  'आवश्यक',   kDistrictColor),
            _SI('${t['assigned']}', 'Assigned', kSuccess),
            _SI('${t['batches']}',  'Batches',  kOrange),
            _SI('${((t['sankhya'] as int)-(t['assigned'] as int)).clamp(0,999999)}',
                'शेष', kError),
          ]),
          const SizedBox(height: 12),
          _GovTable(
            headers: const ['क्र.', 'ड्यूटी', 'आवश्यक', 'Assigned', 'Batches', 'शेष', 'स्थिति'],
            widths:  const [32, null, 62, 70, 62, 50, 76],
            rows: widget.duties.asMap().entries.map((e) {
              final d     = e.value;
              final s     = widget.summary[d.type] ?? {};
              final asgn  = ((s['totalAssigned'] ?? 0) as num).toInt();
              final batch = ((s['batchCount'] ?? 0) as num).toInt();
              final req   = d.sankhya;
              final rem   = (req - asgn).clamp(0, 999999);
              String status;
              if (req == 0)        status = 'मानक नहीं';
              else if (asgn > req) status = 'अधिक';
              else if (asgn >= req)status = 'पूर्ण ✓';
              else if (asgn == 0)  status = 'खाली';
              else                 status = 'आंशिक';
              return [
                '${e.key+1}', d.label,
                req > 0 ? '$req' : '-', '$asgn',
                '$batch', req > 0 ? '$rem' : '-', status,
              ];
            }).toList(),
            footerRow: [
              '', 'योग', '${t['sankhya']}', '${t['assigned']}', '${t['batches']}',
              '${((t['sankhya'] as int)-(t['assigned'] as int)).clamp(0,999999)}', '',
            ],
            statusColIdx: 6,
          ),
        ]),
      )),
    ]);
  }

  // ── Tab 3 ──────────────────────────────────────────────────────────────────
  Widget _buildDutyTab() {
    final r = rOf(context);
    final filtered = _filteredDuties;
    return Column(children: [
      Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(r.s(8, 12), 10, r.s(8, 12), 8),
        child: Column(children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'ड्यूटी नाम खोजें...',
              hintStyle: const TextStyle(color: kSubtle, fontSize: 12),
              prefixIcon: const Icon(Icons.search, color: kSubtle, size: 18),
              suffixIcon: _searchQ.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16, color: kSubtle),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQ = '');
                      })
                  : null,
              filled: true, fillColor: const Color(0xFFF8F4FF), isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: kBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: kDistrictColor, width: 1.5)),
            ),
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(
              child: Text('${filtered.length} ड्यूटी प्रकार',
                  style: const TextStyle(color: kSubtle, fontSize: 11),
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            if (!_generating)
              GestureDetector(
                onTap: () => _print(section: 'duty'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: kOrange, borderRadius: BorderRadius.circular(8)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.print_outlined, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text('सभी Duty प्रिंट', style: TextStyle(
                        color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ]),
                ),
              )
            else
              const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: kDistrictColor)),
          ]),
        ]),
      ),
      Expanded(child: filtered.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.search_off, size: 48, color: kSubtle.withOpacity(0.4)),
              const SizedBox(height: 10),
              Text('"$_searchQ" नहीं मिला',
                  style: const TextStyle(color: kSubtle, fontSize: 13)),
            ]))
          : ListView.builder(
              padding: EdgeInsets.fromLTRB(r.s(8, 12), 8, r.s(8, 12), 24),
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final d       = filtered[i];
                final batches = widget.allBatches[d.type] ?? [];
                final total   = batches.fold<int>(
                    0, (s, b) => s + ((b['staffCount'] ?? 0) as num).toInt());
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DutyPreviewCard(
                    duty: d, batches: batches, total: total,
                    rule: widget.byDuty[d.type], n: _n,
                    onPrint: _generating ? null : () => _print(section: d.type),
                  ),
                );
              },
            )),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  PRINT SECTION BAR
// ══════════════════════════════════════════════════════════════════════════════
class _PrintSectionBar extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onPrint;

  const _PrintSectionBar({required this.title, required this.subtitle,
      required this.icon, required this.color, required this.onPrint});

  @override
  Widget build(BuildContext context) {
    final r = rOf(context);
    return Container(
      color: color.withOpacity(0.07),
      padding: EdgeInsets.fromLTRB(r.s(10, 14), 10, r.s(8, 12), 10),
      child: Row(children: [
        Container(width: 34, height: 34,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: Colors.white, size: 17)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(
              color: color, fontSize: r.s(12, 13.5), fontWeight: FontWeight.w800),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(subtitle, style: const TextStyle(color: kSubtle, fontSize: 10),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        if (onPrint != null)
          GestureDetector(
            onTap: onPrint,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: r.s(10, 12), vertical: 7),
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.print_outlined, color: Colors.white, size: 15),
                const SizedBox(width: 5),
                Text('प्रिंट', style: TextStyle(
                    color: Colors.white, fontSize: r.s(11, 12), fontWeight: FontWeight.w800)),
              ]),
            ))
        else
          const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: kDistrictColor)),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  GOVERNMENT-STYLE ON-SCREEN TABLE (with batch grouping support)
// ══════════════════════════════════════════════════════════════════════════════
/// A row that can be a normal data row or a batch-header row that visually
/// spans the full width.
class _GovRow {
  final List<String> cells;
  final bool         isBatchHeader;
  final String?      batchLabel; // shown when isBatchHeader

  const _GovRow.data(this.cells)        : isBatchHeader = false, batchLabel = null;
  const _GovRow.batch(this.batchLabel)  : isBatchHeader = true, cells = const [];
}

class _GovTable extends StatelessWidget {
  final List<String>       headers;
  final List<double?>      widths;
  final List<List<String>> rows;          // legacy plain rows
  final List<_GovRow>?     groupedRows;   // optional grouped rows
  final List<String>?      footerRow;
  final int?               statusColIdx;

  const _GovTable({
    required this.headers, required this.widths,
    required this.rows, this.footerRow, this.statusColIdx,
    this.groupedRows,
  });

  Color _statusColor(String s) {
    if (s.contains('✓') || s == 'पूर्ण') return kSuccess;
    if (s == 'खाली') return kError;
    if (s == 'आंशिक') return kOrange;
    if (s == 'अधिक') return const Color(0xFF6A1B9A);
    return kSubtle;
  }

  /// Index of the "flex" (name/label) column. We treat the FIRST null-width
  /// column as the flex column and give it a sensible minimum width so that
  /// Devanagari text doesn't wrap one syllable per line.
  int get _flexColIdx {
    for (int i = 0; i < widths.length; i++) {
      if (widths[i] == null) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final effective = groupedRows ?? rows.map((r) => _GovRow.data(r)).toList();
    if (effective.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(8),
            border: Border.all(color: kBorder.withOpacity(0.4))),
        child: const Center(child: Text('कोई डेटा नहीं',
            style: TextStyle(color: kSubtle, fontSize: 12))));
    }

    final flexIdx = _flexColIdx;

    // Compute a sensible MIN width for the flex (name) column based on the
    // longest content in that column. Without this, putting a Table inside a
    // horizontal SingleChildScrollView causes FlexColumnWidth to collapse to
    // ~1 character wide, which makes Devanagari text wrap one syllable per
    // line. We measure the longest string and give it ~7.2px per char, capped.
    double flexMinWidth = 140;
    if (flexIdx >= 0) {
      int maxLen = headers[flexIdx].length;
      for (final row in effective) {
        if (row.isBatchHeader) continue;
        if (flexIdx < row.cells.length) {
          final l = row.cells[flexIdx].length;
          if (l > maxLen) maxLen = l;
        }
      }
      flexMinWidth = (maxLen * 7.2 + 24).clamp(130.0, 220.0);
    }

    // Total fixed-column width sum.
    double totalFixed = 0;
    for (final w in widths) {
      if (w != null) totalFixed += w;
    }
    final fullMinWidth = totalFixed + (flexIdx >= 0 ? flexMinWidth : 0);

    return LayoutBuilder(builder: (context, constraints) {
      final available = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : MediaQuery.of(context).size.width;
      // If screen is wider than required, let the flex column expand to fill
      // remaining space; otherwise keep it at content-driven min and allow
      // horizontal scroll.
      final flexWidth = (flexIdx >= 0 && available > fullMinWidth)
          ? (available - totalFixed - 2)
          : flexMinWidth;
      final tableWidth = totalFixed + (flexIdx >= 0 ? flexWidth : 0);

      final tableWidget = SizedBox(
        width: tableWidth,
        child: Table(
          border: TableBorder.all(
              color: kBorder.withOpacity(0.3), width: 0.6),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: {
            for (int i = 0; i < widths.length; i++)
              i: FixedColumnWidth(
                widths[i] ?? (i == flexIdx ? flexWidth : 100),
              ),
          },
          children: [
            // header
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFF1A1A2E)),
              children: headers.asMap().entries.map((he) {
                final hi = he.key;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 8),
                  child: Text(he.value,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 10,
                          fontWeight: FontWeight.w800),
                      softWrap: true,
                      textAlign: hi == flexIdx
                          ? TextAlign.left : TextAlign.center),
                );
              }).toList(),
            ),
            // data
            ...effective.asMap().entries.map((e) {
              final i = e.key;
              final row = e.value;
              if (row.isBatchHeader) {
                return TableRow(
                  decoration:
                      const BoxDecoration(color: Color(0xFFEDE3F8)),
                  children: List.generate(headers.length, (ci) {
                    String txt = '';
                    if (ci == 0) txt = 'B';
                    else if (ci == 1) txt = row.batchLabel ?? '';
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 7),
                      child: Text(txt,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF4A2A6A)),
                          softWrap: true,
                          textAlign: ci <= 1
                              ? TextAlign.left : TextAlign.center),
                    );
                  }),
                );
              }
              return TableRow(
                decoration: BoxDecoration(
                    color: i.isEven
                        ? Colors.white : const Color(0xFFFAF8F0)),
                children: row.cells.asMap().entries.map((ce) {
                  final ci = ce.key; final cell = ce.value;
                  Color? textColor;
                  if (ci == statusColIdx) textColor = _statusColor(cell);
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 6),
                    child: Text(cell,
                        style: TextStyle(
                            fontSize: 11,
                            color:
                                textColor ?? const Color(0xFF2C2C2C),
                            fontWeight: ci == 0 || textColor != null
                                ? FontWeight.w600
                                : FontWeight.normal),
                        softWrap: true,
                        textAlign: ci == flexIdx
                            ? TextAlign.left : TextAlign.center),
                  );
                }).toList(),
              );
            }),
            // footer
            if (footerRow != null)
              TableRow(
                decoration:
                    const BoxDecoration(color: Color(0xFFECE5F5)),
                children: footerRow!.asMap().entries.map((e) => Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 8),
                      child: Text(e.value,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF2C2C2C)),
                          softWrap: true,
                          textAlign: e.key == flexIdx
                              ? TextAlign.left : TextAlign.center),
                    )).toList(),
              ),
          ],
        ),
      );

      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: kBorder.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
                color: kDistrictColor.withOpacity(0.05),
                blurRadius: 6, offset: const Offset(0, 2))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: tableWidth <= available
              ? tableWidget
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: tableWidget,
                ),
        ),
      );
    });
  }
}

// ── Stat row ──────────────────────────────────────────────────────────────────
class _SI {
  final String value, label; final Color color;
  const _SI(this.value, this.label, this.color);
}

class _StatRow extends StatelessWidget {
  final List<_SI> items;
  const _StatRow({required this.items});
  @override
  Widget build(BuildContext context) {
    final r = rOf(context);
    // Wrap on small screens so cards don't overflow
    if (r.isCompact) {
      return Wrap(
        spacing: 6, runSpacing: 6,
        children: items.map((s) => SizedBox(
          width: (MediaQuery.of(context).size.width - 16 - 6) / 2,
          child: _statCard(s, r),
        )).toList(),
      );
    }
    return Row(
      children: items.map((s) => Expanded(child: Container(
        margin: const EdgeInsets.only(right: 8),
        child: _statCard(s, r),
      ))).toList(),
    );
  }

  Widget _statCard(_SI s, RScale r) => Container(
    padding: EdgeInsets.symmetric(horizontal: r.s(8, 10), vertical: 10),
    decoration: BoxDecoration(
      color: s.color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: s.color.withOpacity(0.25)),
    ),
    child: Column(children: [
      FittedBox(child: Text(s.value, style: TextStyle(color: s.color,
          fontSize: r.s(18, 20), fontWeight: FontWeight.w900))),
      const SizedBox(height: 2),
      FittedBox(child: Text(s.label, style: TextStyle(color: s.color.withOpacity(0.8),
          fontSize: r.s(9.5, 10), fontWeight: FontWeight.w600))),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  DUTY PREVIEW CARD  (Tab 3 on-screen) — BATCH-GROUPED ROWS
// ══════════════════════════════════════════════════════════════════════════════
class _DutyPreviewCard extends StatefulWidget {
  final _DutyEntry duty;
  final List<Map<String, dynamic>> batches;
  final int total;
  final Map<String, dynamic>? rule;
  final int Function(Map<String, dynamic>?, String) n;
  final VoidCallback? onPrint;

  const _DutyPreviewCard({required this.duty, required this.batches,
      required this.total, required this.rule, required this.n,
      required this.onPrint});

  @override
  State<_DutyPreviewCard> createState() => _DutyPreviewCardState();
}

class _DutyPreviewCardState extends State<_DutyPreviewCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final r       = rOf(context);
    final d       = widget.duty;
    final color   = d.isDefault ? kDistrictColor : kCustomColor;
    final isDone  = widget.total >= d.sankhya && d.sankhya > 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.06),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          child: Container(
            padding: EdgeInsets.fromLTRB(r.s(10, 12), 10, r.s(10, 12), 10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.07),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(children: [
              Container(width: 32, height: 32,
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(8)),
                  child: Icon(d.icon, color: Colors.white, size: 16)),
              const SizedBox(width: 10),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.label, style: TextStyle(
                    color: color, fontSize: r.s(12, 13), fontWeight: FontWeight.w800),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${widget.batches.length} Batches  •  ${widget.total} Assigned'
                    '${d.sankhya > 0 ? '  •  संख्या: ${d.sankhya}' : ''}',
                    style: TextStyle(color: kSubtle, fontSize: r.s(9.5, 10.5)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              if (isDone && !r.isCompact)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                      color: kSuccess.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Text('✓ पूर्ण', style: TextStyle(
                      color: kSuccess, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              if (widget.onPrint != null)
                GestureDetector(
                  onTap: widget.onPrint,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(7)),
                    child: const Icon(Icons.print_outlined,
                        color: Colors.white, size: 14),
                  ))
              else
                const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: kDistrictColor)),
              const SizedBox(width: 6),
              Icon(_expanded
                  ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: color, size: 20),
            ]),
          ),
        ),
        if (_expanded) ...[
          if (widget.batches.isEmpty)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('कोई batch नहीं है।',
                  style: TextStyle(color: kSubtle, fontSize: 12)))
          else
            Padding(
              padding: const EdgeInsets.all(10),
              child: _buildBatchGroupedTable(color),
            ),
        ],
      ]),
    );
  }

  /// Builds the grouped table where each batch gets a header row, followed
  /// by its staff rows below it.
  Widget _buildBatchGroupedTable(Color color) {
    final groupedRows = <_GovRow>[];
    int globalSrl = 0;
    for (final b in widget.batches) {
      final bNo   = b['batchNo'] as int? ?? 0;
      final staff = (b['staff'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final busNo = b['busNo'] as String? ?? '';
      final note  = b['note']  as String? ?? '';

      final label = StringBuffer('Batch $bNo  •  ${staff.length} staff');
      if (busNo.isNotEmpty) label.write('  •  Bus: $busNo');
      if (note.isNotEmpty)  label.write('  •  $note');
      groupedRows.add(_GovRow.batch(label.toString()));

      for (final s in staff) {
        globalSrl++;
        groupedRows.add(_GovRow.data([
          '$globalSrl',
          s['name']   as String? ?? '-',
          s['pno']    as String? ?? '-',
          s['rank']   as String? ?? '-',
          s['thana']  as String? ?? '-',
          s['mobile'] as String? ?? '-',
          (s['isArmed'] as bool?) == true ? 'हाँ' : 'नहीं',
        ]));
      }
    }

    return _GovTable(
      headers: const ['क्र.', 'नाम', 'PNO', 'पद', 'थाना', 'मोबाइल', 'Armed'],
      widths:  const [32, null, 76, 68, 84, 84, 48],
      rows: const [], // unused when groupedRows provided
      groupedRows: groupedRows,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  AUTO ASSIGN BANNER
// ══════════════════════════════════════════════════════════════════════════════
class _AutoAssignBanner extends StatelessWidget {
  final String status;
  final int pct, assigned, skipped;
  final VoidCallback onDismiss;

  const _AutoAssignBanner({required this.status, required this.pct,
      required this.assigned, required this.skipped, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final isRunning = status == 'running' || status == 'pending';
    final color = isRunning ? kOrange : kSuccess;
    return Container(
      color: color.withOpacity(0.1),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (isRunning)
            const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: kOrange))
          else
            const Icon(Icons.check_circle_rounded, color: kSuccess, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(
            isRunning
                ? 'Auto-assign चल रही है... $pct%'
                : '$assigned Staff assign हुए, $skipped skip',
            style: TextStyle(color: color, fontSize: 12,
                fontWeight: FontWeight.w800),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
          GestureDetector(onTap: onDismiss,
              child: Icon(Icons.close, size: 16, color: color)),
        ]),
        if (isRunning) ...[
          const SizedBox(height: 6),
          ClipRRect(borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct / 100.0,
              backgroundColor: kOrange.withOpacity(0.15),
              valueColor: const AlwaysStoppedAnimation(kOrange),
              minHeight: 4)),
        ],
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  TAB 1: MANAK
// ══════════════════════════════════════════════════════════════════════════════
class _ManakvTab extends StatelessWidget {
  final List<_DutyEntry>                  duties;
  final Map<String, Map<String, dynamic>> byDuty;
  final int                               filledCount, totalAll;
  final bool Function(Map<String, dynamic>?) hasAny;
  final int  Function(Map<String, dynamic>?) totalStaff;
  final void Function(_DutyEntry, int)       onEdit;
  final VoidCallback                         onAdd;
  final void Function(_DutyEntry)            onEditCustom, onDelete;

  const _ManakvTab({
    required this.duties, required this.byDuty,
    required this.filledCount, required this.totalAll,
    required this.hasAny, required this.totalStaff,
    required this.onEdit, required this.onAdd,
    required this.onEditCustom, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final r = rOf(context);
    return Column(children: [
      Container(
        color: kSurface,
        padding: EdgeInsets.symmetric(horizontal: r.s(10, 14), vertical: 10),
        child: Row(children: [
          const Icon(Icons.shield_outlined, size: 14, color: kDistrictColor),
          const SizedBox(width: 6),
          Expanded(child: Text('ड्यूटी प्रकार पर टैप करके पुलिस बल सेट करें',
              style: TextStyle(color: kDark, fontSize: r.s(10.5, 11.5),
                  fontWeight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text('$totalAll', style: TextStyle(
              color: kDistrictColor, fontSize: r.s(10.5, 11.5), fontWeight: FontWeight.w800)),
          const SizedBox(width: 4),
          Text('($filledCount/${duties.length})',
              style: TextStyle(color: kSubtle, fontSize: r.s(10, 11))),
        ])),
      Expanded(child: ListView.separated(
        padding: EdgeInsets.fromLTRB(r.s(8, 12), 12, r.s(8, 12), 120),
        itemCount: duties.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final entry = duties[i];
          final r2     = byDuty[entry.type];
          final isSet = hasAny(r2);
          return _DutyRuleCard(
            entry: entry, isSet: isSet,
            sankhya:    isSet ? ((r2!['sankhya'] ?? 0) as num).toInt() : 0,
            totalStaff: totalStaff(r2), rule: r2,
            onTap:   () => onEdit(entry, (i + 1) * 10),
            onEdit:   entry.isDefault ? null : () => onEditCustom(entry),
            onDelete: entry.isDefault ? null : () => onDelete(entry));
        },
      )),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  TAB 2: DUTY ASSIGNMENT
// ══════════════════════════════════════════════════════════════════════════════
class _DutyTab extends StatelessWidget {
  final List<_DutyEntry>                  duties;
  final Map<String, Map<String, dynamic>> summary;
  final int                               assignedAll;
  final void Function(_DutyEntry)         onOpenDetail;
  final VoidCallback                      onRefresh;

  const _DutyTab({
    required this.duties, required this.summary,
    required this.assignedAll, required this.onOpenDetail,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final r = rOf(context);
    if (duties.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.assignment_outlined, size: 56, color: kSubtle.withOpacity(0.3)),
      const SizedBox(height: 16),
      const Text('पहले मानक टैब में ड्यूटी प्रकार सेट करें',
          style: TextStyle(color: kSubtle, fontSize: 13)),
    ]));
    return Column(children: [
      Container(
        color: kAssignColor.withOpacity(0.07),
        padding: EdgeInsets.symmetric(horizontal: r.s(10, 14), vertical: 10),
        child: Row(children: [
          const Icon(Icons.people_outlined, size: 14, color: kAssignColor),
          const SizedBox(width: 6),
          Expanded(child: Text('ड्यूटी प्रकार पर टैप करके assign/view करें',
              style: TextStyle(color: kDark, fontSize: r.s(10.5, 11.5),
                  fontWeight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: kAssignColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Text('$assignedAll Assigned', style: TextStyle(
                color: kAssignColor, fontSize: r.s(10.5, 11.5),
                fontWeight: FontWeight.w800))),
        ])),
      Expanded(child: ListView.separated(
        padding: EdgeInsets.fromLTRB(r.s(8, 12), 12, r.s(8, 12), 120),
        itemCount: duties.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final entry    = duties[i];
          final s        = summary[entry.type] ?? {};
          final assigned = ((s['totalAssigned'] ?? 0) as num).toInt();
          final batches  = ((s['batchCount'] ?? 0) as num).toInt();
          final sankhya  = entry.sankhya;
          final pct = sankhya > 0
              ? (assigned / sankhya).clamp(0.0, 1.0) : 0.0;
          return _DutyAssignCard(
            entry: entry, assigned: assigned, batches: batches,
            sankhya: sankhya, pct: pct,
            isOver: assigned > sankhya && sankhya > 0,
            isFull: sankhya > 0 && assigned >= sankhya,
            onTap: () => onOpenDetail(entry));
        },
      )),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DUTY ASSIGN CARD
// ══════════════════════════════════════════════════════════════════════════════
class _DutyAssignCard extends StatelessWidget {
  final _DutyEntry entry;
  final int assigned, batches, sankhya;
  final double pct;
  final bool isOver, isFull;
  final VoidCallback onTap;

  const _DutyAssignCard({
    required this.entry, required this.assigned, required this.batches,
    required this.sankhya, required this.pct,
    required this.isOver, required this.isFull, required this.onTap,
  });

  Color get _barColor {
    if (isOver)  return kError;
    if (isFull)  return kSuccess;
    if (pct > 0.5) return kOrange;
    return kAssignColor;
  }

  @override
  Widget build(BuildContext context) {
    final r = rOf(context);
    final color = entry.isDefault ? kDistrictColor : kCustomColor;
    return Material(color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: assigned > 0 ? color.withOpacity(0.04) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: assigned > 0
                    ? color.withOpacity(0.35) : kBorder.withOpacity(0.4),
                width: assigned > 0 ? 1.5 : 1)),
          padding: EdgeInsets.fromLTRB(r.s(10, 14), 12, r.s(10, 14), 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 40, height: 40,
                decoration: BoxDecoration(
                    color: assigned > 0 ? color : kSubtle.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(entry.icon,
                    color: assigned > 0 ? Colors.white : kSubtle, size: 20)),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(entry.label, style: TextStyle(
                    color: kDark, fontSize: r.s(12.5, 13.5),
                    fontWeight: FontWeight.w700),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6, runSpacing: 2,
                  children: [
                  if (sankhya > 0)
                    Text('$assigned/$sankhya', style: TextStyle(
                        color: _barColor, fontSize: r.s(10.5, 11),
                        fontWeight: FontWeight.w800))
                  else
                    Text('$assigned assigned', style: TextStyle(
                        color: color, fontSize: r.s(10.5, 11),
                        fontWeight: FontWeight.w700)),
                  if (batches > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                          color: kAssignColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(5)),
                      child: Text('$batches batch${batches > 1 ? 'es' : ''}',
                          style: const TextStyle(color: kAssignColor,
                              fontSize: 9, fontWeight: FontWeight.w700))),
                ]),
              ])),
              if (isFull && !r.isCompact) Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: kSuccess.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle, color: kSuccess, size: 12),
                  SizedBox(width: 4),
                  Text('Full', style: TextStyle(
                      color: kSuccess, fontSize: 10, fontWeight: FontWeight.w700))])),
              if (isOver && !r.isCompact) Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: kError.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.warning_amber, color: kError, size: 12),
                  SizedBox(width: 4),
                  Text('Over', style: TextStyle(
                      color: kError, fontSize: 10, fontWeight: FontWeight.w700))])),
              const SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: r.s(8, 10), vertical: 7),
                decoration: BoxDecoration(
                    color: kAssignColor, borderRadius: BorderRadius.circular(9)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.people_outlined, size: 13, color: Colors.white),
                  const SizedBox(width: 4),
                  Text('देखें', style: TextStyle(color: Colors.white,
                      fontSize: r.s(10.5, 11), fontWeight: FontWeight.w700))])),
            ]),
            if (sankhya > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  backgroundColor: _barColor.withOpacity(0.12),
                  valueColor: AlwaysStoppedAnimation(_barColor),
                  minHeight: 5)),
            ],
          ]),
        )));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DUTY DETAIL PAGE
// ══════════════════════════════════════════════════════════════════════════════
class _DutyDetailPage extends StatefulWidget {
  final _DutyEntry entry;
  final Map<String, dynamic>? rule;
  final VoidCallback onRefresh;
  const _DutyDetailPage({super.key, required this.entry,
      required this.rule, required this.onRefresh});

  @override
  State<_DutyDetailPage> createState() => _DutyDetailPageState();
}

class _DutyDetailPageState extends State<_DutyDetailPage> {
  List<Map<String, dynamic>> _batches = [];
  bool _loading = true, _disposed = false;

  @override void initState() { super.initState(); _loadBatches(); }
  @override void dispose() { _disposed = true; super.dispose(); }
  void _safeSetState(VoidCallback fn) {
    if (!_disposed && mounted) setState(fn);
  }

  Future<void> _loadBatches() async {
    _safeSetState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      if (_disposed) return;
      final res = await ApiService.get(
          '/admin/district-duty/${widget.entry.type}/batches', token: token);
      if (_disposed) return;
      final data = res['data'];
      _safeSetState(() {
        _batches = (data is List)
            ? data.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : [];
        _loading = false;
      });
    } catch (e) {
      _safeSetState(() => _loading = false);
      if (!_disposed && mounted) showSnack(context, 'लोड विफल: $e', error: true);
    }
  }

  Future<void> _openAssignSheet() async {
    if (_disposed || !mounted) return;
    final result = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AssignStaffSheet(
          entry: widget.entry, rule: widget.rule));
    if (result == true) { await _loadBatches(); widget.onRefresh(); }
  }

  Future<void> _deleteBatch(int batchNo) async {
    if (!await _confirmDlg(context, 'Batch $batchNo के सभी staff हटाएं?')
        || _disposed) return;
    try {
      final token = await AuthService.getToken();
      await ApiService.delete(
          '/admin/district-duty/${widget.entry.type}/batch/$batchNo',
          token: token);
      if (!_disposed && mounted) {
        showSnack(context, 'Batch $batchNo हटाया गया');
        _loadBatches(); widget.onRefresh();
      }
    } catch (e) {
      if (!_disposed && mounted) showSnack(context, 'Error: $e', error: true);
    }
  }

  Future<void> _clearAll() async {
    if (!await _confirmDlg(context,
        '"${widget.entry.label}" के सभी assignments हटाएं?') || _disposed) return;
    try {
      final token = await AuthService.getToken();
      await ApiService.delete(
          '/admin/district-duty/${widget.entry.type}/clear', token: token);
      if (!_disposed && mounted) {
        showSnack(context, 'सभी assignments हटाए गए');
        _loadBatches(); widget.onRefresh();
      }
    } catch (e) {
      if (!_disposed && mounted) showSnack(context, 'Error: $e', error: true);
    }
  }

  bool _hasAnyRule(Map<String, dynamic> r) {
    for (final key in ['siArmedCount','siUnarmedCount','hcArmedCount',
        'hcUnarmedCount','constArmedCount','constUnarmedCount',
        'auxArmedCount','auxUnarmedCount','pacCount'])
      if (((r[key] ?? 0) as num) > 0) return true;
    return false;
  }

  void _openBatchDetail(Map<String, dynamic> batch) => Navigator.push(
    context, MaterialPageRoute(builder: (_) => _BatchDetailPage(
      dutyType:  widget.entry.type, dutyLabel: widget.entry.label,
      batch: batch,
      color: widget.entry.isDefault ? kDistrictColor : kCustomColor,
      onRefresh: () { _loadBatches(); widget.onRefresh(); })));

  @override
  Widget build(BuildContext context) {
    final r       = rOf(context);
    final color   = widget.entry.isDefault ? kDistrictColor : kCustomColor;
    final sankhya = widget.entry.sankhya;
    final totalAsgn = _batches.fold<int>(
        0, (s, b) => s + ((b['staffCount'] ?? 0) as num).toInt());

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: color, foregroundColor: Colors.white, elevation: 0,
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.entry.label, style: TextStyle(
              fontSize: r.s(13, 14.5), fontWeight: FontWeight.w800),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('${_batches.length} Batches • $totalAsgn Assigned',
              style: TextStyle(fontSize: r.s(10, 11), color: Colors.white70),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
        actions: [
          if (_batches.isNotEmpty)
            IconButton(icon: const Icon(Icons.delete_sweep_outlined, size: 22),
                onPressed: _clearAll),
          IconButton(icon: const Icon(Icons.refresh, size: 20),
              onPressed: _loadBatches),
        ]),
      body: Column(children: [
        Container(
          color: color.withOpacity(0.07),
          padding: EdgeInsets.symmetric(horizontal: r.s(10, 14), vertical: 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _StatChip(label: 'आवश्यक', value: '$sankhya', color: color),
              const SizedBox(width: 8),
              _StatChip(label: 'Assigned', value: '$totalAsgn',
                  color: totalAsgn >= sankhya && sankhya > 0 ? kSuccess : kAssignColor),
              const SizedBox(width: 8),
              _StatChip(label: 'Batches', value: '${_batches.length}', color: kOrange),
              const SizedBox(width: 12),
              if (sankhya > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(totalAsgn >= sankhya ? '✓ पूर्ण' : '${sankhya - totalAsgn} बाकी',
                      style: TextStyle(
                          color: totalAsgn >= sankhya ? kSuccess : kError,
                          fontSize: 12, fontWeight: FontWeight.w800)),
                ),
            ]),
          ),
        ),
        if (widget.rule != null && _hasAnyRule(widget.rule!))
          Container(
            color: color.withOpacity(0.04),
            padding: EdgeInsets.fromLTRB(r.s(10, 14), 8, r.s(10, 14), 8),
            child: _ChipRow(rule: widget.rule!, cardColor: color)),
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(color: kDistrictColor))
            : _batches.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(widget.entry.icon, size: 56,
                        color: kSubtle.withOpacity(0.3)),
                    const SizedBox(height: 16),
                    const Text('कोई staff assign नहीं है',
                        style: TextStyle(color: kSubtle, fontSize: 13)),
                    const SizedBox(height: 8),
                    const Text('नीचे "Assign Staff" बटन दबाएं',
                        style: TextStyle(color: kSubtle, fontSize: 11)),
                  ]))
                : RefreshIndicator(
                    onRefresh: _loadBatches, color: color,
                    child: ListView.separated(
                      padding: EdgeInsets.fromLTRB(r.s(8, 12), 12, r.s(8, 12), 100),
                      itemCount: _batches.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final batch = _batches[i];
                        return _BatchCard(
                          batch: batch, color: color,
                          onDelete: () => _deleteBatch(batch['batchNo'] as int),
                          onViewAll: () => _openBatchDetail(batch));
                      }))),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAssignSheet,
        backgroundColor: color, foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_outlined, size: 20),
        label: const Text('Assign Staff',
            style: TextStyle(fontWeight: FontWeight.w800))),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  BATCH CARD
// ══════════════════════════════════════════════════════════════════════════════
class _BatchCard extends StatelessWidget {
  final Map<String, dynamic> batch;
  final Color color;
  final VoidCallback onDelete, onViewAll;

  const _BatchCard({required this.batch, required this.color,
      required this.onDelete, required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    final r          = rOf(context);
    final batchNo    = batch['batchNo']    as int?  ?? 0;
    final staffCount = (batch['staffCount'] ?? 0)   as num;
    final staffList  = (batch['staff']     as List?)?.cast<Map>() ?? [];
    final busNo      = batch['busNo']      as String? ?? '';
    final note       = batch['note']       as String? ?? '';
    final maxChips   = r.isCompact ? 4 : 6;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.06),
            blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: EdgeInsets.fromLTRB(r.s(10, 14), 11, r.s(10, 12), 11),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(11), topRight: Radius.circular(11))),
          child: Row(children: [
            Container(width: 34, height: 34,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Center(child: Text('$batchNo', style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)))),
            const SizedBox(width: 10),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Batch $batchNo', style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: r.s(12, 13))),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8, runSpacing: 2,
                children: [
                Text('${staffCount.toInt()} staff',
                    style: const TextStyle(color: kSubtle, fontSize: 11)),
                if (busNo.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.directions_bus_outlined, size: 10, color: kSubtle),
                    const SizedBox(width: 3),
                    Text(busNo, style: const TextStyle(color: kSubtle, fontSize: 10))]),
                if (note.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(note,
                      style: const TextStyle(color: kSubtle, fontSize: 10),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ])),
            GestureDetector(onTap: onViewAll,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: r.s(8, 10), vertical: 6),
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(8)),
                child: Text('विवरण', style: TextStyle(
                    color: Colors.white, fontSize: r.s(10.5, 11),
                    fontWeight: FontWeight.w700)))),
            const SizedBox(width: 6),
            GestureDetector(onTap: onDelete,
              child: Container(width: 32, height: 32,
                decoration: BoxDecoration(
                    color: kError.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kError.withOpacity(0.3))),
                child: const Icon(Icons.delete_outline, color: kError, size: 16))),
          ])),
        if (staffList.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Wrap(spacing: 6, runSpacing: 6,
              children: staffList.take(maxChips).map((s) {
                final rc = _rankColor(s['rank'] as String? ?? '');
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                      color: rc.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: rc.withOpacity(0.25))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 22, height: 22,
                      decoration: BoxDecoration(
                          color: rc.withOpacity(0.15), shape: BoxShape.circle),
                      child: Center(child: Text(
                        (s['name'] as String? ?? '').split(' ')
                            .where((w) => w.isNotEmpty).take(1)
                            .map((w) => w[0]).join().toUpperCase(),
                        style: TextStyle(color: rc, fontSize: 10,
                            fontWeight: FontWeight.w900)))),
                    const SizedBox(width: 5),
                    ConstrainedBox(constraints: BoxConstraints(maxWidth: r.s(70, 90)),
                      child: Text(s['name'] as String? ?? '',
                          style: const TextStyle(color: kDark, fontSize: 11,
                              fontWeight: FontWeight.w600),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                          color: rc.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(s['rank'] as String? ?? '',
                          style: TextStyle(color: rc, fontSize: 8,
                              fontWeight: FontWeight.w700))),
                  ]));
              }).followedBy(staffList.length > maxChips
                  ? [Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                          color: kSubtle.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text('+${staffList.length - maxChips} और',
                          style: const TextStyle(color: kSubtle, fontSize: 11)))]
                  : []).toList())),
      ]));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  BATCH DETAIL PAGE
// ══════════════════════════════════════════════════════════════════════════════
class _BatchDetailPage extends StatefulWidget {
  final String dutyType, dutyLabel;
  final Map<String, dynamic> batch;
  final Color color;
  final VoidCallback onRefresh;
  const _BatchDetailPage({super.key, required this.dutyType,
      required this.dutyLabel, required this.batch, required this.color,
      required this.onRefresh});

  @override State<_BatchDetailPage> createState() => _BatchDetailPageState();
}

class _BatchDetailPageState extends State<_BatchDetailPage> {
  late List<Map<String, dynamic>> _staff;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _staff = ((widget.batch['staff'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  @override void dispose() { _disposed = true; super.dispose(); }

  Future<void> _removeStaff(Map<String, dynamic> s) async {
    if (!await _confirmDlg(context, '${s['name']} को हटाएं?')) return;
    try {
      final token = await AuthService.getToken();
      await ApiService.delete(
          '/admin/district-duty/assignment/${s['assignmentId']}', token: token);
      if (!_disposed && mounted) {
        setState(() => _staff.removeWhere(
            (x) => x['assignmentId'] == s['assignmentId']));
        widget.onRefresh();
        showSnack(context, '${s['name']} हटाया गया');
      }
    } catch (e) {
      if (!_disposed && mounted) showSnack(context, 'Error: $e', error: true);
    }
  }

  List<Widget> _buildRankSummary() {
    final Map<String, int> counts = {};
    for (final s in _staff) {
      final r = s['rank'] as String? ?? '';
      if (r.isNotEmpty) counts[r] = (counts[r] ?? 0) + 1;
    }
    return counts.entries.map((e) {
      final rc = _rankColor(e.key);
      return Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: rc.withOpacity(0.1), borderRadius: BorderRadius.circular(6),
            border: Border.all(color: rc.withOpacity(0.3))),
        child: Text('${e.key}: ${e.value}', style: TextStyle(
            color: rc, fontSize: 10, fontWeight: FontWeight.w700)));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final r       = rOf(context);
    final batchNo = widget.batch['batchNo'] as int? ?? 0;
    final busNo   = widget.batch['busNo']   as String? ?? '';
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: widget.color, foregroundColor: Colors.white, elevation: 0,
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.dutyLabel, style: TextStyle(
              fontSize: r.s(13, 14.5), fontWeight: FontWeight.w800),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('Batch $batchNo • ${_staff.length} Staff'
              '${busNo.isNotEmpty ? ' • Bus: $busNo' : ''}',
              style: TextStyle(fontSize: r.s(10, 11), color: Colors.white70),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
      body: Column(children: [
        Container(
          color: widget.color.withOpacity(0.07),
          padding: EdgeInsets.symmetric(horizontal: r.s(10, 14), vertical: 10),
          child: Row(children: [
            Container(width: 36, height: 36,
                decoration: BoxDecoration(
                    color: widget.color, shape: BoxShape.circle),
                child: Center(child: Text('$batchNo', style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w900,
                    fontSize: 15)))),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Batch $batchNo — ${widget.dutyLabel}',
                  style: TextStyle(color: widget.color,
                      fontWeight: FontWeight.w800, fontSize: r.s(12, 13)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${_staff.length} सदस्य',
                  style: const TextStyle(color: kSubtle, fontSize: 11)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: Text('${_staff.length}', style: TextStyle(
                  color: widget.color, fontWeight: FontWeight.w900, fontSize: 16))),
          ])),
        if (_staff.isNotEmpty)
          Container(
            color: kSurface.withOpacity(0.5),
            padding: EdgeInsets.fromLTRB(r.s(10, 14), 6, r.s(10, 14), 6),
            child: SingleChildScrollView(scrollDirection: Axis.horizontal,
                child: Row(children: _buildRankSummary()))),
        Expanded(child: _staff.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.people_outline, size: 56,
                    color: kSubtle.withOpacity(0.3)),
                const SizedBox(height: 12),
                const Text('कोई staff नहीं',
                    style: TextStyle(color: kSubtle, fontSize: 13))]))
            : ListView.builder(
                padding: EdgeInsets.fromLTRB(r.s(8, 12), 10, r.s(8, 12), 20),
                itemCount: _staff.length,
                itemBuilder: (_, i) => _StaffDetailCard(
                  staff: _staff[i], index: i, color: widget.color,
                  onRemove: () => _removeStaff(_staff[i])))),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  STAFF DETAIL CARD
// ══════════════════════════════════════════════════════════════════════════════
class _StaffDetailCard extends StatelessWidget {
  final Map<String, dynamic> staff;
  final int index;
  final Color color;
  final VoidCallback onRemove;
  const _StaffDetailCard({required this.staff, required this.index,
      required this.color, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final rank    = staff['rank'] as String? ?? '';
    final rc      = _rankColor(rank);
    final isArmed = (staff['isArmed'] as bool?) == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(11),
        border: Border.all(color: rc.withOpacity(0.25)),
        boxShadow: [BoxShadow(color: rc.withOpacity(0.04),
            blurRadius: 4, offset: const Offset(0, 1))]),
      child: Row(children: [
        Container(width: 32, height: 32,
            decoration: BoxDecoration(
                color: color.withOpacity(0.1), shape: BoxShape.circle,
                border: Border.all(color: color.withOpacity(0.3))),
            child: Center(child: Text('${index + 1}', style: TextStyle(
                color: color, fontWeight: FontWeight.w900, fontSize: 12)))),
        const SizedBox(width: 10),
        Container(width: 38, height: 38,
            decoration: BoxDecoration(
                color: rc.withOpacity(0.12), shape: BoxShape.circle,
                border: Border.all(color: rc.withOpacity(0.3))),
            child: Center(child: Text(
              (staff['name'] as String? ?? '').split(' ')
                  .where((w) => w.isNotEmpty).take(2)
                  .map((w) => w[0]).join().toUpperCase(),
              style: TextStyle(color: rc, fontWeight: FontWeight.w900, fontSize: 13)))),
        const SizedBox(width: 10),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(staff['name'] as String? ?? '',
                style: const TextStyle(color: kDark, fontWeight: FontWeight.w700,
                    fontSize: 13),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (isArmed) Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                  color: const Color(0xFF6A1B9A).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(5)),
              child: const Text('Armed', style: TextStyle(
                  color: Color(0xFF6A1B9A), fontSize: 9,
                  fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 3),
          Wrap(spacing: 8, runSpacing: 4, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: rc.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: rc.withOpacity(0.3))),
              child: Text(rank, style: TextStyle(
                  color: rc, fontSize: 9, fontWeight: FontWeight.w700))),
            if ((staff['pno'] as String?)?.isNotEmpty == true)
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.badge_outlined, size: 10, color: kSubtle),
                const SizedBox(width: 3),
                Text(staff['pno'] as String,
                    style: const TextStyle(color: kSubtle, fontSize: 10))]),
            if ((staff['thana'] as String?)?.isNotEmpty == true)
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.local_police_outlined, size: 10, color: kSubtle),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(staff['thana'] as String,
                      style: const TextStyle(color: kSubtle, fontSize: 10),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
          ]),
          if ((staff['mobile'] as String?)?.isNotEmpty == true)
            Padding(padding: const EdgeInsets.only(top: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.phone_outlined, size: 10, color: kSubtle),
                const SizedBox(width: 3),
                Text(staff['mobile'] as String,
                    style: const TextStyle(color: kSubtle, fontSize: 10))])),
        ])),
        const SizedBox(width: 8),
        GestureDetector(onTap: onRemove,
          child: Container(width: 32, height: 32,
            decoration: BoxDecoration(
                color: kError.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kError.withOpacity(0.25))),
            child: const Icon(Icons.person_remove_outlined,
                size: 16, color: kError))),
      ]));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  ASSIGN STAFF SHEET
// ══════════════════════════════════════════════════════════════════════════════
class _AssignStaffSheet extends StatefulWidget {
  final _DutyEntry entry;
  final Map<String, dynamic>? rule;
  const _AssignStaffSheet({required this.entry, required this.rule});
  @override State<_AssignStaffSheet> createState() => _AssignStaffSheetState();
}

class _AssignStaffSheetState extends State<_AssignStaffSheet> {
  final List<Map> _staff = [];
  final Set<int>  _selected = {};
  final _busCtrl    = TextEditingController();
  final _noteCtrl   = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _scroll     = ScrollController();
  bool   _loading = true, _loadingMore = false, _hasMore = true,
         _saving = false, _disposed = false;
  int    _page = 1;
  String _q = '', _rankFilter = '';
  Timer? _debounce;
  static const _kRanks = ['SI', 'ASI', 'Head Constable', 'Constable'];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _searchCtrl.addListener(_onSearchChanged);
    _load(reset: true);
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _scroll.removeListener(_onScroll);
    _searchCtrl.removeListener(_onSearchChanged);
    _scroll.dispose(); _searchCtrl.dispose();
    _busCtrl.dispose(); _noteCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_disposed) return;
    if (_scroll.hasClients &&
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 150) {
      _load();
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (_disposed) return;
      final q = _searchCtrl.text.trim();
      if (q != _q) { _q = q; _reload(); }
    });
  }

  void _safeSetState(VoidCallback fn) {
    if (!_disposed && mounted) setState(fn);
  }

  void _reload() {
    _safeSetState(() {
      _staff.clear(); _page = 1; _hasMore = true; _selected.clear();
    });
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_disposed || (!_hasMore && !reset) || _loadingMore) return;
    _safeSetState(() {
      if (reset) _loading = true; else _loadingMore = true;
    });
    try {
      final token = await AuthService.getToken();
      if (_disposed) return;
      var url = '/admin/district-duty/${widget.entry.type}/available-staff'
          '?page=$_page&limit=20&q=${Uri.encodeComponent(_q)}';
      if (_rankFilter.isNotEmpty) url += '&rank=${Uri.encodeComponent(_rankFilter)}';
      final res = await ApiService.get(url, token: token);
      if (_disposed) return;
      final w     = (res['data'] as Map<String, dynamic>?) ?? {};
      final items = (w['data'] as List?)?.map((e) =>
          Map<String, dynamic>.from(e as Map)).toList() ?? [];
      final pages = (w['totalPages'] as num?)?.toInt() ?? 1;
      _safeSetState(() {
        _staff.addAll(items);
        _hasMore = _page < pages; _page++;
        _loading = false; _loadingMore = false;
      });
    } catch (_) {
      _safeSetState(() { _loading = false; _loadingMore = false; });
    }
  }

  Future<void> _assign() async {
    if (_selected.isEmpty) {
      showSnack(context, 'कम से कम 1 staff चुनें', error: true);
      return;
    }
    _safeSetState(() => _saving = true);
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.post(
          '/admin/district-duty/${widget.entry.type}/assign',
          {
            'staffIds': _selected.toList(),
            'busNo': _busCtrl.text.trim(),
            'note': _noteCtrl.text.trim(),
          }, token: token);
      if (!_disposed && mounted) {
        final data = res['data'] as Map?;
        showSnack(context,
            'Batch ${data?['batchNo'] ?? 0} बना: '
            '${data?['assigned'] ?? 0} Assigned'
            '${(data?['skipped'] ?? 0) > 0 ? ', ${data?['skipped']} skip' : ''}');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!_disposed && mounted) showSnack(context, 'Error: $e', error: true);
      _safeSetState(() => _saving = false);
    }
  }

  Widget _filterChip(String label, String value, Color color) {
    final sel = _rankFilter == value;
    final c   = value.isEmpty ? kDistrictColor : _rankColor(value);
    return GestureDetector(
      onTap: () { _safeSetState(() => _rankFilter = value); _reload(); },
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: sel ? c : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: sel ? c : kBorder.withOpacity(0.5))),
        child: Text(label, style: TextStyle(
            color: sel ? Colors.white : kDark, fontSize: 11,
            fontWeight: sel ? FontWeight.w700 : FontWeight.w500))));
  }

  Widget _miniField(TextEditingController ctrl, String hint,
      IconData icon, Color color) => TextField(
    controller: ctrl,
    style: const TextStyle(color: kDark, fontSize: 12),
    decoration: InputDecoration(
      hintText: hint, hintStyle: const TextStyle(color: kSubtle, fontSize: 11),
      prefixIcon: Icon(icon, size: 15, color: color),
      filled: true, fillColor: Colors.white, isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: kBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: kBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
          borderSide: BorderSide(color: color, width: 1.5))));

  @override
  Widget build(BuildContext context) {
    final r = rOf(context);
    final color = widget.entry.isDefault ? kDistrictColor : kCustomColor;
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
          color: kBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(children: [
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 4),
          width: 40, height: 4,
          decoration: BoxDecoration(
              color: kBorder.withOpacity(0.5),
              borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: EdgeInsets.fromLTRB(r.s(12, 16), 6, r.s(12, 16), 12),
          child: Column(children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(widget.entry.icon, color: color, size: 18)),
              const SizedBox(width: 10),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Staff Assign करें', style: TextStyle(
                    color: kDark, fontWeight: FontWeight.w800,
                    fontSize: r.s(14, 15))),
                Text(widget.entry.label, style: const TextStyle(
                    color: kSubtle, fontSize: 12),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              if (_selected.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(20)),
                  child: Text('${_selected.length} चुने', style: const TextStyle(
                      color: Colors.white, fontSize: 12,
                      fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _filterChip('सभी', '', color),
                ..._kRanks.map((r) => _filterChip(r, r, color)),
              ])),
            const SizedBox(height: 8),
            TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: kDark, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'नाम, PNO खोजें...',
                hintStyle: const TextStyle(color: kSubtle, fontSize: 12),
                prefixIcon: const Icon(Icons.search, color: kSubtle, size: 18),
                filled: true, fillColor: Colors.white, isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: kBorder)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: kBorder)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: color, width: 2)))),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _miniField(
                  _busCtrl, 'Bus No (optional)',
                  Icons.directions_bus_outlined, color)),
              const SizedBox(width: 8),
              Expanded(child: _miniField(
                  _noteCtrl, 'Note (optional)',
                  Icons.note_outlined, color)),
            ]),
          ])),
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(color: kDistrictColor))
            : _staff.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.people_outline, size: 48,
                        color: kSubtle.withOpacity(0.4)),
                    const SizedBox(height: 12),
                    const Text('कोई unassigned staff नहीं मिला',
                        style: TextStyle(color: kSubtle, fontSize: 13))]))
                : Scrollbar(
                    controller: _scroll, thumbVisibility: true, thickness: 5,
                    child: ListView.builder(
                      controller: _scroll,
                      padding: EdgeInsets.fromLTRB(r.s(10, 14), 0, r.s(10, 14), 16),
                      itemCount: _staff.length + (_loadingMore ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i >= _staff.length) {
                          return const Padding(padding: EdgeInsets.all(12),
                            child: Center(child: SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: kDistrictColor))));
                        }
                        final s   = _staff[i];
                        final sid = s['id'] as int;
                        final isSel = _selected.contains(sid);
                        final rank  = s['rank'] as String? ?? '';
                        final rc    = _rankColor(rank);
                        return GestureDetector(
                          onTap: () => _safeSetState(() {
                            if (isSel) _selected.remove(sid);
                            else _selected.add(sid);
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                                color: isSel
                                    ? color.withOpacity(0.07) : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: isSel ? color : kBorder.withOpacity(0.4),
                                    width: isSel ? 1.8 : 1)),
                            child: Row(children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                width: 22, height: 22,
                                decoration: BoxDecoration(
                                    color: isSel ? color : Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: isSel ? color : kBorder,
                                        width: isSel ? 0 : 1.5)),
                                child: isSel
                                    ? const Icon(Icons.check, size: 14,
                                        color: Colors.white) : null),
                              const SizedBox(width: 10),
                              Container(width: 36, height: 36,
                                decoration: BoxDecoration(
                                    color: rc.withOpacity(0.12),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: rc.withOpacity(0.3))),
                                child: Center(child: Text(
                                  (s['name'] as String? ?? '').split(' ')
                                      .where((w) => w.isNotEmpty).take(2)
                                      .map((w) => w[0]).join().toUpperCase(),
                                  style: TextStyle(color: rc,
                                      fontWeight: FontWeight.w900, fontSize: 12)))),
                              const SizedBox(width: 10),
                              Expanded(child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(s['name'] as String? ?? '',
                                    style: TextStyle(
                                        color: isSel ? color : kDark,
                                        fontWeight: FontWeight.w700, fontSize: 13),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                Wrap(crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 6, runSpacing: 2,
                                  children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                        color: rc.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                            color: rc.withOpacity(0.3))),
                                    child: Text(rank, style: TextStyle(
                                        color: rc, fontSize: 9,
                                        fontWeight: FontWeight.w700))),
                                  if ((s['pno'] as String?)?.isNotEmpty == true)
                                    Text(s['pno'] as String,
                                        style: const TextStyle(
                                            color: kSubtle, fontSize: 10)),
                                  if ((s['thana'] as String?)?.isNotEmpty == true)
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 140),
                                      child: Text(s['thana'] as String,
                                        style: const TextStyle(
                                            color: kSubtle, fontSize: 10),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis)),
                                ]),
                              ])),
                            ])));
      }))),
        Padding(
          padding: EdgeInsets.fromLTRB(r.s(10, 14), 8, r.s(10, 14), 14),
          child: SizedBox(width: double.infinity, height: 50,
            child: ElevatedButton.icon(
              onPressed: (_saving || _selected.isEmpty) ? null : _assign,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle_outline, size: 20),
              label: FittedBox(child: Text(
                _saving ? 'Assigning...'
                    : _selected.isEmpty ? 'Staff चुनें'
                        : '${_selected.length} Staff Assign करें (New Batch)',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
              style: ElevatedButton.styleFrom(
                backgroundColor: _selected.isEmpty ? kSubtle : color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0)))),
      ]));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DUTY RULE CARD
// ══════════════════════════════════════════════════════════════════════════════
class _DutyRuleCard extends StatelessWidget {
  final _DutyEntry entry;
  final bool isSet;
  final int sankhya, totalStaff;
  final Map<String, dynamic>? rule;
  final VoidCallback onTap;
  final VoidCallback? onEdit, onDelete;

  const _DutyRuleCard({
    required this.entry, required this.isSet,
    required this.sankhya, required this.totalStaff,
    required this.rule, required this.onTap,
    this.onEdit, this.onDelete,
  });

  Color get _color => entry.isDefault ? kDistrictColor : kCustomColor;

  @override
  Widget build(BuildContext context) {
    final r = rOf(context);
    return Material(color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: isSet ? _color.withOpacity(0.06) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isSet ? _color.withOpacity(0.4) : kBorder.withOpacity(0.4),
                width: isSet ? 1.5 : 1)),
          padding: EdgeInsets.symmetric(horizontal: r.s(10, 14), vertical: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 42, height: 42,
                  decoration: BoxDecoration(
                      color: isSet ? _color : kSubtle.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10)),
                  alignment: Alignment.center,
                  child: Icon(entry.icon,
                      color: isSet ? Colors.white : kSubtle, size: 20)),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(entry.label, style: TextStyle(
                      color: kDark, fontSize: r.s(12.5, 13.5), fontWeight: FontWeight.w700),
                      maxLines: 2, overflow: TextOverflow.ellipsis)),
                  if (!entry.isDefault) Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: kCustomColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6)),
                    child: const Text('कस्टम', style: TextStyle(
                        color: kCustomColor, fontSize: 9, fontWeight: FontWeight.w800))),
                ]),
                const SizedBox(height: 3),
                if (isSet)
                  Wrap(spacing: 8, runSpacing: 2, children: [
                    Text('संख्या: $sankhya', style: TextStyle(
                        color: _color, fontSize: 11, fontWeight: FontWeight.w800)),
                    Text('• कुल: $totalStaff', style: const TextStyle(
                        color: kSubtle, fontSize: 11, fontWeight: FontWeight.w600)),
                  ])
                else
                  const Text('मानक सेट नहीं है',
                      style: TextStyle(color: kSubtle, fontSize: 11)),
              ])),
              Icon(isSet ? Icons.check_circle_rounded : Icons.add_circle_outline,
                  color: isSet ? kSuccess : kSubtle, size: 18),
              if (!entry.isDefault) ...[
                const SizedBox(width: 4),
                _iconBtn(Icons.edit_outlined,   kCustomColor, onEdit),
                const SizedBox(width: 4),
                _iconBtn(Icons.delete_outline,  kError,       onDelete),
              ] else ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: kSubtle, size: 20),
              ],
            ]),
            if (isSet && rule != null) ...[
              const SizedBox(height: 10),
              _ChipRow(rule: rule!, cardColor: _color),
            ],
          ])),
      ));
  }

  Widget _iconBtn(IconData icon, Color color, VoidCallback? onTap) =>
      GestureDetector(onTap: onTap,
        child: Container(width: 30, height: 30,
          decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: color.withOpacity(0.25))),
          child: Icon(icon, size: 15, color: color)));
}

// ── Chip Row ──────────────────────────────────────────────────────────────────
class _ChipRow extends StatelessWidget {
  final Map<String, dynamic> rule;
  final Color cardColor;
  const _ChipRow({required this.rule, required this.cardColor});

  @override
  Widget build(BuildContext context) {
    final siA  = (rule['siArmedCount']    ?? 0) as num;
    final siU  = (rule['siUnarmedCount']  ?? 0) as num;
    final hcA  = (rule['hcArmedCount']    ?? 0) as num;
    final hcU  = (rule['hcUnarmedCount']  ?? 0) as num;
    final cA   = (rule['constArmedCount'] ?? 0) as num;
    final cU   = (rule['constUnarmedCount'] ?? 0) as num;
    final auxA = (rule['auxArmedCount']   ?? 0) as num;
    final auxU = (rule['auxUnarmedCount'] ?? 0) as num;
    final pac  = (rule['pacCount']        ?? 0) as num;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        if (siA+siU  > 0) _chip('SI',    siA, siU,  cardColor),
        if (hcA+hcU  > 0) _chip('HC',    hcA, hcU,  cardColor),
        if (cA+cU    > 0) _chip('Const', cA,  cU,   cardColor),
        if (auxA+auxU> 0) _chip('Aux',   auxA, auxU, const Color(0xFFE65100)),
        if (pac      > 0) _single('PAC',
            pac == pac.toInt() ? '${pac.toInt()}' : '$pac',
            const Color(0xFF00695C)),
      ]));
  }

  Widget _chip(String label, num armed, num unarmed, Color color) =>
      Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withOpacity(0.3))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$label: ', style: TextStyle(
              color: color.withOpacity(0.85), fontSize: 10.5,
              fontWeight: FontWeight.w700)),
          if (armed > 0) ...[
            const Icon(Icons.gavel, size: 9, color: Color(0xFF6A1B9A)),
            Text('$armed', style: const TextStyle(
                color: Color(0xFF6A1B9A), fontSize: 11, fontWeight: FontWeight.w900))],
          if (armed > 0 && unarmed > 0)
            Text(' / ', style: TextStyle(color: color.withOpacity(0.5), fontSize: 11)),
          if (unarmed > 0) ...[
            const Icon(Icons.shield_outlined, size: 9, color: Color(0xFF1A5276)),
            Text('$unarmed', style: const TextStyle(
                color: Color(0xFF1A5276), fontSize: 11, fontWeight: FontWeight.w900))],
        ]));

  Widget _single(String label, String value, Color c) => Container(
    margin: const EdgeInsets.only(right: 6),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
        color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withOpacity(0.3))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label: ', style: TextStyle(color: c.withOpacity(0.85),
          fontSize: 10.5, fontWeight: FontWeight.w700)),
      Text(value, style: TextStyle(
          color: c, fontSize: 11, fontWeight: FontWeight.w900)),
    ]));
}

// ── Stat Chip ─────────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3))),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(value, style: TextStyle(
          color: color, fontSize: 14, fontWeight: FontWeight.w900)),
      Text(label, style: TextStyle(
          color: color.withOpacity(0.7), fontSize: 9, fontWeight: FontWeight.w600)),
    ]));
}

// ── Helpers ───────────────────────────────────────────────────────────────────
Color _rankColor(String rank) {
  const m = {
    'SP':            Color(0xFF6A1B9A),
    'ASP':           Color(0xFF1565C0),
    'DSP':           Color(0xFF1A5276),
    'Inspector':     Color(0xFF2E7D32),
    'SI':            Color(0xFF558B2F),
    'ASI':           Color(0xFF8B6914),
    'Head Constable':Color(0xFFB8860B),
    'Constable':     Color(0xFF6D4C41),
  };
  return m[rank] ?? kPrimary;
}

Future<bool> _confirmDlg(BuildContext ctx, String msg) async =>
    await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        backgroundColor: kBg,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: kError, width: 1.2)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: kError, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text('Confirm', style: TextStyle(
                color: kError, fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ]),
        content: Text(msg, style: const TextStyle(color: kDark, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false),
              child: const Text('रद्द', style: TextStyle(color: kSubtle))),
          ElevatedButton(onPressed: () => Navigator.pop(d, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: kError, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            child: const Text('हटाएं')),
        ])) ?? false;