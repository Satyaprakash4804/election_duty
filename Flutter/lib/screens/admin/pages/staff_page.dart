import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as ex;
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';

class StaffPage extends StatefulWidget {
  const StaffPage({super.key});
  @override
  State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage>
    with SingleTickerProviderStateMixin {

  late final TabController _tabs;
  List<Map<String, dynamic>> _allStaff = [];
  List<Map<String, dynamic>> _assigned = [];
  List<Map<String, dynamic>> _reserve  = [];
  bool   _loading = true;
  String _q       = '';
  final  _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)
      ..addListener(() => setState(() {}));
    _searchCtrl.addListener(() => _applyFilter(_searchCtrl.text));
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── LOAD ──────────────────────────────────────────────────────────────────
  Future<void> _load() async {
  if (!mounted) return;

  setState(() => _loading = true);

  try {
    // 🔹 1. GET TOKEN
    final token = await AuthService.getToken();
    print("TOKEN: $token");

    if (token == null || token.isEmpty) {
      throw Exception("Session expired. Please login again.");
    }

    // 🔹 2. API CALL
    final res = await ApiService.get('/admin/staff', token: token);
    print("API RESPONSE: $res");

    // 🔹 3. VALIDATE RESPONSE
    if (res == null || res['data'] == null) {
      throw Exception(res['message'] ?? "Invalid response from server");
    }

    if (res['data'] is! List) {
      throw Exception("Unexpected data format");
    }

    // 🔹 4. PARSE DATA
    final List<Map<String, dynamic>> raw =
        (res['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

    // 🔹 5. UPDATE UI
    if (!mounted) return;

    setState(() {
      _allStaff = raw;
      _loading = false;
    });

    _applyFilter(_q);

  } catch (e) {
    print("LOAD ERROR: $e");

    if (!mounted) return;

    setState(() => _loading = false);

    showSnack(
      context,
      _msg(e).contains("401")
          ? "Session expired. Please login again."
          : "Load failed: ${_msg(e)}",
      error: true,
    );
  }
}

  void _applyFilter(String raw) {
    setState(() {
      _q = raw.toLowerCase().trim();
      final src = _q.isEmpty
          ? _allStaff
          : _allStaff.where((s) =>
              _s(s['name']).contains(_q)   ||
              _s(s['pno']).contains(_q)    ||
              _s(s['mobile']).contains(_q) ||
              _s(s['thana']).contains(_q)).toList();
      _assigned = src.where((s) => _isAssigned(s)).toList();
      _reserve  = src.where((s) => !_isAssigned(s)).toList();
    });
  }

  bool _isAssigned(Map s) {
    final v = s['isAssigned'];
  
    return v == true ||
           v == 1 ||
           v == "1" ||
           v == "true" ||
           (s['centerName'] ?? '').toString().isNotEmpty;
  }
  String _s(dynamic v) => (v ?? '').toString().toLowerCase();
  
  String _v(dynamic v) => (v ?? '').toString().trim();  
  // ── Remove duty (Assigned → Reserve) ──────────────────────────────────────
  Future<void> _removeFromAssigned(Map<String, dynamic> staff) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: kError, width: 1.5),
        ),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: kError),
          SizedBox(width: 8),
          Text('Remove Duty?',
              style: TextStyle(
                  color: kError, fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(color: kDark, fontSize: 13, height: 1.6),
            children: [
              const TextSpan(text: 'Move '),
              TextSpan(text: _v(staff['name']),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const TextSpan(text: ' from\n'),
              TextSpan(text: _v(staff['centerName']),
                  style: const TextStyle(
                      color: kInfo, fontWeight: FontWeight.w700)),
              const TextSpan(text: '\nto Reserve?'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: kSubtle))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: kError,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            child: const Text('Move to Reserve'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final token = await AuthService.getToken();
      // Get duty id for this staff member
      final res = await ApiService.get(
          '/admin/duties?staff_id=${staff['id']}', token: token);
      final duties = res['data'] as List? ?? [];
      if (duties.isNotEmpty) {
        await ApiService.delete(
            '/admin/duties/${duties.first['id']}', token: token);
        showSnack(context, '${_v(staff['name'])} moved to reserve');
      } else {
        showSnack(context, 'No duty found for this staff', error: true);
      }
      _load();
    } catch (e) {
      showSnack(context, 'Error: ${_msg(e)}', error: true);
    }
  }

  // ── Assign duty from Reserve ───────────────────────────────────────────────
  Future<void> _assignFromReserve(Map<String, dynamic> staff) async {
    List centers = [];
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get('/admin/centers/all', token: token);
      centers = res['data'] as List? ?? [];
    } catch (e) {
      if (mounted) showSnack(context, 'Could not load centers: ${_msg(e)}', error: true);
      return;
    }
    if (!mounted) return;

    Map?   selectedCenter;
    final  busCtrl = TextEditingController();
    bool   saving  = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: StatefulBuilder(
            builder: (ctx, ss) => Container(
              decoration: BoxDecoration(
                color: kBg, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder, width: 1.2),
                boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.18),
                    blurRadius: 24, offset: const Offset(0, 8))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                dlgHeader('Assign Duty', Icons.how_to_vote_outlined, ctx),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [

                    // Staff info banner
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kBorder.withOpacity(0.5)),
                      ),
                      child: Row(children: [
                        _avatarWidget(_v(staff['name']), kAccent),
                        const SizedBox(width: 10),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_v(staff['name']), style: const TextStyle(
                                color: kDark, fontWeight: FontWeight.w700,
                                fontSize: 13)),
                            Text('PNO: ${_v(staff['pno'])} • ${_v(staff['thana'])}',
                                style: const TextStyle(
                                    color: kSubtle, fontSize: 11)),
                          ],
                        )),
                      ]),
                    ),
                    const SizedBox(height: 14),

                    // Center dropdown
                    centers.isEmpty
                        ? Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: kError.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: kError.withOpacity(0.3)),
                            ),
                            child: const Row(children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: kError, size: 16),
                              SizedBox(width: 8),
                              Text('No centers found. Add centers first.',
                                  style: TextStyle(color: kError,
                                      fontSize: 12)),
                            ]),
                          )
                        : DropdownButtonFormField<Map>(
                            value: selectedCenter,
                            isExpanded: true,
                            dropdownColor: kBg,
                            decoration: _dlgDeco('Select Election Center',
                                Icons.location_on_outlined),
                            items: centers.map((c) => DropdownMenuItem<Map>(
                              value: c,
                              child: Row(children: [
                                _typeDot('${c['centerType'] ?? 'C'}'),
                                const SizedBox(width: 8),
                                Expanded(child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Text('${c['name']}',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: kDark, fontSize: 13,
                                            fontWeight: FontWeight.w600)),
                                    Text(
                                        '${c['thana']} • ${c['gpName']}',
                                        style: const TextStyle(
                                            color: kSubtle, fontSize: 10)),
                                  ],
                                )),
                              ]),
                            )).toList(),
                            onChanged: (v) => ss(() => selectedCenter = v),
                          ),
                    const SizedBox(height: 12),

                    // Bus number
                    TextField(
                      controller: busCtrl,
                      style: const TextStyle(color: kDark, fontSize: 13),
                      decoration: _dlgDeco('Bus Number (optional)',
                          Icons.directions_bus_outlined),
                    ),
                    const SizedBox(height: 16),

                    Row(children: [
                      Expanded(child: OutlinedButton(
                        onPressed: saving ? null : () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kSubtle,
                          side: const BorderSide(color: kBorder),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Cancel'),
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: (selectedCenter == null ||
                                  centers.isEmpty)
                              ? kSubtle
                              : kPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: (selectedCenter == null ||
                                centers.isEmpty || saving)
                            ? null
                            : () async {
                                ss(() => saving = true);
                                try {
                                  final token = await AuthService.getToken();
                                  await ApiService.post('/admin/duties', {
                                    'staffId':  staff['id'],
                                    'centerId': selectedCenter!['id'],
                                    'busNo':    busCtrl.text.trim(),
                                  }, token: token);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (mounted) {
                                    showSnack(context,
                                        '${_v(staff['name'])} assigned to '
                                        '${_v(selectedCenter!['name'])}');
                                  }
                                  _load();
                                } catch (e) {
                                  ss(() => saving = false);
                                  if (ctx.mounted) {
                                    showSnack(ctx, _msg(e), error: true);
                                  }
                                }
                              },
                        child: saving
                            ? const SizedBox(width: 18, height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text('Assign'),
                      )),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ── Add Staff Dialog ────────────────────────────────────────────────────────
  void _showAddDialog() {
    final pno      = TextEditingController();
    final name     = TextEditingController();
    final mobile   = TextEditingController();
    final thana    = TextEditingController();
    final district = TextEditingController();
    final formKey  = GlobalKey<FormState>();
    bool saving    = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Container(
              decoration: BoxDecoration(
                color: kBg, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder, width: 1.2),
                boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.18),
                    blurRadius: 24, offset: const Offset(0, 8))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                dlgHeader('Add Staff Member',
                    Icons.person_add_outlined, ctx),
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Form(key: formKey, child: Column(children: [
                    AppTextField(
                      label: 'PNO *', controller: pno,
                      prefixIcon: Icons.badge_outlined,
                      validator: (v) => (v?.trim().isEmpty ?? true)
                          ? 'PNO is required' : null,
                    ),
                    AppTextField(
                      label: 'Full Name *', controller: name,
                      prefixIcon: Icons.person_outline,
                      validator: (v) => (v?.trim().isEmpty ?? true)
                          ? 'Name is required' : null,
                    ),
                    AppTextField(
                      label: 'Mobile', controller: mobile,
                      prefixIcon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                    AppTextField(
                      label: 'Thana', controller: thana,
                      prefixIcon: Icons.local_police_outlined,
                    ),
                    AppTextField(
                      label: 'District', controller: district,
                      prefixIcon: Icons.location_city_outlined,
                    ),
                  ])),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(children: [
                    Expanded(child: OutlinedButton(
                      onPressed: saving ? null : () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kSubtle,
                        side: const BorderSide(color: kBorder),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Cancel'),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: saving ? null : () async {
                        if (!formKey.currentState!.validate()) return;
                        ss(() => saving = true);
                        try {
                          final token = await AuthService.getToken();
                          await ApiService.post('/admin/staff', {
                            'pno':      pno.text.trim(),
                            'name':     name.text.trim(),
                            'mobile':   mobile.text.trim(),
                            'thana':    thana.text.trim(),
                            'district': district.text.trim(),
                          }, token: token);
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _load();
                          if (mounted) {
                            showSnack(context, '${name.text} added');
                          }
                        } catch (e) {
                          ss(() => saving = false);
                          if (ctx.mounted) showSnack(ctx, _msg(e), error: true);
                        }
                      },
                      child: saving
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('Save Staff'),
                    )),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ── Excel Upload ─────────────────────────────────────────────────────────────
  Future<void> _pickExcel() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );
    } catch (e) {
      if (mounted) showSnack(context, 'File picker: ${_msg(e)}', error: true);
      return;
    }
    if (result == null || result.files.isEmpty) return;

    final bytes = result.files.single.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) showSnack(context, 'Could not read file', error: true);
      return;
    }

    ex.Excel excel;
    try {
      excel = ex.Excel.decodeBytes(bytes);
    } catch (e) {
      if (mounted) showSnack(context, 'Cannot open file: ${_msg(e)}', error: true);
      return;
    }

    if (excel.tables.isEmpty) {
      if (mounted) showSnack(context, 'No sheets found', error: true);
      return;
    }

    // Sheet selection if multiple
    if (!mounted) return;
    final sheetNames = excel.tables.keys.toList();
    String? chosen;

    if (sheetNames.length == 1) {
      chosen = sheetNames.first;
    } else {
      chosen = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kBg,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: kBorder)),
          title: const Text('Select Sheet',
              style: TextStyle(color: kDark, fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: sheetNames.map((n) => ListTile(
              title: Text(n, style: const TextStyle(color: kDark)),
              trailing: const Icon(Icons.chevron_right, color: kSubtle),
              onTap: () => Navigator.pop(ctx, n),
            )).toList(),
          ),
        ),
      );
    }
    if (chosen == null || !mounted) return;

    final sheet = excel.tables[chosen]!;
    if (sheet.rows.isEmpty) {
      if (mounted) showSnack(context, 'Sheet "$chosen" is empty', error: true);
      return;
    }

    // ── Smart column detection ────────────────────────────────────────────────
    // Read all rows as raw strings for header scanning
    List<String> _rowVals(int rowIdx) {
      if (rowIdx >= sheet.rows.length) return [];
      return sheet.rows[rowIdx].map((c) =>
          (c?.value?.toString() ?? '').trim()).toList();
    }

    String _cellStr(int rowIdx, int colIdx) {
      if (rowIdx >= sheet.rows.length) return '';
      final row = sheet.rows[rowIdx];
      if (colIdx >= row.length) return '';
      return (row[colIdx]?.value?.toString() ?? '').trim();
    }

    // Scan first 3 rows for a header
    int headerRowIdx = -1;
    int? idxPno, idxName, idxMobile, idxThana, idxDistrict;

    for (int ri = 0; ri < sheet.rows.length.clamp(0, 3); ri++) {
      final vals = _rowVals(ri).map((v) => v.toLowerCase()).toList();
      int? p, n, m, t, d;
      for (int ci = 0; ci < vals.length; ci++) {
        final h = vals[ci];
        if (p == null && (h.contains('pno') || h.contains('p.no') ||
            h == 'no' || h.contains('police no') || h.contains('सं') ||
            h.contains('क्र'))) p = ci;
        if (n == null && (h.contains('name') || h.contains('नाम') ||
            h.contains('nam'))) n = ci;
        if (m == null && (h.contains('mobile') || h.contains('mob') ||
            h.contains('phone') || h.contains('contact') ||
            h.contains('मोबाइल'))) m = ci;
        if (t == null && (h.contains('thana') || h.contains('थाना') ||
            h.contains('police station') || h == 'ps' ||
            h.contains('ps '))) t = ci;
        if (d == null && (h.contains('district') || h.contains('dist') ||
            h.contains('जिला') || h.contains('jila'))) d = ci;
      }
      if (p != null || n != null) {
        headerRowIdx = ri;
        idxPno = p; idxName = n; idxMobile = m;
        idxThana = t; idxDistrict = d;
        break;
      }
    }

    // Fall back to positional if no header found
    final dataStart = headerRowIdx >= 0 ? headerRowIdx + 1 : 0;
    idxPno      ??= 0;
    idxName     ??= 1;
    idxMobile   ??= 2;
    idxThana    ??= 3;
    idxDistrict ??= 4;

    // Build detected column map labels for display
    final headerRow = headerRowIdx >= 0 ? _rowVals(headerRowIdx) : [];
    String _colLabel(int idx) => (idx < headerRow.length && headerRow[idx].isNotEmpty)
        ? headerRow[idx] : 'Col ${idx + 1}';

    final colMap = {
      'PNO':      _colLabel(idxPno!),
      'Name':     _colLabel(idxName!),
      'Mobile':   _colLabel(idxMobile!),
      'Thana':    _colLabel(idxThana!),
      'District': _colLabel(idxDistrict!),
    };

    // Parse data rows
    final List<Map<String, dynamic>> preview = [];
    for (int r = dataStart; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      if (row.every((c) =>
          c == null || (c.value?.toString().trim().isEmpty ?? true))) continue;

      final pno  = _cellStr(r, idxPno!);
      final name = _cellStr(r, idxName!);
      if (pno.isEmpty && name.isEmpty) continue;

      preview.add({
        'pno':      pno,
        'name':     name,
        'mobile':   _cellStr(r, idxMobile!),
        'thana':    _cellStr(r, idxThana!),
        'district': _cellStr(r, idxDistrict!),
        '_row':     r + 1,
      });
    }

    if (preview.isEmpty) {
      if (mounted) showSnack(context,
          'No data rows found. Check columns.', error: true);
      return;
    }

    if (!mounted) return;
    _showExcelPreview(preview, colMap);
  }

  // ── Excel Preview Dialog ────────────────────────────────────────────────────
  void _showExcelPreview(
      List<Map<String, dynamic>> initialItems,
      Map<String, String> colMap) {
    final rows     = List<Map<String, dynamic>>.from(initialItems);
    bool uploading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) {
          final validCount = rows.where(_isValidRow).length;
          return Dialog(
            backgroundColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                decoration: BoxDecoration(
                  color: kBg, borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kBorder, width: 1.2),
                  boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.15),
                      blurRadius: 20, offset: const Offset(0, 8))],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [

                  // Header
                  dlgHeader('Preview — ${rows.length} rows',
                      Icons.upload_file_outlined, ctx),

                  // Detected column mapping
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    color: kInfo.withOpacity(0.07),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Detected columns:',
                            style: TextStyle(
                                color: kInfo, fontSize: 10,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Wrap(spacing: 8, runSpacing: 4,
                            children: colMap.entries.map((e) =>
                                _mapChip(e.key, e.value)).toList()),
                      ],
                    ),
                  ),

                  // Stats + hint
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
                    child: Row(children: [
                      _statPill('$validCount Valid', kSuccess),
                      const SizedBox(width: 6),
                      _statPill(
                          '${rows.where((r) => !_isValidRow(r)).length}'
                          ' Errors', kError),
                      const Spacer(),
                      const Icon(Icons.touch_app_outlined,
                          size: 11, color: kSubtle),
                      const SizedBox(width: 3),
                      const Text('Tap × to remove',
                          style: TextStyle(color: kSubtle, fontSize: 10)),
                    ]),
                  ),

                  // Preview list
                  ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight:
                            MediaQuery.of(ctx).size.height * 0.42),
                    child: rows.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('No rows left',
                                  style: TextStyle(
                                      color: kSubtle, fontSize: 13)),
                            ))
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            itemCount: rows.length,
                            itemBuilder: (_, i) {
                              final r     = rows[i];
                              final valid = _isValidRow(r);
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                decoration: BoxDecoration(
                                  color: valid ? Colors.white
                                      : kError.withOpacity(0.04),
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: valid
                                        ? kBorder.withOpacity(0.4)
                                        : kError.withOpacity(0.35),
                                  ),
                                ),
                                child: Row(children: [
                                  // Row number
                                  Container(
                                    width: 36,
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    decoration: BoxDecoration(
                                      color: valid
                                          ? kSurface.withOpacity(0.6)
                                          : kError.withOpacity(0.06),
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(9),
                                        bottomLeft: Radius.circular(9),
                                      ),
                                    ),
                                    child: Text('${r['_row']}',
                                        style: TextStyle(
                                            color: valid ? kSubtle : kError,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                  // Content
                                  Expanded(child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          Expanded(child: Text(
                                            (r['name'] as String).isNotEmpty
                                                ? r['name'] as String
                                                : '⚠ Name missing',
                                            style: TextStyle(
                                              color: (r['name'] as String)
                                                      .isNotEmpty
                                                  ? kDark : kError,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                            ),
                                          )),
                                        ]),
                                        const SizedBox(height: 4),
                                        Wrap(spacing: 8, runSpacing: 3,
                                            children: [
                                          _preTag(Icons.badge_outlined,
                                              (r['pno'] as String).isNotEmpty
                                                  ? 'PNO: ${r['pno']}'
                                                  : '⚠ PNO missing',
                                              (r['pno'] as String).isEmpty
                                                  ? kError : null),
                                          if ((r['mobile'] as String)
                                              .isNotEmpty)
                                            _preTag(Icons.phone_outlined,
                                                r['mobile'] as String, null),
                                          if ((r['thana'] as String)
                                              .isNotEmpty)
                                            _preTag(
                                                Icons.local_police_outlined,
                                                r['thana'] as String, null),
                                          if ((r['district'] as String)
                                              .isNotEmpty)
                                            _preTag(
                                                Icons.location_city_outlined,
                                                r['district'] as String,
                                                null),
                                        ]),
                                      ],
                                    ),
                                  )),
                                  // Remove button
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: const BorderRadius.only(
                                        topRight: Radius.circular(9),
                                        bottomRight: Radius.circular(9),
                                      ),
                                      onTap: () => ss(() => rows.removeAt(i)),
                                      child: Container(
                                        width: 36, height: double.infinity,
                                        alignment: Alignment.center,
                                        child: const Icon(Icons.close,
                                            size: 16, color: kError),
                                      ),
                                    ),
                                  ),
                                ]),
                              );
                            },
                          ),
                  ),

                  // Actions
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
                    child: Row(children: [
                      Expanded(child: OutlinedButton(
                        onPressed: uploading ? null : () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kSubtle,
                          side: const BorderSide(color: kBorder),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Cancel'),
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              validCount == 0 ? kSubtle : kPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: uploading || validCount == 0 ? null : () async {
                          ss(() => uploading = true);
                          try {
                            final valid = rows
                                .where(_isValidRow)
                                .map((r) {
                                  final m = Map<String, dynamic>.from(r);
                                  m.remove('_row');
                                  return m;
                                }).toList();
                            final token = await AuthService.getToken();
                            final res   = await ApiService.post(
                                '/admin/staff/bulk',
                                {'staff': valid},
                                token: token);
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _load();
                            if (mounted) {
                              final d = res['data'] as Map? ?? {};
                              showSnack(context,
                                  '${d['added'] ?? 0} added, '
                                  '${(d['skipped'] as List?)?.length ?? 0}'
                                  ' skipped');
                            }
                          } catch (e) {
                            ss(() => uploading = false);
                            if (ctx.mounted) showSnack(ctx, _msg(e), error: true);
                          }
                        },
                        icon: uploading
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.upload, size: 16),
                        label: Text(uploading
                            ? 'Uploading…'
                            : 'Upload $validCount Valid'),
                      )),
                    ]),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  bool _isValidRow(Map r) =>
      (r['pno'] as String? ?? '').isNotEmpty &&
      (r['name'] as String? ?? '').isNotEmpty;

  // ── Small helpers ──────────────────────────────────────────────────────────
  InputDecoration _dlgDeco(String label, IconData icon) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: kSubtle, fontSize: 13),
    prefixIcon: Icon(icon, size: 18, color: kPrimary),
    filled: true, fillColor: Colors.white, isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kBorder)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kBorder, width: 1.2)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kPrimary, width: 2)),
  );

  Widget _avatarWidget(String name, Color color) {
    final initials = name.trim().split(' ')
        .where((w) => w.isNotEmpty).take(2)
        .map((w) => w[0].toUpperCase()).join();
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Center(child: Text(
        initials.isEmpty ? 'S' : initials,
        style: TextStyle(color: color, fontWeight: FontWeight.w800,
            fontSize: initials.length <= 1 ? 16 : 12))),
    );
  }

  Widget _typeDot(String type) {
    final c = type == 'A' ? kError : type == 'B' ? kAccent : kInfo;
    return Container(
      width: 20, height: 20,
      decoration: BoxDecoration(shape: BoxShape.circle,
          color: c.withOpacity(0.15),
          border: Border.all(color: c.withOpacity(0.5))),
      child: Center(child: Text(type,
          style: TextStyle(color: c, fontSize: 9,
              fontWeight: FontWeight.w900))),
    );
  }

  Widget _mapChip(String field, String colLabel) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(field, style: const TextStyle(
          color: kDark, fontSize: 10, fontWeight: FontWeight.w800)),
      const Text(' → ', style: TextStyle(color: kSubtle, fontSize: 10)),
      Text(colLabel.isEmpty ? '?' : colLabel,
          style: const TextStyle(
              color: kInfo, fontSize: 10, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _preTag(IconData icon, String text, Color? color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 10, color: color ?? kSubtle),
      const SizedBox(width: 2),
      Text(text, style: TextStyle(
          color: color ?? kSubtle, fontSize: 10,
          fontWeight: FontWeight.w500)),
    ]);
  }

  Widget _statPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label, style: TextStyle(
          color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _summaryChip(String label, String count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: RichText(text: TextSpan(children: [
        TextSpan(text: '$count ',
            style: TextStyle(color: color, fontSize: 13,
                fontWeight: FontWeight.w900)),
        TextSpan(text: label,
            style: const TextStyle(color: kSubtle, fontSize: 11,
                fontWeight: FontWeight.w500)),
      ])),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color,
      VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(
              color: Colors.white, fontSize: 12,
              fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  // ── Staff Card ────────────────────────────────────────────────────────────
  Widget _staffCard(Map<String, dynamic> s, {required bool showCenter}) {
    final name     = _v(s['name']);
    final initials = name.trim().split(' ')
        .where((w) => w.isNotEmpty).take(2)
        .map((w) => w[0].toUpperCase()).join();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder.withOpacity(0.4)),
        boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.04),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Avatar
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: showCenter ? kSuccess.withOpacity(0.1) : kSurface,
              border: Border.all(
                  color: showCenter
                      ? kSuccess.withOpacity(0.35) : kBorder),
            ),
            child: Center(child: Text(
              initials.isEmpty ? 'S' : initials,
              style: TextStyle(
                color: showCenter ? kSuccess : kPrimary,
                fontWeight: FontWeight.w900,
                fontSize: initials.length <= 1 ? 18 : 13,
              ),
            )),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(
                  name.isNotEmpty ? name : '—',
                  style: const TextStyle(
                      color: kDark, fontWeight: FontWeight.w700,
                      fontSize: 14),
                )),
                const SizedBox(width: 6),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: (showCenter ? kSuccess : kAccent).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: (showCenter ? kSuccess : kAccent)
                            .withOpacity(0.3)),
                  ),
                  child: Text(
                    showCenter ? 'Assigned' : 'Reserve',
                    style: TextStyle(
                      color: showCenter ? kSuccess : kAccent,
                      fontSize: 10, fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 5),
              Wrap(spacing: 10, runSpacing: 3, children: [
                if (_v(s['pno']).isNotEmpty)
                  _infoTag(Icons.badge_outlined, 'PNO: ${_v(s['pno'])}'),
                if (_v(s['mobile']).isNotEmpty)
                  _infoTag(Icons.phone_outlined, _v(s['mobile'])),
                if (_v(s['thana']).isNotEmpty)
                  _infoTag(Icons.local_police_outlined, _v(s['thana'])),
                if (_v(s['district']).isNotEmpty)
                  _infoTag(Icons.location_city_outlined, _v(s['district'])),
              ]),
              if (showCenter && _v(s['centerName']).isNotEmpty) ...[
                const SizedBox(height: 5),
                Row(children: [
                  const Icon(Icons.location_on_outlined,
                      size: 12, color: kSuccess),
                  const SizedBox(width: 4),
                  Expanded(child: Text(_v(s['centerName']),
                      style: const TextStyle(
                          color: kSuccess, fontSize: 11,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
                ]),
              ],
            ],
          )),

          // Action button
          const SizedBox(width: 4),
          Tooltip(
            message: showCenter ? 'Move to Reserve' : 'Assign Duty',
            child: GestureDetector(
              onTap: () => showCenter
                  ? _removeFromAssigned(s)
                  : _assignFromReserve(s),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (showCenter ? kError : kPrimary).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: (showCenter ? kError : kPrimary).withOpacity(0.25)),
                ),
                child: Icon(
                  showCenter
                      ? Icons.person_remove_outlined
                      : Icons.how_to_vote_outlined,
                  color: showCenter ? kError : kPrimary,
                  size: 18,
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _infoTag(IconData icon, String text) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: kSubtle),
      const SizedBox(width: 3),
      Text(text, style: const TextStyle(
          color: kSubtle, fontSize: 11, fontWeight: FontWeight.w500)),
    ]);
  }

  String _msg(Object e) {
    final s = e.toString();
    return s.contains('Exception:')
        ? s.split('Exception:').last.trim() : s;
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(children: [

      // Search + Actions
      Container(
        color: kSurface,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: kDark, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search name, PNO, mobile, thana…',
                hintStyle: const TextStyle(color: kSubtle, fontSize: 13),
                prefixIcon: const Icon(Icons.search,
                    color: kSubtle, size: 18),
                suffixIcon: _q.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            size: 16, color: kSubtle),
                        onPressed: () {
                          _searchCtrl.clear();
                          _applyFilter('');
                        },
                      )
                    : null,
                filled: true, fillColor: Colors.white, isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: kBorder)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: kBorder, width: 1.2)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: kPrimary, width: 2)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _actionBtn(Icons.person_add_outlined, 'Add',
              kPrimary, _showAddDialog),
          const SizedBox(width: 6),
          _actionBtn(Icons.upload_file_outlined, 'Excel',
              kDark, _pickExcel),
        ]),
      ),

      // Summary strip
      if (!_loading)
        Container(
          color: kBg,
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 6),
          child: Row(children: [
            _summaryChip('Total',    '${_allStaff.length}', kPrimary),
            const SizedBox(width: 8),
            _summaryChip('Assigned', '${_assigned.length}', kSuccess),
            const SizedBox(width: 8),
            _summaryChip('Reserve',  '${_reserve.length}',  kAccent),
            const Spacer(),
            if (_q.isNotEmpty)
              Text('Showing ${_assigned.length + _reserve.length}',
                  style: const TextStyle(
                      color: kSubtle, fontSize: 11)),
          ]),
        ),

      // Tab bar
      Container(
        color: kBg,
        child: TabBar(
          controller: _tabs,
          labelColor: kPrimary,
          unselectedLabelColor: kSubtle,
          labelStyle: const TextStyle(
              fontWeight: FontWeight.w800, fontSize: 13),
          unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w500, fontSize: 13),
          indicatorColor: kPrimary,
          indicatorWeight: 3,
          tabs: [
            Tab(text: 'Assigned (${_assigned.length})'),
            Tab(text: 'Reserve (${_reserve.length})'),
          ],
        ),
      ),

      // Content
      if (_loading)
        const Expanded(child: Center(
            child: CircularProgressIndicator(color: kPrimary)))
      else
        Expanded(child: TabBarView(
          controller: _tabs,
          children: [
            // Assigned tab
            RefreshIndicator(
              onRefresh: _load, color: kPrimary,
              child: _assigned.isEmpty
                  ? emptyState(
                      _q.isNotEmpty
                          ? 'No results for "$_q"'
                          : 'No assigned staff yet.\nAssign duties from Reserve tab.',
                      Icons.how_to_vote_outlined)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 80),
                      itemCount: _assigned.length,
                      itemBuilder: (_, i) =>
                          _staffCard(_assigned[i], showCenter: true),
                    ),
            ),

            // Reserve tab
            RefreshIndicator(
              onRefresh: _load, color: kPrimary,
              child: _reserve.isEmpty
                  ? emptyState(
                      _q.isNotEmpty
                          ? 'No results for "$_q"'
                          : 'All staff assigned!',
                      Icons.badge_outlined)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 80),
                      itemCount: _reserve.length,
                      itemBuilder: (_, i) =>
                          _staffCard(_reserve[i], showCenter: false),
                    ),
            ),
          ],
        )),
    ]);
  }
}