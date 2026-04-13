import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';

// ── Palette (matches app theme) ──────────────────────────────────────────────
const _kBg      = Color(0xFFFDF6E3);
const _kSurface = Color(0xFFF5E6C8);
const _kPrimary = Color(0xFF8B6914);
const _kAccent  = Color(0xFFB8860B);
const _kDark    = Color(0xFF4A3000);
const _kSubtle  = Color(0xFFAA8844);
const _kBorder  = Color(0xFFD4A843);
const _kError   = Color(0xFFC0392B);
const _kSuccess = Color(0xFF2D6A1E);
const _kInfo    = Color(0xFF1A5276);

// ── Step definitions ─────────────────────────────────────────────────────────
const _kSteps = [
  {'id': 0, 'label': 'Super Zone', 'icon': Icons.layers_outlined,         'color': Color(0xFF6A1B9A)},
  {'id': 1, 'label': 'Zone',       'icon': Icons.grid_view_outlined,       'color': Color(0xFF1565C0)},
  {'id': 2, 'label': 'Sector',     'icon': Icons.view_module_outlined,     'color': Color(0xFF2E7D32)},
  {'id': 3, 'label': 'GP',         'icon': Icons.account_balance_outlined, 'color': Color(0xFF6D4C41)},
  {'id': 4, 'label': 'Center',     'icon': Icons.location_on_outlined,     'color': Color(0xFFC62828)},
];

// ── Rank definitions ─────────────────────────────────────────────────────────
const _kRanks = ['SP','ASP','DSP','Inspector','SI','ASI','Head Constable','Constable'];

const _kRankColors = {
  'SP':            Color(0xFF6A1B9A),
  'ASP':           Color(0xFF1565C0),
  'DSP':           Color(0xFF1A5276),
  'Inspector':     Color(0xFF2E7D32),
  'SI':            Color(0xFF558B2F),
  'ASI':           Color(0xFF8B6914),
  'Head Constable':Color(0xFFB8860B),
  'Constable':     Color(0xFF6D4C41),
};

// Rank hierarchy for lower-rank fallback
const _kRankHierarchy = [
  'SP', 'ASP', 'DSP', 'Inspector', 'SI', 'ASI', 'Head Constable', 'Constable'
];

const _kLevelRanks = {
  0: ['SP', 'ASP', 'DSP'],
  1: ['Inspector', 'SI'],
  2: ['ASI', 'Head Constable', 'Constable'],
};

const _kLevelOfficerTitle = {
  0: 'क्षेत्र अधिकारी (Kshetra Adhikari)',
  1: 'निरीक्षक (Nirakshak)',
  2: 'उप-निरीक्षक / पुलिस अधिकारी',
};

// ── Custom rank rule model ────────────────────────────────────────────────────
class _RankRule {
  String rank;
  int count;
  _RankRule({required this.rank, required this.count});
  Map<String, dynamic> toMap() => {'rank': rank, 'count': count};
}

// ══════════════════════════════════════════════════════════════════════════════
//  FORM PAGE — 5-step stepper
// ══════════════════════════════════════════════════════════════════════════════

class FormPage extends StatefulWidget {
  const FormPage({super.key});
  @override
  State<FormPage> createState() => _FormPageState();
}

class _FormPageState extends State<FormPage> {
  int _step = 0;

  int?    _selectedSZId,     _selectedZoneId,   _selectedSectorId, _selectedGPId;
  String? _selectedSZName,   _selectedZoneName, _selectedSectorName, _selectedGPName;

  void _goToStep(int step) {
    if (!mounted) return;
    setState(() {
      _step = step;
      if (step <= 0) { _selectedSZId     = null; _selectedSZName     = null; }
      if (step <= 1) { _selectedZoneId   = null; _selectedZoneName   = null; }
      if (step <= 2) { _selectedSectorId = null; _selectedSectorName = null; }
      if (step <= 3) { _selectedGPId     = null; _selectedGPName     = null; }
    });
  }

  void _onSZSelected(Map item) {
    if (!mounted) return;
    setState(() {
      _selectedSZId       = item['id'] as int;
      _selectedSZName     = item['name'] as String? ?? '';
      _selectedZoneId     = null; _selectedZoneName     = null;
      _selectedSectorId   = null; _selectedSectorName   = null;
      _selectedGPId       = null; _selectedGPName       = null;
      _step = 1;
    });
  }

  void _onZoneSelected(Map item) {
    if (!mounted) return;
    setState(() {
      _selectedZoneId     = item['id'] as int;
      _selectedZoneName   = item['name'] as String? ?? '';
      _selectedSectorId   = null; _selectedSectorName   = null;
      _selectedGPId       = null; _selectedGPName       = null;
      _step = 2;
    });
  }

  void _onSectorSelected(Map item) {
    if (!mounted) return;
    setState(() {
      _selectedSectorId   = item['id'] as int;
      _selectedSectorName = item['name'] as String? ?? '';
      _selectedGPId       = null; _selectedGPName       = null;
      _step = 3;
    });
  }

  void _onGPSelected(Map item) {
    if (!mounted) return;
    setState(() {
      _selectedGPId   = item['id'] as int;
      _selectedGPName = item['name'] as String? ?? '';
      _step = 4;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _StepBar(
        currentStep: _step, onTap: _goToStep,
        szName: _selectedSZName, zoneName: _selectedZoneName,
        sectorName: _selectedSectorName, gpName: _selectedGPName,
      ),
      if (_step > 0)
        _Breadcrumb(
          step: _step,
          szName: _selectedSZName, zoneName: _selectedZoneName,
          sectorName: _selectedSectorName, gpName: _selectedGPName,
          onTap: _goToStep,
        ),
      Expanded(child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(0.05, 0), end: Offset.zero).animate(anim),
            child: child,
          ),
        ),
        child: _buildStep(),
      )),
    ]);
  }

  Widget _buildStep() {
    switch (_step) {
      case 0: return _StepList(
          key: const ValueKey('sz'),
          title: 'Super Zones', icon: Icons.layers_outlined, color: const Color(0xFF6A1B9A),
          officerTitle: _kLevelOfficerTitle[0]!, officerRanks: _kLevelRanks[0]!,
          fetchUrl: '/admin/super-zones', createUrl: '/admin/super-zones',
          updateUrlFn: (id) => '/admin/super-zones/$id',
          deleteUrlFn: (id) => '/admin/super-zones/$id',
          fields: const ['name','district','block'],
          onSelect: _onSZSelected, selectedId: _selectedSZId);

      case 1: return _StepList(
          key: ValueKey('zone_$_selectedSZId'),
          title: 'Zones', icon: Icons.grid_view_outlined, color: const Color(0xFF1565C0),
          officerTitle: _kLevelOfficerTitle[1]!, officerRanks: _kLevelRanks[1]!,
          fetchUrl: '/admin/super-zones/$_selectedSZId/zones',
          createUrl: '/admin/super-zones/$_selectedSZId/zones',
          updateUrlFn: (id) => '/admin/zones/$id',
          deleteUrlFn: (id) => '/admin/zones/$id',
          fields: const ['name','hqAddress'],
          onSelect: _onZoneSelected, selectedId: _selectedZoneId);

      case 2: return _StepList(
          key: ValueKey('sector_$_selectedZoneId'),
          title: 'Sectors', icon: Icons.view_module_outlined, color: const Color(0xFF2E7D32),
          officerTitle: _kLevelOfficerTitle[2]!, officerRanks: _kLevelRanks[2]!,
          fetchUrl: '/admin/zones/$_selectedZoneId/sectors',
          createUrl: '/admin/zones/$_selectedZoneId/sectors',
          updateUrlFn: (id) => '/admin/sectors/$id',
          deleteUrlFn: (id) => '/admin/sectors/$id',
          fields: const ['name'],
          onSelect: _onSectorSelected, selectedId: _selectedSectorId);

      case 3: return _StepList(
          key: ValueKey('gp_$_selectedSectorId'),
          title: 'Gram Panchayats', icon: Icons.account_balance_outlined, color: const Color(0xFF6D4C41),
          officerTitle: '', officerRanks: const [],
          fetchUrl: '/admin/sectors/$_selectedSectorId/gram-panchayats',
          createUrl: '/admin/sectors/$_selectedSectorId/gram-panchayats',
          updateUrlFn: (id) => '/admin/gram-panchayats/$id',
          deleteUrlFn: (id) => '/admin/gram-panchayats/$id',
          fields: const ['name','address'],
          onSelect: _onGPSelected, selectedId: _selectedGPId);

      case 4: return _CenterStep(key: ValueKey('center_$_selectedGPId'), gpId: _selectedGPId!);

      default: return const SizedBox.shrink();
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  STEP BAR
// ══════════════════════════════════════════════════════════════════════════════

class _StepBar extends StatelessWidget {
  final int currentStep;
  final void Function(int) onTap;
  final String? szName, zoneName, sectorName, gpName;
  const _StepBar({required this.currentStep, required this.onTap,
    this.szName, this.zoneName, this.sectorName, this.gpName});

  bool _isEnabled(int step) {
    if (step == 0) return true;
    if (step == 1) return szName != null;
    if (step == 2) return zoneName != null;
    if (step == 3) return sectorName != null;
    if (step == 4) return gpName != null;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kDark,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(children: List.generate(_kSteps.length, (i) {
        final step  = _kSteps[i];
        final label = step['label'] as String;
        final icon  = step['icon'] as IconData;
        final color = step['color'] as Color;
        final isCur  = currentStep == i;
        final isDone = currentStep > i;
        final isEn   = _isEnabled(i);

        return Expanded(child: GestureDetector(
          onTap: isEn ? () => onTap(i) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: isCur ? color : isDone ? color.withOpacity(0.2) : Colors.white12,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isCur ? color : isDone ? color.withOpacity(0.4) : Colors.white24),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(isDone ? Icons.check_circle_rounded : icon,
                  size: 18,
                  color: isCur ? Colors.white : isDone ? color : Colors.white38),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                    color: isCur ? Colors.white : isDone ? color : Colors.white38,
                    fontSize: 9, fontWeight: isCur ? FontWeight.w800 : FontWeight.w500),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ));
      })),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  BREADCRUMB
// ══════════════════════════════════════════════════════════════════════════════

class _Breadcrumb extends StatelessWidget {
  final int step;
  final String? szName, zoneName, sectorName, gpName;
  final void Function(int) onTap;
  const _Breadcrumb({required this.step, this.szName, this.zoneName,
    this.sectorName, this.gpName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final crumbs = <_Crumb>[];
    if (szName     != null) crumbs.add(_Crumb(szName!,     Icons.layers_outlined,           const Color(0xFF6A1B9A), 0));
    if (zoneName   != null) crumbs.add(_Crumb(zoneName!,   Icons.grid_view_outlined,         const Color(0xFF1565C0), 1));
    if (sectorName != null) crumbs.add(_Crumb(sectorName!, Icons.view_module_outlined,       const Color(0xFF2E7D32), 2));
    if (gpName     != null) crumbs.add(_Crumb(gpName!,     Icons.account_balance_outlined,   const Color(0xFF6D4C41), 3));

    return Container(
      color: _kSurface.withOpacity(0.7),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (int i = 0; i < crumbs.length; i++) ...[
            if (i > 0) const Icon(Icons.chevron_right, size: 14, color: _kSubtle),
            GestureDetector(
              onTap: () => onTap(crumbs[i].step),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: crumbs[i].color.withOpacity(i == crumbs.length - 1 ? 0.12 : 0.06),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: crumbs[i].color.withOpacity(i == crumbs.length - 1 ? 0.4 : 0.2)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(crumbs[i].icon, size: 11, color: crumbs[i].color),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 100),
                    child: Text(crumbs[i].name,
                        style: TextStyle(color: crumbs[i].color, fontSize: 11,
                            fontWeight: i == crumbs.length - 1 ? FontWeight.w700 : FontWeight.w500),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _Crumb {
  final String name; final IconData icon; final Color color; final int step;
  _Crumb(this.name, this.icon, this.color, this.step);
}

// ══════════════════════════════════════════════════════════════════════════════
//  GENERIC STEP LIST
// ══════════════════════════════════════════════════════════════════════════════

class _StepList extends StatefulWidget {
  final String title, fetchUrl, createUrl;
  final String Function(int) updateUrlFn, deleteUrlFn;
  final List<String> fields;
  final IconData icon;
  final Color color;
  final String officerTitle;
  final List<String> officerRanks;
  final void Function(Map) onSelect;
  final int? selectedId;

  const _StepList({
    super.key,
    required this.title, required this.fetchUrl, required this.createUrl,
    required this.updateUrlFn, required this.deleteUrlFn,
    required this.fields, required this.icon, required this.color,
    required this.officerTitle, required this.officerRanks,
    required this.onSelect, this.selectedId,
  });

  @override
  State<_StepList> createState() => _StepListState();
}

class _StepListState extends State<_StepList> {
  final List<Map> _items = [];
  bool _loading    = true;
  bool _hasMore    = true;
  bool _loadingMore = false;
  int  _page = 1;
  static const _limit = 20;
  String _q = '';
  Timer? _debounce;
  final _searchCtrl = TextEditingController();
  final _scroll     = ScrollController();
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _searchCtrl.addListener(_onSearchChanged);
    _load(reset: true);
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (_disposed) return;
      final q = _searchCtrl.text.trim();
      if (q != _q) { _q = q; _reload(); }
    });
  }

  void _onScroll() {
    if (_disposed) return;
    if (_scroll.hasClients &&
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      _load();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _scroll.removeListener(_onScroll);
    _searchCtrl.removeListener(_onSearchChanged);
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!_disposed && mounted) setState(fn);
  }

  void _reload() {
    _safeSetState(() { _items.clear(); _page = 1; _hasMore = true; });
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_disposed) return;
    if (reset) {
      _safeSetState(() { _items.clear(); _page = 1; _hasMore = true; _loading = true; });
    }
    if (!_hasMore && !reset) return;
    if (_loadingMore) return;
    _safeSetState(() { if (!reset) _loadingMore = true; });

    try {
      final token = await AuthService.getToken();
      if (_disposed) return;

      final url = '${widget.fetchUrl}?page=$_page&limit=$_limit&q=${Uri.encodeComponent(_q)}';
      final res = await ApiService.get(url, token: token);
      if (_disposed) return;

      List<Map> items;
      int? totalPages;
      final data = res['data'];
      if (data is List) {
        items = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        totalPages = null;
      } else if (data is Map) {
        final inner = data['data'];
        items = (inner is List)
            ? inner.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : [];
        totalPages = (data['totalPages'] as num?)?.toInt();
      } else {
        items = [];
      }

      _safeSetState(() {
        _items.addAll(items);
        _hasMore = totalPages != null ? _page < totalPages : false;
        _page++;
        _loading      = false;
        _loadingMore  = false;
      });
    } catch (e) {
      _safeSetState(() { _loading = false; _loadingMore = false; });
      if (!_disposed && mounted) {
        _snack('Load failed: $e', error: true);
      }
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (_disposed || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? _kError : _kSuccess,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _delete(Map item) async {
    final confirmed = await _confirm(context, 'Delete "${item['name']}"?');
    if (!confirmed || _disposed) return;
    try {
      final token = await AuthService.getToken();
      if (_disposed) return;
      await ApiService.delete(widget.deleteUrlFn(item['id'] as int), token: token);
      if (_disposed) return;
      _snack('Deleted');
      _reload();
    } catch (e) {
      _snack('Delete failed: $e', error: true);
    }
  }

  void _openDialog({Map? existing}) {
    if (_disposed || !mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ItemDialog(
        title: existing == null
            ? 'Add ${widget.title.replaceAll('s', '').trim()}'
            : 'Edit',
        color: widget.color, icon: widget.icon,
        fields: widget.fields,
        officerTitle: widget.officerTitle,
        officerRanks: widget.officerRanks,
        existing: existing,
        createUrl: widget.createUrl,
        updateUrlFn: widget.updateUrlFn,
        onDone: () {
          if (!_disposed) _reload();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        color: _kSurface,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: widget.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(widget.icon, color: widget.color, size: 16)),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.title,
              style: const TextStyle(color: _kDark, fontWeight: FontWeight.w800, fontSize: 15))),
          GestureDetector(
            onTap: () => _openDialog(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(9)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add, color: Colors.white, size: 14),
                SizedBox(width: 4),
                Text('जोड़ें',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ]),
      ),
      Container(
        color: _kBg,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: TextField(
          controller: _searchCtrl,
          style: const TextStyle(color: _kDark, fontSize: 13),
          decoration: InputDecoration(
            hintText: '${widget.title} खोजें...',
            hintStyle: const TextStyle(color: _kSubtle, fontSize: 12),
            prefixIcon: const Icon(Icons.search, color: _kSubtle, size: 18),
            suffixIcon: _q.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16, color: _kSubtle),
                    onPressed: () { _searchCtrl.clear(); _q = ''; _reload(); },
                  )
                : null,
            filled: true, fillColor: Colors.white, isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: widget.color, width: 2)),
          ),
        ),
      ),
      Expanded(child: _loading
        ? const Center(child: CircularProgressIndicator(color: _kPrimary))
        : _items.isEmpty
            ? _emptyState(widget.title, widget.icon, widget.color)
            : RefreshIndicator(
                onRefresh: () async => _reload(),
                color: _kPrimary,
                child: Scrollbar(
                  controller: _scroll, thumbVisibility: true, thickness: 5,
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                    itemCount: _items.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= _items.length) {
                        return const Padding(padding: EdgeInsets.all(16),
                          child: Center(child: SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary))));
                      }
                      final item       = _items[i];
                      final isSelected = widget.selectedId == item['id'];
                      return _ItemCard(
                        item: item, color: widget.color, icon: widget.icon,
                        isSelected: isSelected,
                        onTap:    () => widget.onSelect(item),
                        onEdit:   () => _openDialog(existing: item),
                        onDelete: () => _delete(item),
                      );
                    },
                  ),
                ),
              )),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  ITEM CARD
// ══════════════════════════════════════════════════════════════════════════════

class _ItemCard extends StatelessWidget {
  final Map item; final Color color; final IconData icon;
  final bool isSelected;
  final VoidCallback onTap, onEdit, onDelete;
  const _ItemCard({required this.item, required this.color, required this.icon,
    required this.isSelected, required this.onTap, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final officers = (item['officers'] as List?)?.cast<Map>() ?? [];
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.07) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? color : _kBorder.withOpacity(0.4), width: isSelected ? 2 : 1),
          boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 38, height: 38,
              decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle,
                  border: Border.all(color: color.withOpacity(0.3))),
              child: Icon(isSelected ? Icons.check_circle_rounded : icon, color: color, size: 18)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(item['name'] ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: isSelected ? color : _kDark, fontWeight: FontWeight.w700, fontSize: 14))),
                if (isSelected) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: color.withOpacity(0.3))),
                  child: Text('चुना गया', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 4),
              Wrap(spacing: 10, runSpacing: 3, children: [
                if ((item['district'] as String?)?.isNotEmpty == true) _tag(Icons.location_city_outlined, item['district'] as String),
                if ((item['block'] as String?)?.isNotEmpty == true) _tag(Icons.domain_outlined, item['block'] as String),
                if ((item['hqAddress'] as String?)?.isNotEmpty == true) _tag(Icons.home_outlined, item['hqAddress'] as String),
                if (item['zoneCount']   != null) _tag(Icons.grid_view_outlined,       '${item['zoneCount']} Zones'),
                if (item['sectorCount'] != null) _tag(Icons.view_module_outlined,     '${item['sectorCount']} Sectors'),
                if (item['gpCount']     != null) _tag(Icons.account_balance_outlined, '${item['gpCount']} GPs'),
                if (item['centerCount'] != null) _tag(Icons.location_on_outlined,     '${item['centerCount']} Centers'),
              ]),
              if (officers.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 5, runSpacing: 4,
                  children: officers.take(3).map((o) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: color.withOpacity(0.06), borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: color.withOpacity(0.2))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.person_outline, size: 10, color: color),
                      const SizedBox(width: 3),
                      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 90),
                        child: Text('${o['name'] ?? ''}',
                            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if ((o['rank'] ?? '').isNotEmpty) ...[
                        const SizedBox(width: 3),
                        Text('(${o['rank']})', style: const TextStyle(color: _kSubtle, fontSize: 9)),
                      ],
                    ]),
                  )).toList()),
                if (officers.length > 3) Text('+${officers.length - 3} more', style: TextStyle(color: color, fontSize: 10)),
              ],
            ])),
            Column(mainAxisSize: MainAxisSize.min, children: [
              _iconBtn(Icons.edit_outlined,   _kInfo,  onEdit),
              const SizedBox(height: 4),
              _iconBtn(Icons.delete_outline, _kError, onDelete),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _tag(IconData icon, String text) =>
    Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 10, color: _kSubtle),
      const SizedBox(width: 3),
      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 120),
        child: Text(text, style: const TextStyle(color: _kSubtle, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]);

  Widget _iconBtn(IconData icon, Color c, VoidCallback onTap) =>
    GestureDetector(onTap: onTap,
      child: Container(width: 32, height: 32,
        decoration: BoxDecoration(color: c.withOpacity(0.08), borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.withOpacity(0.25))),
        child: Icon(icon, size: 15, color: c)));
}

// ══════════════════════════════════════════════════════════════════════════════
//  ITEM DIALOG
// ══════════════════════════════════════════════════════════════════════════════

class _ItemDialog extends StatefulWidget {
  final String title; final Color color; final IconData icon;
  final List<String> fields, officerRanks;
  final String officerTitle, createUrl;
  final String Function(int) updateUrlFn;
  final Map? existing;
  final VoidCallback onDone;
  const _ItemDialog({
    required this.title, required this.color, required this.icon,
    required this.fields, required this.officerTitle, required this.officerRanks,
    required this.createUrl, required this.updateUrlFn,
    this.existing, required this.onDone,
  });
  @override State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  final Map<String, TextEditingController> _ctrls = {};
  final List<_OfficerEntry> _officers = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      _ctrls[f] = TextEditingController(text: widget.existing?[f]?.toString() ?? '');
    }
    final existingOfficers = (widget.existing?['officers'] as List?) ?? [];
    for (final o in existingOfficers) {
      _officers.add(_OfficerEntry.fromMap(Map<String, dynamic>.from(o as Map)));
    }
    if (_officers.isEmpty && widget.officerRanks.isNotEmpty) {
      _officers.add(_OfficerEntry());
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) c.dispose();
    for (final o in _officers) o.dispose();
    super.dispose();
  }

  String _fieldLabel(String field) => switch(field) {
    'name'      => 'नाम *',
    'district'  => 'जिला',
    'block'     => 'ब्लॉक',
    'hqAddress' => 'मुख्यालय / HQ Address',
    'address'   => 'पता',
    _ => field,
  };

  IconData _fieldIcon(String field) => switch(field) {
    'name'      => Icons.label_outline,
    'district'  => Icons.location_city_outlined,
    'block'     => Icons.domain_outlined,
    'hqAddress' => Icons.home_outlined,
    'address'   => Icons.map_outlined,
    _ => Icons.edit_outlined,
  };

  Future<void> _save() async {
    final name = _ctrls['name']?.text.trim() ?? '';
    if (name.isEmpty) { _snack('नाम आवश्यक है', error: true); return; }
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final token = await AuthService.getToken();
      if (!mounted) return;
      final body = <String, dynamic>{};
      for (final f in widget.fields) { body[f] = _ctrls[f]?.text.trim() ?? ''; }
      body['officers'] = _officers.where((o) => o.nameCtrl.text.trim().isNotEmpty).map((o) => o.toMap()).toList();
      final isEdit = widget.existing != null;
      if (isEdit) {
        await ApiService.put(widget.updateUrlFn(widget.existing!['id'] as int), body, token: token);
      } else {
        await ApiService.post(widget.createUrl, body, token: token);
      }
      if (!mounted) return;
      final officers    = body['officers'] as List;
      final newOfficers = officers.where((o) => (o['userId'] == null) && (o['pno'] as String? ?? '').isNotEmpty).toList();
      if (newOfficers.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${newOfficers.length} अधिकारी यूज़र बने — Login: PNO, Password: PNO (default)'),
          backgroundColor: _kSuccess, duration: const Duration(seconds: 4), behavior: SnackBarBehavior.floating));
      }
      if (mounted) Navigator.pop(context);
      widget.onDone();
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      _snack('Error: $e', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg),
      backgroundColor: error ? _kError : _kSuccess, behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: Container(
          decoration: BoxDecoration(color: _kBg, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorder, width: 1.2),
            boxShadow: [BoxShadow(color: widget.color.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 8))]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
              decoration: BoxDecoration(color: _kDark,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15))),
              child: Row(children: [
                Container(padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: widget.color.withOpacity(0.25), borderRadius: BorderRadius.circular(7)),
                  child: Icon(widget.icon, color: widget.color, size: 16)),
                const SizedBox(width: 10),
                Expanded(child: Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
                IconButton(onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints()),
              ]),
            ),
            Flexible(child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ...widget.fields.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextFormField(controller: _ctrls[f],
                    style: const TextStyle(color: _kDark, fontSize: 13),
                    decoration: InputDecoration(labelText: _fieldLabel(f),
                      labelStyle: const TextStyle(color: _kSubtle, fontSize: 12),
                      prefixIcon: Icon(_fieldIcon(f), size: 18, color: widget.color),
                      filled: true, fillColor: Colors.white, isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: widget.color, width: 2)))),
                )),
                if (widget.officerRanks.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    Container(width: 3, height: 14, decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    Expanded(child: Text(widget.officerTitle, style: TextStyle(color: widget.color, fontSize: 12, fontWeight: FontWeight.w800))),
                    GestureDetector(
                      onTap: () => setState(() => _officers.add(_OfficerEntry())),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: widget.color.withOpacity(0.1), borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: widget.color.withOpacity(0.3))),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.person_add_outlined, size: 12, color: widget.color),
                          const SizedBox(width: 4),
                          Text('+ जोड़ें', style: TextStyle(color: widget.color, fontSize: 11, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  ..._officers.asMap().entries.map((entry) => _OfficerCard(
                    key: ValueKey(entry.key), index: entry.key, officer: entry.value,
                    color: widget.color, allowedRanks: widget.officerRanks,
                    canRemove: _officers.length > 1,
                    onRemove: () => setState(() => _officers.removeAt(entry.key)),
                    onChanged: () => setState(() {}),
                  )),
                ],
              ]),
            )),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(foregroundColor: _kSubtle, side: const BorderSide(color: _kBorder),
                      padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text('रद्द'))),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(backgroundColor: widget.color, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('सेव करें', style: TextStyle(fontWeight: FontWeight.w700)))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  OFFICER ENTRY MODEL
// ══════════════════════════════════════════════════════════════════════════════

class _OfficerEntry {
  int? id, userId;
  final nameCtrl   = TextEditingController();
  final pnoCtrl    = TextEditingController();
  final mobileCtrl = TextEditingController();
  final rankCtrl   = TextEditingController();
  String selectedRank = '';

  _OfficerEntry();

  factory _OfficerEntry.fromMap(Map<String, dynamic> m) {
    final e = _OfficerEntry()
      ..id          = m['id']
      ..userId      = m['userId']
      ..selectedRank = m['rank'] ?? '';
    e.nameCtrl.text   = m['name']   ?? '';
    e.pnoCtrl.text    = m['pno']    ?? '';
    e.mobileCtrl.text = m['mobile'] ?? '';
    e.rankCtrl.text   = m['rank']   ?? '';
    return e;
  }

  Map<String, dynamic> toMap() => {
    if (id     != null) 'id':     id,
    if (userId != null) 'userId': userId,
    'name':   nameCtrl.text.trim(),
    'pno':    pnoCtrl.text.trim(),
    'mobile': mobileCtrl.text.trim(),
    'rank':   rankCtrl.text.trim().isNotEmpty ? rankCtrl.text.trim() : selectedRank,
  };

  void dispose() { nameCtrl.dispose(); pnoCtrl.dispose(); mobileCtrl.dispose(); rankCtrl.dispose(); }
}

// ══════════════════════════════════════════════════════════════════════════════
//  OFFICER CARD
// ══════════════════════════════════════════════════════════════════════════════

class _OfficerCard extends StatefulWidget {
  final int index;
  final _OfficerEntry officer;
  final Color color;
  final List<String> allowedRanks;
  final bool canRemove;
  final VoidCallback onRemove, onChanged;
  const _OfficerCard({super.key, required this.index, required this.officer,
    required this.color, required this.allowedRanks, required this.canRemove,
    required this.onRemove, required this.onChanged});
  @override State<_OfficerCard> createState() => _OfficerCardState();
}

class _OfficerCardState extends State<_OfficerCard> {
  bool _expanded = true;
  bool _disposed = false;

  @override
  void dispose() { _disposed = true; super.dispose(); }

  void _openPicker() async {
    if (_disposed || !mounted) return;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _StaffPickerSheet(allowedRanks: widget.allowedRanks, color: widget.color));
    if (picked != null && !_disposed && mounted) {
      setState(() {
        widget.officer.userId          = picked['id'] as int?;
        widget.officer.nameCtrl.text   = picked['name']   ?? '';
        widget.officer.pnoCtrl.text    = picked['pno']    ?? '';
        widget.officer.mobileCtrl.text = picked['mobile'] ?? '';
        widget.officer.rankCtrl.text   = picked['rank']   ?? '';
        widget.officer.selectedRank    = picked['rank']   ?? '';
      });
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasData = widget.officer.nameCtrl.text.trim().isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: hasData ? widget.color.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hasData ? widget.color.withOpacity(0.3) : _kBorder.withOpacity(0.4))),
      child: Column(children: [
        GestureDetector(
          onTap: () { if (!_disposed && mounted) setState(() => _expanded = !_expanded); },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Row(children: [
              Container(width: 28, height: 28,
                decoration: BoxDecoration(color: widget.color.withOpacity(0.12), shape: BoxShape.circle),
                child: Center(child: Text('${widget.index + 1}',
                    style: TextStyle(color: widget.color, fontWeight: FontWeight.w900, fontSize: 12)))),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(hasData ? widget.officer.nameCtrl.text : 'अधिकारी ${widget.index + 1}',
                    style: TextStyle(color: hasData ? _kDark : _kSubtle, fontWeight: FontWeight.w700, fontSize: 13)),
                if (hasData && widget.officer.rankCtrl.text.isNotEmpty)
                  Text(widget.officer.rankCtrl.text, style: TextStyle(color: widget.color, fontSize: 11)),
              ])),
              GestureDetector(
                onTap: _openPicker,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: _kInfo.withOpacity(0.08), borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _kInfo.withOpacity(0.3))),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.search, size: 12, color: _kInfo),
                    SizedBox(width: 3),
                    Text('Staff से चुनें', style: TextStyle(color: _kInfo, fontSize: 10, fontWeight: FontWeight.w700))]))),
              const SizedBox(width: 6),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: _kSubtle, size: 18),
              if (widget.canRemove) ...[
                const SizedBox(width: 4),
                GestureDetector(onTap: widget.onRemove, child: const Icon(Icons.remove_circle_outline, color: _kError, size: 18))],
            ])),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(children: [
              if (widget.allowedRanks.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  value: widget.officer.rankCtrl.text.isNotEmpty && widget.allowedRanks.contains(widget.officer.rankCtrl.text)
                      ? widget.officer.rankCtrl.text : null,
                  decoration: InputDecoration(labelText: 'पद / Rank', labelStyle: const TextStyle(color: _kSubtle, fontSize: 12),
                    prefixIcon: Icon(Icons.military_tech_outlined, size: 18, color: widget.color),
                    filled: true, fillColor: Colors.white, isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: widget.color, width: 2))),
                  items: widget.allowedRanks.map((r) => DropdownMenuItem(value: r,
                      child: Text(r, style: const TextStyle(color: _kDark, fontSize: 13)))).toList(),
                  onChanged: (v) { if (v != null && !_disposed && mounted) setState(() { widget.officer.rankCtrl.text = v; widget.officer.selectedRank = v; }); },
                  dropdownColor: _kBg),
                const SizedBox(height: 8),
              ],
              _field(widget.officer.nameCtrl,   'पूरा नाम *', Icons.person_outline,  widget.color),
              _field(widget.officer.pnoCtrl,    'PNO',         Icons.badge_outlined,   widget.color),
              _field(widget.officer.mobileCtrl, 'मोबाइल',     Icons.phone_outlined,   widget.color, type: TextInputType.phone),
            ])),
          crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200)),
      ]));
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon, Color color, {TextInputType? type}) =>
    Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: ctrl, keyboardType: type,
      style: const TextStyle(color: _kDark, fontSize: 13),
      decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: _kSubtle, fontSize: 12),
        prefixIcon: Icon(icon, size: 18, color: color), filled: true, fillColor: Colors.white, isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: color, width: 2)))));
}

// ══════════════════════════════════════════════════════════════════════════════
//  STAFF PICKER SHEET
// ══════════════════════════════════════════════════════════════════════════════

class _StaffPickerSheet extends StatefulWidget {
  final List<String> allowedRanks;
  final Color color;
  const _StaffPickerSheet({required this.allowedRanks, required this.color});
  @override State<_StaffPickerSheet> createState() => _StaffPickerSheetState();
}

class _StaffPickerSheetState extends State<_StaffPickerSheet> {
  final List<Map> _staff = [];
  bool _loading    = true;
  bool _hasMore    = true;
  bool _loadingMore = false;
  bool _disposed   = false;
  int  _page = 1;
  String _q = '', _rankFilter = '';
  Timer? _debounce;
  final _searchCtrl = TextEditingController();
  final _scroll     = ScrollController();

  @override
  void initState() {
    super.initState();
    _rankFilter = widget.allowedRanks.isNotEmpty ? widget.allowedRanks.first : '';
    _scroll.addListener(_onScroll);
    _searchCtrl.addListener(_onSearchChanged);
    _load(reset: true);
  }

  void _onScroll() {
    if (_disposed) return;
    if (_scroll.hasClients && _scroll.position.pixels >= _scroll.position.maxScrollExtent - 100) _load();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (_disposed) return;
      final q = _searchCtrl.text.trim();
      if (q != _q) { _q = q; _reload(); }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _scroll.removeListener(_onScroll);
    _searchCtrl.removeListener(_onSearchChanged);
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) { if (!_disposed && mounted) setState(fn); }
  void _reload() { _safeSetState(() { _staff.clear(); _page = 1; _hasMore = true; }); _load(reset: true); }

  Future<void> _load({bool reset = false}) async {
    if (_disposed) return;
    if (!_hasMore && !reset) return;
    if (_loadingMore) return;
    _safeSetState(() { if (reset) _loading = true; else _loadingMore = true; });
    try {
      final token = await AuthService.getToken();
      if (_disposed) return;
      var url = '/admin/staff?assigned=no&page=$_page&limit=20&q=${Uri.encodeComponent(_q)}';
      if (_rankFilter.isNotEmpty) url += '&rank=${Uri.encodeComponent(_rankFilter)}';
      final res = await ApiService.get(url, token: token);
      if (_disposed) return;
      final w     = (res['data'] as Map<String, dynamic>?) ?? {};
      final items = (w['data'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      final pages = (w['totalPages'] as num?)?.toInt() ?? 1;
      _safeSetState(() { _staff.addAll(items); _hasMore = _page < pages; _page++; _loading = false; _loadingMore = false; });
    } catch (_) { _safeSetState(() { _loading = false; _loadingMore = false; }); }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(color: _kBg, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(children: [
        Container(margin: const EdgeInsets.only(top: 10, bottom: 4), width: 40, height: 4,
          decoration: BoxDecoration(color: _kBorder.withOpacity(0.5), borderRadius: BorderRadius.circular(2))),
        Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Staff से चुनें (अनसाइन)', style: TextStyle(color: _kDark, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 10),
          if (widget.allowedRanks.isNotEmpty)
            SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
              _rankChip('सभी', ''), ...widget.allowedRanks.map((r) => _rankChip(r, r))])),
          const SizedBox(height: 8),
          TextField(controller: _searchCtrl, style: const TextStyle(color: _kDark, fontSize: 13),
            decoration: InputDecoration(hintText: 'नाम, PNO खोजें...', hintStyle: const TextStyle(color: _kSubtle, fontSize: 12),
              prefixIcon: const Icon(Icons.search, color: _kSubtle, size: 18),
              filled: true, fillColor: Colors.white, isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: widget.color, width: 2)))),
        ])),
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _staff.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.people_outline, size: 48, color: _kSubtle.withOpacity(0.4)),
                  const SizedBox(height: 12),
                  Text('${_rankFilter.isEmpty ? 'कोई' : _rankFilter} अनसाइन स्टाफ नहीं', style: const TextStyle(color: _kSubtle, fontSize: 13))]))
              : Scrollbar(controller: _scroll, thumbVisibility: true, thickness: 5,
                  child: ListView.builder(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    itemCount: _staff.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= _staff.length) return const Padding(padding: EdgeInsets.all(12),
                        child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary))));
                      final s = _staff[i];
                      final rankColor = _kRankColors[s['rank']] ?? _kPrimary;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        leading: Container(width: 40, height: 40,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: rankColor.withOpacity(0.12), border: Border.all(color: rankColor.withOpacity(0.3))),
                          child: Center(child: Text(
                            (s['name'] as String? ?? '').split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join().toUpperCase(),
                            style: TextStyle(color: rankColor, fontWeight: FontWeight.w900, fontSize: 13)))),
                        title: Text(s['name'] ?? '', style: const TextStyle(color: _kDark, fontWeight: FontWeight.w700, fontSize: 13)),
                        subtitle: Row(children: [
                          if ((s['pno'] as String?)?.isNotEmpty == true) ...[
                            const Icon(Icons.badge_outlined, size: 10, color: _kSubtle),
                            const SizedBox(width: 3),
                            Text('${s['pno']}', style: const TextStyle(color: _kSubtle, fontSize: 11)),
                            const SizedBox(width: 8)],
                          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: rankColor.withOpacity(0.1), borderRadius: BorderRadius.circular(5), border: Border.all(color: rankColor.withOpacity(0.3))),
                            child: Text(s['rank'] ?? '', style: TextStyle(color: rankColor, fontSize: 10, fontWeight: FontWeight.w700)))]),
                        trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(8)),
                          child: const Text('चुनें', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
                        onTap: () => Navigator.pop(context, Map<String, dynamic>.from(s)));
                    }))),
      ]));
  }

  Widget _rankChip(String label, String value) {
    final sel   = _rankFilter == value;
    final color = value.isEmpty ? _kPrimary : (_kRankColors[value] ?? _kPrimary);
    return GestureDetector(
      onTap: () { if (_disposed) return; _safeSetState(() => _rankFilter = value); _reload(); },
      child: Container(margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: sel ? color : Colors.white, borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? color : _kBorder.withOpacity(0.5))),
        child: Text(label, style: TextStyle(color: sel ? Colors.white : _kDark, fontSize: 11, fontWeight: sel ? FontWeight.w700 : FontWeight.w500))));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  CENTER STEP
// ══════════════════════════════════════════════════════════════════════════════

class _CenterStep extends StatefulWidget {
  final int gpId;
  const _CenterStep({super.key, required this.gpId});
  @override State<_CenterStep> createState() => _CenterStepState();
}

class _CenterStepState extends State<_CenterStep> {
  final List<Map> _centers = [];
  bool _loading    = true;
  bool _loadingMore = false;
  bool _hasMore    = true;
  bool _disposed   = false;
  int  _page = 1;
  String _q = '';
  Timer? _debounce;
  final _searchCtrl = TextEditingController();
  final _scroll     = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _searchCtrl.addListener(_onSearchChanged);
    _load(reset: true);
  }

  void _onScroll() {
    if (_disposed) return;
    if (_scroll.hasClients && _scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) _load();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (_disposed) return;
      final q = _searchCtrl.text.trim();
      if (q != _q) { _q = q; _reload(); }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _scroll.removeListener(_onScroll);
    _searchCtrl.removeListener(_onSearchChanged);
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) { if (!_disposed && mounted) setState(fn); }
  void _reload() { _safeSetState(() { _centers.clear(); _page = 1; _hasMore = true; }); _load(reset: true); }

  Future<void> _load({bool reset = false}) async {
    if (_disposed) return;
    if (!_hasMore && !reset) return;
    if (_loadingMore) return;
    _safeSetState(() { if (reset) _loading = true; else _loadingMore = true; });
    try {
      final token = await AuthService.getToken();
      if (_disposed) return;
      final res = await ApiService.get(
          '/admin/gram-panchayats/${widget.gpId}/centers?page=$_page&limit=20&q=${Uri.encodeComponent(_q)}', token: token);
      if (_disposed) return;
      List<Map> items;
      final data = res['data'];
      if (data is List) { items = data.map((e) => Map<String, dynamic>.from(e as Map)).toList(); _hasMore = false; }
      else if (data is Map) {
        items = ((data['data'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _hasMore = _page < ((data['totalPages'] as num?)?.toInt() ?? 1);
      } else { items = []; _hasMore = false; }
      _safeSetState(() { _centers.addAll(items); _page++; _loading = false; _loadingMore = false; });
    } catch (e) { _safeSetState(() { _loading = false; _loadingMore = false; }); }
  }

  void _openCreateDialog() {
    if (_disposed || !mounted) return;
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => _CenterDialog(gpId: widget.gpId, onDone: () { if (!_disposed) _reload(); }));
  }

  void _openEditDialog(Map center) {
    if (_disposed || !mounted) return;
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => _CenterDialog(gpId: widget.gpId, existing: center, onDone: () { if (!_disposed) _reload(); }));
  }

  Future<void> _delete(Map center) async {
    if (_disposed || !mounted) return;
    final confirmed = await _confirm(context, 'Delete "${center['name']}"?');
    if (!confirmed || _disposed) return;
    try {
      final token = await AuthService.getToken();
      if (_disposed) return;
      await ApiService.delete('/admin/centers/${center['id']}', token: token);
      if (_disposed) return;
      _reload();
    } catch (e) {
      if (!_disposed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e'),
          backgroundColor: _kError, behavior: SnackBarBehavior.floating));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(color: _kSurface, padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: const Color(0xFFC62828).withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.location_on_outlined, color: Color(0xFFC62828), size: 16)),
          const SizedBox(width: 10),
          const Expanded(child: Text('Election Centers', style: TextStyle(color: _kDark, fontWeight: FontWeight.w800, fontSize: 15))),
          GestureDetector(onTap: _openCreateDialog,
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: const Color(0xFFC62828), borderRadius: BorderRadius.circular(9)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add, color: Colors.white, size: 14), SizedBox(width: 4),
                Text('जोड़ें', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))]))),
        ])),
      Container(color: _kBg, padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: TextField(controller: _searchCtrl, style: const TextStyle(color: _kDark, fontSize: 13),
          decoration: InputDecoration(hintText: 'Center खोजें...', hintStyle: const TextStyle(color: _kSubtle, fontSize: 12),
            prefixIcon: const Icon(Icons.search, color: _kSubtle, size: 18),
            suffixIcon: _q.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 16, color: _kSubtle),
                onPressed: () { _searchCtrl.clear(); _q = ''; _reload(); }) : null,
            filled: true, fillColor: Colors.white, isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFC62828), width: 2))))),
      Expanded(child: _loading
        ? const Center(child: CircularProgressIndicator(color: _kPrimary))
        : _centers.isEmpty
            ? _emptyState('Election Centers', Icons.location_on_outlined, const Color(0xFFC62828))
            : RefreshIndicator(onRefresh: () async => _reload(), color: _kPrimary,
                child: Scrollbar(controller: _scroll, thumbVisibility: true, thickness: 5,
                  child: ListView.builder(controller: _scroll, padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                    itemCount: _centers.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= _centers.length) return const Padding(padding: EdgeInsets.all(12),
                        child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary))));
                      return _CenterCard(center: _centers[i], onEdit: () => _openEditDialog(_centers[i]),
                        onDelete: () => _delete(_centers[i]), onRefresh: _reload);
                    })))),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  CENTER CARD  (updated to show rooms count)
// ══════════════════════════════════════════════════════════════════════════════

class _CenterCard extends StatelessWidget {
  final Map center;
  final VoidCallback onEdit, onDelete, onRefresh;
  const _CenterCard({required this.center, required this.onEdit, required this.onDelete, required this.onRefresh});

  Color _typeColor(String t) => switch(t) {
    'A++' => const Color(0xFF6A1B9A),
    'A'   => const Color(0xFFC62828),
    'B'   => const Color(0xFFE65100),
    _     => const Color(0xFF1A5276),
  };

  @override
  Widget build(BuildContext context) {
    final type      = center['centerType'] as String? ?? 'C';
    final tc        = _typeColor(type);
    final assigned  = (center['assignedStaff'] as List?)?.cast<Map>() ?? [];
    final missing   = (center['missingRanks']  as List?)?.cast<Map>() ?? [];
    final dutyCount = center['dutyCount'] ?? assigned.length;
    final roomCount = center['roomCount'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder.withOpacity(0.4)),
        boxShadow: [BoxShadow(color: tc.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 2))]),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(children: [
            Container(width: 42, height: 42,
              decoration: BoxDecoration(color: tc.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: tc.withOpacity(0.3))),
              child: Center(child: Text(type, style: TextStyle(color: tc, fontWeight: FontWeight.w900, fontSize: type.length > 1 ? 11 : 16)))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(center['name'] ?? '', style: const TextStyle(color: _kDark, fontWeight: FontWeight.w700, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Wrap(spacing: 8, children: [
                if ((center['thana'] as String?)?.isNotEmpty == true) _mini(Icons.local_police_outlined, center['thana'] as String),
                if ((center['busNo'] as String?)?.isNotEmpty == true) _mini(Icons.directions_bus_outlined, 'Bus: ${center['busNo']}'),
                _mini(Icons.how_to_vote_outlined, '$dutyCount स्टाफ'),
                if (roomCount > 0) _mini(Icons.meeting_room_outlined, '$roomCount कमरे'),
              ]),
            ])),
            Column(children: [
              _iconBtn(Icons.edit_outlined,  _kInfo,  onEdit),
              const SizedBox(height: 4),
              _iconBtn(Icons.delete_outline, _kError, onDelete),
            ]),
          ]),
        ),
        if (missing.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: _kError.withOpacity(0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: _kError.withOpacity(0.25))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [Icon(Icons.warning_amber_rounded, color: _kError, size: 14), SizedBox(width: 5),
                Text('कुछ रैंक उपलब्ध नहीं', style: TextStyle(color: _kError, fontSize: 12, fontWeight: FontWeight.w700))]),
              const SizedBox(height: 5),
              Wrap(spacing: 6, runSpacing: 4, children: missing.map((m) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: _kError.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
                child: Text('${m['rank']}: ${m['required']} आवश्यक, ${m['available']} उपलब्ध',
                    style: const TextStyle(color: _kError, fontSize: 10, fontWeight: FontWeight.w600)))).toList()),
            ])),
        if (assigned.isNotEmpty)
          Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Wrap(spacing: 6, runSpacing: 5, children: assigned.map((s) {
              final rankColor = _kRankColors[s['rank']] ?? _kPrimary;
              return Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(color: _kSuccess.withOpacity(0.06), borderRadius: BorderRadius.circular(7), border: Border.all(color: _kSuccess.withOpacity(0.25))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.check_circle_outline, size: 11, color: _kSuccess),
                  const SizedBox(width: 3),
                  ConstrainedBox(constraints: const BoxConstraints(maxWidth: 80),
                    child: Text(s['name'] ?? '', style: const TextStyle(color: _kDark, fontSize: 11, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 3),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: rankColor.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                    child: Text(s['rank'] ?? '', style: TextStyle(color: rankColor, fontSize: 9, fontWeight: FontWeight.w700))),
                ]));
            }).toList())),
      ]));
  }

  Widget _mini(IconData icon, String text) =>
    Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 10, color: _kSubtle), const SizedBox(width: 3), Text(text, style: const TextStyle(color: _kSubtle, fontSize: 11))]);

  Widget _iconBtn(IconData icon, Color c, VoidCallback onTap) =>
    GestureDetector(onTap: onTap, child: Container(width: 32, height: 32,
      decoration: BoxDecoration(color: c.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: c.withOpacity(0.25))),
      child: Icon(icon, size: 15, color: c)));
}

// ══════════════════════════════════════════════════════════════════════════════
//  MATDAN STHAL (ROOMS) DIALOG  ← NEW: shows rooms inside a center
// ══════════════════════════════════════════════════════════════════════════════

class _MatdanSthalDialog extends StatefulWidget {
  final int centerId;
  final String centerName;
  const _MatdanSthalDialog({required this.centerId, required this.centerName});
  @override State<_MatdanSthalDialog> createState() => _MatdanSthalDialogState();
}

class _MatdanSthalDialogState extends State<_MatdanSthalDialog> {
  List<Map> _rooms = [];
  bool _loading = true;
  bool _disposed = false;
  final _roomNumCtrl = TextEditingController();
  bool _adding = false;

  @override
  void initState() { super.initState(); _loadRooms(); }

  @override
  void dispose() { _disposed = true; _roomNumCtrl.dispose(); super.dispose(); }

  void _safeSetState(VoidCallback fn) { if (!_disposed && mounted) setState(fn); }

  Future<void> _loadRooms() async {
    _safeSetState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      if (_disposed) return;
      final res = await ApiService.get('/admin/centers/${widget.centerId}/rooms', token: token);
      if (_disposed) return;
      final data = res['data'];
      List<Map> rooms = [];
      if (data is List) rooms = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _safeSetState(() { _rooms = rooms; _loading = false; });
    } catch (_) { _safeSetState(() => _loading = false); }
  }

  Future<void> _addRoom() async {
    final rn = _roomNumCtrl.text.trim();
    if (rn.isEmpty) return;
    _safeSetState(() => _adding = true);
    try {
      final token = await AuthService.getToken();
      if (_disposed) return;
      await ApiService.post('/admin/centers/${widget.centerId}/rooms', {'roomNumber': rn}, token: token);
      if (_disposed) return;
      _roomNumCtrl.clear();
      await _loadRooms();
    } catch (e) {
      if (!_disposed && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: _kError, behavior: SnackBarBehavior.floating));
    } finally { _safeSetState(() => _adding = false); }
  }

  Future<void> _deleteRoom(int roomId) async {
    try {
      final token = await AuthService.getToken();
      if (_disposed) return;
      await ApiService.delete('/admin/rooms/$roomId', token: token);
      if (_disposed) return;
      await _loadRooms();
    } catch (e) {
      if (!_disposed && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: _kError, behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 480, maxHeight: MediaQuery.of(context).size.height * 0.82),
        child: Container(
          decoration: BoxDecoration(color: _kBg, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorder, width: 1.2),
            boxShadow: [const BoxShadow(color: Color(0x22C62828), blurRadius: 20, offset: Offset(0, 8))]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
              decoration: const BoxDecoration(color: _kDark,
                borderRadius: BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15))),
              child: Row(children: [
                Container(padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: const Color(0xFFC62828).withOpacity(0.25), borderRadius: BorderRadius.circular(7)),
                  child: const Icon(Icons.meeting_room_outlined, color: Color(0xFFC62828), size: 16)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('मतदान स्थल (Matdan Sthal)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  Text(widget.centerName, style: const TextStyle(color: Colors.white54, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                IconButton(onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints()),
              ]),
            ),
            // Info banner
            Container(margin: const EdgeInsets.fromLTRB(16, 12, 16, 0), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _kInfo.withOpacity(0.07), borderRadius: BorderRadius.circular(8), border: Border.all(color: _kInfo.withOpacity(0.2))),
              child: const Row(children: [
                Icon(Icons.info_outline, size: 14, color: _kInfo),
                SizedBox(width: 8),
                Expanded(child: Text('प्रत्येक कमरा एक मतदान स्थल (Matdan Sthal) है। एक केंद्र में कितने कमरे हैं वो यहाँ दर्ज करें।',
                    style: TextStyle(color: _kInfo, fontSize: 11)))])),
            // Add room
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(children: [
                Expanded(child: TextField(controller: _roomNumCtrl,
                  style: const TextStyle(color: _kDark, fontSize: 13),
                  keyboardType: TextInputType.text,
                  onSubmitted: (_) => _addRoom(),
                  decoration: InputDecoration(hintText: 'कमरा नंबर / Room Number', hintStyle: const TextStyle(color: _kSubtle, fontSize: 12),
                    prefixIcon: const Icon(Icons.meeting_room_outlined, size: 18, color: _kPrimary),
                    filled: true, fillColor: Colors.white, isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kPrimary, width: 2))))),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _adding ? null : _addRoom,
                  style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: _adding ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.add, size: 18)),
              ])),
            // Rooms list
            Flexible(child: _loading
              ? const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: _kPrimary)))
              : _rooms.isEmpty
                  ? Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.meeting_room_outlined, size: 40, color: _kSubtle.withOpacity(0.4)),
                      const SizedBox(height: 12),
                      const Text('कोई कमरा नहीं जोड़ा गया', style: TextStyle(color: _kSubtle, fontSize: 13)),
                      const SizedBox(height: 4),
                      const Text('ऊपर कमरा नंबर डालकर जोड़ें', style: TextStyle(color: _kSubtle, fontSize: 11))]))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      itemCount: _rooms.length,
                      itemBuilder: (_, i) {
                        final room = _rooms[i];
                        return Container(margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _kBorder.withOpacity(0.4)),
                            boxShadow: [BoxShadow(color: _kPrimary.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 1))]),
                          child: Row(children: [
                            Container(width: 32, height: 32,
                              decoration: BoxDecoration(color: _kPrimary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                              child: Center(child: Text('${i + 1}', style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.w800, fontSize: 13)))),
                            const SizedBox(width: 12),
                            const Icon(Icons.meeting_room_outlined, size: 16, color: _kSubtle),
                            const SizedBox(width: 6),
                            Expanded(child: Text('कमरा: ${room['roomNumber'] ?? ''}',
                                style: const TextStyle(color: _kDark, fontWeight: FontWeight.w600, fontSize: 13))),
                            GestureDetector(onTap: () => _deleteRoom(room['id'] as int),
                              child: Container(width: 30, height: 30,
                                decoration: BoxDecoration(color: _kError.withOpacity(0.08), borderRadius: BorderRadius.circular(7), border: Border.all(color: _kError.withOpacity(0.25))),
                                child: const Icon(Icons.delete_outline, size: 15, color: _kError))),
                          ]));
                      })),
            // Footer
            Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: _kSuccess.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: _kSuccess.withOpacity(0.3))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.meeting_room_outlined, size: 14, color: _kSuccess),
                    const SizedBox(width: 6),
                    Text('कुल ${_rooms.length} कमरे', style: const TextStyle(color: _kSuccess, fontWeight: FontWeight.w700, fontSize: 12))])),
                OutlinedButton(onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(foregroundColor: _kSubtle, side: const BorderSide(color: _kBorder),
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text('बंद करें')),
              ])),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  CUSTOM RANK RULES DIALOG  ← NEW: admin sets custom rank requirements
// ══════════════════════════════════════════════════════════════════════════════

class _CustomRankRulesDialog extends StatefulWidget {
  final int centerId;
  final String centerName;
  final String centerType;
  final List<Map> existingRules;
  final void Function(List<_RankRule>) onConfirm;
  const _CustomRankRulesDialog({
    required this.centerId, required this.centerName, required this.centerType,
    required this.existingRules, required this.onConfirm});
  @override State<_CustomRankRulesDialog> createState() => _CustomRankRulesDialogState();
}

class _CustomRankRulesDialogState extends State<_CustomRankRulesDialog> {
  final List<_RankRule> _rules = [];

  Color get _typeColor => switch(widget.centerType) {
    'A++' => const Color(0xFF6A1B9A), 'A' => const Color(0xFFC62828),
    'B'   => const Color(0xFFE65100), _   => const Color(0xFF1A5276)};

  @override
  void initState() {
    super.initState();
    if (widget.existingRules.isNotEmpty) {
      for (final r in widget.existingRules) {
        _rules.add(_RankRule(rank: r['rank'] as String? ?? _kRanks.first, count: (r['count'] as num?)?.toInt() ?? 1));
      }
    } else {
      _rules.add(_RankRule(rank: _kRanks.last, count: 1));
    }
  }

  void _addRule() => setState(() => _rules.add(_RankRule(rank: _kRanks.last, count: 1)));

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 480, maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Container(
          decoration: BoxDecoration(color: _kBg, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorder, width: 1.2),
            boxShadow: [BoxShadow(color: _typeColor.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 8))]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
              decoration: const BoxDecoration(color: _kDark, borderRadius: BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15))),
              child: Row(children: [
                Container(padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: _typeColor.withOpacity(0.25), borderRadius: BorderRadius.circular(7)),
                  child: Icon(Icons.rule_outlined, color: _typeColor, size: 16)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Custom Rank Rules', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  Text(widget.centerName, style: const TextStyle(color: Colors.white54, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                IconButton(onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints()),
              ])),
            Container(margin: const EdgeInsets.fromLTRB(16, 12, 16, 0), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _typeColor.withOpacity(0.07), borderRadius: BorderRadius.circular(8), border: Border.all(color: _typeColor.withOpacity(0.2))),
              child: Row(children: [
                Icon(Icons.info_outline, size: 14, color: _typeColor),
                const SizedBox(width: 8),
                Expanded(child: Text('इस center के लिए custom rank और staff संख्या सेट करें। Auto-assign इसी के अनुसार काम करेगा।',
                    style: TextStyle(color: _typeColor, fontSize: 11)))])),
            Flexible(child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(children: [
                ..._rules.asMap().entries.map((entry) => _buildRuleRow(entry.key, entry.value)),
                const SizedBox(height: 8),
                GestureDetector(onTap: _addRule,
                  child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(color: _typeColor.withOpacity(0.06), borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _typeColor.withOpacity(0.3), style: BorderStyle.solid)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.add_circle_outline, size: 16, color: _typeColor),
                      const SizedBox(width: 6),
                      Text('और Rank जोड़ें', style: TextStyle(color: _typeColor, fontSize: 12, fontWeight: FontWeight.w700))]))),
              ]))),
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(foregroundColor: _kSubtle, side: const BorderSide(color: _kBorder),
                    padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text('रद्द'))),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(onPressed: () { Navigator.pop(context); widget.onConfirm(_rules); },
                  style: ElevatedButton.styleFrom(backgroundColor: _typeColor, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text('Confirm & Auto-Assign', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)))),
              ])),
          ]),
        ),
      ),
    );
  }

  Widget _buildRuleRow(int index, _RankRule rule) {
    return Container(margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: _kBorder.withOpacity(0.4))),
      child: Row(children: [
        Container(width: 26, height: 26, decoration: BoxDecoration(color: _typeColor.withOpacity(0.1), shape: BoxShape.circle),
          child: Center(child: Text('${index + 1}', style: TextStyle(color: _typeColor, fontWeight: FontWeight.w800, fontSize: 11)))),
        const SizedBox(width: 8),
        Expanded(child: DropdownButtonFormField<String>(
          value: _kRanks.contains(rule.rank) ? rule.rank : _kRanks.last,
          decoration: InputDecoration(labelText: 'Rank', labelStyle: const TextStyle(color: _kSubtle, fontSize: 11),
            isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _typeColor, width: 1.5))),
          items: _kRanks.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(color: _kDark, fontSize: 12)))).toList(),
          onChanged: (v) { if (v != null) setState(() => rule.rank = v); },
          dropdownColor: _kBg)),
        const SizedBox(width: 8),
        SizedBox(width: 70, child: TextField(
          controller: TextEditingController(text: '${rule.count}')..selection = TextSelection.fromPosition(TextPosition(offset: '${rule.count}'.length)),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: _kDark, fontSize: 13),
          onChanged: (v) { final n = int.tryParse(v); if (n != null && n > 0) rule.count = n; },
          decoration: InputDecoration(labelText: 'Count', labelStyle: const TextStyle(color: _kSubtle, fontSize: 11),
            isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _typeColor, width: 1.5))))),
        const SizedBox(width: 6),
        if (_rules.length > 1)
          GestureDetector(onTap: () => setState(() => _rules.removeAt(index)),
            child: const Icon(Icons.remove_circle_outline, color: _kError, size: 20)),
      ]));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  CENTER DIALOG  (fully updated with custom rules + rooms + type-change reassign)
// ══════════════════════════════════════════════════════════════════════════════

class _CenterDialog extends StatefulWidget {
  final int gpId;
  final Map? existing;
  final VoidCallback onDone;
  const _CenterDialog({required this.gpId, this.existing, required this.onDone});
  @override State<_CenterDialog> createState() => _CenterDialogState();
}

class _CenterDialogState extends State<_CenterDialog> {
  final _nameCtrl    = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _thanaCtrl   = TextEditingController();
  final _busCtrl     = TextEditingController();
  String _type  = 'C';
  String _prevType = 'C'; // track type change on edit
  bool _saving  = false;
  bool _disposed = false;

  List<Map> _assignedStaff = [];
  List<Map> _missingRanks  = [];
  List<Map> _lowerRankAssignments = []; // tracks lower rank substitutions
  bool _autoAssigning = false;
  bool _autoAssigned  = false;
  int  _savedCenterId = 0;

  // Custom rules set for this center (manual override)
  List<_RankRule> _customRules = [];
  bool _useCustomRules = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nameCtrl.text    = widget.existing!['name']       as String? ?? '';
      _addressCtrl.text = widget.existing!['address']    as String? ?? '';
      _thanaCtrl.text   = widget.existing!['thana']      as String? ?? '';
      _busCtrl.text     = widget.existing!['busNo']      as String? ?? '';
      _type             = widget.existing!['centerType'] as String? ?? 'C';
      _prevType         = _type;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _nameCtrl.dispose(); _addressCtrl.dispose(); _thanaCtrl.dispose(); _busCtrl.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) { if (!_disposed && mounted) setState(fn); }

  Color get _typeColor => switch(_type) {
    'A++' => const Color(0xFF6A1B9A), 'A' => const Color(0xFFC62828),
    'B'   => const Color(0xFFE65100), _   => const Color(0xFF1A5276)};

  // Open custom rules dialog and trigger auto-assign
  void _openCustomRulesDialog(int centerId) {
    if (_disposed || !mounted) return;
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => _CustomRankRulesDialog(
        centerId: centerId, centerName: _nameCtrl.text.trim(),
        centerType: _type, existingRules: _customRules.map((r) => r.toMap()).toList(),
        onConfirm: (rules) async {
          _safeSetState(() { _customRules = rules; _useCustomRules = true; });
          await _runAutoAssign(centerId, customRules: rules);
        }));
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) { _snack('नाम आवश्यक है', error: true); return; }
    _safeSetState(() => _saving = true);
    try {
      final token = await AuthService.getToken();
      if (_disposed) return;
      final body = {
        'name': _nameCtrl.text.trim(), 'address': _addressCtrl.text.trim(),
        'thana': _thanaCtrl.text.trim(), 'busNo': _busCtrl.text.trim(), 'centerType': _type,
      };
      int centerId;
      final isEdit = widget.existing != null;
      if (isEdit) {
        await ApiService.put('/admin/centers/${widget.existing!['id']}', body, token: token);
        if (_disposed) return;
        centerId = widget.existing!['id'] as int;
        // If center type changed → trigger reassign
        if (_type != _prevType) {
          _safeSetState(() { _saving = false; _autoAssigning = true; });
          await _runAutoAssign(centerId, isReassign: true);
          return;
        }
        if (!_disposed && mounted) Navigator.pop(context);
        widget.onDone();
      } else {
        final res = await ApiService.post('/admin/gram-panchayats/${widget.gpId}/centers', body, token: token);
        if (_disposed) return;
        centerId = (res['data']?['id'] as num?)?.toInt() ?? 0;
        _savedCenterId = centerId;
        if (centerId > 0) {
          _safeSetState(() { _saving = false; _autoAssigning = true; });
          await _runAutoAssign(centerId);
          return;
        }
        if (!_disposed && mounted) Navigator.pop(context);
        widget.onDone();
      }
    } catch (e) {
      _safeSetState(() => _saving = false);
      _snack('Error: $e', error: true);
    }
  }

  Future<void> _runAutoAssign(int centerId, {bool isReassign = false, List<_RankRule>? customRules}) async {
    _safeSetState(() => _autoAssigning = true);
    try {
      final token = await AuthService.getToken();
      if (_disposed) return;

      // If reassigning, first remove old assignments
      if (isReassign) {
        try {
          await ApiService.post('/admin/centers/$centerId/clear-assignments', {}, token: token);
          if (_disposed) return;
        } catch (_) {}
      }

      // Build request body
      final body = <String, dynamic>{};
      if (customRules != null && customRules.isNotEmpty) {
        body['customRules'] = customRules.map((r) => r.toMap()).toList();
      }

      final assignRes = await ApiService.post('/admin/auto-assign/$centerId', body, token: token);
      if (_disposed) return;
      final data = assignRes['data'] as Map<String, dynamic>? ?? {};
      _safeSetState(() {
        _assignedStaff       = List<Map>.from((data['assigned']          as List?) ?? []);
        _missingRanks        = List<Map>.from((data['missing']           as List?) ?? []);
        _lowerRankAssignments = List<Map>.from((data['lowerRankUsed']    as List?) ?? []);
        _autoAssigning       = false;
        _autoAssigned        = true;
        _savedCenterId       = centerId;
      });
    } catch (e) {
      _safeSetState(() { _autoAssigning = false; _saving = false; });
      _snack('Auto-assign failed: $e', error: true);
      if (!_disposed && mounted) Navigator.pop(context);
      widget.onDone();
    }
  }

  Future<void> _assignManualRank(String rank, int centerId) async {
    if (_disposed || !mounted) return;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _StaffPickerSheet(allowedRanks: [rank, ..._getLowerRanks(rank)], color: _typeColor));
    if (picked == null || _disposed || !mounted) return;
    try {
      final token = await AuthService.getToken();
      if (_disposed) return;
      await ApiService.post('/admin/duties', {'staffId': picked['id'], 'centerId': centerId, 'busNo': _busCtrl.text.trim()}, token: token);
      if (_disposed) return;
      _safeSetState(() {
        _assignedStaff.add(picked);
        _missingRanks.removeWhere((m) => m['rank'] == rank);
      });
      _snack('${picked['name']} असाइन किया गया');
    } catch (e) { _snack('Error: $e', error: true); }
  }

  List<String> _getLowerRanks(String rank) {
    final idx = _kRankHierarchy.indexOf(rank);
    if (idx < 0 || idx >= _kRankHierarchy.length - 1) return [];
    return _kRankHierarchy.sublist(idx + 1);
  }

  void _finish() {
    if (!_disposed && mounted) Navigator.pop(context);
    widget.onDone();
  }

  void _snack(String msg, {bool error = false}) {
    if (_disposed || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg),
      backgroundColor: error ? _kError : _kSuccess, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  // Open rooms dialog
  void _openRoomsDialog(int centerId) {
    if (_disposed || !mounted) return;
    showDialog(context: context, builder: (_) => _MatdanSthalDialog(centerId: centerId, centerName: _nameCtrl.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Container(
          decoration: BoxDecoration(color: _kBg, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorder, width: 1.2),
            boxShadow: [BoxShadow(color: _typeColor.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 8))]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Header
            Container(padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
              decoration: const BoxDecoration(color: _kDark,
                borderRadius: BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15))),
              child: Row(children: [
                Container(padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: _typeColor.withOpacity(0.25), borderRadius: BorderRadius.circular(7)),
                  child: Icon(Icons.location_on_outlined, color: _typeColor, size: 16)),
                const SizedBox(width: 10),
                Expanded(child: Text(widget.existing == null ? 'Election Center जोड़ें' : 'Center संपादित करें',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
                if (!_autoAssigned)
                  IconButton(onPressed: () { if (!_disposed && mounted) Navigator.pop(context); },
                    icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                    padding: EdgeInsets.zero, constraints: const BoxConstraints()),
              ])),
            // Body
            Flexible(child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _autoAssigning
                ? Column(children: const [
                    SizedBox(height: 30),
                    CircularProgressIndicator(color: _kPrimary),
                    SizedBox(height: 16),
                    Text('मानक के अनुसार स्टाफ असाइन हो रहा है...', style: TextStyle(color: _kSubtle, fontSize: 13), textAlign: TextAlign.center),
                    SizedBox(height: 30)])
                : _autoAssigned
                  ? _AssignResultView(
                      assignedStaff: _assignedStaff, missingRanks: _missingRanks,
                      lowerRankAssignments: _lowerRankAssignments,
                      centerType: _type, centerId: _savedCenterId,
                      onAssignManual: _assignManualRank,
                      onManageRooms: () => _openRoomsDialog(_savedCenterId),
                      onCustomRules: () => _openCustomRulesDialog(_savedCenterId))
                  : _buildForm(),
            )),
            // Actions
            if (!_autoAssigning)
              Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: _autoAssigned ? _buildDoneActions() : _buildSaveActions()),
          ]),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _formField(_nameCtrl,    'Center का नाम *',  Icons.location_on_outlined,    _typeColor),
      _formField(_addressCtrl, 'पता',              Icons.map_outlined,             _typeColor),
      Row(children: [
        Expanded(child: _formField(_thanaCtrl, 'थाना', Icons.local_police_outlined,  _typeColor)),
        const SizedBox(width: 10),
        Expanded(child: _formField(_busCtrl,   'Bus No', Icons.directions_bus_outlined, _typeColor))]),
      const SizedBox(height: 12),
      // Rooms quick button (only on edit)
      if (widget.existing != null) ...[
        GestureDetector(
          onTap: () => _openRoomsDialog(widget.existing!['id'] as int),
          child: Container(width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _kInfo.withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: _kInfo.withOpacity(0.25))),
            child: Row(children: [
              const Icon(Icons.meeting_room_outlined, size: 16, color: _kInfo),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('मतदान स्थल (Matdan Sthal) / कमरे', style: TextStyle(color: _kInfo, fontWeight: FontWeight.w700, fontSize: 13)),
                Text('${widget.existing!['roomCount'] ?? 0} कमरे दर्ज हैं — प्रबंधन के लिए टैप करें', style: const TextStyle(color: _kSubtle, fontSize: 11))])),
              const Icon(Icons.arrow_forward_ios, size: 12, color: _kInfo)]))),
        const SizedBox(height: 12),
      ],
      // Center type
      Row(children: [
        Container(width: 3, height: 14, decoration: BoxDecoration(color: _typeColor, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        const Text('संवेदनशीलता / Center Type', style: TextStyle(color: _kDark, fontSize: 13, fontWeight: FontWeight.w700))]),
      const SizedBox(height: 10),
      Row(children: ['A++', 'A', 'B', 'C'].map((t) {
        final sel = _type == t;
        final c = switch(t) { 'A++' => const Color(0xFF6A1B9A), 'A' => const Color(0xFFC62828), 'B' => const Color(0xFFE65100), _ => const Color(0xFF1A5276) };
        return Expanded(child: GestureDetector(
          onTap: () => _safeSetState(() => _type = t),
          child: AnimatedContainer(duration: const Duration(milliseconds: 150),
            margin: EdgeInsets.only(right: t == 'C' ? 0 : 8),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: sel ? c : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: c, width: sel ? 2 : 1)),
            child: Column(children: [
              Text(t, style: TextStyle(color: sel ? Colors.white : c, fontWeight: FontWeight.w900, fontSize: 14)),
              Text(switch(t) { 'A++' => 'अति-अति', 'A' => 'अति', 'B' => 'संवेदनशील', _ => 'सामान्य' },
                style: TextStyle(color: sel ? Colors.white70 : c.withOpacity(0.7), fontSize: 9))]))));
      }).toList()),
      const SizedBox(height: 12),
      // Type change warning on edit
      if (widget.existing != null && _type != _prevType)
        Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.orange.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.withOpacity(0.35))),
          child: const Row(children: [
            Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(child: Text('Center Type बदलने पर सभी पुराने assignments हट जाएंगे और नए नियमों से auto-assign होगा।',
                style: TextStyle(color: Colors.orange, fontSize: 11)))])),
      const SizedBox(height: 10),
      // Info banner
      Container(padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: _kInfo.withOpacity(0.06), borderRadius: BorderRadius.circular(8), border: Border.all(color: _kInfo.withOpacity(0.2))),
        child: const Row(children: [
          Icon(Icons.info_outline, size: 14, color: _kInfo),
          SizedBox(width: 8),
          Expanded(child: Text('Center जोड़ने के बाद मानक के अनुसार स्टाफ स्वतः असाइन होगा। Custom rules भी सेट कर सकते हैं।',
              style: TextStyle(color: _kInfo, fontSize: 11)))])),
    ]);
  }

  Widget _buildSaveActions() {
    return Row(children: [
      Expanded(child: OutlinedButton(onPressed: _saving ? null : () { if (!_disposed && mounted) Navigator.pop(context); },
        style: OutlinedButton.styleFrom(foregroundColor: _kSubtle, side: const BorderSide(color: _kBorder),
          padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        child: const Text('रद्द'))),
      const SizedBox(width: 12),
      Expanded(child: ElevatedButton(onPressed: _saving ? null : _save,
        style: ElevatedButton.styleFrom(backgroundColor: _typeColor, foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        child: _saving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Text(widget.existing == null ? 'जोड़ें + Auto-Assign' : (_type != _prevType ? 'Update + Reassign' : 'अपडेट करें'),
                style: const TextStyle(fontWeight: FontWeight.w700)))),
    ]);
  }

  Widget _buildDoneActions() {
    return Row(children: [
      Expanded(child: OutlinedButton.icon(
        onPressed: () => _openRoomsDialog(_savedCenterId),
        icon: const Icon(Icons.meeting_room_outlined, size: 14),
        label: const Text('Matdan Sthal', style: TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(foregroundColor: _kPrimary, side: const BorderSide(color: _kBorder),
          padding: const EdgeInsets.symmetric(vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))))),
      const SizedBox(width: 8),
      Expanded(child: OutlinedButton.icon(
        onPressed: () => _openCustomRulesDialog(_savedCenterId),
        icon: const Icon(Icons.rule_outlined, size: 14),
        label: const Text('Custom Rules', style: TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(foregroundColor: _kInfo, side: const BorderSide(color: _kBorder),
          padding: const EdgeInsets.symmetric(vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))))),
      const SizedBox(width: 8),
      Expanded(child: ElevatedButton(onPressed: _finish,
        style: ElevatedButton.styleFrom(backgroundColor: _kSuccess, foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        child: const Text('बंद करें', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)))),
    ]);
  }

  Widget _formField(TextEditingController ctrl, String label, IconData icon, Color color) =>
    Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(controller: ctrl,
      style: const TextStyle(color: _kDark, fontSize: 13),
      decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: _kSubtle, fontSize: 12),
        prefixIcon: Icon(icon, size: 18, color: color), filled: true, fillColor: Colors.white, isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: color, width: 2)))));
}

// ══════════════════════════════════════════════════════════════════════════════
//  AUTO-ASSIGN RESULT VIEW  (updated: shows lower rank substitutions)
// ══════════════════════════════════════════════════════════════════════════════

class _AssignResultView extends StatelessWidget {
  final List<Map> assignedStaff, missingRanks, lowerRankAssignments;
  final String centerType;
  final int centerId;
  final Future<void> Function(String rank, int centerId) onAssignManual;
  final VoidCallback onManageRooms;
  final VoidCallback onCustomRules;
  const _AssignResultView({
    required this.assignedStaff, required this.missingRanks, required this.lowerRankAssignments,
    required this.centerType, required this.centerId,
    required this.onAssignManual, required this.onManageRooms, required this.onCustomRules});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Success banner
      Container(padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: _kSuccess.withOpacity(0.07), borderRadius: BorderRadius.circular(10), border: Border.all(color: _kSuccess.withOpacity(0.3))),
        child: Row(children: [
          const Icon(Icons.check_circle_rounded, color: _kSuccess, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Center बन गया!', style: TextStyle(color: _kSuccess, fontWeight: FontWeight.w800, fontSize: 13)),
            Text('${assignedStaff.length} स्टाफ "$centerType" मानक के अनुसार असाइन हुए', style: const TextStyle(color: _kSubtle, fontSize: 11))]))])),
      const SizedBox(height: 10),

      // Quick action buttons
      Row(children: [
        Expanded(child: GestureDetector(onTap: onManageRooms,
          child: Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _kPrimary.withOpacity(0.07), borderRadius: BorderRadius.circular(8), border: Border.all(color: _kPrimary.withOpacity(0.25))),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.meeting_room_outlined, size: 14, color: _kPrimary),
              SizedBox(width: 5),
              Text('Matdan Sthal', style: TextStyle(color: _kPrimary, fontSize: 11, fontWeight: FontWeight.w700))])))),
        const SizedBox(width: 8),
        Expanded(child: GestureDetector(onTap: onCustomRules,
          child: Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _kInfo.withOpacity(0.07), borderRadius: BorderRadius.circular(8), border: Border.all(color: _kInfo.withOpacity(0.25))),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.rule_outlined, size: 14, color: _kInfo),
              SizedBox(width: 5),
              Text('Custom Rules', style: TextStyle(color: _kInfo, fontSize: 11, fontWeight: FontWeight.w700))])))),
      ]),
      const SizedBox(height: 14),

      // Lower rank substitutions notice
      if (lowerRankAssignments.isNotEmpty) ...[
        Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.orange.withOpacity(0.07), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.withOpacity(0.35))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.swap_vert_outlined, color: Colors.orange, size: 16),
              SizedBox(width: 6),
              Text('Lower Rank से असाइन किया गया', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w800, fontSize: 12))]),
            const SizedBox(height: 8),
            ...lowerRankAssignments.map((lr) => Padding(padding: const EdgeInsets.only(bottom: 6),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.06), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.arrow_downward, size: 12, color: Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${lr['requiredRank']} ', style: const TextStyle(color: _kDark, fontWeight: FontWeight.w700, fontSize: 12)),
                    const TextSpan(text: 'नहीं मिला — ', style: TextStyle(color: _kSubtle, fontSize: 11)),
                    TextSpan(text: '${lr['assignedRank']}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w700, fontSize: 12)),
                    const TextSpan(text: ' से ${0} staff assigned', style: TextStyle(color: _kSubtle, fontSize: 11)),
                  ]))),
                ]))))])),
        const SizedBox(height: 14),
      ],

      // Assigned staff
      if (assignedStaff.isNotEmpty) ...[
        const Text('असाइन किए गए स्टाफ', style: TextStyle(color: _kDark, fontWeight: FontWeight.w800, fontSize: 13)),
        const SizedBox(height: 8),
        ...assignedStaff.map((s) {
          final rankColor = _kRankColors[s['rank']] ?? _kPrimary;
          final isLowerRank = (s['isLowerRank'] as bool?) == true;
          return Container(margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9), border: Border.all(color: _kBorder.withOpacity(0.4))),
            child: Row(children: [
              Icon(isLowerRank ? Icons.swap_vert_outlined : Icons.check_circle_outline,
                  color: isLowerRank ? Colors.orange : _kSuccess, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s['name'] ?? '', style: const TextStyle(color: _kDark, fontWeight: FontWeight.w700, fontSize: 13)),
                if (isLowerRank && (s['originalRank'] as String?)?.isNotEmpty == true)
                  Text('In place of: ${s['originalRank']}', style: const TextStyle(color: Colors.orange, fontSize: 10)),
              ])),
              Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: rankColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: Text(s['rank'] ?? '', style: TextStyle(color: rankColor, fontSize: 10, fontWeight: FontWeight.w700))),
            ]));
        }),
        const SizedBox(height: 14),
      ],

      // Missing ranks
      if (missingRanks.isNotEmpty) ...[
        const Row(children: [
          Icon(Icons.warning_amber_rounded, color: _kError, size: 16),
          SizedBox(width: 6),
          Text('अनुपलब्ध रैंक — मैन्युअल असाइन करें', style: TextStyle(color: _kError, fontWeight: FontWeight.w800, fontSize: 13))]),
        const SizedBox(height: 8),
        ...missingRanks.map((m) => Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: _kError.withOpacity(0.04), borderRadius: BorderRadius.circular(10), border: Border.all(color: _kError.withOpacity(0.25))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.person_off_outlined, color: _kError, size: 15),
              const SizedBox(width: 6),
              Expanded(child: Text('${m['rank']}', style: const TextStyle(color: _kError, fontWeight: FontWeight.w700, fontSize: 13))),
              Text('${m['required']} चाहिए, ${m['available']} उपलब्ध', style: const TextStyle(color: _kError, fontSize: 11))]),
            if ((m['lowerRankSuggestion'] as String?) != null) ...[
              const SizedBox(height: 4),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
                child: Text('सुझाव: ${m['lowerRankSuggestion']} rank से assign करें', style: const TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.w600))),
            ],
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () => onAssignManual(m['rank'] as String, centerId),
                icon: const Icon(Icons.person_add_outlined, size: 14),
                label: Text('${m['rank']} मैन्युअल असाइन'),
                style: OutlinedButton.styleFrom(foregroundColor: _kPrimary, side: const BorderSide(color: _kBorder),
                  padding: const EdgeInsets.symmetric(vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))))),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('रैंक छोड़ी गई'), backgroundColor: _kSubtle, behavior: SnackBarBehavior.floating));
              },
                style: OutlinedButton.styleFrom(foregroundColor: _kSubtle, side: BorderSide(color: _kSubtle.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text('छोड़ें')),
            ])]))),
      ],
    ]);
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

Widget _emptyState(String label, IconData icon, Color color) => Center(
  child: Padding(padding: const EdgeInsets.all(40),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: color.withOpacity(0.08), shape: BoxShape.circle),
        child: Icon(icon, size: 48, color: color.withOpacity(0.5))),
      const SizedBox(height: 16),
      Text('कोई $label नहीं', style: const TextStyle(color: _kDark, fontSize: 14, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      const Text('ऊपर जोड़ें बटन दबाएं', style: TextStyle(color: _kSubtle, fontSize: 12))])));

Future<bool> _confirm(BuildContext ctx, String msg) async =>
  await showDialog<bool>(context: ctx,
    builder: (d) => AlertDialog(backgroundColor: _kBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _kError, width: 1.2)),
      title: const Row(children: [Icon(Icons.warning_amber_rounded, color: _kError, size: 20), SizedBox(width: 8),
        Text('Confirm Delete', style: TextStyle(color: _kError, fontWeight: FontWeight.w800, fontSize: 15))]),
      content: Text(msg, style: const TextStyle(color: _kDark, fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('रद्द', style: TextStyle(color: _kSubtle))),
        ElevatedButton(onPressed: () => Navigator.pop(d, true),
          style: ElevatedButton.styleFrom(backgroundColor: _kError, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          child: const Text('हटाएं')),
      ])) ?? false;