import 'package:flutter/material.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';

// Officer model with controllers
class _Officer {
  int? id;
  int? userId;
  final nameCtrl = TextEditingController();
  final pnoCtrl = TextEditingController();
  final mobileCtrl = TextEditingController();
  final rankCtrl = TextEditingController();

  _Officer({this.id, this.userId, String name = '', String pno = '', String mobile = '', String rank = ''}) {
    nameCtrl.text = name;
    pnoCtrl.text = pno;
    mobileCtrl.text = mobile;
    rankCtrl.text = rank;
  }

  factory _Officer.fromJson(Map j) => _Officer(
        id: j['id'],
        userId: j['userId'],
        name: j['name'] ?? '',
        pno: j['pno'] ?? '',
        mobile: j['mobile'] ?? '',
        rank: j['rank'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (userId != null) 'userId': userId,
        'name': nameCtrl.text.trim(),
        'pno': pnoCtrl.text.trim(),
        'mobile': mobileCtrl.text.trim(),
        'rank': rankCtrl.text.trim(),
      };

  void dispose() {
    nameCtrl.dispose();
    pnoCtrl.dispose();
    mobileCtrl.dispose();
    rankCtrl.dispose();
  }
}

List<Map<String, dynamic>> _list(dynamic v) {
  if (v == null) return [];
  if (v is List) return v.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  return [];
}

Future<bool> _confirm(BuildContext ctx, String msg) async =>
    await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        backgroundColor: kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: kError),
        ),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: kError),
          SizedBox(width: 8),
          Text('Confirm Delete',
              style: TextStyle(color: kError, fontSize: 14, fontWeight: FontWeight.w800)),
        ]),
        content: Text(msg, style: const TextStyle(color: kDark, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel', style: TextStyle(color: kSubtle)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(d, true),
            style: ElevatedButton.styleFrom(backgroundColor: kError, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ??
    false;

// ─────────────────────────────────────────────────────────────────────────────
// FORM PAGE
// ─────────────────────────────────────────────────────────────────────────────
class FormPage extends StatefulWidget {
  const FormPage({super.key});
  @override
  State<FormPage> createState() => _FormPageState();
}

class _FormPageState extends State<FormPage> {
  List<Map<String, dynamic>> _szList = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final t = await AuthService.getToken();
      final r = await ApiService.get('/admin/super-zones', token: t);
      if (!mounted) return;
      setState(() {
        _szList = _list(r['data']);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showSnack(context, 'Load failed: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        color: kSurface,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(children: [
          const Icon(Icons.account_tree_outlined, color: kPrimary, size: 18),
          const SizedBox(width: 8),
          const Expanded(
              child: Text('Election Structure',
                  style: TextStyle(color: kDark, fontSize: 15, fontWeight: FontWeight.w800))),
          GestureDetector(
            onTap: () => _showSZDialog(context: context, onDone: _load),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(9)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add, color: Colors.white, size: 14),
                SizedBox(width: 4),
                Text('+ Super Zone',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ]),
      ),
      Container(
        color: kInfo.withOpacity(0.06),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        child: const Row(children: [
          Icon(Icons.info_outline, size: 12, color: kInfo),
          SizedBox(width: 6),
          Expanded(
              child: Text('Tap to expand • ✏ edit • 🗑 delete',
                  style: TextStyle(color: kInfo, fontSize: 11))),
        ]),
      ),
      if (_loading)
        const Expanded(child: Center(child: CircularProgressIndicator(color: kPrimary)))
      else if (_szList.isEmpty)
        Expanded(
            child: emptyState('No Super Zones yet.\nTap + Super Zone to begin.', Icons.layers_outlined))
      else
        Expanded(
            child: RefreshIndicator(
          onRefresh: _load,
          color: kPrimary,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 80),
            itemCount: _szList.length,
            itemBuilder: (_, i) => _SZTile(
              data: _szList[i],
              onChanged: _load,
              onEdit: () => _showSZDialog(context: context, onDone: _load, existing: _szList[i]),
            ),
          ),
        )),
    ]);
  }
}

// ─── Super Zone Dialog ────────────────────────────────────────────────────────
Future<void> _showSZDialog({
  required BuildContext context,
  required VoidCallback onDone,
  Map<String, dynamic>? existing,
}) async {
  final isEdit = existing != null;
  final nc = TextEditingController(text: existing?['name'] ?? '');
  final dc = TextEditingController(text: existing?['district'] ?? '');
  final bc = TextEditingController(text: existing?['block'] ?? '');
  final officers = <_Officer>[];

  for (final o in _list(existing?['officers'])) {
    officers.add(_Officer.fromJson(o));
  }
  if (officers.isEmpty) officers.add(_Officer());

  List<Map<String, dynamic>> staff = [];
  try {
    final t = await AuthService.getToken();
    final szId = existing?['id'] ?? 0;
    final r = await ApiService.get('/admin/super-zones/$szId/officers', token: t);
    staff = _list((r['data'] as Map?)?['availableStaff'] ?? []);
  } catch (_) {}

  if (!context.mounted) return;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, ss) => _Dlg(
        title: isEdit ? 'Edit Super Zone' : 'Add Super Zone',
        icon: Icons.layers_outlined,
        accent: kPrimary,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Sec('Super Zone', kPrimary, [
              AppTextField(label: 'Name *', controller: nc, prefixIcon: Icons.layers_outlined),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      label: 'District',
                      controller: dc,
                      prefixIcon: Icons.location_city_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppTextField(
                      label: 'Block',
                      controller: bc,
                      prefixIcon: Icons.domain_outlined,
                    ),
                  ),
                ],
              ),
            ]),
            _OfficerSec(
              title: 'Kshetra Adhikari',
              color: kAccent,
              officers: officers,
              staff: staff,
              ss: ss,
            ),
          ],
        ),

        // ✅ FIXED SAVE
        onSave: () async {
          if (nc.text.trim().isEmpty) {
            showSnack(ctx, 'Name required', error: true);
            return;
          }

          final t = await AuthService.getToken();

          final body = {
            'name': nc.text.trim(),
            'district': dc.text.trim(),
            'block': bc.text.trim(),
            'officers': officers.map((o) => o.toJson()).toList(),
          };

          try {
            if (isEdit) {
              await ApiService.put(
                "/admin/super-zones/${existing!['id']}",
                body,
                token: t,
              );
            } else {
              await ApiService.post(
                '/admin/super-zones',
                body,
                token: t,
              );
            }

            // ✅ CRITICAL FIX
            if (!ctx.mounted) return;

            Navigator.pop(ctx);
            onDone();

          } catch (e) {
            if (!ctx.mounted) return;
            showSnack(ctx, 'Error: $e', error: true);
          }
        },

        // ✅ FIXED CANCEL
        onCancel: () {
          Navigator.pop(ctx);
        },
      ),
    ),
  );
}

// ─── SZ Tile ──────────────────────────────────────────────────────────────────
class _SZTile extends StatefulWidget {
  final Map<String, dynamic> data;
  final VoidCallback onChanged, onEdit;
  const _SZTile({required this.data, required this.onChanged, required this.onEdit});
  @override
  State<_SZTile> createState() => _SZTileState();
}

class _SZTileState extends State<_SZTile> {
  List<Map<String, dynamic>> _zones = [];
  bool _open = false, _busy = false;

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final t = await AuthService.getToken();
      final r = await ApiService.get("/admin/super-zones/${widget.data['id']}/zones", token: t);
      if (!mounted) return;
      setState(() {
        _zones = _list(r['data']);
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _del() async {
    if (!await _confirm(context, 'Delete Super Zone "${widget.data['name']}"?')) return;
    try {
      final t = await AuthService.getToken();
      await ApiService.delete('/admin/super-zones/${widget.data['id']}', token: t);
      widget.onChanged();
    } catch (e) {
      if (mounted) showSnack(context, 'Error: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final offs = _list(d['officers']);
    return _HCard(
      level: 0,
      accent: kPrimary,
      open: _open,
      header: _HRow(
        level: 0,
        accent: kPrimary,
        icon: Icons.layers_outlined,
        title: d['name'] ?? '',
        sub: '${d['district'] ?? ''} ${(d['block'] ?? '').isNotEmpty ? '• ${d['block']}' : ''}',
        badge: '${d['zoneCount'] ?? 0} Zones',
        officers: offs,
        open: _open,
        onTap: () {
          setState(() => _open = !_open);
          if (_open && _zones.isEmpty) _load();
        },
        onEdit: widget.onEdit,
        onDel: _del,
      ),
      body: _busy
          ? const _Spin()
          : Column(children: [
              ..._zones.map((z) => _ZoneTile(data: z, szId: widget.data['id'], onChanged: _load)),
              _AddBtn(
                'Add Zone',
                Icons.grid_view_outlined,
                kAccent,
                () => _showZoneDialog(
                    context: context, szId: widget.data['id'], onDone: _load),
              ),
            ]),
    );
  }
}

// ─── Zone Dialog ──────────────────────────────────────────────────────────────
Future<void> _showZoneDialog({
  required BuildContext context,
  required int szId,
  required VoidCallback onDone,
  Map<String, dynamic>? existing,
}) async {
  final isEdit = existing != null;
  final nc = TextEditingController(text: existing?['name'] ?? '');
  final hc = TextEditingController(text: existing?['hqAddress'] ?? '');
  final officers = <_Officer>[];

  for (final o in _list(existing?['officers'])) officers.add(_Officer.fromJson(o));
  if (officers.isEmpty) officers.add(_Officer());

  List<Map<String, dynamic>> staff = [];
  try {
    final t = await AuthService.getToken();
    final r = await ApiService.get('/admin/zones/${existing?['id'] ?? 0}/officers', token: t);
    staff = _list((r['data'] as Map?)??{}['availableStaff'] ?? []);
  } catch (_) {}

  if (!context.mounted) return;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, ss) => _Dlg(
        title: isEdit ? 'Edit Zone' : 'Add Zone',
        icon: Icons.grid_view_outlined,
        accent: kAccent,
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _Sec('Zone Details', kAccent, [
            AppTextField(
                label: 'Zone Name *', controller: nc, prefixIcon: Icons.grid_view_outlined),
            AppTextField(
                label: 'HQ / Mukhyalay', controller: hc, prefixIcon: Icons.home_outlined),
          ]),
          _OfficerSec(
              title: 'Zonal Adhikari',
              color: kPrimary,
              officers: officers,
              staff: staff,
              ss: ss),
        ]),
        onSave: () async {
          if (nc.text.trim().isEmpty) {
            showSnack(ctx, 'Name required', error: true);
            return;
          }
          final t = await AuthService.getToken();
          final body = {
            'name': nc.text.trim(),
            'hqAddress': hc.text.trim(),
            'officers': officers.map((o) => o.toJson()).toList(),
          };
          if (isEdit) {
            await ApiService.put('/admin/zones/${existing!['id']}', body, token: t);
          } else {
            await ApiService.post('/admin/super-zones/$szId/zones', body, token: t);
          }
          if (ctx.mounted) Navigator.pop(ctx);
          
          onDone();
        },
        onCancel: () {
          Navigator.pop(ctx);
          
        },
      ),
    ),
  );
}

class _ZoneTile extends StatefulWidget {
  final Map<String, dynamic> data;
  final int szId;
  final VoidCallback onChanged;
  const _ZoneTile({required this.data, required this.szId, required this.onChanged});
  @override
  State<_ZoneTile> createState() => _ZoneTileState();
}

class _ZoneTileState extends State<_ZoneTile> {
  List<Map<String, dynamic>> _sectors = [];
  bool _open = false, _busy = false;

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final t = await AuthService.getToken();
      final r = await ApiService.get('/admin/zones/${widget.data['id']}/sectors', token: t);
      if (!mounted) return;
      setState(() {
        _sectors = _list(r['data']);
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _del() async {
    if (!await _confirm(context, 'Delete Zone "${widget.data['name']}"?')) return;
    try {
      final t = await AuthService.getToken();
      await ApiService.delete('/admin/zones/${widget.data['id']}', token: t);
      widget.onChanged();
    } catch (e) {
      if (mounted) showSnack(context, 'Error: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final offs = _list(d['officers']);
    return _HCard(
      level: 1,
      accent: kAccent,
      open: _open,
      header: _HRow(
        level: 1,
        accent: kAccent,
        icon: Icons.grid_view_outlined,
        title: d['name'] ?? '',
        sub: d['hqAddress'] ?? '',
        badge: '${d['sectorCount'] ?? 0} Sectors',
        officers: offs,
        open: _open,
        onTap: () {
          setState(() => _open = !_open);
          if (_open && _sectors.isEmpty) _load();
        },
        onEdit: () => _showZoneDialog(
            context: context, szId: widget.szId, existing: d, onDone: widget.onChanged),
        onDel: _del,
      ),
      body: _busy
          ? const _Spin()
          : Column(children: [
              ..._sectors
                  .map((s) => _SectorTile(data: s, zoneId: widget.data['id'], onChanged: _load)),
              _AddBtn(
                'Add Sector',
                Icons.view_module_outlined,
                kSuccess,
                () => _showSectorDialog(
                    context: context, zoneId: widget.data['id'], onDone: _load),
              ),
            ]),
    );
  }
}

// ─── Sector Dialog ────────────────────────────────────────────────────────────
Future<void> _showSectorDialog({
  required BuildContext context,
  required int zoneId,
  required VoidCallback onDone,
  Map<String, dynamic>? existing,
}) async {
  final isEdit = existing != null;
  final nc = TextEditingController(text: existing?['name'] ?? '');
  final officers = <_Officer>[];

  for (final o in _list(existing?['officers'])) officers.add(_Officer.fromJson(o));
  if (officers.isEmpty) officers.add(_Officer());

  List<Map<String, dynamic>> staff = [];
  try {
    final t = await AuthService.getToken();
    final r =
        await ApiService.get('/admin/sectors/${existing?['id'] ?? 0}/officers', token: t);
    staff = _list((r['data'] as Map?)??{}['availableStaff'] ?? []);
  } catch (_) {}

  if (!context.mounted) return;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, ss) => _Dlg(
        title: isEdit ? 'Edit Sector' : 'Add Sector',
        icon: Icons.view_module_outlined,
        accent: kSuccess,
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _Sec('Sector Details', kSuccess, [
            AppTextField(
                label: 'Sector Name *',
                controller: nc,
                prefixIcon: Icons.view_module_outlined),
          ]),
          _OfficerSec(
              title: 'Police Adhikari',
              color: kInfo,
              officers: officers,
              staff: staff,
              ss: ss),
        ]),
        onSave: () async {
          if (nc.text.trim().isEmpty) {
            showSnack(ctx, 'Name required', error: true);
            return;
          }
          final t = await AuthService.getToken();
          final body = {
            'name': nc.text.trim(),
            'officers': officers
                .where((o) => o.nameCtrl.text.trim().isNotEmpty)
                .map((o) => o.toJson())
                .toList(),
          };
          if (isEdit) {
            await ApiService.put('/admin/sectors/${existing!['id']}', body, token: t);
          } else {
            await ApiService.post('/admin/zones/$zoneId/sectors', body, token: t);
          }
          if (ctx.mounted) Navigator.pop(ctx);
          
          
          onDone();
        },
        onCancel: () {
          Navigator.pop(ctx);
          
          
        },
      ),
    ),
  );
}

class _SectorTile extends StatefulWidget {
  final Map<String, dynamic> data;
  final int zoneId;
  final VoidCallback onChanged;
  const _SectorTile({required this.data, required this.zoneId, required this.onChanged});
  @override
  State<_SectorTile> createState() => _SectorTileState();
}

class _SectorTileState extends State<_SectorTile> {
  List<Map<String, dynamic>> _gps = [];
  bool _open = false, _busy = false;

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final t = await AuthService.getToken();
      final r = await ApiService.get(
          '/admin/sectors/${widget.data['id']}/gram-panchayats',
          token: t);
      if (!mounted) return;
      setState(() {
        _gps = _list(r['data']);
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _del() async {
    if (!await _confirm(context, 'Delete Sector "${widget.data['name']}"?')) return;
    try {
      final t = await AuthService.getToken();
      await ApiService.delete('/admin/sectors/${widget.data['id']}', token: t);
      widget.onChanged();
    } catch (e) {
      if (mounted) showSnack(context, 'Error: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final offs = _list(d['officers']);
    return _HCard(
      level: 2,
      accent: kSuccess,
      open: _open,
      header: _HRow(
        level: 2,
        accent: kSuccess,
        icon: Icons.view_module_outlined,
        title: d['name'] ?? '',
        sub: '${d['gpCount'] ?? 0} Gram Panchayats',
        badge: '${offs.length} Officers',
        officers: offs,
        open: _open,
        onTap: () {
          setState(() => _open = !_open);
          if (_open && _gps.isEmpty) _load();
        },
        onEdit: () => _showSectorDialog(
            context: context,
            zoneId: widget.zoneId,
            existing: d,
            onDone: widget.onChanged),
        onDel: _del,
      ),
      body: _busy
          ? const _Spin()
          : Column(children: [
              ..._gps.map((g) =>
                  _GPTile(data: g, sectorId: widget.data['id'], onChanged: _load)),
              _AddBtn(
                'Add Gram Panchayat',
                Icons.account_balance_outlined,
                kInfo,
                () => _showGPDialog(
                    context: context, sectorId: widget.data['id'], onDone: _load),
              ),
            ]),
    );
  }
}

// ─── GP Dialog + Tile ─────────────────────────────────────────────────────────
Future<void> _showGPDialog({
  required BuildContext context,
  required int sectorId,
  required VoidCallback onDone,
  Map<String, dynamic>? existing,
}) async {
  final isEdit = existing != null;
  final nc = TextEditingController(text: existing?['name'] ?? '');
  final ac = TextEditingController(text: existing?['address'] ?? '');

  if (!context.mounted) return;

  await showDialog(
    context: context,
    builder: (ctx) => _Dlg(
      title: isEdit ? 'Edit Gram Panchayat' : 'Add Gram Panchayat',
      icon: Icons.account_balance_outlined,
      accent: kInfo,
      content: _Sec('Gram Panchayat', kInfo, [
        AppTextField(
            label: 'GP Name *', controller: nc, prefixIcon: Icons.account_balance_outlined),
        AppTextField(label: 'Address', controller: ac, prefixIcon: Icons.map_outlined),
      ]),
      onSave: () async {
        if (nc.text.trim().isEmpty) {
          showSnack(ctx, 'Name required', error: true);
          return;
        }
        final t = await AuthService.getToken();
        final body = {'name': nc.text.trim(), 'address': ac.text.trim()};
        if (isEdit) {
          await ApiService.put('/admin/gram-panchayats/${existing!['id']}', body, token: t);
        } else {
          await ApiService.post('/admin/sectors/$sectorId/gram-panchayats', body, token: t);
        }
        if (ctx.mounted) Navigator.pop(ctx);
        
        
        onDone();
      },
      onCancel: () {
        Navigator.pop(ctx);
        
        
      },
    ),
  );
}

class _GPTile extends StatefulWidget {
  final Map<String, dynamic> data;
  final int sectorId;
  final VoidCallback onChanged;
  const _GPTile({required this.data, required this.sectorId, required this.onChanged});
  @override
  State<_GPTile> createState() => _GPTileState();
}

class _GPTileState extends State<_GPTile> {
  List<Map<String, dynamic>> _centers = [];
  bool _open = false, _busy = false;

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final t = await AuthService.getToken();
      final r = await ApiService.get(
          '/admin/gram-panchayats/${widget.data['id']}/centers',
          token: t);
      if (!mounted) return;
      setState(() {
        _centers = _list(r['data']);
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _del() async {
    if (!await _confirm(context, 'Delete GP "${widget.data['name']}"?')) return;
    try {
      final t = await AuthService.getToken();
      await ApiService.delete('/admin/gram-panchayats/${widget.data['id']}', token: t);
      widget.onChanged();
    } catch (e) {
      if (mounted) showSnack(context, 'Error: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return _HCard(
      level: 3,
      accent: kInfo,
      open: _open,
      header: _HRow(
        level: 3,
        accent: kInfo,
        icon: Icons.account_balance_outlined,
        title: d['name'] ?? '',
        sub: d['address'] ?? '',
        badge: '${d['centerCount'] ?? 0} Centers',
        officers: const [],
        open: _open,
        onTap: () {
          setState(() => _open = !_open);
          if (_open && _centers.isEmpty) _load();
        },
        onEdit: () => _showGPDialog(
            context: context,
            sectorId: widget.sectorId,
            existing: d,
            onDone: widget.onChanged),
        onDel: _del,
      ),
      body: _busy
          ? const _Spin()
          : Column(children: [
              ..._centers.map((c) =>
                  _CenterTile(data: c, gpId: widget.data['id'], onChanged: _load)),
              _AddBtn(
                'Add Election Center',
                Icons.add_location_alt_outlined,
                const Color(0xFF6A1B9A),
                () => _showCenterDialog(
                    context: context, gpId: widget.data['id'], onDone: _load),
              ),
            ]),
    );
  }
}

// ─── Center Dialog + Tile ─────────────────────────────────────────────────────
Future<void> _showCenterDialog({
  required BuildContext context,
  required int gpId,
  required VoidCallback onDone,
  Map<String, dynamic>? existing,
}) async {
  final isEdit = existing != null;
  final nc = TextEditingController(text: existing?['name'] ?? '');
  final ac = TextEditingController(text: existing?['address'] ?? '');
  final tc = TextEditingController(text: existing?['thana'] ?? '');
  final bc = TextEditingController(text: existing?['busNo'] ?? '');
  String type = existing?['centerType'] ?? 'C';

  if (!context.mounted) return;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, ss) => _Dlg(
        title: isEdit ? 'Edit Center' : 'Add Election Center',
        icon: Icons.location_on_outlined,
        accent: const Color(0xFF6A1B9A),
        content: _Sec('Matdan Sthal', const Color(0xFF6A1B9A), [
          AppTextField(
              label: 'Center Name *',
              controller: nc,
              prefixIcon: Icons.location_on_outlined),
          AppTextField(label: 'Address', controller: ac, prefixIcon: Icons.map_outlined),
          Row(children: [
            Expanded(
                child: AppTextField(
                    label: 'Thana',
                    controller: tc,
                    prefixIcon: Icons.local_police_outlined)),
            const SizedBox(width: 8),
            Expanded(
                child: AppTextField(
                    label: 'Bus No',
                    controller: bc,
                    prefixIcon: Icons.directions_bus_outlined)),
          ]),
          const SizedBox(height: 4),
          const Text('Center Type',
              style: TextStyle(
                  color: kSubtle, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
              children: ['A', 'B', 'C'].map((t) {
            final sel = type == t;
            final c = t == 'A' ? kError : t == 'B' ? kAccent : kSuccess;
            return Expanded(
              child: GestureDetector(
                onTap: () => ss(() => type = t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: EdgeInsets.only(right: t == 'C' ? 0 : 8),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? c : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c, width: sel ? 2 : 1),
                  ),
                  child: Column(children: [
                    Text('Type $t',
                        style: TextStyle(
                            color: sel ? Colors.white : c,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                    Text(
                        t == 'A'
                            ? 'High'
                            : t == 'B'
                                ? 'Medium'
                                : 'Normal',
                        style: TextStyle(
                            color: sel
                                ? Colors.white70
                                : c.withOpacity(0.7),
                            fontSize: 10)),
                  ]),
                ),
              ),
            );
          }).toList()),
        ]),
        onSave: () async {
          if (nc.text.trim().isEmpty) {
            showSnack(ctx, 'Name required', error: true);
            return;
          }
          final t = await AuthService.getToken();
          final body = {
            'name': nc.text.trim(),
            'address': ac.text.trim(),
            'thana': tc.text.trim(),
            'busNo': bc.text.trim(),
            'centerType': type,
          };
          if (isEdit) {
            await ApiService.put('/admin/centers/${existing!['id']}', body, token: t);
          } else {
            await ApiService.post('/admin/gram-panchayats/$gpId/centers', body, token: t);
          }
          if (ctx.mounted) Navigator.pop(ctx);
          
          onDone();
        },
        onCancel: () {
          Navigator.pop(ctx);
          
          
        },
      ),
    ),
  );
}

class _CenterTile extends StatefulWidget {
  final Map<String, dynamic> data;
  final int gpId;
  final VoidCallback onChanged;
  const _CenterTile({required this.data, required this.gpId, required this.onChanged});
  @override
  State<_CenterTile> createState() => _CenterTileState();
}

class _CenterTileState extends State<_CenterTile> {
  List<Map<String, dynamic>> _rooms = [], _duties = [];
  bool _open = false, _busy = false;

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final t = await AuthService.getToken();
      final rr =
          await ApiService.get('/admin/centers/${widget.data['id']}/rooms', token: t);
      final rd = await ApiService.get(
          '/admin/duties?center_id=${widget.data['id']}',
          token: t);
      if (!mounted) return;
      setState(() {
        _rooms = _list(rr['data']);
        _duties = _list(rd['data']);
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _del() async {
    if (!await _confirm(context, 'Delete Center "${widget.data['name']}"?')) return;
    try {
      final t = await AuthService.getToken();
      await ApiService.delete('/admin/centers/${widget.data['id']}', token: t);
      widget.onChanged();
    } catch (e) {
      if (mounted) showSnack(context, 'Error: $e', error: true);
    }
  }

  Future<void> _addRoom() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => _Dlg(
        title: 'Add Room (Matdan Kendra)',
        icon: Icons.door_front_door_outlined,
        accent: const Color(0xFF6A1B9A),
        content: _Sec('Room', const Color(0xFF6A1B9A), [
          AppTextField(
              label: 'Room Number *',
              controller: ctrl,
              prefixIcon: Icons.numbers_outlined),
        ]),
        onSave: () async {
          if (ctrl.text.trim().isEmpty) {
            showSnack(ctx, 'Required', error: true);
            return;
          }
          final t = await AuthService.getToken();
          await ApiService.post(
              '/admin/centers/${widget.data['id']}/rooms',
              {'roomNumber': ctrl.text.trim()},
              token: t);
          if (ctx.mounted) Navigator.pop(ctx);
          
          _load();
        },
        onCancel: () {
          Navigator.pop(ctx);
          
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final t = d['centerType'] ?? 'C';
    final tc = t == 'A' ? kError : t == 'B' ? kAccent : kSuccess;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 5),
      child: Column(children: [
        GestureDetector(
          onTap: () {
            setState(() => _open = !_open);
            if (_open) _load();
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: tc.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tc.withOpacity(0.3)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration:
                    BoxDecoration(color: tc, borderRadius: BorderRadius.circular(4)),
                child: Text('Type $t',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 8),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d['name'] ?? '',
                    style: const TextStyle(
                        color: kDark, fontWeight: FontWeight.w700, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                    '${d['thana'] ?? ''} • Bus:${d['busNo'] ?? '-'} • ${d['dutyCount'] ?? 0} staff',
                    style: const TextStyle(color: kSubtle, fontSize: 10)),
              ])),
              Icon(
                  _open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: tc),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _showCenterDialog(
                    context: context,
                    gpId: widget.gpId,
                    existing: d,
                    onDone: widget.onChanged),
                child: const Icon(Icons.edit_outlined, size: 14, color: kAccent),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                  onTap: _del,
                  child: const Icon(Icons.delete_outline, size: 14, color: kError)),
            ]),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: _busy
              ? const _Spin()
              : Container(
                  margin: const EdgeInsets.only(left: 10, top: 4),
                  padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                  decoration: BoxDecoration(
                      border: Border(
                          left: BorderSide(color: tc.withOpacity(0.3), width: 2))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Rooms
                    Row(children: [
                      const Icon(Icons.door_front_door_outlined,
                          size: 11, color: kSubtle),
                      const SizedBox(width: 4),
                      const Text('Matdan Kendra (Rooms)',
                          style: TextStyle(
                              color: kSubtle,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                      const Spacer(),
                      GestureDetector(
                        onTap: _addRoom,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                              color:
                                  const Color(0xFF6A1B9A).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(5)),
                          child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add,
                                    size: 11, color: Color(0xFF6A1B9A)),
                                SizedBox(width: 2),
                                Text('Add Room',
                                    style: TextStyle(
                                        color: Color(0xFF6A1B9A),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700)),
                              ]),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 5),
                    if (_rooms.isEmpty)
                      const Text('No rooms yet',
                          style: TextStyle(color: kSubtle, fontSize: 11))
                    else
                      Wrap(
                          spacing: 5,
                          runSpacing: 5,
                          children: _rooms
                              .map((r) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(
                                            color:
                                                kBorder.withOpacity(0.5))),
                                    child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                              Icons.door_front_door_outlined,
                                              size: 11,
                                              color: kSubtle),
                                          const SizedBox(width: 3),
                                          Text('Room ${r['roomNumber']}',
                                              style: const TextStyle(
                                                  color: kDark,
                                                  fontSize: 11,
                                                  fontWeight:
                                                      FontWeight.w600)),
                                          const SizedBox(width: 4),
                                          GestureDetector(
                                            onTap: () async {
                                              final tok =
                                                  await AuthService.getToken();
                                              await ApiService.delete(
                                                  '/admin/rooms/${r['id']}',
                                                  token: tok);
                                              _load();
                                            },
                                            child: const Icon(Icons.close,
                                                size: 11, color: kError),
                                          ),
                                        ]),
                                  ))
                              .toList()),
                    const SizedBox(height: 10),
                    // Assigned staff
                    const Row(children: [
                      Icon(Icons.how_to_vote_outlined,
                          size: 11, color: kSubtle),
                      SizedBox(width: 4),
                      Text('Assigned Staff',
                          style: TextStyle(
                              color: kSubtle,
                              fontSize: 11,
                              fontWeight: FontWeight.w700))
                    ]),
                    const SizedBox(height: 4),
                    if (_duties.isEmpty)
                      const Text('No staff assigned',
                          style: TextStyle(color: kSubtle, fontSize: 11))
                    else
                      ..._duties.map((duty) => Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                                color: kSuccess.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: kSuccess.withOpacity(0.2))),
                            child: Row(children: [
                              _Av(duty['name'] ?? '', kSuccess),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(duty['name'] ?? '',
                                        style: const TextStyle(
                                            color: kDark,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700)),
                                    Text(
                                        'PNO:${duty['pno'] ?? ''} • ${duty['mobile'] ?? ''}',
                                        style: const TextStyle(
                                            color: kSubtle, fontSize: 10)),
                                  ])),
                              GestureDetector(
                                onTap: () async {
                                  final tok = await AuthService.getToken();
                                  await ApiService.delete(
                                      '/admin/duties/${duty['id']}',
                                      token: tok);
                                  _load();
                                },
                                child: const Icon(
                                    Icons.remove_circle_outline,
                                    size: 15,
                                    color: kError),
                              ),
                            ]),
                          )),
                  ]),
                ),
          crossFadeState:
              _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 220),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

// Dialog wrapper
class _Dlg extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final Widget content;
  final Future<void> Function() onSave;
  final VoidCallback onCancel;
  const _Dlg({
    required this.title,
    required this.icon,
    required this.accent,
    required this.content,
    required this.onSave,
    required this.onCancel,
  });
  @override
  State<_Dlg> createState() => _DlgState();
}

class _DlgState extends State<_Dlg> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
          horizontal: sw > 560 ? (sw - 520) / 2 : 12, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Container(
          decoration: BoxDecoration(
            color: kBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kBorder, width: 1.2),
            boxShadow: [
              BoxShadow(
                  color: widget.accent.withOpacity(0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8))
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              decoration: BoxDecoration(
                  color: kDark,
                  borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(15),
                      topRight: Radius.circular(15))),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                      color: widget.accent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6)),
                  child: Icon(widget.icon, color: widget.accent, size: 15),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(widget.title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14))),
                IconButton(
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.close, color: Colors.white60, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),
            Flexible(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                    child: widget.content)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: Row(children: [
                Expanded(
                    child: OutlinedButton(
                  onPressed: _saving ? null : widget.onCancel,
                  style: OutlinedButton.styleFrom(
                      foregroundColor: kSubtle,
                      side: const BorderSide(color: kBorder),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: const Text('Cancel'),
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: ElevatedButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          setState(() => _saving = true);
                          try {
                            await widget.onSave();
                          } catch (e) {
                            if (mounted) setState(() => _saving = false);
                            if (mounted) showSnack(context, 'Error: $e', error: true);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Save',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                )),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// Section header
class _Sec extends StatelessWidget {
  final String title;
  final Color color;
  final List<Widget> fields;
  const _Sec(this.title, this.color, this.fields);

  @override
  Widget build(BuildContext context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withOpacity(0.2))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 3,
                    height: 12,
                    decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 6),
                Text(title,
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
              ]),
            ),
            ...fields,
            const SizedBox(height: 4),
          ]);
}

// Officer section
class _OfficerSec extends StatelessWidget {
  final String title;
  final Color color;
  final List<_Officer> officers;
  final List<Map<String, dynamic>> staff;
  final StateSetter ss;
  const _OfficerSec({
    required this.title,
    required this.color,
    required this.officers,
    required this.staff,
    required this.ss,
  });

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withOpacity(0.2))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 3,
                height: 12,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 6),
            Text(title,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w800)),
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10)),
              child: Text('${officers.length}',
                  style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w900)),
            ),
          ]),
        ),
        ...List.generate(
            officers.length,
            (i) => _OCard(
                  index: i,
                  o: officers[i],
                  color: color,
                  staff: staff,
                  canRemove: officers.length > 1,
                  onRemove: () => ss(() => officers.removeAt(i)),
                  onPick: (s) => ss(() {
                    officers[i].userId = s['id'];
                    officers[i].nameCtrl.text = s['name'] ?? '';
                    officers[i].pnoCtrl.text = s['pno'] ?? '';
                    officers[i].mobileCtrl.text = s['mobile'] ?? '';
                    officers[i].rankCtrl.text = s['rank'] ?? '';
                  }),
                )),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => ss(() => officers.add(_Officer())),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
                color: color.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withOpacity(0.2))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.person_add_outlined, size: 14, color: color),
              const SizedBox(width: 6),
              Text('+ Add Another $title',
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
        const SizedBox(height: 14),
      ]);
}

// Officer card
class _OCard extends StatelessWidget {
  final int index;
  final _Officer o;
  final Color color;
  final List<Map<String, dynamic>> staff;
  final bool canRemove;
  final VoidCallback onRemove;
  final void Function(Map<String, dynamic>) onPick;
  const _OCard({
    required this.index,
    required this.o,
    required this.color,
    required this.staff,
    required this.canRemove,
    required this.onRemove,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: color.withOpacity(0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.18))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(5)),
              child: Text('Officer ${index + 1}',
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 8),
            if (staff.isNotEmpty)
              GestureDetector(
                onTap: () => _pick(context),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: kInfo.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: kInfo.withOpacity(0.3))),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.search, size: 11, color: kInfo),
                    SizedBox(width: 3),
                    Text('Pick Staff',
                        style: TextStyle(
                            color: kInfo,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            const Spacer(),
            if (canRemove)
              GestureDetector(
                  onTap: onRemove,
                  child: const Icon(Icons.remove_circle_outline,
                      size: 17, color: kError)),
          ]),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (_, c) {
            final wide = c.maxWidth > 340;
            if (wide) {
              return Column(children: [
                AppTextField(
                    label: 'Officer Name *',
                    controller: o.nameCtrl,
                    prefixIcon: Icons.person_outline),
                Row(children: [
                  Expanded(
                      child: AppTextField(
                          label: 'PNO',
                          controller: o.pnoCtrl,
                          prefixIcon: Icons.badge_outlined)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: AppTextField(
                          label: 'Mobile',
                          controller: o.mobileCtrl,
                          prefixIcon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone)),
                ]),
                AppTextField(
                    label: 'Pad / Rank / Post',
                    controller: o.rankCtrl,
                    prefixIcon: Icons.military_tech_outlined),
              ]);
            }
            return Column(children: [
              AppTextField(
                  label: 'Name *',
                  controller: o.nameCtrl,
                  prefixIcon: Icons.person_outline),
              AppTextField(
                  label: 'PNO',
                  controller: o.pnoCtrl,
                  prefixIcon: Icons.badge_outlined),
              AppTextField(
                  label: 'Mobile',
                  controller: o.mobileCtrl,
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone),
              AppTextField(
                  label: 'Rank / Post',
                  controller: o.rankCtrl,
                  prefixIcon: Icons.military_tech_outlined),
            ]);
          }),
        ]),
      );

  Future<void> _pick(BuildContext context) async {
    final search = ValueNotifier('');
    await showModalBottomSheet(
      context: context,
      backgroundColor: kBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        minChildSize: 0.35,
        expand: false,
        builder: (ctx, sc) => Column(children: [
          Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: kBorder, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
            child: Column(children: [
              const Text('Select Officer from Staff',
                  style: TextStyle(
                      color: kDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
              const SizedBox(height: 10),
              TextField(
                onChanged: (v) => search.value = v.toLowerCase(),
                decoration: InputDecoration(
                  hintText: 'Search name, PNO, mobile…',
                  hintStyle: const TextStyle(color: kSubtle, fontSize: 13),
                  prefixIcon:
                      const Icon(Icons.search, color: kSubtle, size: 18),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
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
                      borderSide:
                          const BorderSide(color: kPrimary, width: 2)),
                ),
              ),
            ]),
          ),
          Expanded(
              child: ValueListenableBuilder<String>(
            valueListenable: search,
            builder: (_, q, __) {
              final filtered = staff
                  .where((s) =>
                      q.isEmpty ||
                      '${s['name']}'.toLowerCase().contains(q) ||
                      '${s['pno']}'.toLowerCase().contains(q))
                  .toList();
              return ListView.builder(
                controller: sc,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  if (i >= filtered.length) return const SizedBox.shrink();
                  final s = filtered[i];
                  return ListTile(
                    dense: true,
                    leading: _Av(s['name'] ?? '', kPrimary),
                    title: Text(s['name'] ?? '',
                        style: const TextStyle(
                            color: kDark,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    subtitle: Text(
                        'PNO:${s['pno'] ?? ''} • ${s['mobile'] ?? ''} • ${s['rank'] ?? ''}',
                        style:
                            const TextStyle(color: kSubtle, fontSize: 11)),
                    onTap: () {
                      onPick(s);
                      Navigator.pop(ctx);
                    },
                  );
                },
              );
            },
          )),
        ]),
      ),
    );
  }
}

// Hierarchy card
class _HCard extends StatelessWidget {
  final int level;
  final Color accent;
  final bool open;
  final Widget header, body;
  const _HCard({
    required this.level,
    required this.accent,
    required this.open,
    required this.header,
    required this.body,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 5),
        child: Column(children: [
          header,
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              margin: const EdgeInsets.only(left: 12),
              padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
              decoration: BoxDecoration(
                  border: Border(
                      left: BorderSide(
                          color: accent.withOpacity(0.3), width: 2))),
              child: body,
            ),
            crossFadeState:
                open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ]),
      );
}

// Hierarchy row header
class _HRow extends StatelessWidget {
  final int level;
  final Color accent;
  final IconData icon;
  final String title, sub, badge;
  final List officers;
  final bool open;
  final VoidCallback onTap, onEdit, onDel;
  const _HRow({
    required this.level,
    required this.accent,
    required this.icon,
    required this.title,
    required this.sub,
    required this.badge,
    required this.officers,
    required this.open,
    required this.onTap,
    required this.onEdit,
    required this.onDel,
  });

  static const _bgs = [
    kSurface,
    Color(0xFFFFF8E1),
    Color(0xFFE8F5E9),
    Color(0xFFE3F2FD)
  ];

  @override
  Widget build(BuildContext context) {
    final bg = _bgs[level.clamp(0, 3)];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withOpacity(0.3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 4,
                height: 32,
                decoration: BoxDecoration(
                    color: accent, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 7),
            Expanded(
                child:
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      color: kDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              if (sub.isNotEmpty)
                Text(sub,
                    style: const TextStyle(color: kSubtle, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withOpacity(0.3))),
              child: Text(badge,
                  style: TextStyle(
                      color: accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 4),
            Icon(
                open
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: accent),
            GestureDetector(
                onTap: onEdit,
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child:
                        const Icon(Icons.edit_outlined, size: 14, color: kAccent))),
            GestureDetector(
                onTap: onDel,
                child: const Icon(Icons.delete_outline, size: 14, color: kError)),
          ]),
          if (officers.isNotEmpty) ...[
            const SizedBox(height: 5),
            Wrap(
                spacing: 4,
                runSpacing: 4,
                children: officers
                    .take(4)
                    .map((o) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                  color: accent.withOpacity(0.2))),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.person_outline,
                                size: 10, color: accent),
                            const SizedBox(width: 3),
                            ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxWidth: 100),
                              child: Text('${o['name'] ?? ''}',
                                  style: TextStyle(
                                      color: accent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            if ((o['rank'] ?? '').isNotEmpty) ...[
                              const SizedBox(width: 4),
                              Text('(${o['rank']})',
                                  style: const TextStyle(
                                      color: kSubtle, fontSize: 9)),
                            ],
                          ]),
                        ))
                    .toList()),
            if (officers.length > 4)
              Text('+${officers.length - 4} more',
                  style: TextStyle(
                      color: accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
          ],
        ]),
      ),
    );
  }
}

// Add button
Widget _AddBtn(String label, IconData icon, Color color, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 4, bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
            color: color.withOpacity(0.06),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: color.withOpacity(0.22))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.15), shape: BoxShape.circle),
              child: Icon(Icons.add, size: 12, color: color)),
          const SizedBox(width: 7),
          Text('+ $label',
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      ),
    );

// Avatar
class _Av extends StatelessWidget {
  final String name;
  final Color color;
  const _Av(this.name, this.color);

  @override
  Widget build(BuildContext context) {
    final i = name
        .trim()
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.1),
          border: Border.all(color: color.withOpacity(0.3))),
      child: Center(
          child: Text(i.isNotEmpty ? i : 'S',
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 11))),
    );
  }
}

// Spinner
class _Spin extends StatelessWidget {
  const _Spin();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Center(
            child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    color: kPrimary, strokeWidth: 2))),
      );
}