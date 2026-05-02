import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';

// ─── palette ──────────────────────────────────────────────────────────────────
const kBg      = Color(0xFFFDF6E3);
const kSurface = Color(0xFFF5E6C8);
const kPrimary = Color(0xFF8B6914);
const kAccent  = Color(0xFFB8860B);
const kDark    = Color(0xFF4A3000);
const kSubtle  = Color(0xFFAA8844);
const kBorder  = Color(0xFFD4A843);
const kError   = Color(0xFFC0392B);
const kSuccess = Color(0xFF2D6A1E);
const kInfo    = Color(0xFF1A5276);

const kArmedColor   = Color(0xFF6A1B9A);
const kUnarmedColor = Color(0xFF1A5276);

const _ctLabel = {
  'A++': 'अत्यति संवेदनशील',
  'A':   'अति संवेदनशील',
  'B':   'संवेदनशील',
  'C':   'सामान्य',
};

const _pageLimit   = 50;
const _staffLimit  = 30;
const _dutiesLimit = 30;

enum _ArmedFilter { all, armed, unarmed }

// ══════════════════════════════════════════════════════════════════════════════
//  Armed detection — single source of truth, handles bool / int / String
// ══════════════════════════════════════════════════════════════════════════════
bool _parseArmed(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is int)  return v == 1;
  if (v is String) {
    final s = v.trim().toLowerCase();
    return s == '1' || s == 'true' || s == 'yes';
  }
  return false;
}

// ══════════════════════════════════════════════════════════════════════════════
//  BoothPage
// ══════════════════════════════════════════════════════════════════════════════
class BoothPage extends StatefulWidget {
  const BoothPage({super.key});
  @override
  State<BoothPage> createState() => _BoothPageState();
}

class _BoothPageState extends State<BoothPage> {
  final List<Map> _centers = [];
  int    _page    = 1;
  int    _total   = 0;
  bool   _loading = false;
  bool   _hasMore = true;
  String _q       = '';
  Timer? _debounce;
  final _searchCtrl = TextEditingController();
  final _scroll     = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _searchCtrl.addListener(_onSearchChanged);
    _loadCenters(reset: true);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
      _loadCenters();
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = _searchCtrl.text.trim();
      if (q != _q) { _q = q; _loadCenters(reset: true); }
    });
  }

  Future<void> _loadCenters({bool reset = false}) async {
    if (_loading) return;
    if (!reset && !_hasMore) return;
    if (reset) setState(() { _centers.clear(); _page = 1; _hasMore = true; });
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get(
        '/admin/centers/all?page=$_page&limit=$_pageLimit'
        '&q=${Uri.encodeComponent(_q)}',
        token: token,
      );
      final wrapper = (res['data'] as Map<String, dynamic>?) ?? {};
      final items   = List<Map>.from((wrapper['data']       as List?) ?? []);
      final total   = (wrapper['total']      as num?)?.toInt() ?? 0;
      final pages   = (wrapper['totalPages'] as num?)?.toInt() ?? 1;
      if (!mounted) return;
      setState(() {
        _centers.addAll(items);
        _total   = total;
        _hasMore = _page < pages;
        _page++;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack('लोड विफल: $e', error: true);
      }
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? kError : kSuccess,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showDutiesDialog(Map center) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _DutiesDialog(
        center: center,
        onAssign: (ctx) {
          Navigator.pop(ctx);
          _showAssignDialog(center);
        },
        onDutyRemoved: () => _loadCenters(reset: true),
      ),
    );
  }

  void _showAssignDialog(Map center) {
    final isLocked = _parseArmed(center['isLocked']) ||
        (center['is_locked'] as num? ?? 0) == 1;
    if (isLocked) {
      _snack('यह Super Zone locked है — बदलाव संभव नहीं', error: true);
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _AssignDialog(
        center: center,
        onAssigned: () => _loadCenters(reset: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        color: kSurface,
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _searchCtrl,
          style: const TextStyle(color: kDark, fontSize: 13),
          decoration: _searchDec(
            'नाम, थाना, GP, सेक्टर, जोन से खोजें...',
            onClear: _q.isNotEmpty
                ? () { _searchCtrl.clear(); _q = ''; _loadCenters(reset: true); }
                : null,
          ),
        ),
      ),
      Container(
        color: kBg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          _pill('$_total बूथ', kPrimary),
          const Spacer(),
          if (_loading && _centers.isNotEmpty)
            const SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary)),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18, color: kSubtle),
            onPressed: () => _loadCenters(reset: true),
            padding: EdgeInsets.zero, constraints: const BoxConstraints()),
        ]),
      ),
      Expanded(
        child: _centers.isEmpty && _loading
            ? const Center(child: CircularProgressIndicator(color: kPrimary))
            : _centers.isEmpty
                ? _emptyState(
                    _q.isNotEmpty ? '"$_q" के लिए कोई बूथ नहीं' : 'कोई बूथ नहीं मिला',
                    Icons.location_off_outlined)
                : RefreshIndicator(
                    onRefresh: () => _loadCenters(reset: true),
                    color: kPrimary,
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 80),
                      itemCount: _centers.length + (_hasMore ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i >= _centers.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: SizedBox(width: 22, height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary))));
                        }
                        return RepaintBoundary(
                          child: _CenterCard(
                            center: _centers[i],
                            onTap: () => _showDutiesDialog(_centers[i]),
                          ),
                        );
                      },
                    ),
                  ),
      ),
    ]);
  }

  Widget _emptyState(String msg, IconData icon) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 48, color: kSubtle.withOpacity(0.4)),
      const SizedBox(height: 12),
      Text(msg, style: const TextStyle(color: kSubtle, fontSize: 14), textAlign: TextAlign.center),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  Center card
// ══════════════════════════════════════════════════════════════════════════════
class _CenterCard extends StatelessWidget {
  final Map center;
  final VoidCallback onTap;
  const _CenterCard({required this.center, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final type       = '${center['centerType'] ?? 'C'}';
    final dutyCount  = (center['dutyCount'] ?? 0) as int;
    final boothCount = (center['boothCount'] ?? 1) as int;
    final tColor     = _typeColor(type);
    final rule       = center['boothRule'] as Map?;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder.withOpacity(0.4)),
          boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.05),
              blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Main row ────────────────────────────────────────────────────
          Row(children: [

            // Sensitivity type + booth count column
            Container(
              width: 62,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: tColor.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
                border: Border(right: BorderSide(color: tColor.withOpacity(0.3))),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                // Sensitivity badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: tColor.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(type,
                      style: TextStyle(color: tColor,
                          fontSize: type == 'A++' ? 11 : 15,
                          fontWeight: FontWeight.w900)),
                ),
                const SizedBox(height: 6),
                // Booth count — prominent
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.how_to_vote_outlined, size: 11, color: tColor),
                  const SizedBox(width: 2),
                  Text('$boothCount', style: TextStyle(
                      color: tColor, fontSize: 14, fontWeight: FontWeight.w900)),
                ]),
                Text('बूथ', style: TextStyle(
                    color: tColor.withOpacity(0.7), fontSize: 9,
                    fontWeight: FontWeight.w600)),
              ]),
            ),

            // Center info
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${center['name']}',
                    style: const TextStyle(color: kDark, fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 4),
                Row(children: [
                  Flexible(child: _tagSmall(Icons.local_police_outlined, '${center['thana']}')),
                  const SizedBox(width: 10),
                  Flexible(child: _tagSmall(Icons.account_balance_outlined, '${center['gpName']}')),
                ]),
                const SizedBox(height: 2),
                _tagSmall(Icons.layers_outlined,
                    '${center['sectorName']} › ${center['zoneName']} › ${center['superZoneName']}'),
                if ((center['blockName'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  _tagSmall(Icons.location_city_outlined, 'ब्लॉक: ${center['blockName']}'),
                ],
                if ((center['busNo'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  _tagSmall(Icons.directions_bus_outlined, 'बस: ${center['busNo']}'),
                ],
              ]),
            )),

            // Duty count badge
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: dutyCount > 0 ? kSuccess.withOpacity(0.1) : kSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: dutyCount > 0 ? kSuccess.withOpacity(0.4) : kBorder.withOpacity(0.4)),
                ),
                child: Column(children: [
                  Text('$dutyCount', style: TextStyle(
                      color: dutyCount > 0 ? kSuccess : kSubtle,
                      fontSize: 18, fontWeight: FontWeight.w900)),
                  Text('स्टाफ', style: TextStyle(
                      color: dutyCount > 0 ? kSuccess : kSubtle, fontSize: 10)),
                ]),
              ),
            ),
          ]),

          // ── Rule summary strip ───────────────────────────────────────────
          if (rule != null) _RuleSummaryStrip(rule: rule, typeColor: tColor),
        ]),
      ),
    );
  }

  Widget _tagSmall(IconData icon, String text) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: kSubtle),
        const SizedBox(width: 3),
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: kSubtle, fontSize: 11))),
      ]);
}

// ── Rule summary strip ────────────────────────────────────────────────────────
class _RuleSummaryStrip extends StatelessWidget {
  final Map  rule;
  final Color typeColor;
  const _RuleSummaryStrip({required this.rule, required this.typeColor});

  int _n(dynamic v) => ((v ?? 0) as num).toInt();

  @override
  Widget build(BuildContext context) {
    final siA  = _n(rule['siArmedCount']);
    final siU  = _n(rule['siUnarmedCount']);
    final hcA  = _n(rule['hcArmedCount']);
    final hcU  = _n(rule['hcUnarmedCount']);
    final cA   = _n(rule['constArmedCount']);
    final cU   = _n(rule['constUnarmedCount']);
    final auxA = _n(rule['auxArmedCount']);
    final auxU = _n(rule['auxUnarmedCount']);
    final pac  = _n(rule['pacCount']);
    final total = siA + siU + hcA + hcU + cA + cU + auxA + auxU;

    if (total == 0 && pac == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      decoration: BoxDecoration(
        color: typeColor.withOpacity(0.04),
        borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
        border: Border(top: BorderSide(color: typeColor.withOpacity(0.15))),
      ),
      child: Row(children: [
        Icon(Icons.rule_outlined, size: 11, color: typeColor.withOpacity(0.7)),
        const SizedBox(width: 5),
        Text('मानक:', style: TextStyle(color: typeColor.withOpacity(0.7),
            fontSize: 10, fontWeight: FontWeight.w700)),
        const SizedBox(width: 6),
        Expanded(child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            if (siA + siU > 0) _chip('SI', siA, siU, typeColor),
            if (hcA + hcU > 0) _chip('HC', hcA, hcU, typeColor),
            if (cA + cU > 0)   _chip('CO', cA, cU, typeColor),
            if (auxA + auxU > 0) _chip('Aux', auxA, auxU, const Color(0xFFE65100)),
            if (pac > 0) _singleChip('PAC', pac, const Color(0xFF00695C)),
          ]),
        )),
        const SizedBox(width: 6),
        Text('कुल $total', style: TextStyle(color: typeColor,
            fontSize: 10, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _chip(String label, int armed, int unarmed, Color color) => Container(
    margin: const EdgeInsets.only(right: 5),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: color.withOpacity(0.25)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label:', style: TextStyle(
          color: color.withOpacity(0.8), fontSize: 9, fontWeight: FontWeight.w700)),
      if (armed > 0) ...[
        const SizedBox(width: 2),
        const Icon(Icons.gavel, size: 8, color: kArmedColor),
        Text('$armed', style: const TextStyle(
            color: kArmedColor, fontSize: 9, fontWeight: FontWeight.w900)),
      ],
      if (armed > 0 && unarmed > 0)
        Text('/', style: TextStyle(color: color.withOpacity(0.5), fontSize: 9)),
      if (unarmed > 0) ...[
        const Icon(Icons.shield_outlined, size: 8, color: kUnarmedColor),
        Text('$unarmed', style: const TextStyle(
            color: kUnarmedColor, fontSize: 9, fontWeight: FontWeight.w900)),
      ],
    ]),
  );

  Widget _singleChip(String label, int val, Color color) => Container(
    margin: const EdgeInsets.only(right: 5),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: color.withOpacity(0.25)),
    ),
    child: Text('$label: $val', style: TextStyle(
        color: color, fontSize: 9, fontWeight: FontWeight.w700)),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  Duties Dialog
// ══════════════════════════════════════════════════════════════════════════════
class _DutiesDialog extends StatefulWidget {
  final Map center;
  final void Function(BuildContext ctx) onAssign;
  final VoidCallback onDutyRemoved;
  const _DutiesDialog({
    required this.center,
    required this.onAssign,
    required this.onDutyRemoved,
  });
  @override
  State<_DutiesDialog> createState() => _DutiesDialogState();
}

class _DutiesDialogState extends State<_DutiesDialog> {
  final List<Map> _duties = [];
  int  _page    = 1;
  int  _total   = 0;
  bool _loading = false;
  bool _hasMore = true;
  _ArmedFilter _armedFilter = _ArmedFilter.all;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 150
        && !_loading && _hasMore) _load();
  }

  List<Map> get _filteredDuties {
    if (_armedFilter == _ArmedFilter.all) return _duties;
    return _duties.where((d) {
      final armed = _parseArmed(d['isArmed'] ?? d['is_armed']);
      return _armedFilter == _ArmedFilter.armed ? armed : !armed;
    }).toList();
  }

  int get _armedCount   => _duties.where((d) => _parseArmed(d['isArmed'] ?? d['is_armed'])).length;
  int get _unarmedCount => _duties.length - _armedCount;

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (!reset && !_hasMore) return;
    if (reset) setState(() { _duties.clear(); _page = 1; _hasMore = true; });
    setState(() => _loading = true);
    try {
      final token    = await AuthService.getToken();
      final centerId = widget.center['id'];
      final res = await ApiService.get(
        '/admin/duties?center_id=$centerId&page=$_page&limit=$_dutiesLimit',
        token: token,
      );
      final wrapper = (res['data'] as Map<String, dynamic>?) ?? {};
      final items   = List<Map>.from((wrapper['data']       as List?) ?? []);
      final total   = (wrapper['total']      as num?)?.toInt() ?? 0;
      final pages   = (wrapper['totalPages'] as num?)?.toInt() ?? 1;
      if (!mounted) return;
      setState(() {
        _duties.addAll(items);
        _total   = total;
        _hasMore = _page < pages;
        _page++;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeDuty(Map d) async {
    try {
      final token = await AuthService.getToken();
      await ApiService.delete('/admin/duties/${d['id']}', token: token);
      widget.onDutyRemoved();
      _load(reset: true);
      if (mounted) _snack('ड्यूटी हटा दी गई');
    } catch (e) {
      if (mounted) _snack('त्रुटि: $e', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? kError : kSuccess,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final center     = widget.center;
    final type       = '${center['centerType'] ?? 'C'}';
    final boothCount = (center['boothCount'] ?? 1) as int;
    final rule       = center['boothRule'] as Map?;
    final filtered   = _filteredDuties;
    final screenH    = MediaQuery.of(context).size.height;
    final isLocked   = (widget.center['isLocked'] == true) ||
                       (widget.center['is_locked'] as num? ?? 0) == 1;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 500, maxHeight: screenH * 0.88),
        child: Container(
          decoration: _dlgDec(),
          child: Column(mainAxisSize: MainAxisSize.min, children: [

            _DialogHeader(
              title: '${center['name']}',
              icon: Icons.location_on_outlined,
              onClose: () => Navigator.pop(context),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // Type + booth count row
                Row(children: [
                  _TypeBadge(type: type),
                  const SizedBox(width: 8),
                  // Booth count chip — prominent
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _typeColor(type).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _typeColor(type).withOpacity(0.4)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.how_to_vote_outlined, size: 13, color: _typeColor(type)),
                      const SizedBox(width: 4),
                      Text('$boothCount बूथ',
                          style: TextStyle(color: _typeColor(type),
                              fontSize: 12, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_ctLabel[type] ?? type,
                      style: const TextStyle(color: kSubtle, fontSize: 12,
                          fontWeight: FontWeight.w600))),
                  _countBadge(_total),
                ]),

                const SizedBox(height: 8),

                // Location chips
                Wrap(spacing: 10, runSpacing: 4, children: [
                  _infoChip(Icons.local_police_outlined,    '${center['thana']}'),
                  _infoChip(Icons.account_balance_outlined, '${center['gpName']}'),
                  _infoChip(Icons.map_outlined,   'सेक्टर: ${center['sectorName']}'),
                  _infoChip(Icons.layers_outlined, 'जोन: ${center['zoneName']}'),
                  _infoChip(Icons.public_outlined, 'SZ: ${center['superZoneName']}'),
                  if ((center['blockName'] ?? '').toString().isNotEmpty)
                    _infoChip(Icons.location_city_outlined, 'ब्लॉक: ${center['blockName']}'),
                  if ((center['busNo'] ?? '').toString().isNotEmpty)
                    _infoChip(Icons.directions_bus_outlined, 'बस: ${center['busNo']}'),
                ]),

                // Rule preview — inline detail
                if (rule != null) ...[
                  const SizedBox(height: 8),
                  _InlineRulePreview(rule: rule, typeColor: _typeColor(type)),
                ],

                const SizedBox(height: 10),

                _ArmedFilterBar(
                  current:      _armedFilter,
                  totalCount:   _duties.length,
                  armedCount:   _armedCount,
                  unarmedCount: _unarmedCount,
                  onChanged:    (f) => setState(() => _armedFilter = f),
                ),

                const SizedBox(height: 10),
              ]),
            ),

            const Divider(height: 1, color: kBorder),

            Expanded(
              child: _loading && _duties.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: kPrimary))
                  : filtered.isEmpty
                      ? Center(child: Column(
                          mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.people_outline, size: 40, color: kSubtle.withOpacity(0.5)),
                          const SizedBox(height: 10),
                          Text(
                            _duties.isEmpty
                                ? 'इस बूथ पर कोई स्टाफ नहीं'
                                : _armedFilter == _ArmedFilter.armed
                                    ? 'कोई सशस्त्र स्टाफ नहीं'
                                    : 'कोई निःशस्त्र स्टाफ नहीं',
                            style: const TextStyle(color: kSubtle, fontSize: 13)),
                        ]))
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          itemCount: filtered.length + (_hasMore ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i >= filtered.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(child: SizedBox(width: 18, height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary))));
                            }
                            return _DutyCard(
                              duty: filtered[i],
                              isLocked: isLocked,
                              onRemove: () => _removeDuty(filtered[i]),
                            );
                          },
                        ),
            ),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: kBorder))),
              child: Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: kSubtle,
                      side: const BorderSide(color: kBorder),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text('बंद करें'),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: isLocked ? null : () => widget.onAssign(context),
                  icon: const Icon(Icons.person_add_outlined, size: 16),
                  label: const Text('स्टाफ जोड़ें'),
                )),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Inline rule preview ───────────────────────────────────────────────────────
class _InlineRulePreview extends StatelessWidget {
  final Map rule;
  final Color typeColor;
  const _InlineRulePreview({required this.rule, required this.typeColor});

  int _n(dynamic v) => ((v ?? 0) as num).toInt();

  @override
  Widget build(BuildContext context) {
    final siA  = _n(rule['siArmedCount']);
    final siU  = _n(rule['siUnarmedCount']);
    final hcA  = _n(rule['hcArmedCount']);
    final hcU  = _n(rule['hcUnarmedCount']);
    final cA   = _n(rule['constArmedCount']);
    final cU   = _n(rule['constUnarmedCount']);
    final auxA = _n(rule['auxArmedCount']);
    final auxU = _n(rule['auxUnarmedCount']);
    final total = siA + siU + hcA + hcU + cA + cU + auxA + auxU;

    if (total == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: typeColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: typeColor.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.rule_outlined, size: 12, color: typeColor),
          const SizedBox(width: 5),
          Text('बूथ मानक (Rule)', style: TextStyle(color: typeColor,
              fontSize: 11, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text('कुल $total स्टाफ', style: TextStyle(color: typeColor,
              fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            if (siA > 0)  _miniChip('SI सशस्त्र',    siA, kArmedColor),
            if (siU > 0)  _miniChip('SI निःशस्त्र',  siU, kUnarmedColor),
            if (hcA > 0)  _miniChip('HC सशस्त्र',    hcA, kArmedColor),
            if (hcU > 0)  _miniChip('HC निःशस्त्र',  hcU, kUnarmedColor),
            if (cA  > 0)  _miniChip('CO सशस्त्र',    cA,  kArmedColor),
            if (cU  > 0)  _miniChip('CO निःशस्त्र',  cU,  kUnarmedColor),
            if (auxA > 0) _miniChip('Aux सशस्त्र',   auxA, kArmedColor),
            if (auxU > 0) _miniChip('Aux निःशस्त्र', auxU, kUnarmedColor),
          ]),
        ),
      ]),
    );
  }

  Widget _miniChip(String label, int count, Color color) => Container(
    margin: const EdgeInsets.only(right: 4),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(color == kArmedColor ? Icons.gavel : Icons.shield_outlined,
          size: 9, color: color),
      const SizedBox(width: 3),
      Text('$label: $count', style: TextStyle(
          color: color, fontSize: 9, fontWeight: FontWeight.w700)),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  Duty card — FIXED: uses _parseArmed() for all armed detection
// ══════════════════════════════════════════════════════════════════════════════
class _DutyCard extends StatelessWidget {
  final Map duty;
  final bool isLocked;
  final VoidCallback onRemove;
  const _DutyCard({required this.duty, required this.onRemove, required this.isLocked});

  @override
  Widget build(BuildContext context) {
    final d     = duty;
    final name  = '${d['name'] ?? ''}';
    final rank  = '${d['rank'] ?? d['user_rank'] ?? ''}';
    final pno   = '${d['pno'] ?? ''}';
    final thana = '${d['staffThana'] ?? d['thana'] ?? ''}';

    // ✅ FIXED: use _parseArmed which handles bool/int/String
    final armed     = _parseArmed(d['isArmed'] ?? d['is_armed']);
    final rankColor = _rankColor(rank);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: armed
            ? kArmedColor.withOpacity(0.3)
            : kUnarmedColor.withOpacity(0.25)),
        borderRadius: BorderRadius.circular(10),
        // Subtle left accent bar to make armed/unarmed obvious at a glance
        boxShadow: [BoxShadow(
          color: armed ? kArmedColor.withOpacity(0.08) : kUnarmedColor.withOpacity(0.06),
          blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Row(children: [
        // Colored left accent
        Container(
          width: 4, height: 40,
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: armed ? kArmedColor : kUnarmedColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Avatar
        Container(width: 36, height: 36,
          decoration: BoxDecoration(color: rankColor.withOpacity(0.12),
              shape: BoxShape.circle, border: Border.all(color: rankColor.withOpacity(0.3))),
          child: Center(child: Text(
            name.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join().toUpperCase(),
            style: TextStyle(color: rankColor, fontWeight: FontWeight.w900, fontSize: 12)))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(name, style: const TextStyle(
                color: kDark, fontWeight: FontWeight.w700, fontSize: 13),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            // Armed chip
            _ArmedChip(isArmed: armed),
          ]),
          const SizedBox(height: 3),
          Wrap(spacing: 8, children: [
            if (rank.isNotEmpty) Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: rankColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: rankColor.withOpacity(0.3))),
              child: Text(rank, style: TextStyle(color: rankColor, fontSize: 9,
                  fontWeight: FontWeight.w700))),
            if (pno.isNotEmpty)
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.badge_outlined, size: 10, color: kSubtle),
                const SizedBox(width: 2),
                Text(pno, style: const TextStyle(color: kSubtle, fontSize: 10)),
              ]),
            if (thana.isNotEmpty)
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.local_police_outlined, size: 10, color: kSubtle),
                const SizedBox(width: 2),
                Flexible(child: Text(thana, style: const TextStyle(color: kSubtle, fontSize: 10),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
          ]),
        ])),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: isLocked ? null : onRemove,
          child: Container(width: 32, height: 32,
            decoration: BoxDecoration(
              color: isLocked ? kSubtle.withOpacity(0.06) : kError.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isLocked
                  ? kSubtle.withOpacity(0.2) : kError.withOpacity(0.25)),
            ),
            child: Icon(
              isLocked ? Icons.lock_outline : Icons.person_remove_outlined,
              size: 15, color: isLocked ? kSubtle : kError)),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Assign Dialog
// ══════════════════════════════════════════════════════════════════════════════
class _AssignDialog extends StatefulWidget {
  final Map center;
  final VoidCallback onAssigned;
  const _AssignDialog({required this.center, required this.onAssigned});
  @override
  State<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<_AssignDialog> {
  final List<Map> _staff      = [];
  int    _staffPage           = 1;
  int    _staffTotal          = 0;
  bool   _staffLoading        = false;
  bool   _staffHasMore        = true;
  String _staffQ              = '';
  Timer? _searchTimer;

  final _searchCtrl  = TextEditingController();
  final _staffScroll = ScrollController();
  final Set<int> _selected = {};
  final _busCtrl           = TextEditingController();

  bool _saving = false;
  _ArmedFilter _armedFilter = _ArmedFilter.all;

  List<Map> get _filteredStaff {
    if (_armedFilter == _ArmedFilter.all) return _staff;
    return _staff.where((s) {
      final armed = _parseArmed(s['isArmed'] ?? s['is_armed']);
      return _armedFilter == _ArmedFilter.armed ? armed : !armed;
    }).toList();
  }

  int get _armedCount   => _staff.where((s) => _parseArmed(s['isArmed'] ?? s['is_armed'])).length;
  int get _unarmedCount => _staff.length - _armedCount;

  @override
  void initState() {
    super.initState();
    _staffScroll.addListener(_onStaffScroll);
    _searchCtrl.addListener(_onSearchChanged);
    _busCtrl.text = '${widget.center['busNo'] ?? ''}';
    _loadStaff(reset: true);
  }

  @override
  void dispose() {
    _staffScroll.removeListener(_onStaffScroll);
    _staffScroll.dispose();
    _searchCtrl.dispose();
    _busCtrl.dispose();
    _searchTimer?.cancel();
    super.dispose();
  }

  void _onStaffScroll() {
    if (_staffScroll.position.pixels >= _staffScroll.position.maxScrollExtent - 150
        && !_staffLoading && _staffHasMore) _loadStaff();
  }

  void _onSearchChanged() {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      final q = _searchCtrl.text.trim();
      if (q != _staffQ) { _staffQ = q; _loadStaff(reset: true); }
    });
  }

  Future<void> _loadStaff({bool reset = false}) async {
    if (_staffLoading) return;
    if (!reset && !_staffHasMore) return;
    if (reset) setState(() { _staff.clear(); _staffPage = 1; _staffHasMore = true; });
    setState(() => _staffLoading = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get(
        '/admin/staff?assigned=no&page=$_staffPage'
        '&limit=$_staffLimit&q=${Uri.encodeComponent(_staffQ)}',
        token: token,
      );
      final wrapper = (res['data'] as Map<String, dynamic>?) ?? {};
      final items   = List<Map>.from((wrapper['data']       as List?) ?? []);
      final total   = (wrapper['total']      as num?)?.toInt() ?? 0;
      final pages   = (wrapper['totalPages'] as num?)?.toInt() ?? 1;
      if (!mounted) return;
      setState(() {
        _staff.addAll(items);
        _staffTotal   = total;
        _staffHasMore = _staffPage < pages;
        _staffPage++;
        _staffLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _staffLoading = false);
    }
  }

  Future<void> _assign() async {
    if (_selected.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final token = await AuthService.getToken();
      final ids   = _selected.toList();
      if (ids.length == 1) {
        await ApiService.post('/admin/duties', {
          'staffId':  ids.first,
          'centerId': widget.center['id'],
          'busNo':    _busCtrl.text.trim(),
          'mode':     'manual',
        }, token: token);
      } else {
        await ApiService.post('/admin/staff/bulk-assign', {
          'staffIds': ids,
          'centerId': widget.center['id'],
          'busNo':    _busCtrl.text.trim(),
        }, token: token);
      }
      widget.onAssigned();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('त्रुटि: $e'),
          backgroundColor: kError, behavior: SnackBarBehavior.floating));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final center   = widget.center;
    final type     = '${center['centerType'] ?? 'C'}';
    final bc       = (center['boothCount'] ?? 1) as int;
    final filtered = _filteredStaff;
    final screenH  = MediaQuery.of(context).size.height;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: screenH * 0.90),
        child: Container(
          decoration: _dlgDec(),
          child: Column(mainAxisSize: MainAxisSize.min, children: [

            _DialogHeader(
              title: 'स्टाफ असाइन करें',
              icon: Icons.person_add_outlined,
              onClose: () => Navigator.pop(context),
            ),

            // Center info strip
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              color: kSurface.withOpacity(0.5),
              child: Row(children: [
                _TypeBadge(type: type),
                const SizedBox(width: 8),
                // Booth count chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _typeColor(type).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _typeColor(type).withOpacity(0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.how_to_vote_outlined, size: 11, color: _typeColor(type)),
                    const SizedBox(width: 3),
                    Text('$bc बूथ',
                        style: TextStyle(color: _typeColor(type),
                            fontSize: 11, fontWeight: FontWeight.w700)),
                  ]),
                ),
                const SizedBox(width: 8),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${center['name']}',
                      style: const TextStyle(color: kDark, fontWeight: FontWeight.w700, fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                  Text('${center['thana']}  •  ${center['gpName']}  •  ${center['sectorName']}',
                      style: const TextStyle(color: kSubtle, fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                ])),
                if (_selected.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: kPrimary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: kPrimary.withOpacity(0.4))),
                    child: Text('${_selected.length} चुने',
                        style: const TextStyle(color: kPrimary, fontSize: 11,
                            fontWeight: FontWeight.w700))),
              ]),
            ),

            const Divider(height: 1, color: kBorder),

            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Column(children: [
                TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: kDark, fontSize: 13),
                  decoration: _searchDec(
                    'नाम, PNO, थाना से खोजें... ($_staffTotal उपलब्ध)',
                    onClear: _staffQ.isNotEmpty ? () { _searchCtrl.clear(); } : null,
                  ),
                ),
                const SizedBox(height: 10),
                _ArmedFilterBar(
                  current:      _armedFilter,
                  totalCount:   _staff.length,
                  armedCount:   _armedCount,
                  unarmedCount: _unarmedCount,
                  onChanged:    (f) => setState(() {
                    _armedFilter = f;
                    _selected.clear();
                  }),
                ),
                const SizedBox(height: 8),
              ]),
            ),

            Expanded(
              child: _staffLoading && _staff.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: kPrimary))
                  : filtered.isEmpty
                      ? Center(child: Column(
                          mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.people_outline, size: 40, color: kSubtle.withOpacity(0.4)),
                          const SizedBox(height: 10),
                          Text(
                            _staff.isEmpty
                                ? 'सभी स्टाफ पहले से असाइन हैं'
                                : _staffQ.isNotEmpty
                                    ? '"$_staffQ" नहीं मिला'
                                    : _armedFilter == _ArmedFilter.armed
                                        ? 'कोई सशस्त्र स्टाफ उपलब्ध नहीं'
                                        : 'कोई निःशस्त्र स्टाफ उपलब्ध नहीं',
                            style: const TextStyle(color: kSubtle, fontSize: 13),
                            textAlign: TextAlign.center),
                        ]))
                      : ListView.separated(
                          controller: _staffScroll,
                          itemCount: filtered.length + (_staffHasMore ? 1 : 0),
                          separatorBuilder: (_, __) => const Divider(height: 1, color: kBorder),
                          itemBuilder: (_, i) {
                            if (i >= filtered.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Center(child: SizedBox(width: 16, height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary))));
                            }
                            final s   = filtered[i];
                            final sid = s['id'] as int;
                            return _StaffPickerRow(
                              staff:    s,
                              selected: _selected.contains(sid),
                              onTap: () => setState(() {
                                if (_selected.contains(sid)) _selected.remove(sid);
                                else _selected.add(sid);
                              }),
                            );
                          },
                        ),
            ),

            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: kBorder))),
              child: Column(children: [
                TextFormField(
                  controller: _busCtrl,
                  style: const TextStyle(color: kDark, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'बस संख्या (वैकल्पिक)',
                    labelStyle: const TextStyle(color: kSubtle, fontSize: 12),
                    prefixIcon: const Icon(Icons.directions_bus_outlined, size: 18, color: kSubtle),
                    isDense: true, filled: true, fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kBorder)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kPrimary, width: 2)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: kSubtle,
                        side: const BorderSide(color: kBorder),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: const Text('रद्द'),
                  )),
                  if (_selected.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Expanded(child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: _saving ? null : _assign,
                      child: _saving
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_selected.length == 1 ? 'असाइन करें' : '${_selected.length} असाइन करें'),
                    )),
                  ],
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  _ArmedFilterBar
// ══════════════════════════════════════════════════════════════════════════════
class _ArmedFilterBar extends StatelessWidget {
  final _ArmedFilter current;
  final int totalCount, armedCount, unarmedCount;
  final ValueChanged<_ArmedFilter> onChanged;
  const _ArmedFilterBar({
    required this.current, required this.totalCount,
    required this.armedCount, required this.unarmedCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const Icon(Icons.shield_outlined, size: 13, color: kSubtle),
      const SizedBox(width: 5),
      const Text('शस्त्र:', style: TextStyle(color: kSubtle, fontSize: 11, fontWeight: FontWeight.w700)),
      const SizedBox(width: 8),
      Expanded(child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _chip(_ArmedFilter.all,     'सभी ($totalCount)',             kPrimary),
          const SizedBox(width: 6),
          _chip(_ArmedFilter.armed,   '🗡 सशस्त्र ($armedCount)',     kArmedColor),
          const SizedBox(width: 6),
          _chip(_ArmedFilter.unarmed, '🛡 निःशस्त्र ($unarmedCount)', kUnarmedColor),
        ]),
      )),
    ]);
  }

  Widget _chip(_ArmedFilter filter, String label, Color color) {
    final selected = current == filter;
    return GestureDetector(
      onTap: () => onChanged(filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color:        selected ? color : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border:       Border.all(color: selected ? color : color.withOpacity(0.35)),
        ),
        child: Text(label, style: TextStyle(
            color: selected ? Colors.white : color,
            fontSize: 11, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  _ArmedChip
// ══════════════════════════════════════════════════════════════════════════════
class _ArmedChip extends StatelessWidget {
  final bool isArmed;
  const _ArmedChip({required this.isArmed});

  @override
  Widget build(BuildContext context) {
    final color = isArmed ? kArmedColor : kUnarmedColor;
    final label = isArmed ? 'सशस्त्र' : 'निःशस्त्र';
    final icon  = isArmed ? Icons.gavel : Icons.shield_outlined;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Staff picker row — FIXED armed detection
// ══════════════════════════════════════════════════════════════════════════════
class _StaffPickerRow extends StatelessWidget {
  final Map staff;
  final bool selected;
  final VoidCallback onTap;
  const _StaffPickerRow({required this.staff, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s       = staff;
    // ✅ FIXED: use _parseArmed
    final isArmed = _parseArmed(s['isArmed'] ?? s['is_armed']);
    final rank    = '${s['rank'] ?? s['user_rank'] ?? ''}';
    final rc      = _rankColor(rank);

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        color: selected ? kPrimary.withOpacity(0.07) : Colors.transparent,
        child: Row(children: [
          // Checkbox
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 26, height: 26,
            decoration: BoxDecoration(
              color:  selected ? kPrimary : kSurface,
              shape:  BoxShape.circle,
              border: Border.all(color: selected ? kPrimary : kBorder),
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white, size: 14)
                : null,
          ),
          const SizedBox(width: 10),
          // Avatar
          Container(width: 34, height: 34,
            decoration: BoxDecoration(color: rc.withOpacity(0.12),
                shape: BoxShape.circle, border: Border.all(color: rc.withOpacity(0.3))),
            child: Center(child: Text(
              '${s['name']}'.split(' ').where((w) => w.isNotEmpty)
                  .take(2).map((w) => w[0]).join().toUpperCase(),
              style: TextStyle(color: rc, fontWeight: FontWeight.w900, fontSize: 12)))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${s['name']}',
                  style: TextStyle(color: selected ? kPrimary : kDark,
                      fontSize: 13, fontWeight: FontWeight.w600),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              _ArmedChip(isArmed: isArmed),
            ]),
            const SizedBox(height: 2),
            Row(children: [
              if (rank.isNotEmpty) Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: rc.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: rc.withOpacity(0.3))),
                child: Text(rank, style: TextStyle(color: rc, fontSize: 9,
                    fontWeight: FontWeight.w700))),
              if ('${s['pno']}'.isNotEmpty)
                Text('PNO: ${s['pno']}', style: const TextStyle(color: kSubtle, fontSize: 10)),
              if ('${s['thana']}'.isNotEmpty) ...[
                const Text('  •  ', style: TextStyle(color: kSubtle, fontSize: 10)),
                Flexible(child: Text('${s['thana']}',
                    style: const TextStyle(color: kSubtle, fontSize: 10),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ]),
          ])),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Shared helpers
// ══════════════════════════════════════════════════════════════════════════════

class _DialogHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onClose;
  const _DialogHeader({required this.title, required this.icon, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: const BoxDecoration(
        color: kDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: kPrimary.withOpacity(0.25),
              borderRadius: BorderRadius.circular(7)),
          child: Icon(icon, color: kBorder, size: 16)),
        const SizedBox(width: 10),
        Expanded(child: Text(title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
            overflow: TextOverflow.ellipsis)),
        if (onClose != null)
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white60, size: 20),
            onPressed: onClose,
            padding: EdgeInsets.zero, constraints: const BoxConstraints()),
      ]),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge({required this.type});
  @override
  Widget build(BuildContext context) {
    final color = _typeColor(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.4))),
      child: Text(type, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900)),
    );
  }
}

Color _typeColor(String type) {
  switch (type) {
    case 'A++': return const Color(0xFF6C3483);
    case 'A':   return kError;
    case 'B':   return kAccent;
    default:    return kInfo;
  }
}

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

Widget _countBadge(int count) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  decoration: BoxDecoration(
    color:  count > 0 ? kSuccess.withOpacity(0.1) : kSurface,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: count > 0 ? kSuccess.withOpacity(0.4) : kBorder),
  ),
  child: Text('$count स्टाफ', style: TextStyle(
      color: count > 0 ? kSuccess : kSubtle, fontSize: 11, fontWeight: FontWeight.w700)),
);

BoxDecoration _dlgDec() => BoxDecoration(
  color:        kBg,
  borderRadius: BorderRadius.circular(16),
  border:       Border.all(color: kBorder, width: 1.2),
  boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.15),
      blurRadius: 20, offset: const Offset(0, 8))],
);

InputDecoration _searchDec(String hint, {VoidCallback? onClear}) => InputDecoration(
  hintText:  hint,
  hintStyle: const TextStyle(color: kSubtle, fontSize: 13),
  prefixIcon: const Icon(Icons.search, color: kSubtle, size: 18),
  suffixIcon: onClear != null
      ? IconButton(icon: const Icon(Icons.clear, size: 16, color: kSubtle), onPressed: onClear)
      : null,
  filled: true, fillColor: Colors.white, isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: kBorder)),
  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: kBorder)),
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: kPrimary, width: 2)),
);

Widget _infoChip(IconData icon, String? text) {
  if (text == null || text.isEmpty || text == 'null') return const SizedBox.shrink();
  return Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 11, color: kSubtle),
    const SizedBox(width: 4),
    Flexible(child: Text(text, style: const TextStyle(color: kSubtle, fontSize: 11),
        overflow: TextOverflow.ellipsis)),
  ]);
}

Widget _pill(String text, Color color) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  decoration: BoxDecoration(
    color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20),
    border: Border.all(color: color.withOpacity(0.3)),
  ),
  child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
);