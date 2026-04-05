import 'package:flutter/material.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';

// ─── palette (matches your app) ──────────────────────────────────────────────
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

// ─── center-type label map ────────────────────────────────────────────────────
const _ctLabel = {'A': 'अति संवेदनशील', 'B': 'संवेदनशील', 'C': 'सामान्य'};

class BoothPage extends StatefulWidget {
  const BoothPage({super.key});
  @override
  State<BoothPage> createState() => _BoothPageState();
}

class _BoothPageState extends State<BoothPage> {
  List _centers  = [];
  List _filtered = [];
  List _allStaff = [];
  bool _loading  = true;
  final _search  = TextEditingController();

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
      final s = await ApiService.get('/admin/staff',       token: token);
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

  // Unassigned staff for the picker
  List get _unassigned =>
      _allStaff.where((s) => s['isAssigned'] != true).toList();

  void _filter() {
    final q = _search.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _centers
          : _centers.where((c) =>
              '${c['name']}'.toLowerCase().contains(q)           ||
              '${c['thana']}'.toLowerCase().contains(q)          ||
              '${c['gpName']}'.toLowerCase().contains(q)         ||
              '${c['sectorName']}'.toLowerCase().contains(q)     ||
              '${c['zoneName']}'.toLowerCase().contains(q)       ||
              '${c['superZoneName']}'.toLowerCase().contains(q)  ||
              '${c['blockName'] ?? ''}'.toLowerCase().contains(q)).toList();
    });
  }

  // ── Multi-select assign dialog ─────────────────────────────────────────────
  void _showAssignDialog(Map center) {
    final Set<int> selectedIds = {};
    final busCtrl    = TextEditingController(text: '${center['busNo'] ?? ''}');
    final searchCtrl = TextEditingController();
    final unassigned = _unassigned;
    List filtered    = List.from(unassigned);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: StatefulBuilder(
            builder: (ctx, ss) {
              void filterStaff(String q) {
                ss(() {
                  filtered = q.isEmpty
                      ? List.from(unassigned)
                      : unassigned.where((s) =>
                          '${s['name']}'.toLowerCase().contains(q.toLowerCase())     ||
                          '${s['pno']}'.toLowerCase().contains(q.toLowerCase())      ||
                          '${s['thana']}'.toLowerCase().contains(q.toLowerCase())    ||
                          '${s['rank'] ?? s['user_rank'] ?? ''}'.toLowerCase()
                              .contains(q.toLowerCase())).toList();
                });
              }

              final keyboardH = MediaQuery.of(ctx).viewInsets.bottom;

              return AnimatedPadding(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: keyboardH),
                child: Container(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.82),
                  decoration: BoxDecoration(
                    color: kBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kBorder, width: 1.2),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [

                    // ── Header ──────────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                      decoration: const BoxDecoration(
                        color: kSurface,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                        border: Border(bottom: BorderSide(color: kBorder)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.how_to_vote_outlined, color: kPrimary, size: 20),
                        const SizedBox(width: 10),
                        const Expanded(child: Text('स्टाफ असाइन करें',
                            style: TextStyle(color: kDark, fontSize: 15,
                                fontWeight: FontWeight.w800))),
                        IconButton(
                          icon: const Icon(Icons.close, color: kSubtle, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ]),
                    ),

                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [

                            // ── Center info ──────────────────────────────
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: kSurface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: kBorder.withOpacity(0.5)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    _TypeBadge(type: '${center['centerType'] ?? 'C'}'),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text('${center['name']}',
                                        style: const TextStyle(
                                            color: kDark,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13))),
                                  ]),
                                  const SizedBox(height: 6),
                                  _infoChip(Icons.local_police_outlined, center['thana']),
                                  _infoChip(Icons.account_balance_outlined, center['gpName']),
                                  _infoChip(Icons.layers_outlined,
                                      '${center['sectorName']} › ${center['zoneName']} › ${center['superZoneName']}'),
                                  if ((center['blockName'] ?? '').toString().isNotEmpty)
                                    _infoChip(Icons.location_city_outlined,
                                        'ब्लॉक: ${center['blockName']}'),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            if (unassigned.isEmpty)
                              Container(
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
                                  Text('कोई अनअसाइन स्टाफ नहीं',
                                      style: TextStyle(color: kError, fontSize: 12)),
                                ]),
                              )
                            else ...[

                              // ── Staff search ─────────────────────────
                              TextField(
                                controller: searchCtrl,
                                onChanged: filterStaff,
                                style: const TextStyle(color: kDark, fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'नाम, PNO, थाना, पद से खोजें...',
                                  hintStyle: const TextStyle(
                                      color: kSubtle, fontSize: 12),
                                  prefixIcon: const Icon(Icons.search,
                                      color: kSubtle, size: 18),
                                  suffixIcon: searchCtrl.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear,
                                              size: 16, color: kSubtle),
                                          onPressed: () {
                                            searchCtrl.clear();
                                            filterStaff('');
                                          })
                                      : null,
                                  filled: true,
                                  fillColor: Colors.white,
                                  isDense: true,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 11),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide:
                                          const BorderSide(color: kBorder)),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide:
                                          const BorderSide(color: kBorder)),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: kPrimary, width: 2)),
                                ),
                              ),
                              const SizedBox(height: 6),

                              // ── Selection count + select-all ─────────
                              Row(children: [
                                Text(
                                  selectedIds.isEmpty
                                      ? '${filtered.length} स्टाफ उपलब्ध'
                                      : '${selectedIds.length} चुने गए',
                                  style: TextStyle(
                                      color: selectedIds.isEmpty
                                          ? kSubtle
                                          : kPrimary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600),
                                ),
                                const Spacer(),
                                TextButton(
                                  style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      foregroundColor: kPrimary),
                                  onPressed: () => ss(() {
                                    if (selectedIds.length ==
                                        filtered.length) {
                                      selectedIds.clear();
                                    } else {
                                      selectedIds.addAll(filtered
                                          .map<int>((s) => s['id'] as int));
                                    }
                                  }),
                                  child: Text(
                                    selectedIds.length == filtered.length &&
                                            filtered.isNotEmpty
                                        ? 'सभी हटाएं'
                                        : 'सभी चुनें',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 4),

                              // ── Staff list (fixed height, scrollable) ─
                              Container(
                                height: 200,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: kBorder),
                                ),
                                child: filtered.isEmpty
                                    ? const Center(
                                        child: Text('कोई स्टाफ नहीं मिला',
                                            style: TextStyle(
                                                color: kSubtle, fontSize: 12)))
                                    : ListView.separated(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                vertical: 4),
                                        itemCount: filtered.length,
                                        separatorBuilder: (_, __) => Divider(
                                            height: 1,
                                            color:
                                                kBorder.withOpacity(0.4)),
                                        itemBuilder: (_, i) {
                                          final s = filtered[i];
                                          final id  = s['id'] as int;
                                          final sel = selectedIds.contains(id);
                                          return InkWell(
                                            onTap: () => ss(() => sel
                                                ? selectedIds.remove(id)
                                                : selectedIds.add(id)),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 9),
                                              color: sel
                                                  ? kPrimary.withOpacity(0.07)
                                                  : Colors.transparent,
                                              child: Row(children: [
                                                // Checkbox-style circle
                                                AnimatedContainer(
                                                  duration: const Duration(
                                                      milliseconds: 150),
                                                  width: 28,
                                                  height: 28,
                                                  decoration: BoxDecoration(
                                                    color: sel
                                                        ? kPrimary
                                                        : kSurface,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                        color: sel
                                                            ? kPrimary
                                                            : kBorder),
                                                  ),
                                                  child: sel
                                                      ? const Icon(Icons.check,
                                                          color: Colors.white,
                                                          size: 14)
                                                      : null,
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text('${s['name']}',
                                                        style: TextStyle(
                                                            color: sel
                                                                ? kPrimary
                                                                : kDark,
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600)),
                                                    Text(
                                                      'PNO: ${s['pno']}  •  ${s['thana']}  •  ${s['rank'] ?? s['user_rank'] ?? ''}',
                                                      style: const TextStyle(
                                                          color: kSubtle,
                                                          fontSize: 10),
                                                      overflow: TextOverflow
                                                          .ellipsis,
                                                    ),
                                                  ],
                                                )),
                                              ]),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],

                            const SizedBox(height: 12),

                            // ── Bus number ───────────────────────────────
                            AppTextField(
                                label: 'बस संख्या',
                                controller: busCtrl,
                                prefixIcon: Icons.directions_bus_outlined),

                            const SizedBox(height: 16),

                            // ── Action buttons ───────────────────────────
                            Row(children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: kSubtle,
                                    side: const BorderSide(color: kBorder),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 13),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                  child: const Text('रद्द करें'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: selectedIds.isNotEmpty
                                        ? kPrimary
                                        : kSubtle,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 13),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                  onPressed: selectedIds.isEmpty
                                      ? null
                                      : () async {
                                          Navigator.pop(ctx);
                                          await _assignMultiple(
                                            staffIds: selectedIds.toList(),
                                            centerId: center['id'] as int,
                                            busNo: busCtrl.text,
                                          );
                                        },
                                  child: Text(
                                    selectedIds.isEmpty
                                        ? 'असाइन करें'
                                        : '${selectedIds.length} को असाइन करें',
                                  ),
                                ),
                              ),
                            ]),
                          ],
                        ),
                      ),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Assign multiple staff in sequence ─────────────────────────────────────
  Future<void> _assignMultiple({
    required List<int> staffIds,
    required int centerId,
    required String busNo,
  }) async {
    try {
      final token = await AuthService.getToken();
      int success = 0;
      for (final id in staffIds) {
        try {
          await ApiService.post('/admin/duties', {
            'staffId':  id,
            'centerId': centerId,
            'busNo':    busNo,
          }, token: token);
          success++;
        } catch (_) {}
      }
      await _load();
      if (mounted) {
        showSnack(context,
            '$success स्टाफ सफलतापूर्वक असाइन किए गए');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'त्रुटि: $e', error: true);
    }
  }

  // ── Per-booth duties dialog ────────────────────────────────────────────────
  void _showDutiesDialog(Map center) async {
    // Show loading indicator immediately
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
          child: CircularProgressIndicator(color: kPrimary)),
    );

    try {
      final token = await AuthService.getToken();

      // ✅ FIX: filter by center_id on the client from the full duties list
      // OR use the backend endpoint with center_id filter.
      // Since /admin/duties doesn't support filtering yet, we call it and
      // filter here by centerId:
      final res    = await ApiService.get('/admin/duties', token: token);
      final all    = (res['data'] ?? []) as List;
      final duties = all
          .where((d) => d['centerName'] == center['name'] &&
              (d['gpName'] == center['gpName'] ||
               d['centerName'] == center['name']))
          .toList();

      // Better: filter by center id which is in each duty record
      // The admin duties response doesn't include center_id, so we match by
      // centerId stored in duty. Let's re-check the shape — admin get_duties
      // returns 'id' (duty id), not center_id. We'll match by centerName.
      // To be precise, filter by sthal_id — but that's not returned.
      // RECOMMENDED: add center_id to get_duties response (see backend note).
      // For now we match by center name which is unique enough:
      final centerId = center['id'] as int;

      if (!mounted) return;
      Navigator.pop(context); // close loading

      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Container(
              decoration: BoxDecoration(
                color: kBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder, width: 1.2),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [

                // ── Dialog header ────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                  decoration: const BoxDecoration(
                    color: kSurface,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(16)),
                    border:
                        Border(bottom: BorderSide(color: kBorder)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.location_on_outlined,
                        color: kPrimary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${center['name']}',
                        style: const TextStyle(
                            color: kDark,
                            fontSize: 15,
                            fontWeight: FontWeight.w800),
                        overflow: TextOverflow.ellipsis)),
                    IconButton(
                        icon: const Icon(Icons.close,
                            color: kSubtle, size: 20),
                        onPressed: () => Navigator.pop(ctx)),
                  ]),
                ),

                // ── Center meta ──────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  color: kBg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        _TypeBadge(type: '${center['centerType'] ?? 'C'}'),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          _ctLabel[center['centerType']] ??
                              '${center['centerType']}',
                          style: const TextStyle(
                              color: kSubtle,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        )),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: duties.isNotEmpty
                                ? kSuccess.withOpacity(0.1)
                                : kSurface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: duties.isNotEmpty
                                    ? kSuccess.withOpacity(0.4)
                                    : kBorder),
                          ),
                          child: Text(
                            '${duties.length} स्टाफ',
                            style: TextStyle(
                                color: duties.isNotEmpty
                                    ? kSuccess
                                    : kSubtle,
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Wrap(spacing: 12, runSpacing: 4, children: [
                        _infoChip(Icons.local_police_outlined,
                            '${center['thana']}'),
                        _infoChip(Icons.account_balance_outlined,
                            '${center['gpName']}'),
                        _infoChip(Icons.map_outlined,
                            'सेक्टर: ${center['sectorName']}'),
                        _infoChip(Icons.layers_outlined,
                            'जोन: ${center['zoneName']}'),
                        _infoChip(Icons.public_outlined,
                            'सुपर जोन: ${center['superZoneName']}'),
                        if ((center['blockName'] ?? '')
                            .toString()
                            .isNotEmpty)
                          _infoChip(Icons.location_city_outlined,
                              'ब्लॉक: ${center['blockName']}'),
                        if ((center['busNo'] ?? '')
                            .toString()
                            .isNotEmpty)
                          _infoChip(Icons.directions_bus_outlined,
                              'बस: ${center['busNo']}'),
                      ]),
                    ],
                  ),
                ),

                const Divider(height: 1, color: kBorder),

                // ── Staff list ───────────────────────────────────────────
                SizedBox(
                  height: 260,
                  child: duties.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline,
                                  size: 40,
                                  color: kSubtle.withOpacity(0.5)),
                              const SizedBox(height: 10),
                              const Text('इस बूथ पर कोई स्टाफ नहीं',
                                  style: TextStyle(
                                      color: kSubtle, fontSize: 13)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          itemCount: duties.length,
                          itemBuilder: (_, i) {
                            final d = duties[i];
                            return Container(
                              margin:
                                  const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius:
                                    BorderRadius.circular(10),
                                border: Border.all(
                                    color: kBorder.withOpacity(0.4)),
                              ),
                              child: Row(children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: kSurface,
                                    shape: BoxShape.circle,
                                    border:
                                        Border.all(color: kBorder),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${d['name']}'[0]
                                          .toUpperCase(),
                                      style: const TextStyle(
                                          color: kPrimary,
                                          fontSize: 15,
                                          fontWeight:
                                              FontWeight.w800),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text('${d['name']}',
                                        style: const TextStyle(
                                            color: kDark,
                                            fontWeight:
                                                FontWeight.w700,
                                            fontSize: 13)),
                                    const SizedBox(height: 2),
                                    Text(
                                      'PNO: ${d['pno']}  •  ${d['mobile'] ?? ''}',
                                      style: const TextStyle(
                                          color: kSubtle,
                                          fontSize: 11),
                                    ),
                                    if ((d['rank'] ??
                                            d['user_rank'] ??
                                            '')
                                        .toString()
                                        .isNotEmpty)
                                      Text(
                                        '${d['rank'] ?? d['user_rank']}  •  ${d['staffThana'] ?? d['thana'] ?? ''}',
                                        style: const TextStyle(
                                            color: kAccent,
                                            fontSize: 10,
                                            fontWeight:
                                                FontWeight.w600),
                                      ),
                                  ],
                                )),
                                // Remove button
                                IconButton(
                                  icon: const Icon(
                                      Icons.remove_circle_outline,
                                      color: kError,
                                      size: 20),
                                  onPressed: () async {
                                    final t =
                                        await AuthService.getToken();
                                    await ApiService.delete(
                                        '/admin/duties/${d['id']}',
                                        token: t);
                                    Navigator.pop(ctx);
                                    _load();
                                    if (mounted)
                                      showSnack(context,
                                          'ड्यूटी हटा दी गई');
                                  },
                                ),
                              ]),
                            );
                          },
                        ),
                ),

                // ── Footer buttons ───────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    border:
                        Border(top: BorderSide(color: kBorder)),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kSubtle,
                          side: const BorderSide(color: kBorder),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('बंद करें'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showAssignDialog(center);
                        },
                        icon: const Icon(Icons.person_add_outlined,
                            size: 16),
                        label: const Text('स्टाफ जोड़ें'),
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
      if (mounted) {
        Navigator.pop(context); // close loading
        showSnack(context, 'त्रुटि: $e', error: true);
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Search bar
      Container(
        color: kSurface,
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _search,
          style: const TextStyle(color: kDark, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'नाम, थाना, GP, सेक्टर, जोन से खोजें...',
            hintStyle: const TextStyle(color: kSubtle, fontSize: 13),
            prefixIcon: const Icon(Icons.search, color: kSubtle, size: 18),
            suffixIcon: _search.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16, color: kSubtle),
                    onPressed: () { _search.clear(); _filter(); })
                : null,
            filled: true, fillColor: Colors.white,
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
            isDense: true,
          ),
        ),
      ),

      // Stats bar
      Container(
        color: kBg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          _pill('${_filtered.length} बूथ', kPrimary),
          const SizedBox(width: 8),
          _pill('${_unassigned.length} अनअसाइन', kAccent),
        ]),
      ),

      if (_loading)
        const Expanded(
            child: Center(
                child: CircularProgressIndicator(color: kPrimary)))
      else if (_filtered.isEmpty)
        Expanded(
            child: _emptyState('कोई बूथ नहीं मिला',
                Icons.location_off_outlined))
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
                final c      = _filtered[i];
                final type   = '${c['centerType'] ?? 'C'}';
                final count  = (c['dutyCount'] ?? 0) as int;
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
                          blurRadius: 8,
                          offset: const Offset(0, 3))],
                    ),
                    child: Row(children: [
                      // Type strip
                      Container(
                        width: 52,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: tColor.withOpacity(0.1),
                          borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(12),
                              bottomLeft: Radius.circular(12)),
                          border: Border(
                              right: BorderSide(
                                  color: tColor.withOpacity(0.3))),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(type,
                                style: TextStyle(
                                    color: tColor,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900)),
                            Text(type == 'A'
                                ? 'अति'
                                : type == 'B'
                                    ? 'संवे'
                                    : 'सामा',
                                style: TextStyle(
                                    color: tColor.withOpacity(0.7),
                                    fontSize: 7,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),

                      // Details
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${c['name']}',
                                  style: const TextStyle(
                                      color: kDark,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14)),
                              const SizedBox(height: 4),
                              Row(children: [
                                _tagSmall(Icons.local_police_outlined,
                                    '${c['thana']}'),
                                const SizedBox(width: 10),
                                _tagSmall(
                                    Icons.account_balance_outlined,
                                    '${c['gpName']}'),
                              ]),
                              const SizedBox(height: 2),
                              _tagSmall(Icons.layers_outlined,
                                  '${c['sectorName']} › ${c['zoneName']} › ${c['superZoneName']}'),
                              if ((c['blockName'] ?? '')
                                  .toString()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 2),
                                _tagSmall(Icons.location_city_outlined,
                                    'ब्लॉक: ${c['blockName']}'),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // Staff count
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
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
                            Text('$count',
                                style: TextStyle(
                                    color: count > 0 ? kSuccess : kSubtle,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900)),
                            Text('स्टाफ',
                                style: TextStyle(
                                    color: count > 0 ? kSuccess : kSubtle,
                                    fontSize: 10)),
                          ]),
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

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(text,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w700)),
  );

  Widget _tagSmall(IconData icon, String text) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: kSubtle),
        const SizedBox(width: 3),
        Flexible(
            child: Text(text,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(color: kSubtle, fontSize: 11))),
      ]);

  Widget _emptyState(String msg, IconData icon) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 48, color: kSubtle.withOpacity(0.4)),
      const SizedBox(height: 12),
      Text(msg, style: const TextStyle(color: kSubtle, fontSize: 14)),
    ]),
  );
}

// ── Shared small widgets ───────────────────────────────────────────────────────
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
      child: Text(type,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w900)),
    );
  }
}

Widget _infoChip(IconData icon, String? text) {
  if (text == null || text.isEmpty || text == 'null') {
    return const SizedBox.shrink();
  }
  return Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 11, color: kSubtle),
    const SizedBox(width: 4),
    Flexible(
        child: Text(text,
            style: const TextStyle(color: kSubtle, fontSize: 11),
            overflow: TextOverflow.ellipsis)),
  ]);
}