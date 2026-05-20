import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../admin/pages/duty_card_page.dart';
import 'duty_history_page.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  PALETTE
// ══════════════════════════════════════════════════════════════════════════════
const kBg        = Color(0xFFFDF6E3);
const kSurface   = Color(0xFFF5E6C8);
const kPrimary   = Color(0xFF8B6914);
const kAccent    = Color(0xFFB8860B);
const kDark      = Color(0xFF4A3000);
const kSubtle    = Color(0xFFAA8844);
const kBorder    = Color(0xFFD4A843);
const kError     = Color(0xFFC0392B);
const kSuccess   = Color(0xFF2D6A1E);
const kSuccessBg = Color(0xFFE6F2DF);
const kInfo      = Color(0xFF1A5276);
const kArmed     = Color(0xFF1B5E20);
const kUnarmed   = Color(0xFF37474F);
const kDistrict  = Color(0xFF4A148C);
const kSector    = Color(0xFF1A5276);
const kZone      = Color(0xFF1565C0);
const kKshetra   = Color(0xFF4A148C);
const kPastElec  = Color(0xFFE65100);

// ══════════════════════════════════════════════════════════════════════════════
//  RESPONSIVE HELPER
// ══════════════════════════════════════════════════════════════════════════════
class _RS {
  final double w;
  const _RS(this.w);
  bool get compact => w < 360;
  bool get wide    => w >= 600;
  double s(double sm, double lg) =>
      sm + (lg - sm) * ((w - 320) / 160).clamp(0.0, 1.0);
  EdgeInsets get hPad => EdgeInsets.symmetric(horizontal: compact ? 12.0 : 16.0);
  double get cardRadius => compact ? 12.0 : 14.0;
}

_RS _rs(BuildContext c) => _RS(MediaQuery.of(c).size.width);

// ══════════════════════════════════════════════════════════════════════════════
//  HELPERS
// ══════════════════════════════════════════════════════════════════════════════
const _rankMap = {
  'constable':       'आरक्षी',
  'head constable':  'मुख्य आरक्षी',
  'si':              'उप निरीक्षक',
  'sub inspector':   'उप निरीक्षक',
  'inspector':       'निरीक्षक',
  'asi':             'सहायक उप निरीक्षक',
  'dsp':             'उपाधीक्षक',
  'asp':             'सहा0 पुलिस अधीक्षक',
  'sp':              'पुलिस अधीक्षक',
  'home guard':      'होम गार्ड',
};

String rh(dynamic val) =>
    _rankMap[(val ?? '').toString().toLowerCase()] ?? val?.toString() ?? '—';

String v(dynamic x) =>
    (x == null || x.toString().trim().isEmpty) ? '—' : x.toString();

const _centerTypeMap = {
  'a++': 'अत्यति संवेदनशील',
  'a':   'अति संवेदनशील',
  'b':   'संवेदनशील',
  'c':   'सामान्य',
};
String ct(dynamic x) =>
    _centerTypeMap[(x ?? '').toString().toLowerCase()] ?? x?.toString() ?? '—';

Color _typeColor(String? t) {
  switch ((t ?? '').toUpperCase()) {
    case 'A++': return const Color(0xFF6C3483);
    case 'A':   return kError;
    case 'B':   return kAccent;
    default:    return kInfo;
  }
}

const _districtDutyLabels = {
  'cluster_mobile':        'क्लस्टर मोबाईल',
  'thana_mobile':          'थाना मोबाईल',
  'thana_reserve':         'थाना रिजर्व',
  'thana_extra_mobile':    'थाना अतिरिक्त मोबाईल',
  'sector_pol_mag_mobile': 'सैक्टर पुलिस/मजिस्ट्रेट मोबाईल',
  'zonal_pol_mag_mobile':  'जोनल पुलिस/मजिस्ट्रेट मोबाईल',
  'sdm_co_mobile':         'एसडीएम/सीओ मोबाईल',
  'chowki_mobile':         'चौकी मोबाईल',
  'barrier_picket':        'बैरियर/पिकैट',
  'evm_security':          'ईवीएम सुरक्षा',
  'adm_sp_mobile':         'एडीएम/एसपी मोबाईल',
  'dm_sp_mobile':          'डीएम/एसपी मोबाईल',
  'observer_security':     'पर्यवेक्षक सुरक्षा',
  'hq_reserve':            'मुख्यालय रिजर्व',
};
String dutyLabel(String? k) =>
    _districtDutyLabels[k] ?? k?.replaceAll('_', ' ') ?? '—';

Color _rankColor(String rank) {
  switch (rank.toUpperCase()) {
    case 'SP':             return const Color(0xFF6A1B9A);
    case 'ASP':            return const Color(0xFF1565C0);
    case 'DSP':            return const Color(0xFF1A5276);
    case 'INSPECTOR':      return const Color(0xFF2E7D32);
    case 'SI':             return const Color(0xFF558B2F);
    case 'ASI':            return const Color(0xFF8B6914);
    case 'HEAD CONSTABLE': return const Color(0xFFB8860B);
    case 'CONSTABLE':      return const Color(0xFF6D4C41);
    default:               return kPrimary;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  MANAK BOOTH TIERS (matches admin exactly)
// ══════════════════════════════════════════════════════════════════════════════
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

const List<Map<String, dynamic>> kSensitivities = [
  {'key': 'A++', 'hi': 'अति-अति संवेदनशील', 'color': Color(0xFF6C3483)},
  {'key': 'A',   'hi': 'अति संवेदनशील',      'color': Color(0xFFC0392B)},
  {'key': 'B',   'hi': 'संवेदनशील',           'color': Color(0xFFE67E22)},
  {'key': 'C',   'hi': 'सामान्य',             'color': Color(0xFF1A5276)},
];

// ══════════════════════════════════════════════════════════════════════════════
//  ELECTION CONFIG MODEL
// ══════════════════════════════════════════════════════════════════════════════
class _ElectionConfig {
  final String district;
  final String state;
  final String electionType;
  final String electionName;
  final String phase;
  final String electionYear;
  final String electionDate;
  final String pratahSamay;
  final String sayaSamay;

  const _ElectionConfig({
    this.district     = '',
    this.state        = '',
    this.electionType = '',
    this.electionName = '',
    this.phase        = '',
    this.electionYear = '',
    this.electionDate = '',
    this.pratahSamay  = '',
    this.sayaSamay    = '',
  });

  bool get isEmpty => electionName.isEmpty && district.isEmpty;

  factory _ElectionConfig.fromMap(Map<dynamic, dynamic> m) {
    String rawDate =
        (m['electionDate'] ?? m['election_date'] ?? '').toString().trim();
    if (rawDate.contains('-') && rawDate.length >= 10) {
      final parts = rawDate.substring(0, 10).split('-');
      if (parts.length == 3) rawDate = '${parts[2]}.${parts[1]}.${parts[0]}';
    }

    String year = (m['electionYear'] ?? m['election_year'] ?? '').toString().trim();
    if (year.isEmpty && rawDate.length >= 4) {
      year = rawDate.substring(rawDate.length - 4);
    }

    String pratah = (m['pratahSamay'] ?? m['pratah_samay'] ?? '').toString().trim();
    String saya   = (m['sayaSamay']   ?? m['saya_samay']   ?? '').toString().trim();

    return _ElectionConfig(
      district:     (m['district']                             ?? '').toString().trim(),
      state:        (m['state']                                ?? '').toString().trim(),
      electionType: (m['electionType'] ?? m['election_type']   ?? '').toString().trim(),
      electionName: (m['electionName'] ?? m['election_name']   ?? '').toString().trim(),
      phase:        (m['phase']                                ?? '').toString().trim(),
      electionYear: year,
      electionDate: rawDate,
      pratahSamay:  pratah,
      sayaSamay:    saya,
    );
  }

  Map<String, String> toConfigMap() => {
    'district':     district,
    'state':        state,
    'electionType': electionType,
    'electionName': electionName,
    'phase':        phase,
    'electionYear': electionYear,
    'electionDate': electionDate,
    'pratahSamay':  pratahSamay,
    'sayaSamay':    sayaSamay,
  };

  String get displayDate {
    if (electionDate.isEmpty) return '—';
    if (electionDate.contains('.')) {
      final p = electionDate.split('.');
      if (p.length == 3) {
        const months = ['', 'जनवरी', 'फरवरी', 'मार्च', 'अप्रैल', 'मई', 'जून',
            'जुलाई', 'अगस्त', 'सितम्बर', 'अक्टूबर', 'नवम्बर', 'दिसम्बर'];
        final m = int.tryParse(p[1]) ?? 0;
        if (m >= 1 && m <= 12) return '${p[0]} ${months[m]} ${p[2]}';
      }
    }
    return electionDate;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  MANAK RULE MODEL — columnar (matches admin exactly)
// ══════════════════════════════════════════════════════════════════════════════
class _ManakRule {
  final String sensitivity;
  final int    boothCount;
  final int    siArmed;
  final int    siUnarmed;
  final int    hcArmed;
  final int    hcUnarmed;
  final int    constArmed;
  final int    constUnarmed;
  final int    auxArmed;
  final int    auxUnarmed;
  final double pac;

  const _ManakRule({
    required this.sensitivity,
    required this.boothCount,
    this.siArmed      = 0,
    this.siUnarmed    = 0,
    this.hcArmed      = 0,
    this.hcUnarmed    = 0,
    this.constArmed   = 0,
    this.constUnarmed = 0,
    this.auxArmed     = 0,
    this.auxUnarmed   = 0,
    this.pac          = 0,
  });

  int get totalSI      => siArmed + siUnarmed;
  int get totalHC      => hcArmed + hcUnarmed;
  int get totalConst   => constArmed + constUnarmed;
  int get totalAux     => auxArmed + auxUnarmed;
  int get totalArmed   => siArmed + hcArmed + constArmed + auxArmed;
  int get totalUnarmed => siUnarmed + hcUnarmed + constUnarmed + auxUnarmed;
  int get total        => totalArmed + totalUnarmed;

  factory _ManakRule.fromMap(Map m) {
    int _n(String k, [String? alt]) =>
        ((m[k] ?? (alt != null ? m[alt] : null) ?? 0) as num).toInt();
    double _d(String k, [String? alt]) =>
        ((m[k] ?? (alt != null ? m[alt] : null) ?? 0) as num).toDouble();

    return _ManakRule(
      sensitivity:  (m['sensitivity'] ?? 'C').toString(),
      boothCount:   _n('boothCount', 'booth_count'),
      siArmed:      _n('siArmedCount',    'si_armed_count'),
      siUnarmed:    _n('siUnarmedCount',  'si_unarmed_count'),
      hcArmed:      _n('hcArmedCount',    'hc_armed_count'),
      hcUnarmed:    _n('hcUnarmedCount',  'hc_unarmed_count'),
      constArmed:   _n('constArmedCount', 'const_armed_count'),
      constUnarmed: _n('constUnarmedCount','const_unarmed_count'),
      auxArmed:     _n('auxArmedCount',   'aux_armed_count'),
      auxUnarmed:   _n('auxUnarmedCount', 'aux_unarmed_count'),
      pac:          _d('pacCount',        'pac_count'),
    );
  }

  bool get hasAny =>
      siArmed > 0 || siUnarmed > 0 || hcArmed > 0 || hcUnarmed > 0 ||
      constArmed > 0 || constUnarmed > 0 || auxArmed > 0 || auxUnarmed > 0 ||
      pac > 0;
}

// ══════════════════════════════════════════════════════════════════════════════
//  MANAK PARSER
// ══════════════════════════════════════════════════════════════════════════════
class _ManakParser {
  static List<_ManakRule> parse(List rules) {
    if (rules.isEmpty) return [];

    final first = rules.first as Map;
    final isColumnar = first.containsKey('siArmedCount') ||
        first.containsKey('si_armed_count') ||
        first.containsKey('boothCount') ||
        first.containsKey('booth_count');

    if (isColumnar) {
      return rules
          .where((r) => r is Map)
          .map((r) => _ManakRule.fromMap(r as Map))
          .where((r) => r.hasAny)
          .toList();
    }

    // Per-rank shape: aggregate into columnar
    final Map<String, Map<String, dynamic>> agg = {};
    for (final row in rules) {
      if (row is! Map) continue;
      final sens       = (row['sensitivity'] ?? 'C').toString();
      final boothCount = ((row['boothCount'] ?? row['booth_count'] ?? 1) as num).toInt();
      final key        = '$sens|$boothCount';
      agg.putIfAbsent(key, () => {'boothCount': boothCount, 'sensitivity': sens});

      final rank    = (row['rank'] ?? '').toString().toLowerCase();
      final isArmed = _isArmed(row['is_armed'] ?? row['isArmed']);
      final count   = ((row['count'] ?? 0) as num).toInt();
      if (count <= 0) continue;

      if (rank == 'si' || rank == 'sub inspector') {
        if (isArmed) agg[key]!['siArmed']      = (agg[key]!['siArmed']      ?? 0) + count;
        else          agg[key]!['siUnarmed']    = (agg[key]!['siUnarmed']    ?? 0) + count;
      } else if (rank == 'head constable') {
        if (isArmed) agg[key]!['hcArmed']      = (agg[key]!['hcArmed']      ?? 0) + count;
        else          agg[key]!['hcUnarmed']    = (agg[key]!['hcUnarmed']    ?? 0) + count;
      } else if (rank == 'constable') {
        if (isArmed) agg[key]!['constArmed']   = (agg[key]!['constArmed']   ?? 0) + count;
        else          agg[key]!['constUnarmed'] = (agg[key]!['constUnarmed'] ?? 0) + count;
      } else {
        if (isArmed) agg[key]!['auxArmed']     = (agg[key]!['auxArmed']     ?? 0) + count;
        else          agg[key]!['auxUnarmed']   = (agg[key]!['auxUnarmed']   ?? 0) + count;
      }
    }

    return agg.values
        .map((m) => _ManakRule(
          sensitivity:  m['sensitivity'] as String,
          boothCount:   m['boothCount']  as int,
          siArmed:      (m['siArmed']      ?? 0) as int,
          siUnarmed:    (m['siUnarmed']    ?? 0) as int,
          hcArmed:      (m['hcArmed']      ?? 0) as int,
          hcUnarmed:    (m['hcUnarmed']    ?? 0) as int,
          constArmed:   (m['constArmed']   ?? 0) as int,
          constUnarmed: (m['constUnarmed'] ?? 0) as int,
          auxArmed:     (m['auxArmed']     ?? 0) as int,
          auxUnarmed:   (m['auxUnarmed']   ?? 0) as int,
        ))
        .where((r) => r.hasAny)
        .toList()
      ..sort((a, b) {
        final sc = _sensCode(a.sensitivity).compareTo(_sensCode(b.sensitivity));
        return sc != 0 ? sc : a.boothCount.compareTo(b.boothCount);
      });
  }

  static bool _isArmed(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is int)  return v == 1;
    final s = v.toString().toLowerCase();
    return s == '1' || s == 'true' || s == 'yes' || s == 'armed';
  }

  static int _sensCode(String s) {
    switch (s.toUpperCase()) {
      case 'A++': return 0;
      case 'A':   return 1;
      case 'B':   return 2;
      default:    return 3;
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  MAIN DASHBOARD
// ══════════════════════════════════════════════════════════════════════════════
class StaffDashboardPage extends StatefulWidget {
  const StaffDashboardPage({super.key});
  @override
  State<StaffDashboardPage> createState() => _StaffDashboardPageState();
}

class _StaffDashboardPageState extends State<StaffDashboardPage>
    with TickerProviderStateMixin {
  int _navIdx = 0;

  Map?            _duty;
  Map?            _user;
  Map?            _districtDuty;
  _ElectionConfig _electionConfig  = const _ElectionConfig();
  bool            _loading         = true;
  String?         _error;
  String          _roleType        = 'none';
  bool            _isAfterElection = false;
  bool            _hasPastDuties   = false;

  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadData();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token   = await AuthService.getToken();
      final results = await Future.wait([
        ApiService.get('/staff/profile',         token: token),
        ApiService.get('/staff/my-duty',         token: token),
        ApiService.get('/staff/election-config', token: token),
        ApiService.get('/staff/district-duty',   token: token),
      ]);

      final userResp     = results[0];
      final resp         = results[1];
      final electionResp = results[2];
      final districtResp = results[3];

      final userData = userResp['data'] is Map
          ? Map<String, dynamic>.from(userResp['data'] as Map)
          : <String, dynamic>{};

      Map? dutyData;
      if (resp is Map) {
        dutyData = resp.containsKey('data')
            ? (resp['data'] is Map ? Map<String, dynamic>.from(resp['data'] as Map) : null)
            : Map<String, dynamic>.from(resp as Map);
      }
      final roleType = (dutyData?['roleType'] ?? 'none').toString();

      _ElectionConfig electionConfig = const _ElectionConfig();
      if (electionResp is Map) {
        final ecData = electionResp['data'];
        if (ecData is Map && ecData.isNotEmpty) {
          electionConfig = _ElectionConfig.fromMap(
              Map<String, dynamic>.from(ecData));
        }
      }

      if (electionConfig.district.isEmpty && userData['district'] != null) {
        electionConfig = _ElectionConfig(
          district:     userData['district']?.toString() ?? '',
          state:        electionConfig.state,
          electionType: electionConfig.electionType,
          electionName: electionConfig.electionName,
          phase:        electionConfig.phase,
          electionYear: electionConfig.electionYear,
          electionDate: electionConfig.electionDate,
          pratahSamay:  electionConfig.pratahSamay,
          sayaSamay:    electionConfig.sayaSamay,
        );
      }

      final electionDate = electionConfig.electionDate;
      bool isAfter = false;
      if (electionDate.isNotEmpty) {
        DateTime? ed;
        if (electionDate.contains('.')) {
          final p = electionDate.split('.');
          if (p.length == 3) ed = DateTime.tryParse('${p[2]}-${p[1]}-${p[0]}');
        } else {
          ed = DateTime.tryParse(electionDate);
        }
        if (ed != null) isAfter = DateTime.now().isAfter(ed);
      }

      Map? districtDuty;
      if (districtResp is Map && districtResp['data'] is Map) {
        districtDuty = Map<String, dynamic>.from(districtResp['data'] as Map);
      }

      bool hasPast = false;
      try {
        final histRes = await ApiService.get('/staff/history', token: token);
        final histData = histRes['data'];
        hasPast = histData is List && histData.isNotEmpty;
      } catch (_) {}

      setState(() {
        _user            = userData;
        _duty            = dutyData;
        _electionConfig  = electionConfig;
        _districtDuty    = districtDuty;
        _roleType        = roleType;
        _isAfterElection = isAfter;
        _hasPastDuties   = hasPast;
        _loading         = false;
      });
      _fadeCtrl.forward(from: 0);
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _goTo(int idx) {
    setState(() => _navIdx = idx);
    _fadeCtrl.forward(from: 0);
  }

  void _openHistory() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const DutyHistoryPage()));

  IconData _roleIcon() {
    if (_districtDuty != null && _roleType == 'none') return Icons.shield_outlined;
    switch (_roleType) {
      case 'sector':  return Icons.grid_view;
      case 'zone':    return Icons.map;
      case 'kshetra': return Icons.layers;
      default:        return Icons.how_to_vote;
    }
  }

  Color _roleColor() {
    if (_districtDuty != null && _roleType == 'none') return kDistrict;
    switch (_roleType) {
      case 'sector':  return kSector;
      case 'zone':    return kZone;
      case 'kshetra': return kKshetra;
      default:        return kPrimary;
    }
  }

  String _roleLabel() {
    if (_districtDuty != null && _roleType == 'none') return 'जनपदीय ड्यूटी';
    switch (_roleType) {
      case 'sector':  return 'सेक्टर अधिकारी';
      case 'zone':    return 'जोनल अधिकारी';
      case 'kshetra': return 'क्षेत्र अधिकारी';
      case 'booth':   return 'बूथ स्टाफ';
      default:        return 'स्टाफ';
    }
  }

  List<_NavItem> get _navItems {
    if (_isAfterElection) return [
      _NavItem('इतिहास', Icons.history_outlined, Icons.history),
    ];
    if (_districtDuty != null && _roleType == 'none') return [
      _NavItem('डैशबोर्ड',   Icons.dashboard_outlined, Icons.dashboard),
      _NavItem('ड्यूटी',     Icons.shield_outlined,     Icons.shield),
      _NavItem('सहयोगी',     Icons.groups_outlined,     Icons.groups),
      _NavItem('ड्यूटी कार्ड', Icons.badge_outlined,   Icons.badge),
    ];
    switch (_roleType) {
      case 'sector': return [
        _NavItem('डैशबोर्ड', Icons.dashboard_outlined,  Icons.dashboard),
        _NavItem('ड्यूटी',   Icons.location_on_outlined, Icons.location_on),
        _NavItem('उपस्थिति', Icons.fact_check_outlined,  Icons.fact_check),
        _NavItem('मानक',     Icons.rule_folder_outlined, Icons.rule_folder),
      ];
      case 'zone': return [
        _NavItem('डैशबोर्ड', Icons.dashboard_outlined, Icons.dashboard),
        _NavItem('ड्यूटी',   Icons.map_outlined,        Icons.map),
        _NavItem('सेक्टर',   Icons.grid_view_outlined,  Icons.grid_view),
        _NavItem('मानक',     Icons.rule_folder_outlined, Icons.rule_folder),
      ];
      case 'kshetra': return [
        _NavItem('डैशबोर्ड', Icons.dashboard_outlined, Icons.dashboard),
        _NavItem('ड्यूटी',   Icons.layers_outlined,     Icons.layers),
        _NavItem('जोन',      Icons.map_outlined,         Icons.map),
        _NavItem('मानक',     Icons.rule_folder_outlined, Icons.rule_folder),
      ];
      default: return [
        _NavItem('डैशबोर्ड',   Icons.dashboard_outlined,  Icons.dashboard),
        _NavItem('ड्यूटी',     Icons.location_on_outlined, Icons.location_on),
        _NavItem('सहयोगी',     Icons.groups_outlined,      Icons.groups),
        _NavItem('ड्यूटी कार्ड', Icons.badge_outlined,    Icons.badge),
      ];
    }
  }

  Future<void> _openMap() async {
    final lat = _duty?['latitude'];
    final lng = _duty?['longitude'];
    if (lat == null || lng == null) { _showNoLocDialog(); return; }
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    try {
      if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
      else _showNoLocDialog();
    } catch (_) { _showNoLocDialog(); }
  }

  void _showNoLocDialog() => showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: kError.withOpacity(0.4))),
        title: const Row(children: [
          Icon(Icons.location_off_outlined, color: kError, size: 20),
          SizedBox(width: 8),
          Expanded(child: Text('लोकेशन उपलब्ध नहीं',
              style: TextStyle(color: kDark, fontSize: 15, fontWeight: FontWeight.w800))),
        ]),
        content: const Text('इस केंद्र की GPS लोकेशन अभी तक दर्ज नहीं है।',
            style: TextStyle(color: kDark, fontSize: 13)),
        actions: [ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary, foregroundColor: Colors.white),
            child: const Text('ठीक है'))],
      ));

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: kError, width: 1.5)),
          title: const Row(children: [
            Icon(Icons.logout, color: kError),
            SizedBox(width: 8),
            Text('लॉग आउट', style: TextStyle(color: kError)),
          ]),
          content: const Text('क्या आप लॉग आउट करना चाहते हैं?',
              style: TextStyle(color: kDark)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('रद्द', style: TextStyle(color: kSubtle))),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: kError, foregroundColor: Colors.white),
                child: const Text('लॉग आउट')),
          ],
        ));
    if (ok == true) {
      await AuthService.logout();
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    }
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final items = _navItems;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: kBg,
        appBar: _buildAppBar(),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: kPrimary))
            : _error != null
                ? _ErrorState(error: _error!, onRetry: _loadData)
                : FadeTransition(opacity: _fadeAnim, child: _buildBody()),
        bottomNavigationBar: _buildBottomNav(items),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final rc = _roleColor();
    return AppBar(
      backgroundColor: kDark,
      elevation: 0,
      automaticallyImplyLeading: false,
      title: Row(children: [
        Container(width: 36, height: 36,
          decoration: BoxDecoration(
              color: rc, shape: BoxShape.circle,
              border: Border.all(color: kBorder)),
          child: Icon(_roleIcon(), color: Colors.white, size: 18)),
        const SizedBox(width: 10),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_isAfterElection ? 'ड्यूटी इतिहास'
              : (_navItems.isNotEmpty
                  ? _navItems[_navIdx.clamp(0, _navItems.length - 1)].label
                  : 'डैशबोर्ड'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                  color: Colors.white)),
          Text(_user?['name'] ?? 'Staff Portal',
              style: const TextStyle(fontSize: 10, color: Colors.white60),
              overflow: TextOverflow.ellipsis),
        ])),
      ]),
      actions: [
        GestureDetector(
          onTap: _openHistory,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _hasPastDuties
                  ? kSuccess.withOpacity(0.25)
                  : Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white30),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.history_rounded, color: Colors.white, size: 14),
              const SizedBox(width: 4),
              const Text('इतिहास',
                  style: TextStyle(color: Colors.white,
                      fontSize: 10, fontWeight: FontWeight.w700)),
              if (_hasPastDuties) ...[
                const SizedBox(width: 4),
                Container(width: 6, height: 6,
                    decoration: const BoxDecoration(
                        color: kSuccess, shape: BoxShape.circle)),
              ],
            ]),
          ),
        ),
        if (!_isAfterElection)
          Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _roleColor().withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _roleColor().withOpacity(0.4)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6,
                  decoration: BoxDecoration(
                      color: _roleColor(), shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text(_roleLabel(), style: TextStyle(
                  color: _roleColor(), fontSize: 9,
                  fontWeight: FontWeight.w700)),
            ]),
          ),
        IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
            onPressed: _loadData),
        IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white70),
            onPressed: _confirmLogout),
      ],
    );
  }

  Widget _buildBody() {
    if (_isAfterElection) {
      return _PostElectionView(
          user: _user,
          electionConfig: _electionConfig,
          onOpenHistory: _openHistory);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _buildSection())),
    );
  }

  Widget _buildSection() {
    if (_districtDuty != null && _roleType == 'none') {
      return _buildDistrictSection();
    }
    switch (_roleType) {
      case 'sector':  return _buildSectorSection();
      case 'zone':    return _buildZoneSection();
      case 'kshetra': return _buildKshetraSection();
      default:        return _buildBoothSection();
    }
  }

  Widget _buildDistrictSection() {
    final dd = Map<dynamic, dynamic>.from(_districtDuty!);
    switch (_navIdx) {
      case 0: return _DistrictOverviewSection(
          duty: dd, user: _user ?? {},
          electionConfig: _electionConfig,
          isAfterElection: _isAfterElection,
          onGoToDutyCard: () => _goTo(3));
      case 1: return _DistrictDetailSection(
          duty: dd, electionConfig: _electionConfig);
      case 2: return _DistrictBatchStaffSection(duty: dd);
      case 3: return _DistrictDutyCardSection(
          duty: dd, user: _user ?? {},
          electionConfig: _electionConfig);
      default: return const SizedBox();
    }
  }

  Widget _buildBoothSection() {
    final hasNoDuty = _duty == null || _roleType == 'none';
    switch (_navIdx) {
      case 0: return _BoothOverviewSection(
          duty: _duty, user: _user, noDuty: hasNoDuty,
          electionConfig: _electionConfig,
          hasPastDuties: _hasPastDuties,
          onGoToDutyCard: () => _goTo(3),
          onOpenMap: _openMap, onOpenHistory: _openHistory);
      case 1: return _DutyDetailSection(
          duty: _duty, noDuty: hasNoDuty, onOpenMap: _openMap,
          electionConfig: _electionConfig);
      case 2: return _CoStaffSection(duty: _duty, noDuty: hasNoDuty);
      case 3: return _DutyCardSection(
          duty: _duty, user: _user, noDuty: hasNoDuty,
          electionConfig: _electionConfig);
      default: return const SizedBox();
    }
  }

  Widget _buildSectorSection() {
    switch (_navIdx) {
      case 0: return _SectorOverviewSection(
          duty: _duty, user: _user, electionConfig: _electionConfig);
      case 1: return _SectorInfoSection(duty: _duty);
      case 2: return _SectorAttendanceSection(
          duty: _duty, onRefresh: _loadData);
      case 3: return _ManakSection(
          rules: _duty?['boothRules'] ?? [],
          electionConfig: _electionConfig);
      default: return const SizedBox();
    }
  }

  Widget _buildZoneSection() {
    switch (_navIdx) {
      case 0: return _ZoneOverviewSection(
          duty: _duty, user: _user, electionConfig: _electionConfig);
      case 1: return _ZoneInfoSection(duty: _duty);
      case 2: return _ZoneSectorsSection(duty: _duty);
      case 3: return _ManakSection(
          rules: _duty?['boothRules'] ?? [],
          electionConfig: _electionConfig);
      default: return const SizedBox();
    }
  }

  Widget _buildKshetraSection() {
    switch (_navIdx) {
      case 0: return _KshetraOverviewSection(
          duty: _duty, user: _user, electionConfig: _electionConfig);
      case 1: return _KshetraInfoSection(duty: _duty);
      case 2: return _KshetraZonesSection(duty: _duty);
      case 3: return _ManakSection(
          rules: _duty?['boothRules'] ?? [],
          electionConfig: _electionConfig);
      default: return const SizedBox();
    }
  }

  Widget _buildBottomNav(List<_NavItem> items) => Container(
    decoration: const BoxDecoration(
        color: kSurface, border: Border(top: BorderSide(color: kBorder))),
    child: SafeArea(
      child: SizedBox(
        height: 65,
        child: Row(
          children: List.generate(items.length, (i) {
            final sel = _navIdx == i;
            return Expanded(child: GestureDetector(
              onTap: () => _goTo(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: sel ? kBg : Colors.transparent,
                  border: Border(top: BorderSide(
                      color: sel ? _roleColor() : Colors.transparent, width: 3)),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(sel ? items[i].filledIcon : items[i].icon,
                      color: sel ? _roleColor() : kSubtle, size: 22),
                  const SizedBox(height: 3),
                  Text(items[i].label, style: TextStyle(
                      fontSize: 9,
                      fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                      color: sel ? _roleColor() : kSubtle),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ));
          }),
        ),
      ),
    ),
  );
}

class _NavItem {
  final String label;
  final IconData icon, filledIcon;
  const _NavItem(this.label, this.icon, this.filledIcon);
}

// ══════════════════════════════════════════════════════════════════════════════
//  ELECTION BANNER
// ══════════════════════════════════════════════════════════════════════════════
class _ElectionBanner extends StatelessWidget {
  final _ElectionConfig electionConfig;
  final bool isFinalized;
  const _ElectionBanner({required this.electionConfig, this.isFinalized = false});

  @override
  Widget build(BuildContext context) {
    if (electionConfig.isEmpty) return const SizedBox.shrink();
    final past = isFinalized;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: past
              ? [const Color(0xFF3E1500), const Color(0xFF7A3000)]
              : [const Color(0xFF1A237E), const Color(0xFF283593)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
            color: (past ? kPastElec : const Color(0xFF1A237E)).withOpacity(0.3),
            blurRadius: 12, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 32, height: 32,
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(
                past ? Icons.archive_rounded : Icons.how_to_vote_outlined,
                color: Colors.white, size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (electionConfig.electionName.isNotEmpty)
              Text(electionConfig.electionName,
                  style: const TextStyle(color: Colors.white,
                      fontSize: 13, fontWeight: FontWeight.w800),
                  maxLines: 2),
            if (electionConfig.electionType.isNotEmpty)
              Text(electionConfig.electionType,
                  style: const TextStyle(color: Colors.white70, fontSize: 10)),
            if (electionConfig.district.isNotEmpty)
              Text('जनपद: ${electionConfig.district}',
                  style: const TextStyle(color: Colors.white60, fontSize: 9)),
          ])),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (past) Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                  color: kPastElec.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: kPastElec.withOpacity(0.6))),
              child: const Text('पिछला चुनाव',
                  style: TextStyle(color: Color(0xFFFFCC80),
                      fontSize: 9, fontWeight: FontWeight.w800)),
            ),
            if (!past && electionConfig.phase.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24)),
                child: Text('चरण ${electionConfig.phase}',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 10, fontWeight: FontWeight.w700))),
            ],
          ]),
        ]),
        const SizedBox(height: 10),
        const Divider(color: Colors.white24, height: 1),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _ElecChip(
              Icons.calendar_today_outlined, 'मतदान तिथि',
              electionConfig.displayDate.isNotEmpty
                  ? electionConfig.displayDate
                  : electionConfig.electionDate)),
          if (electionConfig.pratahSamay.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(child: _ElecChip(
                Icons.wb_sunny_outlined, 'प्रातः',
                electionConfig.pratahSamay)),
          ],
          if (electionConfig.sayaSamay.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(child: _ElecChip(
                Icons.nights_stay_outlined, 'सायं',
                electionConfig.sayaSamay)),
          ],
        ]),
        if (electionConfig.state.isNotEmpty || electionConfig.electionYear.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(children: [
            if (electionConfig.state.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6)),
                child: Text('राज्य: ${electionConfig.state}',
                    style: const TextStyle(color: Colors.white70, fontSize: 9))),
            if (electionConfig.electionYear.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6)),
                child: Text('वर्ष: ${electionConfig.electionYear}',
                    style: const TextStyle(color: Colors.white70, fontSize: 9))),
          ]),
        ],
      ]),
    );
  }
}

class _ElecChip extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _ElecChip(this.icon, this.label, this.value);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: Colors.white60, size: 12),
      const SizedBox(width: 5),
      Flexible(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9)),
        Text(value, style: const TextStyle(color: Colors.white,
            fontSize: 11, fontWeight: FontWeight.w700),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ])),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  POST ELECTION VIEW
// ══════════════════════════════════════════════════════════════════════════════
class _PostElectionView extends StatelessWidget {
  final Map? user;
  final _ElectionConfig electionConfig;
  final VoidCallback onOpenHistory;
  const _PostElectionView({
    required this.user,
    required this.electionConfig,
    required this.onOpenHistory,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: kSuccess.withOpacity(0.3),
                blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: Column(children: [
            Container(width: 64, height: 64,
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15), shape: BoxShape.circle,
                  border: Border.all(color: Colors.white30, width: 2)),
              child: const Icon(Icons.how_to_vote_rounded,
                  color: Colors.white, size: 32)),
            const SizedBox(height: 16),
            const Text('चुनाव सम्पन्न हो गया', style: TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            if (electionConfig.electionName.isNotEmpty)
              Text(electionConfig.electionName,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            if (electionConfig.electionDate.isNotEmpty)
              Text('तिथि: ${electionConfig.displayDate}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
            if (electionConfig.phase.isNotEmpty)
              Text('चरण: ${electionConfig.phase}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 8),
            Text('${user?['name'] ?? ''} जी, आपकी ड्यूटी का रिकॉर्ड इतिहास में सुरक्षित है।',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
                textAlign: TextAlign.center),
          ]),
        ),
        const SizedBox(height: 20),
        _ProfileCard(user: user),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: onOpenHistory,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [kDark, Color(0xFF5A3E08)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: kDark.withOpacity(0.4),
                  blurRadius: 14, offset: const Offset(0, 5))],
            ),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 40, height: 40,
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.history_rounded,
                        color: Colors.white, size: 22)),
                const SizedBox(width: 12),
                const Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('ड्यूटी इतिहास देखें', style: TextStyle(
                      color: Colors.white, fontSize: 16,
                      fontWeight: FontWeight.w800)),
                  Text('Duty History', style: TextStyle(
                      color: Colors.white54, fontSize: 11)),
                ]),
              ]),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24)),
                child: const Text('सभी ड्यूटी रिकॉर्ड देखने के लिए टैप करें',
                    style: TextStyle(color: Colors.white70, fontSize: 11))),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: kInfo.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kInfo.withOpacity(0.2))),
          child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, color: kInfo, size: 16),
            SizedBox(width: 8),
            Expanded(child: Text(
              'चुनाव समाप्त हो जाने के बाद यहाँ कोई सक्रिय ड्यूटी नहीं दिखाई जाती। '
              'आपकी सभी पुरानी ड्यूटियाँ "इतिहास" में उपलब्ध हैं।',
              style: TextStyle(color: kInfo, fontSize: 12))),
          ])),
        const SizedBox(height: 24),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  BOOTH — OVERVIEW
// ══════════════════════════════════════════════════════════════════════════════
class _BoothOverviewSection extends StatelessWidget {
  final Map? duty, user;
  final _ElectionConfig electionConfig;
  final bool noDuty, hasPastDuties;
  final VoidCallback onGoToDutyCard, onOpenMap, onOpenHistory;

  const _BoothOverviewSection({
    required this.duty, required this.user,
    required this.noDuty, required this.electionConfig,
    required this.hasPastDuties,
    required this.onGoToDutyCard, required this.onOpenMap,
    required this.onOpenHistory,
  });

  @override
  Widget build(BuildContext context) {
    final r = _rs(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _ElectionBanner(electionConfig: electionConfig),
      _HeroCard(user: user, duty: duty, noDuty: noDuty),
      const SizedBox(height: 18),
      if (!noDuty && duty != null) ...[
        GridView.count(
          crossAxisCount: 2, shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12, mainAxisSpacing: 12,
          childAspectRatio: r.compact ? 1.3 : 1.45,
          children: [
            _StatCard(icon: Icons.location_on_outlined, label: 'मतदान केंद्र',
                value: v(duty?['centerName']), color: kPrimary),
            _StatCard(icon: Icons.directions_bus_outlined, label: 'बस संख्या',
                value: (duty?['busNo']?.toString().isNotEmpty == true)
                    ? 'बस–${duty!['busNo']}' : '—', color: kInfo),
            _StatCard(icon: Icons.map_outlined, label: 'सेक्टर',
                value: v(duty?['sectorName']), color: kSuccess),
            _StatCard(icon: Icons.groups_outlined, label: 'सहयोगी कर्मी',
                value: '${(duty?['allStaff'] as List?)?.length ?? 0} कर्मी',
                color: const Color(0xFFD84315)),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(icon: Icons.info_outline_rounded, title: 'संक्षिप्त विवरण',
          child: Column(children: [
            _InfoTile(Icons.local_police_outlined,    'थाना',         duty?['thana']),
            _InfoTile(Icons.account_balance_outlined, 'ग्राम पंचायत', duty?['gpName']),
            _InfoTile(Icons.layers_outlined,          'जोन',          duty?['zoneName']),
            _InfoTile(Icons.public_outlined,          'सुपर जोन',     duty?['superZoneName']),
            _InfoTile(Icons.category_outlined,        'केंद्र प्रकार', ct(duty?['centerType'])),
          ]),
        ),
        const SizedBox(height: 12),
        _NavButton(icon: Icons.navigation_rounded,
            label: 'Google Maps पर नेविगेट करें',
            color: kPrimary, onTap: onOpenMap),
        const SizedBox(height: 12),
        _NavButton(icon: Icons.print_outlined,
            label: 'ड्यूटी कार्ड प्रिंट करें',
            color: kDark, onTap: onGoToDutyCard),
      ] else ...[
        _NoDutyCard(hasPastDuties: hasPastDuties, onOpenHistory: onOpenHistory),
      ],
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  NO DUTY CARD
// ══════════════════════════════════════════════════════════════════════════════
class _NoDutyCard extends StatelessWidget {
  final bool hasPastDuties;
  final VoidCallback onOpenHistory;
  const _NoDutyCard({required this.hasPastDuties, required this.onOpenHistory});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kBorder.withOpacity(0.5)),
          boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.05),
              blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 64, height: 64,
              decoration: BoxDecoration(color: kSurface, shape: BoxShape.circle,
                  border: Border.all(color: kBorder)),
              child: const Icon(Icons.location_off_outlined,
                  color: kPrimary, size: 30)),
          const SizedBox(height: 16),
          const Text('अभी तक ड्यूटी नहीं सौंपी गई',
              style: TextStyle(color: kDark, fontSize: 16,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('व्यवस्थापक द्वारा ड्यूटी सौंपे जाने पर यहाँ दिखेगी।',
              style: TextStyle(color: kSubtle, fontSize: 12),
              textAlign: TextAlign.center),
        ]),
      ),
      if (hasPastDuties) ...[
        const SizedBox(height: 16),
        GestureDetector(
          onTap: onOpenHistory,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kPastElec.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kPastElec.withOpacity(0.35)),
            ),
            child: Row(children: [
              Container(width: 42, height: 42,
                decoration: BoxDecoration(
                    color: kPastElec.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.history_edu_outlined,
                    color: kPastElec, size: 22)),
              const SizedBox(width: 12),
              const Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('पिछली ड्यूटियां देखें', style: TextStyle(
                    color: kPastElec, fontSize: 14,
                    fontWeight: FontWeight.w800)),
                Text('आपकी पिछले चुनाव की ड्यूटियां',
                    style: TextStyle(color: kSubtle, fontSize: 11)),
              ])),
              const Icon(Icons.chevron_right, color: kPastElec, size: 22),
            ]),
          ),
        ),
      ],
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  BOOTH — DUTY DETAILS
// ══════════════════════════════════════════════════════════════════════════════
class _DutyDetailSection extends StatelessWidget {
  final Map? duty;
  final _ElectionConfig electionConfig;
  final bool noDuty;
  final VoidCallback onOpenMap;
  const _DutyDetailSection({
    required this.duty, required this.noDuty,
    required this.onOpenMap, required this.electionConfig,
  });

  @override
  Widget build(BuildContext context) {
    if (noDuty) return const _NoDutyState();
    return Column(children: [
      _ElectionBanner(electionConfig: electionConfig),
      _SectionCard(icon: Icons.location_on_outlined, title: 'ड्यूटी स्थान',
        child: Column(children: [
          _InfoTile(Icons.how_to_vote_outlined,     'मतदान केंद्र', duty?['centerName']),
          _InfoTile(Icons.home_outlined,            'पता',          duty?['centerAddress']),
          _InfoTile(Icons.category_outlined,        'केंद्र प्रकार', ct(duty?['centerType'])),
          _InfoTile(Icons.local_police_outlined,    'थाना',         duty?['thana']),
          _InfoTile(Icons.account_balance_outlined, 'ग्राम पंचायत', duty?['gpName']),
        ]),
      ),
      const SizedBox(height: 14),
      _SectionCard(icon: Icons.map_outlined, title: 'प्रशासनिक विवरण',
        child: Column(children: [
          _InfoTile(Icons.map_outlined,            'सेक्टर',    duty?['sectorName']),
          _InfoTile(Icons.layers_outlined,         'जोन',       duty?['zoneName']),
          _InfoTile(Icons.home_work_outlined,      'जोन मुख्यालय', duty?['zoneHq']),
          _InfoTile(Icons.public_outlined,         'सुपर जोन',  duty?['superZoneName']),
          _InfoTile(Icons.directions_bus_outlined, 'बस संख्या',
              (duty?['busNo']?.toString().isNotEmpty == true)
                  ? 'बस–${duty!['busNo']}' : null),
        ]),
      ),
      const SizedBox(height: 14),
      if ((duty?['sectorOfficers'] as List?)?.isNotEmpty == true)
        _OfficerCard(label: 'सेक्टर अधिकारी',
            officers: duty!['sectorOfficers'] as List),
      if ((duty?['zonalOfficers'] as List?)?.isNotEmpty == true) ...[
        const SizedBox(height: 12),
        _OfficerCard(label: 'जोनल अधिकारी',
            officers: duty!['zonalOfficers'] as List),
      ],
      if ((duty?['superOfficers'] as List?)?.isNotEmpty == true) ...[
        const SizedBox(height: 12),
        _OfficerCard(label: 'क्षेत्र अधिकारी',
            officers: duty!['superOfficers'] as List),
      ],
      const SizedBox(height: 14),
      _NavButton(icon: Icons.navigation_rounded,
          label: 'Google Maps पर नेविगेट करें',
          color: kPrimary, onTap: onOpenMap),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  BOOTH — CO-STAFF
// ══════════════════════════════════════════════════════════════════════════════
class _CoStaffSection extends StatelessWidget {
  final Map? duty;
  final bool noDuty;
  const _CoStaffSection({required this.duty, required this.noDuty});

  @override
  Widget build(BuildContext context) {
    if (noDuty) return const _NoDutyState();
    final staff = duty?['allStaff'] as List? ?? [];
    return _SectionCard(
      icon: Icons.groups_outlined,
      title: 'सहयोगी कर्मी (${staff.length})',
      child: staff.isEmpty
          ? const Padding(padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('कोई सहयोगी नहीं',
                  style: TextStyle(color: kSubtle, fontSize: 13))))
          : Column(children: staff.asMap().entries.map((e) {
              final s = e.value is Map ? e.value as Map : {};
              return _StaffRow(index: e.key, staff: s,
                  total: staff.length,
                  armed: s['is_armed'] == 1 || s['is_armed'] == true);
            }).toList()),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  BOOTH — DUTY CARD SECTION
// ══════════════════════════════════════════════════════════════════════════════
class _DutyCardSection extends StatefulWidget {
  final Map? duty, user;
  final _ElectionConfig electionConfig;
  final bool noDuty;
  const _DutyCardSection({
    required this.duty, required this.user,
    required this.noDuty, required this.electionConfig,
  });
  @override
  State<_DutyCardSection> createState() => _DutyCardSectionState();
}

class _DutyCardSectionState extends State<_DutyCardSection> {
  bool _printing = false, _hasMarked = false;

  Map<String, dynamic> _toAdminShape() {
    final d  = widget.duty ?? {};
    final u  = widget.user ?? {};
    final ec = widget.electionConfig;
    final sahyogi = (d['allStaff'] ?? []) as List;
    return {
      'name':         u['name']        ?? '',
      'pno':          u['pno']         ?? '',
      'mobile':       u['mobile']      ?? '',
      'rank':         u['rank']        ?? u['user_rank'] ?? '',
      'user_rank':    u['rank']        ?? u['user_rank'] ?? '',
      'isArmed':      u['isArmed']     ?? false,
      'is_armed':     u['isArmed']     ?? false,
      'staffThana':   u['thana']       ?? '',
      'thana':        u['thana']       ?? '',
      'district':     u['district']    ?? '',
      'adminDistrict': ec.district.isNotEmpty
          ? ec.district : (u['district'] ?? ''),
      'centerName':   d['centerName']  ?? '',
      'centerType':   d['centerType']  ?? '',
      'gpName':       d['gpName']      ?? '',
      'sectorName':   d['sectorName']  ?? '',
      'zoneName':     d['zoneName']    ?? '',
      'superZoneName': d['superZoneName'] ?? '',
      'busNo':        d['busNo']       ?? '',
      'bus_no':       d['busNo']       ?? '',
      'zonalOfficers':  d['zonalOfficers']  ?? [],
      'sectorOfficers': d['sectorOfficers'] ?? [],
      'superOfficers':  d['superOfficers']  ?? [],
      'sahyogi':      sahyogi,
      'allStaff':     sahyogi,
      'electionName': ec.electionName,
      'electionType': ec.electionType,
      'electionDate': ec.electionDate,
      'phase':        ec.phase,
      'pratahSamay':  ec.pratahSamay,
      'sayaSamay':    ec.sayaSamay,
      'electionYear': ec.electionYear,
      'state':        ec.state,
      'district':     ec.district.isNotEmpty ? ec.district : (u['district'] ?? ''),
    };
  }

  Future<void> _printCard() async {
    setState(() => _printing = true);
    try {
      final font   = await PdfGoogleFonts.notoSansDevanagariRegular();
      final bold   = await PdfGoogleFonts.notoSansDevanagariBold();
      final doc    = pw.Document();
      final shape  = _toAdminShape();
      final cfg    = widget.electionConfig.toConfigMap();
      if (cfg['district']?.isEmpty == true && shape['adminDistrict'] != null) {
        cfg['district'] = shape['adminDistrict'] as String;
      }
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a6.landscape,
        margin: const pw.EdgeInsets.all(4),
        build: (_) => buildDutyCardPdf(shape, font, bold, config: cfg),
      ));
      await Printing.layoutPdf(onLayout: (_) async => doc.save());
      try {
        final token = await AuthService.getToken();
        await ApiService.post('/staff/mark-card-downloaded', {}, token: token);
      } catch (_) {}
      if (mounted) setState(() => _hasMarked = true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('प्रिंट त्रुटि: $e'), backgroundColor: kError,
          behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.noDuty) return const _NoDutyState();
    final d  = widget.duty ?? {};
    final u  = widget.user ?? {};
    final ec = widget.electionConfig;
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [kDark, Color(0xFF5A3E08)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Container(width: 48, height: 48,
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.badge_outlined,
                  color: Colors.white, size: 24)),
          const SizedBox(width: 14),
          const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ड्यूटी कार्ड', style: TextStyle(
                color: Colors.white, fontSize: 16,
                fontWeight: FontWeight.w800)),
            Text('आधिकारिक चुनाव ड्यूटी कार्ड',
                style: TextStyle(color: Colors.white60, fontSize: 11)),
          ])),
          GestureDetector(
            onTap: _printing ? null : _printCard,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                  color: _printing ? kPrimary.withOpacity(0.6) : kPrimary,
                  borderRadius: BorderRadius.circular(12)),
              child: _printing
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.print_outlined, color: Colors.white, size: 15),
                      SizedBox(width: 6),
                      Text('प्रिंट', style: TextStyle(
                          color: Colors.white, fontSize: 12,
                          fontWeight: FontWeight.w700)),
                    ]),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      if (_hasMarked)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: kSuccess.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kSuccess.withOpacity(0.3))),
          child: const Row(children: [
            Icon(Icons.check_circle_rounded, color: kSuccess, size: 18),
            SizedBox(width: 8),
            Expanded(child: Text('ड्यूटी कार्ड डाउनलोड हो गया ✓',
                style: TextStyle(color: kSuccess, fontSize: 13,
                    fontWeight: FontWeight.w700))),
          ]),
        ),
      if (!ec.isEmpty) ...[
        _ElectionBanner(electionConfig: ec),
        const SizedBox(height: 4),
      ],
      _SectionCard(icon: Icons.preview_outlined, title: 'कार्ड विवरण',
        child: Column(children: [
          _PreviewRow('नाम',          u['name']),
          _PreviewRow('PNO',          u['pno']),
          _PreviewRow('पद',           rh(u['rank'] ?? u['user_rank'])),
          _PreviewRow('केंद्र',        d['centerName']),
          _PreviewRow('केंद्र प्रकार', ct(d['centerType'])),
          _PreviewRow('बस', (d['busNo'] ?? '').toString().isNotEmpty
              ? 'बस–${d['busNo']}' : null),
          _PreviewRow('सेक्टर',        d['sectorName']),
          _PreviewRow('जोन',           d['zoneName']),
          if (ec.electionName.isNotEmpty) _PreviewRow('चुनाव', ec.electionName),
          if (ec.electionType.isNotEmpty) _PreviewRow('प्रकार', ec.electionType),
          if (ec.phase.isNotEmpty)        _PreviewRow('चरण', ec.phase),
          if (ec.electionDate.isNotEmpty) _PreviewRow('मतदान तिथि', ec.displayDate),
          if (ec.pratahSamay.isNotEmpty)  _PreviewRow('प्रातः समय', ec.pratahSamay),
          if (ec.sayaSamay.isNotEmpty)    _PreviewRow('सायं समय', ec.sayaSamay),
          if (ec.district.isNotEmpty)     _PreviewRow('जनपद', ec.district),
          _PreviewRow('सहयोगी',
              '${(d['allStaff'] as List?)?.length ?? 0} कर्मी'),
        ])),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DISTRICT DUTY — OVERVIEW
// ══════════════════════════════════════════════════════════════════════════════
class _DistrictOverviewSection extends StatelessWidget {
  final Map duty, user;
  final _ElectionConfig electionConfig;
  final bool isAfterElection;
  final VoidCallback onGoToDutyCard;

  const _DistrictOverviewSection({
    required this.duty, required this.user,
    required this.electionConfig, required this.isAfterElection,
    required this.onGoToDutyCard,
  });

  @override
  Widget build(BuildContext context) {
    final r          = _rs(context);
    final dutyType   = duty['dutyType']?.toString() ?? '';
    final batchNo    = duty['batchNo'];
    final busNo      = duty['busNo']?.toString() ?? '';
    final note       = duty['note']?.toString()  ?? '';
    final batchStaff = (duty['batchStaff'] as List? ?? []);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _ElectionBanner(electionConfig: electionConfig, isFinalized: isAfterElection),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [kDistrict, Color(0xFF6A1B9A)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: kDistrict.withOpacity(0.35),
              blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 48, height: 48,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white30, width: 2)),
              child: const Icon(Icons.shield_outlined,
                  color: Colors.white, size: 24)),
            const SizedBox(width: 14),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('जनपदीय ड्यूटी', style: TextStyle(
                  color: Colors.white60, fontSize: 10,
                  fontWeight: FontWeight.w600, letterSpacing: 1)),
              Text(dutyLabel(dutyType), style: TextStyle(
                  color: Colors.white, fontSize: r.s(15, 18),
                  fontWeight: FontWeight.w800), maxLines: 2),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24)),
              child: Text('बैच ${batchNo ?? '—'}', style: const TextStyle(
                  color: Colors.white, fontSize: 11,
                  fontWeight: FontWeight.w800))),
          ]),
          if (busNo.isNotEmpty || note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(height: 1, color: Colors.white.withOpacity(0.15)),
            const SizedBox(height: 8),
            if (busNo.isNotEmpty) Row(children: [
              const Icon(Icons.directions_bus_outlined,
                  color: Colors.white54, size: 14),
              const SizedBox(width: 6),
              Text('बस: $busNo',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.notes_outlined,
                    color: Colors.white54, size: 14),
                const SizedBox(width: 6),
                Expanded(child: Text(note,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12))),
              ]),
            ],
          ],
        ]),
      ),
      const SizedBox(height: 14),
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12, mainAxisSpacing: 12,
        childAspectRatio: r.compact ? 1.2 : 1.45,
        children: [
          _StatCard(icon: Icons.shield_outlined, label: 'ड्यूटी प्रकार',
              value: dutyLabel(dutyType), color: kDistrict),
          _StatCard(icon: Icons.confirmation_number_outlined, label: 'बैच संख्या',
              value: 'बैच ${batchNo ?? '—'}', color: kPrimary),
          _StatCard(icon: Icons.groups_outlined, label: 'बैच कर्मी',
              value: '${batchStaff.length} कर्मी', color: kSuccess),
          _StatCard(icon: Icons.directions_bus_outlined, label: 'बस संख्या',
              value: busNo.isNotEmpty ? busNo : '—', color: kInfo),
        ],
      ),
      const SizedBox(height: 14),
      _HeroCard(user: user, duty: null, noDuty: false,
          subtitle: 'जनपदीय ड्यूटी कर्मी'),
      const SizedBox(height: 14),
      _NavButton(icon: Icons.print_outlined,
          label: 'ड्यूटी कार्ड प्रिंट करें',
          color: kDark, onTap: onGoToDutyCard),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DISTRICT DUTY — DETAIL
// ══════════════════════════════════════════════════════════════════════════════
class _DistrictDetailSection extends StatelessWidget {
  final Map duty;
  final _ElectionConfig electionConfig;
  const _DistrictDetailSection({required this.duty, required this.electionConfig});

  @override
  Widget build(BuildContext context) {
    final dutyType   = duty['dutyType']?.toString() ?? '';
    final batchNo    = duty['batchNo'];
    final busNo      = duty['busNo']?.toString()    ?? '';
    final note       = duty['note']?.toString()     ?? '';
    final district   = duty['district']?.toString() ?? '';
    final assignedAt = duty['assignedAt']?.toString() ?? '';

    return Column(children: [
      _SectionCard(icon: Icons.shield_outlined, title: 'जनपदीय ड्यूटी विवरण',
        child: Column(children: [
          _InfoTile(Icons.work_outline, 'ड्यूटी प्रकार', dutyLabel(dutyType)),
          _InfoTile(Icons.confirmation_number_outlined, 'बैच संख्या', 'बैच $batchNo'),
          if (busNo.isNotEmpty)
            _InfoTile(Icons.directions_bus_outlined, 'बस संख्या', busNo),
          if (district.isNotEmpty)
            _InfoTile(Icons.location_city_outlined, 'जनपद', district),
          if (note.isNotEmpty)
            _InfoTile(Icons.notes_outlined, 'विशेष नोट', note),
          if (assignedAt.isNotEmpty)
            _InfoTile(Icons.schedule_outlined, 'नियुक्ति समय', assignedAt),
        ]),
      ),
      const SizedBox(height: 14),
      if (!electionConfig.isEmpty)
        _SectionCard(icon: Icons.how_to_vote_outlined, title: 'चुनाव विवरण',
          child: Column(children: [
            if (electionConfig.electionName.isNotEmpty)
              _InfoTile(Icons.how_to_vote_outlined, 'चुनाव', electionConfig.electionName),
            if (electionConfig.electionType.isNotEmpty)
              _InfoTile(Icons.category_outlined,    'प्रकार', electionConfig.electionType),
            if (electionConfig.phase.isNotEmpty)
              _InfoTile(Icons.numbers_outlined,     'चरण',    electionConfig.phase),
            if (electionConfig.electionDate.isNotEmpty)
              _InfoTile(Icons.calendar_today_outlined, 'तिथि', electionConfig.displayDate),
            if (electionConfig.pratahSamay.isNotEmpty)
              _InfoTile(Icons.wb_sunny_outlined, 'प्रातः समय', electionConfig.pratahSamay),
            if (electionConfig.sayaSamay.isNotEmpty)
              _InfoTile(Icons.nights_stay_outlined, 'सायं समय', electionConfig.sayaSamay),
            if (electionConfig.district.isNotEmpty)
              _InfoTile(Icons.location_city_outlined, 'जनपद', electionConfig.district),
            if (electionConfig.state.isNotEmpty)
              _InfoTile(Icons.map_outlined, 'राज्य', electionConfig.state),
          ]),
        ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: kDistrict.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kDistrict.withOpacity(0.25))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.info_outline_rounded, color: kDistrict, size: 16),
            const SizedBox(width: 8),
            Text('ड्यूटी जानकारी', style: TextStyle(
                color: kDistrict, fontSize: 13, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          Text(
            'आप "${dutyLabel(dutyType)}" ड्यूटी पर बैच $batchNo में तैनात हैं। '
            'यह जनपद स्तरीय ड्यूटी है।',
            style: TextStyle(color: kDistrict.withOpacity(0.8), fontSize: 12)),
        ]),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DISTRICT DUTY — BATCH STAFF
// ══════════════════════════════════════════════════════════════════════════════
class _DistrictBatchStaffSection extends StatelessWidget {
  final Map duty;
  const _DistrictBatchStaffSection({required this.duty});

  @override
  Widget build(BuildContext context) {
    final staff   = (duty['batchStaff'] as List? ?? []);
    final batchNo = duty['batchNo'];
    return _SectionCard(
      icon: Icons.groups_outlined,
      title: 'बैच $batchNo के सहयोगी कर्मी (${staff.length})',
      child: staff.isEmpty
          ? const Padding(padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('कोई सहयोगी नहीं',
                  style: TextStyle(color: kSubtle, fontSize: 13))))
          : Column(children: staff.asMap().entries.map((e) {
              final s = e.value is Map ? e.value as Map : {};
              return _StaffRow(index: e.key, staff: s, total: staff.length,
                  armed: s['is_armed'] == 1 || s['is_armed'] == true);
            }).toList()),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DISTRICT DUTY CARD
// ══════════════════════════════════════════════════════════════════════════════
class _DistrictDutyCardSection extends StatefulWidget {
  final Map duty, user;
  final _ElectionConfig electionConfig;
  const _DistrictDutyCardSection({
    required this.duty, required this.user,
    required this.electionConfig,
  });
  @override
  State<_DistrictDutyCardSection> createState() =>
      _DistrictDutyCardSectionState();
}

class _DistrictDutyCardSectionState extends State<_DistrictDutyCardSection> {
  bool _printing = false, _hasMarked = false;

  Map<String, dynamic> _toAdminShape() {
    final d  = widget.duty;
    final u  = widget.user;
    final ec = widget.electionConfig;
    final batchStaff = (d['batchStaff'] as List? ?? []);
    return {
      'name':       u['name']     ?? '',
      'pno':        u['pno']      ?? '',
      'mobile':     u['mobile']   ?? '',
      'rank':       u['rank']     ?? u['user_rank'] ?? '',
      'user_rank':  u['rank']     ?? u['user_rank'] ?? '',
      'isArmed':    u['isArmed']  ?? false,
      'is_armed':   u['isArmed']  ?? false,
      'staffThana': u['thana']    ?? '',
      'thana':      u['thana']    ?? '',
      'district':   ec.district.isNotEmpty ? ec.district : (u['district'] ?? ''),
      'adminDistrict': ec.district.isNotEmpty ? ec.district : (u['district'] ?? ''),
      'centerName': dutyLabel(d['dutyType']?.toString()),
      'centerType': 'district',
      'gpName': '', 'sectorName': '', 'zoneName': '', 'superZoneName': '',
      'busNo':        d['busNo']     ?? '',
      'bus_no':       d['busNo']     ?? '',
      'zonalOfficers': [], 'sectorOfficers': [], 'superOfficers': [],
      'sahyogi':    batchStaff,
      'allStaff':   batchStaff,
      'staff':      batchStaff,
      'electionName': ec.electionName,
      'electionType': ec.electionType,
      'electionDate': ec.electionDate,
      'phase':        ec.phase,
      'pratahSamay':  ec.pratahSamay,
      'sayaSamay':    ec.sayaSamay,
      'electionYear': ec.electionYear,
      'state':        ec.state,
      'batchNo':      d['batchNo']?.toString() ?? '',
      'dutyLabelHi':  dutyLabel(d['dutyType']?.toString()),
    };
  }

  Future<void> _printCard() async {
    setState(() => _printing = true);
    try {
      final font = await PdfGoogleFonts.notoSansDevanagariRegular();
      final bold = await PdfGoogleFonts.notoSansDevanagariBold();
      final doc  = pw.Document();
      final shape = _toAdminShape();
      final cfg  = widget.electionConfig.toConfigMap();
      if (cfg['district']?.isEmpty == true) {
        cfg['district'] = shape['adminDistrict'] as String? ?? '';
      }
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a6.landscape,
        margin: const pw.EdgeInsets.all(4),
        build: (_) => buildDutyCardPdf(shape, font, bold, config: cfg),
      ));
      await Printing.layoutPdf(onLayout: (_) async => doc.save());
      try {
        final token = await AuthService.getToken();
        await ApiService.post('/staff/mark-card-downloaded', {}, token: token);
      } catch (_) {}
      if (mounted) setState(() => _hasMarked = true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('प्रिंट त्रुटि: $e'), backgroundColor: kError,
          behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d  = widget.duty;
    final u  = widget.user;
    final ec = widget.electionConfig;
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [kDistrict, Color(0xFF6A1B9A)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Container(width: 48, height: 48,
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.badge_outlined,
                  color: Colors.white, size: 24)),
          const SizedBox(width: 14),
          const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('जनपदीय ड्यूटी कार्ड', style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            Text('District Duty Card',
                style: TextStyle(color: Colors.white60, fontSize: 11)),
          ])),
          GestureDetector(
            onTap: _printing ? null : _printCard,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                  color: _printing ? kPrimary.withOpacity(0.6) : kPrimary,
                  borderRadius: BorderRadius.circular(12)),
              child: _printing
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.print_outlined, color: Colors.white, size: 15),
                      SizedBox(width: 6),
                      Text('प्रिंट', style: TextStyle(
                          color: Colors.white, fontSize: 12,
                          fontWeight: FontWeight.w700)),
                    ]),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      if (_hasMarked)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: kSuccess.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kSuccess.withOpacity(0.3))),
          child: const Row(children: [
            Icon(Icons.check_circle_rounded, color: kSuccess, size: 18),
            SizedBox(width: 8),
            Expanded(child: Text('ड्यूटी कार्ड डाउनलोड हो गया ✓',
                style: TextStyle(color: kSuccess, fontSize: 13,
                    fontWeight: FontWeight.w700))),
          ]),
        ),
      if (!ec.isEmpty) ...[
        _ElectionBanner(electionConfig: ec),
        const SizedBox(height: 4),
      ],
      _SectionCard(icon: Icons.preview_outlined, title: 'कार्ड विवरण',
        child: Column(children: [
          _PreviewRow('नाम',           u['name']),
          _PreviewRow('PNO',           u['pno']),
          _PreviewRow('पद',            rh(u['rank'] ?? u['user_rank'])),
          _PreviewRow('ड्यूटी प्रकार', dutyLabel(d['dutyType']?.toString())),
          _PreviewRow('बैच संख्या',    'बैच ${d['batchNo'] ?? '—'}'),
          if ((d['busNo']?.toString() ?? '').isNotEmpty)
            _PreviewRow('बस', d['busNo']),
          _PreviewRow('जनपद',          ec.district.isNotEmpty
              ? ec.district : (u['district'] ?? '')),
          if (ec.electionName.isNotEmpty) _PreviewRow('चुनाव', ec.electionName),
          if (ec.electionType.isNotEmpty) _PreviewRow('प्रकार', ec.electionType),
          if (ec.phase.isNotEmpty)        _PreviewRow('चरण', ec.phase),
          if (ec.electionDate.isNotEmpty) _PreviewRow('मतदान तिथि', ec.displayDate),
          if (ec.pratahSamay.isNotEmpty)  _PreviewRow('प्रातः समय', ec.pratahSamay),
          if (ec.sayaSamay.isNotEmpty)    _PreviewRow('सायं समय', ec.sayaSamay),
          _PreviewRow('सहयोगी',
              '${(d['batchStaff'] as List? ?? []).length} कर्मी'),
        ])),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SECTOR — OVERVIEW / INFO / ATTENDANCE
// ══════════════════════════════════════════════════════════════════════════════
class _SectorOverviewSection extends StatelessWidget {
  final Map? duty, user;
  final _ElectionConfig electionConfig;
  const _SectorOverviewSection({
    required this.duty, required this.user,
    required this.electionConfig,
  });

  @override
  Widget build(BuildContext context) {
    if (duty == null) return const _NoDutyState();
    final r = _rs(context);
    return Column(children: [
      _ElectionBanner(electionConfig: electionConfig),
      Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: kSector.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kSector.withOpacity(0.3)),
        ),
        child: Row(children: [
          Container(width: 40, height: 40,
              decoration: BoxDecoration(
                  color: kSector, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.grid_view_outlined,
                  color: Colors.white, size: 20)),
          const SizedBox(width: 12),
          const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('सेक्टर अधिकारी', style: TextStyle(
                color: kSector, fontSize: 14, fontWeight: FontWeight.w800)),
            Text('बूथ उपस्थिति अंकित करना आपकी जिम्मेदारी है',
                style: TextStyle(color: kSubtle, fontSize: 11)),
          ])),
        ]),
      ),
      _HeroCard(user: user, duty: duty, noDuty: false, subtitle: 'सेक्टर अधिकारी'),
      const SizedBox(height: 16),
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12, mainAxisSpacing: 12,
        childAspectRatio: r.compact ? 1.3 : 1.45,
        children: [
          _StatCard(icon: Icons.how_to_vote_outlined, label: 'कुल बूथ',
              value: '${duty!['totalBooths'] ?? 0}', color: kPrimary),
          _StatCard(icon: Icons.groups_outlined, label: 'असाइन स्टाफ',
              value: '${duty!['totalAssigned'] ?? 0}', color: kSuccess),
          _StatCard(icon: Icons.account_balance_outlined, label: 'ग्राम पंचायत',
              value: '${(duty!['gramPanchayats'] as List?)?.length ?? 0}',
              color: kInfo),
          _StatCard(icon: Icons.map_outlined, label: 'जोन',
              value: v(duty!['zoneName']), color: kAccent),
        ],
      ),
      const SizedBox(height: 14),
      _SectionCard(icon: Icons.info_outline_rounded, title: 'सेक्टर विवरण',
        child: Column(children: [
          _InfoTile(Icons.grid_view_outlined, 'सेक्टर',   duty!['sectorName']),
          _InfoTile(Icons.home_work_outlined, 'मुख्यालय', duty!['hqAddress']),
          _InfoTile(Icons.layers_outlined,    'जोन',      duty!['zoneName']),
          _InfoTile(Icons.public_outlined,    'सुपर जोन', duty!['superZoneName']),
        ]),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kInfo.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kInfo.withOpacity(0.25)),
        ),
        child: const Row(children: [
          Icon(Icons.info_outline, color: kInfo, size: 14),
          SizedBox(width: 8),
          Expanded(child: Text(
            '"उपस्थिति" टैब पर जाकर अपने सेक्टर के बूथ स्टाफ की उपस्थिति अंकित करें।',
            style: TextStyle(color: kInfo, fontSize: 11, height: 1.4))),
        ]),
      ),
    ]);
  }
}

class _SectorInfoSection extends StatelessWidget {
  final Map? duty;
  const _SectorInfoSection({required this.duty});

  @override
  Widget build(BuildContext context) {
    if (duty == null) return const _NoDutyState();
    final co    = (duty!['coOfficers']    as List? ?? []);
    final zonal = (duty!['zonalOfficers'] as List? ?? []);
    return Column(children: [
      _SectionCard(icon: Icons.grid_view_outlined, title: 'सेक्टर जानकारी',
        child: Column(children: [
          _InfoTile(Icons.grid_view_outlined, 'सेक्टर',    duty!['sectorName']),
          _InfoTile(Icons.home_work_outlined, 'HQ पता',    duty!['hqAddress']),
          _InfoTile(Icons.map_outlined,       'जोन',       duty!['zoneName']),
          _InfoTile(Icons.public_outlined,    'सुपर जोन', duty!['superZoneName']),
        ]),
      ),
      if (co.isNotEmpty) ...[const SizedBox(height: 14),
        _OfficerCard(label: 'सह-सेक्टर अधिकारी', officers: co)],
      if (zonal.isNotEmpty) ...[const SizedBox(height: 12),
        _OfficerCard(label: 'जोनल अधिकारी (वरिष्ठ)', officers: zonal)],
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SECTOR — ATTENDANCE
// ══════════════════════════════════════════════════════════════════════════════
class _SectorAttendanceSection extends StatefulWidget {
  final Map? duty;
  final VoidCallback onRefresh;
  const _SectorAttendanceSection({required this.duty, required this.onRefresh});
  @override
  State<_SectorAttendanceSection> createState() =>
      _SectorAttendanceSectionState();
}

class _SectorAttendanceSectionState extends State<_SectorAttendanceSection> {
  final Map<int, bool> _pending = {};
  bool   _saving  = false;
  String _searchQ = '';

  List<Map> get _centers =>
      List<Map>.from(widget.duty?['centers'] ?? []);

  List<Map> get _filtered {
    if (_searchQ.isEmpty) return _centers;
    final q = _searchQ.toLowerCase();
    return _centers.where((c) =>
        (c['name']    ?? '').toString().toLowerCase().contains(q) ||
        (c['gp_name'] ?? '').toString().toLowerCase().contains(q) ||
        (c['thana']   ?? '').toString().toLowerCase().contains(q)).toList();
  }

  void _toggle(int dutyId, bool current) =>
      setState(() => _pending[dutyId] = !current);

  bool _getAttended(Map s) {
    final id = s['duty_id'] as int?;
    if (id != null && _pending.containsKey(id)) return _pending[id]!;
    return s['attended'] == 1 || s['attended'] == true;
  }

  Future<void> _saveAll() async {
    if (_pending.isEmpty) return;
    setState(() => _saving = true);
    try {
      final token   = await AuthService.getToken();
      final updates = _pending.entries
          .map((e) => {'dutyId': e.key, 'attended': e.value}).toList();
      await ApiService.post('/staff/attendance/bulk',
          {'updates': updates}, token: token);
      _pending.clear();
      widget.onRefresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('उपस्थिति सेव हो गई ✓'),
              backgroundColor: kSuccess,
              behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('त्रुटि: $e'), backgroundColor: kError,
          behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.duty == null) return const _NoDutyState();
    final centers = _filtered;
    int totalS = 0, presentS = 0;
    for (final c in _centers) {
      for (final s in (c['staff'] as List? ?? [])) {
        totalS++;
        if (_getAttended(s as Map)) presentS++;
      }
    }
    final r = _rs(context);

    return Column(children: [
      Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: kSector.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kSector.withOpacity(0.3)),
        ),
        child: const Row(children: [
          Icon(Icons.fact_check_outlined, color: kSector, size: 16),
          SizedBox(width: 8),
          Expanded(child: Text(
            'नीचे केवल आपके सेक्टर के बूथों का स्टाफ दिखाई दे रहा है। '
            'उपस्थिति अंकित करें और "सेव करें" दबाएं।',
            style: TextStyle(color: kSector, fontSize: 11, height: 1.4))),
        ]),
      ),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [kDark, Color(0xFF5A3E08)]),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          Row(children: [
            const Icon(Icons.how_to_vote_outlined, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            const Expanded(child: Text('बूथ उपस्थिति', style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800))),
            if (_pending.isNotEmpty)
              GestureDetector(
                onTap: _saving ? null : _saveAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                      color: kSuccess, borderRadius: BorderRadius.circular(10)),
                  child: _saving
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text('${_pending.length} सेव करें',
                          style: const TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _AttStat('कुल स्टाफ', '$totalS', kPrimary)),
            const SizedBox(width: 8),
            Expanded(child: _AttStat('उपस्थित', '$presentS', kSuccess)),
            const SizedBox(width: 8),
            Expanded(child: _AttStat('अनुपस्थित',
                '${totalS - presentS}', kError)),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      TextField(
        onChanged: (q) => setState(() => _searchQ = q.trim()),
        style: const TextStyle(color: kDark, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'बूथ/थाना/GP खोजें...',
          hintStyle: const TextStyle(color: kSubtle, fontSize: 12),
          prefixIcon: const Icon(Icons.search, color: kSubtle, size: 18),
          filled: true, fillColor: Colors.white, isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: kBorder)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: kBorder)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: kSector, width: 2)),
        ),
      ),
      const SizedBox(height: 12),
      if (centers.isEmpty)
        Center(child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Text(
            _searchQ.isNotEmpty
                ? '"$_searchQ" नहीं मिला'
                : 'इस सेक्टर में कोई बूथ नहीं है',
            style: const TextStyle(color: kSubtle, fontSize: 13)),
        ))
      else
        ...centers.map((center) => _BoothAttCard(
            center: center,
            getAttended: _getAttended,
            onToggle: _toggle)),
    ]);
  }
}

class _AttStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _AttStat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10)),
    child: Column(children: [
      Text(value, style: TextStyle(
          color: color, fontSize: 20, fontWeight: FontWeight.w900)),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
    ]));
}

class _BoothAttCard extends StatelessWidget {
  final Map center;
  final bool Function(Map) getAttended;
  final void Function(int, bool) onToggle;
  const _BoothAttCard({
    required this.center, required this.getAttended,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final staff   = (center['staff'] as List? ?? []);
    final type    = '${center['center_type'] ?? 'C'}';
    final tc      = _typeColor(type);
    final present = staff.where((s) => getAttended(s as Map)).length;
    final r       = _rs(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorder.withOpacity(0.4)),
          boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.04),
              blurRadius: 8, offset: const Offset(0, 3))]),
      child: Column(children: [
        Container(
          padding: EdgeInsets.fromLTRB(r.s(12, 14), 12, r.s(12, 14), 12),
          decoration: BoxDecoration(color: tc.withOpacity(0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(bottom: BorderSide(color: tc.withOpacity(0.2)))),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: tc, borderRadius: BorderRadius.circular(6)),
                child: Text(type, style: const TextStyle(
                    color: Colors.white, fontSize: 11,
                    fontWeight: FontWeight.w900))),
            const SizedBox(width: 10),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${center['name'] ?? '—'}', style: const TextStyle(
                  color: kDark, fontSize: 13, fontWeight: FontWeight.w700),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${center['gp_name'] ?? ''}  •  ${center['thana'] ?? ''}',
                  style: const TextStyle(color: kSubtle, fontSize: 10)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: present == staff.length && staff.isNotEmpty
                    ? kSuccess.withOpacity(0.1) : kSubtle.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: present == staff.length && staff.isNotEmpty
                        ? kSuccess.withOpacity(0.3)
                        : kBorder.withOpacity(0.3)),
              ),
              child: Text('$present/${staff.length}',
                  style: TextStyle(
                      color: present == staff.length && staff.isNotEmpty
                          ? kSuccess : kSubtle,
                      fontSize: 11, fontWeight: FontWeight.w800))),
          ]),
        ),
        if (staff.isEmpty)
          const Padding(padding: EdgeInsets.all(16),
              child: Text('कोई स्टाफ असाइन नहीं',
                  style: TextStyle(color: kSubtle, fontSize: 12)))
        else
          ...staff.asMap().entries.map((e) {
            final i   = e.key;
            final s   = e.value as Map;
            final id  = s['duty_id'] as int?;
            final att = getAttended(s);
            final armed = s['is_armed'] == 1 || s['is_armed'] == true;
            return Container(
              padding: EdgeInsets.fromLTRB(r.s(12, 14), 10, r.s(12, 14), 10),
              decoration: BoxDecoration(border: i < staff.length - 1
                  ? Border(bottom: BorderSide(color: kBorder.withOpacity(0.3)))
                  : null),
              child: Row(children: [
                Container(width: 36, height: 36,
                    decoration: BoxDecoration(
                        color: (armed ? kArmed : kUnarmed).withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: (armed ? kArmed : kUnarmed).withOpacity(0.3))),
                    child: Icon(armed ? Icons.security : Icons.person_outline,
                        size: 16, color: armed ? kArmed : kUnarmed)),
                const SizedBox(width: 10),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${s['name'] ?? '—'}', style: const TextStyle(
                      color: kDark, fontSize: 13, fontWeight: FontWeight.w700)),
                  Row(children: [
                    Text(rh(s['user_rank']),
                        style: const TextStyle(color: kSubtle, fontSize: 10)),
                    const Text('  •  ',
                        style: TextStyle(color: kSubtle, fontSize: 10)),
                    Text('${s['pno'] ?? ''}',
                        style: const TextStyle(color: kSubtle, fontSize: 10)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                          color: (armed ? kArmed : kUnarmed).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(armed ? 'सशस्त्र' : 'निःशस्त्र',
                          style: TextStyle(
                              color: armed ? kArmed : kUnarmed,
                              fontSize: 8, fontWeight: FontWeight.w700))),
                  ]),
                ])),
                GestureDetector(
                  onTap: id != null ? () => onToggle(id, att) : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 56, height: 30,
                    decoration: BoxDecoration(
                      color: att ? kSuccess : kError.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                          color: att ? kSuccess : kError.withOpacity(0.4),
                          width: 1.5),
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(att ? Icons.check : Icons.close,
                          size: 14, color: att ? Colors.white : kError),
                      const SizedBox(width: 2),
                      Text(att ? 'हाँ' : 'नहीं', style: TextStyle(
                          color: att ? Colors.white : kError,
                          fontSize: 10, fontWeight: FontWeight.w700)),
                    ]),
                  )),
              ]),
            );
          }),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  ZONE — OVERVIEW / INFO / SECTORS
// ══════════════════════════════════════════════════════════════════════════════
class _ZoneOverviewSection extends StatelessWidget {
  final Map? duty, user;
  final _ElectionConfig electionConfig;
  const _ZoneOverviewSection({
    required this.duty, required this.user,
    required this.electionConfig,
  });

  @override
  Widget build(BuildContext context) {
    if (duty == null) return const _NoDutyState();
    final r = _rs(context);
    return Column(children: [
      _ElectionBanner(electionConfig: electionConfig),
      Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(color: kZone.withOpacity(0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kZone.withOpacity(0.3))),
        child: Row(children: [
          Container(width: 40, height: 40,
              decoration: BoxDecoration(
                  color: kZone, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.map_outlined, color: Colors.white, size: 20)),
          const SizedBox(width: 12),
          const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('जोनल अधिकारी', style: TextStyle(
                color: kZone, fontSize: 14, fontWeight: FontWeight.w800)),
            Text('जोन के सेक्टरों का निरीक्षण करें',
                style: TextStyle(color: kSubtle, fontSize: 11)),
          ])),
        ]),
      ),
      _HeroCard(user: user, duty: duty, noDuty: false, subtitle: 'जोनल अधिकारी'),
      const SizedBox(height: 16),
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12, mainAxisSpacing: 12,
        childAspectRatio: r.compact ? 1.3 : 1.45,
        children: [
          _StatCard(icon: Icons.grid_view_outlined, label: 'कुल सेक्टर',
              value: '${duty!['totalSectors'] ?? 0}', color: kPrimary),
          _StatCard(icon: Icons.how_to_vote_outlined, label: 'कुल बूथ',
              value: '${duty!['totalBooths'] ?? 0}', color: kInfo),
          _StatCard(icon: Icons.groups_outlined, label: 'असाइन स्टाफ',
              value: '${duty!['totalAssigned'] ?? 0}', color: kSuccess),
          _StatCard(icon: Icons.public_outlined, label: 'सुपर जोन',
              value: v(duty!['superZoneName']), color: kAccent),
        ],
      ),
      const SizedBox(height: 14),
      _SectionCard(icon: Icons.map_outlined, title: 'जोन विवरण',
        child: Column(children: [
          _InfoTile(Icons.map_outlined,       'जोन',       duty!['zoneName']),
          _InfoTile(Icons.home_work_outlined, 'मुख्यालय', duty!['hqAddress']),
          _InfoTile(Icons.public_outlined,    'सुपर जोन', duty!['superZoneName']),
        ]),
      ),
    ]);
  }
}

class _ZoneInfoSection extends StatelessWidget {
  final Map? duty;
  const _ZoneInfoSection({required this.duty});
  @override
  Widget build(BuildContext context) {
    if (duty == null) return const _NoDutyState();
    final co     = (duty!['coOfficers']    as List? ?? []);
    final super_ = (duty!['superOfficers'] as List? ?? []);
    return Column(children: [
      _SectionCard(icon: Icons.map_outlined, title: 'जोन विस्तार जानकारी',
        child: Column(children: [
          _InfoTile(Icons.map_outlined,        'जोन',          duty!['zoneName']),
          _InfoTile(Icons.home_work_outlined,  'HQ',           duty!['hqAddress']),
          _InfoTile(Icons.public_outlined,     'सुपर जोन',    duty!['superZoneName']),
          _InfoTile(Icons.grid_view_outlined,  'कुल सेक्टर',  '${duty!['totalSectors'] ?? 0}'),
          _InfoTile(Icons.how_to_vote_outlined,'कुल बूथ',     '${duty!['totalBooths'] ?? 0}'),
          _InfoTile(Icons.groups_outlined,     'असाइन स्टाफ','${duty!['totalAssigned'] ?? 0}'),
        ]),
      ),
      if (co.isNotEmpty) ...[const SizedBox(height: 14),
          _OfficerCard(label: 'जोनल अधिकारी', officers: co)],
      if (super_.isNotEmpty) ...[const SizedBox(height: 12),
          _OfficerCard(label: 'क्षेत्र अधिकारी (वरिष्ठ)', officers: super_)],
    ]);
  }
}

class _ZoneSectorsSection extends StatelessWidget {
  final Map? duty;
  const _ZoneSectorsSection({required this.duty});
  @override
  Widget build(BuildContext context) {
    if (duty == null) return const _NoDutyState();
    final sectors = (duty!['sectors'] as List? ?? []);
    return _SectionCard(
      icon: Icons.grid_view_outlined,
      title: 'सेक्टर (${sectors.length})',
      child: sectors.isEmpty
          ? const Padding(padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('कोई सेक्टर नहीं',
                  style: TextStyle(color: kSubtle))))
          : Column(children: sectors.asMap().entries.map((e) {
              final i    = e.key;
              final s    = e.value as Map;
              final offs = (s['officers'] as List? ?? []);
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(border: i < sectors.length - 1
                    ? Border(bottom: BorderSide(color: kBorder.withOpacity(0.4)))
                    : null),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: kPrimary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.grid_view_outlined,
                            color: kPrimary, size: 16)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${s['name'] ?? '—'}', style: const TextStyle(
                          color: kDark, fontSize: 13, fontWeight: FontWeight.w700)),
                      Text('${s['gp_count'] ?? 0} GP  •  '
                          '${s['center_count'] ?? 0} बूथ  •  '
                          '${s['staff_assigned'] ?? 0} स्टाफ',
                          style: const TextStyle(color: kSubtle, fontSize: 11)),
                    ])),
                  ]),
                  if (offs.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 4,
                        children: offs.map((o) => _OfficerChip(o as Map)).toList()),
                  ],
                ]),
              );
            }).toList()),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  KSHETRA — OVERVIEW / INFO / ZONES
// ══════════════════════════════════════════════════════════════════════════════
class _KshetraOverviewSection extends StatelessWidget {
  final Map? duty, user;
  final _ElectionConfig electionConfig;
  const _KshetraOverviewSection({
    required this.duty, required this.user,
    required this.electionConfig,
  });

  @override
  Widget build(BuildContext context) {
    if (duty == null) return const _NoDutyState();
    final r = _rs(context);
    return Column(children: [
      _ElectionBanner(electionConfig: electionConfig),
      Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(color: kKshetra.withOpacity(0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kKshetra.withOpacity(0.3))),
        child: Row(children: [
          Container(width: 40, height: 40,
              decoration: BoxDecoration(
                  color: kKshetra, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.layers_outlined, color: Colors.white, size: 20)),
          const SizedBox(width: 12),
          const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('क्षेत्र अधिकारी', style: TextStyle(
                color: kKshetra, fontSize: 14, fontWeight: FontWeight.w800)),
            Text('सुपर जोन का निरीक्षण करें',
                style: TextStyle(color: kSubtle, fontSize: 11)),
          ])),
        ]),
      ),
      _HeroCard(user: user, duty: duty, noDuty: false, subtitle: 'क्षेत्र अधिकारी'),
      const SizedBox(height: 16),
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12, mainAxisSpacing: 12,
        childAspectRatio: r.compact ? 1.3 : 1.45,
        children: [
          _StatCard(icon: Icons.map_outlined,         label: 'कुल जोन',
              value: '${duty!['totalZones']    ?? 0}', color: kPrimary),
          _StatCard(icon: Icons.grid_view_outlined,   label: 'कुल सेक्टर',
              value: '${duty!['totalSectors']  ?? 0}', color: kInfo),
          _StatCard(icon: Icons.how_to_vote_outlined, label: 'कुल बूथ',
              value: '${duty!['totalBooths']   ?? 0}', color: kSuccess),
          _StatCard(icon: Icons.groups_outlined,      label: 'असाइन स्टाफ',
              value: '${duty!['totalAssigned'] ?? 0}', color: kAccent),
        ],
      ),
      const SizedBox(height: 14),
      _SectionCard(icon: Icons.layers_outlined, title: 'क्षेत्र विवरण',
        child: Column(children: [
          _InfoTile(Icons.layers_outlined,        'सुपर जोन', duty!['superZoneName']),
          _InfoTile(Icons.location_city_outlined, 'जिला',     duty!['district']),
          _InfoTile(Icons.business_outlined,      'ब्लॉक',    duty!['block']),
        ]),
      ),
    ]);
  }
}

class _KshetraInfoSection extends StatelessWidget {
  final Map? duty;
  const _KshetraInfoSection({required this.duty});
  @override
  Widget build(BuildContext context) {
    if (duty == null) return const _NoDutyState();
    final co = (duty!['coOfficers'] as List? ?? []);
    return Column(children: [
      _SectionCard(icon: Icons.layers_outlined, title: 'क्षेत्र जानकारी',
        child: Column(children: [
          _InfoTile(Icons.layers_outlined,        'सुपर जोन',   duty!['superZoneName']),
          _InfoTile(Icons.location_city_outlined, 'जिला',       duty!['district']),
          _InfoTile(Icons.business_outlined,      'ब्लॉक',      duty!['block']),
          _InfoTile(Icons.map_outlined,           'कुल जोन',    '${duty!['totalZones'] ?? 0}'),
          _InfoTile(Icons.grid_view_outlined,     'कुल सेक्टर', '${duty!['totalSectors'] ?? 0}'),
          _InfoTile(Icons.how_to_vote_outlined,   'कुल बूथ',    '${duty!['totalBooths'] ?? 0}'),
          _InfoTile(Icons.groups_outlined,        'असाइन स्टाफ','${duty!['totalAssigned'] ?? 0}'),
        ]),
      ),
      if (co.isNotEmpty) ...[const SizedBox(height: 14),
          _OfficerCard(label: 'सह-क्षेत्र अधिकारी', officers: co)],
    ]);
  }
}

class _KshetraZonesSection extends StatelessWidget {
  final Map? duty;
  const _KshetraZonesSection({required this.duty});
  @override
  Widget build(BuildContext context) {
    if (duty == null) return const _NoDutyState();
    final zones = (duty!['zones'] as List? ?? []);
    return _SectionCard(
      icon: Icons.map_outlined,
      title: 'जोन (${zones.length})',
      child: zones.isEmpty
          ? const Padding(padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('कोई जोन नहीं',
                  style: TextStyle(color: kSubtle))))
          : Column(children: zones.asMap().entries.map((e) {
              final i    = e.key;
              final z    = e.value as Map;
              final offs = (z['officers'] as List? ?? []);
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(border: i < zones.length - 1
                    ? Border(bottom: BorderSide(color: kBorder.withOpacity(0.4)))
                    : null),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: kInfo.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.map_outlined, color: kInfo, size: 16)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${z['name'] ?? '—'}', style: const TextStyle(
                          color: kDark, fontSize: 13, fontWeight: FontWeight.w700)),
                      Text('${z['sector_count'] ?? 0} सेक्टर  •  '
                          '${z['center_count'] ?? 0} बूथ  •  '
                          '${z['staff_assigned'] ?? 0} स्टाफ',
                          style: const TextStyle(color: kSubtle, fontSize: 11)),
                      if ((z['hq_address'] ?? '').toString().isNotEmpty)
                        Text('HQ: ${z['hq_address']}',
                            style: const TextStyle(color: kSubtle, fontSize: 10)),
                    ])),
                  ]),
                  if (offs.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 4,
                        children: offs.map((o) => _OfficerChip(o as Map)).toList()),
                  ],
                ]),
              );
            }).toList()),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  MANAK SECTION — FULL ADMIN-MATCHING TABLE VIEW
//  ✅ Completely rewritten to match admin ManakBoothReportPage exactly:
//     sensitivity blocks with summary chips + scrollable 17-column table
// ══════════════════════════════════════════════════════════════════════════════
class _ManakSection extends StatelessWidget {
  final List rules;
  final _ElectionConfig electionConfig;
  const _ManakSection({required this.rules, required this.electionConfig});

  @override
  Widget build(BuildContext context) {
    final parsed = _ManakParser.parse(rules);

    // Group by sensitivity
    final Map<String, List<_ManakRule>> grouped = {};
    for (final r in parsed) {
      grouped.putIfAbsent(r.sensitivity, () => []).add(r);
    }
    // Sort each group by boothCount
    for (final list in grouped.values) {
      list.sort((a, b) => a.boothCount.compareTo(b.boothCount));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Header card ───────────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [kDark, Color(0xFF5A3E08)]),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 40, height: 40,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.rule_folder_outlined,
                    color: Colors.white, size: 20)),
            const SizedBox(width: 12),
            const Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('बूथ स्टाफ मानक', style: TextStyle(
                  color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.w800)),
              Text('संवेदनशीलता एवं बूथ संख्या के अनुसार पुलिस बल',
                  style: TextStyle(color: Colors.white60, fontSize: 11)),
            ])),
          ]),
          if (!electionConfig.isEmpty) ...[
            const SizedBox(height: 10),
            Container(height: 1, color: Colors.white.withOpacity(0.15)),
            const SizedBox(height: 8),
            Text(
              '${electionConfig.electionName}'
              '${electionConfig.phase.isNotEmpty ? " — चरण ${electionConfig.phase}" : ""}',
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ]),
      ),
      const SizedBox(height: 14),

      if (rules.isEmpty || parsed.isEmpty)
        _ManakEmpty()
      else
        ...kSensitivities
            .where((s) => grouped.containsKey(s['key']))
            .map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ManakSensBlock(
                    sensKey:  s['key'] as String,
                    sensHi:   s['hi']  as String,
                    color:    s['color'] as Color,
                    rules:    grouped[s['key']]!,
                  ),
                )),
    ]);
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _ManakEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder.withOpacity(0.4))),
    child: const Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.rule_outlined, size: 40, color: kSubtle),
      SizedBox(height: 10),
      Text('कोई मानक सेट नहीं है',
          style: TextStyle(color: kSubtle, fontSize: 13,
              fontWeight: FontWeight.w600)),
      SizedBox(height: 4),
      Text('व्यवस्थापक से मानक सेट करवाएं',
          style: TextStyle(color: kSubtle, fontSize: 11)),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  MANAK SENSITIVITY BLOCK — matches admin _SensBlock exactly
//  Collapsible header + summary chips + full scrollable table
// ══════════════════════════════════════════════════════════════════════════════
class _ManakSensBlock extends StatefulWidget {
  final String sensKey, sensHi;
  final Color color;
  final List<_ManakRule> rules;
  const _ManakSensBlock({
    required this.sensKey, required this.sensHi,
    required this.color, required this.rules,
  });
  @override
  State<_ManakSensBlock> createState() => _ManakSensBlockState();
}

class _ManakSensBlockState extends State<_ManakSensBlock> {
  bool _expanded = true; // open by default so staff can see rules immediately

  String _fp(double v) =>
      v == 0 ? '0' : (v % 1 == 0 ? '${v.toInt()}' : v.toStringAsFixed(1));

  // ── Pre-compute totals (matching admin logic) ────────────────────────────
  _ManakTotals get _totals {
    int tSI = 0, tHC = 0, tC = 0, tAx = 0;
    double tPAC = 0;
    for (final r in widget.rules) {
      tSI += r.totalSI;
      tHC += r.totalHC;
      tC  += r.totalConst;
      tAx += r.totalAux;
      tPAC += r.pac;
    }
    return _ManakTotals(si: tSI, hc: tHC, c: tC, ax: tAx, pac: tPAC,
        total: tSI + tHC + tC + tAx);
  }

  @override
  Widget build(BuildContext context) {
    final t     = _totals;
    final color = widget.color;

    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [BoxShadow(
              color: color.withOpacity(0.07),
              blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(children: [
        // ── Header ─────────────────────────────────────────────────────────
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: kSurface.withOpacity(0.6),
              borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(14),
                  bottom: _expanded ? Radius.zero : const Radius.circular(14)),
              border: Border(bottom: _expanded
                  ? BorderSide(color: kBorder.withOpacity(0.3))
                  : BorderSide.none),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(8)),
                child: Text(widget.sensKey,
                    style: const TextStyle(color: Colors.white,
                        fontSize: 13, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${widget.sensHi} श्रेणी',
                    style: const TextStyle(color: kDark, fontSize: 13,
                        fontWeight: FontWeight.w800)),
                Row(children: [
                  Text('${widget.rules.length}/15 मानक  •  ',
                      style: const TextStyle(color: kSubtle, fontSize: 10)),
                  Text('कुल बल: ${t.total}',
                      style: TextStyle(color: color,
                          fontSize: 10, fontWeight: FontWeight.w700)),
                ]),
              ])),
              // status pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: kSuccess.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: kSuccess.withOpacity(0.35)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 11, color: kSuccess),
                  const SizedBox(width: 4),
                  const Text('सेट', style: TextStyle(
                      color: kSuccess, fontSize: 10, fontWeight: FontWeight.w700)),
                ]),
              ),
              const SizedBox(width: 6),
              Icon(_expanded
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
                  color: color, size: 20),
            ]),
          ),
        ),

        if (_expanded) ...[
          // ── Summary chips (matches admin) ─────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: color.withOpacity(0.04),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _SumChip('SI',     '${t.si}',  color),
                _SumChip('HC',     '${t.hc}',  color),
                _SumChip('Const.', '${t.c}',   color),
                _SumChip('Aux.',   '${t.ax}',  const Color(0xFFE65100)),
                if (t.pac > 0)
                  _SumChip('PAC',  _fp(t.pac), const Color(0xFF00695C)),
                _SumChip('कुल बल', '${t.total}', kSuccess),
              ]),
            ),
          ),

          // ── Full scrollable table ─────────────────────────────────────────
          _ManakTable(rules: widget.rules, color: widget.color),
        ],
      ]),
    );
  }
}

class _ManakTotals {
  final int si, hc, c, ax, total;
  final double pac;
  const _ManakTotals({
    required this.si, required this.hc, required this.c,
    required this.ax, required this.pac, required this.total,
  });
}

class _SumChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _SumChip(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(right: 6),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label: ', style: TextStyle(
          color: color.withOpacity(0.8), fontSize: 10,
          fontWeight: FontWeight.w600)),
      Text(value, style: TextStyle(
          color: color, fontSize: 11, fontWeight: FontWeight.w900)),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  MANAK TABLE — mirrors admin _ReportTable exactly
//  17 columns: क्र.स | label | (no center count — staff don't have it) |
//  Scale-5: SI | HC | Const | Aux | PAC |
//  Per-rule breakdown: SI सश | HC | HC सश | HC निः |
//                      Const | Const सश | Const निः | Aux | PAC
//
//  NOTE: Staff don't have center-count data (only admin does).
//        So the "पोलिंग सेन्टर संख्या" column is omitted.
//        All other columns match admin exactly.
// ══════════════════════════════════════════════════════════════════════════════
class _ManakTable extends StatelessWidget {
  final List<_ManakRule> rules;
  final Color color;
  const _ManakTable({required this.rules, required this.color});

  String _fp(double v) =>
      v == 0 ? '0' : (v % 1 == 0 ? '${v.toInt()}' : v.toStringAsFixed(1));

  // Build a lookup: boothCount → rule
  Map<int, _ManakRule> get _byCount =>
      {for (final r in rules) r.boothCount: r};

  @override
  Widget build(BuildContext context) {
    final byCount = _byCount;

    // Compute grand totals
    int mSI_A=0, mSI_U=0, mHC_A=0, mHC_U=0;
    int mC_A=0,  mC_U=0,  mAx_A=0, mAx_U=0;
    double mPAC = 0;
    for (final r in rules) {
      mSI_A += r.siArmed;   mSI_U += r.siUnarmed;
      mHC_A += r.hcArmed;   mHC_U += r.hcUnarmed;
      mC_A  += r.constArmed; mC_U += r.constUnarmed;
      mAx_A += r.auxArmed;  mAx_U += r.auxUnarmed;
      mPAC  += r.pac;
    }

    // Column widths: 16 cols (no center-count col)
    // 0=क्र.स | 1=label | 2=SI | 3=HC | 4=Const | 5=Aux | 6=PAC |
    // 7=SI सश | 8=HC | 9=HC सश | 10=HC निः |
    // 11=Const | 12=Const सश | 13=Const निः | 14=Aux | 15=PAC
    const Map<int, TableColumnWidth> colWidths = {
      0: FixedColumnWidth(30),   // क्र.स
      1: FixedColumnWidth(92),   // label
      // Scale
      2: FixedColumnWidth(30),
      3: FixedColumnWidth(30),
      4: FixedColumnWidth(34),
      5: FixedColumnWidth(36),
      6: FixedColumnWidth(34),
      // Breakdown
      7:  FixedColumnWidth(32),
      8:  FixedColumnWidth(34),
      9:  FixedColumnWidth(34),
      10: FixedColumnWidth(34),
      11: FixedColumnWidth(34),
      12: FixedColumnWidth(36),
      13: FixedColumnWidth(36),
      14: FixedColumnWidth(38),
      15: FixedColumnWidth(34),
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 700),
        child: Table(
          columnWidths: colWidths,
          border: TableBorder.all(
              color: kBorder.withOpacity(0.25), width: 0.5),
          children: [
            // ── Group header row ──────────────────────────────────────────
            TableRow(
              decoration: BoxDecoration(color: color.withOpacity(0.10)),
              children: [
                _TH(''),
                _TH('', alignLeft: true),
                // Scale group
                _TH2('Scale (प्रति बूथ मानक)', color: color, bold: true),
                _TH(''), _TH(''), _TH(''), _TH(''),
                // Breakdown group
                _TH2('पुलिस बल विवरण (पद एवं श्रेणी वार)',
                    color: color, bold: true),
                _TH(''), _TH(''), _TH(''),
                _TH(''), _TH(''), _TH(''), _TH(''), _TH(''),
              ],
            ),

            // ── Column headers ─────────────────────────────────────────────
            TableRow(
              decoration: const BoxDecoration(color: kSurface),
              children: [
                _TH('क्र.\nस.'),
                _TH('मतदान केन्द्र\nका प्रकार', alignLeft: true),
                // Scale
                _TH('SI'),
                _TH('HC'),
                _TH('Const.'),
                _TH('Aux.\nForce'),
                _TH('PAC\n(sec.)'),
                // Breakdown
                _TH('SI\nसश°'),
                _TH('HC'),
                _TH('HC\nसश°'),
                _TH('HC\nनिः°'),
                _TH('Const.'),
                _TH('Const.\nसश°'),
                _TH('Const.\nनिः°'),
                _TH('Aux.\nForce'),
                _TH('PAC\n(sec.)'),
              ],
            ),

            // ── Data rows (1..15) ──────────────────────────────────────────
            ...List.generate(15, (idx) {
              final i  = idx + 1;
              final r  = byCount[i];
              final bg = idx % 2 == 1
                  ? kBg.withOpacity(0.5)
                  : Colors.white;
              final label = i < 15
                  ? '${kBoothTiers[i - 1]['label']}'
                  : '15+ बूथ';
              final hasRule = r != null && r.hasAny;

              return TableRow(
                decoration: BoxDecoration(color: bg),
                children: [
                  _TD('$i', center: true),
                  _TD(label, alignLeft: true),
                  // Scale
                  _TDn(r?.totalSI    ?? 0, hasData: hasRule),
                  _TDn(r?.totalHC    ?? 0, hasData: hasRule),
                  _TDn(r?.totalConst ?? 0, hasData: hasRule),
                  _TDn(r?.totalAux   ?? 0, hasData: hasRule),
                  _TDs(_fp(r?.pac ?? 0),   hasData: hasRule && (r?.pac ?? 0) > 0),
                  // Breakdown
                  _TDn(r?.siArmed      ?? 0, hasData: hasRule),
                  _TDn(r?.totalHC      ?? 0, hasData: hasRule),
                  _TDn(r?.hcArmed      ?? 0, hasData: hasRule),
                  _TDn(r?.hcUnarmed    ?? 0, hasData: hasRule),
                  _TDn(r?.totalConst   ?? 0, hasData: hasRule),
                  _TDn(r?.constArmed   ?? 0, hasData: hasRule),
                  _TDn(r?.constUnarmed ?? 0, hasData: hasRule),
                  _TDn(r?.totalAux     ?? 0, hasData: hasRule),
                  _TDs(_fp(r?.pac ?? 0),    hasData: hasRule && (r?.pac ?? 0) > 0),
                ],
              );
            }),

            // ── Total row ──────────────────────────────────────────────────
            TableRow(
              decoration: BoxDecoration(color: color.withOpacity(0.09)),
              children: [
                _TD('', center: true),
                _TD('योग', alignLeft: true, bold: true),
                // Scale totals (sum of manak rules)
                _TD('${mSI_A+mSI_U}', center: true, bold: true),
                _TD('${mHC_A+mHC_U}', center: true, bold: true),
                _TD('${mC_A+mC_U}',   center: true, bold: true),
                _TD('${mAx_A+mAx_U}', center: true, bold: true),
                _TD(_fp(mPAC),         center: true, bold: true),
                // Breakdown totals
                _TD('$mSI_A',          center: true, bold: true),
                _TD('${mHC_A+mHC_U}', center: true, bold: true),
                _TD('$mHC_A',          center: true, bold: true),
                _TD('$mHC_U',          center: true, bold: true),
                _TD('${mC_A+mC_U}',   center: true, bold: true),
                _TD('$mC_A',           center: true, bold: true),
                _TD('$mC_U',           center: true, bold: true),
                _TD('${mAx_A+mAx_U}', center: true, bold: true),
                _TD(_fp(mPAC),         center: true, bold: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Table cell helpers (matching admin style) ─────────────────────────────────

Widget _TH(String text, {bool alignLeft = false}) => TableCell(
  verticalAlignment: TableCellVerticalAlignment.middle,
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
    child: Text(text,
        textAlign: alignLeft ? TextAlign.left : TextAlign.center,
        style: const TextStyle(
            fontSize: 9.5, fontWeight: FontWeight.w700,
            color: kDark, height: 1.2)),
  ),
);

Widget _TH2(String text, {Color? color, bool bold = false}) => TableCell(
  verticalAlignment: TableCellVerticalAlignment.middle,
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
    child: Text(text,
        textAlign: TextAlign.center,
        maxLines: 2, overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 8,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: color ?? kDark, height: 1.2)),
  ),
);

Widget _TD(String text,
    {bool center = false, bool bold = false, bool alignLeft = false}) =>
    TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
        child: Text(text,
            textAlign: center
                ? TextAlign.center
                : (alignLeft ? TextAlign.left : TextAlign.center),
            style: TextStyle(
                fontSize: 11,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                color: bold ? kDark : kDark.withOpacity(0.8),
                height: 1.2)),
      ),
    );

Widget _TDn(int v, {bool hasData = true}) => TableCell(
  verticalAlignment: TableCellVerticalAlignment.middle,
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
    child: Text('$v',
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 11,
            fontWeight: v > 0 ? FontWeight.w700 : FontWeight.w400,
            color: v > 0
                ? kDark
                : (hasData ? kSubtle.withOpacity(0.5) : kSubtle.withOpacity(0.25)),
            height: 1.2)),
  ),
);

Widget _TDs(String text, {bool hasData = true}) => TableCell(
  verticalAlignment: TableCellVerticalAlignment.middle,
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
    child: Text(text,
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 11,
            fontWeight: hasData ? FontWeight.w700 : FontWeight.w400,
            color: hasData ? kDark : kSubtle.withOpacity(0.3),
            height: 1.2)),
  ),
);

// ══════════════════════════════════════════════════════════════════════════════
//  SHARED WIDGETS (unchanged from original)
// ══════════════════════════════════════════════════════════════════════════════

class _ProfileCard extends StatelessWidget {
  final Map? user;
  const _ProfileCard({required this.user});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(16),
      border: Border.all(color: kBorder.withOpacity(0.5)),
      boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.05),
          blurRadius: 10, offset: const Offset(0, 3))],
    ),
    child: Row(children: [
      Container(width: 50, height: 50,
        decoration: BoxDecoration(color: kSurface, shape: BoxShape.circle,
            border: Border.all(color: kBorder)),
        child: const Icon(Icons.person_outline_rounded,
            color: kPrimary, size: 24)),
      const SizedBox(width: 14),
      Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(user?['name'] ?? '—', style: const TextStyle(
            color: kDark, fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text('PNO: ${user?['pno'] ?? '—'}  •  '
            '${rh(user?['rank'] ?? user?['user_rank'])}',
            style: const TextStyle(color: kSubtle, fontSize: 11)),
        Text('${user?['thana'] ?? ''}'
            '${user?['district'] != null ? '  •  ${user!['district']}' : ''}',
            style: const TextStyle(color: kSubtle, fontSize: 11)),
      ])),
    ]),
  );
}

class _HeroCard extends StatelessWidget {
  final Map? user, duty;
  final bool noDuty;
  final String? subtitle;
  const _HeroCard({
    required this.user, required this.duty,
    required this.noDuty, this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
          colors: [kDark, Color(0xFF6B4E0A)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: kDark.withOpacity(0.35),
          blurRadius: 16, offset: const Offset(0, 6))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 48, height: 48,
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(color: kBorder.withOpacity(0.4))),
            child: const Icon(Icons.person_outline_rounded,
                color: Colors.white, size: 24)),
        const SizedBox(width: 14),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (subtitle != null)
            Text(subtitle!, style: const TextStyle(
                color: Colors.white60, fontSize: 10,
                letterSpacing: 1.0, fontWeight: FontWeight.w600)),
          Text(user?['name'] ?? '—', style: const TextStyle(
              color: Colors.white, fontSize: 18,
              fontWeight: FontWeight.w800)),
          Text('PNO: ${user?['pno'] ?? '—'}',
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ])),
      ]),
      const SizedBox(height: 14),
      Container(height: 1, color: Colors.white.withOpacity(0.15)),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 8, children: [
        if ((user?['thana'] ?? '').toString().isNotEmpty)
          _HeroBadge(Icons.local_police_outlined, user!['thana'].toString()),
        if ((user?['district'] ?? '').toString().isNotEmpty)
          _HeroBadge(Icons.location_city_outlined, user!['district'].toString()),
        _HeroBadge(Icons.military_tech_outlined,
            rh(user?['rank'] ?? user?['user_rank'])),
      ]),
      if (!noDuty && duty != null &&
          (duty!['centerName'] ?? duty!['sectorName'] ??
              duty!['zoneName'] ?? duty!['superZoneName']) != null) ...[
        const SizedBox(height: 12),
        Container(height: 1, color: Colors.white.withOpacity(0.15)),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.how_to_vote_outlined, size: 14, color: Colors.white54),
          const SizedBox(width: 6),
          Expanded(child: Text(
            'ड्यूटी: ${duty!['centerName'] ?? duty!['sectorName'] ?? duty!['zoneName'] ?? duty!['superZoneName'] ?? '—'}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            overflow: TextOverflow.ellipsis)),
        ]),
      ],
    ]),
  );
}

class _HeroBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _HeroBadge(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: Colors.white60),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
    ]),
  );
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  const _SectionCard({required this.icon, required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder.withOpacity(0.5)),
        boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.04),
            blurRadius: 10, offset: const Offset(0, 3))]),
    child: Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            color: kSurface.withOpacity(0.6),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            border: Border(bottom: BorderSide(color: kBorder.withOpacity(0.4)))),
        child: Row(children: [
          Container(width: 28, height: 28,
              decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: kPrimary, size: 14)),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(
              color: kDark, fontSize: 14, fontWeight: FontWeight.w800))),
        ]),
      ),
      Padding(padding: const EdgeInsets.all(16), child: child),
    ]),
  );
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _StatCard({
    required this.icon, required this.label,
    required this.value, required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder.withOpacity(0.5)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.07),
            blurRadius: 8, offset: const Offset(0, 3))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 32, height: 32,
          decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 16, color: color)),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(color: kSubtle, fontSize: 10,
          fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(color: kDark, fontSize: 13,
          fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
    ]),
  );
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final dynamic value;
  const _InfoTile(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final val = (value == null || value.toString().trim().isEmpty)
        ? null : value.toString();
    if (val == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 30, height: 30,
            decoration: BoxDecoration(
                color: kSurface, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 13, color: kPrimary)),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: kSubtle, fontSize: 10,
              fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(val, style: const TextStyle(color: kDark, fontSize: 13,
              fontWeight: FontWeight.w600)),
        ])),
      ]),
    );
  }
}

class _OfficerCard extends StatelessWidget {
  final String label;
  final List officers;
  const _OfficerCard({required this.label, required this.officers});

  @override
  Widget build(BuildContext context) => _SectionCard(
    icon: Icons.verified_user_outlined, title: label,
    child: Column(children: officers.asMap().entries.map((e) {
      final i = e.key;
      final o = e.value is Map ? e.value as Map : {};
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: i < officers.length - 1
            ? Border(bottom: BorderSide(color: kBorder.withOpacity(0.4)))
            : null),
        child: Row(children: [
          Container(width: 36, height: 36,
              decoration: BoxDecoration(
                  color: kSurface, shape: BoxShape.circle,
                  border: Border.all(color: kBorder)),
              child: const Icon(Icons.person_outline_rounded,
                  color: kPrimary, size: 18)),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v(o['name']), style: const TextStyle(
                color: kDark, fontSize: 13, fontWeight: FontWeight.w700)),
            Text('${rh(o['user_rank'] ?? o['rank'])}  ·  PNO: ${v(o['pno'])}',
                style: const TextStyle(color: kSubtle, fontSize: 10)),
          ])),
          if ((o['mobile'] ?? '').toString().isNotEmpty)
            GestureDetector(
              onTap: () async {
                final uri = Uri.parse('tel:${o['mobile']}');
                if (await canLaunchUrl(uri)) launchUrl(uri);
              },
              child: Container(width: 34, height: 34,
                  decoration: BoxDecoration(
                      color: kSuccessBg,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.phone_outlined,
                      size: 15, color: kSuccess))),
        ]),
      );
    }).toList()),
  );
}

class _StaffRow extends StatelessWidget {
  final int index, total;
  final Map staff;
  final bool armed;
  const _StaffRow({
    required this.index, required this.total,
    required this.staff, required this.armed,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(border: index < total - 1
        ? Border(bottom: BorderSide(color: kBorder.withOpacity(0.4)))
        : null),
    child: Row(children: [
      Container(width: 38, height: 38,
          decoration: BoxDecoration(
              color: (armed ? kArmed : kUnarmed).withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(
                  color: (armed ? kArmed : kUnarmed).withOpacity(0.3))),
          child: Center(child: Text('${index + 1}', style: TextStyle(
              color: armed ? kArmed : kUnarmed,
              fontSize: 12, fontWeight: FontWeight.w800)))),
      const SizedBox(width: 12),
      Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(v(staff['name']), style: const TextStyle(
            color: kDark, fontSize: 13, fontWeight: FontWeight.w700)),
        Text('${v(staff['pno'])} · ${v(staff['thana'])}',
            style: const TextStyle(color: kSubtle, fontSize: 11)),
        Row(children: [
          Text(rh(staff['user_rank'] ?? staff['rank']),
              style: const TextStyle(color: kAccent, fontSize: 10,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
                color: (armed ? kArmed : kUnarmed).withOpacity(0.1),
                borderRadius: BorderRadius.circular(4)),
            child: Text(armed ? 'सशस्त्र' : 'निःशस्त्र',
                style: TextStyle(
                    color: armed ? kArmed : kUnarmed,
                    fontSize: 9, fontWeight: FontWeight.w700))),
        ]),
      ])),
      if ((staff['mobile'] ?? '').toString().isNotEmpty)
        GestureDetector(
          onTap: () async {
            final uri = Uri.parse('tel:${staff['mobile']}');
            if (await canLaunchUrl(uri)) launchUrl(uri);
          },
          child: Container(width: 36, height: 36,
              decoration: BoxDecoration(
                  color: kSuccessBg, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.phone_outlined,
                  size: 15, color: kSuccess))),
    ]),
  );
}

class _OfficerChip extends StatelessWidget {
  final Map officer;
  const _OfficerChip(this.officer);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
        color: kPrimary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kPrimary.withOpacity(0.2))),
    child: Text(
        '${officer['name']} (${rh(officer['user_rank'] ?? officer['rank'])})',
        style: const TextStyle(color: kPrimary, fontSize: 10,
            fontWeight: FontWeight.w600)),
  );
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _NavButton({
    required this.icon, required this.label,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: color.withOpacity(0.4),
              blurRadius: 12, offset: const Offset(0, 4))]),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(
            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final dynamic value;
  const _PreviewRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final display = (value == null || value.toString().trim().isEmpty)
        ? '—' : value.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(flex: 2, child: Text(label,
            style: const TextStyle(color: kSubtle, fontSize: 12))),
        Expanded(flex: 3, child: Text(display,
            style: const TextStyle(color: kDark, fontSize: 12,
                fontWeight: FontWeight.w700),
            textAlign: TextAlign.right)),
      ]),
    );
  }
}

class _NoDutyState extends StatelessWidget {
  const _NoDutyState();
  @override
  Widget build(BuildContext context) => Center(child: Container(
    margin: const EdgeInsets.only(top: 60),
    padding: const EdgeInsets.all(40),
    decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder.withOpacity(0.5)),
        boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.05),
            blurRadius: 16, offset: const Offset(0, 4))]),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 64, height: 64,
          decoration: BoxDecoration(
              color: kSurface, shape: BoxShape.circle,
              border: Border.all(color: kBorder)),
          child: const Icon(Icons.location_off_outlined,
              color: kPrimary, size: 30)),
      const SizedBox(height: 16),
      const Text('अभी तक ड्यूटी नहीं सौंपी गई',
          style: TextStyle(color: kDark, fontSize: 16,
              fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      const Text('व्यवस्थापक द्वारा ड्यूटी सौंपे जाने पर यहाँ दिखेगी।',
          style: TextStyle(color: kSubtle, fontSize: 12),
          textAlign: TextAlign.center),
    ]),
  ));
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline_rounded, size: 52, color: kError),
      const SizedBox(height: 14),
      const Text('डेटा लोड करने में त्रुटि',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
              color: kDark)),
      const SizedBox(height: 8),
      Text(error, style: const TextStyle(color: kSubtle, fontSize: 12),
          textAlign: TextAlign.center),
      const SizedBox(height: 18),
      GestureDetector(onTap: onRetry, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
              color: kPrimary, borderRadius: BorderRadius.circular(12)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.refresh_rounded, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('पुनः प्रयास करें', style: TextStyle(
                color: Colors.white, fontSize: 13,
                fontWeight: FontWeight.w700)),
          ]))),
    ]),
  ));
}