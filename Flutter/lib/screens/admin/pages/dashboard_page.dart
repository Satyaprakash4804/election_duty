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
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final s = await ApiService.get('/admin/overview', token: token);
      final d = await ApiService.get('/admin/duties', token: token);
      setState(() {
        _stats = s['data'];
        _duties = d['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) showSnack(context, 'Failed to load: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_stats != null)
            GridView.count(
              crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.3,
              children: [
                StatCard(label: 'Super Zones', value: '${_stats!['superZones'] ?? 0}', icon: Icons.layers, color: Colors.blue),
                StatCard(label: 'Total Booths', value: '${_stats!['totalBooths'] ?? 0}', icon: Icons.location_on, color: Colors.green),
                StatCard(label: 'Total Staff', value: '${_stats!['totalStaff'] ?? 0}', icon: Icons.people, color: Colors.orange),
                StatCard(label: 'Assigned', value: '${_stats!['assignedDuties'] ?? 0}', icon: Icons.assignment_turned_in, color: Colors.purple),
              ],
            ),

          const SizedBox(height: 20),
          const Text('Recent Duty Assignments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),

          if (_duties.isEmpty)
            const Center(child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('No duties assigned yet', style: TextStyle(color: Colors.grey)),
            ))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                headingRowColor: WidgetStateProperty.all(Colors.blue.shade50),
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
                  DataCell(Text('${d['centerName'] ?? '-'}')),
                  DataCell(Text('${d['superZoneName'] ?? '-'}')),
                  DataCell(_TypeBadge(type: '${d['centerType'] ?? 'C'}')),
                ])).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge({required this.type});

  Color get _color => type == 'A' ? Colors.red : type == 'B' ? Colors.orange : Colors.blue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(type, style: TextStyle(color: _color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}