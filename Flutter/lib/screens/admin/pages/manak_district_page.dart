import 'dart:async';
import 'package:flutter/material.dart';
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
    this.sankhya      = 0,
    this.totalAssigned = 0,
    this.batchCount   = 0,
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

  final List<_DutyEntry>                  _duties   = [];
  final Map<String, Map<String, dynamic>> _byDuty   = {};
  final Map<String, Map<String, dynamic>> _summary  = {};

  bool _loading  = true;
  bool _saving   = false;
  bool _changed  = false;
  bool _disposed = false;

  // Auto-assign job state
  int?   _autoJobId;
  String _autoJobStatus = ''; // pending / running / done / error
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

  // ── Load rules + summary ────────────────────────────────────────────────
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

      final list = (rulesRes is List)
          ? rulesRes
          : ((rulesRes['data'] is List) ? rulesRes['data'] as List : []);

      final summaryData = (summaryRes['data'] is Map)
          ? Map<String, dynamic>.from(summaryRes['data'] as Map)
          : <String, dynamic>{};

      _duties.clear();
      _byDuty.clear();
      _summary.clear();

      summaryData.forEach((key, val) {
        _summary[key] = Map<String, dynamic>.from(val as Map);
      });

      for (final item in list) {
        final r     = Map<String, dynamic>.from(item as Map);
        final entry = _DutyEntry.fromRule(r, summary: _summary[r['dutyType']]);
        _duties.add(entry);
        _byDuty[entry.type] = r;
      }

      // Restore latest job state if running
      final jobData = latestJob['data'];
      if (jobData is Map) {
        final status = jobData['status'] as String? ?? '';
        if (status == 'running' || status == 'pending') {
          _autoJobId     = (jobData['jobId'] as num?)?.toInt();
          _autoJobStatus = status;
          _autoJobPct    = (jobData['pct'] as num?)?.toInt() ?? 0;
          if (token != null) {
            _startPolling(token);
          }
        }
      }
    } catch (e) {
      if (!_disposed && mounted) showSnack(context, 'लोड विफल: $e', error: true);
    } finally {
      _safeSetState(() => _loading = false);
    }
  }

  // ── Rule helpers ──────────────────────────────────────────────────────────
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

  // ── Auto Assign ───────────────────────────────────────────────────────────
  Future<void> _startAutoAssign() async {
    // Confirm dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: kDistrictColor.withOpacity(0.5))),
        title: Row(children: [
          Container(width: 36, height: 36,
            decoration: BoxDecoration(color: kDistrictColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.auto_fix_high, color: kDistrictColor, size: 20)),
          const SizedBox(width: 10),
          const Expanded(child: Text('Auto Assign District Duty',
              style: TextStyle(color: kDark, fontSize: 14, fontWeight: FontWeight.w800))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('मानक के अनुसार सभी ड्यूटी प्रकारों पर स्टाफ auto-assign होगा।',
              style: TextStyle(color: kDark, fontSize: 13)),
          const SizedBox(height: 10),
          Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: kOrange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kOrange.withOpacity(0.3))),
            child: const Row(children: [
              Icon(Icons.info_outline, size: 13, color: kOrange),
              SizedBox(width: 6),
              Expanded(child: Text('यह background में चलेगा। पहले के सभी assignments हट जाएंगे।',
                  style: TextStyle(color: kOrange, fontSize: 11))),
            ])),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('रद्द', style: TextStyle(color: kSubtle))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kDistrictColor,
                foregroundColor: Colors.white, elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Start करें'),
          ),
        ],
      ),
    );
    if (confirmed != true || _disposed) return;

    try {
      final token = await AuthService.getToken();
      // Clear all first
      await ApiService.delete('/admin/district-duty/auto-assign/clear-all', token: token);
      // Start job
      final res = await ApiService.post(
          '/admin/district-duty/auto-assign/start', {}, token: token);
      final jobId = ((res['data'] ?? res)['jobId'] as num?)?.toInt();
      if (jobId == null || jobId <= 0) {
        if (!_disposed && mounted) showSnack(context, 'Job शुरू नहीं हुआ', error: true);
        return;
      }
      _safeSetState(() {
        _autoJobId     = jobId;
        _autoJobStatus = 'running';
        _autoJobPct    = 0;
        _autoAssigned  = 0;
        _autoSkipped   = 0;
      });
      if (token != null) {
          _startPolling(token);
        }
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
          _autoJobStatus = status;
          _autoJobPct    = pct;
          _autoAssigned  = assigned;
          _autoSkipped   = skipped;
        });
        if (status == 'done' || status == 'error') {
          _pollTimer?.cancel();
          if (status == 'done') {
            await _loadAll(); // refresh all data
            if (!_disposed && mounted) {
              showSnack(context, '$assigned staff assign हुए ✓');
            }
          } else {
            final err = d['errorMsg'] as String? ?? 'Unknown error';
            if (!_disposed && mounted) showSnack(context, 'Error: $err', error: true);
          }
        }
      } catch (_) {}
    });
  }

  // ── Clear all assignments ─────────────────────────────────────────────────
  Future<void> _clearAllAssignments() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: kError, width: 1.2),
        ),
        title: const Row(
          children: [
            Icon(Icons.refresh, color: kError, size: 20),
            SizedBox(width: 8),
            Text(
              'ड्यूटी रीफ्रेश करें?',
              style: TextStyle(
                color: kError,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ],
        ),
        content: const Text(
          'सभी ड्यूटी assignments हट जाएंगे और system reset हो जाएगा.\n\n'
          'आप दोबारा Auto Assign कर सकते हैं।',
          style: TextStyle(color: kDark, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('रद्द', style: TextStyle(color: kSubtle)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: kError,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('रीफ्रेश करें'),
          ),
        ],
      ),
    );

    if (confirmed != true || _disposed) return;

    try {
      final token = await AuthService.getToken();

      // 🔴 MAIN ACTION: CLEAR ALL DUTIES
      await ApiService.delete(
        '/admin/district-duty/auto-assign/clear-all',
        token: token,
      );

      if (!_disposed && mounted) {
        showSnack(context, 'ड्यूटी सफलतापूर्वक रीफ्रेश हो गई ✓');

        // 🔄 Reload UI
        _loadAll();
      }
    } catch (e) {
      if (!_disposed && mounted) {
        showSnack(context, 'Error: $e', error: true);
      }
    }
  }

  // ── Open rank editor ──────────────────────────────────────────────────────
  void _openRankEditor(_DutyEntry entry, int sortOrder) async {
    final existing = Map<String, dynamic>.from(
      _byDuty[entry.type] ?? {
        'dutyType':    entry.type,
        'dutyLabelHi': entry.label,
        'sortOrder':   sortOrder,
        'isDefault':   entry.isDefault,
      },
    );

    final updated = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => ManakRankEditorPage(
          title:       entry.label,
          subtitle:    'जनपदीय कानून व्यवस्था',
          color:       entry.isDefault ? kDistrictColor : kCustomColor,
          initial:     existing,
          showSankhya: true,
        ),
      ),
    );

    if (updated != null) {
      updated['dutyType']    = entry.type;
      updated['dutyLabelHi'] = entry.label;
      updated['sortOrder']   = sortOrder;
      updated['isDefault']   = entry.isDefault;
      _safeSetState(() {
        _byDuty[entry.type] = updated;
        final idx = _duties.indexWhere((d) => d.type == entry.type);
        if (idx >= 0) {
          _duties[idx].sankhya = ((updated['sankhya'] ?? 0) as num).toInt();
        }
        _changed = true;
      });
    }
  }

  // ── Open duty detail page ─────────────────────────────────────────────────
  void _openDutyDetail(_DutyEntry entry) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DutyDetailPage(
          entry:     entry,
          rule:      _byDuty[entry.type],
          onRefresh: _loadAll,
        ),
      ),
    );
    _loadAll(); // refresh after returning
  }

  // ── Save all rules ────────────────────────────────────────────────────────
  Future<void> _saveAll() async {
    _safeSetState(() => _saving = true);
    try {
      final token = await AuthService.getToken();
      final rules = <Map<String, dynamic>>[];

      for (int i = 0; i < _duties.length; i++) {
        final d    = _duties[i];
        final base = _byDuty[d.type] ?? {
          'dutyType': d.type, 'dutyLabelHi': d.label, 'sankhya': 0,
          'siArmedCount': 0, 'siUnarmedCount': 0,
          'hcArmedCount': 0, 'hcUnarmedCount': 0,
          'constArmedCount': 0, 'constUnarmedCount': 0,
          'auxArmedCount': 0, 'auxUnarmedCount': 0,
          'pacCount': 0.0,
        };
        final r = Map<String, dynamic>.from(base);
        r['dutyType']    = d.type;
        r['dutyLabelHi'] = d.label;
        r['sortOrder']   = (i + 1) * 10;
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

  // ── Add / edit custom duty type ───────────────────────────────────────────
  Future<void> _showAddDialog({_DutyEntry? editing}) async {
    final ctrl   = TextEditingController(text: editing?.label ?? '');
    final isEdit = editing != null;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
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
          Expanded(child: Text(isEdit ? 'ड्यूटी प्रकार संपादित करें' : 'नया ड्यूटी प्रकार जोड़ें',
              style: const TextStyle(color: kDark, fontSize: 14, fontWeight: FontWeight.w800))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('ड्यूटी का नाम (हिंदी में)',
              style: TextStyle(color: kSubtle, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kBorder.withOpacity(0.6))),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: TextField(controller: ctrl, autofocus: true,
              style: const TextStyle(color: kDark, fontSize: 15, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(border: InputBorder.none,
                  hintText: 'जैसे: विशेष मोबाईल ड्यूटी',
                  hintStyle: TextStyle(color: kSubtle))),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('रद्द करें', style: TextStyle(color: kSubtle))),
          ElevatedButton(
            onPressed: () { if (ctrl.text.trim().isEmpty) return; Navigator.pop(ctx, true); },
            style: ElevatedButton.styleFrom(backgroundColor: kCustomColor,
                foregroundColor: Colors.white, elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: Text(isEdit ? 'अपडेट करें' : 'जोड़ें'),
          ),
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
        final res  = await ApiService.post('/admin/district-rules/custom',
            {'labelHi': label}, token: token);
        final data = (res['data'] ?? res) as Map<String, dynamic>;
        final entry = _DutyEntry(
          type:      data['dutyType'] as String,
          label:     data['dutyLabelHi'] as String,
          icon:      Icons.assignment_outlined,
          isDefault: false,
        );
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

  // ── Delete custom duty type ───────────────────────────────────────────────
  Future<void> _deleteCustomDuty(_DutyEntry entry) async {
    final hasRule = _hasAny(_byDuty[entry.type]);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('ड्यूटी प्रकार हटाएं?',
            style: TextStyle(color: kDark, fontWeight: FontWeight.w800)),
        content: Text(
          hasRule
              ? '"${entry.label}" और इसका मानक दोनों हटा दिए जाएंगे।'
              : '"${entry.label}" को हटाया जाएगा।',
          style: const TextStyle(color: kDark)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('रद्द करें', style: TextStyle(color: kSubtle))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kError,
                foregroundColor: Colors.white, elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('हटाएं'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final token = await AuthService.getToken();
      await ApiService.delete('/admin/district-rules/custom/${entry.type}', token: token);
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
        content: const Text('आपने कुछ बदलाव किए हैं। क्या आप बिना सेव के बाहर निकलना चाहते हैं?',
            style: TextStyle(color: kDark)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('रद्द करें', style: TextStyle(color: kSubtle))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kError,
                foregroundColor: Colors.white),
            child: const Text('बाहर निकलें')),
        ],
      ),
    );
    return discard == true;
  }

  @override
  Widget build(BuildContext context) {
    final filledCount = _duties.where((d) => _hasAny(_byDuty[d.type])).length;
    final totalAll    = _duties.where((d) => _hasAny(_byDuty[d.type]))
        .fold<int>(0, (s, d) => s + _totalStaff(_byDuty[d.type]));
    final assignedAll = _duties.fold<int>(0, (s, d) => s + d.totalAssigned);

    final isJobRunning = _autoJobStatus == 'running' || _autoJobStatus == 'pending';

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          backgroundColor: kDistrictColor,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('जनपदीय कानून व्यवस्था',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            Text('मानक + ड्यूटी असाइनमेंट',
                style: TextStyle(fontSize: 11, color: Colors.white70)),
          ]),
          actions: [
            IconButton(icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'पुनः लोड करें', onPressed: _loadAll),
            // Clear all button
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, size: 20),
              tooltip: 'सभी Assignments हटाएं',
              onPressed: isJobRunning ? null : _clearAllAssignments,
            ),
            if (_changed)
              Padding(padding: const EdgeInsets.only(right: 6),
                child: Center(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(20)),
                  child: const Text('अनसेव्ड',
                      style: TextStyle(color: Colors.white, fontSize: 10,
                          fontWeight: FontWeight.w800))))),
          ],
          bottom: TabBar(
            controller: _tabCtrl,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            unselectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            tabs: const [
              Tab(text: 'मानक'),
              Tab(text: 'ड्यूटी'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: kDistrictColor))
            : Column(children: [
                // Auto-assign progress banner
                if (isJobRunning || _autoJobStatus == 'done')
                  _AutoAssignBanner(
                    status:   _autoJobStatus,
                    pct:      _autoJobPct,
                    assigned: _autoAssigned,
                    skipped:  _autoSkipped,
                    onDismiss: () => _safeSetState(() => _autoJobStatus = ''),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _ManakvTab(
                        duties: _duties, byDuty: _byDuty,
                        filledCount: filledCount, totalAll: totalAll,
                        hasAny: _hasAny, totalStaff: _totalStaff,
                        onEdit: _openRankEditor,
                        onAdd: () => _showAddDialog(),
                        onEditCustom: (e) => _showAddDialog(editing: e),
                        onDelete: _deleteCustomDuty,
                      ),
                      _DutyTab(
                        duties: _duties, summary: _summary,
                        assignedAll: assignedAll,
                        onOpenDetail: _openDutyDetail,
                        onRefresh: _loadAll,
                      ),
                    ],
                  ),
                ),
              ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Auto assign row
              Row(children: [
                Expanded(child: SizedBox(height: 46,
                  child: ElevatedButton.icon(
                    onPressed: isJobRunning ? null : _startAutoAssign,
                    icon: isJobRunning
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.auto_fix_high, size: 17),
                    label: Text(isJobRunning ? 'Running... $_autoJobPct%' : 'Auto Assign',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: isJobRunning ? kSubtle : kOrange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0),
                  ))),
              ]),
              const SizedBox(height: 8),
              // Add + Save row
              Row(children: [
                GestureDetector(
                  onTap: () => _showAddDialog(),
                  child: Container(height: 50, padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: kCustomColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kCustomColor.withOpacity(0.4))),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add_circle_outline, color: kCustomColor, size: 20),
                      SizedBox(width: 6),
                      Text('नया जोड़ें',
                          style: TextStyle(color: kCustomColor, fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ])),
                ),
                const SizedBox(width: 10),
                Expanded(child: SizedBox(height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _saveAll,
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_rounded, size: 18),
                    label: Text(_saving ? 'सेव हो रहा है...' : 'मानक सेव करें',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _saving ? kSubtle : kDistrictColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0),
                  ))),
              ]),
            ]),
          ),
        ),
      ),
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

  const _AutoAssignBanner({
    required this.status, required this.pct,
    required this.assigned, required this.skipped,
    required this.onDismiss,
  });

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
            isRunning ? 'Auto-assign चल रही है... $pct%'
                : '$assigned Staff assign हुए, $skipped skip',
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800),
          )),
          GestureDetector(onTap: onDismiss,
              child: Icon(Icons.close, size: 16, color: color)),
        ]),
        if (isRunning) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct / 100.0,
              backgroundColor: kOrange.withOpacity(0.15),
              valueColor: const AlwaysStoppedAnimation(kOrange),
              minHeight: 4,
            ),
          ),
        ],
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  TAB 1: MANAK
// ══════════════════════════════════════════════════════════════════════════════
class _ManakvTab extends StatelessWidget {
  final List<_DutyEntry>               duties;
  final Map<String, Map<String, dynamic>> byDuty;
  final int                            filledCount, totalAll;
  final bool Function(Map<String, dynamic>?) hasAny;
  final int  Function(Map<String, dynamic>?) totalStaff;
  final void Function(_DutyEntry, int) onEdit;
  final VoidCallback                   onAdd;
  final void Function(_DutyEntry)      onEditCustom, onDelete;

  const _ManakvTab({
    required this.duties, required this.byDuty,
    required this.filledCount, required this.totalAll,
    required this.hasAny, required this.totalStaff,
    required this.onEdit, required this.onAdd,
    required this.onEditCustom, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        color: kSurface,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          const Icon(Icons.shield_outlined, size: 14, color: kDistrictColor),
          const SizedBox(width: 6),
          const Expanded(child: Text('ड्यूटी प्रकार पर टैप करके पुलिस बल सेट करें',
              style: TextStyle(color: kDark, fontSize: 11.5, fontWeight: FontWeight.w600))),
          Text('$totalAll', style: const TextStyle(color: kDistrictColor,
              fontSize: 11.5, fontWeight: FontWeight.w800)),
          const SizedBox(width: 4),
          Text('($filledCount/${duties.length})',
              style: const TextStyle(color: kSubtle, fontSize: 11)),
        ]),
      ),
      Expanded(child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
        itemCount: duties.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final entry = duties[i];
          final r     = byDuty[entry.type];
          final isSet = hasAny(r);
          return _DutyRuleCard(
            entry:      entry,
            isSet:      isSet,
            sankhya:    isSet ? ((r!['sankhya'] ?? 0) as num).toInt() : 0,
            totalStaff: totalStaff(r),
            rule:       r,
            onTap:      () => onEdit(entry, (i + 1) * 10),
            onEdit:     entry.isDefault ? null : () => onEditCustom(entry),
            onDelete:   entry.isDefault ? null : () => onDelete(entry),
          );
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
    if (duties.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.assignment_outlined, size: 56, color: kSubtle.withOpacity(0.3)),
        const SizedBox(height: 16),
        const Text('पहले मानक टैब में ड्यूटी प्रकार सेट करें',
            style: TextStyle(color: kSubtle, fontSize: 13)),
      ]));
    }

    return Column(children: [
      Container(
        color: kAssignColor.withOpacity(0.07),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          const Icon(Icons.people_outlined, size: 14, color: kAssignColor),
          const SizedBox(width: 6),
          const Expanded(child: Text('ड्यूटी प्रकार पर टैप करके assign/view करें',
              style: TextStyle(color: kDark, fontSize: 11.5, fontWeight: FontWeight.w600))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: kAssignColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Text('$assignedAll Assigned',
                style: const TextStyle(color: kAssignColor, fontSize: 11.5,
                    fontWeight: FontWeight.w800))),
        ]),
      ),
      Expanded(child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
        itemCount: duties.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final entry    = duties[i];
          final s        = summary[entry.type] ?? {};
          final assigned = ((s['totalAssigned'] ?? 0) as num).toInt();
          final batches  = ((s['batchCount']    ?? 0) as num).toInt();
          final sankhya  = entry.sankhya;
          final pct      = sankhya > 0 ? (assigned / sankhya).clamp(0.0, 1.0) : 0.0;
          final isOver   = assigned > sankhya && sankhya > 0;
          final isFull   = sankhya > 0 && assigned >= sankhya;

          return _DutyAssignCard(
            entry:    entry,
            assigned: assigned,
            batches:  batches,
            sankhya:  sankhya,
            pct:      pct,
            isOver:   isOver,
            isFull:   isFull,
            onTap:    () => onOpenDetail(entry),
          );
        },
      )),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DUTY ASSIGN CARD (tab 2)
// ══════════════════════════════════════════════════════════════════════════════
class _DutyAssignCard extends StatelessWidget {
  final _DutyEntry entry;
  final int assigned, batches, sankhya;
  final double pct;
  final bool isOver, isFull;
  final VoidCallback onTap;

  const _DutyAssignCard({
    required this.entry, required this.assigned, required this.batches,
    required this.sankhya, required this.pct, required this.isOver,
    required this.isFull, required this.onTap,
  });

  Color get _barColor {
    if (isOver) return kError;
    if (isFull) return kSuccess;
    if (pct > 0.5) return kOrange;
    return kAssignColor;
  }

  @override
  Widget build(BuildContext context) {
    final color = entry.isDefault ? kDistrictColor : kCustomColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: assigned > 0 ? color.withOpacity(0.04) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: assigned > 0 ? color.withOpacity(0.35) : kBorder.withOpacity(0.4),
                width: assigned > 0 ? 1.5 : 1),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 40, height: 40,
                decoration: BoxDecoration(
                    color: assigned > 0 ? color : kSubtle.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(entry.icon,
                    color: assigned > 0 ? Colors.white : kSubtle, size: 20)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(entry.label,
                    style: const TextStyle(color: kDark, fontSize: 13.5,
                        fontWeight: FontWeight.w700),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(children: [
                  if (sankhya > 0) ...[
                    Text('$assigned/$sankhya',
                        style: TextStyle(color: _barColor, fontSize: 11,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(width: 6),
                  ] else
                    Text('$assigned assigned',
                        style: TextStyle(color: color, fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  if (batches > 0) ...[
                    Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: kAssignColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(5)),
                      child: Text('$batches batch${batches > 1 ? 'es' : ''}',
                          style: const TextStyle(color: kAssignColor, fontSize: 9,
                              fontWeight: FontWeight.w700))),
                  ],
                ]),
              ])),
              if (isFull)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: kSuccess.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle, color: kSuccess, size: 12),
                    SizedBox(width: 4),
                    Text('Full', style: TextStyle(color: kSuccess, fontSize: 10,
                        fontWeight: FontWeight.w700)),
                  ])),
              if (isOver)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: kError.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.warning_amber, color: kError, size: 12),
                    SizedBox(width: 4),
                    Text('Over', style: TextStyle(color: kError, fontSize: 10,
                        fontWeight: FontWeight.w700)),
                  ])),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(color: kAssignColor, borderRadius: BorderRadius.circular(9)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.people_outlined, size: 13, color: Colors.white),
                  SizedBox(width: 4),
                  Text('देखें', style: TextStyle(color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w700)),
                ])),
            ]),
            if (sankhya > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  backgroundColor: _barColor.withOpacity(0.12),
                  valueColor: AlwaysStoppedAnimation(_barColor),
                  minHeight: 5,
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DUTY DETAIL PAGE — batch-wise list + assign button
// ══════════════════════════════════════════════════════════════════════════════
class _DutyDetailPage extends StatefulWidget {
  final _DutyEntry             entry;
  final Map<String, dynamic>?  rule;
  final VoidCallback           onRefresh;

  const _DutyDetailPage({
    super.key,
    required this.entry,
    required this.rule,
    required this.onRefresh,
  });

  @override
  State<_DutyDetailPage> createState() => _DutyDetailPageState();
}

class _DutyDetailPageState extends State<_DutyDetailPage> {
  List<Map<String, dynamic>> _batches = [];
  bool _loading  = true;
  bool _disposed = false;

  @override
  void initState() { super.initState(); _loadBatches(); }

  @override
  void dispose() { _disposed = true; super.dispose(); }

  void _safeSetState(VoidCallback fn) { if (!_disposed && mounted) setState(fn); }

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
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AssignStaffSheet(
        entry: widget.entry,
        rule:  widget.rule,
      ),
    );
    if (result == true) {
      await _loadBatches();
      widget.onRefresh();
    }
  }

  Future<void> _deleteBatch(int batchNo) async {
    final confirmed = await _confirmDlg(context, 'Batch $batchNo के सभी staff हटाएं?');
    if (!confirmed || _disposed) return;
    try {
      final token = await AuthService.getToken();
      await ApiService.delete(
          '/admin/district-duty/${widget.entry.type}/batch/$batchNo', token: token);
      if (!_disposed && mounted) {
        showSnack(context, 'Batch $batchNo हटाया गया');
        _loadBatches();
        widget.onRefresh();
      }
    } catch (e) {
      if (!_disposed && mounted) showSnack(context, 'Error: $e', error: true);
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await _confirmDlg(context,
        '"${widget.entry.label}" के सभी assignments हटाएं?');
    if (!confirmed || _disposed) return;
    try {
      final token = await AuthService.getToken();
      await ApiService.delete(
          '/admin/district-duty/${widget.entry.type}/clear', token: token);
      if (!_disposed && mounted) {
        showSnack(context, 'सभी assignments हटाए गए');
        _loadBatches();
        widget.onRefresh();
      }
    } catch (e) {
      if (!_disposed && mounted) showSnack(context, 'Error: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color     = widget.entry.isDefault ? kDistrictColor : kCustomColor;
    final sankhya   = widget.entry.sankhya;
    final totalAsgn = _batches.fold<int>(0,
        (s, b) => s + ((b['staffCount'] ?? 0) as num).toInt());

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.entry.label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('${_batches.length} Batches • $totalAsgn Assigned',
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
        actions: [
          if (_batches.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, size: 22),
              tooltip: 'सभी हटाएं',
              onPressed: _clearAll,
            ),
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _loadBatches),
        ],
      ),
      body: Column(children: [
        // Stats strip
        Container(
          color: color.withOpacity(0.07),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            _StatChip(label: 'आवश्यक',  value: '$sankhya',   color: color),
            const SizedBox(width: 8),
            _StatChip(label: 'Assigned', value: '$totalAsgn',
                color: totalAsgn >= sankhya && sankhya > 0 ? kSuccess : kAssignColor),
            const SizedBox(width: 8),
            _StatChip(label: 'Batches',  value: '${_batches.length}', color: kOrange),
            const Spacer(),
            if (sankhya > 0)
              Text(totalAsgn >= sankhya ? '✓ पूर्ण' : '${sankhya - totalAsgn} बाकी',
                  style: TextStyle(
                      color: totalAsgn >= sankhya ? kSuccess : kError,
                      fontSize: 12, fontWeight: FontWeight.w800)),
          ]),
        ),

        // Rule summary strip
        if (widget.rule != null && _hasAnyRule(widget.rule!))
          Container(
            color: color.withOpacity(0.04),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: _ChipRow(rule: widget.rule!, cardColor: color),
          ),

        // Batch list
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: kDistrictColor))
          : _batches.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(widget.entry.icon, size: 56, color: kSubtle.withOpacity(0.3)),
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
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                    itemCount: _batches.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final batch = _batches[i];
                      return _BatchCard(
                        batch:     batch,
                        color:     color,
                        onDelete:  () => _deleteBatch(batch['batchNo'] as int),
                        onViewAll: () => _openBatchDetail(batch),
                      );
                    },
                  ),
                )),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAssignSheet,
        backgroundColor: color,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_outlined, size: 20),
        label: const Text('Assign Staff', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }

  bool _hasAnyRule(Map<String, dynamic> r) {
    for (final key in ['siArmedCount','siUnarmedCount','hcArmedCount',
        'hcUnarmedCount','constArmedCount','constUnarmedCount',
        'auxArmedCount','auxUnarmedCount','pacCount']) {
      if (((r[key] ?? 0) as num) > 0) return true;
    }
    return false;
  }

  void _openBatchDetail(Map<String, dynamic> batch) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _BatchDetailPage(
        dutyType:  widget.entry.type,
        dutyLabel: widget.entry.label,
        batch:     batch,
        color:     widget.entry.isDefault ? kDistrictColor : kCustomColor,
        onRefresh: () {
          _loadBatches();
          widget.onRefresh();
        },
      ),
    ));
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
    final batchNo    = batch['batchNo']    as int? ?? 0;
    final staffCount = (batch['staffCount'] ?? 0) as num;
    final staffList  = (batch['staff'] as List?)?.cast<Map>() ?? [];
    final busNo      = (batch['busNo']  as String?) ?? '';
    final note       = (batch['note']   as String?) ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.06),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Batch header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(11), topRight: Radius.circular(11))),
          child: Row(children: [
            Container(width: 34, height: 34,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Center(child: Text('$batchNo',
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w900, fontSize: 14)))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Batch $batchNo',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
              Row(children: [
                Text('${staffCount.toInt()} staff',
                    style: const TextStyle(color: kSubtle, fontSize: 11)),
                if (busNo.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.directions_bus_outlined, size: 10, color: kSubtle),
                    const SizedBox(width: 3),
                    Text(busNo, style: const TextStyle(color: kSubtle, fontSize: 10)),
                  ]),
                ],
                if (note.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(child: Text(note,
                      style: const TextStyle(color: kSubtle, fontSize: 10),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ]),
            ])),
            GestureDetector(
              onTap: onViewAll,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                child: const Text('विवरण', style: TextStyle(color: Colors.white,
                    fontSize: 11, fontWeight: FontWeight.w700)))),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onDelete,
              child: Container(width: 32, height: 32,
                decoration: BoxDecoration(color: kError.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kError.withOpacity(0.3))),
                child: const Icon(Icons.delete_outline, color: kError, size: 16))),
          ]),
        ),

        // Staff preview (first 6)
        if (staffList.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Wrap(spacing: 6, runSpacing: 6,
              children: staffList.take(6).map((s) {
                final rankColor = _rankColor(s['rank'] as String? ?? '');
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                      color: rankColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: rankColor.withOpacity(0.25))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 22, height: 22,
                      decoration: BoxDecoration(color: rankColor.withOpacity(0.15),
                          shape: BoxShape.circle),
                      child: Center(child: Text(
                        (s['name'] as String? ?? '').split(' ')
                            .where((w) => w.isNotEmpty).take(1).map((w) => w[0]).join().toUpperCase(),
                        style: TextStyle(color: rankColor, fontSize: 10,
                            fontWeight: FontWeight.w900)))),
                    const SizedBox(width: 5),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 80),
                      child: Text(s['name'] as String? ?? '',
                          style: const TextStyle(color: kDark, fontSize: 11,
                              fontWeight: FontWeight.w600),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: rankColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(s['rank'] as String? ?? '',
                          style: TextStyle(color: rankColor, fontSize: 8,
                              fontWeight: FontWeight.w700))),
                  ]));
              }).followedBy(staffList.length > 6
                  ? [Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(color: kSubtle.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text('+${staffList.length - 6} और',
                          style: const TextStyle(color: kSubtle, fontSize: 11)))]
                  : []).toList()),
          ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  BATCH DETAIL PAGE — full staff list
// ══════════════════════════════════════════════════════════════════════════════
class _BatchDetailPage extends StatefulWidget {
  final String           dutyType, dutyLabel;
  final Map<String, dynamic> batch;
  final Color            color;
  final VoidCallback     onRefresh;

  const _BatchDetailPage({super.key,
    required this.dutyType, required this.dutyLabel,
    required this.batch, required this.color, required this.onRefresh});

  @override
  State<_BatchDetailPage> createState() => _BatchDetailPageState();
}

class _BatchDetailPageState extends State<_BatchDetailPage> {
  late List<Map<String, dynamic>> _staff;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _staff = ((widget.batch['staff'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  @override
  void dispose() { _disposed = true; super.dispose(); }

  Future<void> _removeStaff(Map<String, dynamic> s) async {
    final confirmed = await _confirmDlg(context, '${s['name']} को हटाएं?');
    if (!confirmed) return;
    try {
      final token = await AuthService.getToken();
      await ApiService.delete(
          '/admin/district-duty/assignment/${s['assignmentId']}', token: token);
      if (!_disposed && mounted) {
        setState(() => _staff.removeWhere((x) => x['assignmentId'] == s['assignmentId']));
        widget.onRefresh();
        showSnack(context, '${s['name']} हटाया गया');
      }
    } catch (e) {
      if (!_disposed && mounted) showSnack(context, 'Error: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final batchNo = widget.batch['batchNo'] as int? ?? 0;
    final busNo   = widget.batch['busNo']   as String? ?? '';

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: widget.color,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.dutyLabel,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('Batch $batchNo • ${_staff.length} Staff${busNo.isNotEmpty ? ' • Bus: $busNo' : ''}',
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
      ),
      body: Column(children: [
        // Batch info banner
        Container(
          color: widget.color.withOpacity(0.07),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Container(width: 36, height: 36,
              decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
              child: Center(child: Text('$batchNo',
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w900, fontSize: 15)))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Batch $batchNo — ${widget.dutyLabel}',
                  style: TextStyle(color: widget.color,
                      fontWeight: FontWeight.w800, fontSize: 13),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${_staff.length} सदस्य — Sahyogi विवरण',
                  style: const TextStyle(color: kSubtle, fontSize: 11)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: widget.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: Text('${_staff.length}',
                  style: TextStyle(color: widget.color, fontWeight: FontWeight.w900,
                      fontSize: 16))),
          ]),
        ),

        // Rank summary row
        if (_staff.isNotEmpty)
          Container(
            color: kSurface.withOpacity(0.5),
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: _buildRankSummary()),
            ),
          ),

        // Info note
        Container(
          color: kAssignColor.withOpacity(0.06),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: const Row(children: [
            Icon(Icons.info_outline, size: 13, color: kAssignColor),
            SizedBox(width: 6),
            Expanded(child: Text(
              'इस batch के सभी staff एक साथ इस ड्यूटी पर तैनात हैं।',
              style: TextStyle(color: kAssignColor, fontSize: 11))),
          ]),
        ),

        Expanded(child: _staff.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.people_outline, size: 56, color: kSubtle.withOpacity(0.3)),
              const SizedBox(height: 12),
              const Text('कोई staff नहीं', style: TextStyle(color: kSubtle, fontSize: 13)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
              itemCount: _staff.length,
              itemBuilder: (_, i) {
                final s = _staff[i];
                return _StaffDetailCard(
                  staff: s, index: i, color: widget.color,
                  onRemove: () => _removeStaff(s),
                );
              },
            )),
      ]),
    );
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
        decoration: BoxDecoration(color: rc.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: rc.withOpacity(0.3))),
        child: Text('${e.key}: ${e.value}',
            style: TextStyle(color: rc, fontSize: 10, fontWeight: FontWeight.w700)),
      );
    }).toList();
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  STAFF DETAIL CARD
// ══════════════════════════════════════════════════════════════════════════════
class _StaffDetailCard extends StatelessWidget {
  final Map<String, dynamic> staff;
  final int   index;
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
        boxShadow: [BoxShadow(color: rc.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Row(children: [
        Container(width: 32, height: 32,
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.3))),
          child: Center(child: Text('${index + 1}',
              style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12)))),
        const SizedBox(width: 10),
        Container(width: 38, height: 38,
          decoration: BoxDecoration(color: rc.withOpacity(0.12), shape: BoxShape.circle,
              border: Border.all(color: rc.withOpacity(0.3))),
          child: Center(child: Text(
            (staff['name'] as String? ?? '').split(' ')
                .where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join().toUpperCase(),
            style: TextStyle(color: rc, fontWeight: FontWeight.w900, fontSize: 13)))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(staff['name'] as String? ?? '',
                style: const TextStyle(color: kDark, fontWeight: FontWeight.w700, fontSize: 13),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (isArmed) Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: const Color(0xFF6A1B9A).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(5)),
              child: const Text('🗡 Armed', style: TextStyle(color: Color(0xFF6A1B9A),
                  fontSize: 9, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 3),
          Wrap(spacing: 8, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: rc.withOpacity(0.1), borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: rc.withOpacity(0.3))),
              child: Text(rank, style: TextStyle(color: rc, fontSize: 9, fontWeight: FontWeight.w700))),
            if ((staff['pno'] as String?)?.isNotEmpty == true)
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.badge_outlined, size: 10, color: kSubtle),
                const SizedBox(width: 3),
                Text(staff['pno'] as String, style: const TextStyle(color: kSubtle, fontSize: 10)),
              ]),
            if ((staff['thana'] as String?)?.isNotEmpty == true)
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.local_police_outlined, size: 10, color: kSubtle),
                const SizedBox(width: 3),
                Text(staff['thana'] as String,
                    style: const TextStyle(color: kSubtle, fontSize: 10),
                    maxLines: 1),
              ]),
          ]),
          if ((staff['mobile'] as String?)?.isNotEmpty == true)
            Padding(padding: const EdgeInsets.only(top: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.phone_outlined, size: 10, color: kSubtle),
                const SizedBox(width: 3),
                Text(staff['mobile'] as String, style: const TextStyle(color: kSubtle, fontSize: 10)),
              ])),
        ])),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onRemove,
          child: Container(width: 32, height: 32,
            decoration: BoxDecoration(color: kError.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kError.withOpacity(0.25))),
            child: const Icon(Icons.person_remove_outlined, size: 16, color: kError))),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  ASSIGN STAFF SHEET — manual batch creation
// ══════════════════════════════════════════════════════════════════════════════
class _AssignStaffSheet extends StatefulWidget {
  final _DutyEntry            entry;
  final Map<String, dynamic>? rule;

  const _AssignStaffSheet({required this.entry, required this.rule});

  @override
  State<_AssignStaffSheet> createState() => _AssignStaffSheetState();
}

class _AssignStaffSheetState extends State<_AssignStaffSheet> {
  final List<Map>    _staff       = [];
  final Set<int>     _selected    = {};
  final _busCtrl                  = TextEditingController();
  final _noteCtrl                 = TextEditingController();
  final _searchCtrl               = TextEditingController();
  final ScrollController _scroll  = ScrollController();

  bool   _loading     = true;
  bool   _loadingMore = false;
  bool   _hasMore     = true;
  bool   _saving      = false;
  bool   _disposed    = false;
  int    _page        = 1;
  String _q           = '';
  String _rankFilter  = '';
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
    _scroll.dispose();
    _searchCtrl.dispose();
    _busCtrl.dispose();
    _noteCtrl.dispose();
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

  void _safeSetState(VoidCallback fn) { if (!_disposed && mounted) setState(fn); }
  void _reload() { _safeSetState(() { _staff.clear(); _page = 1; _hasMore = true; _selected.clear(); }); _load(reset: true); }

  Future<void> _load({bool reset = false}) async {
    if (_disposed) return;
    if (!_hasMore && !reset) return;
    if (_loadingMore) return;
    _safeSetState(() { if (reset) _loading = true; else _loadingMore = true; });
    try {
      final token = await AuthService.getToken();
      if (_disposed) return;
      var url = '/admin/district-duty/${widget.entry.type}/available-staff'
          '?page=$_page&limit=20&q=${Uri.encodeComponent(_q)}';
      if (_rankFilter.isNotEmpty) url += '&rank=${Uri.encodeComponent(_rankFilter)}';
      final res = await ApiService.get(url, token: token);
      if (_disposed) return;
      final w     = (res['data'] as Map<String, dynamic>?) ?? {};
      final items = (w['data'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      final pages = (w['totalPages'] as num?)?.toInt() ?? 1;
      _safeSetState(() {
        _staff.addAll(items); _hasMore = _page < pages; _page++;
        _loading = false; _loadingMore = false;
      });
    } catch (_) { _safeSetState(() { _loading = false; _loadingMore = false; }); }
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
          'busNo':    _busCtrl.text.trim(),
          'note':     _noteCtrl.text.trim(),
        },
        token: token,
      );
      if (!_disposed && mounted) {
        final data    = res['data'] as Map?;
        final batchNo = data?['batchNo']  ?? 0;
        final asgnd   = data?['assigned'] ?? 0;
        final skipped = data?['skipped']  ?? 0;
        showSnack(context,
            'Batch $batchNo बना: $asgnd Assigned${skipped > 0 ? ', $skipped skip' : ''}');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!_disposed && mounted) showSnack(context, 'Error: $e', error: true);
      _safeSetState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.entry.isDefault ? kDistrictColor : kCustomColor;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(color: kBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(children: [
        Container(margin: const EdgeInsets.only(top: 10, bottom: 4), width: 40, height: 4,
          decoration: BoxDecoration(color: kBorder.withOpacity(0.5), borderRadius: BorderRadius.circular(2))),

        Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 12), child: Column(children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(widget.entry.icon, color: color, size: 18)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Staff Assign करें', style: TextStyle(color: kDark,
                  fontWeight: FontWeight.w800, fontSize: 15)),
              Text(widget.entry.label, style: const TextStyle(color: kSubtle, fontSize: 12),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            if (_selected.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
                child: Text('${_selected.length} चुने',
                    style: const TextStyle(color: Colors.white, fontSize: 12,
                        fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 10),

          SingleChildScrollView(scrollDirection: Axis.horizontal,
            child: Row(children: [
              _filterChip('सभी', '', color),
              ..._kRanks.map((r) => _filterChip(r, r, color)),
            ])),
          const SizedBox(height: 8),

          TextField(controller: _searchCtrl,
            style: const TextStyle(color: kDark, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'नाम, PNO खोजें...',
              hintStyle: const TextStyle(color: kSubtle, fontSize: 12),
              prefixIcon: const Icon(Icons.search, color: kSubtle, size: 18),
              filled: true, fillColor: Colors.white, isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: kBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: color, width: 2)))),

          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _miniField(_busCtrl, 'Bus No (optional)',
                Icons.directions_bus_outlined, color)),
            const SizedBox(width: 8),
            Expanded(child: _miniField(_noteCtrl, 'Note (optional)',
                Icons.note_outlined, color)),
          ]),
        ])),

        // Staff list
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: kDistrictColor))
          : _staff.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.people_outline, size: 48, color: kSubtle.withOpacity(0.4)),
                  const SizedBox(height: 12),
                  const Text('कोई unassigned staff नहीं मिला',
                      style: TextStyle(color: kSubtle, fontSize: 13))]))
              : Scrollbar(controller: _scroll, thumbVisibility: true, thickness: 5,
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                    itemCount: _staff.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= _staff.length) return const Padding(padding: EdgeInsets.all(12),
                        child: Center(child: SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: kDistrictColor))));
                      final s     = _staff[i];
                      final sid   = s['id'] as int;
                      final isSel = _selected.contains(sid);
                      final rank  = s['rank'] as String? ?? '';
                      final rc    = _rankColor(rank);

                      return GestureDetector(
                        onTap: () => _safeSetState(() {
                          if (isSel) _selected.remove(sid); else _selected.add(sid); }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSel ? color.withOpacity(0.07) : Colors.white,
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
                              child: isSel ? const Icon(Icons.check, size: 14,
                                  color: Colors.white) : null),
                            const SizedBox(width: 10),
                            Container(width: 36, height: 36,
                              decoration: BoxDecoration(color: rc.withOpacity(0.12),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: rc.withOpacity(0.3))),
                              child: Center(child: Text(
                                (s['name'] as String? ?? '').split(' ')
                                    .where((w) => w.isNotEmpty).take(2)
                                    .map((w) => w[0]).join().toUpperCase(),
                                style: TextStyle(color: rc, fontWeight: FontWeight.w900,
                                    fontSize: 12)))),
                            const SizedBox(width: 10),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(s['name'] as String? ?? '',
                                  style: TextStyle(color: isSel ? color : kDark,
                                      fontWeight: FontWeight.w700, fontSize: 13),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              Row(children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(color: rc.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: rc.withOpacity(0.3))),
                                  child: Text(rank, style: TextStyle(color: rc,
                                      fontSize: 9, fontWeight: FontWeight.w700))),
                                if ((s['pno'] as String?)?.isNotEmpty == true) ...[
                                  const SizedBox(width: 6),
                                  Text(s['pno'] as String,
                                      style: const TextStyle(color: kSubtle, fontSize: 10)),
                                ],
                                if ((s['thana'] as String?)?.isNotEmpty == true) ...[
                                  const SizedBox(width: 6),
                                  Flexible(child: Text(s['thana'] as String,
                                      style: const TextStyle(color: kSubtle, fontSize: 10),
                                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                                ],
                              ]),
                            ])),
                          ]),
                        ),
                      );
                    }),
                )),

        Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: SizedBox(width: double.infinity, height: 50,
            child: ElevatedButton.icon(
              onPressed: (_saving || _selected.isEmpty) ? null : _assign,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle_outline, size: 20),
              label: Text(
                _saving ? 'Assigning...'
                    : _selected.isEmpty ? 'Staff चुनें'
                    : '${_selected.length} Staff Assign करें (New Batch)',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _selected.isEmpty ? kSubtle : color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0),
            ))),
      ]),
    );
  }

  Widget _filterChip(String label, String value, Color color) {
    final sel = _rankFilter == value;
    final c   = value.isEmpty ? kDistrictColor : (_rankColor(value));
    return GestureDetector(
      onTap: () { _safeSetState(() => _rankFilter = value); _reload(); },
      child: Container(margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: sel ? c : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: sel ? c : kBorder.withOpacity(0.5))),
        child: Text(label, style: TextStyle(
            color: sel ? Colors.white : kDark,
            fontSize: 11, fontWeight: sel ? FontWeight.w700 : FontWeight.w500))));
  }

  Widget _miniField(TextEditingController ctrl, String hint, IconData icon, Color color) =>
    TextField(controller: ctrl,
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
}

// ══════════════════════════════════════════════════════════════════════════════
//  DUTY RULE CARD (manak tab)
// ══════════════════════════════════════════════════════════════════════════════
class _DutyRuleCard extends StatelessWidget {
  final _DutyEntry              entry;
  final bool                    isSet;
  final int                     sankhya, totalStaff;
  final Map<String, dynamic>?   rule;
  final VoidCallback            onTap;
  final VoidCallback?           onEdit, onDelete;

  const _DutyRuleCard({
    required this.entry, required this.isSet, required this.sankhya,
    required this.totalStaff, required this.rule, required this.onTap,
    this.onEdit, this.onDelete,
  });

  Color get _color => entry.isDefault ? kDistrictColor : kCustomColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: isSet ? _color.withOpacity(0.06) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isSet ? _color.withOpacity(0.4) : kBorder.withOpacity(0.4),
                width: isSet ? 1.5 : 1)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(entry.label,
                      style: const TextStyle(color: kDark, fontSize: 13.5,
                          fontWeight: FontWeight.w700))),
                  if (!entry.isDefault) Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: kCustomColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6)),
                    child: const Text('कस्टम',
                        style: TextStyle(color: kCustomColor, fontSize: 9,
                            fontWeight: FontWeight.w800))),
                ]),
                const SizedBox(height: 3),
                if (isSet)
                  Row(children: [
                    Text('संख्या: $sankhya',
                        style: TextStyle(color: _color, fontSize: 11, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    Text('• कुल: $totalStaff',
                        style: const TextStyle(color: kSubtle, fontSize: 11, fontWeight: FontWeight.w600)),
                  ])
                else
                  const Text('मानक सेट नहीं है', style: TextStyle(color: kSubtle, fontSize: 11)),
              ])),
              Icon(isSet ? Icons.check_circle_rounded : Icons.add_circle_outline,
                  color: isSet ? kSuccess : kSubtle, size: 18),
              if (!entry.isDefault) ...[
                const SizedBox(width: 4),
                _iconBtn(Icons.edit_outlined, kCustomColor, onEdit),
                const SizedBox(width: 4),
                _iconBtn(Icons.delete_outline, kError, onDelete),
              ] else ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: kSubtle, size: 20),
              ],
            ]),
            if (isSet && rule != null) ...[
              const SizedBox(height: 10),
              _ChipRow(rule: rule!, cardColor: _color),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, Color color, VoidCallback? onTap) =>
    GestureDetector(onTap: onTap,
      child: Container(width: 30, height: 30,
        decoration: BoxDecoration(color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: color.withOpacity(0.25))),
        child: Icon(icon, size: 15, color: color)));
}

// ── Chip Row ──────────────────────────────────────────────────────────────────
class _ChipRow extends StatelessWidget {
  final Map<String, dynamic> rule;
  final Color                cardColor;
  const _ChipRow({required this.rule, required this.cardColor});

  @override
  Widget build(BuildContext context) {
    final siA  = (rule['siArmedCount']      ?? 0) as num;
    final siU  = (rule['siUnarmedCount']    ?? 0) as num;
    final hcA  = (rule['hcArmedCount']      ?? 0) as num;
    final hcU  = (rule['hcUnarmedCount']    ?? 0) as num;
    final cA   = (rule['constArmedCount']   ?? 0) as num;
    final cU   = (rule['constUnarmedCount'] ?? 0) as num;
    final auxA = (rule['auxArmedCount']     ?? 0) as num;
    final auxU = (rule['auxUnarmedCount']   ?? 0) as num;
    final pac  = (rule['pacCount']          ?? 0) as num;

    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
      if (siA + siU   > 0) _chip('SI',    siA,  siU,  cardColor),
      if (hcA + hcU   > 0) _chip('HC',    hcA,  hcU,  cardColor),
      if (cA  + cU    > 0) _chip('Const', cA,   cU,   cardColor),
      if (auxA + auxU > 0) _chip('Aux',   auxA, auxU,  const Color(0xFFE65100)),
      if (pac > 0)         _singleChip('PAC',
          pac == pac.toInt() ? '${pac.toInt()}' : '$pac',
          const Color(0xFF00695C)),
    ]));
  }

  Widget _chip(String label, num armed, num unarmed, Color color) => Container(
    margin: const EdgeInsets.only(right: 6),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label: ', style: TextStyle(color: color.withOpacity(0.85),
          fontSize: 10.5, fontWeight: FontWeight.w700)),
      if (armed > 0) ...[
        const Icon(Icons.gavel, size: 9, color: Color(0xFF6A1B9A)),
        Text('$armed', style: const TextStyle(color: Color(0xFF6A1B9A),
            fontSize: 11, fontWeight: FontWeight.w900))],
      if (armed > 0 && unarmed > 0)
        Text(' / ', style: TextStyle(color: color.withOpacity(0.5), fontSize: 11)),
      if (unarmed > 0) ...[
        const Icon(Icons.shield_outlined, size: 9, color: Color(0xFF1A5276)),
        Text('$unarmed', style: const TextStyle(color: Color(0xFF1A5276),
            fontSize: 11, fontWeight: FontWeight.w900))],
    ]));

  Widget _singleChip(String label, String value, Color c) => Container(
    margin: const EdgeInsets.only(right: 6),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withOpacity(0.3))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label: ', style: TextStyle(color: c.withOpacity(0.85),
          fontSize: 10.5, fontWeight: FontWeight.w700)),
      Text(value, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w900)),
    ]));
}

// ── Stat chip ─────────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3))),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w900)),
      Text(label, style: TextStyle(color: color.withOpacity(0.7), fontSize: 9,
          fontWeight: FontWeight.w600)),
    ]));
}

// ── Helpers ───────────────────────────────────────────────────────────────────
Color _rankColor(String rank) {
  const m = {
    'SP':             Color(0xFF6A1B9A),
    'ASP':            Color(0xFF1565C0),
    'DSP':            Color(0xFF1A5276),
    'Inspector':      Color(0xFF2E7D32),
    'SI':             Color(0xFF558B2F),
    'ASI':            Color(0xFF8B6914),
    'Head Constable': Color(0xFFB8860B),
    'Constable':      Color(0xFF6D4C41),
  };
  return m[rank] ?? kPrimary;
}

Future<bool> _confirmDlg(BuildContext ctx, String msg) async =>
  await showDialog<bool>(
    context: ctx,
    builder: (d) => AlertDialog(
      backgroundColor: kBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: kError, width: 1.2)),
      title: const Row(children: [
        Icon(Icons.warning_amber_rounded, color: kError, size: 20),
        SizedBox(width: 8),
        Text('Confirm', style: TextStyle(color: kError, fontWeight: FontWeight.w800, fontSize: 15))]),
      content: Text(msg, style: const TextStyle(color: kDark, fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false),
            child: const Text('रद्द', style: TextStyle(color: kSubtle))),
        ElevatedButton(onPressed: () => Navigator.pop(d, true),
          style: ElevatedButton.styleFrom(backgroundColor: kError, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          child: const Text('हटाएं')),
      ])) ?? false;