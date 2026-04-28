import 'package:flutter/material.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';
import 'manak_rank_editor_page.dart';

const kBg      = Color(0xFFFDF6E3);
const kSurface = Color(0xFFF5E6C8);
const kPrimary = Color(0xFF8B6914);
const kDark    = Color(0xFF4A3000);
const kSubtle  = Color(0xFFAA8844);
const kBorder  = Color(0xFFD4A843);
const kError   = Color(0xFFC0392B);
const kSuccess = Color(0xFF2D6A1E);

// 15 booth-count tiers with Hindi labels
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
//  MANAK BOOTH PAGE — list of 15 booth tiers for a given sensitivity
// ══════════════════════════════════════════════════════════════════════════════
class ManakBoothPage extends StatefulWidget {
  final String sensitivity;   // "A++", "A", "B", "C"
  final Color  color;
  final String hindi;
  final List<Map<String, dynamic>> initialRules;

  const ManakBoothPage({
    super.key,
    required this.sensitivity,
    required this.color,
    required this.hindi,
    required this.initialRules,
  });

  @override
  State<ManakBoothPage> createState() => _ManakBoothPageState();
}

class _ManakBoothPageState extends State<ManakBoothPage> {
  // booth_count → row map (full rule object)
  final Map<int, Map<String, dynamic>> _byBooth = {};
  bool _saving  = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    for (final r in widget.initialRules) {
      final bc = (r['boothCount'] ?? 0) as int;
      if (bc >= 1 && bc <= 15) _byBooth[bc] = Map<String, dynamic>.from(r);
    }
  }

  bool _hasAny(Map<String, dynamic>? r) {
    if (r == null) return false;
    return ((r['siArmedCount']      ?? 0) as num) > 0 ||
           ((r['siUnarmedCount']    ?? 0) as num) > 0 ||
           ((r['hcArmedCount']      ?? 0) as num) > 0 ||
           ((r['hcUnarmedCount']    ?? 0) as num) > 0 ||
           ((r['constArmedCount']   ?? 0) as num) > 0 ||
           ((r['constUnarmedCount'] ?? 0) as num) > 0 ||
           ((r['auxForceCount']     ?? 0) as num) > 0 ||
           ((r['pacCount']          ?? 0) as num) > 0;
  }

  int _totalStaff(Map<String, dynamic>? r) {
    if (r == null) return 0;
    return ((r['siArmedCount']      ?? 0) as num).toInt() +
           ((r['siUnarmedCount']    ?? 0) as num).toInt() +
           ((r['hcArmedCount']      ?? 0) as num).toInt() +
           ((r['hcUnarmedCount']    ?? 0) as num).toInt() +
           ((r['constArmedCount']   ?? 0) as num).toInt() +
           ((r['constUnarmedCount'] ?? 0) as num).toInt() +
           ((r['auxForceCount']     ?? 0) as num).toInt();
  }

  void _openRankEditor(int boothCount, String label) async {
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

    if (updated != null) {
      updated['boothCount'] = boothCount;
      setState(() {
        _byBooth[boothCount] = updated;
        _changed = true;
      });
    }
  }

  Future<void> _saveAll() async {
    setState(() => _saving = true);
    try {
      final token = await AuthService.getToken();
      final rules = _byBooth.values.toList();
      await ApiService.post(
        '/admin/booth-rules',
        {'sensitivity': widget.sensitivity, 'rules': rules},
        token: token,
      );
      if (!mounted) return;
      showSnack(context, '${widget.sensitivity} मानक सेव हो गया ✓');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSnack(context, 'सेव विफल: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('रद्द करें', style: TextStyle(color: kSubtle)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: kError, foregroundColor: Colors.white),
            child: const Text('बाहर निकलें'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          backgroundColor: widget.color,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.sensitivity} मानक',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              Text(widget.hindi,
                  style: const TextStyle(fontSize: 11, color: Colors.white70,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          actions: [
            if (_changed)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('अनसेव्ड',
                        style: TextStyle(color: Colors.white,
                            fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            // Header strip
            Container(
              color: kSurface,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: widget.color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'मतदान केन्द्र पर बूथ संख्या के अनुसार पुलिस बल मानक चुनें',
                      style: TextStyle(color: kDark, fontSize: 11.5,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text('${_byBooth.values.where(_hasAny).length}/15',
                      style: TextStyle(color: widget.color, fontSize: 12,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            // List of tiers
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                itemCount: kBoothTiers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final tier = kBoothTiers[i];
                  final bc   = tier['count'] as int;
                  final r    = _byBooth[bc];
                  final isSet = _hasAny(r);
                  return _BoothTierCard(
                    label: tier['label'] as String,
                    count: bc,
                    isSet: isSet,
                    totalStaff: _totalStaff(r),
                    rule:   r,
                    color:  widget.color,
                    onTap:  () => _openRankEditor(bc, tier['label'] as String),
                  );
                },
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _saveAll,
                icon: _saving
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded, size: 18),
                label: Text(
                  _saving ? 'सेव हो रहा है...' : 'सभी मानक सेव करें',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _saving ? kSubtle : widget.color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  BOOTH TIER CARD — one row per booth count (1..15)
// ══════════════════════════════════════════════════════════════════════════════
class _BoothTierCard extends StatelessWidget {
  final String label;
  final int    count;
  final bool   isSet;
  final int    totalStaff;
  final Map<String, dynamic>? rule;
  final Color  color;
  final VoidCallback onTap;

  const _BoothTierCard({
    required this.label, required this.count, required this.isSet,
    required this.totalStaff, required this.rule, required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: isSet ? color.withOpacity(0.06) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSet ? color.withOpacity(0.4) : kBorder.withOpacity(0.4),
              width: isSet ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Booth count badge
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: isSet ? color : kSubtle.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      count == 15 ? '15+' : '$count',
                      style: TextStyle(
                        color: isSet ? Colors.white : kSubtle,
                        fontSize: count == 15 ? 13 : 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: TextStyle(
                            color: kDark, fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        if (isSet)
                          Text('कुल: $totalStaff कर्मचारी',
                              style: TextStyle(color: color,
                                  fontSize: 11, fontWeight: FontWeight.w700))
                        else
                          const Text('मानक सेट नहीं है',
                              style: TextStyle(color: kSubtle, fontSize: 11)),
                      ],
                    ),
                  ),
                  Icon(
                    isSet ? Icons.check_circle_rounded : Icons.add_circle_outline,
                    color: isSet ? kSuccess : kSubtle, size: 18,
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, color: kSubtle, size: 20),
                ],
              ),
              if (isSet) ...[
                const SizedBox(height: 10),
                _ChipRow(rule: rule!, color: color),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  CHIP ROW — compact summary (shows armed + unarmed split)
// ══════════════════════════════════════════════════════════════════════════════
class _ChipRow extends StatelessWidget {
  final Map<String, dynamic> rule;
  final Color color;
  const _ChipRow({required this.rule, required this.color});

  @override
  Widget build(BuildContext context) {
    final siA  = (rule['siArmedCount']      ?? 0) as num;
    final siU  = (rule['siUnarmedCount']    ?? 0) as num;
    final hcA  = (rule['hcArmedCount']      ?? 0) as num;
    final hcU  = (rule['hcUnarmedCount']    ?? 0) as num;
    final cA   = (rule['constArmedCount']   ?? 0) as num;
    final cU   = (rule['constUnarmedCount'] ?? 0) as num;
    final aux  = (rule['auxForceCount']     ?? 0) as num;
    final pac  = (rule['pacCount']          ?? 0) as num;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        if (siA + siU > 0) _splitChip('SI',    siA, siU),
        if (hcA + hcU > 0) _splitChip('HC',    hcA, hcU),
        if (cA  + cU  > 0) _splitChip('Const', cA,  cU),
        if (aux       > 0) _singleChip('Aux',  '$aux',  const Color(0xFFE65100)),
        if (pac       > 0) _singleChip('PAC',
            pac == pac.toInt() ? '${pac.toInt()}' : '$pac',
            const Color(0xFF00695C)),
      ]),
    );
  }

  // Chip showing armed/unarmed split: "SI: 2🗡 / 1🛡"
  Widget _splitChip(String label, num armed, num unarmed) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label: ',
            style: TextStyle(color: color.withOpacity(0.85),
                fontSize: 10.5, fontWeight: FontWeight.w700)),
        if (armed > 0) ...[
          const Icon(Icons.gavel, size: 9, color: Color(0xFF6A1B9A)),
          Text('$armed',
              style: const TextStyle(color: Color(0xFF6A1B9A),
                  fontSize: 11, fontWeight: FontWeight.w900)),
        ],
        if (armed > 0 && unarmed > 0)
          Text(' / ',
              style: TextStyle(color: color.withOpacity(0.5), fontSize: 11)),
        if (unarmed > 0) ...[
          const Icon(Icons.shield_outlined, size: 9, color: Color(0xFF1A5276)),
          Text('$unarmed',
              style: const TextStyle(color: Color(0xFF1A5276),
                  fontSize: 11, fontWeight: FontWeight.w900)),
        ],
      ]),
    );
  }

  Widget _singleChip(String label, String value, Color c) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label: ',
            style: TextStyle(color: c.withOpacity(0.85),
                fontSize: 10.5, fontWeight: FontWeight.w700)),
        Text(value,
            style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w900)),
      ]),
    );
  }
}