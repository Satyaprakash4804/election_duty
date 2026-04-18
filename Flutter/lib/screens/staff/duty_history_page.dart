import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';

// ── Palette (matches app theme) ──────────────────────────────────────────────
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

// ══════════════════════════════════════════════════════════════════════════════
//  DUTY HISTORY PAGE  — Staff-facing; shows all past + current duty records
// ══════════════════════════════════════════════════════════════════════════════

class DutyHistoryPage extends StatefulWidget {
  const DutyHistoryPage({super.key});
  @override
  State<DutyHistoryPage> createState() => _DutyHistoryPageState();
}

class _DutyHistoryPageState extends State<DutyHistoryPage> {
  List<Map<String, dynamic>> _duties = [];
  bool _loading = true;
  String? _error;

  // Filter
  String _filterStatus = 'All'; // All | Present | Absent | Upcoming

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get('/staff/history', token: token);
      final raw   = res['data'];
      final list  = (raw is List) ? raw : [];
      if (!mounted) return;
      setState(() {
        _duties  = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  // ── Filtering ─────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filtered {
    switch (_filterStatus) {
      case 'Present':  return _duties.where((d) => d['present'] == true).toList();
      case 'Absent':   return _duties.where((d) => d['present'] == false && d['date'] != null).toList();
      case 'Upcoming': return _duties.where((d) => d['date'] == null || _isUpcoming(d['date'])).toList();
      default:         return _duties;
    }
  }

  bool _isUpcoming(String? dateStr) {
    if (dateStr == null) return false;
    try {
      final d = DateTime.parse(dateStr);
      return d.isAfter(DateTime.now());
    } catch (_) { return false; }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'तारीख अज्ञात';
    try {
      final d = DateTime.parse(dateStr);
      const months = ['', 'जन', 'फर', 'मार्च', 'अप्रैल', 'मई', 'जून', 'जुलाई', 'अग', 'सित', 'अक्ट', 'नव', 'दिस'];
      return '${d.day} ${months[d.month]} ${d.year}';
    } catch (_) { return dateStr; }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ड्यूटी इतिहास', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          Text('Duty History', style: TextStyle(color: Colors.white54, fontSize: 10)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20), onPressed: _load),
        ],
      ),
      body: Column(children: [

        // ── Filter chips ────────────────────────────────────────────────────
        Container(
          color: _kSurface,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            for (final f in ['All', 'Upcoming', 'Present', 'Absent'])
              _filterChip(f),
          ]),
        ),

        // ── Stats summary row ────────────────────────────────────────────────
        if (!_loading && _error == null)
          _SummaryRow(duties: _duties),

        // ── List ─────────────────────────────────────────────────────────────
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _load)
              : _filtered.isEmpty
                  ? _EmptyView(filter: _filterStatus)
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: _kPrimary,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) => _DutyCard(
                          duty: _filtered[i],
                          dateFormatter: _formatDate,
                          isUpcoming: _isUpcoming(_filtered[i]['date']),
                        ),
                      ),
                    )),
      ]),
    );
  }

  Widget _filterChip(String label) {
    final isSel  = _filterStatus == label;
    final color  = switch(label) {
      'Present'  => _kSuccess,
      'Absent'   => _kError,
      'Upcoming' => _kInfo,
      _          => _kPrimary,
    };
    final hindiLabel = switch(label) {
      'Present'  => '✅ उपस्थित',
      'Absent'   => '❌ अनुपस्थित',
      'Upcoming' => '🗓 आगामी',
      _          => 'सभी',
    };
    return GestureDetector(
      onTap: () => setState(() => _filterStatus = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSel ? color : _kBorder.withOpacity(0.5)),
          boxShadow: isSel ? [BoxShadow(color: color.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))] : [],
        ),
        child: Text(hindiLabel,
          style: TextStyle(
            color: isSel ? Colors.white : _kDark,
            fontSize: 11,
            fontWeight: isSel ? FontWeight.w800 : FontWeight.w500)),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SUMMARY ROW — present/absent/upcoming counts
// ══════════════════════════════════════════════════════════════════════════════

class _SummaryRow extends StatelessWidget {
  final List<Map<String, dynamic>> duties;
  const _SummaryRow({required this.duties});

  @override
  Widget build(BuildContext context) {
    final present  = duties.where((d) => d['present'] == true).length;
    final absent   = duties.where((d) => d['present'] == false && d['date'] != null).length;
    final upcoming = duties.where((d) {
      final s = d['date'] as String?;
      if (s == null) return false;
      try { return DateTime.parse(s).isAfter(DateTime.now()); } catch (_) { return false; }
    }).length;

    return Container(
      color: _kBg,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(children: [
        _chip('कुल', '${duties.length}', _kPrimary),
        const SizedBox(width: 8),
        _chip('उपस्थित', '$present', _kSuccess),
        const SizedBox(width: 8),
        _chip('अनुपस्थित', '$absent', _kError),
        const SizedBox(width: 8),
        _chip('आगामी', '$upcoming', _kInfo),
      ]),
    );
  }

  Widget _chip(String label, String count, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(children: [
        Text(count, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900)),
        Text(label, style: const TextStyle(color: _kSubtle, fontSize: 10)),
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  DUTY CARD — one election record
// ══════════════════════════════════════════════════════════════════════════════

class _DutyCard extends StatefulWidget {
  final Map<String, dynamic> duty;
  final String Function(String?) dateFormatter;
  final bool isUpcoming;
  const _DutyCard({required this.duty, required this.dateFormatter, required this.isUpcoming});
  @override State<_DutyCard> createState() => _DutyCardState();
}

class _DutyCardState extends State<_DutyCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.duty;
    final isPresent = d['present'] as bool? ?? false;
    final hasDate   = d['date'] != null;
    final dateStr   = widget.dateFormatter(d['date'] as String?);

    // Status config
    late Color statusColor;
    late IconData statusIcon;
    late String statusText;
    if (widget.isUpcoming) {
      statusColor = _kInfo;
      statusIcon  = Icons.schedule_rounded;
      statusText  = 'आगामी';
    } else if (!hasDate) {
      statusColor = _kSubtle;
      statusIcon  = Icons.help_outline_rounded;
      statusText  = 'अज्ञात';
    } else if (isPresent) {
      statusColor = _kSuccess;
      statusIcon  = Icons.check_circle_rounded;
      statusText  = 'उपस्थित';
    } else {
      statusColor = _kError;
      statusIcon  = Icons.cancel_rounded;
      statusText  = 'अनुपस्थित';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withOpacity(0.25), width: 1.5),
        boxShadow: [BoxShadow(color: statusColor.withOpacity(0.07), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(children: [

        // ── Header ──────────────────────────────────────────────────────────
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(children: [

              // Status circle
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor.withOpacity(0.1),
                  border: Border.all(color: statusColor.withOpacity(0.35), width: 1.5),
                ),
                child: Icon(statusIcon, color: statusColor, size: 22),
              ),
              const SizedBox(width: 12),

              // Date + booth name
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.calendar_today_outlined, size: 11, color: _kSubtle),
                  const SizedBox(width: 3),
                  Text(dateStr, style: const TextStyle(color: _kSubtle, fontSize: 11)),
                ]),
                const SizedBox(height: 5),
                Text(
                  d['booth'] as String? ?? 'बूथ अज्ञात',
                  style: const TextStyle(color: _kDark, fontWeight: FontWeight.w700, fontSize: 14),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ])),

              // Expand arrow
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.keyboard_arrow_down_rounded, color: statusColor.withOpacity(0.7), size: 22),
              ),
            ]),
          ),
        ),

        // ── Hierarchy breadcrumb (always visible) ────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: _HierarchyRow(duty: d),
        ),

        // ── Expanded detail ──────────────────────────────────────────────────
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: _ExpandedDetail(duty: d),
          crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 220),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  HIERARCHY ROW — Super Zone → Zone → Sector → GP → Booth
// ══════════════════════════════════════════════════════════════════════════════

class _HierarchyRow extends StatelessWidget {
  final Map<String, dynamic> duty;
  const _HierarchyRow({required this.duty});

  @override
  Widget build(BuildContext context) {
    final items = <_HItem>[];

    if ((duty['superZone'] as String?)?.isNotEmpty == true)
      items.add(_HItem(duty['superZone'] as String, Icons.layers_outlined,         const Color(0xFF6A1B9A)));
    if ((duty['zone'] as String?)?.isNotEmpty == true)
      items.add(_HItem(duty['zone'] as String,      Icons.grid_view_outlined,       const Color(0xFF1565C0)));
    if ((duty['sector'] as String?)?.isNotEmpty == true)
      items.add(_HItem(duty['sector'] as String,    Icons.view_module_outlined,     const Color(0xFF2E7D32)));
    if ((duty['gramPanchayat'] as String?)?.isNotEmpty == true)
      items.add(_HItem(duty['gramPanchayat'] as String, Icons.account_balance_outlined, const Color(0xFF6D4C41)));

    if (items.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) const Icon(Icons.chevron_right, size: 12, color: _kSubtle),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: items[i].color.withOpacity(0.07),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: items[i].color.withOpacity(0.2)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(items[i].icon, size: 10, color: items[i].color),
              const SizedBox(width: 3),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 90),
                child: Text(items[i].label,
                    style: TextStyle(color: items[i].color, fontSize: 10, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _HItem {
  final String label; final IconData icon; final Color color;
  _HItem(this.label, this.icon, this.color);
}

// ══════════════════════════════════════════════════════════════════════════════
//  EXPANDED DETAIL — full assignment info
// ══════════════════════════════════════════════════════════════════════════════

class _ExpandedDetail extends StatelessWidget {
  final Map<String, dynamic> duty;
  const _ExpandedDetail({required this.duty});

  @override
  Widget build(BuildContext context) {
    final assigned = (duty['assignedStaff'] as List?)?.cast<Map>() ?? [];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Details grid
        _DetailGrid(duty: duty),

        if (assigned.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Divider(height: 1, color: _kBorder),
          const SizedBox(height: 10),
          const Row(children: [
            Icon(Icons.people_outline, size: 13, color: _kSubtle),
            SizedBox(width: 5),
            Text('इस बूथ पर तैनात सभी स्टाफ', style: TextStyle(color: _kSubtle, fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 5,
            children: assigned.map((s) {
              const rankColors = {
                'SP': Color(0xFF6A1B9A), 'ASP': Color(0xFF1565C0),
                'DSP': Color(0xFF1A5276), 'Inspector': Color(0xFF2E7D32),
                'SI': Color(0xFF558B2F), 'ASI': Color(0xFF8B6914),
                'Head Constable': Color(0xFFB8860B), 'Constable': Color(0xFF6D4C41),
              };
              final rank = s['rank'] as String? ?? '';
              final rc = rankColors[rank] ?? _kPrimary;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: _kBorder.withOpacity(0.4)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: rc, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 80),
                    child: Text(s['name'] as String? ?? '', style: const TextStyle(color: _kDark, fontSize: 11, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 4),
                  Text('($rank)', style: TextStyle(color: rc, fontSize: 9)),
                ]),
              );
            }).toList()),
        ],
      ]),
    );
  }
}

class _DetailGrid extends StatelessWidget {
  final Map<String, dynamic> duty;
  const _DetailGrid({required this.duty});

  @override
  Widget build(BuildContext context) {
    final rows = <_DRow>[];

    if ((duty['booth'] as String?)?.isNotEmpty == true)
      rows.add(_DRow('मतदान केंद्र', duty['booth'] as String, Icons.location_on_outlined, _kError));
    if ((duty['gramPanchayat'] as String?)?.isNotEmpty == true)
      rows.add(_DRow('ग्राम पंचायत', duty['gramPanchayat'] as String, Icons.account_balance_outlined, const Color(0xFF6D4C41)));
    if ((duty['sector'] as String?)?.isNotEmpty == true)
      rows.add(_DRow('सेक्टर', duty['sector'] as String, Icons.view_module_outlined, const Color(0xFF2E7D32)));
    if ((duty['zone'] as String?)?.isNotEmpty == true)
      rows.add(_DRow('जोन', duty['zone'] as String, Icons.grid_view_outlined, const Color(0xFF1565C0)));
    if ((duty['superZone'] as String?)?.isNotEmpty == true)
      rows.add(_DRow('सुपर जोन / क्षेत्र', duty['superZone'] as String, Icons.layers_outlined, const Color(0xFF6A1B9A)));
    if ((duty['busNo'] as String?)?.isNotEmpty == true)
      rows.add(_DRow('बस संख्या', duty['busNo'] as String, Icons.directions_bus_outlined, _kAccent));

    return Column(
      children: rows.map((r) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(color: r.color.withOpacity(0.1), borderRadius: BorderRadius.circular(7)),
            child: Icon(r.icon, size: 14, color: r.color),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.label, style: const TextStyle(color: _kSubtle, fontSize: 10)),
            Text(r.value, style: const TextStyle(color: _kDark, fontSize: 12, fontWeight: FontWeight.w700)),
          ])),
        ]),
      )).toList(),
    );
  }
}

class _DRow { final String label, value; final IconData icon; final Color color; _DRow(this.label, this.value, this.icon, this.color); }

// ── Error + empty views ───────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String error; final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});
  @override Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.error_outline, size: 48, color: _kError),
    const SizedBox(height: 12),
    const Text('डेटा लोड नहीं हो सका', style: TextStyle(color: _kDark, fontSize: 14, fontWeight: FontWeight.w700)),
    const SizedBox(height: 6),
    Text(error, style: const TextStyle(color: _kSubtle, fontSize: 12), textAlign: TextAlign.center),
    const SizedBox(height: 16),
    ElevatedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 16), label: const Text('दोबारा कोशिश'),
      style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
  ])));
}

class _EmptyView extends StatelessWidget {
  final String filter;
  const _EmptyView({required this.filter});
  @override Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(40), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.history_rounded, size: 56, color: _kSubtle.withOpacity(0.35)),
    const SizedBox(height: 14),
    Text(filter == 'All' ? 'कोई ड्यूटी रिकॉर्ड नहीं' : 'इस फ़िल्टर में कोई रिकॉर्ड नहीं', style: const TextStyle(color: _kSubtle, fontSize: 13), textAlign: TextAlign.center),
  ])));
}
