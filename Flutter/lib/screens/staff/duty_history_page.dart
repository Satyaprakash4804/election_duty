import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _kBg       = Color(0xFFFDF6E3);
const _kSurface  = Color(0xFFF5E6C8);
const _kPrimary  = Color(0xFF8B6914);
const _kAccent   = Color(0xFFB8860B);
const _kDark     = Color(0xFF4A3000);
const _kSubtle   = Color(0xFFAA8844);
const _kBorder   = Color(0xFFD4A843);
const _kError    = Color(0xFFC0392B);
const _kSuccess  = Color(0xFF2D6A1E);
const _kInfo     = Color(0xFF1A5276);
const _kDistrict = Color(0xFF4A148C);

// ══════════════════════════════════════════════════════════════════════════════
//  DUTY HISTORY PAGE
// ══════════════════════════════════════════════════════════════════════════════
class DutyHistoryPage extends StatefulWidget {
  const DutyHistoryPage({super.key});
  @override
  State<DutyHistoryPage> createState() => _DutyHistoryPageState();
}

class _DutyHistoryPageState extends State<DutyHistoryPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _duties = [];
  bool   _loading = true;
  String? _error;
  String  _filterStatus = 'All';

  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _load();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Data ─────────────────────────────────────────────────────────────────
  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    _fadeCtrl.reset();
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get('/staff/history', token: token);
      final raw   = res['data'];
      final list  = (raw is List) ? raw : <dynamic>[];
      if (!mounted) return;
      setState(() {
        _duties  = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
      _fadeCtrl.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  // ── Filtering ─────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filtered {
    switch (_filterStatus) {
      case 'Present':
        return _duties.where((d) =>
            d['dutyKind'] == 'booth' && d['present'] == true).toList();
      case 'Absent':
        return _duties.where((d) =>
            d['dutyKind'] == 'booth' && d['present'] == false).toList();
      case 'Upcoming':
        return _duties.where((d) =>
            d['date'] != null && _isUpcoming(d['date'] as String?)).toList();
      case 'District':
        return _duties.where((d) => d['dutyKind'] == 'district').toList();
      default:
        return _duties;
    }
  }

  bool _isUpcoming(String? dateStr) {
    if (dateStr == null) return false;
    try {
      return DateTime.parse(dateStr).isAfter(DateTime.now());
    } catch (_) { return false; }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'तारीख अज्ञात';
    try {
      final d = DateTime.parse(dateStr);
      const months = [
        '', 'जन', 'फर', 'मार्च', 'अप्रैल', 'मई', 'जून',
        'जुलाई', 'अग', 'सित', 'अक्ट', 'नव', 'दिस'
      ];
      return '${d.day} ${months[d.month]} ${d.year}';
    } catch (_) { return dateStr; }
  }

  // ── Stats ─────────────────────────────────────────────────────────────────
  int get _presentCount  => _duties.where(
      (d) => d['dutyKind'] == 'booth' && d['present'] == true).length;
  int get _absentCount   => _duties.where(
      (d) => d['dutyKind'] == 'booth' && d['present'] == false).length;
  int get _districtCount => _duties.where(
      (d) => d['dutyKind'] == 'district').length;

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [_buildSliverAppBar()],
        body: Column(children: [
          _buildFilterBar(),
          if (!_loading && _error == null) _buildSummaryStrip(),
          Expanded(child: _buildBody()),
        ]),
      ),
    );
  }

  Widget _buildSliverAppBar() => SliverAppBar(
    expandedHeight: 110,
    floating: false,
    pinned: true,
    backgroundColor: _kDark,
    elevation: 0,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
      onPressed: () => Navigator.pop(context),
    ),
    actions: [
      IconButton(
        icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
        onPressed: _load,
        tooltip: 'ताज़ा करें',
      ),
    ],
    flexibleSpace: FlexibleSpaceBar(
      titlePadding: const EdgeInsets.fromLTRB(56, 0, 48, 14),
      title: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ड्यूटी इतिहास',
              style: TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800,
                  letterSpacing: 0.3)),
          Text('Duty History',
              style: TextStyle(
                  color: Colors.white54, fontSize: 9, fontWeight: FontWeight.w400)),
        ],
      ),
      background: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF6B4A00), _kDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Opacity(
          opacity: 0.05,
          child: GridView.count(
            crossAxisCount: 8,
            physics: const NeverScrollableScrollPhysics(),
            children: List.generate(64, (_) =>
              const Icon(Icons.shield_outlined, color: Colors.white, size: 20)),
          ),
        ),
      ),
    ),
  );

  Widget _buildFilterBar() => Container(
    color: _kSurface,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final f in ['All', 'Upcoming', 'Present', 'Absent', 'District'])
          _filterChip(f),
      ]),
    ),
  );

  Widget _filterChip(String label) {
    final isSel = _filterStatus == label;
    final (color, hindi) = switch (label) {
      'Present'  => (_kSuccess,  '✅ उपस्थित'),
      'Absent'   => (_kError,    '❌ अनुपस्थित'),
      'Upcoming' => (_kInfo,     '🗓 आगामी'),
      'District' => (_kDistrict, '🛡 जनपदीय'),
      _          => (_kPrimary,  'सभी'),
    };

    return GestureDetector(
      onTap: () => setState(() => _filterStatus = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSel ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSel ? color : _kBorder.withOpacity(0.4)),
          boxShadow: isSel
              ? [BoxShadow(color: color.withOpacity(0.25),
                           blurRadius: 6, offset: const Offset(0, 2))]
              : [],
        ),
        child: Text(hindi,
          style: TextStyle(
            color: isSel ? Colors.white : _kDark,
            fontSize: 11.5,
            fontWeight: isSel ? FontWeight.w800 : FontWeight.w500)),
      ),
    );
  }

  Widget _buildSummaryStrip() {
    final booth    = _duties.where((d) => d['dutyKind'] == 'booth').length;
    final district = _districtCount;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder.withOpacity(0.25)),
        boxShadow: [BoxShadow(
            color: _kPrimary.withOpacity(0.06),
            blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(children: [
        _statCell('कुल', '${_duties.length}',   _kPrimary),
        _statDivider(),
        _statCell('बूथ',     '$booth',           _kAccent),
        _statDivider(),
        _statCell('उपस्थित', '$_presentCount',   _kSuccess),
        _statDivider(),
        _statCell('अनुपस्थित','$_absentCount',   _kError),
        _statDivider(),
        _statCell('जनपदीय',  '$district',        _kDistrict),
      ]),
    );
  }

  Widget _statCell(String label, String val, Color color) => Expanded(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(val,
          style: TextStyle(
              color: color, fontSize: 18,
              fontWeight: FontWeight.w900, height: 1.1)),
      const SizedBox(height: 2),
      Text(label,
          style: const TextStyle(
              color: _kSubtle, fontSize: 9.5, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _statDivider() => Container(
      height: 32, width: 1, color: _kBorder.withOpacity(0.3));

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(
            color: _kPrimary,
            strokeWidth: 2.5,
            backgroundColor: _kPrimary.withOpacity(0.1),
          ),
          const SizedBox(height: 14),
          const Text('लोड हो रहा है…',
              style: TextStyle(color: _kSubtle, fontSize: 13)),
        ]),
      );
    }
    if (_error != null) {
      return _ErrorView(error: _error!, onRetry: _load);
    }
    if (_filtered.isEmpty) {
      return _EmptyView(filter: _filterStatus);
    }
    return FadeTransition(
      opacity: _fadeAnim,
      child: RefreshIndicator(
        onRefresh: _load,
        color: _kPrimary,
        backgroundColor: Colors.white,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 40),
          itemCount: _filtered.length,
          itemBuilder: (_, i) {
            final duty = _filtered[i];
            return duty['dutyKind'] == 'district'
                ? _DistrictDutyCard(
                    duty: duty,
                    dateFormatter: _formatDate,
                    isUpcoming: _isUpcoming(duty['date'] as String?),
                  )
                : _BoothDutyCard(
                    duty: duty,
                    dateFormatter: _formatDate,
                    isUpcoming: _isUpcoming(duty['date'] as String?),
                  );
          },
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  BOOTH DUTY CARD
// ══════════════════════════════════════════════════════════════════════════════
class _BoothDutyCard extends StatefulWidget {
  final Map<String, dynamic> duty;
  final String Function(String?) dateFormatter;
  final bool isUpcoming;
  const _BoothDutyCard({
    required this.duty,
    required this.dateFormatter,
    required this.isUpcoming,
  });
  @override State<_BoothDutyCard> createState() => _BoothDutyCardState();
}

class _BoothDutyCardState extends State<_BoothDutyCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final d         = widget.duty;
    final isPresent = d['present'] as bool? ?? false;
    final hasDate   = d['date'] != null;
    final dateStr   = widget.dateFormatter(d['date'] as String?);

    final (statusColor, statusIcon, statusText) = switch (true) {
      _ when widget.isUpcoming => (_kInfo,    Icons.schedule_rounded,      'आगामी'),
      _ when !hasDate          => (_kSubtle,  Icons.help_outline_rounded,  'अज्ञात'),
      _ when isPresent         => (_kSuccess, Icons.check_circle_rounded,  'उपस्थित'),
      _                        => (_kError,   Icons.cancel_rounded,        'अनुपस्थित'),
    };

    return _CardShell(
      statusColor: statusColor,
      child: Column(children: [
        // ── Header ──────────────────────────────────────────────────────────
        _CardHeader(
          statusColor: statusColor,
          statusIcon: statusIcon,
          statusText: statusText,
          title: d['booth'] as String? ?? 'बूथ अज्ञात',
          dateStr: dateStr,
          expanded: _expanded,
          onTap: () => setState(() => _expanded = !_expanded),
          trailing: null,
        ),

        // ── Hierarchy breadcrumb ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: _HierarchyRow(duty: d),
        ),

        // ── Expanded detail ──────────────────────────────────────────────────
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: _BoothExpandedDetail(duty: d),
          crossFadeState:
              _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 220),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DISTRICT DUTY CARD
// ══════════════════════════════════════════════════════════════════════════════
class _DistrictDutyCard extends StatefulWidget {
  final Map<String, dynamic> duty;
  final String Function(String?) dateFormatter;
  final bool isUpcoming;
  const _DistrictDutyCard({
    required this.duty,
    required this.dateFormatter,
    required this.isUpcoming,
  });
  @override State<_DistrictDutyCard> createState() => _DistrictDutyCardState();
}

class _DistrictDutyCardState extends State<_DistrictDutyCard> {
  bool _expanded = false;

  // Hindi label map (mirrors backend)
  static const _labels = {
    'cluster_mobile':        'क्लस्टर मोबाईल',
    'thana_mobile':          'थाना मोबाईल',
    'thana_reserve':         'थाना रिजर्व',
    'thana_extra_mobile':    'थाना अतिरिक्त मोबाईल',
    'sector_pol_mag_mobile': 'सैक्टर पुलिस/मजिस्ट्रेट मोबाईल',
    'zonal_pol_mag_mobile':  'जोनल पुलिस/मजिस्ट्रेट मोबाईल',
    'sdm_co_mobile':         'एसडीएम/सीओ मोबाईल',
    'chowki_mobile':         'चौकी मोबाईल',
    'barrier_picket':        'बैरियर/पिकैट',
    'evm_security':          'ईवीएम सुरक्षा',
    'adm_sp_mobile':         'एडीएम/एसपी मोबाईल',
    'dm_sp_mobile':          'डीएम/एसपी मोबाईल',
    'observer_security':     'पर्यवेक्षक सुरक्षा',
    'hq_reserve':            'मुख्यालय रिजर्व',
  };

  static String _dutyLabel(String key) =>
      _labels[key] ?? key.replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    final d       = widget.duty;
    final dateStr = widget.dateFormatter(d['date'] as String?);
    final title   = _dutyLabel(d['dutyType'] as String? ?? '');

    return _CardShell(
      statusColor: _kDistrict,
      child: Column(children: [
        // ── Header ──────────────────────────────────────────────────────────
        _CardHeader(
          statusColor: _kDistrict,
          statusIcon: Icons.shield_outlined,
          statusText: 'जनपदीय',
          title: title,
          dateStr: dateStr,
          expanded: _expanded,
          onTap: () => setState(() => _expanded = !_expanded),
          trailing: _BatchBadge(batchNo: d['batchNo']),
        ),

        // ── Location chips ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: _DistrictChips(duty: d),
        ),

        // ── Expanded detail ──────────────────────────────────────────────────
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: _DistrictExpandedDetail(
              duty: d, dutyLabel: _dutyLabel),
          crossFadeState:
              _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 220),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SHARED CARD SHELL
// ══════════════════════════════════════════════════════════════════════════════
class _CardShell extends StatelessWidget {
  final Color statusColor;
  final Widget child;
  const _CardShell({required this.statusColor, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: statusColor.withOpacity(0.22), width: 1.5),
      boxShadow: [
        BoxShadow(
            color: statusColor.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 3)),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: child,
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  SHARED CARD HEADER
// ══════════════════════════════════════════════════════════════════════════════
class _CardHeader extends StatelessWidget {
  final Color statusColor;
  final IconData statusIcon;
  final String statusText;
  final String title;
  final String dateStr;
  final bool expanded;
  final VoidCallback onTap;
  final Widget? trailing;

  const _CardHeader({
    required this.statusColor,
    required this.statusIcon,
    required this.statusText,
    required this.title,
    required this.dateStr,
    required this.expanded,
    required this.onTap,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
      child: Row(children: [
        // Status circle
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              statusColor.withOpacity(0.18),
              statusColor.withOpacity(0.06),
            ]),
            border: Border.all(color: statusColor.withOpacity(0.4), width: 1.5),
          ),
          child: Icon(statusIcon, color: statusColor, size: 22),
        ),
        const SizedBox(width: 12),

        // Labels
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 5, runSpacing: 3,
              children: [
                _StatusBadge(label: statusText, color: statusColor),
                if (trailing != null) trailing!,
                _DateBadge(dateStr: dateStr),
              ],
            ),
            const SizedBox(height: 5),
            Text(title,
                style: const TextStyle(
                    color: _kDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 0.1),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        )),

        // Expand arrow
        AnimatedRotation(
          turns: expanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 220),
          child: Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.keyboard_arrow_down_rounded,
                color: statusColor, size: 20),
          ),
        ),
      ]),
    ),
  );
}

// ── Small reusable badges ─────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String label; final Color color;
  const _StatusBadge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(label,
        style: TextStyle(
            color: color, fontSize: 10, fontWeight: FontWeight.w800)),
  );
}

class _DateBadge extends StatelessWidget {
  final String dateStr;
  const _DateBadge({required this.dateStr});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.calendar_today_outlined, size: 10, color: _kSubtle),
    const SizedBox(width: 3),
    Text(dateStr,
        style: const TextStyle(color: _kSubtle, fontSize: 10.5)),
  ]);
}

class _BatchBadge extends StatelessWidget {
  final dynamic batchNo;
  const _BatchBadge({required this.batchNo});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
    decoration: BoxDecoration(
      color: _kDistrict.withOpacity(0.08),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: _kDistrict.withOpacity(0.25)),
    ),
    child: Text('बैच ${batchNo ?? '—'}',
        style: const TextStyle(
            color: _kDistrict, fontSize: 10, fontWeight: FontWeight.w700)),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  DISTRICT LOCATION CHIPS
// ══════════════════════════════════════════════════════════════════════════════
class _DistrictChips extends StatelessWidget {
  final Map<String, dynamic> duty;
  const _DistrictChips({required this.duty});

  Widget _chip(IconData icon, String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.07),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: color.withOpacity(0.22)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: color),
      const SizedBox(width: 4),
      Text(text,
          style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w600)),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if ((duty['district'] as String?)?.isNotEmpty == true)
      chips.add(_chip(Icons.location_city_outlined, duty['district'] as String, _kDistrict));
    if ((duty['busNo'] as String?)?.isNotEmpty == true)
      chips.add(_chip(Icons.directions_bus_outlined, 'बस: ${duty['busNo']}', _kAccent));
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 5, children: chips);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  BOOTH EXPANDED DETAIL
// ══════════════════════════════════════════════════════════════════════════════
class _BoothExpandedDetail extends StatelessWidget {
  final Map<String, dynamic> duty;
  const _BoothExpandedDetail({required this.duty});

  @override
  Widget build(BuildContext context) {
    final assigned = (duty['assignedStaff'] as List?)?.cast<Map>() ?? [];

    return _ExpandedContainer(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailRow(Icons.location_on_outlined,     'मतदान केंद्र',
            duty['booth'] as String? ?? '—',         _kError),
        if ((duty['gramPanchayat'] as String?)?.isNotEmpty == true)
          _DetailRow(Icons.account_balance_outlined, 'ग्राम पंचायत',
              duty['gramPanchayat'] as String,        const Color(0xFF6D4C41)),
        if ((duty['sector'] as String?)?.isNotEmpty == true)
          _DetailRow(Icons.view_module_outlined,     'सेक्टर',
              duty['sector'] as String,               const Color(0xFF2E7D32)),
        if ((duty['zone'] as String?)?.isNotEmpty == true)
          _DetailRow(Icons.grid_view_outlined,        'जोन',
              duty['zone'] as String,                 const Color(0xFF1565C0)),
        if ((duty['superZone'] as String?)?.isNotEmpty == true)
          _DetailRow(Icons.layers_outlined,           'सुपर जोन',
              duty['superZone'] as String,            const Color(0xFF6A1B9A)),
        if ((duty['busNo'] as String?)?.isNotEmpty == true)
          _DetailRow(Icons.directions_bus_outlined,   'बस संख्या',
              duty['busNo'] as String,                _kAccent),
        if ((duty['address'] as String?)?.isNotEmpty == true)
          _DetailRow(Icons.place_outlined,            'पता',
              duty['address'] as String,              _kSubtle),

        if (assigned.isNotEmpty) ...[
          const _StaffDivider(label: 'इस बूथ पर तैनात सभी स्टाफ'),
          _StaffChips(staffList: assigned, rankKey: 'rank'),
        ],
      ],
    ));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DISTRICT EXPANDED DETAIL
// ══════════════════════════════════════════════════════════════════════════════
class _DistrictExpandedDetail extends StatelessWidget {
  final Map<String, dynamic> duty;
  final String Function(String) dutyLabel;
  const _DistrictExpandedDetail({required this.duty, required this.dutyLabel});

  @override
  Widget build(BuildContext context) {
    final staff = (duty['batchStaff'] as List?)?.cast<Map>() ?? [];

    return _ExpandedContainer(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailRow(Icons.shield_outlined,              'ड्यूटी प्रकार',
            dutyLabel(duty['dutyType'] as String? ?? ''), _kDistrict),
        _DetailRow(Icons.confirmation_number_outlined, 'बैच संख्या',
            'बैच ${duty['batchNo'] ?? '—'}',              _kPrimary),
        if ((duty['district'] as String?)?.isNotEmpty == true)
          _DetailRow(Icons.location_city_outlined,     'जनपद',
              duty['district'] as String,               _kInfo),
        if ((duty['busNo'] as String?)?.isNotEmpty == true)
          _DetailRow(Icons.directions_bus_outlined,    'बस संख्या',
              duty['busNo'] as String,                  _kAccent),
        if ((duty['note'] as String?)?.isNotEmpty == true)
          _DetailRow(Icons.notes_outlined,             'विशेष नोट',
              duty['note'] as String,                   _kSubtle),

        if (staff.isNotEmpty) ...[
          const _StaffDivider(label: 'बैच के सहयोगी कर्मी'),
          _StaffChips(staffList: staff, rankKey: 'rank'),
        ],
      ],
    ));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SHARED EXPANDED CONTAINER
// ══════════════════════════════════════════════════════════════════════════════
class _ExpandedContainer extends StatelessWidget {
  final Widget child;
  const _ExpandedContainer({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _kBg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _kBorder.withOpacity(0.3)),
    ),
    child: child,
  );
}

// ── Detail row (icon + label + value) ────────────────────────────────────────
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _DetailRow(this.icon, this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 15, color: color),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: _kSubtle, fontSize: 9.5)),
          Text(value,
              style: const TextStyle(
                  color: _kDark, fontSize: 12.5,
                  fontWeight: FontWeight.w700)),
        ],
      )),
    ]),
  );
}

// ── Staff section divider ─────────────────────────────────────────────────────
class _StaffDivider extends StatelessWidget {
  final String label;
  const _StaffDivider({required this.label});
  @override
  Widget build(BuildContext context) => Column(children: [
    const SizedBox(height: 8),
    const Divider(height: 1, color: _kBorder),
    const SizedBox(height: 10),
    Row(children: [
      const Icon(Icons.people_outline, size: 13, color: _kSubtle),
      const SizedBox(width: 5),
      Text(label,
          style: const TextStyle(
              color: _kSubtle, fontSize: 11, fontWeight: FontWeight.w700)),
    ]),
    const SizedBox(height: 8),
  ]);
}

// ── Staff chips ───────────────────────────────────────────────────────────────
class _StaffChips extends StatelessWidget {
  final List<Map> staffList;
  final String rankKey; // 'rank' for booth; 'rank' same for district
  const _StaffChips({required this.staffList, required this.rankKey});

  static const _rankColors = {
    'SP':             Color(0xFF6A1B9A),
    'ASP':            Color(0xFF1565C0),
    'DSP':            Color(0xFF1A5276),
    'Inspector':      Color(0xFF2E7D32),
    'SI':             Color(0xFF558B2F),
    'ASI':            Color(0xFF8B6914),
    'Head Constable': Color(0xFFB8860B),
    'Constable':      Color(0xFF6D4C41),
  };

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6, runSpacing: 5,
    children: staffList.map((s) {
      final rank = s[rankKey] as String? ?? '';
      final rc   = _rankColors[rank] ?? _kPrimary;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kBorder.withOpacity(0.4)),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 3, offset: const Offset(0, 1))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7,
              decoration: BoxDecoration(color: rc, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 85),
            child: Text(s['name'] as String? ?? '',
                style: const TextStyle(
                    color: _kDark, fontSize: 11.5, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if ((s['pno'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(width: 4),
            Text('(${s['pno']})',
                style: TextStyle(color: rc, fontSize: 9.5, fontWeight: FontWeight.w500)),
          ],
        ]),
      );
    }).toList(),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  HIERARCHY ROW  — Super Zone → Zone → Sector → GP
// ══════════════════════════════════════════════════════════════════════════════
class _HierarchyRow extends StatelessWidget {
  final Map<String, dynamic> duty;
  const _HierarchyRow({required this.duty});

  @override
  Widget build(BuildContext context) {
    final items = <({String label, IconData icon, Color color})>[];

    if ((duty['superZone'] as String?)?.isNotEmpty == true)
      items.add((label: duty['superZone'] as String,
          icon: Icons.layers_outlined,         color: const Color(0xFF6A1B9A)));
    if ((duty['zone'] as String?)?.isNotEmpty == true)
      items.add((label: duty['zone'] as String,
          icon: Icons.grid_view_outlined,       color: const Color(0xFF1565C0)));
    if ((duty['sector'] as String?)?.isNotEmpty == true)
      items.add((label: duty['sector'] as String,
          icon: Icons.view_module_outlined,     color: const Color(0xFF2E7D32)));
    if ((duty['gramPanchayat'] as String?)?.isNotEmpty == true)
      items.add((label: duty['gramPanchayat'] as String,
          icon: Icons.account_balance_outlined, color: const Color(0xFF6D4C41)));

    if (items.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 2),
              child: Icon(Icons.chevron_right, size: 12, color: _kSubtle),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: items[i].color.withOpacity(0.07),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: items[i].color.withOpacity(0.2)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(items[i].icon, size: 10, color: items[i].color),
              const SizedBox(width: 3),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 90),
                child: Text(items[i].label,
                    style: TextStyle(
                        color: items[i].color,
                        fontSize: 10, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  ERROR + EMPTY VIEWS
// ══════════════════════════════════════════════════════════════════════════════
class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: _kError.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.error_outline, size: 36, color: _kError),
        ),
        const SizedBox(height: 16),
        const Text('डेटा लोड नहीं हो सका',
            style: TextStyle(
                color: _kDark, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(error,
            style: const TextStyle(color: _kSubtle, fontSize: 12),
            textAlign: TextAlign.center),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('दोबारा कोशिश करें'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _kPrimary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ]),
    ),
  );
}

class _EmptyView extends StatelessWidget {
  final String filter;
  const _EmptyView({required this.filter});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: _kSubtle.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.history_rounded,
              size: 40, color: _kSubtle.withOpacity(0.4)),
        ),
        const SizedBox(height: 16),
        Text(
          filter == 'All'
              ? 'कोई ड्यूटी रिकॉर्ड नहीं मिला'
              : 'इस फ़िल्टर में कोई रिकॉर्ड नहीं',
          style: const TextStyle(
              color: _kSubtle, fontSize: 14, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text('ऊपर अन्य फ़िल्टर आज़माएं',
            style: TextStyle(color: _kSubtle, fontSize: 12)),
      ]),
    ),
  );
}