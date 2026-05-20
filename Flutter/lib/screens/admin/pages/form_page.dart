import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _kBg      = Color(0xFFFDF6E3);
const _kSurface = Color(0xFFF5E6C8);
const _kPrimary = Color(0xFF8B6914);
const _kDark    = Color(0xFF4A3000);
const _kSubtle  = Color(0xFFAA8844);
const _kBorder  = Color(0xFFD4A843);
const _kError   = Color(0xFFC0392B);
const _kSuccess = Color(0xFF2D6A1E);
const _kInfo    = Color(0xFF1A5276);
const _kOrange  = Color(0xFFE65100);
const _kAmber   = Color(0xFFF59E0B);

// ── Step definitions ──────────────────────────────────────────────────────────
const _kSteps = [
  {'id': 0, 'label': 'Super Zone', 'icon': Icons.layers_outlined,         'color': Color(0xFF6A1B9A)},
  {'id': 1, 'label': 'Zone',       'icon': Icons.grid_view_outlined,       'color': Color(0xFF1565C0)},
  {'id': 2, 'label': 'Sector',     'icon': Icons.view_module_outlined,     'color': Color(0xFF2E7D32)},
  {'id': 3, 'label': 'GP',         'icon': Icons.account_balance_outlined, 'color': Color(0xFF6D4C41)},
  {'id': 4, 'label': 'Center',     'icon': Icons.location_on_outlined,     'color': Color(0xFFC62828)},
];

const _kRanks = ['SP','ASP','DSP','Inspector','SI','ASI','Head Constable','Constable'];
const _kRankColors = {
  'SP':             Color(0xFF6A1B9A),
  'ASP':            Color(0xFF1565C0),
  'DSP':            Color(0xFF1A5276),
  'Inspector':      Color(0xFF2E7D32),
  'SI':             Color(0xFF558B2F),
  'ASI':            Color(0xFF8B6914),
  'Head Constable': Color(0xFFB8860B),
  'Constable':      Color(0xFF6D4C41),
};
const _kLevelRanks = {
  0: ['Inspector', 'SI'],
  1: ['Inspector', 'SI'],
  2: ['ASI', 'Head Constable', 'Constable'],
};
const _kLevelOfficerTitle = {
  0: 'क्षेत्र अधिकारी (Kshetra Adhikari)',
  1: 'निरीक्षक (Nirakshak)',
  2: 'उप-निरीक्षक / पुलिस अधिकारी',
};
const _kLevelOfficerUrl = {
  0: '/admin/kshetra-officers',
  1: '/admin/zonal-officers',
  2: '/admin/sector-officers',
};

final List<String> upDistrictsHindi = [
  'आगरा','आज़मगढ़','बिजनौर','इटावा','अलीगढ़','बागपत','बदायूं','फर्रुखाबाद',
  'अंबेडकर नगर','बहराइच','बुलंदशहर','फतेहपुर','अमेठी','बलिया','चंदौली','फिरोजाबाद',
  'अमरोहा','बलरामपुर','चित्रकूट','गौतम बुद्ध नगर','औरैया','बांदा','देवरिया','गाज़ियाबाद',
  'अयोध्या','बाराबंकी','एटा','गाज़ीपुर','गोंडा','जालौन','कासगंज','लखनऊ',
  'गोरखपुर','जौनपुर','कौशांबी','महाराजगंज','हमीरपुर','झांसी','कुशीनगर','महोबा',
  'हापुड़','कन्नौज','लखीमपुर खीरी','मैनपुरी','हरदोई','कानपुर देहात','ललितपुर','मथुरा',
  'हाथरस','कानपुर नगर','मऊ','पीलीभीत','संभल','सोनभद्र','मेरठ','प्रतापगढ़',
  'संतकबीर नगर','सुल्तानपुर','मिर्जापुर','प्रयागराज','भदोही (संत रविदास नगर)','उन्नाव',
  'मुरादाबाद','रायबरेली','शाहजहाँपुर','वाराणसी','मुजफ्फरनगर','रामपुर','शामली',
  'सहारनपुर','श्रावस्ती','सिद्धार्थनगर','सीतापुर',
];

// ═══════════════════════════════════════════════════════════════════════════════
//  ELECTION STATE
// ═══════════════════════════════════════════════════════════════════════════════

enum _ElectionLoadStatus { loading, active, finalized, none, error }

class _ElectionState {
  final int? id;
  final String name, date, type, phase;
  final bool isActive, isFinalized;
  final _ElectionLoadStatus loadStatus;
  final String errorMsg;

  const _ElectionState({
    this.id, this.name='', this.date='', this.type='', this.phase='',
    this.isActive=false, this.isFinalized=false,
    this.loadStatus=_ElectionLoadStatus.none, this.errorMsg='',
  });

  factory _ElectionState.loading() => const _ElectionState(loadStatus: _ElectionLoadStatus.loading);
  factory _ElectionState.none()    => const _ElectionState(loadStatus: _ElectionLoadStatus.none);
  factory _ElectionState.error(String msg) =>
      _ElectionState(loadStatus: _ElectionLoadStatus.error, errorMsg: msg);

  bool get canAssign => isActive && !isFinalized && id != null;
}

String _eStr(dynamic v) => (v as String? ?? '').trim();
bool   _eBool(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is int)  return v == 1;
  return false;
}
int? _eInt(dynamic v) {
  if (v == null) return null;
  if (v is int)    return v;
  if (v is double) return v.toInt();
  return int.tryParse('$v');
}

Future<_ElectionState> _loadElectionFromApi(String? token) async {
  try {
    final res       = await ApiService.get('/admin/election-config/active', token: token);
    final outer     = (res is Map ? res['data'] : null) as Map<String, dynamic>? ?? {};
    final hasActive = outer['hasActiveConfig'] as bool? ?? false;
    final cfg       = outer['config'] as Map<String, dynamic>? ?? {};
    if (hasActive && cfg.isNotEmpty) {
      final finalized = _eBool(cfg['isFinalized']) || _eBool(cfg['is_finalized']);
      return _ElectionState(
        id: _eInt(cfg['id']), name: _eStr(cfg['electionName']),
        date: _eStr(cfg['electionDate']), type: _eStr(cfg['electionType']),
        phase: _eStr(cfg['phase']),
        isActive: !finalized, isFinalized: finalized,
        loadStatus: finalized ? _ElectionLoadStatus.finalized : _ElectionLoadStatus.active,
      );
    }
    return _ElectionState.none();
  } catch (_) {}

  try {
    final res       = await ApiService.get('/admin/election/finalize/status', token: token);
    final outer     = res is Map ? res : <String, dynamic>{};
    final hasActive = outer['hasActiveConfig'] as bool? ?? false;
    final cfg       = outer['config'] as Map<String, dynamic>?
                   ?? outer['data']   as Map<String, dynamic>? ?? {};
    final finalized = _eBool(cfg['isFinalized']) || _eBool(outer['alreadyFinalized']);
    final name      = _eStr(cfg['electionName']);
    final eid       = _eInt(cfg['id'] ?? outer['electionId']);
    if (!hasActive) return _ElectionState.none();
    return _ElectionState(
      id: eid, name: name, date: _eStr(cfg['electionDate']),
      type: _eStr(cfg['electionType']), phase: _eStr(cfg['phase']),
      isActive: !finalized, isFinalized: finalized,
      loadStatus: finalized ? _ElectionLoadStatus.finalized
          : name.isNotEmpty ? _ElectionLoadStatus.active : _ElectionLoadStatus.none,
    );
  } catch (_) {}

  return _ElectionState.error('चुनाव स्थिति लोड नहीं हो सकी');
}

// ─── Election guard dialog ────────────────────────────────────────────────────
Future<void> handleElectionGuard(
  BuildContext context, _ElectionState election, Future<void> Function() action,
) async {
  if (!election.canAssign) {
    String title, body; IconData ico; Color col;
    switch (election.loadStatus) {
      case _ElectionLoadStatus.loading:
        title='चुनाव लोड हो रहा है'; body='कृपया प्रतीक्षा करें।';
        ico=Icons.hourglass_top_rounded; col=_kAmber;
      case _ElectionLoadStatus.finalized:
        title='चुनाव समाप्त हो चुका है';
        body='"${election.name}" समाप्त। नई ड्यूटी के लिए Master admin से संपर्क करें।';
        ico=Icons.archive_rounded; col=_kError;
      case _ElectionLoadStatus.error:
        title='चुनाव स्थिति अज्ञात';
        body=election.errorMsg.isNotEmpty ? election.errorMsg : 'पुनः प्रयास करें।';
        ico=Icons.wifi_off_rounded; col=_kError;
      default:
        title='कोई सक्रिय चुनाव नहीं';
        body='अधिकारी assignment के लिए Master admin से चुनाव कॉन्फ़िगर करवाएं।';
        ico=Icons.warning_amber_rounded; col=_kAmber;
    }
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kBg,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14), side: BorderSide(color: col, width: 1.5)),
        title: Row(children: [
          Icon(ico, color: col, size: 22), const SizedBox(width: 8),
          Expanded(child: Text(title,
              style: TextStyle(color: col, fontWeight: FontWeight.w800, fontSize: 15))),
        ]),
        content: Text(body, style: const TextStyle(color: _kDark, fontSize: 13)),
        actions: [ElevatedButton(
          onPressed: () => Navigator.pop(ctx),
          style: ElevatedButton.styleFrom(backgroundColor: col, foregroundColor: Colors.white),
          child: const Text('ठीक है'),
        )],
      ),
    );
    return;
  }
  await action();
}

// ═══════════════════════════════════════════════════════════════════════════════
//  JOB STATE
// ═══════════════════════════════════════════════════════════════════════════════

class _JobState {
  final int szId;
  final String szName;
  int jobId;
  String status;
  int totalCenters;
  int doneCenters;
  bool hasShortages;
  Map<String, dynamic>? shortageReport;

  _JobState({
    required this.szId, required this.szName, required this.jobId,
    this.status='pending', this.totalCenters=0, this.doneCenters=0,
    this.hasShortages=false, this.shortageReport,
  });

  double get progress =>
      totalCenters > 0 ? (doneCenters / totalCenters).clamp(0.0, 1.0) : 0;
}

final Map<int, _JobState> _activeJobs = {};
final _jobNotifier = ValueNotifier<int>(0);
void _notifyJobChange() => _jobNotifier.value++;

// ═══════════════════════════════════════════════════════════════════════════════
//  FORM PAGE
// ═══════════════════════════════════════════════════════════════════════════════

class FormPage extends StatefulWidget {
  const FormPage({super.key});
  @override State<FormPage> createState() => _FormPageState();
}

class _FormPageState extends State<FormPage> {
  int _step = 0;
  int? _selectedSZId, _selectedZoneId, _selectedSectorId, _selectedGPId;
  String? _selectedSZName, _selectedZoneName, _selectedSectorName, _selectedGPName;
  _ElectionState _election        = _ElectionState.loading();
  bool           _electionLoading = true;

  @override
  void initState() { super.initState(); _fetchActiveElection(); }

  Future<void> _fetchActiveElection() async {
    if (!mounted) return;
    setState(() { _electionLoading=true; _election=_ElectionState.loading(); });
    try {
      final token  = await AuthService.getToken();
      final result = await _loadElectionFromApi(token);
      if (!mounted) return;
      setState(() { _election=result; _electionLoading=false; });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _election=_ElectionState.error('चुनाव स्थिति लोड नहीं हो सकी');
        _electionLoading=false;
      });
    }
  }

  void _goToStep(int step) {
    if (!mounted) return;
    setState(() {
      _step = step;
      if (step <= 0) { _selectedSZId=null;     _selectedSZName=null; }
      if (step <= 1) { _selectedZoneId=null;   _selectedZoneName=null; }
      if (step <= 2) { _selectedSectorId=null; _selectedSectorName=null; }
      if (step <= 3) { _selectedGPId=null;     _selectedGPName=null; }
    });
  }

  void _onSZSelected(Map item) {
    if (!mounted) return;
    setState(() {
      _selectedSZId=item['id'] as int; _selectedSZName=item['name'] as String? ?? '';
      _selectedZoneId=null; _selectedZoneName=null;
      _selectedSectorId=null; _selectedSectorName=null;
      _selectedGPId=null; _selectedGPName=null;
      _step=1;
    });
  }
  void _onZoneSelected(Map item) {
    if (!mounted) return;
    setState(() {
      _selectedZoneId=item['id'] as int; _selectedZoneName=item['name'] as String? ?? '';
      _selectedSectorId=null; _selectedSectorName=null;
      _selectedGPId=null; _selectedGPName=null; _step=2;
    });
  }
  void _onSectorSelected(Map item) {
    if (!mounted) return;
    setState(() {
      _selectedSectorId=item['id'] as int; _selectedSectorName=item['name'] as String? ?? '';
      _selectedGPId=null; _selectedGPName=null; _step=3;
    });
  }
  void _onGPSelected(Map item) {
    if (!mounted) return;
    setState(() {
      _selectedGPId=item['id'] as int; _selectedGPName=item['name'] as String? ?? '';
      _step=4;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _ElectionStatusBar(election:_election, loading:_electionLoading, onRefresh:_fetchActiveElection),
      ValueListenableBuilder<int>(
        valueListenable: _jobNotifier,
        builder: (_,__,___) {
          final running = _activeJobs.values
              .where((j) => j.status=='running' || j.status=='pending').toList();
          if (running.isEmpty) return const SizedBox.shrink();
          return _GlobalJobBanner(jobs: running);
        },
      ),
      _StepBar(currentStep:_step, onTap:_goToStep,
        szName:_selectedSZName, zoneName:_selectedZoneName,
        sectorName:_selectedSectorName, gpName:_selectedGPName),
      if (_step > 0)
        _Breadcrumb(step:_step, szName:_selectedSZName, zoneName:_selectedZoneName,
          sectorName:_selectedSectorName, gpName:_selectedGPName, onTap:_goToStep),
      Expanded(child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin:const Offset(0.04,0), end:Offset.zero).animate(anim),
            child: child),
        ),
        child: _buildStep(),
      )),
    ]);
  }

  Widget _buildStep() {
    switch (_step) {
      case 0: return _StepList(
          key: const ValueKey('sz'),
          title:'Super Zones', icon:Icons.layers_outlined, color:const Color(0xFF6A1B9A),
          officerTitle:_kLevelOfficerTitle[0]!, officerRanks:_kLevelRanks[0]!,
          officerPostUrl:_kLevelOfficerUrl[0]!, levelIndex:0,
          fetchUrl:'/admin/super-zones', createUrl:'/admin/super-zones',
          updateUrlFn:(id)=>'/admin/super-zones/$id',
          deleteUrlFn:(id)=>'/admin/super-zones/$id',
          fields:const ['name','district','block'],
          onSelect:_onSZSelected, selectedId:_selectedSZId,
          showAssignButton:true, election:_election);

      case 1: return _StepList(
          key: ValueKey('zone_$_selectedSZId'),
          title:'Zones', icon:Icons.grid_view_outlined, color:const Color(0xFF1565C0),
          officerTitle:_kLevelOfficerTitle[1]!, officerRanks:_kLevelRanks[1]!,
          officerPostUrl:_kLevelOfficerUrl[1]!, levelIndex:1,
          fetchUrl:'/admin/super-zones/$_selectedSZId/zones',
          createUrl:'/admin/super-zones/$_selectedSZId/zones',
          updateUrlFn:(id)=>'/admin/zones/$id', deleteUrlFn:(id)=>'/admin/zones/$id',
          fields:const ['name','hqAddress'],
          onSelect:_onZoneSelected, selectedId:_selectedZoneId, election:_election);

      case 2: return _StepList(
          key: ValueKey('sector_$_selectedZoneId'),
          title:'Sectors', icon:Icons.view_module_outlined, color:const Color(0xFF2E7D32),
          officerTitle:_kLevelOfficerTitle[2]!, officerRanks:_kLevelRanks[2]!,
          officerPostUrl:_kLevelOfficerUrl[2]!, levelIndex:2,
          fetchUrl:'/admin/zones/$_selectedZoneId/sectors',
          createUrl:'/admin/zones/$_selectedZoneId/sectors',
          updateUrlFn:(id)=>'/admin/sectors/$id', deleteUrlFn:(id)=>'/admin/sectors/$id',
          fields:const ['name','hqAddress'],
          onSelect:_onSectorSelected, selectedId:_selectedSectorId, election:_election);

      case 3: return _StepList(
          key: ValueKey('gp_$_selectedSectorId'),
          title:'Gram Panchayats', icon:Icons.account_balance_outlined, color:const Color(0xFF6D4C41),
          officerTitle:'', officerRanks:const [], officerPostUrl:'', levelIndex:3,
          fetchUrl:'/admin/sectors/$_selectedSectorId/gram-panchayats',
          createUrl:'/admin/sectors/$_selectedSectorId/gram-panchayats',
          updateUrlFn:(id)=>'/admin/gram-panchayats/$id',
          deleteUrlFn:(id)=>'/admin/gram-panchayats/$id',
          fields:const ['name','address'],
          onSelect:_onGPSelected, selectedId:_selectedGPId, election:_election);

      case 4: return _CenterStep(
          key: ValueKey('center_$_selectedGPId'),
          gpId:_selectedGPId!, szId:_selectedSZId, election:_election);

      default: return const SizedBox.shrink();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ELECTION STATUS BAR
// ═══════════════════════════════════════════════════════════════════════════════

class _ElectionStatusBar extends StatelessWidget {
  final _ElectionState election; final bool loading; final VoidCallback onRefresh;
  const _ElectionStatusBar({required this.election, required this.loading, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (loading || election.loadStatus == _ElectionLoadStatus.loading) {
      return Container(
        color: _kDark.withOpacity(0.92),
        padding: const EdgeInsets.symmetric(horizontal:14, vertical:8),
        child: Row(children: [
          const SizedBox(width:12,height:12,child:CircularProgressIndicator(strokeWidth:2,color:_kAmber)),
          const SizedBox(width:8),
          const Expanded(child:Text('चुनाव स्थिति लोड हो रही है...',
              style:TextStyle(color:_kAmber,fontSize:11,fontWeight:FontWeight.w600))),
          GestureDetector(onTap:onRefresh,child:const Icon(Icons.refresh,size:14,color:_kAmber)),
        ]),
      );
    }

    late Color barColor, iconColor, textColor, subColor; late IconData ico;
    late String label, subtitle; late bool canTap;

    switch (election.loadStatus) {
      case _ElectionLoadStatus.active:
        barColor=_kSuccess.withOpacity(0.11); iconColor=_kSuccess; textColor=_kSuccess; subColor=_kDark;
        ico=Icons.how_to_vote_outlined; label='सक्रिय चुनाव';
        subtitle=[
          if(election.name.isNotEmpty) 'चुनाव: ${election.name}',
          if(election.phase.isNotEmpty) election.phase,
          if(election.date.isNotEmpty)  election.date,
        ].join('  •  ');
        canTap=false;
      case _ElectionLoadStatus.finalized:
        barColor=_kError.withOpacity(0.09); iconColor=_kError; textColor=_kError; subColor=_kSubtle;
        ico=Icons.archive_rounded; label='⚠️ चुनाव समाप्त';
        subtitle=election.name.isNotEmpty ? '"${election.name}" समाप्त — assignment अक्षम'
            : 'चुनाव समाप्त — नई ड्यूटी के लिए Master admin से संपर्क करें';
        canTap=true;
      case _ElectionLoadStatus.error:
        barColor=_kError.withOpacity(0.08); iconColor=_kError; textColor=_kError; subColor=_kSubtle;
        ico=Icons.wifi_off_rounded; label='⚠️ चुनाव स्थिति अज्ञात';
        subtitle=election.errorMsg.isNotEmpty ? election.errorMsg : 'पुनः प्रयास करें';
        canTap=true;
      default:
        barColor=_kAmber.withOpacity(0.11); iconColor=_kAmber; textColor=_kAmber; subColor=_kSubtle;
        ico=Icons.warning_amber_rounded; label='⚠️ कोई सक्रिय चुनाव नहीं';
        subtitle='अधिकारी assignment के लिए Master admin से चुनाव कॉन्फ़िगर करवाएं';
        canTap=true;
    }

    return GestureDetector(
      onTap: canTap ? onRefresh : null,
      child: AnimatedContainer(
        duration:const Duration(milliseconds:300), color:barColor,
        padding:const EdgeInsets.symmetric(horizontal:14,vertical:7),
        child:Row(children:[
          Container(padding:const EdgeInsets.all(5),
            decoration:BoxDecoration(color:iconColor.withOpacity(0.15),shape:BoxShape.circle),
            child:Icon(ico,size:13,color:iconColor)),
          const SizedBox(width:8),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
            Text(label,style:TextStyle(color:textColor,fontSize:9,fontWeight:FontWeight.w800,letterSpacing:0.4)),
            if(subtitle.isNotEmpty)
              Text(subtitle,style:TextStyle(color:subColor,fontSize:10),maxLines:1,overflow:TextOverflow.ellipsis),
          ])),
          Icon(canTap?Icons.refresh:Icons.check_circle_outline,size:13,color:iconColor),
        ])),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  GLOBAL JOB BANNER
// ═══════════════════════════════════════════════════════════════════════════════

class _GlobalJobBanner extends StatelessWidget {
  final List<_JobState> jobs;
  const _GlobalJobBanner({required this.jobs});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kOrange.withOpacity(0.12),
      padding: const EdgeInsets.symmetric(horizontal:12,vertical:8),
      child: Column(mainAxisSize:MainAxisSize.min, children:[
        Row(children:[
          const SizedBox(width:14,height:14,child:CircularProgressIndicator(strokeWidth:2,color:_kOrange)),
          const SizedBox(width:8),
          Expanded(child:Text(
            jobs.map((j) {
              final pct = (j.progress*100).toStringAsFixed(0);
              return '${j.szName}: ${j.status=="pending"?"शुरू हो रहा है...":"$pct% (${j.doneCenters}/${j.totalCenters})"}';
            }).join(' • '),
            style:const TextStyle(color:_kOrange,fontSize:11,fontWeight:FontWeight.w700),
            maxLines:1,overflow:TextOverflow.ellipsis,
          )),
          const Icon(Icons.sync,size:14,color:_kOrange),
        ]),
        if(jobs.any((j)=>j.totalCenters>0)) ...[
          const SizedBox(height:4),
          for(final j in jobs.where((j)=>j.totalCenters>0))
            Padding(padding:const EdgeInsets.only(bottom:2),
              child:LinearProgressIndicator(
                value:j.progress,
                backgroundColor:_kOrange.withOpacity(0.15),
                valueColor:const AlwaysStoppedAnimation<Color>(_kOrange),
                minHeight:3)),
        ],
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  STEP BAR
// ═══════════════════════════════════════════════════════════════════════════════

class _StepBar extends StatelessWidget {
  final int currentStep; final void Function(int) onTap;
  final String? szName, zoneName, sectorName, gpName;
  const _StepBar({required this.currentStep, required this.onTap,
    this.szName, this.zoneName, this.sectorName, this.gpName});

  bool _isEnabled(int step) {
    if (step==0) return true;
    if (step==1) return szName!=null;
    if (step==2) return zoneName!=null;
    if (step==3) return sectorName!=null;
    if (step==4) return gpName!=null;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color:_kDark,
      padding:const EdgeInsets.symmetric(horizontal:8,vertical:10),
      child:Row(children:List.generate(_kSteps.length,(i){
        final step=_kSteps[i]; final label=step['label'] as String;
        final icon=step['icon'] as IconData; final color=step['color'] as Color;
        final isCur=currentStep==i; final isDone=currentStep>i; final isEn=_isEnabled(i);
        return Expanded(child:GestureDetector(
          onTap:isEn?()=>onTap(i):null,
          child:AnimatedContainer(
            duration:const Duration(milliseconds:200),
            margin:const EdgeInsets.symmetric(horizontal:2),
            padding:const EdgeInsets.symmetric(vertical:7),
            decoration:BoxDecoration(
              color:isCur?color:isDone?color.withOpacity(0.2):Colors.white12,
              borderRadius:BorderRadius.circular(10),
              border:Border.all(color:isCur?color:isDone?color.withOpacity(0.4):Colors.white24)),
            child:Column(mainAxisSize:MainAxisSize.min,children:[
              Icon(isDone?Icons.check_circle_rounded:icon,
                  size:18, color:isCur?Colors.white:isDone?color:Colors.white38),
              const SizedBox(height:3),
              Text(label,style:TextStyle(
                  color:isCur?Colors.white:isDone?color:Colors.white38,
                  fontSize:9,fontWeight:isCur?FontWeight.w800:FontWeight.w500),
                maxLines:1,overflow:TextOverflow.ellipsis),
            ]),
          ),
        ));
      })),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  BREADCRUMB
// ═══════════════════════════════════════════════════════════════════════════════

class _Breadcrumb extends StatelessWidget {
  final int step; final String? szName, zoneName, sectorName, gpName;
  final void Function(int) onTap;
  const _Breadcrumb({required this.step, this.szName, this.zoneName,
    this.sectorName, this.gpName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final crumbs = <_Crumb>[];
    if (szName!=null)     crumbs.add(_Crumb(szName!,     Icons.layers_outlined,         const Color(0xFF6A1B9A),0));
    if (zoneName!=null)   crumbs.add(_Crumb(zoneName!,   Icons.grid_view_outlined,       const Color(0xFF1565C0),1));
    if (sectorName!=null) crumbs.add(_Crumb(sectorName!, Icons.view_module_outlined,     const Color(0xFF2E7D32),2));
    if (gpName!=null)     crumbs.add(_Crumb(gpName!,     Icons.account_balance_outlined, const Color(0xFF6D4C41),3));

    return Container(
      color:_kSurface.withOpacity(0.7),
      padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),
      child:SingleChildScrollView(scrollDirection:Axis.horizontal,
        child:Row(children:[
          for(int i=0;i<crumbs.length;i++)...[
            if(i>0) const Icon(Icons.chevron_right,size:14,color:_kSubtle),
            GestureDetector(
              onTap:()=>onTap(crumbs[i].step),
              child:Container(
                padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),
                decoration:BoxDecoration(
                  color:crumbs[i].color.withOpacity(i==crumbs.length-1?0.12:0.06),
                  borderRadius:BorderRadius.circular(6),
                  border:Border.all(color:crumbs[i].color.withOpacity(i==crumbs.length-1?0.4:0.2))),
                child:Row(mainAxisSize:MainAxisSize.min,children:[
                  Icon(crumbs[i].icon,size:11,color:crumbs[i].color),
                  const SizedBox(width:4),
                  ConstrainedBox(constraints:const BoxConstraints(maxWidth:100),
                    child:Text(crumbs[i].name,
                        style:TextStyle(color:crumbs[i].color,fontSize:11,
                            fontWeight:i==crumbs.length-1?FontWeight.w700:FontWeight.w500),
                        maxLines:1,overflow:TextOverflow.ellipsis)),
                ])),
            ),
          ],
        ])),
    );
  }
}
class _Crumb {
  final String name; final IconData icon; final Color color; final int step;
  _Crumb(this.name,this.icon,this.color,this.step);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  STEP LIST
// ═══════════════════════════════════════════════════════════════════════════════

class _StepList extends StatefulWidget {
  final String title, fetchUrl, createUrl, officerPostUrl;
  final String Function(int) updateUrlFn, deleteUrlFn;
  final List<String> fields; final IconData icon; final Color color;
  final String officerTitle; final List<String> officerRanks; final int levelIndex;
  final void Function(Map) onSelect; final int? selectedId;
  final bool showAssignButton; final _ElectionState election;

  const _StepList({super.key,
    required this.title, required this.fetchUrl, required this.createUrl,
    required this.officerPostUrl, required this.updateUrlFn, required this.deleteUrlFn,
    required this.fields, required this.icon, required this.color,
    required this.officerTitle, required this.officerRanks, required this.levelIndex,
    required this.onSelect, this.selectedId, this.showAssignButton=false,
    required this.election});

  @override State<_StepList> createState() => _StepListState();
}

class _StepListState extends State<_StepList> {
  final List<Map> _items = [];
  bool _loading=true, _hasMore=true, _loadingMore=false, _disposed=false;
  int _page=1; static const _limit=20; String _q='';
  Timer? _debounce;
  final _searchCtrl = TextEditingController();
  final _scroll     = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _searchCtrl.addListener(_onSearchChanged);
    _load(reset:true);
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce=Timer(const Duration(milliseconds:350),(){
      if(_disposed)return;
      final q=_searchCtrl.text.trim();
      if(q!=_q){_q=q;_reload();}
    });
  }

  void _onScroll() {
    if(_disposed)return;
    if(_scroll.hasClients && _scroll.position.pixels>=_scroll.position.maxScrollExtent-200) _load();
  }

  @override
  void dispose(){
    _disposed=true; _debounce?.cancel();
    _scroll.removeListener(_onScroll); _searchCtrl.removeListener(_onSearchChanged);
    _scroll.dispose(); _searchCtrl.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn){if(!_disposed&&mounted)setState(fn);}

  void _reload(){
    _safeSetState((){_items.clear();_page=1;_hasMore=true;});
    _load(reset:true);
  }

  Future<void> _load({bool reset=false}) async {
    if(_disposed)return;
    if(reset) _safeSetState((){_items.clear();_page=1;_hasMore=true;_loading=true;});
    if(!_hasMore&&!reset)return;
    if(_loadingMore)return;
    _safeSetState((){if(!reset)_loadingMore=true;});
    try {
      final token=await AuthService.getToken();
      if(_disposed)return;
      final url='${widget.fetchUrl}?page=$_page&limit=$_limit&q=${Uri.encodeComponent(_q)}';
      final res=await ApiService.get(url,token:token);
      if(_disposed)return;
      List<Map> items; int? totalPages;
      final data=res['data'];
      if(data is List){
        items=data.map((e)=>Map<String,dynamic>.from(e as Map)).toList(); totalPages=null;
      } else if(data is Map){
        final inner=data['data'];
        items=(inner is List)?inner.map((e)=>Map<String,dynamic>.from(e as Map)).toList():[];
        totalPages=(data['totalPages'] as num?)?.toInt();
      } else { items=[]; }
      _safeSetState((){
        _items.addAll(items);
        _hasMore=totalPages!=null?_page<totalPages:false;
        _page++; _loading=false; _loadingMore=false;
      });
    } catch(e){
      _safeSetState((){_loading=false;_loadingMore=false;});
      if(!_disposed&&mounted) _snack('Load failed: $e',error:true);
    }
  }

  void _snack(String msg,{bool error=false}){
    if(_disposed||!mounted)return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:Text(msg), backgroundColor:error?_kError:_kSuccess,
      behavior:SnackBarBehavior.floating,
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10))));
  }

  Future<void> _delete(Map item) async {
    final confirmed=await _confirm(context,'Delete "${item['name']}"?');
    if(!confirmed||_disposed)return;
    try {
      final token=await AuthService.getToken(); if(_disposed)return;
      await ApiService.delete(widget.deleteUrlFn(item['id'] as int),token:token);
      if(_disposed)return;
      _snack('Deleted'); _reload();
    } catch(e){_snack('Delete failed: $e',error:true);}
  }

  void _openDialog({Map? existing}){
    if(_disposed||!mounted)return;
    showDialog(context:context,barrierDismissible:false,builder:(_)=>_ItemDialog(
      title:existing==null?'Add ${widget.title.replaceAll('s','').trim()}':'Edit',
      color:widget.color,icon:widget.icon,fields:widget.fields,
      officerTitle:widget.officerTitle,officerRanks:widget.officerRanks,
      officerPostUrl:widget.officerPostUrl,levelIndex:widget.levelIndex,
      existing:existing,createUrl:widget.createUrl,updateUrlFn:widget.updateUrlFn,
      election:widget.election,onDone:(){if(!_disposed)_reload();}));
  }

  // ── Assign Duty ─────────────────────────────────────────────────────────────
  Future<void> _startAssignJob(Map szItem) async {
    final szId=szItem['id'] as int; final szName=szItem['name'] as String? ?? '';
    if(_activeJobs.containsKey(szId) &&
        (_activeJobs[szId]!.status=='running'||_activeJobs[szId]!.status=='pending')){
      _snack('$szName के लिए assignment पहले से चल रही है'); return;
    }
    final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      backgroundColor:_kBg,
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14),
          side:BorderSide(color:widget.color.withOpacity(0.5))),
      title:Row(children:[
        Icon(Icons.assignment_outlined,color:widget.color,size:20),const SizedBox(width:8),
        const Expanded(child:Text('Duty Assignment',
            style:TextStyle(color:_kDark,fontWeight:FontWeight.w800,fontSize:15))),
      ]),
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('"$szName" के सभी centers पर मानक के अनुसार 1 set स्टाफ असाइन होगा।',
            style:const TextStyle(color:_kDark,fontSize:13)),
        const SizedBox(height:8),
        Container(padding:const EdgeInsets.all(9),
          decoration:BoxDecoration(color:_kOrange.withOpacity(0.08),borderRadius:BorderRadius.circular(8),
              border:Border.all(color:_kOrange.withOpacity(0.3))),
          child:const Row(children:[
            Icon(Icons.info_outline,size:13,color:_kOrange),SizedBox(width:6),
            Expanded(child:Text('Background में चलेगा। पहले से assigned centers skip होंगे।',
                style:TextStyle(color:_kOrange,fontSize:11))),
          ])),
      ]),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false),
            child:const Text('रद्द',style:TextStyle(color:_kSubtle))),
        ElevatedButton(onPressed:()=>Navigator.pop(ctx,true),
            style:ElevatedButton.styleFrom(backgroundColor:widget.color,foregroundColor:Colors.white),
            child:const Text('Start')),
      ]));
    if(confirmed!=true||!mounted)return;

    try {
      final token=await AuthService.getToken();
      final res=await ApiService.post('/admin/assign/start/$szId',{},token:token);
      final jobId=(res['data']?['jobId'] as num?)?.toInt()??0;
      if(jobId<=0){_snack('Job शुरू नहीं हुआ',error:true);return;}
      _activeJobs[szId]=_JobState(szId:szId,szName:szName,jobId:jobId,status:'running');
      _notifyJobChange();
      _pollJobStatus(szId,jobId,token??'');
      _snack('$szName assignment शुरू हो गई');
    } catch(e){_snack('Assignment शुरू नहीं हुई: $e',error:true);}
  }

  void _pollJobStatus(int szId, int jobId, String token) {
    Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final res = await ApiService.get('/admin/assign/status/$jobId', token: token);
        final job = res['data'] as Map?;
        final status = job?['status'] as String? ?? 'pending';
        final total = (job?['total_centers'] as num?)?.toInt()
            ?? (job?['totalCenters'] as num?)?.toInt() ?? 0;
        final done = (job?['done_centers'] as num?)?.toInt()
            ?? (job?['doneCenters'] as num?)?.toInt() ?? 0;
        final shortageRaw = job?['shortage_report'] ?? job?['shortageReport'];
        Map<String, dynamic>? shortageReport;
        if (shortageRaw is Map) shortageReport = Map<String, dynamic>.from(shortageRaw);
        final hasShortages = shortageReport?['hasShortages'] as bool? ?? false;

        if (_activeJobs.containsKey(szId)) {
          _activeJobs[szId]!.status = status;
          _activeJobs[szId]!.totalCenters = total;
          _activeJobs[szId]!.doneCenters = done;
          _activeJobs[szId]!.hasShortages = hasShortages;
          _activeJobs[szId]!.shortageReport = shortageReport;
        }
        _notifyJobChange();

        if (status == 'done' || status == 'error') {
          timer.cancel();
          final name = _activeJobs[szId]?.szName ?? '';
          final report = _activeJobs[szId]?.shortageReport;
          _activeJobs.remove(szId);
          _notifyJobChange();
          if (!_disposed) _reload();
          if (mounted) {
            if (status == 'done' && hasShortages && report != null) {
              await showModalBottomSheet(
                context: context, isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => _ShortageResolutionSheet(
                  szId: szId, szName: name, shortageReport: report,
                  onResolved: () { if (!_disposed) _reload(); }),
              );
            } else if (status == 'done') {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('$name Assignment पूर्ण! ✓'),
                backgroundColor: _kSuccess, behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4)));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Assignment विफल: ${job?['error_msg'] ?? job?['errorMsg'] ?? 'Unknown'}'),
                backgroundColor: _kError, behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 5)));
            }
          }
        }
      } catch (e) { debugPrint('Poll job error: $e'); }
    });
  }

  // ── Clear Duties ─────────────────────────────────────────────────────────────
  Future<void> _refreshDuties(Map szItem) async {
    final szId=szItem['id'] as int; final szName=szItem['name'] as String? ?? '';
    final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      backgroundColor:_kBg,
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14),side:const BorderSide(color:_kError)),
      title:const Row(children:[
        Icon(Icons.cleaning_services_outlined,color:_kError,size:20),SizedBox(width:8),
        Text('सभी Duties हटाएं',style:TextStyle(color:_kError,fontWeight:FontWeight.w800))]),
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('"$szName" के सभी बूथ assignments हट जाएंगे।',
            style:const TextStyle(color:_kDark,fontSize:13)),
        const SizedBox(height:8),
        Container(padding:const EdgeInsets.all(9),
          decoration:BoxDecoration(color:_kOrange.withOpacity(0.08),borderRadius:BorderRadius.circular(8),
              border:Border.all(color:_kOrange.withOpacity(0.3))),
          child:const Row(children:[
            Icon(Icons.info_outline,size:13,color:_kOrange),SizedBox(width:6),
            Expanded(child:Text('Staff Reserve में वापस आ जाएगा। दोबारा "Assign Duty" से लगाएं।',
                style:TextStyle(color:_kOrange,fontSize:11)))]))]),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false),
            child:const Text('रद्द',style:TextStyle(color:_kSubtle))),
        ElevatedButton(onPressed:()=>Navigator.pop(ctx,true),
            style:ElevatedButton.styleFrom(backgroundColor:_kError,foregroundColor:Colors.white),
            child:const Text('हां, हटाएं'))]));
    if(confirmed!=true||!mounted)return;
    try {
      final token=await AuthService.getToken();
      final res=await ApiService.post('/admin/super-zones/$szId/clear-duties',{},token:token);
      final removed=(res['data']?['removed'] as num?)?.toInt()??0;
      _snack('$removed assignments हटाई गईं ✓'); _reload();
    } catch(e){_snack('Error: $e',error:true);}
  }

  // ── Lock / Unlock ─────────────────────────────────────────────────────────────
  Future<void> _lockSZ(Map szItem) async {
    final szId=szItem['id'] as int;
    final isLocked=(szItem['is_locked'] as num? ??0)==1;
    if(isLocked){
      final ctrl=TextEditingController();
      final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
        backgroundColor:_kBg,
        title:const Row(children:[
          Icon(Icons.lock_open,color:_kInfo,size:20),SizedBox(width:8),
          Text('Unlock Request',style:TextStyle(color:_kInfo,fontWeight:FontWeight.w800))]),
        content:Column(mainAxisSize:MainAxisSize.min,children:[
          const Text('Unlock का कारण दर्ज करें:',style:TextStyle(color:_kDark,fontSize:13)),
          const SizedBox(height:8),
          TextField(controller:ctrl,style:const TextStyle(color:_kDark),
              decoration:InputDecoration(hintText:'कारण लिखें...',filled:true,fillColor:Colors.white,
                  border:OutlineInputBorder(borderRadius:BorderRadius.circular(8))),maxLines:3)]),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),
              child:const Text('रद्द',style:TextStyle(color:_kSubtle))),
          ElevatedButton(onPressed:()=>Navigator.pop(ctx,true),
              style:ElevatedButton.styleFrom(backgroundColor:_kInfo,foregroundColor:Colors.white),
              child:const Text('Request भेजें'))]));
      if(confirmed!=true||!mounted)return;
      try {
        final token=await AuthService.getToken();
        await ApiService.post('/admin/unlock/request',
            {'superZoneId':szId,'reason':ctrl.text.trim()},token:token);
        _snack('Unlock request भेजी गई'); _reload();
      } catch(e){_snack('Error: $e',error:true);}
    } else {
      final ctrl=TextEditingController();
      final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
        backgroundColor:_kBg,
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14),side:const BorderSide(color:_kSuccess)),
        title:const Row(children:[
          Icon(Icons.lock,color:_kSuccess,size:20),SizedBox(width:8),
          Text('Lock Duties',style:TextStyle(color:_kSuccess,fontWeight:FontWeight.w800))]),
        content:Column(mainAxisSize:MainAxisSize.min,children:[
          const Text('Lock करने के बाद manual changes बंद हो जाएंगे।',
              style:TextStyle(color:_kDark,fontSize:13)),
          const SizedBox(height:8),
          TextField(controller:ctrl,style:const TextStyle(color:_kDark),
              decoration:InputDecoration(hintText:'कारण (Optional)',filled:true,fillColor:Colors.white,
                  border:OutlineInputBorder(borderRadius:BorderRadius.circular(8))))]),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),
              child:const Text('रद्द',style:TextStyle(color:_kSubtle))),
          ElevatedButton(onPressed:()=>Navigator.pop(ctx,true),
              style:ElevatedButton.styleFrom(backgroundColor:_kSuccess,foregroundColor:Colors.white),
              child:const Text('Lock करें'))]));
      if(confirmed!=true||!mounted)return;
      try {
        final token=await AuthService.getToken();
        await ApiService.post('/admin/lock/$szId',{'reason':ctrl.text.trim()},token:token);
        _snack('Locked successfully'); _reload();
      } catch(e){_snack('Error: $e',error:true);}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children:[
      // Header
      Container(color:_kSurface,padding:const EdgeInsets.fromLTRB(12,10,12,10),
        child:Row(children:[
          Container(padding:const EdgeInsets.all(7),
            decoration:BoxDecoration(color:widget.color.withOpacity(0.12),borderRadius:BorderRadius.circular(8)),
            child:Icon(widget.icon,color:widget.color,size:16)),
          const SizedBox(width:10),
          Expanded(child:Text(widget.title,
              style:const TextStyle(color:_kDark,fontWeight:FontWeight.w800,fontSize:15))),
          GestureDetector(onTap:()=>_openDialog(),
            child:Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:7),
              decoration:BoxDecoration(color:widget.color,borderRadius:BorderRadius.circular(9)),
              child:const Row(mainAxisSize:MainAxisSize.min,children:[
                Icon(Icons.add,color:Colors.white,size:14),SizedBox(width:4),
                Text('जोड़ें',style:TextStyle(color:Colors.white,fontSize:12,fontWeight:FontWeight.w700))]))),
        ])),
      // Search
      Container(color:_kBg,padding:const EdgeInsets.fromLTRB(12,8,12,8),
        child:TextField(controller:_searchCtrl,style:const TextStyle(color:_kDark,fontSize:13),
          decoration:InputDecoration(
            hintText:'${widget.title} खोजें...',hintStyle:const TextStyle(color:_kSubtle,fontSize:12),
            prefixIcon:const Icon(Icons.search,color:_kSubtle,size:18),
            suffixIcon:_q.isNotEmpty?IconButton(
                icon:const Icon(Icons.clear,size:16,color:_kSubtle),
                onPressed:(){_searchCtrl.clear();_q='';_reload();}):null,
            filled:true,fillColor:Colors.white,isDense:true,
            contentPadding:const EdgeInsets.symmetric(horizontal:12,vertical:10),
            border:OutlineInputBorder(borderRadius:BorderRadius.circular(10),borderSide:const BorderSide(color:_kBorder)),
            enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(10),borderSide:const BorderSide(color:_kBorder)),
            focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(10),borderSide:BorderSide(color:widget.color,width:2))))),
      // List
      Expanded(child:_loading
        ? const Center(child:CircularProgressIndicator(color:_kPrimary))
        : _items.isEmpty
            ? _emptyState(widget.title,widget.icon,widget.color)
            : RefreshIndicator(
                onRefresh:()async=>_reload(),color:_kPrimary,
                child:Scrollbar(controller:_scroll,thumbVisibility:true,thickness:5,
                  child:ListView.builder(
                    controller:_scroll,
                    padding:const EdgeInsets.fromLTRB(12,8,12,80),
                    itemCount:_items.length+(_loadingMore?1:0),
                    itemBuilder:(_,i){
                      if(i>=_items.length) return const Padding(padding:EdgeInsets.all(16),
                        child:Center(child:SizedBox(width:20,height:20,
                          child:CircularProgressIndicator(strokeWidth:2,color:_kPrimary))));
                      final item=_items[i]; final isSelected=widget.selectedId==item['id'];
                      final szId=item['id'] as int;
                      final jobActive=widget.showAssignButton &&
                          _activeJobs.containsKey(szId) &&
                          (_activeJobs[szId]!.status=='running'||_activeJobs[szId]!.status=='pending');
                      return ValueListenableBuilder<int>(
                        valueListenable:_jobNotifier,
                        builder:(_,__,___)=>_ItemCard(
                          item:item,color:widget.color,icon:widget.icon,
                          isSelected:isSelected,
                          showAssignButton:widget.showAssignButton,
                          jobRunning:jobActive,
                          jobProgress:jobActive?_activeJobs[szId]?.progress:null,
                          jobDoneText:jobActive?'${_activeJobs[szId]?.doneCenters??0}/${_activeJobs[szId]?.totalCenters??0}':null,
                          activeElectionId:widget.election.id,
                          onTap:()=>widget.onSelect(item),
                          onEdit:()=>_openDialog(existing:item),
                          onDelete:()=>_delete(item),
                          onAssign:widget.showAssignButton?()=>_startAssignJob(item):null,
                          onRefresh:widget.showAssignButton?()=>_refreshDuties(item):null,
                          onLock:widget.showAssignButton?()=>_lockSZ(item):null));
                    })))),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ITEM CARD — Super Zone level
//  FIX: Duty counts now use per-CENTER logic (1 manak set per center, not per booth)
//       Backend fields: assignedBooths = duty_assignments COUNT
//                       totalBooths    = SUM of required staff PER CENTER (1 set each)
// ═══════════════════════════════════════════════════════════════════════════════

class _ItemCard extends StatelessWidget {
  final Map item; final Color color; final IconData icon;
  final bool isSelected, showAssignButton, jobRunning;
  final double? jobProgress; final String? jobDoneText;
  final int? activeElectionId;
  final VoidCallback onTap, onEdit, onDelete;
  final VoidCallback? onAssign, onRefresh, onLock;

  const _ItemCard({
    required this.item, required this.color, required this.icon,
    required this.isSelected, required this.onTap, required this.onEdit, required this.onDelete,
    this.showAssignButton=false, this.jobRunning=false,
    this.jobProgress, this.jobDoneText, this.activeElectionId,
    this.onAssign, this.onRefresh, this.onLock});

  // ── FIX: Read duty counts from backend fields correctly ───────────────────
  // Backend `get_super_zones` returns:
  //   assignedBooths = COUNT(duty_assignments) under this SZ
  //   totalBooths    = SUM of manak-required staff across all centers (1 set each)
  //   dutyFullyAssigned = bool from backend
  int _assignedCount() {
    // Try explicit fields first
    for (final k in ['assignedBooths','assigned_booths','assigned_count','assignedDuties','dutyCount','duty_count']) {
      final v = item[k];
      if (v != null) return (v as num).toInt();
    }
    return 0;
  }

  int _requiredCount() {
    // totalBooths = total required manak staff (NOT booth_count multiplied!)
    for (final k in ['totalBooths','total_booths','requiredBooths','required_count']) {
      final v = item[k];
      if (v != null) return (v as num).toInt();
    }
    return 0;
  }

  bool _isDutyFull() {
    // Trust backend flag first (most accurate)
    for (final k in ['dutyFullyAssigned','duty_fully_assigned','allAssigned','all_assigned','isFullyAssigned']) {
      final v = item[k];
      if (v != null) {
        if (v is bool) return v;
        if (v is int)  return v == 1;
      }
    }
    // Fallback: compute locally
    final t = _requiredCount();
    final a = _assignedCount();
    return t > 0 && a >= t;
  }

  bool _isDutyPartial() {
    final a = _assignedCount();
    if (a <= 0) return false;
    if (_isDutyFull()) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final officers   = (item['officers'] as List?)?.cast<Map>()??[];
    final isLocked   = (item['is_locked'] as num? ??0)==1;
    final centerCount= (item['center_count'] as num? ?? item['centerCount'] as num? ?? 0).toInt();
    final dutyFull   = showAssignButton && _isDutyFull();
    final dutyPartial= showAssignButton && !dutyFull && _isDutyPartial();
    final assignedB  = _assignedCount();
    final totalB     = _requiredCount();

    return GestureDetector(
      onTap:onTap,
      child:AnimatedContainer(
        duration:const Duration(milliseconds:150),
        margin:const EdgeInsets.only(bottom:8),
        decoration:BoxDecoration(
          color:isSelected?color.withOpacity(0.07):Colors.white,
          borderRadius:BorderRadius.circular(12),
          border:Border.all(
            color:jobRunning?_kOrange
                :dutyFull&&!isSelected?_kSuccess.withOpacity(0.45)
                :isLocked?_kSuccess.withOpacity(0.4)
                :isSelected?color:_kBorder.withOpacity(0.4),
            width:isSelected||jobRunning||dutyFull?1.5:1),
          boxShadow:[BoxShadow(color:color.withOpacity(0.05),blurRadius:6,offset:const Offset(0,2))]),
        child:Padding(
          padding:const EdgeInsets.fromLTRB(10,10,8,10),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
              // Avatar + duty dot
              Stack(clipBehavior:Clip.none,children:[
                Container(width:38,height:38,
                  decoration:BoxDecoration(
                    color:jobRunning?_kOrange.withOpacity(0.15):color.withOpacity(0.12),
                    shape:BoxShape.circle,
                    border:Border.all(color:jobRunning?_kOrange.withOpacity(0.4):color.withOpacity(0.3))),
                  child:jobRunning
                    ? const Center(child:SizedBox(width:16,height:16,
                        child:CircularProgressIndicator(strokeWidth:2,color:_kOrange)))
                    : Icon(isSelected?Icons.check_circle_rounded:icon,color:color,size:18)),
                if(showAssignButton&&!jobRunning)
                  Positioned(bottom:-2,right:-2,
                    child:_DutyDot(full:dutyFull,partial:dutyPartial)),
              ]),
              const SizedBox(width:10),
              // Content
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                // Name row
                Row(children:[
                  Expanded(child:Text(item['name']??'',maxLines:1,overflow:TextOverflow.ellipsis,
                      style:TextStyle(color:isSelected?color:_kDark,fontWeight:FontWeight.w700,fontSize:14))),
                  if(showAssignButton&&!jobRunning) ...[
                    const SizedBox(width:6),
                    _DutyStatusPill(full:dutyFull,partial:dutyPartial,assigned:assignedB,total:totalB),
                  ],
                  if(isLocked) Container(margin:const EdgeInsets.only(left:4),
                    padding:const EdgeInsets.symmetric(horizontal:5,vertical:2),
                    decoration:BoxDecoration(color:_kSuccess.withOpacity(0.1),borderRadius:BorderRadius.circular(5),
                        border:Border.all(color:_kSuccess.withOpacity(0.4))),
                    child:const Row(mainAxisSize:MainAxisSize.min,children:[
                      Icon(Icons.lock,size:9,color:_kSuccess),SizedBox(width:2),
                      Text('Lock',style:TextStyle(color:_kSuccess,fontSize:8,fontWeight:FontWeight.w700))])),
                  if(isSelected&&!isLocked) Container(margin:const EdgeInsets.only(left:4),
                    padding:const EdgeInsets.symmetric(horizontal:5,vertical:2),
                    decoration:BoxDecoration(color:color.withOpacity(0.12),borderRadius:BorderRadius.circular(5),
                        border:Border.all(color:color.withOpacity(0.3))),
                    child:Text('✓',style:TextStyle(color:color,fontSize:9,fontWeight:FontWeight.w800))),
                ]),
                const SizedBox(height:3),
                // Meta tags
                Wrap(spacing:8,runSpacing:2,children:[
                  if((item['district'] as String?)?.isNotEmpty==true) _tag(Icons.location_city_outlined,item['district'] as String),
                  if((item['block'] as String?)?.isNotEmpty==true) _tag(Icons.domain_outlined,item['block'] as String),
                  if((item['hqAddress'] as String?)?.isNotEmpty==true) _tag(Icons.home_outlined,item['hqAddress'] as String),
                  if(item['zoneCount']!=null) _tag(Icons.grid_view_outlined,'${item['zoneCount']} Zones'),
                  if(item['sectorCount']!=null) _tag(Icons.view_module_outlined,'${item['sectorCount']} Sectors'),
                  if(item['gpCount']!=null) _tag(Icons.account_balance_outlined,'${item['gpCount']} GPs'),
                  if(centerCount>0) _tag(Icons.location_on_outlined,'$centerCount Centers'),
                ]),
                // Job progress strip
                if(jobRunning&&jobDoneText!=null)...[
                  const SizedBox(height:6),
                  Row(children:[
                    Expanded(child:LinearProgressIndicator(
                      value:jobProgress??0,
                      backgroundColor:_kOrange.withOpacity(0.15),
                      valueColor:const AlwaysStoppedAnimation<Color>(_kOrange),
                      minHeight:4)),
                    const SizedBox(width:6),
                    Text(jobDoneText??'',style:const TextStyle(color:_kOrange,fontSize:9,fontWeight:FontWeight.w700)),
                  ]),
                ],
                // Duty progress strip — only show when totalB > 0 (manak set)
                if(showAssignButton&&!jobRunning&&totalB>0)...[
                  const SizedBox(height:6),
                  _DutyProgressStrip(assigned:assignedB,total:totalB,full:dutyFull,partial:dutyPartial),
                ],
                // No manak set warning
                if(showAssignButton&&!jobRunning&&totalB==0&&centerCount>0)...[
                  const SizedBox(height:4),
                  Row(children:[
                    const Icon(Icons.info_outline,size:10,color:_kSubtle),const SizedBox(width:4),
                    const Text('मानक (Booth Rules) सेट नहीं — duty count N/A',
                        style:TextStyle(color:_kSubtle,fontSize:9)),
                  ]),
                ],
                // Officer chips
                if(officers.isNotEmpty)...[
                  const SizedBox(height:5),
                  Wrap(spacing:4,runSpacing:3,children:officers.take(2).map((o){
                    final oEId=(o['electionId'] as num?)?.toInt();
                    final isOld=activeElectionId!=null&&oEId!=null&&oEId!=activeElectionId;
                    return Container(
                      padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
                      decoration:BoxDecoration(
                        color:isOld?_kAmber.withOpacity(0.08):color.withOpacity(0.06),
                        borderRadius:BorderRadius.circular(6),
                        border:Border.all(color:isOld?_kAmber.withOpacity(0.4):color.withOpacity(0.2))),
                      child:Row(mainAxisSize:MainAxisSize.min,children:[
                        Icon(isOld?Icons.history:Icons.person_outline,size:9,color:isOld?_kAmber:color),
                        const SizedBox(width:3),
                        ConstrainedBox(constraints:const BoxConstraints(maxWidth:75),
                          child:Text(o['name']??'',style:TextStyle(color:isOld?_kAmber:color,fontSize:10,
                              fontWeight:FontWeight.w600),maxLines:1,overflow:TextOverflow.ellipsis)),
                        if((o['rank']??'').isNotEmpty)...[
                          const SizedBox(width:2),
                          Text('(${o['rank']})',style:TextStyle(color:isOld?_kAmber.withOpacity(0.7):_kSubtle,fontSize:8)),
                        ],
                        if(isOld)...[const SizedBox(width:3),
                          Container(padding:const EdgeInsets.symmetric(horizontal:3,vertical:1),
                            decoration:BoxDecoration(color:_kAmber.withOpacity(0.15),borderRadius:BorderRadius.circular(3)),
                            child:const Text('पुराना',style:TextStyle(color:_kAmber,fontSize:7,fontWeight:FontWeight.w800)))],
                      ]));
                  }).toList()),
                  if(officers.length>2) Text('+${officers.length-2} more',style:TextStyle(color:color,fontSize:9)),
                ],
              ])),
              // Edit/Delete
              Column(mainAxisSize:MainAxisSize.min,children:[
                _iconBtn(Icons.edit_outlined,_kInfo,onEdit),
                const SizedBox(height:4),
                _iconBtn(Icons.delete_outline,_kError,onDelete),
              ]),
            ]),
            // Action buttons (SZ level only)
            if(showAssignButton)...[
              const SizedBox(height:8),
              Row(children:[
                Expanded(child:_actionBtn(
                  icon:jobRunning?Icons.sync:Icons.assignment_outlined,
                  label:jobRunning?'Running...':'Assign',
                  color:_kOrange, enabled:!jobRunning&&!isLocked, onTap:onAssign)),
                const SizedBox(width:5),
                Expanded(child:_actionBtn(
                  icon:Icons.cleaning_services_outlined,label:'Clear',
                  color:_kInfo, enabled:!isLocked, onTap:onRefresh)),
                const SizedBox(width:5),
                Expanded(child:_actionBtn(
                  icon:isLocked?Icons.lock_open:Icons.lock,
                  label:isLocked?'Unlock':'Lock',
                  color:isLocked?_kError:_kSuccess, onTap:onLock)),
              ]),
            ],
          ])),
      ),
    );
  }

  Widget _actionBtn({required IconData icon, required String label, required Color color,
      bool enabled=true, VoidCallback? onTap}) =>
    GestureDetector(onTap:enabled?onTap:null,
      child:AnimatedContainer(duration:const Duration(milliseconds:120),
        padding:const EdgeInsets.symmetric(vertical:7),
        decoration:BoxDecoration(
          color:enabled?color.withOpacity(0.08):Colors.grey.withOpacity(0.06),
          borderRadius:BorderRadius.circular(8),
          border:Border.all(color:enabled?color.withOpacity(0.35):Colors.grey.withOpacity(0.2))),
        child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[
          Icon(icon,size:12,color:enabled?color:Colors.grey),const SizedBox(width:3),
          Flexible(child:Text(label,style:TextStyle(color:enabled?color:Colors.grey,fontSize:10,
              fontWeight:FontWeight.w700),maxLines:1,overflow:TextOverflow.ellipsis))])));

  Widget _tag(IconData icon, String text) =>
    Row(mainAxisSize:MainAxisSize.min,children:[
      Icon(icon,size:9,color:_kSubtle),const SizedBox(width:2),
      ConstrainedBox(constraints:const BoxConstraints(maxWidth:110),
        child:Text(text,style:const TextStyle(color:_kSubtle,fontSize:10),
            maxLines:1,overflow:TextOverflow.ellipsis))]);

  Widget _iconBtn(IconData icon, Color c, VoidCallback onTap) =>
    GestureDetector(onTap:onTap,child:Container(width:30,height:30,
      decoration:BoxDecoration(color:c.withOpacity(0.08),borderRadius:BorderRadius.circular(8),
          border:Border.all(color:c.withOpacity(0.25))),
      child:Icon(icon,size:14,color:c)));
}

// ── Duty status widgets ───────────────────────────────────────────────────────

class _DutyDot extends StatelessWidget {
  final bool full, partial;
  const _DutyDot({required this.full, required this.partial});

  @override
  Widget build(BuildContext context) {
    final color=full?_kSuccess:partial?_kAmber:_kError;
    return AnimatedContainer(
      duration:const Duration(milliseconds:300),
      width:13,height:13,
      decoration:BoxDecoration(color:color,shape:BoxShape.circle,
          border:Border.all(color:Colors.white,width:1.5),
          boxShadow:[BoxShadow(color:color.withOpacity(0.5),blurRadius:3)]),
      child:Center(child:Icon(full?Icons.check:partial?Icons.more_horiz:Icons.close,
          size:7,color:Colors.white)));
  }
}

class _DutyStatusPill extends StatelessWidget {
  final bool full, partial; final int assigned, total;
  const _DutyStatusPill({required this.full,required this.partial,required this.assigned,required this.total});

  @override
  Widget build(BuildContext context) {
    Color bg,border,fg; String label;
    if(full){
      bg=_kSuccess.withOpacity(0.10);border=_kSuccess.withOpacity(0.40);fg=_kSuccess;
      label=total>0?'$assigned/$total ✓':'पूर्ण ✓';
    } else if(partial){
      bg=_kAmber.withOpacity(0.10);border=_kAmber.withOpacity(0.40);fg=_kAmber;
      label=total>0?'$assigned/$total':'$assigned असाइन';
    } else if(total>0){
      bg=_kError.withOpacity(0.08);border=_kError.withOpacity(0.30);fg=_kError;
      label='0/$total';
    } else {
      bg=_kSubtle.withOpacity(0.08);border=_kSubtle.withOpacity(0.20);fg=_kSubtle;
      label='N/A';
    }
    return AnimatedContainer(duration:const Duration(milliseconds:300),
      padding:const EdgeInsets.symmetric(horizontal:5,vertical:2),
      decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(20),border:Border.all(color:border)),
      child:Text(label,style:TextStyle(color:fg,fontSize:8,fontWeight:FontWeight.w800)));
  }
}

class _DutyProgressStrip extends StatelessWidget {
  final int assigned, total; final bool full, partial;
  const _DutyProgressStrip({required this.assigned,required this.total,required this.full,required this.partial});

  @override
  Widget build(BuildContext context) {
    final ratio=total>0?(assigned/total).clamp(0.0,1.0):0.0;
    final color=full?_kSuccess:partial?_kAmber:_kError;
    final hint=full?'सभी centers पर duty असाइन ✓'
        :partial?'$assigned/$total staff असाइन — अधूरा'
        :'कोई duty असाइन नहीं — "Assign" दबाएं';
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      ClipRRect(borderRadius:BorderRadius.circular(4),child:Stack(children:[
        Container(height:4,color:color.withOpacity(0.12)),
        AnimatedFractionallySizedBox(duration:const Duration(milliseconds:600),curve:Curves.easeOut,
          widthFactor:ratio,
          child:Container(height:4,decoration:BoxDecoration(color:color,borderRadius:BorderRadius.circular(4)))),
      ])),
      const SizedBox(height:2),
      Text(hint,style:TextStyle(color:color,fontSize:8,fontWeight:FontWeight.w600)),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SHORTAGE RESOLUTION SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class _ShortageResolutionSheet extends StatefulWidget {
  final int szId; final String szName;
  final Map<String,dynamic> shortageReport; final VoidCallback onResolved;
  const _ShortageResolutionSheet({required this.szId,required this.szName,
    required this.shortageReport,required this.onResolved});
  @override State<_ShortageResolutionSheet> createState() => _ShortageResolutionSheetState();
}

class _ShortageResolutionSheetState extends State<_ShortageResolutionSheet> {
  bool _disposed=false;
  @override void dispose(){_disposed=true;super.dispose();}

  Map<String,dynamic> get _perCenter => widget.shortageReport['perCenter'] as Map<String,dynamic>? ?? {};
  int get _totalCenters => widget.shortageReport['totalCenters'] as int? ?? 0;
  int get _centersWithShortage => widget.shortageReport['centersWithShortage'] as int? ?? 0;
  int get _totalAssigned => widget.shortageReport['totalAssigned'] as int? ?? 0;

  void _openCenterShortage(Map<String,dynamic> centerData) {
    if(_disposed||!mounted)return;
    showModalBottomSheet(context:context,isScrollControlled:true,backgroundColor:Colors.transparent,
      builder:(_)=>_CenterShortageSheet(
        centerId:centerData['centerId'] as int,
        centerName:centerData['centerName'] as String? ?? '',
        sensitivity:centerData['sensitivity'] as String? ?? 'C',
        boothCount:centerData['boothCount'] as int? ?? 1,
        shortages:(centerData['shortages'] as List?)?.cast<Map<String,dynamic>>()??[],
        onResolved:(){if(!_disposed&&mounted)widget.onResolved();}));
  }

  @override
  Widget build(BuildContext context) {
    final centers=_perCenter.values.toList().cast<Map<String,dynamic>>();
    return Container(
      height:MediaQuery.of(context).size.height*0.9,
      decoration:const BoxDecoration(color:_kBg,borderRadius:BorderRadius.vertical(top:Radius.circular(20))),
      child:Column(children:[
        Container(margin:const EdgeInsets.only(top:10,bottom:4),width:40,height:4,
          decoration:BoxDecoration(color:_kBorder.withOpacity(0.5),borderRadius:BorderRadius.circular(2))),
        Padding(padding:const EdgeInsets.fromLTRB(16,8,16,10),child:Row(children:[
          Container(padding:const EdgeInsets.all(8),
            decoration:BoxDecoration(color:_kAmber.withOpacity(0.12),borderRadius:BorderRadius.circular(10)),
            child:const Icon(Icons.warning_amber_rounded,color:_kAmber,size:20)),
          const SizedBox(width:10),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('Shortage Report',style:TextStyle(color:_kDark,fontWeight:FontWeight.w800,fontSize:15)),
            Text(widget.szName,style:const TextStyle(color:_kSubtle,fontSize:11)),
          ])),
          GestureDetector(onTap:()=>Navigator.pop(context),
            child:Container(padding:const EdgeInsets.all(6),
              decoration:BoxDecoration(color:_kSubtle.withOpacity(0.1),borderRadius:BorderRadius.circular(8)),
              child:const Icon(Icons.close,size:18,color:_kSubtle))),
        ])),
        Container(margin:const EdgeInsets.fromLTRB(16,0,16,10),
          padding:const EdgeInsets.all(12),
          decoration:BoxDecoration(color:_kAmber.withOpacity(0.08),borderRadius:BorderRadius.circular(10),
              border:Border.all(color:_kAmber.withOpacity(0.3))),
          child:Row(children:[
            Expanded(child:_statCol('$_totalCenters','कुल Centers',_kDark)),
            Container(width:1,height:36,color:_kBorder.withOpacity(0.3)),
            Expanded(child:_statCol('$_totalAssigned','Assigned',_kSuccess)),
            Container(width:1,height:36,color:_kBorder.withOpacity(0.3)),
            Expanded(child:_statCol('$_centersWithShortage','Shortage',_kError)),
          ])),
        Container(margin:const EdgeInsets.fromLTRB(16,0,16,10),
          padding:const EdgeInsets.all(9),
          decoration:BoxDecoration(color:_kInfo.withOpacity(0.07),borderRadius:BorderRadius.circular(8),
              border:Border.all(color:_kInfo.withOpacity(0.2))),
          child:const Row(children:[
            Icon(Icons.info_outline,size:13,color:_kInfo),SizedBox(width:6),
            Expanded(child:Text('Shortage center पर tap करें — substitute rank चुनें। मानक में बदलाव नहीं होगा।',
                style:TextStyle(color:_kInfo,fontSize:11)))])),
        Expanded(child:centers.isEmpty
          ? const Center(child:Text('सभी centers असाइन हो गए ✓',
              style:TextStyle(color:_kSuccess,fontSize:14,fontWeight:FontWeight.w700)))
          : ListView.builder(
              padding:const EdgeInsets.fromLTRB(16,0,16,20),
              itemCount:centers.length,
              itemBuilder:(_,i){
                final c=centers[i];
                final shortages=(c['shortages'] as List?)?.cast<Map<String,dynamic>>()??[];
                return GestureDetector(
                  onTap:()=>_openCenterShortage(c),
                  child:Container(margin:const EdgeInsets.only(bottom:8),
                    padding:const EdgeInsets.all(12),
                    decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(12),
                        border:Border.all(color:_kError.withOpacity(0.3))),
                    child:Row(children:[
                      Container(width:38,height:38,
                        decoration:BoxDecoration(color:_kError.withOpacity(0.1),shape:BoxShape.circle,
                            border:Border.all(color:_kError.withOpacity(0.3))),
                        child:Center(child:Text(c['sensitivity'] as String? ?? 'C',
                            style:const TextStyle(color:_kError,fontWeight:FontWeight.w900,fontSize:12)))),
                      const SizedBox(width:10),
                      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                        Text(c['centerName'] as String? ?? '',
                            style:const TextStyle(color:_kDark,fontWeight:FontWeight.w700,fontSize:13),
                            maxLines:1,overflow:TextOverflow.ellipsis),
                        Text('${c['boothCount']} बूथ • ${shortages.length} shortage',
                            style:const TextStyle(color:_kSubtle,fontSize:11)),
                        const SizedBox(height:3),
                        Wrap(spacing:4,runSpacing:2,children:shortages.take(3).map((s){
                          final missing=s['missing'] as int? ??0;
                          final ls=s['labelShort'] as String? ?? s['rank'] as String? ?? '';
                          final la=s['labelArmed'] as String? ?? (s['armed']==true?'सशस्त्र':'निःशस्त्र');
                          return Container(
                            padding:const EdgeInsets.symmetric(horizontal:5,vertical:1),
                            decoration:BoxDecoration(color:_kError.withOpacity(0.08),borderRadius:BorderRadius.circular(4)),
                            child:Text('$ls ($la): $missing कम',
                                style:const TextStyle(color:_kError,fontSize:9,fontWeight:FontWeight.w700)));
                        }).toList()),
                      ])),
                      Container(padding:const EdgeInsets.all(5),
                        decoration:BoxDecoration(color:_kInfo.withOpacity(0.1),borderRadius:BorderRadius.circular(7)),
                        child:const Icon(Icons.arrow_forward_ios,size:11,color:_kInfo)),
                    ])));
              })),
      ]));
  }
  Widget _statCol(String val,String label,Color color)=>Column(children:[
    Text(val,style:TextStyle(color:color,fontSize:18,fontWeight:FontWeight.w900)),
    const SizedBox(height:2),
    Text(label,style:const TextStyle(color:_kSubtle,fontSize:10))]);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CENTER SHORTAGE SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class _CenterShortageSheet extends StatefulWidget {
  final int centerId; final String centerName, sensitivity;
  final int boothCount;
  final List<Map<String,dynamic>> shortages;
  final VoidCallback onResolved;
  const _CenterShortageSheet({required this.centerId,required this.centerName,
    required this.sensitivity,required this.boothCount,required this.shortages,
    required this.onResolved});
  @override State<_CenterShortageSheet> createState()=>_CenterShortageSheetState();
}

class _CenterShortageSheetState extends State<_CenterShortageSheet> {
  bool _disposed=false,_saving=false,_loadingInfo=true;
  List<Map<String,dynamic>> _requirements=[];
  List<Map<String,dynamic>> _pool=[];
  final Map<int,List<_SubSlot>> _overrides={};

  @override void initState(){super.initState();_loadShortageInfo();}
  @override void dispose(){_disposed=true;super.dispose();}

  Future<void> _loadShortageInfo() async {
    try {
      final token=await AuthService.getToken();
      final res=await ApiService.get('/admin/center/${widget.centerId}/shortage-info',token:token);
      final data=res['data'] as Map<String,dynamic>?;
      if(!_disposed&&mounted){
        setState((){
          _requirements=(data?['requirements'] as List?)?.cast<Map<String,dynamic>>()??[];
          _pool=(data?['pool'] as List?)?.cast<Map<String,dynamic>>()??[];
          _loadingInfo=false;
          for(int i=0;i<_requirements.length;i++){
            if((_requirements[i]['missing'] as int? ??0)>0)
              _overrides[i]=[_SubSlot(count:_requirements[i]['missing'] as int? ??0)];
          }
        });
      }
    } catch(_){if(!_disposed&&mounted)setState(()=>_loadingInfo=false);}
  }

  Future<void> _saveOverrides() async {
    final subs=<Map<String,dynamic>>[];
    for(final entry in _overrides.entries){
      if(entry.key>=_requirements.length)continue;
      final req=_requirements[entry.key];
      for(final sub in entry.value){
        if(sub.rank.isEmpty||sub.count<=0)continue;
        subs.add({'originalRank':req['rank'],'originalArmed':req['armed'],
          'substituteRank':sub.rank,'substituteArmed':sub.armed,'count':sub.count});
      }
    }
    if(subs.isEmpty){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:Text('कोई override नहीं चुना गया'),backgroundColor:_kAmber,behavior:SnackBarBehavior.floating));
      return;
    }
    setState(()=>_saving=true);
    try {
      final token=await AuthService.getToken();
      final substitutions=<Map<String,dynamic>>[];
      for(final s in subs){
        substitutions.add({'rank':s['originalRank'],'armed':s['originalArmed'],
          'replacements':[{'rank':s['substituteRank'],'armed':s['substituteArmed'],'count':s['count']}]});
      }
      final res=await ApiService.post('/admin/center/${widget.centerId}/assign-override',
          {'substitutions':substitutions},token:token);
      final inserted=(res['data']?['inserted'] as num?)?.toInt()??0;
      final failures=res['data']?['failures'] as List?;
      if(!_disposed&&mounted){
        Navigator.pop(context);
        widget.onResolved();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:Text('$inserted staff असाइन किए${failures!=null&&failures.isNotEmpty?" (${failures.length} failed)":""}'),
          backgroundColor:failures!=null&&failures.isNotEmpty?_kAmber:_kSuccess,
          behavior:SnackBarBehavior.floating));
      }
    } catch(e){
      if(!_disposed&&mounted){
        setState(()=>_saving=false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:Text('Error: $e'),backgroundColor:_kError,behavior:SnackBarBehavior.floating));
      }
    }
  }

  void _openSubstitutePicker(int slotIdx) async {
    final req=_requirements[slotIdx];
    final result=await showModalBottomSheet<_SubSlot>(
      context:context,isScrollControlled:true,backgroundColor:Colors.transparent,
      builder:(_)=>_SubstitutePickerSheet(
        originalRank:req['rank'] as String? ?? '',
        originalArmed:req['armed'] as bool? ?? false,
        missing:req['missing'] as int? ?? 0,
        pool:_pool));
    if(result!=null&&!_disposed&&mounted)
      setState((){_overrides.putIfAbsent(slotIdx,()=>[]).add(result);});
  }

  void _removeOverride(int slotIdx,int subIdx){
    if(!_disposed&&mounted) setState((){_overrides[slotIdx]?.removeAt(subIdx);});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height:MediaQuery.of(context).size.height*0.92,
      decoration:const BoxDecoration(color:_kBg,borderRadius:BorderRadius.vertical(top:Radius.circular(20))),
      child:Column(children:[
        Container(margin:const EdgeInsets.only(top:10,bottom:4),width:40,height:4,
          decoration:BoxDecoration(color:_kBorder.withOpacity(0.5),borderRadius:BorderRadius.circular(2))),
        Padding(padding:const EdgeInsets.fromLTRB(16,8,16,10),child:Row(children:[
          Container(padding:const EdgeInsets.all(7),
            decoration:BoxDecoration(color:_kError.withOpacity(0.1),borderRadius:BorderRadius.circular(8)),
            child:const Icon(Icons.warning_amber_rounded,color:_kError,size:18)),
          const SizedBox(width:10),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('Shortage Resolution',style:TextStyle(color:_kDark,fontWeight:FontWeight.w800,fontSize:14)),
            Text('${widget.centerName} • ${widget.sensitivity}',
                style:const TextStyle(color:_kSubtle,fontSize:10),maxLines:1,overflow:TextOverflow.ellipsis),
          ])),
          GestureDetector(onTap:()=>Navigator.pop(context),
            child:const Icon(Icons.close,color:_kSubtle,size:20)),
        ])),
        Container(margin:const EdgeInsets.fromLTRB(16,0,16,10),
          padding:const EdgeInsets.all(9),
          decoration:BoxDecoration(color:_kAmber.withOpacity(0.08),borderRadius:BorderRadius.circular(8),
              border:Border.all(color:_kAmber.withOpacity(0.3))),
          child:const Row(children:[
            Icon(Icons.info_outline,size:13,color:_kAmber),SizedBox(width:6),
            Expanded(child:Text('Substitute ranks सिर्फ इस center के लिए। मानक में बदलाव नहीं।',
                style:TextStyle(color:Color(0xFF92400E),fontSize:11)))])),
        Expanded(child:_loadingInfo
          ? const Center(child:CircularProgressIndicator(color:_kPrimary))
          : ListView.builder(
              padding:const EdgeInsets.fromLTRB(16,0,16,100),
              itemCount:_requirements.length,
              itemBuilder:(_,i){
                final req=_requirements[i];
                final required=req['required'] as int? ??0;
                final assigned=req['assigned'] as int? ??0;
                final missing=req['missing'] as int? ??0;
                final ls=req['labelShort'] as String? ??'';
                final la=req['labelArmed'] as String? ??'';
                final overrides=_overrides[i]??[];
                final overrideSum=overrides.fold<int>(0,(s,o)=>s+o.count);
                final stillMissing=(missing-overrideSum).clamp(0,missing);
                final isResolved=stillMissing==0;
                return Container(margin:const EdgeInsets.only(bottom:10),
                  decoration:BoxDecoration(
                    color:isResolved?_kSuccess.withOpacity(0.04):Colors.white,
                    borderRadius:BorderRadius.circular(12),
                    border:Border.all(color:isResolved?_kSuccess.withOpacity(0.4):_kBorder.withOpacity(0.4))),
                  child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Padding(padding:const EdgeInsets.fromLTRB(12,10,12,8),child:Row(children:[
                      Container(width:34,height:34,
                        decoration:BoxDecoration(
                          color:(isResolved?_kSuccess:missing>0?_kError:_kSuccess).withOpacity(0.12),
                          shape:BoxShape.circle),
                        child:Center(child:Icon(
                          isResolved?Icons.check_circle_rounded:missing>0?Icons.close:Icons.check_circle_rounded,
                          size:18,color:isResolved?_kSuccess:missing>0?_kError:_kSuccess))),
                      const SizedBox(width:10),
                      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                        Text('$ls — $la',style:const TextStyle(color:_kDark,fontWeight:FontWeight.w700,fontSize:13)),
                        Text('Required: $required  |  Assigned: $assigned  |  Missing: $missing',
                            style:const TextStyle(color:_kSubtle,fontSize:11)),
                      ])),
                      if(missing>0&&!isResolved)
                        GestureDetector(onTap:()=>_openSubstitutePicker(i),
                          child:Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:5),
                            decoration:BoxDecoration(color:_kInfo.withOpacity(0.1),borderRadius:BorderRadius.circular(8),
                                border:Border.all(color:_kInfo.withOpacity(0.3))),
                            child:const Row(mainAxisSize:MainAxisSize.min,children:[
                              Icon(Icons.person_add_outlined,size:13,color:_kInfo),SizedBox(width:4),
                              Text('Substitute',style:TextStyle(color:_kInfo,fontSize:11,fontWeight:FontWeight.w700))]))),
                    ])),
                    if(overrides.isNotEmpty)...[
                      const Divider(height:1,color:Color(0xFFE8D5A3)),
                      Padding(padding:const EdgeInsets.fromLTRB(12,6,12,8),child:Column(
                        crossAxisAlignment:CrossAxisAlignment.start,children:[
                        const Text('Substitutes:',style:TextStyle(color:_kSubtle,fontSize:10,fontWeight:FontWeight.w700)),
                        const SizedBox(height:4),
                        for(int si=0;si<overrides.length;si++) Padding(
                          padding:const EdgeInsets.only(bottom:4),
                          child:Row(children:[
                            Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
                              decoration:BoxDecoration(color:_kInfo.withOpacity(0.07),borderRadius:BorderRadius.circular(7),
                                  border:Border.all(color:_kInfo.withOpacity(0.2))),
                              child:Text('${overrides[si].rank} (${overrides[si].armed?"सशस्त्र":"निःशस्त्र"}) × ${overrides[si].count}',
                                  style:const TextStyle(color:_kInfo,fontSize:11,fontWeight:FontWeight.w600))),
                            const SizedBox(width:6),
                            GestureDetector(onTap:()=>_removeOverride(i,si),
                              child:const Icon(Icons.remove_circle_outline,size:16,color:_kError)),
                          ])),
                        if(stillMissing>0) Text('अभी भी $stillMissing और चाहिए',
                            style:const TextStyle(color:_kError,fontSize:10,fontWeight:FontWeight.w600)),
                      ])),
                    ],
                  ]));
              })),
        Container(padding:const EdgeInsets.fromLTRB(16,10,16,16),
          decoration:BoxDecoration(color:_kBg,border:Border(top:BorderSide(color:_kBorder.withOpacity(0.4)))),
          child:SizedBox(width:double.infinity,height:50,
            child:ElevatedButton.icon(
              onPressed:_saving?null:_saveOverrides,
              icon:_saving?const SizedBox(width:18,height:18,
                  child:CircularProgressIndicator(strokeWidth:2,color:Colors.white))
                  :const Icon(Icons.assignment_turned_in_outlined,size:18),
              label:Text(_saving?'असाइन हो रहा है...':'Override असाइन करें',
                  style:const TextStyle(fontSize:14,fontWeight:FontWeight.w800)),
              style:ElevatedButton.styleFrom(backgroundColor:_kOrange,foregroundColor:Colors.white,
                shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)))))),
      ]));
  }
}

class _SubSlot {
  String rank; bool armed; int count;
  _SubSlot({this.rank='',this.armed=false,required this.count});
}

// ── Substitute Picker Sheet ───────────────────────────────────────────────────

class _SubstitutePickerSheet extends StatefulWidget {
  final String originalRank; final bool originalArmed;
  final int missing; final List<Map<String,dynamic>> pool;
  const _SubstitutePickerSheet({required this.originalRank,required this.originalArmed,
    required this.missing,required this.pool});
  @override State<_SubstitutePickerSheet> createState()=>_SubstitutePickerSheetState();
}

class _SubstitutePickerSheetState extends State<_SubstitutePickerSheet> {
  String _selectedRank=''; bool _selectedArmed=false; int _count=1;

  @override
  Widget build(BuildContext context) {
    final poolByRankArmed=<String,int>{};
    for(final p in widget.pool){
      final r=p['rank'] as String? ??'';
      final arm=p['armed'] as bool? ??false;
      final av=p['available'] as int? ??0;
      if(r.isNotEmpty&&av>0) poolByRankArmed['$r|${arm?1:0}']= av;
    }

    return Container(
      height:MediaQuery.of(context).size.height*0.7,
      decoration:const BoxDecoration(color:_kBg,borderRadius:BorderRadius.vertical(top:Radius.circular(20))),
      child:Column(children:[
        Container(margin:const EdgeInsets.only(top:10,bottom:4),width:40,height:4,
          decoration:BoxDecoration(color:_kBorder.withOpacity(0.5),borderRadius:BorderRadius.circular(2))),
        Padding(padding:const EdgeInsets.fromLTRB(16,8,16,10),child:Row(children:[
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('Substitute चुनें',style:TextStyle(color:_kDark,fontWeight:FontWeight.w800,fontSize:15)),
            Text('${widget.originalRank} के लिए — ${widget.missing} की जरूरत',
                style:const TextStyle(color:_kSubtle,fontSize:11)),
          ])),
          GestureDetector(onTap:()=>Navigator.pop(context),child:const Icon(Icons.close,color:_kSubtle,size:20)),
        ])),
        SizedBox(height:44,
          child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:16),
            children:poolByRankArmed.entries.map((e){
              final parts=e.key.split('|'); final r=parts[0]; final arm=parts[1]=='1';
              final av=e.value; final color=_kRankColors[r]??_kPrimary;
              final sel=_selectedRank==r&&_selectedArmed==arm;
              return GestureDetector(
                onTap:()=>setState((){_selectedRank=r;_selectedArmed=arm;_count=1;}),
                child:Container(margin:const EdgeInsets.only(right:6),
                  padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),
                  decoration:BoxDecoration(
                    color:sel?color:Colors.white,borderRadius:BorderRadius.circular(20),
                    border:Border.all(color:sel?color:_kBorder.withOpacity(0.5))),
                  child:Text('$r (${arm?"Arm":"Unarm"}) $av',
                      style:TextStyle(color:sel?Colors.white:_kDark,fontSize:11,
                          fontWeight:sel?FontWeight.w700:FontWeight.w500))));
            }).toList())),
        if(_selectedRank.isNotEmpty) Padding(
          padding:const EdgeInsets.fromLTRB(16,8,16,8),
          child:Row(children:[
            const Text('संख्या:',style:TextStyle(color:_kDark,fontSize:13,fontWeight:FontWeight.w700)),
            const SizedBox(width:12),
            GestureDetector(onTap:(){if(_count>1)setState(()=>_count--);},
              child:Container(width:36,height:36,
                decoration:BoxDecoration(color:_kPrimary.withOpacity(0.1),borderRadius:BorderRadius.circular(8),
                    border:Border.all(color:_kPrimary.withOpacity(0.3))),
                child:const Icon(Icons.remove,color:_kPrimary,size:18))),
            const SizedBox(width:10),
            Container(width:48,height:36,
              decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(8),
                  border:Border.all(color:_kPrimary.withOpacity(0.5))),
              child:Center(child:Text('$_count',style:const TextStyle(color:_kDark,fontSize:16,fontWeight:FontWeight.w900)))),
            const SizedBox(width:10),
            GestureDetector(onTap:(){if(_count<widget.missing)setState(()=>_count++);},
              child:Container(width:36,height:36,
                decoration:BoxDecoration(color:_kPrimary.withOpacity(0.1),borderRadius:BorderRadius.circular(8),
                    border:Border.all(color:_kPrimary.withOpacity(0.3))),
                child:const Icon(Icons.add,color:_kPrimary,size:18))),
            const SizedBox(width:8),
            Text('/ ${widget.missing} max',style:const TextStyle(color:_kSubtle,fontSize:11)),
          ])),
        const Spacer(),
        if(_selectedRank.isNotEmpty) Container(
          padding:const EdgeInsets.fromLTRB(16,8,16,16),
          decoration:BoxDecoration(color:_kBg,border:Border(top:BorderSide(color:_kBorder.withOpacity(0.4)))),
          child:SizedBox(width:double.infinity,height:46,child:ElevatedButton(
            onPressed:()=>Navigator.pop(context,
                _SubSlot(rank:_selectedRank,armed:_selectedArmed,count:_count)),
            style:ElevatedButton.styleFrom(backgroundColor:_kInfo,foregroundColor:Colors.white,
              shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12))),
            child:Text('$_selectedRank (${_selectedArmed?"सशस्त्र":"निःशस्त्र"}) × $_count जोड़ें',
                style:const TextStyle(fontWeight:FontWeight.w700,fontSize:13))))),
        if(_selectedRank.isEmpty)
          Padding(padding:const EdgeInsets.fromLTRB(16,0,16,20),
            child:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
              Icon(Icons.group_outlined,size:48,color:_kSubtle.withOpacity(0.4)),
              const SizedBox(height:12),
              const Text('ऊपर कोई rank चुनें',style:TextStyle(color:_kSubtle,fontSize:13)),
            ]))),
      ]));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CENTER STEP — FIX: proper data parsing + loading states
// ═══════════════════════════════════════════════════════════════════════════════

class _CenterStep extends StatefulWidget {
  final int gpId; final int? szId; final _ElectionState election;
  const _CenterStep({super.key,required this.gpId,this.szId,required this.election});
  @override State<_CenterStep> createState()=>_CenterStepState();
}

class _CenterStepState extends State<_CenterStep> {
  final List<Map> _centers=[];
  bool _loading=true,_loadingMore=false,_hasMore=true,_disposed=false;
  int _page=1; static const _limit=20; String _q='';
  Timer? _debounce;
  final _searchCtrl=TextEditingController();
  final _scroll=ScrollController();

  @override
  void initState(){
    super.initState();
    _scroll.addListener(_onScroll);
    _searchCtrl.addListener(_onSearchChanged);
    _load(reset:true);
  }

  void _onScroll(){
    if(_disposed)return;
    if(_scroll.hasClients&&_scroll.position.pixels>=_scroll.position.maxScrollExtent-200) _load();
  }

  void _onSearchChanged(){
    _debounce?.cancel();
    _debounce=Timer(const Duration(milliseconds:350),(){
      if(_disposed)return;
      final q=_searchCtrl.text.trim();
      if(q!=_q){_q=q;_reload();}
    });
  }

  @override
  void dispose(){
    _disposed=true;_debounce?.cancel();
    _scroll.removeListener(_onScroll);_searchCtrl.removeListener(_onSearchChanged);
    _scroll.dispose();_searchCtrl.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn){if(!_disposed&&mounted)setState(fn);}

  void _reload(){
    _safeSetState((){_centers.clear();_page=1;_hasMore=true;});
    _load(reset:true);
  }

  Future<void> _load({bool reset=false}) async {
    if(_disposed)return;
    if(!_hasMore&&!reset)return;
    if(_loadingMore&&!reset)return;

    _safeSetState((){
      if(reset){ _loading=true; _loadingMore=false; }
      else { _loadingMore=true; }
    });

    try {
      final token=await AuthService.getToken();
      if(_disposed)return;

      final url='/admin/gram-panchayats/${widget.gpId}/centers'
          '?page=$_page&limit=$_limit&q=${Uri.encodeComponent(_q)}';
      final res=await ApiService.get(url,token:token);
      if(_disposed)return;

      // ── FIX: robust response parsing ──────────────────────────────────────
      // Backend returns: { success:true, data:{ data:[...], total:N, totalPages:N } }
      List<Map> items=[];
      int totalPages=1;

      final outer=res is Map ? res : <String,dynamic>{};
      final payload=outer['data'];

      if(payload is List){
        // Flat list response
        items=payload.map((e)=>Map<String,dynamic>.from(e as Map)).toList();
        totalPages=1;
        _hasMore=false;
      } else if(payload is Map){
        // Paginated response: { data:[...], total:N, totalPages:N }
        final inner=payload['data'];
        if(inner is List){
          items=inner.map((e)=>Map<String,dynamic>.from(e as Map)).toList();
        }
        totalPages=(payload['totalPages'] as num?)?.toInt() ?? 1;
      }

      _safeSetState((){
        if(reset) _centers.clear();
        _centers.addAll(items);
        _hasMore=_page<totalPages;
        _page++;
        _loading=false;
        _loadingMore=false;
      });
    } catch(e){
      debugPrint('CenterStep load error: $e');
      _safeSetState((){_loading=false;_loadingMore=false;});
      if(!_disposed&&mounted){
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:Text('Centers लोड नहीं हुए: $e'),
          backgroundColor:_kError,behavior:SnackBarBehavior.floating));
      }
    }
  }

  void _openCreateDialog(){
    if(_disposed||!mounted)return;
    showDialog(context:context,barrierDismissible:false,
      builder:(_)=>_CenterDialog(gpId:widget.gpId,onDone:(){if(!_disposed)_reload();}));
  }

  void _openEditDialog(Map c){
    if(_disposed||!mounted)return;
    showDialog(context:context,barrierDismissible:false,
      builder:(_)=>_CenterDialog(gpId:widget.gpId,existing:c,onDone:(){if(!_disposed)_reload();}));
  }

  Future<void> _delete(Map c) async {
    if(_disposed||!mounted)return;
    final confirmed=await _confirm(context,'Delete "${c['name']}"?');
    if(!confirmed||_disposed)return;
    try {
      final token=await AuthService.getToken();
      if(_disposed)return;
      await ApiService.delete('/admin/centers/${c['id']}',token:token);
      if(_disposed)return;
      _reload();
    } catch(e){
      if(!_disposed&&mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content:Text('Delete failed: $e'),backgroundColor:_kError,behavior:SnackBarBehavior.floating));
    }
  }

  void _openSwapSheet(Map c){
    if(_disposed||!mounted)return;
    showModalBottomSheet(context:context,isScrollControlled:true,backgroundColor:Colors.transparent,
      builder:(_)=>_SwapStaffSheet(center:c,onSwapped:(){if(!_disposed)_reload();}));
  }

  void _openShortageSheet(Map c){
    if(_disposed||!mounted)return;
    showModalBottomSheet(context:context,isScrollControlled:true,backgroundColor:Colors.transparent,
      builder:(_)=>_CenterShortageSheet(
        centerId:c['id'] as int,
        centerName:c['name'] as String? ?? '',
        sensitivity:c['centerType'] as String? ?? 'C',
        boothCount:c['boothCount'] as int? ?? 1,
        shortages:(c['missingRanks'] as List?)?.cast<Map<String,dynamic>>()??[],
        onResolved:(){if(!_disposed)_reload();}));
  }

  @override
  Widget build(BuildContext context) {
    return Column(children:[
      // Header
      Container(color:_kSurface,padding:const EdgeInsets.fromLTRB(12,10,12,10),
        child:Row(children:[
          Container(padding:const EdgeInsets.all(7),
            decoration:BoxDecoration(color:const Color(0xFFC62828).withOpacity(0.12),borderRadius:BorderRadius.circular(8)),
            child:const Icon(Icons.location_on_outlined,color:Color(0xFFC62828),size:16)),
          const SizedBox(width:10),
          const Expanded(child:Text('Election Centers',
              style:TextStyle(color:_kDark,fontWeight:FontWeight.w800,fontSize:15))),
          // Center count badge
          if(_centers.isNotEmpty)
            Container(
              margin:const EdgeInsets.only(right:8),
              padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
              decoration:BoxDecoration(
                color:const Color(0xFFC62828).withOpacity(0.1),
                borderRadius:BorderRadius.circular(12)),
              child:Text('${_centers.length}',
                style:const TextStyle(color:Color(0xFFC62828),fontWeight:FontWeight.w700,fontSize:12))),
          GestureDetector(onTap:_openCreateDialog,
            child:Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:7),
              decoration:BoxDecoration(color:const Color(0xFFC62828),borderRadius:BorderRadius.circular(9)),
              child:const Row(mainAxisSize:MainAxisSize.min,children:[
                Icon(Icons.add,color:Colors.white,size:14),SizedBox(width:4),
                Text('जोड़ें',style:TextStyle(color:Colors.white,fontSize:12,fontWeight:FontWeight.w700))]))),
        ])),
      // Search
      Container(color:_kBg,padding:const EdgeInsets.fromLTRB(12,8,12,8),
        child:TextField(controller:_searchCtrl,style:const TextStyle(color:_kDark,fontSize:13),
          decoration:InputDecoration(
            hintText:'Center खोजें...',hintStyle:const TextStyle(color:_kSubtle,fontSize:12),
            prefixIcon:const Icon(Icons.search,color:_kSubtle,size:18),
            suffixIcon:_q.isNotEmpty?IconButton(icon:const Icon(Icons.clear,size:16,color:_kSubtle),
                onPressed:(){_searchCtrl.clear();_q='';_reload();}):null,
            filled:true,fillColor:Colors.white,isDense:true,
            contentPadding:const EdgeInsets.symmetric(horizontal:12,vertical:10),
            border:OutlineInputBorder(borderRadius:BorderRadius.circular(10),borderSide:const BorderSide(color:_kBorder)),
            enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(10),borderSide:const BorderSide(color:_kBorder)),
            focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(10),
                borderSide:const BorderSide(color:Color(0xFFC62828),width:2))))),
      // List or states
      Expanded(child: _buildContent()),
    ]);
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: _kPrimary),
          SizedBox(height: 12),
          Text('Centers लोड हो रहे हैं...', style: TextStyle(color: _kSubtle, fontSize: 13)),
        ],
      ));
    }

    if (_centers.isEmpty) {
      return _emptyState('Election Centers', Icons.location_on_outlined, const Color(0xFFC62828));
    }

    return RefreshIndicator(
      onRefresh: () async => _reload(),
      color: _kPrimary,
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        thickness: 5,
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
          itemCount: _centers.length + (_loadingMore ? 1 : 0),
          itemBuilder: (_, i) {
            if (i >= _centers.length) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary))));
            }
            return _CenterCard(
              center: _centers[i],
              onEdit: () => _openEditDialog(_centers[i]),
              onDelete: () => _delete(_centers[i]),
              onSwap: () => _openSwapSheet(_centers[i]),
              onShortage: () => _openShortageSheet(_centers[i]),
              onRefresh: _reload,
            );
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CENTER CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _CenterCard extends StatelessWidget {
  final Map center;
  final VoidCallback onEdit, onDelete, onSwap, onShortage, onRefresh;
  const _CenterCard({required this.center,required this.onEdit,required this.onDelete,
    required this.onSwap,required this.onShortage,required this.onRefresh});

  Color _typeColor(String t) => switch(t){
    'A++'=>const Color(0xFF6A1B9A),'A'=>const Color(0xFFC62828),'B'=>const Color(0xFFE65100),_=>const Color(0xFF1A5276)};

  @override
  Widget build(BuildContext context) {
    final type        = center['centerType'] as String? ?? 'C';
    final tc          = _typeColor(type);
    final assignedRaw = center['assignedStaff'] ?? center['assigned_staff'];
    final assigned    = (assignedRaw is List) ? assignedRaw.cast<Map>() : <Map>[];
    final missingRaw  = center['missingRanks'] ?? center['missing_ranks'];
    final missing     = (missingRaw is List) ? missingRaw.cast<Map>() : <Map>[];
    final dutyCount   = (center['dutyCount'] as num? ?? center['duty_count'] as num? ?? assigned.length).toInt();
    final boothCount  = (center['boothCount'] as num? ?? center['booth_count'] as num? ?? 0).toInt();
    final roomCount   = (center['roomCount'] as num? ?? center['room_count'] as num? ?? 0).toInt();

    final bool hasShortage       = missing.isNotEmpty;
    final bool isFullyAssigned   = !hasShortage && dutyCount > 0;
    final bool isPartiallyAssigned = dutyCount > 0 && hasShortage;

    final borderColor = hasShortage
        ? _kAmber.withOpacity(0.5)
        : isFullyAssigned
            ? _kSuccess.withOpacity(0.4)
            : _kBorder.withOpacity(0.4);

    return Container(
      margin:const EdgeInsets.only(bottom:10),
      decoration:BoxDecoration(
        color:Colors.white,borderRadius:BorderRadius.circular(12),
        border:Border.all(color:borderColor,width:isFullyAssigned||hasShortage?1.5:1),
        boxShadow:[BoxShadow(color:tc.withOpacity(0.06),blurRadius:6,offset:const Offset(0,2))]),
      child:Column(children:[
        // Header row
        Padding(padding:const EdgeInsets.fromLTRB(12,10,8,8),
          child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Stack(clipBehavior:Clip.none,children:[
              Container(width:44,height:44,
                decoration:BoxDecoration(
                  color:tc.withOpacity(isFullyAssigned?0.15:0.08),
                  borderRadius:BorderRadius.circular(10),
                  border:Border.all(color:tc.withOpacity(0.3))),
                child:Center(child:Text(type,
                    style:TextStyle(color:tc,fontWeight:FontWeight.w900,fontSize:type.length>1?11:16)))),
              if(isFullyAssigned||hasShortage||isPartiallyAssigned)
                Positioned(bottom:-2,right:-2,
                  child:Container(width:14,height:14,
                    decoration:BoxDecoration(
                      color:isFullyAssigned?_kSuccess:hasShortage?_kAmber:_kError,
                      shape:BoxShape.circle,
                      border:Border.all(color:Colors.white,width:1.5)),
                    child:Center(child:Icon(
                      isFullyAssigned?Icons.check:hasShortage?Icons.warning_amber_rounded:Icons.close,
                      size:8,color:Colors.white)))),
            ]),
            const SizedBox(width:10),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Row(children:[
                Expanded(child:Text(center['name']??'',
                    style:const TextStyle(color:_kDark,fontWeight:FontWeight.w700,fontSize:14),
                    maxLines:1,overflow:TextOverflow.ellipsis)),
                if(isFullyAssigned) Container(
                  margin:const EdgeInsets.only(left:4),
                  padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
                  decoration:BoxDecoration(color:_kSuccess.withOpacity(0.1),borderRadius:BorderRadius.circular(6),
                      border:Border.all(color:_kSuccess.withOpacity(0.4))),
                  child:const Text('✓ पूर्ण',style:TextStyle(color:_kSuccess,fontSize:9,fontWeight:FontWeight.w800)))
                else if(hasShortage) Container(
                  margin:const EdgeInsets.only(left:4),
                  padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
                  decoration:BoxDecoration(color:_kAmber.withOpacity(0.1),borderRadius:BorderRadius.circular(6),
                      border:Border.all(color:_kAmber.withOpacity(0.4))),
                  child:const Text('⚠ अधूरा',style:TextStyle(color:_kAmber,fontSize:9,fontWeight:FontWeight.w800))),
              ]),
              const SizedBox(height:3),
              Wrap(spacing:8,runSpacing:2,children:[
                if((center['thana'] as String?)?.isNotEmpty==true)
                  _mini(Icons.local_police_outlined,center['thana'] as String),
                if((center['busNo'] as String?)?.isNotEmpty==true)
                  _mini(Icons.directions_bus_outlined,'Bus: ${center['busNo']}'),
                _mini(Icons.how_to_vote_outlined,'$boothCount बूथ'),
                _mini(Icons.people_outlined,'$dutyCount असाइन'),
                if(roomCount>0) _mini(Icons.meeting_room_outlined,'$roomCount कमरे'),
              ]),
            ])),
            Column(mainAxisSize:MainAxisSize.min,children:[
              _iconBtn(Icons.edit_outlined,_kInfo,onEdit),
              const SizedBox(height:4),
              _iconBtn(Icons.delete_outline,_kError,onDelete),
            ]),
          ])),

        // Shortage warning
        if(hasShortage)
          Container(margin:const EdgeInsets.fromLTRB(12,0,12,6),
            padding:const EdgeInsets.symmetric(horizontal:10,vertical:8),
            decoration:BoxDecoration(color:_kAmber.withOpacity(0.07),borderRadius:BorderRadius.circular(8),
                border:Border.all(color:_kAmber.withOpacity(0.3))),
            child:Row(children:[
              const Icon(Icons.warning_amber_rounded,color:_kAmber,size:14),
              const SizedBox(width:6),
              Expanded(child:Wrap(spacing:6,runSpacing:3,
                children:missing.map((m){
                  final rank=m['rank'] as String? ??'';
                  final req=m['required'] as int? ??0;
                  final got=m['assigned'] as int? ?? m['available'] as int? ??0;
                  final miss=m['missing'] as int? ?? (req-got).clamp(0,req);
                  return Container(
                    padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
                    decoration:BoxDecoration(color:_kAmber.withOpacity(0.12),borderRadius:BorderRadius.circular(5)),
                    child:Text('$rank: $miss कम',style:const TextStyle(color:Color(0xFF92400E),fontSize:10,fontWeight:FontWeight.w600)));
                }).toList())),
            ])),

        // Assigned staff chips
        if(assigned.isNotEmpty)
          Padding(padding:const EdgeInsets.fromLTRB(12,0,12,8),
            child:Wrap(spacing:5,runSpacing:4,
              children:assigned.take(6).map((s){
                final rank=s['rank'] as String? ?? s['user_rank'] as String? ??'';
                final rankColor=_kRankColors[rank]??_kPrimary;
                return Container(
                  padding:const EdgeInsets.symmetric(horizontal:7,vertical:4),
                  decoration:BoxDecoration(
                    color:_kSuccess.withOpacity(0.06),borderRadius:BorderRadius.circular(7),
                    border:Border.all(color:_kSuccess.withOpacity(0.25))),
                  child:Row(mainAxisSize:MainAxisSize.min,children:[
                    const Icon(Icons.check_circle_outline,size:10,color:_kSuccess),
                    const SizedBox(width:3),
                    ConstrainedBox(constraints:const BoxConstraints(maxWidth:65),
                      child:Text(s['name'] as String? ??'',
                          style:const TextStyle(color:_kDark,fontSize:11,fontWeight:FontWeight.w600),
                          maxLines:1,overflow:TextOverflow.ellipsis)),
                    const SizedBox(width:3),
                    Container(padding:const EdgeInsets.symmetric(horizontal:3,vertical:1),
                      decoration:BoxDecoration(color:rankColor.withOpacity(0.12),borderRadius:BorderRadius.circular(4)),
                      child:Text(rank,style:TextStyle(color:rankColor,fontSize:8,fontWeight:FontWeight.w700))),
                  ]));
              }).followedBy(assigned.length>6?[
                Container(padding:const EdgeInsets.symmetric(horizontal:7,vertical:4),
                  decoration:BoxDecoration(color:_kSubtle.withOpacity(0.08),borderRadius:BorderRadius.circular(7)),
                  child:Text('+${assigned.length-6} और',style:const TextStyle(color:_kSubtle,fontSize:11)))
              ]:[]).toList())),

        // Not assigned notice
        if(assigned.isEmpty&&dutyCount==0)
          Padding(padding:const EdgeInsets.fromLTRB(12,0,12,8),
            child:Container(padding:const EdgeInsets.all(8),
              decoration:BoxDecoration(color:_kError.withOpacity(0.05),borderRadius:BorderRadius.circular(8),
                  border:Border.all(color:_kError.withOpacity(0.2))),
              child:const Row(children:[
                Icon(Icons.person_off_outlined,size:14,color:_kError),SizedBox(width:6),
                Expanded(child:Text('कोई staff assign नहीं — Super Zone से "Assign Duty" चलाएं',
                    style:TextStyle(color:_kError,fontSize:11)))]))),

        // Action buttons
        Padding(padding:const EdgeInsets.fromLTRB(12,0,12,10),
          child:Row(children:[
            Expanded(child:_actionChip(icon:Icons.swap_horiz,label:'Swap Staff',color:_kInfo,onTap:onSwap)),
            const SizedBox(width:6),
            if(hasShortage)
              Expanded(child:_actionChip(icon:Icons.person_add_outlined,label:'Fix Shortage',color:_kAmber,onTap:onShortage)),
          ])),
      ]));
  }

  Widget _mini(IconData icon,String text)=>Row(mainAxisSize:MainAxisSize.min,children:[
    Icon(icon,size:10,color:_kSubtle),const SizedBox(width:3),
    Text(text,style:const TextStyle(color:_kSubtle,fontSize:11))]);

  Widget _iconBtn(IconData icon,Color c,VoidCallback onTap)=>GestureDetector(onTap:onTap,
    child:Container(width:32,height:32,
      decoration:BoxDecoration(color:c.withOpacity(0.08),borderRadius:BorderRadius.circular(8),
          border:Border.all(color:c.withOpacity(0.25))),
      child:Icon(icon,size:15,color:c)));

  Widget _actionChip({required IconData icon,required String label,required Color color,required VoidCallback onTap})=>
    GestureDetector(onTap:onTap,
      child:Container(padding:const EdgeInsets.symmetric(vertical:7),
        decoration:BoxDecoration(color:color.withOpacity(0.07),borderRadius:BorderRadius.circular(8),
            border:Border.all(color:color.withOpacity(0.25))),
        child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[
          Icon(icon,size:13,color:color),const SizedBox(width:5),
          Text(label,style:TextStyle(color:color,fontSize:11,fontWeight:FontWeight.w700))])));
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SWAP STAFF SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class _SwapStaffSheet extends StatefulWidget {
  final Map center; final VoidCallback onSwapped;
  const _SwapStaffSheet({required this.center,required this.onSwapped});
  @override State<_SwapStaffSheet> createState()=>_SwapStaffSheetState();
}

class _SwapStaffSheetState extends State<_SwapStaffSheet> {
  List<Map> _assigned=[]; bool _loading=true,_disposed=false,_swapping=false;
  @override void initState(){super.initState();_loadAssigned();}
  @override void dispose(){_disposed=true;super.dispose();}
  void _safeSetState(VoidCallback fn){if(!_disposed&&mounted)setState(fn);}

  Future<void> _loadAssigned() async {
    _safeSetState(()=>_loading=true);
    try {
      final token=await AuthService.getToken(); if(_disposed)return;
      final res=await ApiService.get('/admin/center/${widget.center['id']}/staff',token:token);
      if(_disposed)return;
      final data=res['data'];
      _safeSetState((){
        _assigned=(data is List)?data.map((e)=>Map<String,dynamic>.from(e as Map)).toList():[];
        _loading=false;
      });
    } catch(_){_safeSetState(()=>_loading=false);}
  }

  Future<void> _pickAndSwap(Map removeStaff) async {
    if(_disposed||!mounted)return;
    final rank=removeStaff['user_rank'] as String? ?? removeStaff['rank'] as String? ?? '';
    final picked=await showModalBottomSheet<Map<String,dynamic>>(
      context:context,isScrollControlled:true,backgroundColor:Colors.transparent,
      builder:(_)=>_StaffPickerSheet(
        allowedRanks:rank.isNotEmpty?[rank]:_kRanks.toList(),color:_kInfo));
    if(picked==null||_disposed||!mounted)return;
    setState(()=>_swapping=true);
    try {
      final token=await AuthService.getToken();
      await ApiService.post('/admin/swap',{
        'removeStaffId':removeStaff['id'],'addStaffId':picked['id'],
        'centerId':widget.center['id']},token:token);
      if(!_disposed&&mounted){
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:Text('Swap सफल!'),backgroundColor:_kSuccess,behavior:SnackBarBehavior.floating));
        widget.onSwapped(); Navigator.pop(context);
      }
    } catch(e){
      if(!_disposed&&mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:Text('Swap विफल: $e'),backgroundColor:_kError,behavior:SnackBarBehavior.floating));
    } finally {if(!_disposed&&mounted)setState(()=>_swapping=false);}
  }

  @override
  Widget build(BuildContext context) {
    final type=widget.center['centerType'] as String? ?? 'C';
    final tc=switch(type){'A++'=>const Color(0xFF6A1B9A),'A'=>const Color(0xFFC62828),'B'=>const Color(0xFFE65100),_=>const Color(0xFF1A5276)};
    return Container(
      height:MediaQuery.of(context).size.height*0.8,
      decoration:const BoxDecoration(color:_kBg,borderRadius:BorderRadius.vertical(top:Radius.circular(20))),
      child:Column(children:[
        Container(margin:const EdgeInsets.only(top:10,bottom:4),width:40,height:4,
          decoration:BoxDecoration(color:_kBorder.withOpacity(0.5),borderRadius:BorderRadius.circular(2))),
        Padding(padding:const EdgeInsets.fromLTRB(16,8,16,12),child:Row(children:[
          Container(padding:const EdgeInsets.all(8),
            decoration:BoxDecoration(color:tc.withOpacity(0.12),borderRadius:BorderRadius.circular(10)),
            child:Icon(Icons.swap_horiz,color:tc,size:18)),
          const SizedBox(width:10),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('Swap / Remove Staff',style:TextStyle(color:_kDark,fontWeight:FontWeight.w800,fontSize:15)),
            Text(widget.center['name']??'',style:const TextStyle(color:_kSubtle,fontSize:12),
                maxLines:1,overflow:TextOverflow.ellipsis),
          ])),
          Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
            decoration:BoxDecoration(color:tc.withOpacity(0.1),borderRadius:BorderRadius.circular(8)),
            child:Text(type,style:TextStyle(color:tc,fontWeight:FontWeight.w900,fontSize:13))),
        ])),
        Container(margin:const EdgeInsets.fromLTRB(16,0,16,10),
          padding:const EdgeInsets.all(9),
          decoration:BoxDecoration(color:_kInfo.withOpacity(0.07),borderRadius:BorderRadius.circular(8),
              border:Border.all(color:_kInfo.withOpacity(0.2))),
          child:const Row(children:[
            Icon(Icons.info_outline,size:13,color:_kInfo),SizedBox(width:6),
            Expanded(child:Text('Swap: staff हटाएं और Reserve से नया लगाएं',
                style:TextStyle(color:_kInfo,fontSize:11)))])),
        Expanded(child:_loading
          ? const Center(child:CircularProgressIndicator(color:_kPrimary))
          : _assigned.isEmpty
              ? const Center(child:Text('कोई staff assign नहीं',style:TextStyle(color:_kSubtle,fontSize:13)))
              : ListView.builder(
                  padding:const EdgeInsets.fromLTRB(16,0,16,20),
                  itemCount:_assigned.length,
                  itemBuilder:(_,i){
                    final s=_assigned[i];
                    final rank=s['user_rank'] as String? ?? s['rank'] as String? ?? '';
                    final rc=_kRankColors[rank]??_kPrimary;
                    return Container(margin:const EdgeInsets.only(bottom:8),
                      padding:const EdgeInsets.symmetric(horizontal:12,vertical:10),
                      decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(10),
                          border:Border.all(color:_kBorder.withOpacity(0.4))),
                      child:Row(children:[
                        Container(width:38,height:38,
                          decoration:BoxDecoration(shape:BoxShape.circle,color:rc.withOpacity(0.12),
                              border:Border.all(color:rc.withOpacity(0.3))),
                          child:Center(child:Text(
                            (s['name'] as String? ??'').split(' ')
                                .where((w)=>w.isNotEmpty).take(2).map((w)=>w[0]).join().toUpperCase(),
                            style:TextStyle(color:rc,fontWeight:FontWeight.w900,fontSize:13)))),
                        const SizedBox(width:10),
                        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                          Text(s['name']??'',style:const TextStyle(color:_kDark,fontWeight:FontWeight.w700,fontSize:13)),
                          Row(children:[
                            Container(padding:const EdgeInsets.symmetric(horizontal:5,vertical:1),
                              decoration:BoxDecoration(color:rc.withOpacity(0.1),borderRadius:BorderRadius.circular(5),
                                  border:Border.all(color:rc.withOpacity(0.3))),
                              child:Text(rank,style:TextStyle(color:rc,fontSize:9,fontWeight:FontWeight.w700))),
                            if((s['mobile'] as String?)?.isNotEmpty==true)...[
                              const SizedBox(width:6),
                              Text(s['mobile'] as String,style:const TextStyle(color:_kSubtle,fontSize:10))],
                          ]),
                        ])),
                        GestureDetector(onTap:_swapping?null:()=>_pickAndSwap(s),
                          child:Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),
                            decoration:BoxDecoration(color:_kInfo.withOpacity(0.08),borderRadius:BorderRadius.circular(8),
                                border:Border.all(color:_kInfo.withOpacity(0.3))),
                            child:const Row(mainAxisSize:MainAxisSize.min,children:[
                              Icon(Icons.swap_horiz,size:13,color:_kInfo),SizedBox(width:4),
                              Text('Swap',style:TextStyle(color:_kInfo,fontSize:11,fontWeight:FontWeight.w700))]))),
                      ]));
                  })),
      ]));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  STAFF PICKER SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class _StaffPickerSheet extends StatefulWidget {
  final List<String> allowedRanks; final Color color;
  const _StaffPickerSheet({required this.allowedRanks,required this.color});
  @override State<_StaffPickerSheet> createState()=>_StaffPickerSheetState();
}

class _StaffPickerSheetState extends State<_StaffPickerSheet> {
  final List<Map> _staff=[]; bool _loading=true,_hasMore=true,_loadingMore=false,_disposed=false;
  int _page=1; String _q='',_rankFilter='';
  Timer? _debounce; final _searchCtrl=TextEditingController(); final _scroll=ScrollController();

  @override void initState(){
    super.initState();
    _rankFilter=widget.allowedRanks.isNotEmpty?widget.allowedRanks.first:'';
    _scroll.addListener(_onScroll); _searchCtrl.addListener(_onSearchChanged); _load(reset:true);
  }
  void _onScroll(){if(_disposed)return;if(_scroll.hasClients&&_scroll.position.pixels>=_scroll.position.maxScrollExtent-100)_load();}
  void _onSearchChanged(){_debounce?.cancel();_debounce=Timer(const Duration(milliseconds:300),(){if(_disposed)return;final q=_searchCtrl.text.trim();if(q!=_q){_q=q;_reload();}});}
  @override void dispose(){_disposed=true;_debounce?.cancel();_scroll.removeListener(_onScroll);_searchCtrl.removeListener(_onSearchChanged);_scroll.dispose();_searchCtrl.dispose();super.dispose();}
  void _safeSetState(VoidCallback fn){if(!_disposed&&mounted)setState(fn);}
  void _reload(){_safeSetState((){_staff.clear();_page=1;_hasMore=true;});_load(reset:true);}

  Future<void> _load({bool reset=false}) async {
    if(_disposed)return; if(!_hasMore&&!reset)return; if(_loadingMore)return;
    _safeSetState((){if(reset)_loading=true;else _loadingMore=true;});
    try {
      final token=await AuthService.getToken(); if(_disposed)return;
      var url='/admin/staff?assigned=no&page=$_page&limit=20&q=${Uri.encodeComponent(_q)}';
      if(_rankFilter.isNotEmpty) url+='&rank=${Uri.encodeComponent(_rankFilter)}';
      final res=await ApiService.get(url,token:token); if(_disposed)return;
      final w=(res['data'] as Map<String,dynamic>?)??{};
      final items=(w['data'] as List?)?.map((e)=>Map<String,dynamic>.from(e as Map)).toList()??[];
      final pages=(w['totalPages'] as num?)?.toInt()??1;
      _safeSetState((){_staff.addAll(items);_hasMore=_page<pages;_page++;_loading=false;_loadingMore=false;});
    } catch(_){_safeSetState((){_loading=false;_loadingMore=false;});}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height:MediaQuery.of(context).size.height*0.75,
      decoration:const BoxDecoration(color:_kBg,borderRadius:BorderRadius.vertical(top:Radius.circular(20))),
      child:Column(children:[
        Container(margin:const EdgeInsets.only(top:10,bottom:4),width:40,height:4,
          decoration:BoxDecoration(color:_kBorder.withOpacity(0.5),borderRadius:BorderRadius.circular(2))),
        Padding(padding:const EdgeInsets.fromLTRB(16,6,16,10),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('Staff से चुनें (अनसाइन)',style:TextStyle(color:_kDark,fontWeight:FontWeight.w800,fontSize:15)),
          const SizedBox(height:10),
          if(widget.allowedRanks.isNotEmpty)
            SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
              _rankChip('सभी',''), ...widget.allowedRanks.map((r)=>_rankChip(r,r))])),
          const SizedBox(height:8),
          TextField(controller:_searchCtrl,style:const TextStyle(color:_kDark,fontSize:13),
            decoration:InputDecoration(hintText:'नाम, PNO खोजें...',hintStyle:const TextStyle(color:_kSubtle,fontSize:12),
              prefixIcon:const Icon(Icons.search,color:_kSubtle,size:18),
              filled:true,fillColor:Colors.white,isDense:true,
              contentPadding:const EdgeInsets.symmetric(horizontal:12,vertical:10),
              border:OutlineInputBorder(borderRadius:BorderRadius.circular(10),borderSide:const BorderSide(color:_kBorder)),
              enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(10),borderSide:const BorderSide(color:_kBorder)),
              focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(10),borderSide:BorderSide(color:widget.color,width:2)))),
        ])),
        Expanded(child:_loading
          ? const Center(child:CircularProgressIndicator(color:_kPrimary))
          : _staff.isEmpty
              ? Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
                  Icon(Icons.people_outline,size:48,color:_kSubtle.withOpacity(0.4)),const SizedBox(height:12),
                  Text('${_rankFilter.isEmpty?'कोई':_rankFilter} अनसाइन स्टाफ नहीं',
                      style:const TextStyle(color:_kSubtle,fontSize:13))]))
              : Scrollbar(controller:_scroll,thumbVisibility:true,thickness:5,
                  child:ListView.builder(controller:_scroll,
                    padding:const EdgeInsets.fromLTRB(16,0,16,20),
                    itemCount:_staff.length+(_loadingMore?1:0),
                    itemBuilder:(_,i){
                      if(i>=_staff.length) return const Padding(padding:EdgeInsets.all(12),
                        child:Center(child:SizedBox(width:18,height:18,
                            child:CircularProgressIndicator(strokeWidth:2,color:_kPrimary))));
                      final s=_staff[i]; final rc=_kRankColors[s['rank']]??_kPrimary;
                      return ListTile(
                        contentPadding:const EdgeInsets.symmetric(horizontal:4,vertical:4),
                        leading:Container(width:40,height:40,
                          decoration:BoxDecoration(shape:BoxShape.circle,color:rc.withOpacity(0.12),
                              border:Border.all(color:rc.withOpacity(0.3))),
                          child:Center(child:Text(
                            (s['name'] as String? ??'').split(' ')
                                .where((w)=>w.isNotEmpty).take(2).map((w)=>w[0]).join().toUpperCase(),
                            style:TextStyle(color:rc,fontWeight:FontWeight.w900,fontSize:13)))),
                        title:Text(s['name']??'',style:const TextStyle(color:_kDark,fontWeight:FontWeight.w700,fontSize:13)),
                        subtitle:Row(children:[
                          if((s['pno'] as String?)?.isNotEmpty==true)...[
                            const Icon(Icons.badge_outlined,size:10,color:_kSubtle),const SizedBox(width:3),
                            Text('${s['pno']}',style:const TextStyle(color:_kSubtle,fontSize:11)),const SizedBox(width:8)],
                          Container(padding:const EdgeInsets.symmetric(horizontal:5,vertical:1),
                            decoration:BoxDecoration(color:rc.withOpacity(0.1),borderRadius:BorderRadius.circular(5),
                                border:Border.all(color:rc.withOpacity(0.3))),
                            child:Text(s['rank']??'',style:TextStyle(color:rc,fontSize:10,fontWeight:FontWeight.w700)))]),
                        trailing:Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),
                          decoration:BoxDecoration(color:widget.color,borderRadius:BorderRadius.circular(8)),
                          child:const Text('चुनें',style:TextStyle(color:Colors.white,fontSize:11,fontWeight:FontWeight.w700))),
                        onTap:()=>Navigator.pop(context,Map<String,dynamic>.from(s)));
                    }))),
      ]));
  }

  Widget _rankChip(String label,String value){
    final sel=_rankFilter==value; final color=value.isEmpty?_kPrimary:(_kRankColors[value]??_kPrimary);
    return GestureDetector(
      onTap:(){if(_disposed)return;_safeSetState(()=>_rankFilter=value);_reload();},
      child:Container(margin:const EdgeInsets.only(right:6),
        padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),
        decoration:BoxDecoration(color:sel?color:Colors.white,borderRadius:BorderRadius.circular(20),
          border:Border.all(color:sel?color:_kBorder.withOpacity(0.5))),
        child:Text(label,style:TextStyle(color:sel?Colors.white:_kDark,
            fontSize:11,fontWeight:sel?FontWeight.w700:FontWeight.w500))));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ITEM DIALOG
// ═══════════════════════════════════════════════════════════════════════════════

class _ItemDialog extends StatefulWidget {
  final String title; final Color color; final IconData icon;
  final List<String> fields,officerRanks;
  final String officerTitle,createUrl,officerPostUrl;
  final int levelIndex; final String Function(int) updateUrlFn;
  final Map? existing; final VoidCallback onDone; final _ElectionState election;
  const _ItemDialog({required this.title,required this.color,required this.icon,
    required this.fields,required this.officerTitle,required this.officerRanks,
    required this.createUrl,required this.updateUrlFn,required this.officerPostUrl,
    required this.levelIndex,this.existing,required this.onDone,required this.election});
  @override State<_ItemDialog> createState()=>_ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  final Map<String,TextEditingController> _ctrls={};
  final List<_OfficerEntry> _officers=[];
  bool _saving=false;

  @override
  void initState(){
    super.initState();
    for(final f in widget.fields) _ctrls[f]=TextEditingController(text:widget.existing?[f]?.toString()??'');
    for(final o in (widget.existing?['officers'] as List?)??[])
      _officers.add(_OfficerEntry.fromMap(Map<String,dynamic>.from(o as Map)));
    if(_officers.isEmpty&&widget.officerRanks.isNotEmpty) _officers.add(_OfficerEntry());
  }
  @override void dispose(){for(final c in _ctrls.values)c.dispose();for(final o in _officers)o.dispose();super.dispose();}

  String _fieldLabel(String f)=>switch(f){'name'=>'नाम *','district'=>'जिला','block'=>'ब्लॉक','hqAddress'=>'मुख्यालय / HQ','address'=>'पता',_=>f};
  IconData _fieldIcon(String f)=>switch(f){'name'=>Icons.label_outline,'district'=>Icons.location_city_outlined,'block'=>Icons.domain_outlined,'hqAddress'=>Icons.home_outlined,'address'=>Icons.map_outlined,_=>Icons.edit_outlined};

  Future<void> _save() async {
    final name=_ctrls['name']?.text.trim()??'';
    if(name.isEmpty){_snack('नाम आवश्यक है',error:true);return;}
    final hasOfficers=_officers.any((o)=>o.nameCtrl.text.trim().isNotEmpty);
    if(hasOfficers&&widget.officerRanks.isNotEmpty&&!widget.election.canAssign){
      bool proceed=false;
      await handleElectionGuard(context,widget.election,()async{proceed=true;});
      if(!proceed)return;
    }
    if(!mounted)return;
    setState(()=>_saving=true);
    try {
      final token=await AuthService.getToken(); if(!mounted)return;
      final body=<String,dynamic>{};
      for(final f in widget.fields) body[f]=_ctrls[f]?.text.trim()??'';
      body['officers']=_officers.where((o)=>o.nameCtrl.text.trim().isNotEmpty)
          .map((o)=>({...o.toMap(),if(widget.election.id!=null)'electionId':widget.election.id})).toList();
      final isEdit=widget.existing!=null;
      if(isEdit) await ApiService.put(widget.updateUrlFn(widget.existing!['id'] as int),body,token:token);
      else       await ApiService.post(widget.createUrl,body,token:token);
      if(!mounted)return;
      Navigator.pop(context); widget.onDone();
    } catch(e){if(mounted)setState(()=>_saving=false);_snack('Error: $e',error:true);}
  }

  void _snack(String msg,{bool error=false}){
    if(!mounted)return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(msg),
      backgroundColor:error?_kError:_kSuccess,behavior:SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final hasOfficerSection=widget.officerRanks.isNotEmpty;
    final electionActive=widget.election.canAssign;
    return Dialog(
      backgroundColor:Colors.transparent,
      insetPadding:const EdgeInsets.symmetric(horizontal:12,vertical:20),
      child:ConstrainedBox(
        constraints:BoxConstraints(maxWidth:520,maxHeight:MediaQuery.of(context).size.height*0.88),
        child:Container(
          decoration:BoxDecoration(color:_kBg,borderRadius:BorderRadius.circular(16),
              border:Border.all(color:_kBorder,width:1.2),
              boxShadow:[BoxShadow(color:widget.color.withOpacity(0.15),blurRadius:20,offset:const Offset(0,8))]),
          child:Column(mainAxisSize:MainAxisSize.min,children:[
            Container(padding:const EdgeInsets.fromLTRB(16,13,12,13),
              decoration:BoxDecoration(color:_kDark,borderRadius:const BorderRadius.only(
                  topLeft:Radius.circular(15),topRight:Radius.circular(15))),
              child:Row(children:[
                Container(padding:const EdgeInsets.all(6),
                  decoration:BoxDecoration(color:widget.color.withOpacity(0.25),borderRadius:BorderRadius.circular(7)),
                  child:Icon(widget.icon,color:widget.color,size:16)),
                const SizedBox(width:10),
                Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text(widget.title,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w700,fontSize:15)),
                  if(hasOfficerSection) Row(children:[
                    Icon(electionActive?Icons.how_to_vote_outlined:Icons.warning_amber_rounded,
                        size:10,color:electionActive?_kSuccess.withOpacity(0.8):_kAmber),
                    const SizedBox(width:4),
                    Expanded(child:Text(
                      electionActive?'चुनाव: ${widget.election.name}'
                          :'⚠️ कोई सक्रिय चुनाव नहीं',
                      style:TextStyle(color:electionActive?Colors.white54:_kAmber,fontSize:9,fontWeight:FontWeight.w600),
                      maxLines:1,overflow:TextOverflow.ellipsis)),
                  ]),
                ])),
                IconButton(onPressed:()=>Navigator.pop(context),
                    icon:const Icon(Icons.close,color:Colors.white60,size:20),
                    padding:EdgeInsets.zero,constraints:const BoxConstraints()),
              ])),
            if(hasOfficerSection&&!widget.election.canAssign)
              _ElectionWarningBanner(election:widget.election),
            Flexible(child:SingleChildScrollView(padding:const EdgeInsets.all(16),
              child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                ...widget.fields.map((f)=>Padding(padding:const EdgeInsets.only(bottom:10),
                  child:f=='district'
                    ? DropdownButtonFormField<String>(
                        value:_ctrls[f]?.text.isNotEmpty==true?_ctrls[f]!.text:null,
                        items:upDistrictsHindi.map((d)=>DropdownMenuItem(value:d,
                            child:Text(d,style:const TextStyle(color:_kDark,fontSize:13)))).toList(),
                        onChanged:(val){if(val!=null)_ctrls[f]!.text=val;},
                        decoration:InputDecoration(labelText:'जिला',labelStyle:const TextStyle(color:_kSubtle,fontSize:12),
                          prefixIcon:Icon(Icons.location_city_outlined,size:18,color:widget.color),
                          filled:true,fillColor:Colors.white,isDense:true,
                          contentPadding:const EdgeInsets.symmetric(horizontal:12,vertical:11),
                          border:OutlineInputBorder(borderRadius:BorderRadius.circular(10),borderSide:const BorderSide(color:_kBorder)),
                          enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(10),borderSide:const BorderSide(color:_kBorder)),
                          focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(10),borderSide:BorderSide(color:widget.color,width:2))))
                    : TextFormField(controller:_ctrls[f],style:const TextStyle(color:_kDark,fontSize:13),
                        decoration:InputDecoration(labelText:_fieldLabel(f),labelStyle:const TextStyle(color:_kSubtle,fontSize:12),
                          prefixIcon:Icon(_fieldIcon(f),size:18,color:widget.color),
                          filled:true,fillColor:Colors.white,isDense:true,
                          contentPadding:const EdgeInsets.symmetric(horizontal:12,vertical:11),
                          border:OutlineInputBorder(borderRadius:BorderRadius.circular(10),borderSide:const BorderSide(color:_kBorder)),
                          enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(10),borderSide:const BorderSide(color:_kBorder)),
                          focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(10),borderSide:BorderSide(color:widget.color,width:2)))))),
                if(widget.officerRanks.isNotEmpty)...[
                  const SizedBox(height:6),
                  Row(children:[
                    Container(width:3,height:14,decoration:BoxDecoration(color:widget.color,borderRadius:BorderRadius.circular(2))),
                    const SizedBox(width:8),
                    Expanded(child:Text(widget.officerTitle,style:TextStyle(color:widget.color,fontSize:12,fontWeight:FontWeight.w800))),
                    GestureDetector(onTap:()=>setState(()=>_officers.add(_OfficerEntry())),
                      child:Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
                        decoration:BoxDecoration(color:widget.color.withOpacity(0.1),borderRadius:BorderRadius.circular(7),
                            border:Border.all(color:widget.color.withOpacity(0.3))),
                        child:Row(mainAxisSize:MainAxisSize.min,children:[
                          Icon(Icons.person_add_outlined,size:12,color:widget.color),const SizedBox(width:4),
                          Text('+ जोड़ें',style:TextStyle(color:widget.color,fontSize:11,fontWeight:FontWeight.w700))]))),
                  ]),
                  const SizedBox(height:10),
                  ..._officers.asMap().entries.map((entry)=>_OfficerCard(
                    key:ValueKey(entry.key),index:entry.key,officer:entry.value,
                    color:widget.color,allowedRanks:widget.officerRanks,
                    canRemove:_officers.length>1,activeElectionId:widget.election.id,
                    onRemove:()=>setState(()=>_officers.removeAt(entry.key)),
                    onChanged:()=>setState((){}),)),
                ],
              ]))),
            Padding(padding:const EdgeInsets.fromLTRB(16,8,16,16),
              child:Row(children:[
                Expanded(child:OutlinedButton(onPressed:_saving?null:()=>Navigator.pop(context),
                  style:OutlinedButton.styleFrom(foregroundColor:_kSubtle,side:const BorderSide(color:_kBorder),
                      padding:const EdgeInsets.symmetric(vertical:13),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10))),
                  child:const Text('रद्द'))),
                const SizedBox(width:12),
                Expanded(child:ElevatedButton(onPressed:_saving?null:_save,
                  style:ElevatedButton.styleFrom(backgroundColor:widget.color,foregroundColor:Colors.white,
                      padding:const EdgeInsets.symmetric(vertical:13),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10))),
                  child:_saving?const SizedBox(width:18,height:18,child:CircularProgressIndicator(color:Colors.white,strokeWidth:2))
                      :const Text('सेव करें',style:TextStyle(fontWeight:FontWeight.w700)))),
              ])),
          ])),
      ),
    );
  }
}

class _ElectionWarningBanner extends StatelessWidget {
  final _ElectionState election;
  const _ElectionWarningBanner({required this.election});
  @override
  Widget build(BuildContext context) {
    late Color col,bgColor; late IconData ico; late String msg;
    switch(election.loadStatus){
      case _ElectionLoadStatus.loading:
        col=_kAmber;bgColor=_kAmber.withOpacity(0.08);ico=Icons.hourglass_top_rounded;
        msg='चुनाव स्थिति लोड हो रही है।';
      case _ElectionLoadStatus.finalized:
        col=_kError;bgColor=_kError.withOpacity(0.07);ico=Icons.archive_rounded;
        msg='"${election.name}" समाप्त — assignment अक्षम।';
      case _ElectionLoadStatus.error:
        col=_kError;bgColor=_kError.withOpacity(0.07);ico=Icons.wifi_off_rounded;
        msg=election.errorMsg.isNotEmpty?election.errorMsg:'लोड नहीं हो सकी।';
      default:
        col=_kAmber;bgColor=_kAmber.withOpacity(0.08);ico=Icons.warning_amber_rounded;
        msg='कोई सक्रिय चुनाव नहीं — Master admin से कॉन्फ़िगर करवाएं।';
    }
    return Container(padding:const EdgeInsets.symmetric(horizontal:14,vertical:10),color:bgColor,
      child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Icon(ico,size:14,color:col),const SizedBox(width:8),
        Expanded(child:Text(msg,style:TextStyle(color:col,fontSize:11,fontWeight:FontWeight.w600)))]));
  }
}

class _OfficerEntry {
  int? id,userId;
  final nameCtrl=TextEditingController();
  final pnoCtrl=TextEditingController();
  final mobileCtrl=TextEditingController();
  final rankCtrl=TextEditingController();
  String selectedRank='';
  _OfficerEntry();
  factory _OfficerEntry.fromMap(Map<String,dynamic> m){
    final e=_OfficerEntry()..id=m['id']..userId=m['userId']..selectedRank=m['rank']??'';
    e.nameCtrl.text=m['name']??''; e.pnoCtrl.text=m['pno']??'';
    e.mobileCtrl.text=m['mobile']??''; e.rankCtrl.text=m['rank']??'';
    return e;
  }
  Map<String,dynamic> toMap()=>{
    if(id!=null)'id':id,if(userId!=null)'userId':userId,
    'name':nameCtrl.text.trim(),'pno':pnoCtrl.text.trim(),
    'mobile':mobileCtrl.text.trim(),'rank':rankCtrl.text.trim().isNotEmpty?rankCtrl.text.trim():selectedRank,
  };
  void dispose(){nameCtrl.dispose();pnoCtrl.dispose();mobileCtrl.dispose();rankCtrl.dispose();}
}

class _OfficerCard extends StatefulWidget {
  final int index; final _OfficerEntry officer; final Color color;
  final List<String> allowedRanks; final bool canRemove; final int? activeElectionId;
  final VoidCallback onRemove,onChanged;
  const _OfficerCard({super.key,required this.index,required this.officer,
    required this.color,required this.allowedRanks,required this.canRemove,
    required this.onRemove,required this.onChanged,this.activeElectionId});
  @override State<_OfficerCard> createState()=>_OfficerCardState();
}

class _OfficerCardState extends State<_OfficerCard> {
  bool _expanded=true,_disposed=false;
  @override void dispose(){_disposed=true;super.dispose();}

  void _openPicker() async {
    if(_disposed||!mounted)return;
    final picked=await showModalBottomSheet<Map<String,dynamic>>(
      context:context,isScrollControlled:true,backgroundColor:Colors.transparent,
      builder:(_)=>_StaffPickerSheet(allowedRanks:widget.allowedRanks,color:widget.color));
    if(picked!=null&&!_disposed&&mounted){
      setState((){
        widget.officer.userId=picked['id'] as int?;
        widget.officer.nameCtrl.text=picked['name']??'';
        widget.officer.pnoCtrl.text=picked['pno']??'';
        widget.officer.mobileCtrl.text=picked['mobile']??'';
        widget.officer.rankCtrl.text=picked['rank']??'';
        widget.officer.selectedRank=picked['rank']??'';
      });
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasData=widget.officer.nameCtrl.text.trim().isNotEmpty;
    return Container(margin:const EdgeInsets.only(bottom:10),
      decoration:BoxDecoration(
        color:hasData?widget.color.withOpacity(0.04):Colors.white,
        borderRadius:BorderRadius.circular(10),
        border:Border.all(color:hasData?widget.color.withOpacity(0.3):_kBorder.withOpacity(0.4))),
      child:Column(children:[
        GestureDetector(
          onTap:(){if(!_disposed&&mounted)setState(()=>_expanded=!_expanded);},
          child:Padding(padding:const EdgeInsets.fromLTRB(12,10,10,10),child:Row(children:[
            Container(width:28,height:28,
              decoration:BoxDecoration(color:widget.color.withOpacity(0.12),shape:BoxShape.circle),
              child:Center(child:Text('${widget.index+1}',
                  style:TextStyle(color:widget.color,fontWeight:FontWeight.w900,fontSize:12)))),
            const SizedBox(width:10),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(hasData?widget.officer.nameCtrl.text:'अधिकारी ${widget.index+1}',
                  style:TextStyle(color:hasData?_kDark:_kSubtle,fontWeight:FontWeight.w700,fontSize:13)),
              if(hasData&&widget.officer.rankCtrl.text.isNotEmpty)
                Text(widget.officer.rankCtrl.text,style:TextStyle(color:widget.color,fontSize:11)),
            ])),
            GestureDetector(onTap:_openPicker,
              child:Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
                decoration:BoxDecoration(color:_kInfo.withOpacity(0.08),borderRadius:BorderRadius.circular(6),
                    border:Border.all(color:_kInfo.withOpacity(0.3))),
                child:const Row(mainAxisSize:MainAxisSize.min,children:[
                  Icon(Icons.search,size:12,color:_kInfo),SizedBox(width:3),
                  Text('Staff',style:TextStyle(color:_kInfo,fontSize:10,fontWeight:FontWeight.w700))]))),
            const SizedBox(width:6),
            Icon(_expanded?Icons.expand_less:Icons.expand_more,color:_kSubtle,size:18),
            if(widget.canRemove)...[const SizedBox(width:4),
              GestureDetector(onTap:widget.onRemove,
                child:const Icon(Icons.remove_circle_outline,color:_kError,size:18))],
          ])),
        ),
        AnimatedCrossFade(
          firstChild:const SizedBox.shrink(),
          secondChild:Padding(padding:const EdgeInsets.fromLTRB(12,0,12,12),child:Column(children:[
            if(widget.allowedRanks.isNotEmpty)...[
              DropdownButtonFormField<String>(
                value:widget.officer.rankCtrl.text.isNotEmpty&&widget.allowedRanks.contains(widget.officer.rankCtrl.text)
                    ?widget.officer.rankCtrl.text:null,
                decoration:InputDecoration(labelText:'पद / Rank',labelStyle:const TextStyle(color:_kSubtle,fontSize:12),
                  prefixIcon:Icon(Icons.military_tech_outlined,size:18,color:widget.color),
                  filled:true,fillColor:Colors.white,isDense:true,
                  contentPadding:const EdgeInsets.symmetric(horizontal:12,vertical:11),
                  border:OutlineInputBorder(borderRadius:BorderRadius.circular(10),borderSide:const BorderSide(color:_kBorder)),
                  enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(10),borderSide:const BorderSide(color:_kBorder)),
                  focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(10),borderSide:BorderSide(color:widget.color,width:2))),
                items:widget.allowedRanks.map((r)=>DropdownMenuItem(value:r,
                    child:Text(r,style:const TextStyle(color:_kDark,fontSize:13)))).toList(),
                onChanged:(v){if(v!=null&&!_disposed&&mounted)
                  setState((){widget.officer.rankCtrl.text=v;widget.officer.selectedRank=v;});},
                dropdownColor:_kBg),
              const SizedBox(height:8),
            ],
            _field(widget.officer.nameCtrl,'पूरा नाम *',Icons.person_outline,widget.color),
            _field(widget.officer.pnoCtrl,'PNO',Icons.badge_outlined,widget.color),
            _field(widget.officer.mobileCtrl,'मोबाइल',Icons.phone_outlined,widget.color,type:TextInputType.phone),
            if(widget.activeElectionId!=null) Container(
              padding:const EdgeInsets.symmetric(horizontal:10,vertical:7),
              decoration:BoxDecoration(color:_kSuccess.withOpacity(0.06),borderRadius:BorderRadius.circular(8),
                  border:Border.all(color:_kSuccess.withOpacity(0.2))),
              child:Row(children:[
                const Icon(Icons.how_to_vote_outlined,size:13,color:_kSuccess),const SizedBox(width:6),
                Text('Election ID: ${widget.activeElectionId} — tag होगा',
                    style:const TextStyle(color:_kSuccess,fontSize:10,fontWeight:FontWeight.w600))])),
          ])),
          crossFadeState:_expanded?CrossFadeState.showSecond:CrossFadeState.showFirst,
          duration:const Duration(milliseconds:200)),
      ]));
  }

  Widget _field(TextEditingController ctrl,String label,IconData icon,Color color,{TextInputType? type})=>
    Padding(padding:const EdgeInsets.only(bottom:8),child:TextField(controller:ctrl,keyboardType:type,
      style:const TextStyle(color:_kDark,fontSize:13),
      decoration:InputDecoration(labelText:label,labelStyle:const TextStyle(color:_kSubtle,fontSize:12),
        prefixIcon:Icon(icon,size:18,color:color),filled:true,fillColor:Colors.white,isDense:true,
        contentPadding:const EdgeInsets.symmetric(horizontal:12,vertical:11),
        border:OutlineInputBorder(borderRadius:BorderRadius.circular(10),borderSide:const BorderSide(color:_kBorder)),
        enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(10),borderSide:const BorderSide(color:_kBorder)),
        focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(10),borderSide:BorderSide(color:color,width:2)))));
}

// ─── Center Dialog ────────────────────────────────────────────────────────────

class _CenterDialog extends StatefulWidget {
  final int gpId; final Map? existing; final VoidCallback onDone;
  const _CenterDialog({required this.gpId,this.existing,required this.onDone});
  @override State<_CenterDialog> createState()=>_CenterDialogState();
}

class _CenterDialogState extends State<_CenterDialog> {
  final _nameCtrl=TextEditingController(); final _addressCtrl=TextEditingController();
  final _thanaCtrl=TextEditingController(); final _busCtrl=TextEditingController();
  final _latCtrl=TextEditingController(); final _lngCtrl=TextEditingController();
  final _boothCtrl=TextEditingController(text:'1');
  String _type='C'; bool _saving=false,_disposed=false;

  @override
  void initState(){
    super.initState();
    if(widget.existing!=null){
      _nameCtrl.text=widget.existing!['name'] as String? ?? '';
      _addressCtrl.text=widget.existing!['address'] as String? ?? '';
      _thanaCtrl.text=widget.existing!['thana'] as String? ?? '';
      _busCtrl.text=widget.existing!['busNo'] as String? ?? '';
      _latCtrl.text=(widget.existing!['latitude']??'').toString();
      _lngCtrl.text=(widget.existing!['longitude']??'').toString();
      _type=widget.existing!['centerType'] as String? ?? 'C';
      _boothCtrl.text='${widget.existing!['boothCount']??widget.existing!['booth_count']??1}';
    }
  }
  @override void dispose(){_disposed=true;for(final c in [_nameCtrl,_addressCtrl,_thanaCtrl,_busCtrl,_latCtrl,_lngCtrl,_boothCtrl])c.dispose();super.dispose();}
  void _safeSetState(VoidCallback fn){if(!_disposed&&mounted)setState(fn);}
  Color get _typeColor=>switch(_type){'A++'=>const Color(0xFF6A1B9A),'A'=>const Color(0xFFC62828),'B'=>const Color(0xFFE65100),_=>const Color(0xFF1A5276)};

  Future<void> _save() async {
    if(_nameCtrl.text.trim().isEmpty){_snack('नाम आवश्यक है',error:true);return;}
    final bc=int.tryParse(_boothCtrl.text.trim())??1;
    if(bc<1){_snack('बूथ संख्या कम से कम 1',error:true);return;}
    _safeSetState(()=>_saving=true);
    try {
      final token=await AuthService.getToken(); if(_disposed)return;
      final body={'name':_nameCtrl.text.trim(),'address':_addressCtrl.text.trim(),
        'thana':_thanaCtrl.text.trim(),'busNo':_busCtrl.text.trim(),'centerType':_type,'boothCount':bc,
        'latitude':_latCtrl.text.trim().isEmpty?null:double.tryParse(_latCtrl.text.trim()),
        'longitude':_lngCtrl.text.trim().isEmpty?null:double.tryParse(_lngCtrl.text.trim())};
      final isEdit=widget.existing!=null;
      if(isEdit) await ApiService.put('/admin/centers/${widget.existing!['id']}',body,token:token);
      else       await ApiService.post('/admin/gram-panchayats/${widget.gpId}/centers',body,token:token);
      if(_disposed)return;
      if(mounted)Navigator.pop(context);
      widget.onDone();
    } catch(e){_safeSetState(()=>_saving=false);_snack('Error: $e',error:true);}
  }

  void _snack(String msg,{bool error=false}){if(_disposed||!mounted)return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(msg),
      backgroundColor:error?_kError:_kSuccess,behavior:SnackBarBehavior.floating,
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10))));}

  @override
  Widget build(BuildContext context) {
    return Dialog(backgroundColor:Colors.transparent,insetPadding:const EdgeInsets.symmetric(horizontal:12,vertical:20),
      child:ConstrainedBox(constraints:BoxConstraints(maxWidth:520,maxHeight:MediaQuery.of(context).size.height*0.9),
        child:Container(
          decoration:BoxDecoration(color:_kBg,borderRadius:BorderRadius.circular(16),
            border:Border.all(color:_kBorder,width:1.2),
            boxShadow:[BoxShadow(color:_typeColor.withOpacity(0.15),blurRadius:20,offset:const Offset(0,8))]),
          child:Column(mainAxisSize:MainAxisSize.min,children:[
            Container(padding:const EdgeInsets.fromLTRB(16,13,12,13),
              decoration:const BoxDecoration(color:_kDark,borderRadius:BorderRadius.only(topLeft:Radius.circular(15),topRight:Radius.circular(15))),
              child:Row(children:[
                Container(padding:const EdgeInsets.all(6),
                  decoration:BoxDecoration(color:_typeColor.withOpacity(0.25),borderRadius:BorderRadius.circular(7)),
                  child:Icon(Icons.location_on_outlined,color:_typeColor,size:16)),
                const SizedBox(width:10),
                Expanded(child:Text(widget.existing==null?'Election Center जोड़ें':'Center संपादित करें',
                    style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w700,fontSize:15))),
                IconButton(onPressed:_saving?null:()=>Navigator.pop(context),
                    icon:const Icon(Icons.close,color:Colors.white60,size:20),
                    padding:EdgeInsets.zero,constraints:const BoxConstraints()),
              ])),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    _ff(
                      _nameCtrl,
                      'Center का नाम *',
                      Icons.location_on_outlined,
                    ),

                    _ff(
                      _addressCtrl,
                      'पता',
                      Icons.map_outlined,
                    ),

                    // ─── LATITUDE & LONGITUDE ──────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: _ff(
                            _latCtrl,
                            'Latitude',
                            Icons.my_location_outlined,
                            type: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                          ),
                        ),

                        const SizedBox(width: 10),

                        Expanded(
                          child: _ff(
                            _lngCtrl,
                            'Longitude',
                            Icons.explore_outlined,
                            type: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // ─── THANA & BUS ───────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: _ff(
                            _thanaCtrl,
                            'थाना',
                            Icons.local_police_outlined,
                          ),
                        ),

                        const SizedBox(width: 10),

                        Expanded(
                          child: _ff(
                            _busCtrl,
                            'Bus No',
                            Icons.directions_bus_outlined,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    const Text(
                      'बूथ संख्या *',
                      style: TextStyle(
                        color: _kDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Row(
                      children: [

                        // ─── MINUS BUTTON ─────────────────────────────
                        _sb(
                          Icons.remove,
                          () {
                            final v = int.tryParse(_boothCtrl.text) ?? 1;

                            if (v > 1) {
                              setState(() {
                                _boothCtrl.text = '${v - 1}';
                              });
                            }
                          },
                        ),

                        const SizedBox(width: 10),

                        // ─── BOOTH COUNT FIELD ───────────────────────
                        Expanded(
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _typeColor.withOpacity(0.6),
                                width: 1.5,
                              ),
                            ),

                            child: TextField(
                              controller: _boothCtrl,
                              keyboardType: TextInputType.number,

                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(2),
                              ],

                              textAlign: TextAlign.center,

                              style: TextStyle(
                                color: _typeColor,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),

                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 10),

                        // ─── PLUS BUTTON ──────────────────────────────
                        _sb(
                          Icons.add,
                          () {
                            final v = int.tryParse(_boothCtrl.text) ?? 1;

                            if (v < 15) {
                              setState(() {
                                _boothCtrl.text = '${v + 1}';
                              });
                            }
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    Center(
                      child: Text(
                        '(1 से 15 तक) — 1 center = 1 manak set',
                        style: TextStyle(
                          color: _kSubtle.withOpacity(0.7),
                          fontSize: 10,
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    const Text(
                      'Center Type / संवेदनशीलता',
                      style: TextStyle(
                        color: _kDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Row(
                      children: ['A++', 'A', 'B', 'C'].map((t) {

                        final sel = _type == t;

                        final c = switch (t) {
                          'A++' => const Color(0xFF6A1B9A),
                          'A'   => const Color(0xFFC62828),
                          'B'   => const Color(0xFFE65100),
                          _     => const Color(0xFF1A5276),
                        };

                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _type = t),

                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),

                              margin: EdgeInsets.only(
                                right: t == 'C' ? 0 : 8,
                              ),

                              padding: const EdgeInsets.symmetric(vertical: 10),

                              decoration: BoxDecoration(
                                color: sel ? c : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: c,
                                  width: sel ? 2 : 1,
                                ),
                              ),

                              child: Column(
                                children: [

                                  Text(
                                    t,
                                    style: TextStyle(
                                      color: sel ? Colors.white : c,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),

                                  Text(
                                    switch (t) {
                                      'A++' => 'अति-अति',
                                      'A'   => 'अति',
                                      'B'   => 'संवेदनशील',
                                      _     => 'सामान्य',
                                    },

                                    style: TextStyle(
                                      color: sel
                                          ? Colors.white70
                                          : c.withOpacity(0.7),
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            Padding(padding:const EdgeInsets.fromLTRB(16,8,16,16),child:Row(children:[
              Expanded(child:OutlinedButton(onPressed:_saving?null:()=>Navigator.pop(context),
                style:OutlinedButton.styleFrom(foregroundColor:_kSubtle,side:const BorderSide(color:_kBorder),
                    padding:const EdgeInsets.symmetric(vertical:13),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10))),
                child:const Text('रद्द'))),
              const SizedBox(width:12),
              Expanded(child:ElevatedButton(onPressed:_saving?null:_save,
                style:ElevatedButton.styleFrom(backgroundColor:_typeColor,foregroundColor:Colors.white,
                    padding:const EdgeInsets.symmetric(vertical:13),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10))),
                child:_saving?const SizedBox(width:18,height:18,child:CircularProgressIndicator(color:Colors.white,strokeWidth:2))
                    :Text(widget.existing==null?'Center जोड़ें':'अपडेट करें',style:const TextStyle(fontWeight:FontWeight.w700)))),
            ])),
          ]))));
  }
  Widget _ff(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType? type,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: ctrl,
          keyboardType: type,
          style: const TextStyle(
            color: _kDark,
            fontSize: 13,
          ),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(
              color: _kSubtle,
              fontSize: 12,
            ),
            prefixIcon: Icon(
              icon,
              size: 18,
              color: _typeColor,
            ),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 11,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _kBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _kBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: _typeColor,
                width: 2,
              ),
            ),
          ),
        ),
      );

 Widget _sb(
    IconData icon,
    VoidCallback onTap,
  ) {
    return Material(
      color: _typeColor,
      borderRadius: BorderRadius.circular(10),

      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,

        child: SizedBox(
          width: 44,
          height: 48,

          child: Icon(
            icon,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

Widget _emptyState(String label,IconData icon,Color color)=>Center(
  child:Padding(padding:const EdgeInsets.all(40),child:Column(mainAxisSize:MainAxisSize.min,children:[
    Container(padding:const EdgeInsets.all(20),
      decoration:BoxDecoration(color:color.withOpacity(0.08),shape:BoxShape.circle),
      child:Icon(icon,size:48,color:color.withOpacity(0.5))),
    const SizedBox(height:16),
    Text('कोई $label नहीं',style:const TextStyle(color:_kDark,fontSize:14,fontWeight:FontWeight.w700)),
    const SizedBox(height:6),
    const Text('ऊपर जोड़ें बटन दबाएं',style:TextStyle(color:_kSubtle,fontSize:12))])));

Future<bool> _confirm(BuildContext ctx,String msg) async =>
  await showDialog<bool>(context:ctx,builder:(d)=>AlertDialog(backgroundColor:_kBg,
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14),side:const BorderSide(color:_kError,width:1.2)),
    title:const Row(children:[Icon(Icons.warning_amber_rounded,color:_kError,size:20),SizedBox(width:8),
      Text('Confirm Delete',style:TextStyle(color:_kError,fontWeight:FontWeight.w800,fontSize:15))]),
    content:Text(msg,style:const TextStyle(color:_kDark,fontSize:13)),
    actions:[
      TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('रद्द',style:TextStyle(color:_kSubtle))),
      ElevatedButton(onPressed:()=>Navigator.pop(d,true),
        style:ElevatedButton.styleFrom(backgroundColor:_kError,foregroundColor:Colors.white,
            shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(8))),
        child:const Text('हटाएं'))]))??false;