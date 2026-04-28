import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const kBg      = Color(0xFFFDF6E3);
const kSurface = Color(0xFFF5E6C8);
const kPrimary = Color(0xFF8B6914);
const kDark    = Color(0xFF4A3000);
const kSubtle  = Color(0xFFAA8844);
const kBorder  = Color(0xFFD4A843);
const kError   = Color(0xFFC0392B);
const kSuccess = Color(0xFF2D6A1E);
const kArmed   = Color(0xFF6A1B9A);
const kUnarmed = Color(0xFF1A5276);
const kPacColor = Color(0xFF00695C);

// 5 fixed scale ranks
class _RankDef {
  final String key;          // 'si', 'hc', 'const', 'aux', 'pac'
  final String label;
  final String hindi;
  final IconData icon;
  final bool hasArmedSplit;  // SI/HC/Const → true (split into armed+unarmed)
  final bool isDecimal;      // PAC → true (allows 0.5)
  const _RankDef(this.key, this.label, this.hindi, this.icon,
      {this.hasArmedSplit = true, this.isDecimal = false});
}

const List<_RankDef> _kRanks = [
  _RankDef('si',    'SI',        'उप निरीक्षक',     Icons.shield_outlined),
  _RankDef('hc',    'HC',        'मुख्य आरक्षी',     Icons.military_tech_outlined),
  _RankDef('const', 'Constable', 'आरक्षी',           Icons.person_outline),
  _RankDef('aux',   'Aux Force', 'सहायक बल',         Icons.groups_outlined,
           hasArmedSplit: false),
  _RankDef('pac',   'PAC',       'पीएसी (सेक्शन)',  Icons.security_outlined,
           hasArmedSplit: false, isDecimal: true),
];

// ══════════════════════════════════════════════════════════════════════════════
//  RANK EDITOR PAGE  —  per-rank armed + unarmed counts
// ══════════════════════════════════════════════════════════════════════════════
class ManakRankEditorPage extends StatefulWidget {
  final String title;
  final String subtitle;
  final Color  color;
  final Map<String, dynamic> initial;
  final bool   showSankhya;       // for district-rules

  const ManakRankEditorPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.initial,
    this.showSankhya = false,
  });

  @override
  State<ManakRankEditorPage> createState() => _ManakRankEditorPageState();
}

class _ManakRankEditorPageState extends State<ManakRankEditorPage> {
  // Controllers — keyed by ('si_armed', 'si_unarmed', 'hc_armed', ...).
  // Aux & PAC are single-keyed: 'aux', 'pac'.
  late final Map<String, TextEditingController> _ctrls;
  late final TextEditingController _sankhyaCtrl;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    final ini = widget.initial;
    _ctrls = {
      'si_armed':      TextEditingController(text: _initVal(ini['siArmedCount'])),
      'si_unarmed':    TextEditingController(text: _initVal(ini['siUnarmedCount'])),
      'hc_armed':      TextEditingController(text: _initVal(ini['hcArmedCount'])),
      'hc_unarmed':    TextEditingController(text: _initVal(ini['hcUnarmedCount'])),
      'const_armed':   TextEditingController(text: _initVal(ini['constArmedCount'])),
      'const_unarmed': TextEditingController(text: _initVal(ini['constUnarmedCount'])),
      'aux':           TextEditingController(text: _initVal(ini['auxForceCount'])),
      'pac':           TextEditingController(text: _initVal(ini['pacCount'], decimal: true)),
    };
    _sankhyaCtrl = TextEditingController(text: _initVal(ini['sankhya']));

    for (final c in _ctrls.values) {
      c.addListener(() => setState(() => _changed = true));
    }
    _sankhyaCtrl.addListener(() => setState(() => _changed = true));
  }

  String _initVal(dynamic v, {bool decimal = false}) {
    if (v == null) return '';
    final n = v is num ? v : (num.tryParse(v.toString()) ?? 0);
    if (n == 0) return '';
    if (decimal) {
      if (n == n.toInt()) return '${n.toInt()}';
      return '$n';
    }
    return '${n.toInt()}';
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) c.dispose();
    _sankhyaCtrl.dispose();
    super.dispose();
  }

  num _val(String key) {
    final txt = _ctrls[key]?.text.trim() ?? '';
    if (txt.isEmpty) return 0;
    return num.tryParse(txt) ?? 0;
  }

  int get _armedTotal =>
      _val('si_armed').toInt() + _val('hc_armed').toInt() + _val('const_armed').toInt();
  int get _unarmedTotal =>
      _val('si_unarmed').toInt() + _val('hc_unarmed').toInt() + _val('const_unarmed').toInt();
  int get _auxTotal => _val('aux').toInt();
  int get _totalStaff => _armedTotal + _unarmedTotal + _auxTotal;

  void _change(String key, num delta, {bool decimal = false}) {
    final cur  = _val(key);
    final next = (cur + delta).clamp(0, 999);
    setState(() {
      if (next == 0) {
        _ctrls[key]!.text = '';
      } else if (decimal) {
        _ctrls[key]!.text =
            (next == next.toInt() ? '${next.toInt()}' : '$next');
      } else {
        _ctrls[key]!.text = '${next.toInt()}';
      }
      _changed = true;
    });
  }

  void _save() {
    final out = <String, dynamic>{
      'siArmedCount':      _val('si_armed').toInt(),
      'siUnarmedCount':    _val('si_unarmed').toInt(),
      'hcArmedCount':      _val('hc_armed').toInt(),
      'hcUnarmedCount':    _val('hc_unarmed').toInt(),
      'constArmedCount':   _val('const_armed').toInt(),
      'constUnarmedCount': _val('const_unarmed').toInt(),
      'auxForceCount':     _val('aux').toInt(),
      'pacCount':          _val('pac'),
    };
    if (widget.showSankhya) {
      final v = num.tryParse(_sankhyaCtrl.text.trim());
      out['sankhya'] = (v ?? 0).toInt();
    }
    Navigator.pop(context, out);
  }

  Future<bool> _onWillPop() async {
    if (!_changed) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBg,
        title: const Text('बदलाव सहेजे नहीं गए',
            style: TextStyle(color: kDark, fontWeight: FontWeight.w800)),
        content: const Text(
            'आपने कुछ बदलाव किए हैं। क्या आप बिना सेव के बाहर निकलना चाहते हैं?',
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
              Text(widget.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              Text(widget.subtitle,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ],
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
          children: [
            _summaryHeader(),
            const SizedBox(height: 14),
            if (widget.showSankhya) _sankhyaField(),
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'मानक के अनुसार व्यवस्थित पुलिस बल का विवरण',
                style: TextStyle(color: kDark, fontSize: 13,
                    fontWeight: FontWeight.w800),
              ),
            ),
            ..._kRanks.map(_buildRankCard),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check_rounded, size: 20),
                label: const Text('लागू करें',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.color,
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

  // ── Summary header ─────────────────────────────────────────────────────
  Widget _summaryHeader() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.groups, color: widget.color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('कुल कर्मचारी: $_totalStaff',
                    style: TextStyle(color: widget.color,
                        fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10, runSpacing: 4,
                  children: [
                    _miniStat(Icons.gavel, 'सशस्त्र', _armedTotal, kArmed),
                    _miniStat(Icons.shield, 'निःशस्त्र', _unarmedTotal, kUnarmed),
                    if (_auxTotal > 0)
                      _miniStat(Icons.groups_outlined, 'सहायक',
                          _auxTotal, const Color(0xFFE65100)),
                    if (_val('pac') > 0)
                      _miniStat(Icons.security, 'PAC', _val('pac'), kPacColor),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Sankhya field ──────────────────────────────────────────────────────
  Widget _sankhyaField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('संख्या',
              style: TextStyle(color: kDark, fontSize: 13,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kBorder.withOpacity(0.5)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.format_list_numbered, color: kPrimary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _sankhyaCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    style: const TextStyle(color: kDark, fontSize: 16,
                        fontWeight: FontWeight.w800),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: '0',
                      hintStyle: TextStyle(color: kSubtle),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(IconData icon, String label, num value, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: color),
      const SizedBox(width: 3),
      Text('$label: ',
          style: TextStyle(color: color.withOpacity(0.7),
              fontSize: 10.5, fontWeight: FontWeight.w600)),
      Text(value == value.toInt() ? '${value.toInt()}' : '$value',
          style: TextStyle(color: color, fontSize: 11.5,
              fontWeight: FontWeight.w900)),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════
  //  Per-rank card — handles both split (armed+unarmed) and single types
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildRankCard(_RankDef rank) {
    if (rank.hasArmedSplit) {
      return _splitRankCard(rank);
    } else {
      return _singleRankCard(rank);
    }
  }

  // SI / HC / Constable — two count fields side-by-side
  Widget _splitRankCard(_RankDef rank) {
    final armedKey   = '${rank.key}_armed';
    final unarmedKey = '${rank.key}_unarmed';
    final armed      = _val(armedKey).toInt();
    final unarmed    = _val(unarmedKey).toInt();
    final total      = armed + unarmed;
    final active     = total > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: active ? widget.color.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: active
                ? widget.color.withOpacity(0.4)
                : kBorder.withOpacity(0.4),
            width: active ? 1.4 : 1),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(rank.icon, color: widget.color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rank.label,
                        style: const TextStyle(color: kDark,
                            fontSize: 14, fontWeight: FontWeight.w800)),
                    Text(rank.hindi,
                        style: const TextStyle(color: kSubtle, fontSize: 11)),
                  ],
                ),
              ),
              if (active)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('कुल: $total',
                      style: TextStyle(color: widget.color,
                          fontSize: 11, fontWeight: FontWeight.w800)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Two columns side by side
          Row(
            children: [
              Expanded(
                child: _countField(
                  field:    armedKey,
                  label:    'सशस्त्र',
                  sublabel: 'Armed',
                  icon:     Icons.gavel,
                  color:    kArmed,
                  decimal:  false,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _countField(
                  field:    unarmedKey,
                  label:    'निःशस्त्र',
                  sublabel: 'Unarmed',
                  icon:     Icons.shield_outlined,
                  color:    kUnarmed,
                  decimal:  false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Aux Force / PAC — single count field, full width
  Widget _singleRankCard(_RankDef rank) {
    final value  = _val(rank.key);
    final active = value > 0;
    final color  = rank.key == 'pac' ? kPacColor : const Color(0xFFE65100);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: active ? color.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: active ? color.withOpacity(0.4) : kBorder.withOpacity(0.4),
            width: active ? 1.4 : 1),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(rank.icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rank.label,
                    style: const TextStyle(color: kDark,
                        fontSize: 14, fontWeight: FontWeight.w800)),
                Text(rank.hindi,
                    style: const TextStyle(color: kSubtle, fontSize: 11)),
              ],
            ),
          ),
          _stepBtn(Icons.remove, value > 0,
              () => _change(rank.key, rank.isDecimal ? -0.5 : -1,
                  decimal: rank.isDecimal),
              color: kError),
          const SizedBox(width: 6),
          SizedBox(
            width: 56, height: 38,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: active ? color : kBorder.withOpacity(0.6),
                    width: active ? 1.4 : 1),
              ),
              child: TextField(
                controller: _ctrls[rank.key]!,
                keyboardType: rank.isDecimal
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: rank.isDecimal
                    ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
                    : [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                style: TextStyle(
                    color: active ? color : kDark,
                    fontSize: 17, fontWeight: FontWeight.w900),
                decoration: const InputDecoration(
                  border: InputBorder.none, isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 7),
                  hintText: '0',
                  hintStyle: TextStyle(color: kSubtle, fontWeight: FontWeight.w400),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _stepBtn(Icons.add, true,
              () => _change(rank.key, rank.isDecimal ? 0.5 : 1,
                  decimal: rank.isDecimal),
              color: color),
        ],
      ),
    );
  }

  // ── Reusable count field with stepper ─────────────────────────────────
  Widget _countField({
    required String field,
    required String label,
    required String sublabel,
    required IconData icon,
    required Color color,
    required bool decimal,
  }) {
    final ctrl   = _ctrls[field]!;
    final value  = _val(field);
    final active = value > 0;

    return Container(
      decoration: BoxDecoration(
        color: active ? color.withOpacity(0.06) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: active ? color.withOpacity(0.45) : kBorder.withOpacity(0.4),
            width: active ? 1.3 : 1),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800)),
              ),
              Text(sublabel,
                  style: TextStyle(
                      color: color.withOpacity(0.6),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          // Stepper row
          Row(
            children: [
              _stepBtn(Icons.remove, value > 0,
                  () => _change(field, decimal ? -0.5 : -1, decimal: decimal),
                  color: kError, size: 32),
              const SizedBox(width: 4),
              Expanded(
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                        color: active ? color : kBorder.withOpacity(0.5),
                        width: active ? 1.3 : 1),
                  ),
                  child: TextField(
                    controller: ctrl,
                    keyboardType: decimal
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.number,
                    textAlign: TextAlign.center,
                    inputFormatters: decimal
                        ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
                        : [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(3),
                          ],
                    style: TextStyle(
                        color: active ? color : kDark,
                        fontSize: 16, fontWeight: FontWeight.w900),
                    decoration: const InputDecoration(
                      border: InputBorder.none, isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 7),
                      hintText: '0',
                      hintStyle: TextStyle(color: kSubtle, fontWeight: FontWeight.w400),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _stepBtn(Icons.add, true,
                  () => _change(field, decimal ? 0.5 : 1, decimal: decimal),
                  color: color, size: 32),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, bool enabled, VoidCallback onTap,
      {required Color color, double size = 38}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: size, height: size,
        decoration: BoxDecoration(
          color: enabled
              ? color.withOpacity(0.12)
              : Colors.grey.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: enabled
                  ? color.withOpacity(0.4)
                  : Colors.grey.withOpacity(0.2),
              width: 1.2),
        ),
        child: Icon(icon, size: size * 0.45,
            color: enabled ? color : Colors.grey.withOpacity(0.4)),
      ),
    );
  }
}