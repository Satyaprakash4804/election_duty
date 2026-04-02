import 'package:flutter/material.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, dynamic>? _stats;
  List _duties = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
  setState(() => _loading = true);

  try {
    final token = await AuthService.getToken();

    final s = await ApiService.get('/admin/overview', token: token);
    final d = await ApiService.get('/admin/duties', token: token);

    setState(() {
      _stats  = s['data'];
      _duties = d['data'] ?? [];
      _loading = false;
    });

  } catch (e) {
    setState(() => _loading = false);

    // 🔥 IMPORTANT FIX (ADD THIS)
    if (e.toString().contains("Session expired")) {
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/login',
          (route) => false,
        );
      }
      return;
    }

    // normal error
    if (mounted) {
      showSnack(context, 'Failed to load: $e', error: true);
    }
  }
}

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: kPrimary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Stats ─────────────────────────────────────────────────────────
          if (_stats != null)
            LayoutBuilder(builder: (_, c) {
              final cols = c.maxWidth > 500 ? 4 : 2;
              return GridView.count(
                shrinkWrap: true,
                crossAxisCount: cols,
                crossAxisSpacing: 12, mainAxisSpacing: 12,
                childAspectRatio: 1.4,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  StatCard(label: 'Super Zones',
                      value: '${_stats!['superZones'] ?? 0}',
                      icon: Icons.layers_outlined, color: kPrimary),
                  StatCard(label: 'Total Booths',
                      value: '${_stats!['totalBooths'] ?? 0}',
                      icon: Icons.location_on_outlined, color: kSuccess),
                  StatCard(label: 'Total Staff',
                      value: '${_stats!['totalStaff'] ?? 0}',
                      icon: Icons.badge_outlined, color: kAccent),
                  StatCard(label: 'Assigned',
                      value: '${_stats!['assignedDuties'] ?? 0}',
                      icon: Icons.how_to_vote_outlined, color: kInfo),
                ],
              );
            }),

          const SizedBox(height: 20),
          const SectionHeader('Recent Duty Assignments'),

          if (_duties.isEmpty)
            emptyState('No duties assigned yet', Icons.how_to_vote_outlined)
          else
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kBorder.withOpacity(0.5)),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(kSurface),
                  headingTextStyle: const TextStyle(
                      color: kDark, fontWeight: FontWeight.w800, fontSize: 12),
                  dataTextStyle: const TextStyle(color: kDark, fontSize: 12),
                  columnSpacing: 16,
                  columns: const [
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('PNO')),
                    DataColumn(label: Text('Center')),
                    DataColumn(label: Text('Super Zone')),
                    DataColumn(label: Text('Type')),
                  ],
                  rows: _duties.take(30).map((d) => DataRow(cells: [
                    DataCell(Text('${d['name']}')),
                    DataCell(Text('${d['pno']}')),
                    DataCell(Text('${d['centerName'] ?? '-'}',
                        overflow: TextOverflow.ellipsis)),
                    DataCell(Text('${d['superZoneName'] ?? '-'}',
                        overflow: TextOverflow.ellipsis)),
                    DataCell(TypeBadge(type: '${d['centerType'] ?? 'C'}')),
                  ])).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}