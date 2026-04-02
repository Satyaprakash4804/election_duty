import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as ex;
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  STAFF PAGE
// ─────────────────────────────────────────────────────────────────────────────
class StaffPage extends StatefulWidget {
  const StaffPage({super.key});

  @override
  State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage>
    with SingleTickerProviderStateMixin {

  late final TabController _tabs;

  // Raw data from API
  List<Map<String, dynamic>> _allStaff   = [];
  // Filtered views
  List<Map<String, dynamic>> _assigned   = [];
  List<Map<String, dynamic>> _reserve    = [];

  bool _loading = true;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)
      ..addListener(() => setState(() {}));
    _searchCtrl.addListener(_onSearch);
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
      final token = await AuthService.getToken();
      // FIX: correct URL prefix is /admin/staff
      final res = await ApiService.get('/admin/staff', token: token);
      final raw = (res['data'] as List? ?? [])
        .map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          m['isAssigned'] = m['isAssigned'] == true || m['isAssigned'] == 1;
          return m;
        })
        .toList();    

      setState(() {
        _allStaff = raw;
        _loading  = false;
      });
      _applyFilter(_searchQuery);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showSnack(context, 'Failed to load staff: ${_msg(e)}', error: true);
    }
  }

  // ── SEARCH / FILTER ───────────────────────────────────────────────────────
  void _onSearch() {
    _applyFilter(_searchCtrl.text);
  }

  void _applyFilter(String q) {
    setState(() {
      _searchQuery = q.toLowerCase().trim();
      final filtered = _searchQuery.isEmpty
          ? _allStaff
          : _allStaff.where((s) =>
              _v(s['name']).contains(_searchQuery) ||
              _v(s['pno']).contains(_searchQuery) ||
              _v(s['mobile']).contains(_searchQuery) ||
              _v(s['thana']).contains(_searchQuery)).toList();

       _assigned = filtered.where((s) => s['isAssigned'] == true || s['isAssigned'] == 1).toList();
      _reserve  = filtered.where((s) => s['isAssigned'] != true && s['isAssigned'] != 1).toList();
    });  
  }

  String _v(dynamic v) => (v ?? '').toString().toLowerCase();

  // ── ADD STAFF DIALOG ──────────────────────────────────────────────────────
  void _showAddDialog() {
    final pnoCtrl      = TextEditingController();
    final nameCtrl     = TextEditingController();
    final mobileCtrl   = TextEditingController();
    final thanaCtrl    = TextEditingController();
    final districtCtrl = TextEditingController();
    final formKey      = GlobalKey<FormState>();
    bool  saving       = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Container(
              decoration: BoxDecoration(
                color: kBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder, width: 1.2),
                boxShadow: [BoxShadow(
                    color: kPrimary.withOpacity(0.18),
                    blurRadius: 24, offset: const Offset(0, 8))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                dlgHeader('Add Staff Member', Icons.person_add_outlined, ctx),

                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Form(
                    key: formKey,
                    child: Column(children: [
                      AppTextField(
                        label: 'PNO *',
                        controller: pnoCtrl,
                        prefixIcon: Icons.badge_outlined,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'PNO is required' : null,
                      ),
                      AppTextField(
                        label: 'Full Name *',
                        controller: nameCtrl,
                        prefixIcon: Icons.person_outline,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Name is required' : null,
                      ),
                      AppTextField(
                        label: 'Mobile',
                        controller: mobileCtrl,
                        prefixIcon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                      AppTextField(
                        label: 'Thana',
                        controller: thanaCtrl,
                        prefixIcon: Icons.local_police_outlined,
                      ),
                      AppTextField(
                        label: 'District',
                        controller: districtCtrl,
                        prefixIcon: Icons.location_city_outlined,
                      ),
                    ]),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving ? null : () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kSubtle,
                          side: const BorderSide(color: kBorder),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: saving
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setDlg(() => saving = true);
                                try {
                                  final token = await AuthService.getToken();
                                  // FIX: correct URL prefix
                                  await ApiService.post(
                                    '/admin/staff',
                                    {
                                      'pno':      pnoCtrl.text.trim(),
                                      'name':     nameCtrl.text.trim(),
                                      'mobile':   mobileCtrl.text.trim(),
                                      'thana':    thanaCtrl.text.trim(),
                                      'district': districtCtrl.text.trim(),
                                    },
                                    token: token,
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  // FIX: reload list + show snack AFTER dialog closes
                                  await _load();
                                  if (mounted) {
                                    showSnack(context,
                                        '${nameCtrl.text} added successfully');
                                  }
                                } catch (e) {
                                  setDlg(() => saving = false);
                                  if (ctx.mounted) {
                                    showSnack(ctx,
                                        'Error: ${_msg(e)}', error: true);
                                  }
                                }
                              },
                        child: saving
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text('Save Staff'),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ── EXCEL UPLOAD ──────────────────────────────────────────────────────────
  Future<void> _pickExcel() async {
    // Show loading indicator while picking
    if (mounted) {
      showSnack(context, 'Opening file picker…');
    }

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,    // CRITICAL: must be true to get bytes on Android
      );
    } catch (e) {
      if (mounted) showSnack(context, 'File picker error: ${_msg(e)}', error: true);
      return;
    }

    if (result == null || result.files.isEmpty) return;

    final bytes = result.files.single.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        showSnack(context,
            'Could not read file. Enable Developer Mode in Windows settings.',
            error: true);
      }
      return;
    }

    // Parse Excel
    List<Map<String, dynamic>> items = [];
    try {
      final excel = ex.Excel.decodeBytes(bytes);
      for (final sheetName in excel.tables.keys) {
        final sheet = excel.tables[sheetName]!;
        if (sheet == null || sheet.rows.isEmpty) continue;
        // Skip header row (i=0), read from row 1
        for (int i = 1; i < sheet.rows.length; i++) {
          final row = sheet.rows[i];
          if (row.isEmpty) continue;
          final pno  = _cellVal(row, 0);
          final name = _cellVal(row, 1);
          if (pno.isEmpty && name.isEmpty) continue;
          items.add({
            'pno':      pno,
            'name':     name,
            'mobile':   _cellVal(row, 2),
            'thana':    _cellVal(row, 3),
            'district': _cellVal(row, 4),
          });
        }
        break; // only first sheet
      }
    } catch (e) {
      showSnack(context, 'Excel parse error: ${e.toString()}', error: true);
      return;
    }

    if (items.isEmpty) {
      if (mounted) {
        showSnack(context,
            'No data found. Check format: PNO | Name | Mobile | Thana | District',
            error: true);
      }
      return;
    }

    // Show preview dialog
    if (!mounted) return;
    _showExcelPreviewDialog(items);
  }

  String _cellVal(List<ex.Data?> row, int col) {
    if (col >= row.length) return '';

    final cell = row[col];
    if (cell == null) return '';

    final value = cell.value;
    if (value == null) return '';

    return value.toString().trim();
  }  

  // ── EXCEL PREVIEW DIALOG ──────────────────────────────────────────────────
  void _showExcelPreviewDialog(List<Map<String, dynamic>> items) {
    bool uploading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Container(
              decoration: BoxDecoration(
                color: kBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder, width: 1.2),
                boxShadow: [BoxShadow(
                    color: kPrimary.withOpacity(0.15),
                    blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [

                // Header
                dlgHeader(
                  'Preview — ${items.length} Staff Found',
                  Icons.upload_file_outlined,
                  ctx,
                ),

                // Format hint
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  color: kInfo.withOpacity(0.07),
                  child: const Text(
                    'Columns: PNO | Name | Mobile | Thana | District',
                    style: TextStyle(color: kInfo, fontSize: 11,
                        fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ),

                // Preview list
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.4,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final s = items[i];
                      final hasError =
                          (s['pno'] as String).isEmpty ||
                          (s['name'] as String).isEmpty;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: hasError
                              ? kError.withOpacity(0.05)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: hasError
                                ? kError.withOpacity(0.3)
                                : kBorder.withOpacity(0.4),
                          ),
                        ),
                        child: Row(children: [
                          // Row number
                          Container(
                            width: 26, height: 26,
                            decoration: BoxDecoration(
                              color: hasError
                                  ? kError.withOpacity(0.12)
                                  : kSurface,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: hasError
                                  ? const Icon(Icons.warning_amber_rounded,
                                      color: kError, size: 14)
                                  : Text('${i + 1}',
                                      style: const TextStyle(
                                          color: kPrimary, fontSize: 10,
                                          fontWeight: FontWeight.w800)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (s['name'] as String).isNotEmpty
                                      ? s['name'] as String
                                      : '⚠ Name missing',
                                  style: TextStyle(
                                    color: hasError ? kError : kDark,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Wrap(spacing: 8, children: [
                                  _excelTag(Icons.badge_outlined,
                                      (s['pno'] as String).isNotEmpty
                                          ? s['pno'] as String
                                          : '⚠ PNO missing',
                                      color: (s['pno'] as String).isEmpty
                                          ? kError : null),
                                  if ((s['mobile'] as String).isNotEmpty)
                                    _excelTag(Icons.phone_outlined,
                                        s['mobile'] as String),
                                  if ((s['thana'] as String).isNotEmpty)
                                    _excelTag(Icons.local_police_outlined,
                                        s['thana'] as String),
                                ]),
                              ],
                            ),
                          ),
                        ]),
                      );
                    },
                  ),
                ),

                // Stats row
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                  child: Row(children: [
                    _statPill('${items.where((s) =>
                        (s['pno'] as String).isNotEmpty &&
                        (s['name'] as String).isNotEmpty).length} Valid',
                        kSuccess),
                    const SizedBox(width: 8),
                    _statPill('${items.where((s) =>
                        (s['pno'] as String).isEmpty ||
                        (s['name'] as String).isEmpty).length} Errors',
                        kError),
                  ]),
                ),

                // Action buttons
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: uploading ? null : () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kSubtle,
                          side: const BorderSide(color: kBorder),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: uploading
                            ? null
                            : () async {
                                setDlg(() => uploading = true);
                                try {
                                  final token = await AuthService.getToken();
                                  // FIX: correct URL prefix
                                  final res = await ApiService.post(
                                    '/admin/staff/bulk',
                                    {'staff': items},
                                    token: token,
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);

                                  // FIX: reload + show result
                                  await _load();
                                  if (mounted) {
                                    final d = res['data'] as Map? ?? {};
                                    final added   = d['added']   ?? 0;
                                    final skipped = (d['skipped'] as List?)
                                            ?.length ?? 0;
                                    showSnack(context,
                                        '$added added, $skipped skipped (duplicate PNOs)');
                                  }
                                } catch (e) {
                                  setDlg(() => uploading = false);
                                  if (ctx.mounted) {
                                    showSnack(ctx,
                                        'Upload failed: ${_msg(e)}',
                                        error: true);
                                  }
                                }
                              },
                        icon: uploading
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.upload, size: 16),
                        label: Text(uploading ? 'Uploading…' : 'Upload All'),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _excelTag(IconData icon, String text, {Color? color}) {
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

  // ── STAFF CARD ────────────────────────────────────────────────────────────
  Widget _staffCard(Map<String, dynamic> s, {bool showCenter = false}) {
    final name     = _v2(s['name']);
    final initials = name.isNotEmpty
        ? name.trim().split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase()
        : 'S';
    final pno      = _v2(s['pno']);
    final mobile   = _v2(s['mobile']);
    final thana    = _v2(s['thana']);
    final district = _v2(s['district']);
    final center   = _v2(s['centerName']);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder.withOpacity(0.4)),
        boxShadow: [BoxShadow(
            color: kPrimary.withOpacity(0.04),
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
              color: showCenter
                  ? kSuccess.withOpacity(0.1)
                  : kSurface,
              border: Border.all(
                color: showCenter
                    ? kSuccess.withOpacity(0.35)
                    : kBorder,
              ),
            ),
            child: Center(child: Text(initials, style: TextStyle(
                color: showCenter ? kSuccess : kPrimary,
                fontWeight: FontWeight.w900,
                fontSize: initials.length == 1 ? 18 : 14))),
          ),

          const SizedBox(width: 12),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + status badge
                Row(children: [
                  Expanded(child: Text(name.isNotEmpty ? name : '—',
                      style: const TextStyle(
                          color: kDark, fontWeight: FontWeight.w700,
                          fontSize: 14))),
                  const SizedBox(width: 6),
                  _statusBadge(showCenter),
                ]),
                const SizedBox(height: 5),

                // Info rows
                Wrap(spacing: 12, runSpacing: 4, children: [
                  if (pno.isNotEmpty)      _tag(Icons.badge_outlined,         'PNO: $pno'),
                  if (mobile.isNotEmpty)   _tag(Icons.phone_outlined,         mobile),
                  if (thana.isNotEmpty)    _tag(Icons.local_police_outlined,  thana),
                  if (district.isNotEmpty) _tag(Icons.location_city_outlined, district),
                ]),

                // Center name (assigned tab only)
                if (showCenter && center.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Row(children: [
                    const Icon(Icons.location_on_outlined,
                        size: 12, color: kSuccess),
                    const SizedBox(width: 4),
                    Expanded(child: Text(center,
                        style: const TextStyle(
                            color: kSuccess, fontSize: 11,
                            fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                  ]),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _statusBadge(bool assigned) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: (assigned ? kSuccess : kAccent).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: (assigned ? kSuccess : kAccent).withOpacity(0.3)),
      ),
      child: Text(
        assigned ? 'Assigned' : 'Reserve',
        style: TextStyle(
            color: assigned ? kSuccess : kAccent,
            fontSize: 10, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _tag(IconData icon, String text) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: kSubtle),
      const SizedBox(width: 3),
      Text(text, style: const TextStyle(
          color: kSubtle, fontSize: 11, fontWeight: FontWeight.w500)),
    ]);
  }

  String _v2(dynamic v) => (v ?? '').toString().trim();

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(children: [

      // ── Search bar + action buttons ───────────────────────────────────────
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
                prefixIcon: const Icon(Icons.search, color: kSubtle, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16, color: kSubtle),
                        onPressed: () {
                          _searchCtrl.clear();
                          _applyFilter('');
                        },
                      )
                    : null,
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
                    borderSide: const BorderSide(color: kPrimary, width: 2)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _actionBtn(
              Icons.person_add_outlined, 'Add', kPrimary, _showAddDialog),
          const SizedBox(width: 6),
          _actionBtn(
              Icons.upload_file_outlined, 'Excel', kDark, _pickExcel),
        ]),
      ),

      // ── Summary strip ─────────────────────────────────────────────────────
      if (!_loading)
        Container(
          color: kBg,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(children: [
            _summaryChip('Total', '${_allStaff.length}', kPrimary),
            const SizedBox(width: 8),
            _summaryChip('Assigned', '${_assigned.length}', kSuccess),
            const SizedBox(width: 8),
            _summaryChip('Reserve', '${_reserve.length}', kAccent),
            const Spacer(),
            if (_searchQuery.isNotEmpty)
              Text('Filtered: ${_assigned.length + _reserve.length}',
                  style: const TextStyle(
                      color: kSubtle, fontSize: 11,
                      fontWeight: FontWeight.w600)),
          ]),
        ),

      // ── Tab bar ───────────────────────────────────────────────────────────
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

      // ── Tab views ─────────────────────────────────────────────────────────
      if (_loading)
        const Expanded(child: Center(
            child: CircularProgressIndicator(color: kPrimary)))
      else
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              // Assigned
              RefreshIndicator(
                onRefresh: _load,
                color: kPrimary,
                child: _assigned.isEmpty
                    ? emptyState(
                        _searchQuery.isNotEmpty
                            ? 'No results for "$_searchQuery"'
                            : 'No assigned staff yet',
                        Icons.how_to_vote_outlined)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                        itemCount: _assigned.length,
                        itemBuilder: (_, i) =>
                            _staffCard(_assigned[i], showCenter: true),
                      ),
              ),

              // Reserve
              RefreshIndicator(
                onRefresh: _load,
                color: kPrimary,
                child: _reserve.isEmpty
                    ? emptyState(
                        _searchQuery.isNotEmpty
                            ? 'No results for "$_searchQuery"'
                            : 'No reserve staff',
                        Icons.badge_outlined)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                        itemCount: _reserve.length,
                        itemBuilder: (_, i) =>
                            _staffCard(_reserve[i], showCenter: false),
                      ),
              ),
            ],
          ),
        ),
    ]);
  }

  Widget _actionBtn(
      IconData icon, String label, Color color, VoidCallback onTap) {
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

  Widget _summaryChip(String label, String count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: RichText(
        text: TextSpan(children: [
          TextSpan(text: '$count ',
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w900)),
          TextSpan(text: label,
              style: const TextStyle(
                  color: kSubtle, fontSize: 11, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  String _msg(Object e) {
    final s = e.toString();
    if (s.contains('Exception:')) return s.split('Exception:').last.trim();
    return s;
  }
}