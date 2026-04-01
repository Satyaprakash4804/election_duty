import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';

class StaffPage extends StatefulWidget {
  const StaffPage({super.key});
  @override
  State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage> {
  List _staff = [];
  List _filtered = [];
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
      final res = await ApiService.get('/admin/staff', token: token);
      setState(() {
        _staff = res['data'] ?? [];
        _filtered = _staff;
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
          ? _staff
          : _staff.where((s) =>
              '${s['name']}'.toLowerCase().contains(q) ||
              '${s['pno']}'.toLowerCase().contains(q) ||
              '${s['mobile']}'.toLowerCase().contains(q) ||
              '${s['thana']}'.toLowerCase().contains(q)).toList();
    });
  }

  void _showAddDialog() {
    final pno = TextEditingController(), name = TextEditingController(),
        mobile = TextEditingController(), thana = TextEditingController(),
        district = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Staff'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AppTextField(label: 'PNO *', controller: pno),
            AppTextField(label: 'Name *', controller: name),
            AppTextField(label: 'Mobile', controller: mobile, keyboardType: TextInputType.phone),
            AppTextField(label: 'Thana', controller: thana),
            AppTextField(label: 'District', controller: district),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (pno.text.isEmpty || name.text.isEmpty) {
                showSnack(ctx, 'PNO and Name required', error: true);
                return;
              }
              try {
                final token = await AuthService.getToken();
                await ApiService.post('/admin/staff', {
                  'pno': pno.text, 'name': name.text,
                  'mobile': mobile.text, 'thana': thana.text, 'district': district.text,
                }, token: token);
                Navigator.pop(ctx);
                _load();
                if (mounted) showSnack(context, 'Staff added successfully');
              } catch (e) {
                showSnack(ctx, 'Error: $e', error: true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['xlsx'], withData: true,
    );
    if (result == null) return;

    final bytes = result.files.single.bytes!;
    final excel = Excel.decodeBytes(bytes);
    final List items = [];

    for (final table in excel.tables.keys) {
      final sheet = excel.tables[table]!;
      for (int i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (row.isEmpty) continue;
        items.add({
          'pno':      row[0]?.value?.toString() ?? '',
          'name':     row[1]?.value?.toString() ?? '',
          'mobile':   row[2]?.value?.toString() ?? '',
          'thana':    row[3]?.value?.toString() ?? '',
          'district': row[4]?.value?.toString() ?? '',
        });
      }
    }

    if (items.isEmpty) {
      if (mounted) showSnack(context, 'No data found in Excel', error: true);
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Upload ${items.length} Staff?'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) => ListTile(
              dense: true,
              title: Text('${items[i]['name']}'),
              subtitle: Text('PNO: ${items[i]['pno']} | ${items[i]['thana']}'),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final token = await AuthService.getToken();
                final res = await ApiService.post('/admin/staff/bulk', {'staff': items}, token: token);
                _load();
                final added = res['data']['added'];
                final skipped = (res['data']['skipped'] as List).length;
                if (mounted) showSnack(context, '$added added, $skipped skipped');
              } catch (e) {
                if (mounted) showSnack(context, 'Upload failed: $e', error: true);
              }
            },
            child: const Text('Upload'),
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
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    hintText: 'Search by name, PNO, mobile, thana...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _showAddDialog,
                icon: const Icon(Icons.person_add),
                tooltip: 'Add Staff',
              ),
              const SizedBox(width: 4),
              IconButton.outlined(
                onPressed: _pickExcel,
                icon: const Icon(Icons.upload_file),
                tooltip: 'Upload Excel (PNO, Name, Mobile, Thana, District)',
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Text('${_filtered.length} shown', style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const Spacer(),
            Text('Total: ${_staff.length}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ]),
        ),

        const SizedBox(height: 4),

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
                  final s = _filtered[i];
                  final assigned = s['isAssigned'] == true;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: assigned ? Colors.green.shade100 : Colors.grey.shade200,
                      child: Text(
                        (s['name'] as String? ?? 'S')[0].toUpperCase(),
                        style: TextStyle(
                          color: assigned ? Colors.green.shade800 : Colors.grey.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text('${s['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('PNO: ${s['pno']} • ${s['thana']} • ${s['mobile']}'),
                    trailing: assigned
                        ? Chip(
                            label: Text('${s['centerName'] ?? 'Assigned'}',
                                style: const TextStyle(fontSize: 11)),
                            backgroundColor: Colors.green.shade50,
                            side: BorderSide(color: Colors.green.shade300),
                            visualDensity: VisualDensity.compact,
                          )
                        : const Chip(
                            label: Text('Unassigned', style: TextStyle(fontSize: 11)),
                            visualDensity: VisualDensity.compact,
                          ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}