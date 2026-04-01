import 'package:flutter/material.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';

class BoothPage extends StatefulWidget {
  const BoothPage({super.key});
  @override
  State<BoothPage> createState() => _BoothPageState();
}

class _BoothPageState extends State<BoothPage> {
  List _centers = [];
  List _filtered = [];
  List _staff = [];
  bool _loading = true;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(_filter);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final c = await ApiService.get('/admin/centers/all', token: token);
      final s = await ApiService.get('/admin/staff', token: token);
      setState(() {
        _centers = c['data'] ?? [];
        _staff = (s['data'] ?? []).where((s) => s['isAssigned'] != true).toList();
        _filtered = _centers;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) showSnack(context, 'Failed to load: $e', error: true);
    }
  }

  void _filter() {
    final q = _search.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _centers
          : _centers.where((c) =>
              '${c['name']}'.toLowerCase().contains(q) ||
              '${c['thana']}'.toLowerCase().contains(q) ||
              '${c['gpName']}'.toLowerCase().contains(q) ||
              '${c['sectorName']}'.toLowerCase().contains(q) ||
              '${c['zoneName']}'.toLowerCase().contains(q) ||
              '${c['superZoneName']}'.toLowerCase().contains(q)).toList();
    });
  }

  void _showAssignDialog(Map center) {
    Map? selectedStaff;
    final busCtrl = TextEditingController(text: '${center['busNo'] ?? ''}');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: Text('Assign Staff\n${center['name']}', style: const TextStyle(fontSize: 14)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<Map>(
              decoration: const InputDecoration(labelText: 'Select Staff', border: OutlineInputBorder(), isDense: true),
              value: selectedStaff,
              isExpanded: true,
              items: _staff.map((s) => DropdownMenuItem<Map>(
                value: s,
                child: Text('${s['name']} (${s['pno']})', overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (v) => ss(() => selectedStaff = v),
            ),
            const SizedBox(height: 12),
            AppTextField(label: 'Bus Number', controller: busCtrl),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: selectedStaff == null ? null : () async {
                final token = await AuthService.getToken();
                await ApiService.post('/admin/duties', {
                  'staffId': selectedStaff!['id'],
                  'centerId': center['id'],
                  'busNo': busCtrl.text,
                }, token: token);
                Navigator.pop(ctx);
                _load();
                if (mounted) showSnack(context, 'Duty assigned');
              },
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDutiesDialog(Map center) async {
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.get('/admin/duties?center_id=${center['id']}', token: token);
      final duties = res['data'] ?? [];

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${center['name']}', style: const TextStyle(fontSize: 15)),
            Text('Type ${center['centerType']} • ${center['thana']}',
                style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.normal)),
          ]),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: duties.isEmpty
                ? const Center(child: Text('No staff assigned yet'))
                : ListView.builder(
                    itemCount: duties.length,
                    itemBuilder: (_, i) {
                      final d = duties[i];
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade100,
                          radius: 16,
                          child: Text('${i + 1}', style: const TextStyle(fontSize: 11)),
                        ),
                        title: Text('${d['name']}'),
                        subtitle: Text('PNO: ${d['pno']} • ${d['mobile']}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                          onPressed: () async {
                            final t = await AuthService.getToken();
                            await ApiService.delete('/admin/duties/${d['id']}', token: t);
                            Navigator.pop(ctx);
                            _load();
                            if (mounted) showSnack(context, 'Duty removed');
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            FilledButton.icon(
              onPressed: () { Navigator.pop(ctx); _showAssignDialog(center); },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Staff'),
            ),
          ],
        ),
      );
    } catch (e) {
      showSnack(context, 'Error: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _search,
          decoration: const InputDecoration(
            hintText: 'Search by name, thana, GP, sector, zone...',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ),

      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(children: [
          Text('${_filtered.length} centers', style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const Spacer(),
          Text('Unassigned staff: ${_staff.length}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ]),
      ),

      if (_loading)
        const Expanded(child: Center(child: CircularProgressIndicator()))
      else
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final c = _filtered[i];
                final type = '${c['centerType'] ?? 'C'}';
                final tColor = type == 'A' ? Colors.red : type == 'B' ? Colors.orange : Colors.blue;
                final count = c['dutyCount'] ?? 0;

                return ListTile(
                  leading: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: tColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: tColor.withOpacity(0.4)),
                    ),
                    child: Center(child: Text(type, style: TextStyle(fontWeight: FontWeight.bold, color: tColor, fontSize: 16))),
                  ),
                  title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${c['thana']} • ${c['gpName']}'),
                    Text('${c['sectorName']} • ${c['zoneName']}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ]),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: count > 0 ? Colors.green.shade50 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: count > 0 ? Colors.green.shade300 : Colors.grey.shade300),
                    ),
                    child: Text('$count staff',
                        style: TextStyle(fontSize: 11, color: count > 0 ? Colors.green.shade700 : Colors.grey)),
                  ),
                  isThreeLine: true,
                  onTap: () => _showDutiesDialog(c),
                );
              },
            ),
          ),
        ),
    ]);
  }
}