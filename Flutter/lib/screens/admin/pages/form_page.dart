import 'package:flutter/material.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';

class FormPage extends StatefulWidget {
  const FormPage({super.key});
  @override
  State<FormPage> createState() => _FormPageState();
}

class _FormPageState extends State<FormPage> {
  List _superZones = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.get('/admin/super-zones', token: token);
      setState(() { _superZones = res['data'] ?? []; _loading = false; });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) showSnack(context, 'Failed: $e', error: true);
    }
  }

  Future<void> _addSuperZone() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => _SimpleDialog(
        title: 'Add Super Zone',
        icon: Icons.layers_outlined,
        child: AppTextField(label: 'Super Zone Name *', controller: ctrl,
            prefixIcon: Icons.layers_outlined),
        onSave: () async {
          if (ctrl.text.isEmpty) return;
          final token = await AuthService.getToken();
          await ApiService.post('/admin/super-zones', {'name': ctrl.text},
              token: token);
          Navigator.pop(ctx);
          _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Header bar
      Container(
        color: kSurface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          const SectionHeader('Election Structure'),
          const Spacer(),
          GestureDetector(
            onTap: _addSuperZone,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: kPrimary, borderRadius: BorderRadius.circular(10)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add, color: Colors.white, size: 16),
                SizedBox(width: 4),
                Text('Super Zone', style: TextStyle(
                    color: Colors.white, fontSize: 12,
                    fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ]),
      ),

      if (_loading)
        const Expanded(child: Center(child: CircularProgressIndicator(color: kPrimary)))
      else if (_superZones.isEmpty)
        Expanded(child: emptyState(
            'No super zones yet.\nTap + Super Zone to start.',
            Icons.layers_outlined))
      else
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            color: kPrimary,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _superZones.length,
              itemBuilder: (ctx, i) => _SuperZoneTile(
                data: _superZones[i], onChanged: _load),
            ),
          ),
        ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Reusable Simple Dialog
// ─────────────────────────────────────────────────────────────────────────────
class _SimpleDialog extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Future<void> Function() onSave;

  const _SimpleDialog({
    required this.title, required this.icon,
    required this.child,  required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          decoration: BoxDecoration(
            color: kBg, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kBorder, width: 1.2),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            dlgHeader(title, icon, context),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                child,
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kSubtle,
                      side: const BorderSide(color: kBorder),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Cancel'),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton(
                    onPressed: onSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Save'),
                  )),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Level tiles — colour-coded by level
// ─────────────────────────────────────────────────────────────────────────────
const _levelColors = [kPrimary, kAccent, kSuccess, kInfo];
const _levelBg     = [kSurface, Color(0xFFFFF8E1), Color(0xFFE8F5E9), Color(0xFFE3F2FD)];

Widget _levelHeader(int level, String label, String sub,
    VoidCallback onExpand, bool open, VoidCallback onDelete) {
  final color = _levelColors[level.clamp(0, 3)];
  final bg    = _levelBg[level.clamp(0, 3)];
  return Container(
    margin: const EdgeInsets.only(bottom: 6),
    decoration: BoxDecoration(
      color: bg, borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withOpacity(0.4)),
    ),
    child: ListTile(
      dense: true,
      leading: Container(
        width: 6, height: 30,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(3)),
      ),
      title: Text(label, style: TextStyle(
          color: kDark, fontWeight: FontWeight.w700, fontSize: 13)),
      subtitle: Text(sub, style: const TextStyle(color: kSubtle, fontSize: 11)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          icon: Icon(open ? Icons.expand_less : Icons.expand_more,
              size: 20, color: color),
          onPressed: onExpand,
          padding: EdgeInsets.zero, constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 18, color: kError),
          onPressed: onDelete,
          padding: EdgeInsets.zero, constraints: const BoxConstraints(),
        ),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  SUPER ZONE
// ─────────────────────────────────────────────────────────────────────────────
class _SuperZoneTile extends StatefulWidget {
  final Map data; final VoidCallback onChanged;
  const _SuperZoneTile({required this.data, required this.onChanged});
  @override State<_SuperZoneTile> createState() => _SuperZoneTileState();
}
class _SuperZoneTileState extends State<_SuperZoneTile> {
  List _zones = []; bool _open = false, _busy = false;

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final t = await AuthService.getToken();
      final r = await ApiService.get(
          '/admin/super-zones/${widget.data['id']}/zones', token: t);
      setState(() { _zones = r['data'] ?? []; _busy = false; });
    } catch (_) { setState(() => _busy = false); }
  }

  Future<void> _add() async {
    final name = TextEditingController(), hq = TextEditingController(),
        on = TextEditingController(), op = TextEditingController(),
        om = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            decoration: BoxDecoration(
              color: kBg, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBorder, width: 1.2),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              dlgHeader('Add Zone', Icons.grid_view_outlined, ctx),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  AppTextField(label: 'Zone Name *', controller: name,
                      prefixIcon: Icons.grid_view_outlined),
                  AppTextField(label: 'HQ Address', controller: hq,
                      prefixIcon: Icons.home_outlined),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Icon(Icons.manage_accounts_outlined,
                          size: 14, color: kSubtle),
                      SizedBox(width: 6),
                      Text('Zonal Officer', style: TextStyle(
                          color: kSubtle, fontSize: 12,
                          fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  AppTextField(label: 'Officer Name', controller: on,
                      prefixIcon: Icons.person_outline),
                  AppTextField(label: 'PNO', controller: op,
                      prefixIcon: Icons.badge_outlined),
                  AppTextField(label: 'Mobile', controller: om,
                      prefixIcon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kSubtle,
                        side: const BorderSide(color: kBorder),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Cancel'),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimary, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        if (name.text.isEmpty) return;
                        final t = await AuthService.getToken();
                        await ApiService.post(
                            '/admin/super-zones/${widget.data['id']}/zones', {
                          'name': name.text, 'hqAddress': hq.text,
                          'officerName': on.text, 'officerPno': op.text,
                          'officerMobile': om.text,
                        }, token: t);
                        Navigator.pop(ctx); _load();
                      },
                      child: const Text('Save'),
                    )),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final t = await AuthService.getToken();
    await ApiService.delete('/admin/super-zones/${widget.data['id']}', token: t);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.transparent,
      child: Column(children: [
        _levelHeader(0,
            '${widget.data['name']}',
            '${widget.data['zoneCount'] ?? 0} zones • ${widget.data['district'] ?? ''}',
            () { setState(() => _open = !_open); if (_open && _zones.isEmpty) _load(); },
            _open, _delete),
        if (_open)
          _busy
              ? const Padding(padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(color: kPrimary))
              : Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Column(children: [
                    ..._zones.map((z) => _ZoneTile(data: z, onChanged: _load)),
                    _AddButton('Add Zone', Icons.grid_view_outlined, _add),
                  ]),
                ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ZONE
// ─────────────────────────────────────────────────────────────────────────────
class _ZoneTile extends StatefulWidget {
  final Map data; final VoidCallback onChanged;
  const _ZoneTile({required this.data, required this.onChanged});
  @override State<_ZoneTile> createState() => _ZoneTileState();
}
class _ZoneTileState extends State<_ZoneTile> {
  List _sectors = []; bool _open = false, _busy = false;

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final t = await AuthService.getToken();
      final r = await ApiService.get(
          '/admin/zones/${widget.data['id']}/sectors', token: t);
      setState(() { _sectors = r['data'] ?? []; _busy = false; });
    } catch (_) { setState(() => _busy = false); }
  }

  Future<void> _delete() async {
    final t = await AuthService.getToken();
    await ApiService.delete('/admin/zones/${widget.data['id']}', token: t);
    widget.onChanged();
  }

  Future<void> _add() async {
    final name = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => _SimpleDialog(
        title: 'Add Sector', icon: Icons.view_module_outlined,
        child: AppTextField(label: 'Sector Name *', controller: name,
            prefixIcon: Icons.view_module_outlined),
        onSave: () async {
          if (name.text.isEmpty) return;
          final t = await AuthService.getToken();
          await ApiService.post('/admin/zones/${widget.data['id']}/sectors',
              {'name': name.text}, token: t);
          Navigator.pop(ctx); _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _levelHeader(1, '${widget.data['name']}',
          '${widget.data['sectorCount'] ?? 0} sectors • ${widget.data['officerName'] ?? ''}',
          () { setState(() => _open = !_open); if (_open && _sectors.isEmpty) _load(); },
          _open, _delete),
      if (_open)
        _busy
            ? const Padding(padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(color: kPrimary))
            : Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Column(children: [
                  ..._sectors.map((s) => _SectorTile(data: s, onChanged: _load)),
                  _AddButton('Add Sector', Icons.view_module_outlined, _add),
                ]),
              ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SECTOR
// ─────────────────────────────────────────────────────────────────────────────
class _SectorTile extends StatefulWidget {
  final Map data; final VoidCallback onChanged;
  const _SectorTile({required this.data, required this.onChanged});
  @override State<_SectorTile> createState() => _SectorTileState();
}
class _SectorTileState extends State<_SectorTile> {
  List _gps = []; bool _open = false, _busy = false;

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final t = await AuthService.getToken();
      final r = await ApiService.get(
          '/admin/sectors/${widget.data['id']}/gram-panchayats', token: t);
      setState(() { _gps = r['data'] ?? []; _busy = false; });
    } catch (_) { setState(() => _busy = false); }
  }

  Future<void> _delete() async {
    final t = await AuthService.getToken();
    await ApiService.delete('/admin/sectors/${widget.data['id']}', token: t);
    widget.onChanged();
  }

  Future<void> _add() async {
    final name = TextEditingController(), addr = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => _SimpleDialog(
        title: 'Add Gram Panchayat', icon: Icons.account_balance_outlined,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppTextField(label: 'GP Name *', controller: name,
              prefixIcon: Icons.account_balance_outlined),
          AppTextField(label: 'Address', controller: addr,
              prefixIcon: Icons.map_outlined),
        ]),
        onSave: () async {
          if (name.text.isEmpty) return;
          final t = await AuthService.getToken();
          await ApiService.post(
              '/admin/sectors/${widget.data['id']}/gram-panchayats',
              {'name': name.text, 'address': addr.text}, token: t);
          Navigator.pop(ctx); _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _levelHeader(2, '${widget.data['name']}',
          '${widget.data['gpCount'] ?? 0} gram panchayats',
          () { setState(() => _open = !_open); if (_open && _gps.isEmpty) _load(); },
          _open, _delete),
      if (_open)
        _busy
            ? const Padding(padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(color: kPrimary))
            : Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Column(children: [
                  ..._gps.map((g) => _GPTile(data: g, onChanged: _load)),
                  _AddButton('Add Gram Panchayat',
                      Icons.account_balance_outlined, _add),
                ]),
              ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  GRAM PANCHAYAT
// ─────────────────────────────────────────────────────────────────────────────
class _GPTile extends StatefulWidget {
  final Map data; final VoidCallback onChanged;
  const _GPTile({required this.data, required this.onChanged});
  @override State<_GPTile> createState() => _GPTileState();
}
class _GPTileState extends State<_GPTile> {
  List _centers = []; bool _open = false, _busy = false;

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final t = await AuthService.getToken();
      final r = await ApiService.get(
          '/admin/gram-panchayats/${widget.data['id']}/centers', token: t);
      setState(() { _centers = r['data'] ?? []; _busy = false; });
    } catch (_) { setState(() => _busy = false); }
  }

  Future<void> _delete() async {
    final t = await AuthService.getToken();
    await ApiService.delete('/admin/gram-panchayats/${widget.data['id']}', token: t);
    widget.onChanged();
  }

  Future<void> _add() async {
    final name = TextEditingController(), addr = TextEditingController(),
        thana = TextEditingController(), bus = TextEditingController();
    String type = 'C';
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            decoration: BoxDecoration(
              color: kBg, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBorder, width: 1.2),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              dlgHeader('Add Election Center',
                  Icons.location_on_outlined, ctx),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  AppTextField(label: 'Center Name *', controller: name,
                      prefixIcon: Icons.location_on_outlined),
                  AppTextField(label: 'Address', controller: addr,
                      prefixIcon: Icons.map_outlined),
                  AppTextField(label: 'Thana', controller: thana,
                      prefixIcon: Icons.local_police_outlined),
                  AppTextField(label: 'Bus No', controller: bus,
                      prefixIcon: Icons.directions_bus_outlined),
                  StatefulBuilder(builder: (ctx, ss) =>
                      DropdownButtonFormField<String>(
                        value: type,
                        dropdownColor: kBg,
                        decoration: InputDecoration(
                          labelText: 'Center Type',
                          labelStyle: const TextStyle(color: kSubtle),
                          prefixIcon: const Icon(Icons.category_outlined,
                              size: 18, color: kPrimary),
                          filled: true, fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: kBorder)),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: kBorder)),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        items: ['A', 'B', 'C'].map((e) =>
                            DropdownMenuItem(value: e,
                                child: Text('Type $e'))).toList(),
                        onChanged: (v) => ss(() => type = v!),
                      )),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kSubtle,
                        side: const BorderSide(color: kBorder),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Cancel'),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimary, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        if (name.text.isEmpty) return;
                        final t = await AuthService.getToken();
                        await ApiService.post(
                            '/admin/gram-panchayats/${widget.data['id']}/centers',
                            {
                              'name': name.text, 'address': addr.text,
                              'thana': thana.text, 'busNo': bus.text,
                              'centerType': type,
                            }, token: t);
                        Navigator.pop(ctx); _load();
                      },
                      child: const Text('Save'),
                    )),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _levelHeader(3, '${widget.data['name']}',
          '${widget.data['centerCount'] ?? 0} centers • ${widget.data['address'] ?? ''}',
          () { setState(() => _open = !_open); if (_open && _centers.isEmpty) _load(); },
          _open, _delete),
      if (_open)
        _busy
            ? const Padding(padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(color: kPrimary))
            : Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Column(children: [
                  ..._centers.map((c) {
                    final t = '${c['centerType'] ?? 'C'}';
                    final tColor = t == 'A' ? kError : t == 'B' ? kAccent : kInfo;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: tColor.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: tColor.withOpacity(0.3)),
                      ),
                      child: Row(children: [
                        TypeBadge(type: t),
                        const SizedBox(width: 10),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${c['name']}', style: const TextStyle(
                                color: kDark, fontWeight: FontWeight.w600,
                                fontSize: 12)),
                            Text('${c['thana']} • Bus: ${c['busNo'] ?? '-'}',
                                style: const TextStyle(
                                    color: kSubtle, fontSize: 11)),
                          ],
                        )),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 16, color: kError),
                          onPressed: () async {
                            final tok = await AuthService.getToken();
                            await ApiService.delete(
                                '/admin/centers/${c['id']}', token: tok);
                            _load();
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ]),
                    );
                  }),
                  _AddButton('Add Center', Icons.add_location_alt_outlined, _add),
                ]),
              ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Add Button
// ─────────────────────────────────────────────────────────────────────────────
class _AddButton extends StatelessWidget {
  final String label; final IconData icon; final VoidCallback onTap;
  const _AddButton(this.label, this.icon, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: kPrimary.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kPrimary.withOpacity(0.25),
              style: BorderStyle.solid),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: kPrimary),
          const SizedBox(width: 6),
          Text('+ $label', style: const TextStyle(
              color: kPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}