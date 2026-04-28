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
const kDistrictColor = Color(0xFF6C3483);

// 14 duty types — matches backend DEFAULT_DISTRICT_DUTIES order/keys
const List<Map<String, dynamic>> kDistrictDuties = [
  {'type': 'cluster_mobile',        'label': 'क्लस्टर मोबाईल',                  'icon': Icons.directions_car_outlined},
  {'type': 'thana_mobile',          'label': 'थाना मोबाईल',                     'icon': Icons.local_police_outlined},
  {'type': 'thana_reserve',         'label': 'थाना रिजर्व',                     'icon': Icons.savings_outlined},
  {'type': 'thana_extra_mobile',    'label': 'थाना अतिरिक्त मोबाईल',           'icon': Icons.add_road_outlined},
  {'type': 'sector_pol_mag_mobile', 'label': 'सैक्टर पुलिस / मजिस्ट्रेट मोबाईल', 'icon': Icons.gavel_outlined},
  {'type': 'zonal_pol_mag_mobile',  'label': 'जोनल पुलिस / मजिस्ट्रेट मोबाईल',  'icon': Icons.account_tree_outlined},
  {'type': 'sdm_co_mobile',         'label': 'एसडीएम / सीओ मोबाईल',           'icon': Icons.admin_panel_settings_outlined},
  {'type': 'chowki_mobile',         'label': 'चौकी मोबाईल',                    'icon': Icons.home_work_outlined},
  {'type': 'barrier_picket',        'label': 'बैरियर / पिकैट',                'icon': Icons.block_outlined},
  {'type': 'evm_security',          'label': 'ईवीएम सुरक्षा',                'icon': Icons.how_to_vote_outlined},
  {'type': 'adm_sp_mobile',         'label': 'एडीएम / एसपी मोबाईल',          'icon': Icons.shield_outlined},
  {'type': 'dm_sp_mobile',          'label': 'डीएम / एसपी मोबाईल',            'icon': Icons.workspace_premium_outlined},
  {'type': 'observer_security',     'label': 'पर्यवेक्षक सुरक्षा',             'icon': Icons.visibility_outlined},
  {'type': 'hq_reserve',            'label': 'मुख्यालय रिजर्व',                'icon': Icons.business_outlined},
];

// ══════════════════════════════════════════════════════════════════════════════
//  MANAK DISTRICT PAGE
// ══════════════════════════════════════════════════════════════════════════════
class ManakDistrictPage extends StatefulWidget {
  final List<Map<String, dynamic>> initialRules;
  const ManakDistrictPage({super.key, required this.initialRules});

  @override
  State<ManakDistrictPage> createState() => _ManakDistrictPageState();
}

class _ManakDistrictPageState extends State<ManakDistrictPage> {
  // duty_type → row map
  final Map<String, Map<String, dynamic>> _byDuty = {};
  bool _saving  = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    for (final r in widget.initialRules) {
      final t = (r['dutyType'] ?? '').toString();
      if (t.isNotEmpty) _byDuty[t] = Map<String, dynamic>.from(r);
    }
  }

  bool _hasAny(Map<String, dynamic>? r) {
    if (r == null) return false;
    return ((r['sankhya']            ?? 0) as num) > 0 ||
           ((r['siArmedCount']       ?? 0) as num) > 0 ||
           ((r['siUnarmedCount']     ?? 0) as num) > 0 ||
           ((r['hcArmedCount']       ?? 0) as num) > 0 ||
           ((r['hcUnarmedCount']     ?? 0) as num) > 0 ||
           ((r['constArmedCount']    ?? 0) as num) > 0 ||
           ((r['constUnarmedCount']  ?? 0) as num) > 0 ||
           ((r['auxForceCount']      ?? 0) as num) > 0 ||
           ((r['pacCount']           ?? 0) as num) > 0;
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

  void _openRankEditor(Map<String, dynamic> duty, int sortOrder) async {
    final dutyType = duty['type'] as String;
    final label    = duty['label'] as String;
    final existing = _byDuty[dutyType] ?? {
      'dutyType':    dutyType,
      'dutyLabelHi': label,
      'sortOrder':   sortOrder,
    };

    final updated = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => ManakRankEditorPage(
          title:       label,
          subtitle:    'जनपदीय कानून व्यवस्था',
          color:       kDistrictColor,
          initial:     existing,
          showSankhya: true,
        ),
      ),
    );

    if (updated != null) {
      updated['dutyType']    = dutyType;
      updated['dutyLabelHi'] = label;
      updated['sortOrder']   = sortOrder;
      setState(() {
        _byDuty[dutyType] = updated;
        _changed = true;
      });
    }
  }

  Future<void> _saveAll() async {
    setState(() => _saving = true);
    try {
      final token = await AuthService.getToken();
      // Send all 14 in canonical order (only those that exist in _byDuty)
      final List<Map<String, dynamic>> rules = [];
      for (int i = 0; i < kDistrictDuties.length; i++) {
        final d = kDistrictDuties[i];
        final t = d['type'] as String;
        if (_byDuty.containsKey(t)) {
          final r = Map<String, dynamic>.from(_byDuty[t]!);
          r['dutyType']    = t;
          r['dutyLabelHi'] = d['label'];
          r['sortOrder']   = (i + 1) * 10;
          rules.add(r);
        }
      }
      await ApiService.post(
        '/admin/district-rules',
        {'rules': rules},
        token: token,
      );
      if (!mounted) return;
      showSnack(context, 'जनपदीय मानक सेव हो गया ✓');
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
    final filledCount = _byDuty.values.where(_hasAny).length;
    final totalAll = _byDuty.values.where(_hasAny)
        .fold<int>(0, (s, r) => s + _totalStaff(r));

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          backgroundColor: kDistrictColor,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('जनपदीय कानून व्यवस्था',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              Text('मानक — कानून व्यवस्था ड्यूटी',
                  style: TextStyle(fontSize: 11, color: Colors.white70)),
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
            // Summary header
            Container(
              color: kSurface,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, size: 14, color: kDistrictColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'ड्यूटी प्रकार पर टैप करके पुलिस बल सेट करें',
                      style: const TextStyle(color: kDark, fontSize: 11.5,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text('$totalAll कर्मचारी',
                      style: const TextStyle(color: kDistrictColor, fontSize: 11.5,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(width: 6),
                  Text('$filledCount/${kDistrictDuties.length}',
                      style: const TextStyle(color: kDistrictColor, fontSize: 12,
                          fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                itemCount: kDistrictDuties.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final duty = kDistrictDuties[i];
                  final type = duty['type'] as String;
                  final r    = _byDuty[type];
                  final isSet = _hasAny(r);
                  return _DutyCard(
                    label:      duty['label'] as String,
                    icon:       duty['icon']  as IconData,
                    isSet:      isSet,
                    sankhya:    isSet ? ((r!['sankhya'] ?? 0) as num).toInt() : 0,
                    totalStaff: _totalStaff(r),
                    rule:       r,
                    onTap:      () => _openRankEditor(duty, (i + 1) * 10),
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
                  backgroundColor: _saving ? kSubtle : kDistrictColor,
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
//  DUTY CARD — one row per duty type
// ══════════════════════════════════════════════════════════════════════════════
class _DutyCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSet;
  final int sankhya;
  final int totalStaff;
  final Map<String, dynamic>? rule;
  final VoidCallback onTap;

  const _DutyCard({
    required this.label, required this.icon, required this.isSet,
    required this.sankhya, required this.totalStaff,
    required this.rule, required this.onTap,
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
            color: isSet ? kDistrictColor.withOpacity(0.06) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSet
                  ? kDistrictColor.withOpacity(0.4)
                  : kBorder.withOpacity(0.4),
              width: isSet ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: isSet
                          ? kDistrictColor
                          : kSubtle.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon,
                        color: isSet ? Colors.white : kSubtle, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: const TextStyle(
                            color: kDark, fontSize: 13.5,
                            fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        if (isSet)
                          Row(children: [
                            Text('संख्या: $sankhya',
                                style: const TextStyle(
                                    color: kDistrictColor, fontSize: 11,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(width: 8),
                            Text('• कुल: $totalStaff',
                                style: const TextStyle(
                                    color: kSubtle, fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ])
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
                _ChipRow(rule: rule!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  CHIP ROW — compact preview (armed/unarmed split)
// ══════════════════════════════════════════════════════════════════════════════
class _ChipRow extends StatelessWidget {
  final Map<String, dynamic> rule;
  const _ChipRow({required this.rule});

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

  Widget _splitChip(String label, num armed, num unarmed) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: kDistrictColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: kDistrictColor.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label: ',
            style: TextStyle(color: kDistrictColor.withOpacity(0.85),
                fontSize: 10.5, fontWeight: FontWeight.w700)),
        if (armed > 0) ...[
          const Icon(Icons.gavel, size: 9, color: Color(0xFF6A1B9A)),
          Text('$armed',
              style: const TextStyle(color: Color(0xFF6A1B9A),
                  fontSize: 11, fontWeight: FontWeight.w900)),
        ],
        if (armed > 0 && unarmed > 0)
          Text(' / ',
              style: TextStyle(color: kDistrictColor.withOpacity(0.5),
                  fontSize: 11)),
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