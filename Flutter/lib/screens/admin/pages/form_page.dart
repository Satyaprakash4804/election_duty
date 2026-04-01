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
      if (mounted) showSnack(context, 'Failed to load: $e', error: true);
    }
  }

  Future<void> _addSuperZone() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Super Zone'),
        content: AppTextField(label: 'Super Zone Name', controller: ctrl),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.isEmpty) return;
              final token = await AuthService.getToken();
              await ApiService.post('/admin/super-zones', {'name': ctrl.text}, token: token);
              Navigator.pop(ctx);
              _load();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const Text('Election Structure', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            FilledButton.icon(
              onPressed: _addSuperZone,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Super Zone'),
            ),
          ]),
        ),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_superZones.isEmpty)
          const Expanded(child: Center(child: Text('No super zones yet. Add one to start.')))
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _superZones.length,
                itemBuilder: (ctx, i) => _SuperZoneTile(
                  data: _superZones[i],
                  onDeleted: _load,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Super Zone Tile ──────────────────────────────────────────────────────────

class _SuperZoneTile extends StatefulWidget {
  final Map data;
  final VoidCallback onDeleted;
  const _SuperZoneTile({required this.data, required this.onDeleted});
  @override
  State<_SuperZoneTile> createState() => _SuperZoneTileState();
}

class _SuperZoneTileState extends State<_SuperZoneTile> {
  List _zones = [];
  bool _open = false, _loading = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.get('/admin/super-zones/${widget.data['id']}/zones', token: token);
      setState(() { _zones = res['data'] ?? []; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _addZone() async {
    final name = TextEditingController(), hq = TextEditingController(),
        oName = TextEditingController(), oPno = TextEditingController(),
        oMobile = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Zone'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppTextField(label: 'Zone Name *', controller: name),
          AppTextField(label: 'HQ Address', controller: hq),
          const Divider(),
          const Text('Zonal Officer', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          AppTextField(label: 'Officer Name', controller: oName),
          AppTextField(label: 'PNO', controller: oPno),
          AppTextField(label: 'Mobile', controller: oMobile),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (name.text.isEmpty) return;
              final token = await AuthService.getToken();
              await ApiService.post('/admin/super-zones/${widget.data['id']}/zones', {
                'name': name.text, 'hqAddress': hq.text,
                'officerName': oName.text, 'officerPno': oPno.text, 'officerMobile': oMobile.text,
              }, token: token);
              Navigator.pop(ctx);
              _load();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Super Zone?'),
        content: const Text('This will delete all nested zones, sectors, GPs and centers.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      final token = await AuthService.getToken();
      await ApiService.delete('/admin/super-zones/${widget.data['id']}', token: token);
      widget.onDeleted();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(children: [
        ListTile(
          leading: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: Colors.blue.shade700, borderRadius: BorderRadius.circular(8)),
            child: Center(child: Text('${widget.data['id']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          ),
          title: Text(widget.data['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${widget.data['zoneCount'] ?? 0} zones • ${widget.data['district'] ?? ''}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: Icon(_open ? Icons.expand_less : Icons.expand_more), onPressed: () {
              setState(() => _open = !_open);
              if (_open && _zones.isEmpty) _load();
            }),
            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: _delete),
          ]),
        ),
        if (_open) ...[
          const Divider(height: 1),
          _loading
              ? const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(children: [
                    ..._zones.map((z) => _ZoneTile(data: z, onDeleted: _load)),
                    TextButton.icon(onPressed: _addZone, icon: const Icon(Icons.add, size: 16), label: const Text('Add Zone')),
                  ]),
                ),
        ],
      ]),
    );
  }
}

// ─── Zone Tile ────────────────────────────────────────────────────────────────

class _ZoneTile extends StatefulWidget {
  final Map data;
  final VoidCallback onDeleted;
  const _ZoneTile({required this.data, required this.onDeleted});
  @override
  State<_ZoneTile> createState() => _ZoneTileState();
}

class _ZoneTileState extends State<_ZoneTile> {
  List _sectors = [];
  bool _open = false, _loading = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.get('/admin/zones/${widget.data['id']}/sectors', token: token);
      setState(() { _sectors = res['data'] ?? []; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _addSector() async {
    final name = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Sector'),
        content: AppTextField(label: 'Sector Name *', controller: name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (name.text.isEmpty) return;
              final token = await AuthService.getToken();
              await ApiService.post('/admin/zones/${widget.data['id']}/sectors', {'name': name.text}, token: token);
              Navigator.pop(ctx);
              _load();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: Colors.blue.shade50,
      child: Column(children: [
        ListTile(
          dense: true,
          leading: const Icon(Icons.circle, size: 10, color: Colors.blue),
          title: Text(widget.data['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${widget.data['sectorCount'] ?? 0} sectors • ${widget.data['officerName'] ?? ''}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: Icon(_open ? Icons.expand_less : Icons.expand_more, size: 20), onPressed: () {
              setState(() => _open = !_open);
              if (_open && _sectors.isEmpty) _load();
            }),
            IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), onPressed: () async {
              final token = await AuthService.getToken();
              await ApiService.delete('/admin/zones/${widget.data['id']}', token: token);
              widget.onDeleted();
            }),
          ]),
        ),
        if (_open)
          _loading
              ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Column(children: [
                    ..._sectors.map((s) => _SectorTile(data: s, onDeleted: _load)),
                    TextButton.icon(onPressed: _addSector, icon: const Icon(Icons.add, size: 16), label: const Text('Add Sector')),
                  ]),
                ),
      ]),
    );
  }
}

// ─── Sector Tile ──────────────────────────────────────────────────────────────

class _SectorTile extends StatefulWidget {
  final Map data;
  final VoidCallback onDeleted;
  const _SectorTile({required this.data, required this.onDeleted});
  @override
  State<_SectorTile> createState() => _SectorTileState();
}

class _SectorTileState extends State<_SectorTile> {
  List _gps = [];
  bool _open = false, _loading = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.get('/admin/sectors/${widget.data['id']}/gram-panchayats', token: token);
      setState(() { _gps = res['data'] ?? []; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _addGP() async {
    final name = TextEditingController(), addr = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Gram Panchayat'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          AppTextField(label: 'GP Name *', controller: name),
          AppTextField(label: 'Address', controller: addr),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (name.text.isEmpty) return;
              final token = await AuthService.getToken();
              await ApiService.post('/admin/sectors/${widget.data['id']}/gram-panchayats',
                  {'name': name.text, 'address': addr.text}, token: token);
              Navigator.pop(ctx);
              _load();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      color: Colors.green.shade50,
      child: Column(children: [
        ListTile(
          dense: true,
          leading: const Icon(Icons.circle, size: 8, color: Colors.green),
          title: Text(widget.data['name'] ?? ''),
          subtitle: Text('${widget.data['gpCount'] ?? 0} GPs'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18), onPressed: () {
              setState(() => _open = !_open);
              if (_open && _gps.isEmpty) _load();
            }),
            IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), onPressed: () async {
              final token = await AuthService.getToken();
              await ApiService.delete('/admin/sectors/${widget.data['id']}', token: token);
              widget.onDeleted();
            }),
          ]),
        ),
        if (_open)
          _loading
              ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Column(children: [
                    ..._gps.map((g) => _GPTile(data: g, onDeleted: _load)),
                    TextButton.icon(onPressed: _addGP, icon: const Icon(Icons.add, size: 16), label: const Text('Add GP')),
                  ]),
                ),
      ]),
    );
  }
}

// ─── GP Tile ──────────────────────────────────────────────────────────────────

class _GPTile extends StatefulWidget {
  final Map data;
  final VoidCallback onDeleted;
  const _GPTile({required this.data, required this.onDeleted});
  @override
  State<_GPTile> createState() => _GPTileState();
}

class _GPTileState extends State<_GPTile> {
  List _centers = [];
  bool _open = false, _loading = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.get('/admin/gram-panchayats/${widget.data['id']}/centers', token: token);
      setState(() { _centers = res['data'] ?? []; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _addCenter() async {
    final name = TextEditingController(), addr = TextEditingController(),
        thana = TextEditingController(), bus = TextEditingController();
    String type = 'C';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: const Text('Add Election Center'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            AppTextField(label: 'Center Name *', controller: name),
            AppTextField(label: 'Address', controller: addr),
            AppTextField(label: 'Thana', controller: thana),
            AppTextField(label: 'Bus No', controller: bus),
            DropdownButtonFormField<String>(
              value: type,
              decoration: const InputDecoration(labelText: 'Center Type', border: OutlineInputBorder(),
                  isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              items: ['A', 'B', 'C'].map((e) => DropdownMenuItem(value: e, child: Text('Type $e'))).toList(),
              onChanged: (v) => ss(() => type = v!),
            ),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (name.text.isEmpty) return;
                final token = await AuthService.getToken();
                await ApiService.post('/admin/gram-panchayats/${widget.data['id']}/centers', {
                  'name': name.text, 'address': addr.text,
                  'thana': thana.text, 'busNo': bus.text, 'centerType': type,
                }, token: token);
                Navigator.pop(ctx);
                _load();
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      color: Colors.orange.shade50,
      child: Column(children: [
        ListTile(
          dense: true,
          leading: const Icon(Icons.location_on, size: 16, color: Colors.orange),
          title: Text(widget.data['name'] ?? ''),
          subtitle: Text('${widget.data['centerCount'] ?? 0} centers'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18), onPressed: () {
              setState(() => _open = !_open);
              if (_open && _centers.isEmpty) _load();
            }),
            IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), onPressed: () async {
              final token = await AuthService.getToken();
              await ApiService.delete('/admin/gram-panchayats/${widget.data['id']}', token: token);
              widget.onDeleted();
            }),
          ]),
        ),
        if (_open)
          _loading
              ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Column(children: [
                    ..._centers.map((c) {
                      final t = '${c['centerType'] ?? 'C'}';
                      final tColor = t == 'A' ? Colors.red : t == 'B' ? Colors.orange : Colors.blue;
                      return ListTile(
                        dense: true,
                        leading: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: tColor.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                          child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: tColor)),
                        ),
                        title: Text('${c['name']}', style: const TextStyle(fontSize: 13)),
                        subtitle: Text('${c['thana']} • Bus: ${c['busNo'] ?? '-'}', style: const TextStyle(fontSize: 11)),
                        trailing: IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red), onPressed: () async {
                          final token = await AuthService.getToken();
                          await ApiService.delete('/admin/centers/${c['id']}', token: token);
                          _load();
                        }),
                      );
                    }),
                    TextButton.icon(onPressed: _addCenter, icon: const Icon(Icons.add, size: 16), label: const Text('Add Center')),
                  ]),
                ),
      ]),
    );
  }
}