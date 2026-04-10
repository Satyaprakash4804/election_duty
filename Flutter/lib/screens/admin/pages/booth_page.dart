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

const _ctLabel     = {'A': 'अति संवेदनशील', 'B': 'संवेदनशील', 'C': 'सामान्य'};
const _pageLimit   = 50;
const _staffLimit  = 30;
const _dutiesLimit = 30;

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
  int  _page     = 1;
  int  _total    = 0;
  bool _loading  = false;   // ← starts false so first load fires
  bool _hasMore  = true;
  String _q      = '';
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
    if (reset) {
      setState(() { _centers.clear(); _page = 1; _hasMore = true; });
    }
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.get(
        '/admin/centers/all?page=$_page&limit=$_pageLimit'
        '&q=${Uri.encodeComponent(_q)}',
        token: token,
      );
      final wrapper = (res['data'] as Map<String, dynamic>?) ?? {};
      final items   = List<Map>.from((wrapper['data'] as List?) ?? []);
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AssignDialog(
        center: center,
        onAssigned: () => _loadCenters(reset: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [

      // Search bar
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

      // Stats
      Container(
        color: kBg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          _pill('$_total बूथ', kPrimary),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18, color: kSubtle),
            onPressed: () => _loadCenters(reset: true),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ]),
      ),

      // List
      Expanded(
        child: _centers.isEmpty && _loading
            ? const Center(child: CircularProgressIndicator(color: kPrimary))
            : _centers.isEmpty
                ? _emptyState(
                    _q.isNotEmpty
                        ? '"$_q" के लिए कोई बूथ नहीं'
                        : 'कोई बूथ नहीं मिला',
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
                            child: Center(child: SizedBox(
                                width: 22, height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: kPrimary))),
                          );
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
      Text(msg,
          style: const TextStyle(color: kSubtle, fontSize: 14),
          textAlign: TextAlign.center),
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
    final type   = '${center['centerType'] ?? 'C'}';
    final count  = (center['dutyCount'] ?? 0) as int;
    final tColor = type == 'A' ? kError : type == 'B' ? kAccent : kInfo;
    final abbr   = type == 'A' ? 'अति' : type == 'B' ? 'संवे' : 'सामा';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder.withOpacity(0.4)),
          boxShadow: [BoxShadow(
              color: kPrimary.withOpacity(0.05),
              blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(children: [
          Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: tColor.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12)),
              border: Border(right: BorderSide(color: tColor.withOpacity(0.3))),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(type, style: TextStyle(
                  color: tColor, fontSize: 20, fontWeight: FontWeight.w900)),
              Text(abbr, style: TextStyle(
                  color: tColor.withOpacity(0.7), fontSize: 7,
                  fontWeight: FontWeight.w600)),
            ]),
          ),
          Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${center['name']}',
                  style: const TextStyle(
                      color: kDark, fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 4),
              Row(children: [
                Flexible(child: _tagSmall(Icons.local_police_outlined,
                    '${center['thana']}')),
                const SizedBox(width: 10),
                Flexible(child: _tagSmall(Icons.account_balance_outlined,
                    '${center['gpName']}')),
              ]),
              const SizedBox(height: 2),
              _tagSmall(Icons.layers_outlined,
                  '${center['sectorName']} › ${center['zoneName']} › ${center['superZoneName']}'),
              if ((center['blockName'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 2),
                _tagSmall(Icons.location_city_outlined,
                    'ब्लॉक: ${center['blockName']}'),
              ],
            ]),
          )),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: count > 0 ? kSuccess.withOpacity(0.1) : kSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: count > 0
                        ? kSuccess.withOpacity(0.4)
                        : kBorder.withOpacity(0.4)),
              ),
              child: Column(children: [
                Text('$count', style: TextStyle(
                    color: count > 0 ? kSuccess : kSubtle,
                    fontSize: 18, fontWeight: FontWeight.w900)),
                Text('स्टाफ', style: TextStyle(
                    color: count > 0 ? kSuccess : kSubtle, fontSize: 10)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _tagSmall(IconData icon, String text) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: kSubtle),
        const SizedBox(width: 3),
        Flexible(child: Text(text,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: kSubtle, fontSize: 11))),
      ]);
}

// ══════════════════════════════════════════════════════════════════════════════
//  Duties Dialog
//  ROOT CAUSE OF INFINITE LOADING:
//  _loading was initialised to `true`, so the guard `if (_loading && !reset)`
//  in the old code blocked the very first _load() call from initState.
//  FIX: _loading = false + guard changed to `if (_loading) return`.
//
//  ROOT CAUSE OF BLASTBufferQueue:
//  _scroll.addListener() was called inside StatefulBuilder's builder function,
//  which runs on every setState(). Each rebuild added a NEW listener without
//  removing the old one, multiplying scroll callbacks exponentially until the
//  GPU frame buffer was exhausted.
//  FIX: listener attached ONCE in initState(), removed in dispose().
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
  bool _loading = false;   // ← FIX: was true, blocked first load
  bool _hasMore = true;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);   // ← FIX: once here, not in build()
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
        && !_loading && _hasMore) {
      _load();
    }
  }

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
      final items   = List<Map>.from((wrapper['data'] as List?) ?? []);
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
    final center  = widget.center;
    final type    = '${center['centerType'] ?? 'C'}';
    final screenH = MediaQuery.of(context).size.height;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 500, maxHeight: screenH * 0.85),
        child: Container(
          decoration: _dlgDec(),
          child: Column(mainAxisSize: MainAxisSize.min, children: [

            _DialogHeader(
              title: '${center['name']}',
              icon: Icons.location_on_outlined,
              onClose: () => Navigator.pop(context),
            ),

            // Center meta
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  _TypeBadge(type: type),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_ctLabel[type] ?? type,
                      style: const TextStyle(
                          color: kSubtle, fontSize: 12,
                          fontWeight: FontWeight.w600))),
                  _countBadge(_total),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 12, runSpacing: 4, children: [
                  _infoChip(Icons.local_police_outlined, '${center['thana']}'),
                  _infoChip(Icons.account_balance_outlined, '${center['gpName']}'),
                  _infoChip(Icons.map_outlined, 'सेक्टर: ${center['sectorName']}'),
                  _infoChip(Icons.layers_outlined, 'जोन: ${center['zoneName']}'),
                  _infoChip(Icons.public_outlined,
                      'सुपर जोन: ${center['superZoneName']}'),
                  if ((center['blockName'] ?? '').toString().isNotEmpty)
                    _infoChip(Icons.location_city_outlined,
                        'ब्लॉक: ${center['blockName']}'),
                  if ((center['busNo'] ?? '').toString().isNotEmpty)
                    _infoChip(Icons.directions_bus_outlined,
                        'बस: ${center['busNo']}'),
                ]),
              ]),
            ),

            const Divider(height: 1, color: kBorder),

            // FIX: Expanded + plain ListView, no shrinkWrap
            Expanded(
              child: _loading && _duties.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: kPrimary))
                  : _duties.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline,
                                  size: 40, color: kSubtle.withOpacity(0.5)),
                              const SizedBox(height: 10),
                              const Text('इस बूथ पर कोई स्टाफ नहीं',
                                  style: TextStyle(
                                      color: kSubtle, fontSize: 13)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          itemCount: _duties.length + (_hasMore ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i >= _duties.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(child: SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: kPrimary))),
                              );
                            }
                            final d = _duties[i];
                            return _DutyCard(
                                duty: d, onRemove: () => _removeDuty(d));
                          },
                        ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: kBorder))),
              child: Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: kSubtle,
                      side: const BorderSide(color: kBorder),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: const Text('बंद करें'),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  onPressed: () => widget.onAssign(context),
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

// ══════════════════════════════════════════════════════════════════════════════
//  Duty card
// ══════════════════════════════════════════════════════════════════════════════
class _DutyCard extends StatelessWidget {
  final Map duty;
  final VoidCallback onRemove;
  const _DutyCard({required this.duty, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final d    = duty;
    final name = '${d['name'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder.withOpacity(0.4)),
      ),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
              color: kSurface, shape: BoxShape.circle,
              border: Border.all(color: kBorder)),
          child: Center(child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: kPrimary, fontSize: 15,
                  fontWeight: FontWeight.w800))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name.isNotEmpty ? name : '—',
              style: const TextStyle(
                  color: kDark, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 2),
          Text('PNO: ${d['pno'] ?? ''}  •  ${d['mobile'] ?? ''}',
              style: const TextStyle(color: kSubtle, fontSize: 11)),
          if ((d['rank'] ?? d['user_rank'] ?? '').toString().isNotEmpty)
            Text(
              '${d['rank'] ?? d['user_rank']}'
              '  •  ${d['staffThana'] ?? d['thana'] ?? ''}',
              style: const TextStyle(
                  color: kAccent, fontSize: 10, fontWeight: FontWeight.w600),
            ),
        ])),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, color: kError, size: 20),
          onPressed: onRemove,
          tooltip: 'ड्यूटी हटाएं',
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Assign Dialog
//  Same two fixes as DutiesDialog:
//  1. _staffLoading = false so initState load fires
//  2. _staffScroll listener attached in initState, not build()
// ══════════════════════════════════════════════════════════════════════════════
class _AssignDialog extends StatefulWidget {
  final Map center;
  final VoidCallback onAssigned;
  const _AssignDialog({required this.center, required this.onAssigned});
  @override
  State<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<_AssignDialog> {
  final List<Map>  _staff      = [];
  int    _staffPage            = 1;
  int    _staffTotal           = 0;
  bool   _staffLoading         = false;  // ← FIX: was true
  bool   _staffHasMore         = true;
  String _staffQ               = '';
  Timer? _searchTimer;
  final  _searchCtrl           = TextEditingController();
  final  _staffScroll          = ScrollController();
  final  Set<int> _selected    = {};
  final  _busCtrl              = TextEditingController();
  bool   _saving               = false;

  @override
  void initState() {
    super.initState();
    _staffScroll.addListener(_onStaffScroll);  // ← FIX: once here
    _searchCtrl.addListener(_onSearchChanged);
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
    if (_staffScroll.position.pixels >=
            _staffScroll.position.maxScrollExtent - 150
        && !_staffLoading
        && _staffHasMore) {
      _loadStaff();
    }
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
    if (reset) {
      setState(() { _staff.clear(); _staffPage = 1; _staffHasMore = true; });
    }
    setState(() => _staffLoading = true);
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.get(
        '/admin/staff?assigned=no&page=$_staffPage'
        '&limit=$_staffLimit&q=${Uri.encodeComponent(_staffQ)}',
        token: token,
      );
      final wrapper = (res['data'] as Map<String, dynamic>?) ?? {};
      final items   = List<Map>.from((wrapper['data'] as List?) ?? []);
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${ids.length} स्टाफ सफलतापूर्वक असाइन किए गए'),
          backgroundColor: kSuccess,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('त्रुटि: $e'),
          backgroundColor: kError,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allSelected = _staff.isNotEmpty &&
        _staff.every((s) => _selected.contains(s['id'] as int));

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Container(
          decoration: _dlgDec(),
          child: Column(mainAxisSize: MainAxisSize.min, children: [

            _DialogHeader(
              title: 'स्टाफ असाइन करें',
              icon: Icons.how_to_vote_outlined,
              onClose: _saving ? null : () => Navigator.pop(context),
            ),

            Flexible(child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                _CenterInfoCard(center: widget.center),
                const SizedBox(height: 14),

                Row(children: [
                  _sectionLabel('स्टाफ चुनें'),
                  const Spacer(),
                  if (_staffTotal > 0)
                    Text('$_staffTotal उपलब्ध',
                        style: const TextStyle(color: kSubtle, fontSize: 11)),
                ]),
                const SizedBox(height: 8),

                // Search
                TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: kDark, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'नाम, PNO, थाना, पद से खोजें...',
                    hintStyle: const TextStyle(color: kSubtle, fontSize: 12),
                    prefixIcon: const Icon(Icons.search, color: kSubtle, size: 18),
                    suffixIcon: _staffQ.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16, color: kSubtle),
                            onPressed: () {
                              _searchCtrl.clear();
                              _staffQ = '';
                              _loadStaff(reset: true);
                            })
                        : null,
                    filled: true, fillColor: Colors.white, isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kBorder)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kBorder)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kPrimary, width: 2)),
                  ),
                ),
                const SizedBox(height: 6),

                // Selection header
                Row(children: [
                  Text(
                    _selected.isEmpty
                        ? '${_staff.length} लोड (${_staffTotal} कुल)'
                        : '${_selected.length} चुने गए',
                    style: TextStyle(
                        color: _selected.isEmpty ? kSubtle : kPrimary,
                        fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (_staff.isNotEmpty)
                    TextButton(
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: kPrimary),
                      onPressed: () => setState(() {
                        if (allSelected) {
                          for (final s in _staff) _selected.remove(s['id'] as int);
                        } else {
                          for (final s in _staff) _selected.add(s['id'] as int);
                        }
                      }),
                      child: Text(allSelected ? 'सभी हटाएं' : 'सभी चुनें',
                          style: const TextStyle(fontSize: 11)),
                    ),
                ]),
                const SizedBox(height: 4),

                // FIX: SizedBox + no shrinkWrap — avoids layout loops
                SizedBox(
                  height: 240,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kBorder),
                      ),
                      child: _staffLoading && _staff.isEmpty
                          ? const Center(child: CircularProgressIndicator(
                              color: kPrimary, strokeWidth: 2))
                          : _staff.isEmpty
                              ? Center(child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.people_outline, size: 32,
                                        color: kSubtle.withOpacity(0.5)),
                                    const SizedBox(height: 8),
                                    Text(
                                      _staffQ.isNotEmpty
                                          ? '"$_staffQ" नहीं मिला'
                                          : 'सभी स्टाफ असाइन हैं',
                                      style: const TextStyle(
                                          color: kSubtle, fontSize: 12),
                                    ),
                                  ],
                                ))
                              : ListView.separated(
                                  controller: _staffScroll,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 4),
                                  itemCount: _staff.length +
                                      (_staffHasMore ? 1 : 0),
                                  separatorBuilder: (_, __) => Divider(
                                      height: 1,
                                      color: kBorder.withOpacity(0.4)),
                                  itemBuilder: (_, i) {
                                    if (i >= _staff.length) {
                                      return const Padding(
                                        padding: EdgeInsets.all(10),
                                        child: Center(child: SizedBox(
                                            width: 16, height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: kPrimary))),
                                      );
                                    }
                                    final s   = _staff[i];
                                    final id  = s['id'] as int;
                                    final sel = _selected.contains(id);
                                    return _StaffPickerRow(
                                      staff: s, selected: sel,
                                      onTap: () => setState(() => sel
                                          ? _selected.remove(id)
                                          : _selected.add(id)),
                                    );
                                  },
                                ),
                    ),
                  ),
                ),

                if (_staffHasMore && !_staffLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('↓ स्क्रॉल करें — और स्टाफ लोड होंगे',
                        style: TextStyle(color: kSubtle, fontSize: 10)),
                  ),

                const SizedBox(height: 12),

                // Bus number
                TextField(
                  controller: _busCtrl,
                  style: const TextStyle(color: kDark, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'बस संख्या (वैकल्पिक)',
                    labelStyle: const TextStyle(color: kSubtle, fontSize: 12),
                    prefixIcon: const Icon(Icons.directions_bus_outlined,
                        size: 18, color: kPrimary),
                    filled: true, fillColor: Colors.white, isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kBorder)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kBorder)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kPrimary, width: 2)),
                  ),
                ),
              ]),
            )),

            // Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: kSubtle,
                      side: const BorderSide(color: kBorder),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: const Text('रद्द करें'),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selected.isEmpty ? kSubtle : kPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _selected.isEmpty || _saving ? null : _assign,
                  child: _saving
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text(
                          _selected.isEmpty
                              ? 'असाइन करें'
                              : '${_selected.length} को असाइन करें',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                )),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Staff picker row
// ══════════════════════════════════════════════════════════════════════════════
class _StaffPickerRow extends StatelessWidget {
  final Map staff;
  final bool selected;
  final VoidCallback onTap;
  const _StaffPickerRow(
      {required this.staff, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = staff;
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        color: selected ? kPrimary.withOpacity(0.07) : Colors.transparent,
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 26, height: 26,
            decoration: BoxDecoration(
              color: selected ? kPrimary : kSurface,
              shape: BoxShape.circle,
              border: Border.all(color: selected ? kPrimary : kBorder),
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white, size: 14)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${s['name']}',
                style: TextStyle(
                    color: selected ? kPrimary : kDark,
                    fontSize: 13, fontWeight: FontWeight.w600)),
            Text(
              'PNO: ${s['pno']}  •  ${s['thana'] ?? ''}'
              '  •  ${s['rank'] ?? s['user_rank'] ?? ''}',
              style: const TextStyle(color: kSubtle, fontSize: 10),
              overflow: TextOverflow.ellipsis,
            ),
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
  const _DialogHeader(
      {required this.title, required this.icon, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: const BoxDecoration(
        color: kDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.25),
              borderRadius: BorderRadius.circular(7)),
          child: Icon(icon, color: kBorder, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700,
                fontSize: 15),
            overflow: TextOverflow.ellipsis)),
        if (onClose != null)
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white60, size: 20),
            onPressed: onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
      ]),
    );
  }
}

class _CenterInfoCard extends StatelessWidget {
  final Map center;
  const _CenterInfoCard({required this.center});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder.withOpacity(0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _TypeBadge(type: '${center['centerType'] ?? 'C'}'),
          const SizedBox(width: 10),
          Expanded(child: Text('${center['name']}',
              style: const TextStyle(
                  color: kDark, fontWeight: FontWeight.w700, fontSize: 13))),
        ]),
        const SizedBox(height: 6),
        _infoChip(Icons.local_police_outlined, center['thana']),
        _infoChip(Icons.account_balance_outlined, center['gpName']),
        _infoChip(Icons.layers_outlined,
            '${center['sectorName']} › '
            '${center['zoneName']} › '
            '${center['superZoneName']}'),
        if ((center['blockName'] ?? '').toString().isNotEmpty)
          _infoChip(Icons.location_city_outlined,
              'ब्लॉक: ${center['blockName']}'),
      ]),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge({required this.type});
  @override
  Widget build(BuildContext context) {
    final color = type == 'A' ? kError : type == 'B' ? kAccent : kInfo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.4))),
      child: Text(type, style: TextStyle(
          color: color, fontSize: 12, fontWeight: FontWeight.w900)),
    );
  }
}

Widget _countBadge(int count) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  decoration: BoxDecoration(
    color: count > 0 ? kSuccess.withOpacity(0.1) : kSurface,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(
        color: count > 0 ? kSuccess.withOpacity(0.4) : kBorder),
  ),
  child: Text('$count स्टाफ', style: TextStyle(
      color: count > 0 ? kSuccess : kSubtle,
      fontSize: 11, fontWeight: FontWeight.w700)),
);

BoxDecoration _dlgDec() => BoxDecoration(
  color: kBg,
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: kBorder, width: 1.2),
  boxShadow: [BoxShadow(
      color: kPrimary.withOpacity(0.15),
      blurRadius: 20, offset: const Offset(0, 8))],
);

Widget _sectionLabel(String label) => Row(children: [
  Container(width: 3, height: 14,
      decoration: BoxDecoration(
          color: kPrimary, borderRadius: BorderRadius.circular(2))),
  const SizedBox(width: 7),
  Text(label, style: const TextStyle(
      color: kDark, fontSize: 13, fontWeight: FontWeight.w800)),
]);

InputDecoration _searchDec(String hint, {VoidCallback? onClear}) =>
    InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: kSubtle, fontSize: 13),
      prefixIcon: const Icon(Icons.search, color: kSubtle, size: 18),
      suffixIcon: onClear != null
          ? IconButton(
              icon: const Icon(Icons.clear, size: 16, color: kSubtle),
              onPressed: onClear)
          : null,
      filled: true, fillColor: Colors.white, isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kPrimary, width: 2)),
    );

Widget _infoChip(IconData icon, String? text) {
  if (text == null || text.isEmpty || text == 'null') {
    return const SizedBox.shrink();
  }
  return Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: kSubtle),
      const SizedBox(width: 4),
      Flexible(child: Text(text,
          style: const TextStyle(color: kSubtle, fontSize: 11),
          overflow: TextOverflow.ellipsis)),
    ]),
  );
}

Widget _pill(String text, Color color) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  decoration: BoxDecoration(
    color: color.withOpacity(0.1),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: color.withOpacity(0.3)),
  ),
  child: Text(text, style: TextStyle(
      color: color, fontSize: 11, fontWeight: FontWeight.w700)),
);