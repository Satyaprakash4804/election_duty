import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';
import 'hierarchy_report_page.dart';

// ── Sensitivity meta ──────────────────────────────────────────────────────────
const _kSensitivities = [
  {'key': 'A++', 'hi': 'अति-अति संवेदनशील', 'color': Color(0xFF6C3483)},
  {'key': 'A',   'hi': 'अति संवेदनशील',      'color': Color(0xFFC0392B)},
  {'key': 'B',   'hi': 'संवेदनशील',           'color': Color(0xFFE67E22)},
  {'key': 'C',   'hi': 'सामान्य',             'color': Color(0xFF1A5276)},
];

// ── All staff ranks ───────────────────────────────────────────────────────────
const _kRanks = [
  {'en': 'SP',             'hi': 'पुलिस अधीक्षक'},
  {'en': 'ASP',            'hi': 'सहा० पुलिस अधीक्षक'},
  {'en': 'DSP',            'hi': 'पुलिस उपाधीक्षक'},
  {'en': 'Inspector',      'hi': 'निरीक्षक'},
  {'en': 'SI',             'hi': 'उप निरीक्षक'},
  {'en': 'ASI',            'hi': 'सहा० उप निरीक्षक'},
  {'en': 'Head Constable', 'hi': 'मुख्य आरक्षी'},
  {'en': 'Constable',      'hi': 'आरक्षी'},
];

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with AutomaticKeepAliveClientMixin {

  Map<String, dynamic>? _stats;
  final List<dynamic>   _duties = [];

  bool _loadingStats  = true;
  bool _loadingDuties = true;
  bool _loadingMore   = false;
  bool _hasMore       = true;

  int _page  = 1;
  int _total = 0;
  static const int _pageSize = 20;

  final ScrollController _scrollCtrl = ScrollController();

  // Rules: sensitivity → { rank → count }
  // Stored as map for easy lookup by rank
  final Map<String, Map<String, int>> _rules = {
    'A++': {}, 'A': {}, 'B': {}, 'C': {},
  };
  bool _loadingRules = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadStats();
    _loadDuties(reset: true);
    _loadAllRules();
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      if (!_loadingMore && _hasMore) _loadDuties();
    }
  }

  // ── Load overview stats ───────────────────────────────────────────────────
  Future<void> _loadStats() async {
    if (mounted) setState(() => _loadingStats = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get('/admin/overview', token: token);
      if (mounted) setState(() => _stats = res['data'] as Map<String, dynamic>?);
    } catch (e) {
      _handleError(e);
    } finally {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  // ── Load duties paginated ─────────────────────────────────────────────────
  Future<void> _loadDuties({bool reset = false}) async {
    if (reset) {
      setState(() {
        _duties.clear();
        _page = 1; _hasMore = true; _loadingDuties = true;
      });
    } else {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    }
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get(
        '/admin/duties?page=$_page&limit=$_pageSize',
        token: token,
      );
      final wrapper    = (res['data'] as Map<String, dynamic>?) ?? {};
      final items      = (wrapper['data']       as List?)?.cast<dynamic>() ?? [];
      final total      = (wrapper['total']      as num?)?.toInt() ?? 0;
      final totalPages = (wrapper['totalPages'] as num?)?.toInt() ?? 1;
      if (mounted) {
        setState(() {
          _duties.addAll(items);
          _total   = total;
          _hasMore = _page < totalPages;
          _page++;
        });
      }
    } catch (e) {
      _handleError(e);
    } finally {
      if (mounted) setState(() { _loadingDuties = false; _loadingMore = false; });
    }
  }

  // ── Load rules for all sensitivities ─────────────────────────────────────
  Future<void> _loadAllRules() async {
    if (mounted) setState(() => _loadingRules = true);
    try {
      final token = await AuthService.getToken();
      await Future.wait(['A++', 'A', 'B', 'C'].map((s) async {
        try {
          final res = await ApiService.get(
            '/admin/rules?sensitivity=${Uri.encodeComponent(s)}',
            token: token,
          );
          final raw  = res['data'];
          final list = raw is List ? raw
              : (raw is Map && raw['data'] is List) ? raw['data'] as List
              : <dynamic>[];

          // Build rank→count map; backend returns {rank, required_count}
          final Map<String, int> rankMap = {};
          for (final r in list) {
            final rank  = (r['rank'] ?? r['user_rank'] ?? '').toString();
            final count = ((r['required_count'] ?? r['count'] ?? 0) as num).toInt();
            if (rank.isNotEmpty) rankMap[rank] = count;
          }
          if (mounted) setState(() => _rules[s] = rankMap);
        } catch (e) {
          debugPrint('Rules load failed for $s: $e');
        }
      }));
    } finally {
      if (mounted) setState(() => _loadingRules = false);
    }
  }

  // ── Save rules for one sensitivity ───────────────────────────────────────
  Future<bool> _saveRules(String sensitivity, Map<String, int> rankMap) async {
    try {
      final token = await AuthService.getToken();
      final rules = rankMap.entries
          .map((e) => {'rank': e.key, 'count': e.value})
          .toList();
      await ApiService.post(
        '/admin/rules',
        {'sensitivity': sensitivity, 'rules': rules},
        token: token,
      );
      if (mounted) setState(() => _rules[sensitivity] = Map.from(rankMap));
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _refresh() async {
    await Future.wait([
      _loadStats(),
      _loadDuties(reset: true),
      _loadAllRules(),
    ]);
  }

  void _handleError(Object e) {
    if (!mounted) return;
    if (e.toString().contains('Session expired')) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      return;
    }
    showSnack(context, 'Error: $e', error: true);
  }

  // ── Open मानक edit modal ──────────────────────────────────────────────────
  void _openManakModal(String sensitivity, Color color, String hindi) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ManakModal(
        sensitivity:  sensitivity,
        color:        color,
        hindi:        hindi,
        initialRules: Map.from(_rules[sensitivity] ?? {}),
        onSave: (updated) async {
          final ok = await _saveRules(sensitivity, updated);
          if (mounted) {
            showSnack(
              context,
              ok ? '$sensitivity मानक सेव हो गया ✓' : 'सेव विफल, पुनः प्रयास करें',
              error: !ok,
            );
          }
          return ok;
        },
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final sw = MediaQuery.of(context).size.width;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: kPrimary,
      child: CustomScrollView(
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [

          // ── Stats grid ───────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: _loadingStats
                  ? _StatsShimmer(cols: sw > 500 ? 4 : 2)
                  : _StatsGrid(stats: _stats, sw: sw),
            ),
          ),

          // ── Hierarchy banner ─────────────────────────────────────────────
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: _HierarchyBanner(),
            ),
          ),

          // ── मानक section ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: _ManakSection(
                rules:       _rules,
                loading:     _loadingRules,
                onTapSens:   _openManakModal,
              ),
            ),
          ),

          // ── Section header ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SectionHeader('Recent Duty Assignments'),
                  if (_total > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: kPrimary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('$_total total',
                          style: const TextStyle(
                              fontSize: 11,
                              color: kPrimary,
                              fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
          ),

          // ── Duty list ────────────────────────────────────────────────────
          if (_loadingDuties)
            SliverList(delegate: SliverChildBuilderDelegate(
              (_, __) => const _DutyShimmer(), childCount: 6))
          else if (_duties.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: _EmptyDuties(),
              ),
            )
          else if (sw > 700)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _DutyCard(duty: _duties[i]),
                  childCount: _duties.length,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, crossAxisSpacing: 10,
                  mainAxisSpacing: 10, childAspectRatio: 2.7,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) => _DutyCard(duty: _duties[i]),
                childCount: _duties.length,
              )),
            ),

          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(child: SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: kPrimary))),
              ),
            ),

          if (!_hasMore && _duties.isNotEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: Text('— End of list —',
                    style: TextStyle(color: kSubtle, fontSize: 12))),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  मानक Section — 4 tappable sensitivity tiles on dashboard
// ══════════════════════════════════════════════════════════════════════════════
class _ManakSection extends StatelessWidget {
  final Map<String, Map<String, int>> rules;
  final bool loading;
  final void Function(String sensitivity, Color color, String hindi) onTapSens;

  const _ManakSection({
    required this.rules,
    required this.loading,
    required this.onTapSens,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder.withOpacity(0.4)),
        boxShadow: [BoxShadow(
            color: kPrimary.withOpacity(0.06),
            blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: kSurface.withOpacity(0.6),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border(bottom: BorderSide(color: kBorder.withOpacity(0.3))),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(9)),
              child: const Icon(Icons.rule_folder_outlined,
                  color: kPrimary, size: 18),
            ),
            const SizedBox(width: 10),
            const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('मानक (Rules)',
                  style: TextStyle(color: kDark, fontSize: 14,
                      fontWeight: FontWeight.w800)),
              Text('श्रेणी पर टैप करें — संपादित करें',
                  style: TextStyle(color: kSubtle, fontSize: 10)),
            ])),
            // All-set badge
            Builder(builder: (_) {
              final allSet = _kSensitivities
                  .every((s) => (rules[s['key']] ?? {}).isNotEmpty);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: allSet
                      ? kSuccess.withOpacity(0.1)
                      : kError.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: allSet
                          ? kSuccess.withOpacity(0.3)
                          : kError.withOpacity(0.2)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(allSet
                      ? Icons.check_circle_rounded
                      : Icons.pending_outlined,
                      size: 11,
                      color: allSet ? kSuccess : kError),
                  const SizedBox(width: 4),
                  Text(allSet ? 'सभी सेट' : 'अधूरे',
                      style: TextStyle(
                          color: allSet ? kSuccess : kError,
                          fontSize: 10, fontWeight: FontWeight.w700)),
                ]),
              );
            }),
          ]),
        ),

        // 4 sensitivity tiles
        Padding(
          padding: const EdgeInsets.all(12),
          child: loading
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(20),
                  child: SizedBox(width: 24, height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: kPrimary))))
              : GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.55,
                  children: _kSensitivities.map((s) {
                    final key    = s['key']   as String;
                    final color  = s['color'] as Color;
                    final hindi  = s['hi']    as String;
                    final rankMap = rules[key] ?? {};
                    final isSet  = rankMap.isNotEmpty;
                    final total  = rankMap.values.fold(0, (a, b) => a + b);

                    return _SensTile(
                      label:   key,
                      hindi:   hindi,
                      color:   color,
                      isSet:   isSet,
                      total:   total,
                      rankMap: rankMap,
                      onTap:   () => onTapSens(key, color, hindi),
                    );
                  }).toList(),
                ),
        ),

        // Footer hint
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: Row(children: const [
            Icon(Icons.touch_app_outlined, size: 12, color: kSubtle),
            SizedBox(width: 5),
            Text('बूथ की संवेदनशीलता के अनुसार स्टाफ स्वतः असाइन होगा',
                style: TextStyle(color: kSubtle, fontSize: 10)),
          ]),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Sensitivity tile — tappable, shows current rule summary
// ══════════════════════════════════════════════════════════════════════════════
class _SensTile extends StatelessWidget {
  final String label, hindi;
  final Color color;
  final bool isSet;
  final int total;
  final Map<String, int> rankMap;
  final VoidCallback onTap;

  const _SensTile({
    required this.label,
    required this.hindi,
    required this.color,
    required this.isSet,
    required this.total,
    required this.rankMap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Build a short summary like "SI×2, Constable×4"
    final summary = rankMap.entries
        .where((e) => e.value > 0)
        .map((e) => '${e.key}×${e.value}')
        .join(', ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: isSet ? color.withOpacity(0.07) : kError.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isSet ? color.withOpacity(0.3) : kError.withOpacity(0.2)),
          ),
          padding: const EdgeInsets.all(11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                // Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isSet ? color : kError,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900)),
                ),
                const Spacer(),
                // Status icon
                Icon(
                  isSet ? Icons.check_circle_rounded : Icons.edit_outlined,
                  size: 15,
                  color: isSet ? kSuccess : kSubtle,
                ),
              ]),
              const SizedBox(height: 6),
              Text(hindi,
                  style: TextStyle(
                      color: isSet ? color : kSubtle,
                      fontSize: 9,
                      fontWeight: FontWeight.w600),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const Spacer(),
              if (isSet && total > 0) ...[
                Text('$total कर्मचारी',
                    style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w900)),
                if (summary.isNotEmpty)
                  Text(summary,
                      style: const TextStyle(
                          color: kSubtle, fontSize: 9),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              ] else
                Row(children: [
                  Icon(Icons.add_circle_outline,
                      size: 12, color: isSet ? color : kSubtle),
                  const SizedBox(width: 4),
                  Text(isSet ? 'संपादित करें' : 'सेट करें',
                      style: TextStyle(
                          color: isSet ? color : kSubtle,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  मानक Modal — shown when user taps a sensitivity tile
// ══════════════════════════════════════════════════════════════════════════════
class _ManakModal extends StatefulWidget {
  final String sensitivity, hindi;
  final Color color;
  final Map<String, int> initialRules;
  final Future<bool> Function(Map<String, int>) onSave;

  const _ManakModal({
    required this.sensitivity,
    required this.hindi,
    required this.color,
    required this.initialRules,
    required this.onSave,
  });

  @override
  State<_ManakModal> createState() => _ManakModalState();
}

class _ManakModalState extends State<_ManakModal> {
  // rank → TextEditingController (count, default 0)
  late final Map<String, TextEditingController> _ctrls;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrls = {
      for (final r in _kRanks)
        r['en']!: TextEditingController(
          text: '${widget.initialRules[r['en']] ?? 0}',
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) c.dispose();
    super.dispose();
  }

  int get _totalStaff => _ctrls.values.fold(0, (sum, c) {
        final n = int.tryParse(c.text) ?? 0;
        return sum + (n < 0 ? 0 : n);
      });

  Future<void> _save() async {
    setState(() => _saving = true);
    final map = <String, int>{};
    for (final r in _kRanks) {
      final n = int.tryParse(_ctrls[r['en']]!.text) ?? 0;
      if (n > 0) map[r['en']!] = n;
    }
    final ok = await widget.onSave(map);
    if (mounted) {
      setState(() => _saving = false);
      if (ok) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFDF6E3),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(0, 0, 0, bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [

        // Drag handle
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 4),
          width: 40, height: 4,
          decoration: BoxDecoration(
              color: const Color(0xFFD4A843).withOpacity(0.4),
              borderRadius: BorderRadius.circular(2)),
        ),

        // Modal header
        Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: const Color(0xFFD4A843).withOpacity(0.25))),
          ),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: widget.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: widget.color.withOpacity(0.3)),
              ),
              child: Center(
                child: Text(widget.sensitivity,
                    style: TextStyle(
                        color: widget.color,
                        fontSize: widget.sensitivity.length > 2 ? 10 : 14,
                        fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${widget.sensitivity} मानक',
                  style: const TextStyle(
                      color: Color(0xFF4A3000),
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              Text(widget.hindi,
                  style: TextStyle(
                      color: widget.color, fontSize: 11)),
            ])),
            // Total badge
            StatefulBuilder(builder: (_, set) {
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: widget.color.withOpacity(0.3)),
                ),
                child: Text('$_totalStaff कुल',
                    style: TextStyle(
                        color: widget.color,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
              );
            }),
          ]),
        ),

        // Ranks list — scrollable
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.52,
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10),
            itemCount: _kRanks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final rank = _kRanks[i];
              final en   = rank['en']!;
              final hi   = rank['hi']!;
              final ctrl = _ctrls[en]!;

              return StatefulBuilder(builder: (_, set) {
                final count = int.tryParse(ctrl.text) ?? 0;
                final active = count > 0;

                return Container(
                  decoration: BoxDecoration(
                    color: active
                        ? widget.color.withOpacity(0.06)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: active
                          ? widget.color.withOpacity(0.3)
                          : const Color(0xFFD4A843).withOpacity(0.3),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  child: Row(children: [

                    // Rank info
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(hi,
                            style: TextStyle(
                                color: active
                                    ? widget.color
                                    : const Color(0xFF4A3000),
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        Text(en,
                            style: const TextStyle(
                                color: Color(0xFFAA8844),
                                fontSize: 10)),
                      ],
                    )),

                    // Number input — type directly
                    Container(
                      width: 54,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: active
                              ? widget.color
                              : const Color(0xFFD4A843).withOpacity(0.6),
                          width: active ? 1.5 : 1,
                        ),
                      ),
                      child: TextField(
                        controller: ctrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                        ],
                        style: TextStyle(
                          color: active
                              ? widget.color
                              : const Color(0xFF4A3000),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              vertical: 9),
                        ),
                        onChanged: (_) => set(() {}),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Quick ± buttons
                    Column(children: [
                      _TinyBtn(
                        icon: Icons.add,
                        color: widget.color,
                        onTap: () {
                          final n = (int.tryParse(ctrl.text) ?? 0) + 1;
                          if (n <= 99) {
                            ctrl.text = '$n';
                            set(() {});
                          }
                        },
                      ),
                      const SizedBox(height: 3),
                      _TinyBtn(
                        icon: Icons.remove,
                        color: count > 0
                            ? const Color(0xFFC0392B)
                            : const Color(0xFFAA8844),
                        onTap: () {
                          final n = (int.tryParse(ctrl.text) ?? 0) - 1;
                          if (n >= 0) {
                            ctrl.text = '$n';
                            set(() {});
                          }
                        },
                      ),
                    ]),
                  ]),
                );
              });
            },
          ),
        ),

        // Save button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(
                _saving
                    ? 'सेव हो रहा है...'
                    : '${widget.sensitivity} मानक सेव करें',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _saving
                    ? const Color(0xFFAA8844)
                    : widget.color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Tiny +/- button ───────────────────────────────────────────────────────────
class _TinyBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _TinyBtn(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26, height: 17,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Icon(icon, size: 12, color: color),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Stats Grid
// ══════════════════════════════════════════════════════════════════════════════
class _StatsGrid extends StatelessWidget {
  final Map<String, dynamic>? stats;
  final double sw;
  const _StatsGrid({required this.stats, required this.sw});

  @override
  Widget build(BuildContext context) {
    if (stats == null) return const SizedBox.shrink();
    final cols  = sw > 600 ? 4 : 2;
    final items = [
      _SI('Super Zones',  '${stats!['superZones']     ?? 0}',
          Icons.layers_outlined,      kPrimary),
      _SI('Total Booths', '${stats!['totalBooths']    ?? 0}',
          Icons.location_on_outlined, kSuccess),
      _SI('Total Staff',  '${stats!['totalStaff']     ?? 0}',
          Icons.badge_outlined,       kAccent),
      _SI('Assigned',     '${stats!['assignedDuties'] ?? 0}',
          Icons.how_to_vote_outlined, kInfo),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols, crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: sw > 600 ? 1.7 : 1.45,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _StatCard(item: items[i]),
    );
  }
}

class _SI {
  final String label, value;
  final IconData icon;
  final Color color;
  const _SI(this.label, this.value, this.icon, this.color);
}

class _StatCard extends StatelessWidget {
  final _SI item;
  const _StatCard({required this.item});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: item.color.withOpacity(0.18)),
        boxShadow: [BoxShadow(
            color: item.color.withOpacity(0.07),
            blurRadius: 10, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: item.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(9)),
            child: Icon(item.icon, color: item.color, size: 17),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.value,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
                    color: item.color, height: 1)),
            const SizedBox(height: 3),
            Text(item.label,
                style: const TextStyle(fontSize: 11, color: kSubtle,
                    fontWeight: FontWeight.w500)),
          ]),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Shimmer
// ══════════════════════════════════════════════════════════════════════════════
class _StatsShimmer extends StatelessWidget {
  final int cols;
  const _StatsShimmer({required this.cols});
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols, crossAxisSpacing: 10,
        mainAxisSpacing: 10, childAspectRatio: 1.45,
      ),
      itemCount: 4,
      itemBuilder: (_, __) => _Shimmer(radius: 14),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Hierarchy Banner
// ══════════════════════════════════════════════════════════════════════════════
class _HierarchyBanner extends StatelessWidget {
  const _HierarchyBanner();
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const HierarchyReportPage())),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F2B5B), Color(0xFF1E4D9B)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(
                color: const Color(0xFF0F2B5B).withOpacity(0.3),
                blurRadius: 14, offset: const Offset(0, 5))],
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(9)),
              child: const Icon(Icons.table_chart_outlined,
                  color: Colors.white, size: 19),
            ),
            const SizedBox(width: 13),
            const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('प्रशासनिक पदानुक्रम रिपोर्ट',
                  style: TextStyle(color: Colors.white, fontSize: 14,
                      fontWeight: FontWeight.w800)),
              SizedBox(height: 2),
              Text('Super Zone · Sector · Panchayat Tables',
                  style: TextStyle(color: Colors.white60, fontSize: 11)),
            ])),
            const Icon(Icons.chevron_right, color: Colors.white54, size: 20),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Empty Duties
// ══════════════════════════════════════════════════════════════════════════════
class _EmptyDuties extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder.withOpacity(0.3)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.08), shape: BoxShape.circle),
          child: const Icon(Icons.how_to_vote_outlined,
              size: 40, color: kPrimary),
        ),
        const SizedBox(height: 14),
        const Text('No duties assigned yet',
            style: TextStyle(color: kDark, fontSize: 14,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('Pull down to refresh',
            style: TextStyle(color: kSubtle, fontSize: 12)),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Duty Card
// ══════════════════════════════════════════════════════════════════════════════
class _DutyCard extends StatelessWidget {
  final dynamic duty;
  const _DutyCard({required this.duty});

  Color _tc(String t) {
    switch (t.toUpperCase()) {
      case 'A': return kSuccess;
      case 'B': return kInfo;
      default:  return kAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = '${duty['centerType'] ?? 'C'}';
    final tc   = _tc(type);
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder.withOpacity(0.28)),
        boxShadow: [BoxShadow(
            color: kDark.withOpacity(0.04),
            blurRadius: 7, offset: const Offset(0, 3))],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                color: tc.withOpacity(0.1), shape: BoxShape.circle,
                border: Border.all(color: tc.withOpacity(0.35))),
            child: Center(child: Text(type,
                style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w900, color: tc))),
          ),
          const SizedBox(width: 11),
          Expanded(flex: 3, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${duty['name'] ?? '-'}',
                  style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w700, color: kDark),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.badge_outlined, size: 10, color: kSubtle),
                const SizedBox(width: 3),
                Text('${duty['pno'] ?? '-'}',
                    style: const TextStyle(fontSize: 11, color: kSubtle)),
              ]),
            ],
          )),
          Container(width: 1, height: 28,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: kBorder.withOpacity(0.3)),
          Expanded(flex: 4, child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${duty['centerName'] ?? '-'}',
                  style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w700, color: kDark),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end),
              const SizedBox(height: 2),
              Text('${duty['superZoneName'] ?? '-'}',
                  style: const TextStyle(fontSize: 11, color: kSubtle),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end),
            ],
          )),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Duty Shimmer
// ══════════════════════════════════════════════════════════════════════════════
class _DutyShimmer extends StatelessWidget {
  const _DutyShimmer();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 9),
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder.withOpacity(0.2)),
        ),
        child: Row(children: [
          const SizedBox(width: 13),
          _Shimmer(width: 36, height: 36, radius: 18),
          const SizedBox(width: 11),
          Expanded(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Shimmer(width: 110, height: 11, radius: 4),
            const SizedBox(height: 6),
            _Shimmer(width: 75, height: 9, radius: 4),
          ])),
          Column(mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end, children: [
            _Shimmer(width: 95, height: 11, radius: 4),
            const SizedBox(height: 6),
            _Shimmer(width: 65, height: 9, radius: 4),
          ]),
          const SizedBox(width: 13),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Shimmer animation
// ══════════════════════════════════════════════════════════════════════════════
class _Shimmer extends StatefulWidget {
  final double? width, height;
  final double radius;
  const _Shimmer({this.width, this.height, this.radius = 6});
  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>    _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width, height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          color: Color.lerp(
              const Color(0xFFEDE8D5),
              const Color(0xFFF5EED8), _anim.value),
        ),
      ),
    );
  }
}

// ── Shared palette constants ──────────────────────────────────────────────────
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