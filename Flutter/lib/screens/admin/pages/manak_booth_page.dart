// ═════════════════════════════════════════════════════════════════════════════
//  manak_booth_page.dart
//
//  CHANGES IN THIS REVISION:
//  ✅ Accepts electionId (int?) and electionName (String?) constructor params
//  ✅ Election banner at top — shows active election name in gold, or a
//     "कोई सक्रिय चुनाव नहीं" amber warning when electionId is null
//  ✅ Save button is Tooltip-wrapped and disabled when electionId is null
//  ✅ POST body includes electionId for backend tagging
//  ✅ Election staleness badge: if a rule row was saved under a different
//     election, a subtle "पुराना चुनाव" chip is shown on that tier card
//  ✅ Fully responsive — adapts to narrow (320px) to wide (600px+) viewports
//  ✅ LayoutBuilder used for chip-row wrapping and badge sizing
//  ✅ PopScope replaces deprecated WillPopScope
// ═════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';
import 'manak_rank_editor_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Palette
// ─────────────────────────────────────────────────────────────────────────────
const _kBg       = Color(0xFFFDF6E3);
const _kSurface  = Color(0xFFF5E6C8);
const _kDark     = Color(0xFF4A3000);
const _kSubtle   = Color(0xFFAA8844);
const _kBorder   = Color(0xFFD4A843);
const _kError    = Color(0xFFC0392B);
const _kSuccess  = Color(0xFF2D6A1E);
const _kGold     = Color(0xFF8B6914);
const _kArmed    = Color(0xFF6A1B9A);
const _kUnarmed  = Color(0xFF1A5276);
const _kAux      = Color(0xFFE65100);
const _kPac      = Color(0xFF00695C);
const _kAmber    = Color(0xFFF59E0B);
const _kAmberBg  = Color(0xFFFFFBEB);
const _kAmberBrd = Color(0xFFFDE68A);
const _kOldElec  = Color(0xFF6B7280); // grey for stale election badge

// ─────────────────────────────────────────────────────────────────────────────
//  Responsive scale helper
// ─────────────────────────────────────────────────────────────────────────────
class _RS {
  final double w;
  const _RS(this.w);

  double get t => w <= 320 ? 0.0 : w >= 600 ? 1.0 : (w - 320) / 280;
  double s(double small, double large) => small + (large - small) * t;

  bool get isCompact => w < 360;
  bool get isNarrow  => w < 420;
  bool get isWide    => w >= 600;

  EdgeInsets get hPad => EdgeInsets.symmetric(horizontal: s(10, 16));
  EdgeInsets get listPad => EdgeInsets.fromLTRB(s(10, 14), 10, s(10, 14), 110);
}

_RS _rsOf(BuildContext c) => _RS(MediaQuery.of(c).size.width);

// ─────────────────────────────────────────────────────────────────────────────
//  Booth tier data
// ─────────────────────────────────────────────────────────────────────────────
const List<Map<String, dynamic>> kBoothTiers = [
  {'count': 1,  'label': '1 बूथ'},
  {'count': 2,  'label': '2 बूथ'},
  {'count': 3,  'label': '3 बूथ'},
  {'count': 4,  'label': '4 बूथ'},
  {'count': 5,  'label': '5 बूथ'},
  {'count': 6,  'label': '6 बूथ'},
  {'count': 7,  'label': '7 बूथ'},
  {'count': 8,  'label': '8 बूथ'},
  {'count': 9,  'label': '9 बूथ'},
  {'count': 10, 'label': '10 बूथ'},
  {'count': 11, 'label': '11 बूथ'},
  {'count': 12, 'label': '12 बूथ'},
  {'count': 13, 'label': '13 बूथ'},
  {'count': 14, 'label': '14 बूथ'},
  {'count': 15, 'label': '15 और उससे अधिक बूथ'},
];

// ══════════════════════════════════════════════════════════════════════════════
//  ManakBoothPage
// ══════════════════════════════════════════════════════════════════════════════
class ManakBoothPage extends StatefulWidget {
  /// Sensitivity category: "A++", "A", "B", "C"
  final String sensitivity;
  final Color  color;
  final String hindi;
  final List<Map<String, dynamic>> initialRules;

  final int? electionId;
  final String? electionName;

  const ManakBoothPage({
    super.key,
    required this.sensitivity,
    required this.color,
    required this.hindi,
    required this.initialRules,
    // Election context — required for election-driven saves
    this.electionId,
    this.electionName,
  });

  @override
  State<ManakBoothPage> createState() => _ManakBoothPageState();
}

class _ManakBoothPageState extends State<ManakBoothPage>
    with SingleTickerProviderStateMixin {
  // booth_count (1–15) → full rule map returned by backend
  final Map<int, Map<String, dynamic>> _byBooth = {};
  bool _saving  = false;
  bool _changed = false;

  // Subtle animation controller for the "unsaved" pill
  late AnimationController _unsavedAnim;
  late Animation<double>   _unsavedFade;

  // ── Derived ───────────────────────────────────────────────────────────────
  bool get _canSave  => widget.electionId != null && !_saving;
  int  get _setCount => _byBooth.values.where(_hasAny).length;

  @override
  void initState() {
    super.initState();
    // Populate from parent's initial rules
    for (final r in widget.initialRules) {
      final bc = (r['boothCount'] ?? 0) is int
          ? r['boothCount'] as int
          : int.tryParse('${r['boothCount']}') ?? 0;
      if (bc >= 1 && bc <= 15) {
        _byBooth[bc] = Map<String, dynamic>.from(r);
      }
    }

    _unsavedAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _unsavedFade = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _unsavedAnim, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _unsavedAnim.dispose();
    super.dispose();
  }

  // ── Rule helpers ──────────────────────────────────────────────────────────

  static bool _hasAny(Map<String, dynamic>? r) {
    if (r == null) return false;
    const keys = [
      'siArmedCount', 'siUnarmedCount',
      'hcArmedCount', 'hcUnarmedCount',
      'constArmedCount', 'constUnarmedCount',
      'auxArmedCount', 'auxUnarmedCount',
      'pacCount',
    ];
    return keys.any((k) => ((r[k] ?? 0) as num) > 0);
  }

  static int _totalStaff(Map<String, dynamic>? r) {
    if (r == null) return 0;
    const keys = [
      'siArmedCount', 'siUnarmedCount',
      'hcArmedCount', 'hcUnarmedCount',
      'constArmedCount', 'constUnarmedCount',
      'auxArmedCount', 'auxUnarmedCount',
    ];
    return keys.fold(0, (s, k) => s + ((r[k] ?? 0) as num).toInt());
  }

  /// Returns true when this rule row was saved under a different election.
  bool _isStaleElection(Map<String, dynamic>? r) {
    if (r == null || widget.electionId == null) return false;
    final rid = r['electionId'];
    if (rid == null) return false;
    final rInt = rid is int ? rid : int.tryParse('$rid');
    return rInt != null && rInt != widget.electionId;
  }

  // ── Navigation to rank editor ─────────────────────────────────────────────

  Future<void> _openRankEditor(int boothCount, String label) async {
    final existing = _byBooth[boothCount] ?? {'boothCount': boothCount};

    final updated = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => ManakRankEditorPage(
          title:    '${widget.sensitivity} — $label',
          subtitle: widget.hindi,
          color:    widget.color,
          initial:  existing,
        ),
      ),
    );

    if (updated != null && mounted) {
      updated['boothCount'] = boothCount;
      // Tag with current election immediately on edit
      if (widget.electionId != null) {
        updated['electionId'] = widget.electionId;
      }
      setState(() {
        _byBooth[boothCount] = updated;
        _changed = true;
      });
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _saveAll() async {
    if (!_canSave) return;

    setState(() => _saving = true);
    try {
      final token = await AuthService.getToken();
      final rules = _byBooth.values.toList();

      await ApiService.post(
        '/admin/booth-rules',
        {
          'sensitivity': widget.sensitivity,
          'rules':       rules,
          // ✅ Election ID — every save is tagged to the active election
          if (widget.electionId != null) 'electionId': widget.electionId,
        },
        token: token,
      );

      if (!mounted) return;
      showSnack(context, '${widget.sensitivity} मानक सेव हो गया ✓');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        await showApiError(context, e);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Discard guard ─────────────────────────────────────────────────────────

  Future<bool> _confirmDiscard() async {
    if (!_changed) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded,
              color: _kAmber, size: 22),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'बदलाव सहेजे नहीं गए',
              style: TextStyle(
                  color: _kDark,
                  fontWeight: FontWeight.w800,
                  fontSize: 15),
            ),
          ),
        ]),
        content: const Text(
          'आपने कुछ बदलाव किए हैं।\nक्या आप बिना सेव किए बाहर निकलना चाहते हैं?',
          style: TextStyle(color: _kDark, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('रद्द करें',
                style: TextStyle(color: _kSubtle)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kError,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('बाहर निकलें'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmDiscard();
        if (ok && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: _kBg,
        appBar: _buildAppBar(),
        body: LayoutBuilder(
          builder: (ctx, constraints) {
            final rs = _RS(constraints.maxWidth);
            return Column(
              children: [
                _ElectionBanner(
                  electionId:   widget.electionId,
                  electionName: widget.electionName,
                  color:        widget.color,
                  rs:           rs,
                ),
                _ProgressHeader(
                  setCount:    _setCount,
                  totalCount:  kBoothTiers.length,
                  sensitivity: widget.sensitivity,
                  color:       widget.color,
                  rs:          rs,
                ),
                Expanded(child: _buildList(rs)),
              ],
            );
          },
        ),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: widget.color,
      foregroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.sensitivity} — बूथ मानक',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800),
            ),
            Text(
              widget.hindi,
              style: const TextStyle(
                  fontSize: 10.5,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      actions: [
        if (_changed)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: FadeTransition(
                opacity: _unsavedFade,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.edit_outlined,
                          size: 10, color: Colors.white),
                      SizedBox(width: 4),
                      Text('अनसेव्ड',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── List ──────────────────────────────────────────────────────────────────

  Widget _buildList(_RS rs) {
    return ListView.separated(
      padding: rs.listPad,
      itemCount: kBoothTiers.length,
      separatorBuilder: (_, __) => SizedBox(height: rs.s(6, 10)),
      itemBuilder: (_, i) {
        final tier  = kBoothTiers[i];
        final bc    = tier['count'] as int;
        final rule  = _byBooth[bc];
        final isSet = _hasAny(rule);
        return _BoothTierCard(
          label:      tier['label'] as String,
          count:      bc,
          isSet:      isSet,
          totalStaff: _totalStaff(rule),
          rule:       rule,
          color:      widget.color,
          isStale:    _isStaleElection(rule),
          rs:         rs,
          onTap:      () => _openRankEditor(bc, tier['label'] as String),
        );
      },
    );
  }

  // ── Bottom save bar ───────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        decoration: BoxDecoration(
          color: _kBg,
          border: Border(
            top: BorderSide(color: _kBorder.withOpacity(0.4)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Quick stats row
            if (_setCount > 0) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _StatPill(
                    label: '$_setCount / ${kBoothTiers.length} तय',
                    icon:  Icons.check_circle_outline,
                    color: _kSuccess,
                  ),
                  const SizedBox(width: 8),
                  _StatPill(
                    label: '${kBoothTiers.length - _setCount} शेष',
                    icon:  Icons.radio_button_unchecked,
                    color: _kSubtle,
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            // Save button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: _canSave
                  ? ElevatedButton.icon(
                      onPressed: _saving ? null : _saveAll,
                      icon: _saving
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white))
                          : const Icon(Icons.save_rounded, size: 18),
                      label: Text(
                        _saving
                            ? 'सेव हो रहा है...'
                            : 'सभी मानक सेव करें',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _saving ? _kSubtle : widget.color,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    )
                  // ── Disabled state when no active election ────────────────
                  : Tooltip(
                      message: 'सक्रिय चुनाव नहीं है — master से कॉन्फ़िगर करवाएं',
                      triggerMode: TooltipTriggerMode.tap,
                      child: ElevatedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.lock_outline, size: 18),
                        label: const Text(
                          'सेव अनुपलब्ध — कोई सक्रिय चुनाव नहीं',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kSubtle.withOpacity(0.15),
                          foregroundColor: _kSubtle,
                          disabledBackgroundColor:
                              _kSubtle.withOpacity(0.12),
                          disabledForegroundColor: _kSubtle,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                                color: _kSubtle.withOpacity(0.3)),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  _ElectionBanner
//  Shows active election name or "no election" warning.
// ══════════════════════════════════════════════════════════════════════════════
class _ElectionBanner extends StatelessWidget {
  final int?    electionId;
  final String? electionName;
  final Color   color;
  final _RS     rs;

  const _ElectionBanner({
    required this.electionId,
    required this.electionName,
    required this.color,
    required this.rs,
  });

  @override
  Widget build(BuildContext context) {
    final hasElection = electionId != null;
    final label       = (electionName?.isNotEmpty == true)
        ? electionName!
        : (hasElection ? 'चुनाव #$electionId' : null);

    if (hasElection && label != null) {
      // ── Active election — gold banner ─────────────────────────────────────
      return Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
            horizontal: rs.s(12, 16), vertical: rs.s(7, 9)),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          border: Border(
            bottom: BorderSide(color: color.withOpacity(0.25)),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.how_to_vote_outlined,
                size: rs.s(13, 15), color: color),
            SizedBox(width: rs.s(5, 7)),
            Text(
              'चुनाव: ',
              style: TextStyle(
                  color: _kSubtle,
                  fontSize: rs.s(10.5, 11.5),
                  fontWeight: FontWeight.w600),
            ),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                    color: color,
                    fontSize: rs.s(11, 12),
                    fontWeight: FontWeight.w800),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Active badge
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: _kSuccess.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: _kSuccess.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: _kSuccess,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'सक्रिय',
                    style: TextStyle(
                        color: _kSuccess,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ── No active election — amber warning ────────────────────────────────
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
          horizontal: rs.s(12, 16), vertical: rs.s(8, 10)),
      color: _kAmberBg,
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 15, color: _kAmber),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'कोई सक्रिय चुनाव नहीं — मानक सेव नहीं होगा।\n'
              'master से चुनाव कॉन्फ़िगर करवाएं।',
              style: TextStyle(
                  color: const Color(0xFF92400E),
                  fontSize: rs.s(10.5, 11.5),
                  fontWeight: FontWeight.w600,
                  height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  _ProgressHeader
//  Shows completion count and instruction strip below the election banner.
// ══════════════════════════════════════════════════════════════════════════════
class _ProgressHeader extends StatelessWidget {
  final int    setCount;
  final int    totalCount;
  final String sensitivity;
  final Color  color;
  final _RS    rs;

  const _ProgressHeader({
    required this.setCount,
    required this.totalCount,
    required this.sensitivity,
    required this.color,
    required this.rs,
  });

  @override
  Widget build(BuildContext context) {
    final pct = totalCount == 0 ? 0.0 : setCount / totalCount;
    return Container(
      color: const Color(0xFFF5E6C8),
      padding: EdgeInsets.symmetric(
          horizontal: rs.s(12, 16), vertical: rs.s(8, 10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: rs.s(12, 14), color: color),
              SizedBox(width: rs.s(4, 6)),
              Expanded(
                child: Text(
                  'बूथ संख्या के अनुसार पुलिस बल मानक सेट करें',
                  style: TextStyle(
                      color: _kDark,
                      fontSize: rs.s(10.5, 11.5),
                      fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '$setCount / $totalCount',
                style: TextStyle(
                    color: color,
                    fontSize: rs.s(12, 13),
                    fontWeight: FontWeight.w900),
              ),
            ],
          ),
          // Progress bar
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value:            pct,
              minHeight:        4,
              backgroundColor:  color.withOpacity(0.12),
              valueColor:       AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  _BoothTierCard — one row per booth count tier (1..15)
// ══════════════════════════════════════════════════════════════════════════════
class _BoothTierCard extends StatelessWidget {
  final String               label;
  final int                  count;
  final bool                 isSet;
  final int                  totalStaff;
  final Map<String, dynamic>? rule;
  final Color                color;
  final bool                 isStale;   // rule was saved in a different election
  final _RS                  rs;
  final VoidCallback         onTap;

  const _BoothTierCard({
    required this.label,
    required this.count,
    required this.isSet,
    required this.totalStaff,
    required this.rule,
    required this.color,
    required this.isStale,
    required this.rs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          decoration: BoxDecoration(
            color: isSet
                ? color.withOpacity(0.055)
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSet
                  ? color.withOpacity(isStale ? 0.2 : 0.4)
                  : _kBorder.withOpacity(0.35),
              width: isSet ? 1.5 : 1,
            ),
            boxShadow: isSet
                ? [
                    BoxShadow(
                      color: color.withOpacity(0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          padding: EdgeInsets.symmetric(
              horizontal: rs.s(10, 14),
              vertical: rs.s(10, 12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopRow(),
              if (isSet) ...[
                SizedBox(height: rs.s(8, 10)),
                _ChipRow(rule: rule!, color: color, rs: rs),
              ],
              // Stale election badge — shown when this rule was saved under a
              // different election than the currently active one.
              if (isStale && isSet) ...[
                const SizedBox(height: 6),
                _StaleBadge(electionId: rule!['electionId']),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopRow() {
    final badgeSize = rs.s(38, 44).toDouble();
    return Row(
      children: [
        // Booth count badge
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: badgeSize,
          height: badgeSize,
          decoration: BoxDecoration(
            color: isSet
                ? (isStale ? _kOldElec : color)
                : _kSubtle.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            count == 15 ? '15+' : '$count',
            style: TextStyle(
              color: isSet ? Colors.white : _kSubtle,
              fontSize: rs.s(count == 15 ? 11 : 14, count == 15 ? 13 : 17),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        SizedBox(width: rs.s(9, 12)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                    color: _kDark,
                    fontSize: rs.s(12.5, 14),
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              if (isSet)
                Text(
                  'कुल: $totalStaff कर्मचारी',
                  style: TextStyle(
                      color: isStale ? _kOldElec : color,
                      fontSize: rs.s(10, 11),
                      fontWeight: FontWeight.w700),
                )
              else
                Text(
                  'मानक सेट नहीं है',
                  style: TextStyle(
                      color: _kSubtle,
                      fontSize: rs.s(10, 11)),
                ),
            ],
          ),
        ),
        // Status icon
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Icon(
            isSet ? Icons.check_circle_rounded : Icons.add_circle_outline,
            key: ValueKey(isSet),
            color: isSet ? _kSuccess : _kSubtle,
            size: rs.s(16, 18),
          ),
        ),
        SizedBox(width: rs.s(2, 4)),
        Icon(Icons.chevron_right, color: _kSubtle, size: rs.s(18, 20)),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  _StaleBadge — shown when a rule row belongs to a past election
// ══════════════════════════════════════════════════════════════════════════════
class _StaleBadge extends StatelessWidget {
  final dynamic electionId;
  const _StaleBadge({required this.electionId});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _kOldElec.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kOldElec.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.history_outlined,
              size: 10, color: _kOldElec),
          const SizedBox(width: 4),
          Text(
            'पुराने चुनाव का मानक (ID: $electionId) — संपादित करें',
            style: const TextStyle(
                color: _kOldElec,
                fontSize: 9.5,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  _ChipRow — compact force summary for a set tier card
// ══════════════════════════════════════════════════════════════════════════════
class _ChipRow extends StatelessWidget {
  final Map<String, dynamic> rule;
  final Color color;
  final _RS   rs;

  const _ChipRow({
    required this.rule,
    required this.color,
    required this.rs,
  });

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

    final chips = <Widget>[
      if (siA + siU   > 0) _splitChip('SI',    siA,  siU,  color),
      if (hcA + hcU   > 0) _splitChip('HC',    hcA,  hcU,  color),
      if (cA  + cU    > 0) _splitChip('Const', cA,   cU,   color),
      if (auxA + auxU > 0) _splitChip('Aux',   auxA, auxU,  _kAux,
          isAux: true),
      if (pac         > 0) _singleChip(
          'PAC',
          pac == pac.toInt() ? '${pac.toInt()}' : '$pac',
          _kPac),
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    // On narrow screens, wrap chips; on wide screens, horizontal scroll
    if (rs.isNarrow) {
      return Wrap(spacing: 5, runSpacing: 5, children: chips);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: chips),
    );
  }

  Widget _splitChip(
    String label, num armed, num unarmed, Color c, {bool isAux = false}) {
    final bg = isAux ? _kAux : c;
    return Container(
      margin: const EdgeInsets.only(right: 5),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.07),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: bg.withOpacity(0.28)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(
          '$label: ',
          style: TextStyle(
              color: bg.withOpacity(0.85),
              fontSize: 10,
              fontWeight: FontWeight.w700),
        ),
        if (armed > 0) ...[
          const Icon(Icons.gavel, size: 9, color: _kArmed),
          Text(
            '$armed',
            style: const TextStyle(
                color: _kArmed, fontSize: 10.5, fontWeight: FontWeight.w900),
          ),
        ],
        if (armed > 0 && unarmed > 0)
          Text(' / ',
              style: TextStyle(color: bg.withOpacity(0.4), fontSize: 10)),
        if (unarmed > 0) ...[
          const Icon(Icons.shield_outlined, size: 9, color: _kUnarmed),
          Text(
            '$unarmed',
            style: const TextStyle(
                color: _kUnarmed, fontSize: 10.5, fontWeight: FontWeight.w900),
          ),
        ],
      ]),
    );
  }

  Widget _singleChip(String label, String value, Color c) {
    return Container(
      margin: const EdgeInsets.only(right: 5),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.09),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withOpacity(0.28)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(
          '$label: ',
          style: TextStyle(
              color: c.withOpacity(0.85),
              fontSize: 10,
              fontWeight: FontWeight.w700),
        ),
        Text(
          value,
          style: TextStyle(
              color: c, fontSize: 10.5, fontWeight: FontWeight.w900),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  _StatPill — quick stat in the bottom bar
// ══════════════════════════════════════════════════════════════════════════════
class _StatPill extends StatelessWidget {
  final String   label;
  final IconData icon;
  final Color    color;

  const _StatPill({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}