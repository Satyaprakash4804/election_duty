import 'package:flutter/material.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';

class BoothPage extends StatefulWidget {
  const BoothPage({super.key});
  @override
  State<BoothPage> createState() => _BoothPageState();
}

class _BoothPageState extends State<BoothPage> {
  List _centers = [];
  List _filtered = [];
  List _allStaff = [];          // all staff from API
  bool _loading = true;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(_filter);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final c = await ApiService.get('/admin/centers/all', token: token);
      final s = await ApiService.get('/admin/staff', token: token);
      setState(() {
        _centers  = c['data'] ?? [];
        _allStaff = s['data'] ?? [];
        _filtered = _centers;
        _loading  = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) showSnack(context, 'Failed to load: $e', error: true);
    }
  }

  // Only unassigned staff for the dropdown
  List get _unassigned =>
      _allStaff.where((s) => s['isAssigned'] != true).toList();

  void _filter() {
    final q = _search.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _centers
          : _centers.where((c) =>
              '${c['name']}'.toLowerCase().contains(q)         ||
              '${c['thana']}'.toLowerCase().contains(q)        ||
              '${c['gpName']}'.toLowerCase().contains(q)       ||
              '${c['sectorName']}'.toLowerCase().contains(q)   ||
              '${c['zoneName']}'.toLowerCase().contains(q)     ||
              '${c['superZoneName']}'.toLowerCase().contains(q)).toList();
    });
  }

  // ── Assign Dialog (with available staff dropdown) ─────────────────────────
  void _showAssignDialog(Map center) {
    Map? selectedStaff;
    final busCtrl = TextEditingController(text: '${center['busNo'] ?? ''}');
    final unassigned = _unassigned;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: StatefulBuilder(
            builder: (ctx, ss) => Container(
              decoration: BoxDecoration(
                color: kBg, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder, width: 1.2),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                dlgHeader('Assign Staff', Icons.how_to_vote_outlined, ctx),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    // Center info banner
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kSurface, borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kBorder.withOpacity(0.5)),
                      ),
                      child: Row(children: [
                        TypeBadge(type: '${center['centerType'] ?? 'C'}'),
                        const SizedBox(width: 10),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${center['name']}', style: const TextStyle(
                                color: kDark, fontWeight: FontWeight.w700,
                                fontSize: 13)),
                            Text('${center['thana']} • ${center['gpName']}',
                                style: const TextStyle(
                                    color: kSubtle, fontSize: 11)),
                          ],
                        )),
                      ]),
                    ),
                    const SizedBox(height: 16),

                    // Available staff count
                    Row(children: [
                      const Icon(Icons.people_outline, size: 14, color: kSubtle),
                      const SizedBox(width: 6),
                      Text('${unassigned.length} unassigned staff available',
                          style: const TextStyle(
                              color: kSubtle, fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 10),

                    // Staff Dropdown
                    unassigned.isEmpty
                        ? Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: kError.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: kError.withOpacity(0.3)),
                            ),
                            child: const Row(children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: kError, size: 16),
                              SizedBox(width: 8),
                              Text('No unassigned staff available',
                                  style: TextStyle(color: kError, fontSize: 12)),
                            ]),
                          )
                        : DropdownButtonFormField<Map>(
                            value: selectedStaff,
                            isExpanded: true,
                            dropdownColor: kBg,
                            decoration: InputDecoration(
                              labelText: 'Select Staff Member',
                              labelStyle: const TextStyle(color: kSubtle),
                              prefixIcon: const Icon(Icons.badge_outlined,
                                  size: 18, color: kPrimary),
                              filled: true, fillColor: Colors.white,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: kBorder)),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: kBorder)),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                      color: kPrimary, width: 2)),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                            ),
                            items: unassigned.map((s) => DropdownMenuItem<Map>(
                              value: s,
                              child: Row(children: [
                                Container(
                                  width: 28, height: 28,
                                  decoration: BoxDecoration(
                                    color: kSurface, shape: BoxShape.circle,
                                    border: Border.all(color: kBorder)),
                                  child: Center(child: Text(
                                    '${s['name']}'[0].toUpperCase(),
                                    style: const TextStyle(
                                        color: kPrimary, fontSize: 12,
                                        fontWeight: FontWeight.w800))),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('${s['name']}',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: kDark, fontSize: 13,
                                            fontWeight: FontWeight.w600)),
                                    Text('PNO: ${s['pno']} • ${s['thana']}',
                                        style: const TextStyle(
                                            color: kSubtle, fontSize: 10)),
                                  ],
                                )),
                              ]),
                            )).toList(),
                            onChanged: (v) => ss(() => selectedStaff = v),
                          ),

                    const SizedBox(height: 12),
                    AppTextField(label: 'Bus Number',
                        controller: busCtrl,
                        prefixIcon: Icons.directions_bus_outlined),
                    const SizedBox(height: 4),

                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kSubtle,
                            side: const BorderSide(color: kBorder),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: selectedStaff == null
                                ? kSubtle : kPrimary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: selectedStaff == null || unassigned.isEmpty
                              ? null
                              : () async {
                                  final token = await AuthService.getToken();
                                  await ApiService.post('/admin/duties', {
                                    'staffId': selectedStaff!['id'],
                                    'centerId': center['id'],
                                    'busNo': busCtrl.text,
                                  }, token: token);
                                  Navigator.pop(ctx);
                                  _load();
                                  if (mounted) showSnack(context, 'Duty assigned');
                                },
                          child: const Text('Assign'),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ── Duties Dialog ─────────────────────────────────────────────────────────
  void _showDutiesDialog(Map center) async {
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get(
          '/admin/duties?center_id=${center['id']}', token: token);
      final duties = res['data'] ?? [];
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              decoration: BoxDecoration(
                color: kBg, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder, width: 1.2),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                dlgHeader(center['name'], Icons.location_on_outlined, ctx),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(children: [
                    TypeBadge(type: '${center['centerType'] ?? 'C'}'),
                    const SizedBox(width: 8),
                    Text('${center['thana']} • ${center['gpName']}',
                        style: const TextStyle(color: kSubtle, fontSize: 12)),
                    const Spacer(),
                    Text('${duties.length} staff',
                        style: const TextStyle(
                            color: kPrimary, fontWeight: FontWeight.w700,
                            fontSize: 12)),
                  ]),
                ),
                SizedBox(
                  height: 260,
                  child: duties.isEmpty
                      ? emptyState('No staff assigned yet',
                          Icons.people_outline)
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          itemCount: duties.length,
                          itemBuilder: (_, i) {
                            final d = duties[i];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: kBorder.withOpacity(0.4)),
                              ),
                              child: Row(children: [
                                Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: kSurface, shape: BoxShape.circle,
                                    border: Border.all(color: kBorder)),
                                  child: Center(child: Text(
                                    '${d['name']}'[0].toUpperCase(),
                                    style: const TextStyle(
                                        color: kPrimary, fontSize: 15,
                                        fontWeight: FontWeight.w800))),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${d['name']}', style: const TextStyle(
                                        color: kDark, fontWeight: FontWeight.w700,
                                        fontSize: 13)),
                                    Text('PNO: ${d['pno']} • ${d['mobile']}',
                                        style: const TextStyle(
                                            color: kSubtle, fontSize: 11)),
                                  ],
                                )),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline,
                                      color: kError, size: 20),
                                  onPressed: () async {
                                    final t = await AuthService.getToken();
                                    await ApiService.delete(
                                        '/admin/duties/${d['id']}', token: t);
                                    Navigator.pop(ctx);
                                    _load();
                                    if (mounted) showSnack(context, 'Duty removed');
                                  },
                                ),
                              ]),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kSubtle,
                          side: const BorderSide(color: kBorder),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Close'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showAssignDialog(center);
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Staff'),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
    } catch (e) {
      showSnack(context, 'Error: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // ── Search ─────────────────────────────────────────────────────────────
      Container(
        color: kSurface,
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _search,
          style: const TextStyle(color: kDark, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Search centers by name, thana, GP, sector, zone...',
            hintStyle: const TextStyle(color: kSubtle, fontSize: 13),
            prefixIcon: const Icon(Icons.search, color: kSubtle, size: 18),
            filled: true, fillColor: Colors.white,
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
                borderSide: const BorderSide(color: kPrimary, width: 2)),
            isDense: true,
          ),
        ),
      ),

      // ── Stats Bar ──────────────────────────────────────────────────────────
      Container(
        color: kBg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          _pill('${_filtered.length} centers', kPrimary),
          const SizedBox(width: 8),
          _pill('${_unassigned.length} unassigned staff', kAccent),
        ]),
      ),

      if (_loading)
        const Expanded(child: Center(child: CircularProgressIndicator(color: kPrimary)))
      else if (_filtered.isEmpty)
        Expanded(child: emptyState('No centers found', Icons.location_off_outlined))
      else
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            color: kPrimary,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final c     = _filtered[i];
                final type  = '${c['centerType'] ?? 'C'}';
                final count = (c['dutyCount'] ?? 0) as int;
                final tColor = type == 'A' ? kError
                    : type == 'B' ? kAccent : kInfo;

                return GestureDetector(
                  onTap: () => _showDutiesDialog(c),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kBorder.withOpacity(0.4)),
                      boxShadow: [BoxShadow(
                          color: kPrimary.withOpacity(0.05),
                          blurRadius: 8, offset: const Offset(0, 3))],
                    ),
                    child: Row(children: [
                      // Type indicator strip
                      Container(
                        width: 50,
                        decoration: BoxDecoration(
                          color: tColor.withOpacity(0.1),
                          borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(12),
                              bottomLeft: Radius.circular(12)),
                          border: Border(
                              right: BorderSide(
                                  color: tColor.withOpacity(0.3))),
                        ),
                        child: Center(child: Text(type,
                            style: TextStyle(
                                color: tColor, fontSize: 18,
                                fontWeight: FontWeight.w900))),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${c['name']}', style: const TextStyle(
                                  color: kDark, fontWeight: FontWeight.w700,
                                  fontSize: 14)),
                              const SizedBox(height: 4),
                              Row(children: [
                                _tagSmall(Icons.local_police_outlined,
                                    '${c['thana']}'),
                                const SizedBox(width: 10),
                                _tagSmall(Icons.account_balance_outlined,
                                    '${c['gpName']}'),
                              ]),
                              const SizedBox(height: 2),
                              _tagSmall(Icons.layers_outlined,
                                  '${c['sectorName']} • ${c['zoneName']}'),
                            ],
                          ),
                        ),
                      ),
                      // Staff count badge
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: count > 0
                                    ? kSuccess.withOpacity(0.1)
                                    : kSurface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: count > 0
                                        ? kSuccess.withOpacity(0.4)
                                        : kBorder.withOpacity(0.4)),
                              ),
                              child: Column(children: [
                                Text('$count', style: TextStyle(
                                    color: count > 0 ? kSuccess : kSubtle,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900)),
                                Text('staff', style: TextStyle(
                                    color: count > 0 ? kSuccess : kSubtle,
                                    fontSize: 10)),
                              ]),
                            ),
                          ],
                        ),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
        ),
    ]);
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(text, style: TextStyle(
          color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _tagSmall(IconData icon, String text) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: kSubtle),
      const SizedBox(width: 3),
      Text(text, style: const TextStyle(color: kSubtle, fontSize: 11)),
    ]);
  }
}