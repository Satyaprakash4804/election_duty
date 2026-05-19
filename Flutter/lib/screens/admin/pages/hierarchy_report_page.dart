import 'dart:async';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _kBg      = Color(0xFFFAFAFA);
const _kPrimary = Color(0xFF0F2B5B);
const _kGreen   = Color(0xFF186A3B);
const _kPurple  = Color(0xFF6C3483);
const _kRed     = Color(0xFFC0392B);
const _kDark    = Color(0xFF1A2332);
const _kSubtle  = Color(0xFF6B7C93);
const _kBorder  = Color(0xFFDDE3EE);
const _kAccent  = Color(0xFFFBBF24);
const _kGold    = Color(0xFFFFF8E7);
const _kOrange  = Color(0xFFE67E22);
const _kAmber   = Color(0xFFFFF3CD);
const _kAmberDark = Color(0xFF856404);

Color _sensitivityColor(String? t) {
  switch (t) {
    case 'A++': return const Color(0xFF6C3483);
    case 'A':   return _kRed;
    case 'B':   return _kOrange;
    default:    return const Color(0xFF1A5276);
  }
}

BoxDecoration _cellDec({bool right = true, bool bottom = true, Color? bg}) =>
    BoxDecoration(
      color: bg,
      border: Border(
        right:  right  ? const BorderSide(color: _kBorder) : BorderSide.none,
        bottom: bottom ? const BorderSide(color: _kBorder) : BorderSide.none,
      ),
    );

const _kRanks = [
  {'en': 'SP',             'hi': 'पुलिस अधीक्षक'},
  {'en': 'ASP',            'hi': 'सह0 पुलिस अधीक्षक'},
  {'en': 'DSP',            'hi': 'पुलिस उपाधीक्षक'},
  {'en': 'Inspector',      'hi': 'निरीक्षक'},
  {'en': 'SI',             'hi': 'उप निरीक्षक'},
  {'en': 'ASI',            'hi': 'सह0 उप निरीक्षक'},
  {'en': 'Head Constable', 'hi': 'मुख्य आरक्षी'},
  {'en': 'Constable',      'hi': 'आरक्षी'},
];

const _kCenterTypes = ['A++', 'A', 'B', 'C'];

// ── Pagination constants ──────────────────────────────────────────────────────
const _kPageSize = 20;

// ══════════════════════════════════════════════════════════════════════════════
// ELECTION SELECTOR PAGE  — shown before HierarchyReportPage
// Admin/super_admin: district is locked (backend), directly see election picker.
// Master: first picks district, then election.
// ══════════════════════════════════════════════════════════════════════════════
class HierarchyElectionSelectorPage extends StatefulWidget {
  final String role;
  final String? districtHint; // pre-set for admin/super_admin
  const HierarchyElectionSelectorPage({
    super.key,
    required this.role,
    this.districtHint,
  });
  @override
  State<HierarchyElectionSelectorPage> createState() =>
      _HierarchyElectionSelectorPageState();
}

class _HierarchyElectionSelectorPageState
    extends State<HierarchyElectionSelectorPage> {
  // Districts (master only)
  List<String> _districts = [];
  String? _selectedDistrict;

  // Elections
  List<Map> _elections = [];
  String? _selectedElectionId;
  bool _loadingDistricts = false;
  bool _loadingElections = false;
  String? _error;

  bool get _isMaster => widget.role.toLowerCase() == 'master';

  @override
  void initState() {
    super.initState();
    if (_isMaster) {
      _loadDistricts();
    } else {
      // admin / super_admin district locked by backend
      _selectedDistrict = widget.districtHint ?? '';
      _loadElections();
    }
  }

  Future<void> _loadDistricts() async {
    setState(() { _loadingDistricts = true; _error = null; });
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get('/admin/hierarchy/districts', token: token);
      final list  = res['data'] as List? ?? [];
      setState(() {
        _districts = list.map((e) => '$e').toList();
        _loadingDistricts = false;
      });
    } catch (e) {
      setState(() { _loadingDistricts = false; _error = e.toString(); });
    }
  }

  Future<void> _loadElections({String? district}) async {
    setState(() { _loadingElections = true; _error = null; _elections = []; _selectedElectionId = null; });
    try {
      final token = await AuthService.getToken();
      final d = district ?? _selectedDistrict ?? '';
      final ep = d.isNotEmpty
          ? '/admin/elections?district=${Uri.encodeComponent(d)}'
          : '/admin/elections';
      final res  = await ApiService.get(ep, token: token);
      final list = (res['data'] as List? ?? res as List? ?? []);
      setState(() {
        _elections = List<Map>.from(list);
        _loadingElections = false;
        // Auto-select current/active if only one
        if (_elections.length == 1) {
          _selectedElectionId = '${_elections.first['id']}';
        }
      });
    } catch (e) {
      setState(() { _loadingElections = false; _error = e.toString(); });
    }
  }

  void _proceed() {
    if (_selectedElectionId == null) return;
    final elec = _elections.firstWhere(
      (e) => '${e['id']}' == _selectedElectionId,
      orElse: () => {},
    );
    final isActive = elec['is_active'] == true || elec['isActive'] == true ||
        (elec['status'] ?? '').toString().toLowerCase() == 'active';

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HierarchyReportPage(
          role:       widget.role,
          district:   _selectedDistrict,
          electionId: int.tryParse(_selectedElectionId!),
          electionName: '${elec['name'] ?? elec['election_name'] ?? 'चुनाव'}',
          isHistory:  !isActive,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPrimary, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('प्रशासनिक पदानुक्रम',
                style: TextStyle(color: Colors.white,
                    fontSize: 15, fontWeight: FontWeight.w800)),
            Text('चुनाव चुनें',
                style: TextStyle(color: Colors.white54, fontSize: 10)),
          ],
        ),
      ),
      body: _loadingDistricts
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header illustration
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F2B5B), Color(0xFF1E3F80)],
                            begin: Alignment.topLeft, end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Column(children: [
                          Icon(Icons.how_to_vote_outlined,
                              size: 48, color: Colors.white70),
                          SizedBox(height: 10),
                          Text('पदानुक्रम रिपोर्ट',
                              style: TextStyle(color: Colors.white,
                                  fontSize: 18, fontWeight: FontWeight.w800)),
                          SizedBox(height: 4),
                          Text('चुनाव का चयन करके रिपोर्ट देखें',
                              style: TextStyle(
                                  color: Colors.white60, fontSize: 12)),
                        ]),
                      ),
                      const SizedBox(height: 24),

                      if (_error != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _kRed.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _kRed.withOpacity(0.3)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.error_outline,
                                color: _kRed, size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error!,
                                style: const TextStyle(
                                    color: _kRed, fontSize: 12))),
                          ]),
                        ),

                      // District selector (master only)
                      if (_isMaster) ...[
                        _SectionCard(
                          title: 'जनपद चुनें',
                          icon: Icons.location_city_outlined,
                          color: _kPrimary,
                          child: _loadingDistricts
                              ? const Center(child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: _kPrimary)))
                              : _DropCard<String>(
                                  value: _selectedDistrict,
                                  hint: 'जनपद चुनें',
                                  items: _districts
                                      .map((d) => DropdownMenuItem(
                                            value: d,
                                            child: Text(d, overflow: TextOverflow.ellipsis)))
                                      .toList(),
                                  onChanged: (v) {
                                    setState(() {
                                      _selectedDistrict = v;
                                      _elections = [];
                                      _selectedElectionId = null;
                                    });
                                    if (v != null) _loadElections(district: v);
                                  },
                                ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Election selector
                      _SectionCard(
                        title: 'चुनाव चुनें',
                        icon: Icons.ballot_outlined,
                        color: _kGreen,
                        child: _loadingElections
                            ? const Center(child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: _kGreen)))
                            : _elections.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(
                                      _isMaster && _selectedDistrict == null
                                          ? 'पहले जनपद चुनें'
                                          : 'कोई चुनाव उपलब्ध नहीं',
                                      style: const TextStyle(
                                          color: _kSubtle, fontSize: 13),
                                      textAlign: TextAlign.center,
                                    ),
                                  )
                                : Column(
                                    children: _elections.map((e) {
                                      final id = '${e['id']}';
                                      final name = '${e['name'] ?? e['election_name'] ?? 'चुनाव'}';
                                      final isActive = e['is_active'] == true ||
                                          e['isActive'] == true ||
                                          (e['status'] ?? '').toString().toLowerCase() == 'active';
                                      final selected = _selectedElectionId == id;
                                      return _ElectionTile(
                                        name: name,
                                        isActive: isActive,
                                        selected: selected,
                                        election: e,
                                        onTap: () => setState(() => _selectedElectionId = id),
                                      );
                                    }).toList(),
                                  ),
                      ),

                      const SizedBox(height: 24),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _selectedElectionId != null
                                ? _kPrimary : Colors.grey[300],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: _selectedElectionId != null ? 2 : 0,
                          ),
                          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                          label: const Text('रिपोर्ट देखें',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                          onPressed: _selectedElectionId != null ? _proceed : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _ElectionTile extends StatelessWidget {
  final String name;
  final bool isActive, selected;
  final Map election;
  final VoidCallback onTap;
  const _ElectionTile({
    required this.name, required this.isActive,
    required this.selected, required this.election, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final startDate = election['start_date'] ?? election['startDate'] ?? '';
    final endDate   = election['end_date']   ?? election['endDate']   ?? '';
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? (isActive ? _kGreen : _kPrimary).withOpacity(0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? (isActive ? _kGreen : _kPrimary)
                : _kBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 22, height: 22,
            decoration: BoxDecoration(
              color: selected
                  ? (isActive ? _kGreen : _kPrimary)
                  : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? (isActive ? _kGreen : _kPrimary)
                    : _kBorder,
                width: 2,
              ),
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white, size: 13)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(
              fontWeight: FontWeight.w700, fontSize: 14,
              color: selected
                  ? (isActive ? _kGreen : _kPrimary) : _kDark,
            )),
            if (startDate.toString().isNotEmpty || endDate.toString().isNotEmpty)
              Text('$startDate${endDate.toString().isNotEmpty ? ' – $endDate' : ''}',
                  style: const TextStyle(color: _kSubtle, fontSize: 11)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isActive
                  ? _kGreen.withOpacity(0.12)
                  : _kSubtle.withOpacity(0.10),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isActive ? 'वर्तमान' : 'इतिहास',
              style: TextStyle(
                color: isActive ? _kGreen : _kSubtle,
                fontSize: 10, fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget child;
  const _SectionCard({
    required this.title, required this.icon,
    required this.color, required this.child,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _kBorder),
      boxShadow: [BoxShadow(
        color: color.withOpacity(0.07),
        blurRadius: 8, offset: const Offset(0, 3))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          border: Border(bottom: BorderSide(color: color.withOpacity(0.15))),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(color: color,
              fontWeight: FontWeight.w800, fontSize: 13)),
        ]),
      ),
      Padding(padding: const EdgeInsets.all(12), child: child),
    ]),
  );
}

class _DropCard<T> extends StatelessWidget {
  final T? value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  const _DropCard({required this.value, required this.hint,
      required this.items, required this.onChanged});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
          color: value != null ? _kPrimary : _kBorder, width: 1.5),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value, isExpanded: true, isDense: false,
        hint: Text(hint, style: const TextStyle(color: _kSubtle, fontSize: 13)),
        style: const TextStyle(color: _kDark, fontSize: 13),
        dropdownColor: Colors.white,
        items: items,
        onChanged: onChanged,
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// MAIN HIERARCHY REPORT PAGE
// ══════════════════════════════════════════════════════════════════════════════
class HierarchyReportPage extends StatefulWidget {
  final String role;
  final String? district;
  // NEW: election context
  final int?    electionId;
  final String? electionName;
  final bool    isHistory;

  const HierarchyReportPage({
    super.key,
    required this.role,
    this.district,
    this.electionId,
    this.electionName,
    this.isHistory = false,
  });
  @override
  State<HierarchyReportPage> createState() => _HierarchyReportPageState();
}

class _HierarchyReportPageState extends State<HierarchyReportPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List _data = [];
  bool _loading = true;
  String? _error;

  // Filters
  String? _fSZ, _fZone, _fSector, _fGP;

  // Pagination for Tab 3
  int _tab3Page = 1;
  static const _tab3PageSize = _kPageSize;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(() {
      if (!_tab.indexIsChanging) return;
      setState(() {
        _fSZ = _fZone = _fSector = _fGP = null;
        _tab3Page = 1;
      });
    });
    _load();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  // ── Build endpoint with optional electionId ─────────────────────────────
  String _buildEndpoint() {
    final isMaster = widget.role.toLowerCase() == 'master';
    final d = (widget.district ?? '').trim();
    final params = <String>[];
    if (isMaster && d.isNotEmpty) params.add('district=${Uri.encodeComponent(d)}');
    if (widget.isHistory && widget.electionId != null) {
      params.add('electionId=${widget.electionId}');
    }
    final q = params.isNotEmpty ? '?${params.join('&')}' : '';
    return '/admin/hierarchy/full$q';
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.get(_buildEndpoint(), token: token);
      setState(() {
        _data = (res is List ? res : (res['data'] as List? ?? []));
        _loading = false;
        _tab3Page = 1;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  // ── Filtered lists ────────────────────────────────────────────────────────
  List get _szList => _data;

  List get _filteredSZ => _fSZ == null
      ? _data
      : _data.where((s) => '${s['id']}' == _fSZ).toList();

  List get _allZones =>
      _filteredSZ.expand((s) => (s['zones'] as List? ?? [])).toList();

  List get _filteredZones => _fZone == null
      ? _allZones
      : _allZones.where((z) => '${z['id']}' == _fZone).toList();

  List get _allSectors =>
      _allZones.expand((z) => (z['sectors'] as List? ?? [])).toList();

  List get _filteredSectors => _fSector == null
      ? _allSectors
      : _allSectors.where((s) => '${s['id']}' == _fSector).toList();

  List get _allGPs =>
      _allSectors.expand((s) => (s['panchayats'] as List? ?? [])).toList();

  List<Map> get _allTab3Items {
    final items = <Map>[];
    for (final sz in _filteredSZ) {
      for (final z in (sz['zones'] as List? ?? [])) {
        if (_fZone != null && '${z['id']}' != _fZone) continue;
        for (final s in (z['sectors'] as List? ?? [])) {
          if (_fSector != null && '${s['id']}' != _fSector) continue;
          for (final gp in (s['panchayats'] as List? ?? [])) {
            if (_fGP != null && '${gp['id']}' != _fGP) continue;
            items.add({'sz': sz, 'z': z, 's': s, 'gp': gp});
          }
        }
      }
    }
    return items;
  }

  List<Map> get _pagedTab3Items {
    final all = _allTab3Items;
    final start = (_tab3Page - 1) * _tab3PageSize;
    final end = (start + _tab3PageSize).clamp(0, all.length);
    if (start >= all.length) return [];
    return all.sublist(start, end);
  }

  int get _tab3TotalPages =>
      ((_allTab3Items.length + _tab3PageSize - 1) / _tab3PageSize)
          .ceil().clamp(1, 9999);

  // ── CRUD helpers ─────────────────────────────────────────────────────────
  // CRUD operations are disabled in history mode
  bool get _canEdit => !widget.isHistory;

  Future<void> _delete(String ep, int id, String name) async {
    if (!_canEdit) { _snack('इतिहास मोड में संपादन अक्षम है', _kOrange); return; }
    final ok = await _confirm('हटाएं', '"$name" को हटाना चाहते हैं?');
    if (ok != true) return;
    try {
      final token = await AuthService.getToken();
      await ApiService.delete('$ep/$id', token: token);
      _load();
      _snack('सफलतापूर्वक हटाया गया', _kGreen);
    } catch (e) { _snack('त्रुटि: $e', _kRed); }
  }

  Future<bool?> _confirm(String title, String msg) => showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('रद्द')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _kRed),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('हटाएं', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PRINT — includes election name in header
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _print() async {
    final font = await PdfGoogleFonts.notoSansDevanagariRegular();
    final bold = await PdfGoogleFonts.notoSansDevanagariBold();
    final doc  = pw.Document();
    final idx  = _tab.index;

    // Election header string for PDF
    final elecHeader = widget.electionName != null
        ? 'चुनाव: ${widget.electionName}'
        : '';

    if (idx == 0) {
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(14),
        build: (_) {
          final widgets = <pw.Widget>[];
          if (elecHeader.isNotEmpty) {
            widgets.add(_pdfElectionHeader(elecHeader, font, bold));
            widgets.add(pw.SizedBox(height: 6));
          }
          for (final sz in _filteredSZ) {
            widgets.addAll(_pdfTab1(sz, font, bold));
            widgets.add(pw.SizedBox(height: 10));
          }
          return widgets;
        },
      ));
    } else if (idx == 1) {
      for (final sz in _filteredSZ) {
        for (final z in (sz['zones'] as List? ?? [])) {
          if (_fZone != null && '${z['id']}' != _fZone) continue;
          doc.addPage(pw.MultiPage(
            pageFormat: PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.all(14),
            build: (_) {
              final ws = <pw.Widget>[];
              if (elecHeader.isNotEmpty) {
                ws.add(_pdfElectionHeader(elecHeader, font, bold));
                ws.add(pw.SizedBox(height: 4));
              }
              ws.addAll(_pdfTab2(sz, z, font, bold));
              return ws;
            },
          ));
        }
      }
    } else {
      for (final item in _allTab3Items) {
        final sz = item['sz'] as Map;
        final z  = item['z']  as Map;
        final s  = item['s']  as Map;
        final gp = item['gp'] as Map;
        doc.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(14),
          build: (_) {
            final ws = <pw.Widget>[];
            if (elecHeader.isNotEmpty) {
              ws.add(_pdfElectionHeader(elecHeader, font, bold));
              ws.add(pw.SizedBox(height: 4));
            }
            ws.addAll(_pdfTab3(sz, z, s, gp, font, bold));
            return ws;
          },
        ));
      }
    }

    if (doc.document.pdfPageList.pages.isEmpty) {
      _snack('प्रिंट के लिए कोई डेटा नहीं', _kRed); return;
    }
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  // ─── PDF election header ──────────────────────────────────────────────────
  pw.Widget _pdfElectionHeader(String text, pw.Font font, pw.Font bold) =>
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: pw.BoxDecoration(
          color: const PdfColor.fromInt(0xFFFFF3CD),
          border: pw.Border.all(color: const PdfColor.fromInt(0xFFFFD700), width: 0.5),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Text(text,
            style: pw.TextStyle(font: bold, fontSize: 9,
                color: const PdfColor.fromInt(0xFF856404))),
      );

  // ─── PDF helpers ──────────────────────────────────────────────────────────
  pw.Widget _pdfTh(String t, pw.Font bold) => pw.Container(
    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
    padding: const pw.EdgeInsets.all(3),
    child: pw.Text(t, style: pw.TextStyle(font: bold, fontSize: 7),
        textAlign: pw.TextAlign.center),
  );

  pw.Widget _pdfTd(String t, pw.Font font, {bool center = false}) => pw.Padding(
    padding: const pw.EdgeInsets.all(3),
    child: pw.Text(t, style: pw.TextStyle(font: font, fontSize: 7),
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left),
  );

  String _officerStr(List officers) {
    if (officers.isEmpty) return '—';
    return officers.map((o) {
      final name   = (o['name']      ?? '').toString().trim();
      final rank   = (o['user_rank'] ?? '').toString().trim();
      final mobile = (o['mobile']    ?? '').toString().trim();
      final pno    = (o['pno']       ?? '').toString().trim();
      final parts  = [name, rank, if (pno.isNotEmpty) 'PNO:$pno', if (mobile.isNotEmpty) 'मो:$mobile'];
      return parts.where((p) => p.isNotEmpty).join(' ');
    }).join('\n');
  }

  // ─── PDF Tab 1 ────────────────────────────────────────────────────────────
  List<pw.Widget> _pdfTab1(Map sz, pw.Font font, pw.Font bold) {
    final zones = sz['zones'] as List? ?? [];
    int globalSector = 0;
    final rows = <List<String>>[];

    for (int zi = 0; zi < zones.length; zi++) {
      final z       = zones[zi] as Map;
      final sectors = z['sectors'] as List? ?? [];
      final zOff    = (z['officers'] as List? ?? []);
      final zOffStr = _officerStr(zOff);
      final hq      = (z['hq_address'] ?? z['hqAddress'] ?? '—').toString();

      if (sectors.isEmpty) {
        rows.add(['${zi + 1}', zOffStr, hq, '—', '—', '—', '—', '—']);
      } else {
        for (final s in sectors) {
          globalSector++;
          final gps     = s['panchayats'] as List? ?? [];
          final gpNames = gps.map((g) => '${g['name']}').join(', ');
          final thanas  = gps.map((g) => '${g['thana'] ?? ''}')
              .where((t) => t.isNotEmpty).toSet().join(', ');
          final sOff    = (s['officers'] as List? ?? []);
          final sOffStr = _officerStr(sOff);
          final sHq = (s['hq'] ?? s['hq_address'] ?? '—').toString();
          rows.add([
            '${zi + 1}', zOffStr, hq,
            '$globalSector', sOffStr, sHq,
            gpNames.isEmpty ? '—' : gpNames,
            thanas.isEmpty  ? '—' : thanas,
          ]);
        }
      }
    }

    int gpTotal = 0;
    for (final z in zones) {
      for (final s in (z['sectors'] as List? ?? [])) {
        gpTotal += ((s['panchayats'] as List?)?.length ?? 0);
      }
    }

    return [
      pw.RichText(text: pw.TextSpan(children: [
        pw.TextSpan(
          text: 'सुपर जोन–${sz['name']}  ब्लाक ${sz['block'] ?? ''}  ',
          style: pw.TextStyle(font: bold, fontSize: 11)),
        pw.TextSpan(
          text: 'कुल ग्राम पंचायत–$gpTotal',
          style: pw.TextStyle(font: bold, fontSize: 11)),
      ])),
      pw.SizedBox(height: 6),
      pw.Table(
        border: pw.TableBorder.all(width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(28), 1: pw.FlexColumnWidth(2.0),
          2: pw.FlexColumnWidth(1.5), 3: pw.FixedColumnWidth(28),
          4: pw.FlexColumnWidth(2.5), 5: pw.FlexColumnWidth(1.5),
          6: pw.FlexColumnWidth(3.0), 7: pw.FlexColumnWidth(1.2),
        },
        children: [
          pw.TableRow(children: [
            _pdfTh('सुपर\nजोन', bold), _pdfTh('जोनल अधिकारी', bold),
            _pdfTh('मुख्यालय', bold), _pdfTh('सैक्टर', bold),
            _pdfTh('सैक्टर पुलिस अधिकारी का नाम', bold),
            _pdfTh('मुख्यालय', bold),
            _pdfTh('सैक्टर में लगने वाले ग्राम पंचायत का नाम', bold),
            _pdfTh('थाना', bold),
          ]),
          ...rows.map((r) => pw.TableRow(children: [
            _pdfTd(r[0], font, center: true), _pdfTd(r[1], font),
            _pdfTd(r[2], font), _pdfTd(r[3], font, center: true),
            _pdfTd(r[4], font), _pdfTd(r[5], font),
            _pdfTd(r[6], font), _pdfTd(r[7], font),
          ])),
        ],
      ),
    ];
  }

  // ─── PDF Tab 2 ────────────────────────────────────────────────────────────
  List<pw.Widget> _pdfTab2(Map sz, Map z, pw.Font font, pw.Font bold) {
    final sectors = z['sectors'] as List? ?? [];
    final zOff    = (z['officers'] as List? ?? []);
    final szOff   = (sz['officers'] as List? ?? []);

    final rows = <List<String>>[];
    int sSeq = 0;
    for (final s in sectors) {
      sSeq++;
      final sOff   = (s['officers'] as List? ?? []);
      final magStr = sOff.isNotEmpty
          ? '${sOff[0]['name'] ?? ''} ${sOff[0]['user_rank'] ?? ''}\n${sOff[0]['mobile'] ?? ''}'
          : '—';
      final polStr = sOff.length > 1
          ? '${sOff[1]['name'] ?? ''} ${sOff[1]['user_rank'] ?? ''}\n${sOff[1]['mobile'] ?? ''}'
          : magStr;

      final gps = s['panchayats'] as List? ?? [];
      if (gps.isEmpty) {
        rows.add(['$sSeq', magStr, polStr, '—', '—', '—']);
      } else {
        for (final gp in gps) {
          final centers    = gp['centers'] as List? ?? [];
          final sthalNames = centers.map((c) => '${c['name']}').join('\n');
          final kendraStrs = centers
              .expand((c) => (c['kendras'] as List? ?? []))
              .map((k) => '${k['room_number']}')
              .join(', ');
          rows.add([
            '$sSeq', magStr, polStr,
            '${gp['name']}',
            sthalNames.isEmpty ? '—' : sthalNames,
            kendraStrs.isEmpty ? '—' : kendraStrs,
          ]);
        }
      }
    }

    final zOffStr  = _officerStr(zOff);
    final szOffStr = _officerStr(szOff);

    return [
      pw.Text(
        'जोन: ${z['name']}  |  सुपर जोन: ${sz['name']}  |  ब्लॉक: ${sz['block'] ?? ''}',
        style: pw.TextStyle(font: bold, fontSize: 11)),
      if (zOffStr.isNotEmpty && zOffStr != '—') ...[
        pw.SizedBox(height: 2),
        pw.Text('जोनल अधिकारी: $zOffStr', style: pw.TextStyle(font: font, fontSize: 8)),
      ],
      if (szOffStr.isNotEmpty && szOffStr != '—') ...[
        pw.SizedBox(height: 2),
        pw.Text('सुपर जोन अधिकारी: $szOffStr', style: pw.TextStyle(font: font, fontSize: 8)),
      ],
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(28), 1: pw.FlexColumnWidth(2.5),
          2: pw.FlexColumnWidth(2.5), 3: pw.FlexColumnWidth(1.8),
          4: pw.FlexColumnWidth(2.5), 5: pw.FlexColumnWidth(1.2),
        },
        children: [
          pw.TableRow(children: [
            _pdfTh('सैक्टर\nसं.', bold),
            _pdfTh('सैक्टर मजिस्ट्रेट\n(नाम/पद/मोबाइल)', bold),
            _pdfTh('सैक्टर पुलिस अधिकारी\n(नाम/पद/मोबाइल)', bold),
            _pdfTh('ग्राम पंचायत', bold),
            _pdfTh('मतदेय स्थल', bold),
            _pdfTh('मतदान केन्द्र', bold),
          ]),
          ...rows.map((r) => pw.TableRow(
              children: r.map((c) => _pdfTd(c, font)).toList())),
        ],
      ),
    ];
  }

  // ─── PDF Tab 3 — ONE ROW PER matdan_sthal, rooms inside name cell ───────
  List<pw.Widget> _pdfTab3(Map sz, Map z, Map s, Map gp, pw.Font font, pw.Font bold) {
    final centers = gp['centers'] as List? ?? [];

    // Count total kendras for header stats
    int totalKendra = 0;
    for (final c in centers) {
      final k = (c['kendras'] as List? ?? []);
      totalKendra += k.isEmpty ? 1 : k.length;
    }

    // r[0]=serial, r[1]=center name+rooms, r[2]=sthal serial,
    // r[3]=sthal name, r[4]=zone, r[5]=sector, r[6]=thana,
    // r[7]=duty, r[8]=mobile, r[9]=bus
    final rows = <List<String>>[];
    int sthalNo = 1;
    for (final c in centers) {
      final kendras     = c['kendras'] as List? ?? [];
      final roomNos     = kendras.isEmpty
          ? ''
          : kendras.map((k) => '${k['room_number']}').join(', ');
      final nameWithRooms = roomNos.isNotEmpty
          ? '${c['name']}\nक.नं. $roomNos'
          : '${c['name']}';
      final cType = (c['center_type'] ?? 'C').toString();

      final dutyOfficers = c['duty_officers'] as List? ?? [];
      final dutyText = dutyOfficers.isNotEmpty
          ? dutyOfficers.map((d) =>
              '${d['name'] ?? ''} ${d['pno'] ?? ''}\n${d['user_rank'] ?? ''}').join('\n')
          : '—';
      final mobileText = dutyOfficers.isNotEmpty
          ? dutyOfficers.map((d) => '${d['mobile'] ?? ''}')
              .where((m) => m.isNotEmpty).join('\n')
          : '—';
      final busNo = (c['bus_no'] ?? '—').toString();
      final thana = (c['thana'] ?? gp['thana'] ?? '—').toString();

      rows.add([
        '$sthalNo',            // 0 serial
        '$nameWithRooms\n$cType', // 1 name + rooms + type
        '$sthalNo',            // 2 sthal serial (same)
        '${c['name']}',       // 3 sthal name
        '${z['name']}',       // 4 zone
        '${s['name']}',       // 5 sector
        thana,                 // 6 thana
        dutyText,              // 7 duty officer
        mobileText,            // 8 mobile
        busNo,                 // 9 bus
      ]);
      sthalNo++;
    }

    return [
      pw.RichText(text: pw.TextSpan(children: [
        pw.TextSpan(
          text: 'बूथ ड्यूटी – ब्लॉक ${sz['block'] ?? sz['name']}  ',
          style: pw.TextStyle(font: bold, fontSize: 11)),
        pw.TextSpan(
          text: 'मतदान दिनांकः ....../......./2026',
          style: pw.TextStyle(font: font, fontSize: 10)),
      ])),
      pw.SizedBox(height: 2),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('मतदान केन्द्र–$totalKendra',
            style: pw.TextStyle(font: bold, fontSize: 9)),
        pw.Text('मतदेय स्थल–${centers.length}',
            style: pw.TextStyle(font: bold, fontSize: 9)),
      ]),
      pw.Text(
        'ग्राम पंचायत: ${gp['name']}  |  सैक्टर: ${s['name']}  |  जोन: ${z['name']}',
        style: pw.TextStyle(font: font, fontSize: 8)),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(22),   // serial
          1: pw.FlexColumnWidth(2.4),   // center name + rooms + type
          2: pw.FixedColumnWidth(22),   // sthal serial
          3: pw.FlexColumnWidth(2.0),   // sthal name
          4: pw.FixedColumnWidth(28),   // zone
          5: pw.FixedColumnWidth(28),   // sector
          6: pw.FlexColumnWidth(1.2),   // thana
          7: pw.FlexColumnWidth(2.5),   // duty officer
          8: pw.FlexColumnWidth(1.4),   // mobile
          9: pw.FixedColumnWidth(26),   // bus
        },
        children: [
          pw.TableRow(children: [
            _pdfTh('मतदान\nकेन्द्र\nसंख्या', bold),
            _pdfTh('मतदान केन्द्र का नाम', bold),
            _pdfTh('मतदेय\nसं.', bold),
            _pdfTh('मतदान स्थल\nका नाम', bold),
            _pdfTh('जोन\nसंख्या', bold),
            _pdfTh('सैक्टर\nसंख्या', bold),
            _pdfTh('थाना', bold),
            _pdfTh('ड्यूटी पर लगाया\nपुलिस का नाम', bold),
            _pdfTh('मोबाईल\nनम्बर', bold),
            _pdfTh('बस\nनं.', bold),
          ]),
          ...rows.map((r) => pw.TableRow(children: [
            _pdfTd(r[0], font, center: true),
            _pdfTd(r[1], font),
            _pdfTd(r[2], font, center: true),
            _pdfTd(r[3], font),
            _pdfTd(r[4], font, center: true),
            _pdfTd(r[5], font, center: true),
            _pdfTd(r[6], font),
            _pdfTd(r[7], font),
            _pdfTd(r[8], font),
            _pdfTd(r[9], font, center: true),
          ])),
        ],
      ),
    ];
  }

  // ── CRUD dialogs ──────────────────────────────────────────────────────────
  void _addSuperZone() {
    if (!_canEdit) { _snack('इतिहास मोड में संपादन अक्षम है', _kOrange); return; }
    _openDialog(
      title: 'सुपर जोन जोड़ें', color: _kPrimary, icon: Icons.layers_outlined,
      fields: {'name': 'नाम', 'district': 'जिला', 'block': 'ब्लॉक'},
      onSave: (data) async {
        final t = await AuthService.getToken();
        await ApiService.post('/admin/super-zones', Map<String, dynamic>.from(data), token: t);
        _load();
      },
    );
  }

  void _editSZ(Map sz) {
    if (!_canEdit) { _snack('इतिहास मोड में संपादन अक्षम है', _kOrange); return; }
    _openDialog(
      title: 'सुपर जोन संपादित करें', color: _kPrimary, icon: Icons.edit_outlined,
      fields: {'name': 'नाम', 'district': 'जिला', 'block': 'ब्लॉक'},
      initial: {'name': sz['name'], 'district': sz['district'], 'block': sz['block']},
      onSave: (data) async {
        final t = await AuthService.getToken();
        await ApiService.put('/admin/hierarchy/super-zone/${sz['id']}',
            Map<String, dynamic>.from(data), token: t);
        _load();
      },
    );
  }

  void _addZone(Map sz) {
    if (!_canEdit) { _snack('इतिहास मोड में संपादन अक्षम है', _kOrange); return; }
    _openDialog(
      title: 'जोन जोड़ें – ${sz['name']}', color: _kGreen, icon: Icons.map_outlined,
      fields: {'name': 'जोन का नाम', 'hqAddress': 'मुख्यालय पता'},
      onSave: (data) async {
        final t = await AuthService.getToken();
        await ApiService.post('/admin/super-zones/${sz['id']}/zones',
            Map<String, dynamic>.from(data), token: t);
        _load();
      },
    );
  }

  void _editZone(Map z) {
    if (!_canEdit) { _snack('इतिहास मोड में संपादन अक्षम है', _kOrange); return; }
    _openDialog(
      title: 'जोन संपादित करें', color: _kGreen, icon: Icons.edit_outlined,
      fields: {'name': 'जोन का नाम', 'hqAddress': 'मुख्यालय पता'},
      initial: {'name': z['name'], 'hqAddress': z['hq_address'] ?? z['hqAddress'] ?? ''},
      onSave: (data) async {
        final t = await AuthService.getToken();
        await ApiService.put('/admin/zones/${z['id']}',
            Map<String, dynamic>.from(data), token: t);
        _load();
      },
    );
  }

  void _addSector(Map z) {
    if (!_canEdit) { _snack('इतिहास मोड में संपादन अक्षम है', _kOrange); return; }
    _openDialog(
      title: 'सैक्टर जोड़ें – ${z['name']}', color: _kGreen, icon: Icons.add,
      fields: {'name': 'सैक्टर का नाम', 'hqAddress': 'मुख्यालय पता'},
      onSave: (data) async {
        final t = await AuthService.getToken();
        await ApiService.post('/admin/zones/${z['id']}/sectors',
            Map<String, dynamic>.from(data), token: t);
        _load();
      },
    );
  }

  void _editSector(Map s) {
    if (!_canEdit) { _snack('इतिहास मोड में संपादन अक्षम है', _kOrange); return; }
    _openDialog(
      title: 'सैक्टर संपादित करें', color: _kGreen, icon: Icons.edit_outlined,
      fields: {'name': 'सैक्टर का नाम', 'hqAddress': 'मुख्यालय पता'},
      initial: {
        'name': s['name'],
        'hqAddress': s['hq_address'] ?? s['hqAddress'] ?? s['hq'] ?? '',
      },
      onSave: (data) async {
        final t = await AuthService.getToken();
        await ApiService.put('/admin/hierarchy/sector/${s['id']}',
            Map<String, dynamic>.from(data), token: t);
        _load();
      },
    );
  }

  void _addGP(Map s) {
    if (!_canEdit) { _snack('इतिहास मोड में संपादन अक्षम है', _kOrange); return; }
    _openDialog(
      title: 'ग्राम पंचायत जोड़ें – ${s['name']}', color: _kPurple, icon: Icons.add,
      fields: {'name': 'ग्राम पंचायत का नाम', 'address': 'पता'},
      onSave: (data) async {
        final t = await AuthService.getToken();
        await ApiService.post('/admin/sectors/${s['id']}/gram-panchayats',
            Map<String, dynamic>.from(data), token: t);
        _load();
      },
    );
  }

  void _addCenter(Map gp) {
    if (!_canEdit) { _snack('इतिहास मोड में संपादन अक्षम है', _kOrange); return; }
    _openCenterDialog(null, gpId: gp['id']);
  }
  void _editCenter(Map c) {
    if (!_canEdit) { _snack('इतिहास मोड में संपादन अक्षम है', _kOrange); return; }
    _openCenterDialog(c);
  }

  void _addKendra(Map c) {
    if (!_canEdit) { _snack('इतिहास मोड में संपादन अक्षम है', _kOrange); return; }
    _openDialog(
      title: 'मतदेय स्थल (कक्ष) जोड़ें', color: _kPurple, icon: Icons.add,
      fields: {'roomNumber': 'कक्ष संख्या'},
      onSave: (data) async {
        final t = await AuthService.getToken();
        await ApiService.post('/admin/centers/${c['id']}/rooms',
            Map<String, dynamic>.from(data), token: t);
        _load();
      },
    );
  }

  void _openCenterDialog(Map? center, {int? gpId}) {
    final nameCtrl    = TextEditingController(text: center?['name'] ?? '');
    final addressCtrl = TextEditingController(text: center?['address'] ?? '');
    final thanaCtrl   = TextEditingController(text: center?['thana'] ?? '');
    final busCtrl     = TextEditingController(
        text: center?['bus_no'] ?? center?['busNo'] ?? '');
    String type = center?['center_type'] ?? center?['centerType'] ?? 'C';
    if (!_kCenterTypes.contains(type)) type = 'C';
    final fk = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(center != null ? 'मतदेय स्थल संपादित करें' : 'मतदेय स्थल जोड़ें'),
          content: SizedBox(
            width: 380,
            child: Form(
              key: fk,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _field(nameCtrl, 'नाम *', required: true),
                  const SizedBox(height: 8),
                  _field(addressCtrl, 'पता'),
                  const SizedBox(height: 8),
                  _field(thanaCtrl, 'थाना'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: _kCenterTypes.map((t) => GestureDetector(
                      onTap: () => ss(() => type = t),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: type == t ? _sensitivityColor(t) : Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _sensitivityColor(t)),
                        ),
                        child: Text(t, style: TextStyle(
                            color: type == t ? Colors.white : _sensitivityColor(t),
                            fontWeight: FontWeight.w800, fontSize: 12)),
                      ),
                    )).toList(),
                  ),
                  const SizedBox(height: 8),
                  _field(busCtrl, 'बस संख्या'),
                ]),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kPurple),
              onPressed: () async {
                if (!fk.currentState!.validate()) return;
                Navigator.pop(ctx);
                final data = <String, dynamic>{
                  'name':        nameCtrl.text.trim(),
                  'address':     addressCtrl.text.trim(),
                  'thana':       thanaCtrl.text.trim(),
                  'centerType':  type,
                  'busNo':       busCtrl.text.trim(),
                  'center_type': type,
                };
                final tok = await AuthService.getToken();
                if (center != null) {
                  await ApiService.put(
                      '/admin/hierarchy/sthal/${center['id']}', data, token: tok);
                } else {
                  await ApiService.post(
                      '/admin/gram-panchayats/$gpId/centers', data, token: tok);
                }
                _load();
              },
              child: const Text('सहेजें', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _openStaffDialog(Map center) {
    if (!_canEdit) { _snack('इतिहास मोड में स्टाफ असाइन अक्षम है', _kOrange); return; }
    showDialog(
      context: context,
      builder: (ctx) => _PaginatedStaffDialog(
        center: center,
        onChanged: _load,
      ),
    );
  }

  void _openDialog({
    required String title, required Color color, required IconData icon,
    required Map<String, String> fields,
    Map<String, dynamic>? initial,
    required Future<void> Function(Map<String, dynamic>) onSave,
  }) {
    final ctrls = fields.map((k, v) =>
        MapEntry(k, TextEditingController(text: '${initial?[k] ?? ''}')));
    final fk = GlobalKey<FormState>();
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(children: [
            Icon(icon, color: color, size: 20), const SizedBox(width: 8),
            Expanded(child: Text(title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
          ]),
          content: SizedBox(
            width: 340,
            child: Form(
              key: fk,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: fields.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _field(ctrls[e.key]!, e.value,
                      required: e.key == 'name'),
                )).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
              onPressed: saving ? null : () async {
                if (!fk.currentState!.validate()) return;
                ss(() => saving = true);
                try {
                  final data = <String, dynamic>{
                    for (final e in ctrls.entries) e.key: e.value.text.trim(),
                  };
                  await onSave(data);
                  if (ctx.mounted) Navigator.pop(ctx);
                  _snack('सफलतापूर्वक सहेजा गया', _kGreen);
                } catch (e) {
                  _snack('त्रुटि: $e', _kRed);
                } finally {
                  if (ctx.mounted) ss(() => saving = false);
                }
              },
              child: saving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('सहेजें',
                      style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {bool required = false}) =>
      TextFormField(
        controller: c,
        decoration: InputDecoration(
          labelText: label, isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kPrimary, width: 2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        validator: required
            ? (v) => (v?.trim().isEmpty ?? true) ? '$label आवश्यक' : null
            : null,
      );

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final scopeLine = widget.electionName != null
        ? 'चुनाव: ${widget.electionName}'
        : (widget.role.toLowerCase() == 'master' &&
                (widget.district ?? '').trim().isNotEmpty)
            ? 'जनपद: ${widget.district}'
            : 'Administrative Hierarchy Report';

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPrimary, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('प्रशासनिक पदानुक्रम',
              style: TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
          Text(scopeLine,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
              overflow: TextOverflow.ellipsis),
        ]),
        actions: [
          IconButton(
              icon: const Icon(Icons.print_outlined, color: Colors.white),
              onPressed: _print, tooltip: 'प्रिंट'),
          if (_canEdit) ...[
            IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                onPressed: _addSuperZone, tooltip: 'सुपर जोन जोड़ें'),
          ],
          IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              onPressed: _load),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: _kAccent, indicatorWeight: 3,
          labelColor: Colors.white, unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'सुपर जोन', icon: Icon(Icons.layers_outlined, size: 16)),
            Tab(text: 'जोन/सैक्टर', icon: Icon(Icons.map_outlined, size: 16)),
            Tab(text: 'बूथ ड्यूटी', icon: Icon(Icons.how_to_vote_outlined, size: 16)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _load)
              : Column(children: [
                  // ── History banner ──────────────────────────────────────
                  if (widget.isHistory) _HistoryBanner(
                      electionName: widget.electionName ?? 'पिछला चुनाव'),
                  _buildFilterBar(),
                  Expanded(child: TabBarView(controller: _tab, children: [
                    _buildTab1(),
                    _buildTab2(),
                    _buildTab3(),
                  ])),
                ]),
    );
  }

  Widget _buildFilterBar() {
    final tabIdx = _tab.index;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _FDrop(
            label: 'सुपर जोन', value: _fSZ, placeholder: 'सभी सुपर जोन',
            items: _szList.map((s) => _DI('${s['id']}', '${s['name']}')).toList(),
            onChanged: (v) => setState(() {
              _fSZ = v; _fZone = _fSector = _fGP = null; _tab3Page = 1;
            }),
          ),
          if (tabIdx >= 1) ...[
            const SizedBox(width: 10),
            _FDrop(
              label: 'जोन', value: _fZone, placeholder: 'सभी जोन',
              items: _allZones.map((z) => _DI('${z['id']}', '${z['name']}')).toList(),
              onChanged: (v) => setState(() {
                _fZone = v; _fSector = _fGP = null; _tab3Page = 1;
              }),
            ),
          ],
          if (tabIdx >= 2) ...[
            const SizedBox(width: 10),
            _FDrop(
              label: 'सैक्टर', value: _fSector, placeholder: 'सभी सैक्टर',
              items: _allSectors
                  .map((s) => _DI('${s['id']}', '${s['name']}'))
                  .toList(),
              onChanged: (v) => setState(() {
                _fSector = v; _fGP = null; _tab3Page = 1;
              }),
            ),
            const SizedBox(width: 10),
            _FDrop(
              label: 'ग्राम पंचायत', value: _fGP, placeholder: 'सभी GP',
              items: _allGPs
                  .map((g) => _DI('${g['id']}', '${g['name']}'))
                  .toList(),
              onChanged: (v) => setState(() { _fGP = v; _tab3Page = 1; }),
            ),
          ],
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 1
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildTab1() {
    if (_filteredSZ.isEmpty) return const _Empty(text: 'कोई सुपर जोन नहीं मिला');
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: _filteredSZ.length,
      itemBuilder: (_, i) => _Tab1Card(
        sz: _filteredSZ[i],
        isHistory: widget.isHistory,
        onEdit:    () => _editSZ(_filteredSZ[i]),
        onDelete:  () => _delete('/admin/hierarchy/super-zone',
            _filteredSZ[i]['id'], '${_filteredSZ[i]['name']}'),
        onAddZone: () => _addZone(_filteredSZ[i]),
        onManageOfficers: () => _openOfficerDialog(
          'सुपर जोन अधिकारी', _kPrimary,
          '/admin/super-zones/${_filteredSZ[i]['id']}/officers',
          (_filteredSZ[i]['officers'] as List? ?? []),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 2
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildTab2() {
    final items = <Map>[];
    for (final sz in _filteredSZ) {
      for (final z in (sz['zones'] as List? ?? [])) {
        if (_fZone != null && '${z['id']}' != _fZone) continue;
        items.add({'sz': sz, 'z': z});
      }
    }
    if (items.isEmpty) return const _Empty(text: 'कोई जोन नहीं मिला');
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: items.length,
      itemBuilder: (_, i) => _Tab2Card(
        sz: items[i]['sz'], z: items[i]['z'],
        isHistory: widget.isHistory,
        onEditZone:   () => _editZone(items[i]['z']),
        onDeleteZone: () => _delete('/admin/zones',
            items[i]['z']['id'], '${items[i]['z']['name']}'),
        onAddSector:  () => _addSector(items[i]['z']),
        onManageZoneOfficers: () => _openOfficerDialog(
          'जोनल अधिकारी', _kGreen,
          '/admin/zones/${items[i]['z']['id']}/officers',
          (items[i]['z']['officers'] as List? ?? []),
        ),
        onEditSector:   _editSector,
        onDeleteSector: (s) => _delete(
            '/admin/hierarchy/sector', s['id'], '${s['name']}'),
        onAddGP:        _addGP,
        onManageSectorOfficers: (s) => _openOfficerDialog(
          'सैक्टर अधिकारी', _kGreen,
          '/admin/sectors/${s['id']}/officers',
          (s['officers'] as List? ?? []),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 3 — with pagination
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildTab3() {
    final allItems   = _allTab3Items;
    final totalPages = _tab3TotalPages;
    final pagedItems = _pagedTab3Items;

    if (allItems.isEmpty) return const _Empty(text: 'कोई पंचायत नहीं मिली');

    return Column(
      children: [
        _Tab3PaginationBar(
          currentPage: _tab3Page, totalPages: totalPages,
          totalItems: allItems.length, pageSize: _tab3PageSize,
          onPageChanged: (p) => setState(() => _tab3Page = p),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            itemCount: pagedItems.length,
            itemBuilder: (_, i) {
              final item = pagedItems[i];
              return _Tab3Card(
                sz: item['sz'], z: item['z'],
                s:  item['s'],  gp: item['gp'],
                isHistory: widget.isHistory,
                onAddCenter:    () => _addCenter(item['gp']),
                onEditCenter:   _editCenter,
                onDeleteCenter: (c) => _delete(
                    '/admin/hierarchy/sthal', c['id'], '${c['name']}'),
                onAddKendra:    _addKendra,
                onDeleteKendra: (k) => _delete(
                    '/admin/rooms', k['id'], '${k['room_number']}'),
                onManageStaff:  _openStaffDialog,
              );
            },
          ),
        ),
        _Tab3PaginationBar(
          currentPage: _tab3Page, totalPages: totalPages,
          totalItems: allItems.length, pageSize: _tab3PageSize,
          onPageChanged: (p) => setState(() => _tab3Page = p),
          compact: true,
        ),
      ],
    );
  }

  void _openOfficerDialog(
      String title, Color color, String endpoint, List officers) {
    if (!_canEdit) { _snack('इतिहास मोड में संपादन अक्षम है', _kOrange); return; }
    showDialog(
      context: context,
      builder: (ctx) => _OfficersDialog(
        title: title, color: color, endpoint: endpoint,
        officers: List<Map>.from(officers),
        onSave: (_) => _load(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// HISTORY BANNER
// ══════════════════════════════════════════════════════════════════════════════
class _HistoryBanner extends StatelessWidget {
  final String electionName;
  const _HistoryBanner({required this.electionName});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    color: _kAmber,
    child: Row(children: [
      const Icon(Icons.history_outlined, color: _kAmberDark, size: 16),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          'इतिहास देख रहे हैं: $electionName  •  संपादन अक्षम है',
          style: const TextStyle(
              color: _kAmberDark, fontSize: 12, fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const Icon(Icons.lock_outline, color: _kAmberDark, size: 14),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 3 PAGINATION BAR
// ══════════════════════════════════════════════════════════════════════════════
class _Tab3PaginationBar extends StatelessWidget {
  final int currentPage, totalPages, totalItems, pageSize;
  final ValueChanged<int> onPageChanged;
  final bool compact;

  const _Tab3PaginationBar({
    required this.currentPage, required this.totalPages,
    required this.totalItems, required this.pageSize,
    required this.onPageChanged, this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final start = ((currentPage - 1) * pageSize + 1).clamp(1, totalItems);
    final end   = (currentPage * pageSize).clamp(1, totalItems);

    final pages = <int>[];
    if (totalPages <= 7) {
      for (int i = 1; i <= totalPages; i++) pages.add(i);
    } else {
      pages.add(1);
      if (currentPage > 3) pages.add(-1);
      for (int i = (currentPage - 1).clamp(2, totalPages - 1);
           i <= (currentPage + 1).clamp(2, totalPages - 1); i++) {
        pages.add(i);
      }
      if (currentPage < totalPages - 2) pages.add(-1);
      pages.add(totalPages);
    }

    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(
          horizontal: 12, vertical: compact ? 4 : 8),
      child: compact
          ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _navBtn(Icons.first_page, currentPage > 1, () => onPageChanged(1)),
              _navBtn(Icons.chevron_left, currentPage > 1,
                  () => onPageChanged(currentPage - 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('$currentPage / $totalPages',
                    style: const TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w700, color: _kPrimary)),
              ),
              _navBtn(Icons.chevron_right, currentPage < totalPages,
                  () => onPageChanged(currentPage + 1)),
              _navBtn(Icons.last_page, currentPage < totalPages,
                  () => onPageChanged(totalPages)),
            ])
          : Row(children: [
              Expanded(child: Text(
                'ग्राम पंचायत $start–$end / $totalItems  '
                '(पृष्ठ $currentPage/$totalPages)',
                style: const TextStyle(fontSize: 11, color: _kSubtle),
              )),
              Row(children: [
                _navBtn(Icons.first_page, currentPage > 1, () => onPageChanged(1)),
                _navBtn(Icons.chevron_left, currentPage > 1,
                    () => onPageChanged(currentPage - 1)),
                ...pages.map((p) => p == -1
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2),
                        child: Text('…', style: TextStyle(color: _kSubtle)))
                    : _pageBtn(p, p == currentPage, () => onPageChanged(p))),
                _navBtn(Icons.chevron_right, currentPage < totalPages,
                    () => onPageChanged(currentPage + 1)),
                _navBtn(Icons.last_page, currentPage < totalPages,
                    () => onPageChanged(totalPages)),
              ]),
            ]),
    );
  }

  Widget _navBtn(IconData icon, bool enabled, VoidCallback onTap) =>
      InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 18,
              color: enabled ? _kPrimary : _kBorder),
        ),
      );

  Widget _pageBtn(int page, bool active, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: active ? _kPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: active ? _kPrimary : _kBorder),
          ),
          child: Center(child: Text('$page',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: active ? Colors.white : _kDark))),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// PAGINATED STAFF DIALOG
// ══════════════════════════════════════════════════════════════════════════════
class _PaginatedStaffDialog extends StatefulWidget {
  final Map center;
  final VoidCallback onChanged;
  const _PaginatedStaffDialog({required this.center, required this.onChanged});
  @override
  State<_PaginatedStaffDialog> createState() => _PaginatedStaffDialogState();
}

class _PaginatedStaffDialogState extends State<_PaginatedStaffDialog> {
  final List<Map> _staff    = [];
  int  _page                = 1;
  int  _total               = 0;
  bool _loading             = false;
  bool _hasMore             = true;
  String _q                 = '';
  Timer? _debounce;
  final _searchCtrl         = TextEditingController();
  final _scroll             = ScrollController();
  final _busCtrl            = TextEditingController();
  int? _selectedId;
  bool _saving              = false;

  List _assigned = [];

  @override
  void initState() {
    super.initState();
    _assigned = List.from(widget.center['duty_officers'] as List? ?? []);
    _busCtrl.text = '${widget.center['bus_no'] ?? ''}';
    _scroll.addListener(_onScroll);
    _searchCtrl.addListener(_onSearch);
    _loadStaff(reset: true);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _searchCtrl.removeListener(_onSearch);
    _scroll.dispose(); _searchCtrl.dispose();
    _busCtrl.dispose(); _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 150
        && !_loading && _hasMore) _loadStaff();
  }

  void _onSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final q = _searchCtrl.text.trim();
      if (q != _q) { _q = q; _loadStaff(reset: true); }
    });
  }

  Future<void> _loadStaff({bool reset = false}) async {
    if (_loading) return;
    if (!reset && !_hasMore) return;
    if (reset) setState(() { _staff.clear(); _page = 1; _hasMore = true; });
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get(
        '/admin/staff?assigned=no&page=$_page&limit=30'
        '&q=${Uri.encodeComponent(_q)}',
        token: token,
      );
      final wrapper    = (res['data'] as Map<String, dynamic>?) ?? {};
      final items      = List<Map>.from((wrapper['data'] as List?) ?? []);
      final total      = (wrapper['total']      as num?)?.toInt() ?? 0;
      final totalPages = (wrapper['totalPages'] as num?)?.toInt() ?? 1;
      if (!mounted) return;
      setState(() {
        _staff.addAll(items);
        _total   = total;
        _hasMore = _page < totalPages;
        _page++;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _assign() async {
    if (_selectedId == null || _saving) return;
    setState(() => _saving = true);
    try {
      final token = await AuthService.getToken();
      await ApiService.post('/admin/duties', {
        'staffId':  _selectedId,
        'centerId': widget.center['id'],
        'busNo':    _busCtrl.text.trim(),
      }, token: token);
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('त्रुटि: $e'), backgroundColor: _kRed,
            behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeDuty(Map d) async {
    try {
      final token = await AuthService.getToken();
      await ApiService.delete('/admin/duties/${d['id']}', token: token);
      widget.onChanged();
      setState(() => _assigned.removeWhere((a) => a['id'] == d['id']));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('त्रुटि: $e'), backgroundColor: _kRed));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: 500,
            maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            decoration: const BoxDecoration(color: _kPurple,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
            child: Row(children: [
              const Icon(Icons.people_alt_outlined, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text('स्टाफ – ${widget.center['name']}',
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w800, fontSize: 13),
                  overflow: TextOverflow.ellipsis)),
              IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 18),
                  onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_assigned.isNotEmpty) ...[
                const Text('असाइन किए गए स्टाफ:',
                    style: TextStyle(fontWeight: FontWeight.w700,
                        fontSize: 12, color: _kSubtle)),
                const SizedBox(height: 6),
                ..._assigned.map((d) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF3E5F5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _kPurple.withOpacity(0.3))),
                  child: Row(children: [
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${d['name']}', style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13, color: _kDark)),
                      Text(
                        'PNO: ${d['pno']}  •  ${d['user_rank'] ?? ''}'
                        '  •  ${d['mobile'] ?? ''}',
                        style: const TextStyle(color: _kSubtle, fontSize: 11)),
                    ])),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline,
                          color: _kRed, size: 20),
                      onPressed: () => _removeDuty(d),
                    ),
                  ]),
                )),
                const Divider(height: 20),
              ],
              const Text('नया स्टाफ जोड़ें:',
                  style: TextStyle(fontWeight: FontWeight.w700,
                      fontSize: 12, color: _kSubtle)),
              const SizedBox(height: 8),
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'नाम, PNO, थाना से खोजें... ($_total उपलब्ध)',
                  prefixIcon: const Icon(Icons.search, size: 18, color: _kSubtle),
                  isDense: true, fillColor: const Color(0xFFF8F9FC), filled: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kBorder)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kBorder)),
                  suffixIcon: _q.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16, color: _kSubtle),
                          onPressed: () { _searchCtrl.clear(); })
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 10, horizontal: 12),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                        border: Border.all(color: _kBorder),
                        borderRadius: BorderRadius.circular(8)),
                    child: _loading && _staff.isEmpty
                        ? const Center(child: CircularProgressIndicator(
                            color: _kPurple, strokeWidth: 2))
                        : _staff.isEmpty
                            ? Center(child: Text(
                                _q.isNotEmpty
                                    ? '"$_q" नहीं मिला'
                                    : 'सभी स्टाफ असाइन किए जा चुके हैं',
                                style: const TextStyle(
                                    color: _kSubtle, fontSize: 12)))
                            : ListView.separated(
                                controller: _scroll,
                                itemCount: _staff.length + (_hasMore ? 1 : 0),
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1, color: _kBorder),
                                itemBuilder: (_, i) {
                                  if (i >= _staff.length) {
                                    return const Padding(padding: EdgeInsets.all(8),
                                        child: Center(child: SizedBox(
                                            width: 16, height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2, color: _kPurple))));
                                  }
                                  final s   = _staff[i];
                                  final sel = _selectedId == s['id'];
                                  return InkWell(
                                    onTap: () => setState(() =>
                                        _selectedId = sel ? null : s['id'] as int),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 9),
                                      color: sel
                                          ? _kPurple.withOpacity(0.07)
                                          : Colors.transparent,
                                      child: Row(children: [
                                        AnimatedContainer(
                                          duration: const Duration(milliseconds: 150),
                                          width: 24, height: 24,
                                          decoration: BoxDecoration(
                                              color: sel ? _kPurple
                                                  : const Color(0xFFF5EAD0),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                  color: sel ? _kPurple : _kBorder)),
                                          child: sel
                                              ? const Icon(Icons.check,
                                                  color: Colors.white, size: 13)
                                              : null),
                                        const SizedBox(width: 10),
                                        Expanded(child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                          Text('${s['name']}', style: TextStyle(
                                              color: sel ? _kPurple : _kDark,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13)),
                                          Text(
                                            'PNO: ${s['pno']}  •  '
                                            '${s['thana'] ?? ''}  •  '
                                            '${s['rank'] ?? s['user_rank'] ?? ''}',
                                            style: const TextStyle(
                                                color: _kSubtle, fontSize: 10),
                                            overflow: TextOverflow.ellipsis),
                                        ])),
                                      ]),
                                    ),
                                  );
                                },
                              ),
                  ),
                ),
              ),
              if (_hasMore && !_loading)
                const Padding(padding: EdgeInsets.only(top: 4),
                    child: Text('↓ स्क्रॉल करें — और स्टाफ लोड होंगे',
                        style: TextStyle(color: _kSubtle, fontSize: 10))),
              const SizedBox(height: 10),
              TextFormField(
                controller: _busCtrl,
                decoration: InputDecoration(
                  labelText: 'बस संख्या', isDense: true,
                  prefixIcon: const Icon(Icons.directions_bus_outlined, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),
            ]),
          )),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Row(children: [
              Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('बंद करें'))),
              if (_selectedId != null) ...[
                const SizedBox(width: 10),
                Expanded(child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _kPurple),
                  onPressed: _saving ? null : _assign,
                  child: _saving
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('असाइन करें',
                          style: TextStyle(color: Colors.white)),
                )),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// OFFICERS MANAGEMENT DIALOG
// ══════════════════════════════════════════════════════════════════════════════
class _OfficersDialog extends StatefulWidget {
  final String title, endpoint;
  final Color color;
  final List<Map> officers;
  final void Function(List<Map>) onSave;
  const _OfficersDialog({required this.title, required this.color,
      required this.endpoint, required this.officers, required this.onSave});
  @override
  State<_OfficersDialog> createState() => _OfficersDialogState();
}

class _OfficersDialogState extends State<_OfficersDialog> {
  late List<Map<String, dynamic>> _officers;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _officers = widget.officers.map((o) => Map<String, dynamic>.from(o)).toList();
  }

  void _add() => setState(() => _officers.add({
    'name': '', 'pno': '', 'mobile': '', 'user_rank': '',
  }));

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final token = await AuthService.getToken();
      final payload = _officers
          .where((o) => (o['name'] ?? '').toString().isNotEmpty)
          .map((o) => {
                'name':      o['name'] ?? '',
                'pno':       o['pno']  ?? '',
                'mobile':    o['mobile'] ?? '',
                'rank':      o['user_rank'] ?? '',
              })
          .toList();

      final parts = widget.endpoint.split('/');
      String type = '';
      String id   = '';

      if (widget.endpoint.contains('super-zones')) {
        type = 'super-zone'; id = parts[3];
      } else if (widget.endpoint.contains('zones')) {
        type = 'zone'; id = parts[3];
      } else if (widget.endpoint.contains('sectors')) {
        type = 'sector'; id = parts[3];
      }

      await ApiService.post(
        '/admin/hierarchy/$type/$id/officers/replace',
        {'officers': payload},
        token: token,
      );

      widget.onSave(_officers);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('अधिकारी अपडेट किए गए'),
          backgroundColor: _kGreen,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('त्रुटि: $e'), backgroundColor: _kRed,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            decoration: BoxDecoration(color: widget.color,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14))),
            child: Row(children: [
              const Icon(Icons.people_outlined, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(widget.title,
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w800, fontSize: 14))),
              IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 18),
                  onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Flexible(child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              ..._officers.asMap().entries.map((e) {
                final i = e.key; final o = e.value;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _kBg, borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kBorder.withOpacity(0.5)),
                  ),
                  child: Column(children: [
                    Row(children: [
                      Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(
                            color: widget.color.withOpacity(0.15),
                            shape: BoxShape.circle),
                        child: Center(child: Text('${i + 1}',
                            style: TextStyle(color: widget.color,
                                fontSize: 10, fontWeight: FontWeight.w900))),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(() => _officers.removeAt(i)),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                              color: _kRed.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(6)),
                          child: const Icon(Icons.delete_outline,
                              color: _kRed, size: 16),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    _officerField(o, 'name', 'नाम', Icons.person_outline),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(child: _officerField(
                          o, 'pno', 'PNO', Icons.badge_outlined)),
                      const SizedBox(width: 8),
                      Expanded(child: _officerField(
                          o, 'mobile', 'मोबाइल', Icons.phone_outlined)),
                    ]),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _kBorder)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _kRanks.any((r) => r['en'] == o['user_rank'])
                              ? o['user_rank'] as String? : null,
                          isExpanded: true, isDense: true,
                          hint: const Text('पद चुनें',
                              style: TextStyle(fontSize: 12, color: _kSubtle)),
                          style: const TextStyle(color: _kDark, fontSize: 12),
                          items: _kRanks.map((r) => DropdownMenuItem<String>(
                            value: r['en'],
                            child: Text('${r['hi']} (${r['en']})',
                                style: const TextStyle(fontSize: 12)),
                          )).toList(),
                          onChanged: (v) =>
                              setState(() => o['user_rank'] = v ?? ''),
                        ),
                      ),
                    ),
                  ]),
                );
              }),
              OutlinedButton.icon(
                onPressed: _add,
                icon: Icon(Icons.add, color: widget.color),
                label: Text('अधिकारी जोड़ें',
                    style: TextStyle(color: widget.color)),
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: widget.color),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
              ),
            ]),
          )),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Row(children: [
              Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('रद्द'))),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: widget.color),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('सहेजें',
                        style: TextStyle(color: Colors.white)),
              )),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _officerField(
      Map<String, dynamic> o, String key, String label, IconData icon) {
    return TextFormField(
      initialValue: '${o[key] ?? ''}',
      style: const TextStyle(fontSize: 12, color: _kDark),
      decoration: InputDecoration(
        labelText: label, isDense: true,
        prefixIcon: Icon(icon, size: 16, color: _kSubtle),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        labelStyle: const TextStyle(fontSize: 11, color: _kSubtle),
      ),
      onChanged: (v) => o[key] = v,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 1 CARD
// ══════════════════════════════════════════════════════════════════════════════
class _Tab1Card extends StatelessWidget {
  final Map sz;
  final bool isHistory;
  final VoidCallback onEdit, onDelete, onAddZone, onManageOfficers;
  const _Tab1Card({required this.sz, required this.isHistory,
      required this.onEdit, required this.onDelete,
      required this.onAddZone, required this.onManageOfficers});

  @override
  Widget build(BuildContext context) {
    final zones = sz['zones'] as List? ?? [];
    int gpTotal = 0, sTotal = 0;
    for (final z in zones) {
      final secs = z['sectors'] as List? ?? [];
      sTotal += secs.length;
      for (final s in secs) gpTotal += ((s['panchayats'] as List?)?.length ?? 0);
    }

    final rows = <_R1>[];
    int globalSec = 0;
    for (int zi = 0; zi < zones.length; zi++) {
      final z       = zones[zi] as Map;
      final sectors = z['sectors'] as List? ?? [];
      final zOff    = z['officers'] as List? ?? [];
      if (sectors.isEmpty) {
        rows.add(_R1(zi: zi, z: z, s: null, sGlobal: null,
            zOff: zOff, gpNames: '—', thanas: '—'));
      } else {
        for (int si = 0; si < sectors.length; si++) {
          final s   = sectors[si] as Map;
          globalSec++;
          final gps = s['panchayats'] as List? ?? [];
          rows.add(_R1(
            zi: zi, z: z, s: s, sGlobal: globalSec, zOff: zOff,
            gpNames: gps.map((g) => '${g['name']}').join('، '),
            thanas: gps.map((g) => '${g['thana'] ?? ''}')
                .where((t) => t.isNotEmpty).toSet().join('، '),
          ));
        }
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: [BoxShadow(color: _kPrimary.withOpacity(0.07),
            blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF0F2B5B), Color(0xFF1E3F80)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('सुपर जोन–${sz['name']}  ब्लाक ${sz['block'] ?? '—'}',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 14, fontWeight: FontWeight.w800)),
                Text('जिला: ${sz['district'] ?? '—'}  |  कुल ग्राम पंचायत: $gpTotal',
                    style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ])),
              if (!isHistory) ...[
                _IAB(icon: Icons.person_add_outlined, color: Colors.teal[200]!,
                    onTap: onManageOfficers, tooltip: 'अधिकारी'),
                _IAB(icon: Icons.add_circle_outline, color: _kAccent,
                    onTap: onAddZone, tooltip: 'जोन जोड़ें'),
                _IAB(icon: Icons.edit_outlined, color: _kAccent, onTap: onEdit),
                _IAB(icon: Icons.delete_outline, color: Colors.red[300]!, onTap: onDelete),
              ],
            ]),
            const SizedBox(height: 6),
            Row(children: [
              _MC('${zones.length} जोन', Colors.blue),
              const SizedBox(width: 6),
              _MC('$sTotal सैक्टर', Colors.green),
              const SizedBox(width: 6),
              _MC('$gpTotal ग्राम पंचायत', Colors.orange),
            ]),
          ]),
        ),

        if ((sz['officers'] as List?)?.isNotEmpty == true)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: _kGold,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('सुपर जोन / क्षेत्र अधिकारी:',
                  style: TextStyle(color: _kSubtle, fontSize: 10,
                      fontWeight: FontWeight.w700)),
              ...(sz['officers'] as List).map((o) => Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(children: [
                  const Icon(Icons.person_pin_outlined, size: 12, color: _kPrimary),
                  const SizedBox(width: 5),
                  Expanded(child: Text(
                    '${o['name'] ?? '—'}  ${o['user_rank'] ?? ''}'
                    '${(o['pno'] ?? '').toString().isNotEmpty ? '  PNO: ${o['pno']}' : ''}'
                    '${(o['mobile'] ?? '').toString().isNotEmpty ? '  मो: ${o['mobile']}' : ''}',
                    style: const TextStyle(color: _kDark, fontSize: 11),
                  )),
                ]),
              )),
            ]),
          ),

        if (rows.isEmpty)
          const Padding(padding: EdgeInsets.all(16),
              child: _Empty(text: 'कोई जोन/सैक्टर नहीं'))
        else
          Padding(padding: const EdgeInsets.all(8),
              child: _Tab1Table(rows: rows, sz: sz)),
      ]),
    );
  }
}

class _R1 {
  final int zi; final Map z; final Map? s; final int? sGlobal;
  final List zOff; final String gpNames, thanas;
  const _R1({required this.zi, required this.z, required this.s,
      required this.sGlobal, required this.zOff,
      required this.gpNames, required this.thanas});
}

class _Tab1Table extends StatelessWidget {
  final List<_R1> rows; final Map sz;
  const _Tab1Table({required this.rows, required this.sz});

  static const _ws = <int, double>{
    0: 54, 1: 40, 2: 155, 3: 110, 4: 44, 5: 165, 6: 115, 7: 230, 8: 88,
  };

  @override
  Widget build(BuildContext context) {
    final totalW = _ws.values.fold(0.0, (a, b) => a + b);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: totalW),
        child: Column(children: [
          _header(),
          ...rows.asMap().entries.map((e) => _row(e.key, rows, sz)),
        ]),
      ),
    );
  }

  Widget _header() {
    const labels = [
      'सुपर\nजोन', 'जोन', 'जोनल अधिकारी\n/ जोनल पुलिस\nअधिकारी',
      'मुख्यालय', 'सैक्टर\nसं.', 'सैक्टर पुलिस\nअधिकारी का नाम',
      'मुख्यालय', 'ग्राम पंचायत का नाम', 'थाना',
    ];
    return Container(
      decoration: BoxDecoration(color: const Color(0xFFF5EAD0),
          border: Border.all(color: _kBorder, width: 0.7)),
      child: Row(children: List.generate(9, (i) => Container(
        width: _ws[i], padding: const EdgeInsets.all(6),
        decoration: _cellDec(right: i < 8, bottom: false),
        child: Text(labels[i],
            style: const TextStyle(color: _kDark,
                fontWeight: FontWeight.w800, fontSize: 10),
            textAlign: TextAlign.center),
      ))),
    );
  }

  Widget _row(int i, List<_R1> rows, Map sz) {
    final r = rows[i];
    final isFirstInZone = i == 0 || rows[i-1].zi != r.zi;
    final bg = r.zi.isOdd ? Colors.white : const Color(0xFFFFFDF7);
    final zOffText = r.zOff.isNotEmpty
        ? r.zOff.map((o) {
            final name = (o['name'] ?? '').toString().trim();
            final rank = (o['user_rank'] ?? '').toString().trim();
            final mob  = (o['mobile'] ?? '').toString().trim();
            return [name, if (rank.isNotEmpty) rank, if (mob.isNotEmpty) 'मो:$mob']
                .join('\n');
          }).join('\n---\n')
        : '—';
    final sOff  = (r.s?['officers'] as List? ?? []);
    final sText = sOff.isNotEmpty
        ? sOff.map((o) {
            final name = (o['name']      ?? '').toString().trim();
            final rank = (o['user_rank'] ?? '').toString().trim();
            final mob  = (o['mobile']    ?? '').toString().trim();
            return [name, if (rank.isNotEmpty) rank, if (mob.isNotEmpty) 'मो:$mob']
                .join('\n');
          }).join('\n---\n')
        : '—';
    final sHq = r.s != null
        ? ((r.s!['hq'] ?? r.s!['hq_address'] ?? r.s!['hqAddress'] ?? '—').toString())
        : '—';

    return Container(
      decoration: BoxDecoration(color: bg,
          border: const Border(
            left:   BorderSide(color: _kBorder, width: 0.7),
            right:  BorderSide(color: _kBorder, width: 0.7),
            bottom: BorderSide(color: _kBorder, width: 0.7),
          )),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: _ws[0], height: 48,
            decoration: _cellDec(right: true, bottom: false),
            child: Center(child: i == 0
                ? RotatedBox(quarterTurns: 3,
                    child: Text('सुपर जोन–${sz['name']}',
                        style: const TextStyle(color: _kPrimary,
                            fontSize: 9, fontWeight: FontWeight.w700)))
                : const SizedBox())),
        Container(width: _ws[1], padding: const EdgeInsets.all(6),
            decoration: _cellDec(right: true, bottom: false),
            child: isFirstInZone
                ? Center(child: Text('${r.zi + 1}',
                    style: const TextStyle(color: _kPrimary,
                        fontWeight: FontWeight.w900, fontSize: 14)))
                : const SizedBox()),
        Container(width: _ws[2], padding: const EdgeInsets.all(6),
            decoration: _cellDec(right: true, bottom: false),
            child: isFirstInZone
                ? Text(zOffText, style: const TextStyle(fontSize: 11, color: _kDark))
                : const SizedBox()),
        Container(width: _ws[3], padding: const EdgeInsets.all(6),
            decoration: _cellDec(right: true, bottom: false),
            child: isFirstInZone
                ? Text('${r.z['hq_address'] ?? r.z['hqAddress'] ?? '—'}',
                    style: const TextStyle(fontSize: 11, color: _kDark))
                : const SizedBox()),
        Container(width: _ws[4], padding: const EdgeInsets.all(6),
            decoration: _cellDec(right: true, bottom: false),
            child: r.sGlobal != null
                ? Center(child: Text('${r.sGlobal}',
                    style: const TextStyle(color: _kGreen,
                        fontWeight: FontWeight.w800, fontSize: 12)))
                : const SizedBox()),
        Container(width: _ws[5], padding: const EdgeInsets.all(6),
            decoration: _cellDec(right: true, bottom: false),
            child: Text(sText, style: const TextStyle(fontSize: 11, color: _kDark))),
        Container(width: _ws[6], padding: const EdgeInsets.all(6),
            decoration: _cellDec(right: true, bottom: false),
            child: Text(sHq, style: const TextStyle(fontSize: 11, color: _kDark))),
        Container(width: _ws[7], padding: const EdgeInsets.all(6),
            decoration: _cellDec(right: true, bottom: false),
            child: Text(r.gpNames, style: const TextStyle(fontSize: 11, color: _kDark))),
        Container(width: _ws[8], padding: const EdgeInsets.all(6),
            decoration: _cellDec(right: false, bottom: false),
            child: Text(r.thanas, style: const TextStyle(fontSize: 11, color: _kDark))),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 2 CARD
// ══════════════════════════════════════════════════════════════════════════════
class _Tab2Card extends StatelessWidget {
  final Map sz, z;
  final bool isHistory;
  final VoidCallback onEditZone, onDeleteZone, onAddSector, onManageZoneOfficers;
  final void Function(Map) onEditSector, onAddGP, onManageSectorOfficers;
  final Future<void> Function(Map) onDeleteSector;
  const _Tab2Card({
    required this.sz, required this.z, required this.isHistory,
    required this.onEditZone, required this.onDeleteZone,
    required this.onAddSector, required this.onManageZoneOfficers,
    required this.onEditSector, required this.onDeleteSector,
    required this.onAddGP, required this.onManageSectorOfficers,
  });

  @override
  Widget build(BuildContext context) {
    final sectors = z['sectors'] as List? ?? [];
    final zOff    = z['officers'] as List? ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: [BoxShadow(color: _kGreen.withOpacity(0.08),
            blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF186A3B), Color(0xFF239B56)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('जोन: ${z['name']}',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 14, fontWeight: FontWeight.w800)),
                Text('सुपर जोन: ${sz['name']}  |  ब्लॉक: ${sz['block'] ?? '—'}',
                    style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ])),
              if (!isHistory) ...[
                _IAB(icon: Icons.person_add_outlined, color: Colors.teal[200]!,
                    onTap: onManageZoneOfficers, tooltip: 'अधिकारी'),
                _IAB(icon: Icons.add_circle_outline, color: _kAccent,
                    onTap: onAddSector, tooltip: 'सैक्टर जोड़ें'),
                _IAB(icon: Icons.edit_outlined, color: _kAccent, onTap: onEditZone),
                _IAB(icon: Icons.delete_outline, color: Colors.red[300]!, onTap: onDeleteZone),
              ],
            ]),
            if (zOff.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 4),
              const Text('जोनल अधिकारी:',
                  style: TextStyle(color: Colors.white70, fontSize: 10)),
              ...zOff.map((o) => Text(
                '• ${o['name'] ?? '—'}  ${o['user_rank'] ?? ''}'
                '  PNO: ${o['pno'] ?? '—'}  मो: ${o['mobile'] ?? '—'}',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              )),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: _Tab2Table(
              sectors: sectors,
              isHistory: isHistory,
              onEdit: onEditSector,
              onDelete: onDeleteSector,
              onAddGP: onAddGP,
              onManageOfficers: onManageSectorOfficers),
        ),
      ]),
    );
  }
}

class _Tab2Table extends StatelessWidget {
  final List sectors;
  final bool isHistory;
  final void Function(Map) onEdit, onAddGP, onManageOfficers;
  final Future<void> Function(Map) onDelete;
  const _Tab2Table({required this.sectors, required this.isHistory,
      required this.onEdit, required this.onDelete,
      required this.onAddGP, required this.onManageOfficers});

  static const _ws = <int, double>{
    0: 40, 1: 180, 2: 180, 3: 120, 4: 180, 5: 90, 6: 88,
  };

  @override
  Widget build(BuildContext context) {
    final totalW = _ws.values.fold(0.0, (a, b) => a + b);
    final rows = <Map>[];
    int sSeq = 0;
    for (final s in sectors) {
      sSeq++;
      final gps    = s['panchayats'] as List? ?? [];
      final sOff   = s['officers']   as List? ?? [];
      final magStr = sOff.isNotEmpty
          ? '${sOff[0]['name'] ?? ''}\n'
            '${sOff[0]['user_rank'] ?? ''}\n'
            '${sOff[0]['mobile'] ?? ''}'
          : '—';
      final polStr = sOff.length > 1
          ? '${sOff[1]['name'] ?? ''}\n'
            '${sOff[1]['user_rank'] ?? ''}\n'
            '${sOff[1]['mobile'] ?? ''}'
          : magStr;

      if (gps.isEmpty) {
        rows.add({'s': s, 'sSeq': sSeq, 'mag': magStr,
            'pol': polStr, 'gp': null, 'first': true});
      } else {
        for (int gi = 0; gi < gps.length; gi++) {
          rows.add({
            's': s, 'sSeq': sSeq,
            'mag': gi == 0 ? magStr : '',
            'pol': gi == 0 ? polStr : '',
            'gp': gps[gi], 'first': gi == 0,
          });
        }
      }
    }

    if (rows.isEmpty) return const _Empty(text: 'कोई सैक्टर नहीं');

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: totalW),
        child: Column(children: [
          Container(
            decoration: BoxDecoration(color: const Color(0xFFE8F5E9),
                border: Border.all(color: _kBorder, width: 0.7)),
            child: Row(children: [
              _th(0, 'सैक्टर\nसं.'),
              _th(1, 'सैक्टर मजिस्ट्रेट\n(नाम/पद/मोबाइल)'),
              _th(2, 'सैक्टर पुलिस अधिकारी\n(नाम/पद/मोबाइल)'),
              _th(3, 'ग्राम पंचायत'),
              _th(4, 'मतदेय स्थल\n(केन्द्र)'),
              _th(5, 'मतदान\nकेन्द्र'),
              _th(6, 'एक्शन', last: true),
            ]),
          ),
          ...rows.asMap().entries.map((e) {
            final i     = e.key; final r = e.value;
            final gp    = r['gp']    as Map?;
            final s     = r['s']     as Map;
            final first = r['first'] as bool;
            final bg    = i.isEven ? Colors.white : const Color(0xFFF1F8E9);

            final centers  = gp != null ? (gp['centers'] as List? ?? []) : <Map>[];
            final sthalStr = centers.map((c) => '${c['name']}').join('\n');
            final kStr = centers.map((c) {
              final kendras = c['kendras'];
              if (kendras is List && kendras.isNotEmpty) {
                return kendras.map((k) => '${k['room_number']}').join(', ');
              }
              return '1';
            }).where((e) => e.isNotEmpty).join(' | ');

            return Container(
              decoration: BoxDecoration(color: bg,
                  border: const Border(
                    left:   BorderSide(color: _kBorder, width: 0.7),
                    right:  BorderSide(color: _kBorder, width: 0.7),
                    bottom: BorderSide(color: _kBorder, width: 0.7),
                  )),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _cell(0, first
                    ? Text('${r['sSeq']}',
                        style: const TextStyle(color: _kGreen,
                            fontWeight: FontWeight.w900, fontSize: 14),
                        textAlign: TextAlign.center)
                    : const SizedBox()),
                _cell(1, first
                    ? Text('${r['mag']}',
                        style: const TextStyle(fontSize: 11, color: _kDark))
                    : const SizedBox()),
                _cell(2, first
                    ? Text('${r['pol']}',
                        style: const TextStyle(fontSize: 11, color: _kDark))
                    : const SizedBox()),
                _cell(3, Text('${gp?['name'] ?? '—'}',
                    style: const TextStyle(fontSize: 11, color: _kDark))),
                _cell(4, Text(sthalStr.isEmpty ? '—' : sthalStr,
                    style: const TextStyle(fontSize: 11, color: _kDark))),
                _cell(5, Text(kStr.isEmpty ? '—' : kStr,
                    style: const TextStyle(fontSize: 11, color: _kDark))),
                _cell(6, isHistory
                    ? const Center(child: Icon(Icons.lock_outline,
                        size: 14, color: _kSubtle))
                    : Wrap(spacing: 2, runSpacing: 2, children: [
                        _IAB(icon: Icons.person_add_outlined, color: Colors.teal,
                            tooltip: 'अधिकारी', onTap: () => onManageOfficers(s)),
                        _IAB(icon: Icons.add, color: _kGreen,
                            onTap: () => onAddGP(s), tooltip: 'GP जोड़ें'),
                        _IAB(icon: Icons.edit_outlined, color: _kGreen,
                            onTap: () => onEdit(s)),
                        _IAB(icon: Icons.delete_outline, color: _kRed,
                            onTap: () => onDelete(s)),
                      ]), last: true),
              ]),
            );
          }),
        ]),
      ),
    );
  }

  Widget _th(int i, String t, {bool last = false}) => Container(
    width: _ws[i], padding: const EdgeInsets.all(6),
    decoration: _cellDec(right: !last, bottom: false,
        bg: const Color(0xFFE8F5E9)),
    child: Text(t, style: const TextStyle(color: Color(0xFF1B5E20),
        fontWeight: FontWeight.w800, fontSize: 10),
        textAlign: TextAlign.center),
  );

  Widget _cell(int i, Widget child, {bool last = false}) => Container(
    width: _ws[i], padding: const EdgeInsets.all(6),
    decoration: _cellDec(right: !last, bottom: false), child: child,
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 3 CARD
// ══════════════════════════════════════════════════════════════════════════════
class _Tab3Card extends StatelessWidget {
  final Map sz, z, s, gp;
  final bool isHistory;
  final VoidCallback onAddCenter;
  final void Function(Map) onEditCenter, onAddKendra, onManageStaff;
  final Future<void> Function(Map) onDeleteCenter, onDeleteKendra;
  const _Tab3Card({required this.sz, required this.z, required this.s,
      required this.gp, required this.isHistory,
      required this.onAddCenter, required this.onEditCenter,
      required this.onDeleteCenter, required this.onAddKendra,
      required this.onDeleteKendra, required this.onManageStaff});

  @override
  Widget build(BuildContext context) {
    final centers = gp['centers'] as List? ?? [];
    int totalKendra = 0;
    for (final c in centers) {
      final k = c['kendras'] as List? ?? [];
      totalKendra += k.isEmpty ? 1 : k.length;
    }

    // ONE ROW PER CENTER (matdan_sthal) — kendra room numbers joined in one cell
    final rows = <Map>[];
    int sthalNo = 1;
    for (final c in centers) {
      final kendras = c['kendras'] as List? ?? [];
      // e.g. "101, 102, 103" or empty when no rooms defined
      final roomNos = kendras.isEmpty
          ? ''
          : kendras.map((k) => '${k['room_number']}').join(', ');
      rows.add({
        'c':       c,
        'sthalNo': sthalNo,    // simple serial shown in both col0 and col2
        'roomNos': roomNos,    // combined room numbers shown inside name cell
      });
      sthalNo++;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: [BoxShadow(color: _kPurple.withOpacity(0.08),
            blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF6C3483), Color(0xFF8E44AD)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('बूथ ड्यूटी – ब्लॉक ${sz['block'] ?? sz['name']}',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 14, fontWeight: FontWeight.w800)),
                Wrap(spacing: 12, children: [
                  Text('ग्राम पंचायत: ${gp['name']}',
                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  Text('सैक्टर: ${s['name']}',
                      style: const TextStyle(color: Colors.white60, fontSize: 11)),
                  Text('जोन: ${z['name']}',
                      style: const TextStyle(color: Colors.white60, fontSize: 11)),
                ]),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                _GoldChip('मतदेय स्थल: ${centers.length}'),
                const SizedBox(height: 4),
                _GoldChip('मतदान केन्द्र: $totalKendra'),
              ]),
            ]),
            if (!isHistory) ...[
              const SizedBox(height: 6),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.2),
                    foregroundColor: Colors.white, elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('मतदेय स्थल जोड़ें',
                    style: TextStyle(fontSize: 11)),
                onPressed: onAddCenter,
              ),
            ],
          ]),
        ),

        if (rows.isEmpty)
          const Padding(padding: EdgeInsets.all(16),
              child: _Empty(text: 'कोई मतदेय स्थल नहीं'))
        else
          Padding(
            padding: const EdgeInsets.all(8),
            child: _Tab3Table(
                rows: rows, z: z, s: s, gp: gp,
                isHistory: isHistory,
                onEditCenter:   onEditCenter,
                onDeleteCenter: onDeleteCenter,
                onAddKendra:    onAddKendra,
                onDeleteKendra: onDeleteKendra,
                onManageStaff:  onManageStaff),
          ),
      ]),
    );
  }
}

class _Tab3Table extends StatelessWidget {
  final List<Map> rows; final Map z, s, gp;
  final bool isHistory;
  final void Function(Map) onEditCenter, onAddKendra, onManageStaff;
  final Future<void> Function(Map) onDeleteCenter, onDeleteKendra;
  const _Tab3Table({required this.rows, required this.z, required this.s,
      required this.gp, required this.isHistory,
      required this.onEditCenter, required this.onDeleteCenter,
      required this.onAddKendra, required this.onDeleteKendra,
      required this.onManageStaff});

  static const _ws = <int, double>{
    0: 44,   // kendra serial (1, 2, 3…)
    1: 170,  // center name + room nos + type badge
    2: 44,   // sthal serial
    3: 150,  // sthal name + address
    4: 54,   // zone
    5: 58,   // sector
    6: 80,   // thana
    7: 200,  // duty officer
    8: 115,  // mobile
    9: 50,   // bus no
    10: 88,  // actions
  };

  @override
  Widget build(BuildContext context) {
    final totalW = _ws.values.fold(0.0, (a, b) => a + b);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: totalW),
        child: Column(children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(color: const Color(0xFFF3E5F5),
                border: Border.all(color: _kBorder, width: 0.7)),
            child: Row(children: [
              _th(0, 'मतदान\nकेन्द्र\nसंख्या'),
              _th(1, 'मतदान केन्द्र\nका नाम'),
              _th(2, 'मतदेय\nस्थल सं.'),
              _th(3, 'मतदान स्थल\nका नाम'),
              _th(4, 'जोन\nसंख्या'),
              _th(5, 'सैक्टर\nसंख्या'),
              _th(6, 'थाना'),
              _th(7, 'ड्यूटी पर लगाया\nपुलिस का नाम'),
              _th(8, 'मोबाईल\nनम्बर'),
              _th(9, 'बस\nनं.'),
              _th(10, 'एक्शन', last: true),
            ]),
          ),
          // ── One row per matdan_sthal (center) ───────────────────────────
          ...rows.asMap().entries.map((e) {
            final i   = e.key;
            final r   = e.value;
            final c   = r['c'] as Map;
            final bg  = i.isEven ? Colors.white : const Color(0xFFFDF4FF);

            // Simple serial number for this center (1, 2, 3…)
            // Room numbers shown inside the center name cell
            final roomNos = (r['roomNos'] as String? ?? '');
            final nameWithRooms = roomNos.isNotEmpty
                ? '${c['name']}\nक.नं. $roomNos'
                : '${c['name']}';

            final typeColor = _sensitivityColor(c['center_type'] as String?);

            final duty  = c['duty_officers'] as List? ?? [];
            final dText = duty.isNotEmpty
                ? duty.map((d) =>
                    '${d['name'] ?? ''}  ${d['pno'] ?? ''}\n'
                    '${d['user_rank'] ?? ''}').join('\n')
                : '—';
            final mText = duty.isNotEmpty
                ? duty.map((d) => '${d['mobile'] ?? ''}')
                    .where((m) => m.isNotEmpty).join('\n')
                : '—';

            return Container(
              decoration: BoxDecoration(color: bg,
                  border: const Border(
                    left:   BorderSide(color: _kBorder, width: 0.7),
                    right:  BorderSide(color: _kBorder, width: 0.7),
                    bottom: BorderSide(color: _kBorder, width: 0.7),
                  )),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // col 0 — simple serial number
                _cell(0, Center(child: Text('${r['sthalNo']}',
                    style: const TextStyle(color: _kPurple,
                        fontWeight: FontWeight.w800, fontSize: 13)))),
                // col 1 — center name + room nos + type badge
                _cell(1, Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(nameWithRooms,
                      style: const TextStyle(color: _kDark, fontSize: 11)),
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                        color: typeColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: typeColor.withOpacity(0.4))),
                    child: Text('${c['center_type'] ?? 'C'}',
                        style: TextStyle(color: typeColor,
                            fontSize: 10, fontWeight: FontWeight.w800))),
                ])),
                // col 2 — sthal serial number
                _cell(2, Center(child: Text('${r['sthalNo']}',
                    style: const TextStyle(color: _kDark,
                        fontWeight: FontWeight.w700, fontSize: 12)))),
                // col 3 — sthal name + address
                _cell(3, Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${c['name']}',
                      style: const TextStyle(color: _kDark, fontSize: 11)),
                  if ((c['address'] ?? '').toString().isNotEmpty)
                    Text('${c['address']}',
                        style: const TextStyle(color: _kSubtle, fontSize: 9)),
                ])),
                // col 4 — zone
                _cell(4, Center(child: Text('${z['name']}',
                    style: const TextStyle(color: _kDark, fontSize: 10)))),
                // col 5 — sector
                _cell(5, Center(child: Text('${s['name']}',
                    style: const TextStyle(color: _kDark, fontSize: 10)))),
                // col 6 — thana
                _cell(6, Text('${c['thana'] ?? gp['thana'] ?? '—'}',
                    style: const TextStyle(color: _kDark, fontSize: 11))),
                // col 7 — duty officer
                _cell(7, Text(dText,
                    style: const TextStyle(color: _kDark, fontSize: 11))),
                // col 8 — mobile
                _cell(8, Text(mText,
                    style: const TextStyle(color: _kDark, fontSize: 11,
                        fontFamily: 'monospace'))),
                // col 9 — bus no
                _cell(9, Center(child: Text('${c['bus_no'] ?? '—'}',
                    style: const TextStyle(color: _kDark,
                        fontWeight: FontWeight.w700, fontSize: 11)))),
                // col 10 — actions
                _cell(10, isHistory
                    ? const Center(child: Icon(Icons.lock_outline,
                        size: 14, color: _kSubtle))
                    : Wrap(spacing: 2, runSpacing: 2, children: [
                        _IAB(icon: Icons.people_alt_outlined, color: _kGreen,
                            tooltip: 'स्टाफ', onTap: () => onManageStaff(c)),
                        _IAB(icon: Icons.add_box_outlined, color: _kPrimary,
                            tooltip: 'कक्ष जोड़ें', onTap: () => onAddKendra(c)),
                        _IAB(icon: Icons.edit_outlined, color: _kPurple,
                            onTap: () => onEditCenter(c)),
                        _IAB(icon: Icons.delete_outline, color: _kRed,
                            onTap: () => onDeleteCenter(c)),
                      ]), last: true),
              ]),
            );
          }),
        ]),
      ),
    );
  }

  Widget _th(int i, String t, {bool last = false}) => Container(
    width: _ws[i], padding: const EdgeInsets.all(6),
    decoration: _cellDec(right: !last, bottom: false,
        bg: const Color(0xFFF3E5F5)),
    child: Text(t, style: const TextStyle(color: _kPurple,
        fontWeight: FontWeight.w800, fontSize: 9.5),
        textAlign: TextAlign.center),
  );

  Widget _cell(int i, Widget child, {bool last = false}) => Container(
    width: _ws[i], padding: const EdgeInsets.all(6),
    decoration: _cellDec(right: !last, bottom: false), child: child,
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// TINY SHARED WIDGETS
// ══════════════════════════════════════════════════════════════════════════════
class _DI { final String value, label; const _DI(this.value, this.label); }

class _FDrop extends StatelessWidget {
  final String label, placeholder; final String? value;
  final List<_DI> items; final ValueChanged<String?> onChanged;
  const _FDrop({required this.label, required this.placeholder,
      required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: _kSubtle,
            fontSize: 9, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          constraints: const BoxConstraints(minWidth: 110, maxWidth: 165),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: value != null ? _kPrimary : _kBorder, width: 1.5)),
          child: DropdownButton<String>(
            value: value, underline: const SizedBox(), isExpanded: true,
            hint: Text(placeholder,
                style: const TextStyle(color: _kSubtle, fontSize: 12),
                overflow: TextOverflow.ellipsis),
            style: const TextStyle(color: _kDark, fontSize: 12),
            dropdownColor: Colors.white,
            items: [
              DropdownMenuItem<String>(
                  value: null,
                  child: Text(placeholder,
                      style: const TextStyle(color: _kSubtle, fontSize: 12))),
              ...items.map((i) => DropdownMenuItem<String>(
                  value: i.value,
                  child: Text(i.label,
                      style: const TextStyle(color: _kDark, fontSize: 12),
                      overflow: TextOverflow.ellipsis))),
            ],
            onChanged: onChanged,
          ),
        ),
      ]);
}

class _IAB extends StatelessWidget {
  final IconData icon; final Color color; final VoidCallback onTap;
  final String? tooltip;
  const _IAB({required this.icon, required this.color,
      required this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? '',
    child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(padding: const EdgeInsets.all(4),
            child: Icon(icon, color: color, size: 18))),
  );
}

class _GoldChip extends StatelessWidget {
  final String label;
  const _GoldChip(this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(7)),
    child: Text(label, style: const TextStyle(
        color: _kAccent, fontSize: 11, fontWeight: FontWeight.w700)),
  );
}

class _MC extends StatelessWidget {
  final String label; final Color color;
  const _MC(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(
        color: color, fontSize: 10, fontWeight: FontWeight.w700)),
  );
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty({required this.text});
  @override
  Widget build(BuildContext context) => Center(child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.inbox_outlined, size: 44, color: _kSubtle),
      const SizedBox(height: 8),
      Text(text, style: const TextStyle(color: _kSubtle, fontSize: 13)),
    ],
  ));
}

class _ErrorView extends StatelessWidget {
  final String error; final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, size: 48, color: _kRed),
      const SizedBox(height: 10),
      const Text('डेटा लोड करने में त्रुटि',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
              color: _kDark)),
      const SizedBox(height: 6),
      Text(error, style: const TextStyle(color: _kSubtle, fontSize: 12),
          textAlign: TextAlign.center),
      const SizedBox(height: 14),
      ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
        onPressed: onRetry,
        icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
        label: const Text('पुनः प्रयास',
            style: TextStyle(color: Colors.white)),
      ),
    ]),
  ));
}