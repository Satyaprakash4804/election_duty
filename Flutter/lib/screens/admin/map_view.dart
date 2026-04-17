import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mappls_gl/mappls_gl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';

// ── Palette (matches existing app theme) ────────────────────────────────────
const _kBg      = Color(0xFFF8F9FC);
const _kPrimary = Color(0xFF0F2B5B);
const _kAccent  = Color(0xFFFBBF24);
const _kGreen   = Color(0xFF186A3B);
const _kRed     = Color(0xFFC0392B);
const _kOrange  = Color(0xFFE67E22);
const _kPurple  = Color(0xFF6C3483);
const _kSubtle  = Color(0xFF6B7C93);
const _kBorder  = Color(0xFFDDE3EE);
const _kDark    = Color(0xFF1A2332);
const _kSurface = Color(0xFFFFFFFF);

Color _typeColor(String? t) {
  switch (t) {
    case 'A++': return _kPurple;
    case 'A':   return _kRed;
    case 'B':   return _kOrange;
    default:    return _kGreen;
  }
}

// Hex color string for Mappls GL style expressions
String _typeColorHex(String? t) {
  switch (t) {
    case 'A++': return '#6C3483';
    case 'A':   return '#C0392B';
    case 'B':   return '#E67E22';
    default:    return '#186A3B';
  }
}

String _typeLabel(String? t) {
  switch (t) {
    case 'A++': return 'अत्यति संवेदनशील';
    case 'A':   return 'अति संवेदनशील';
    case 'B':   return 'संवेदनशील';
    default:    return 'सामान्य';
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Entry point — MapViewPage
// ══════════════════════════════════════════════════════════════════════════════
class MapViewPage extends StatefulWidget {
  const MapViewPage({super.key});

  @override
  State<MapViewPage> createState() => _MapViewPageState();
}

class _MapViewPageState extends State<MapViewPage> {
  _NavLevel _level     = _NavLevel.district;
  String?   _district;
  Map?      _superZone;
  Map?      _zone;

  List<Map> _districts  = [];
  List<Map> _superZones = [];
  List<Map> _zones      = [];
  List<Map> _centers    = [];

  bool    _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHierarchy();
  }

  Future<void> _loadHierarchy() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get('/admin/hierarchy/full', token: token);
      final data  = res is List ? res : (res['data'] ?? []) as List;

      final districtSet = <String>{};
      for (final sz in data) {
        final d = (sz['district'] ?? '').toString().trim();
        if (d.isNotEmpty) districtSet.add(d);
      }

      setState(() {
        _superZones = List<Map>.from(data);
        _districts  = districtSet
            .map((d) => <String, dynamic>{'district': d})
            .toList();
        _loading    = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _selectDistrict(String district) =>
      setState(() { _district = district; _level = _NavLevel.superZone; });

  void _selectSuperZone(Map sz) {
    final zones = List<Map>.from(sz['zones'] as List? ?? []);
    setState(() { _superZone = sz; _zones = zones; _level = _NavLevel.zone; });
  }

  void _selectZone(Map zone) {
    final centers = <Map>[];
    for (final s in (zone['sectors'] as List? ?? [])) {
      for (final gp in (s['panchayats'] as List? ?? [])) {
        for (final c in (gp['centers'] as List? ?? [])) {
          final lat = c['latitude'];
          final lng = c['longitude'];
          if (lat != null && lng != null) {
            centers.add({
              ...Map<String, dynamic>.from(c),
              '_zone':      zone,
              '_sector':    s,
              '_gp':        gp,
              '_superZone': _superZone,
            });
          }
        }
      }
    }
    setState(() { _zone = zone; _centers = centers; _level = _NavLevel.map; });
  }

  void _goBack() {
    setState(() {
      switch (_level) {
        case _NavLevel.map:
          _level = _NavLevel.zone; _zone = null; _centers.clear(); break;
        case _NavLevel.zone:
          _level = _NavLevel.superZone; _superZone = null; _zones.clear(); break;
        case _NavLevel.superZone:
          _level = _NavLevel.district; _district = null; break;
        case _NavLevel.district: break;
      }
    });
  }

  List<Map> get _filteredSuperZones => _district == null
      ? _superZones
      : _superZones.where((sz) =>
          (sz['district'] ?? '').toString().trim() == _district).toList();

  String get _title {
    switch (_level) {
      case _NavLevel.district:  return 'जिला चुनें';
      case _NavLevel.superZone: return _district ?? 'सुपर जोन';
      case _NavLevel.zone:      return _superZone?['name'] ?? 'जोन';
      case _NavLevel.map:       return _zone?['name'] ?? 'नक्शा';
    }
  }

  String get _breadcrumb {
    final parts = <String>['चुनाव नक्शा'];
    if (_district  != null) parts.add(_district!);
    if (_superZone != null) parts.add(_superZone!['name'] ?? '');
    if (_zone      != null) parts.add(_zone!['name'] ?? '');
    return parts.join(' › ');
  }

  @override
  Widget build(BuildContext context) {
    final isMap = _level == _NavLevel.map;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        elevation: 0,
        leading: _level != _NavLevel.district
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                onPressed: _goBack)
            : null,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_title,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
          Text(_breadcrumb,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
        actions: [
          // Print button — only visible on map level
          if (isMap)
            IconButton(
              icon: const Icon(Icons.print_outlined, color: Colors.white, size: 20),
              tooltip: 'नक्शा प्रिंट करें',
              onPressed: () {
                // Trigger print via the map view's GlobalKey
                _mapViewKey.currentState?.printMap();
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
            onPressed: _loadHierarchy,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _loadHierarchy)
              : _buildBody(),
    );
  }

  // GlobalKey to access _MapView state for print
  final _mapViewKey = GlobalKey<_MapViewState>();

  Widget _buildBody() {
    switch (_level) {
      case _NavLevel.district:
        return _DistrictList(districts: _districts, onSelect: _selectDistrict);
      case _NavLevel.superZone:
        return _SuperZoneList(superZones: _filteredSuperZones, onSelect: _selectSuperZone);
      case _NavLevel.zone:
        return _ZoneList(zones: _zones, superZone: _superZone!, onSelect: _selectZone);
      case _NavLevel.map:
        return _MapView(
          key:       _mapViewKey,
          zone:      _zone!,
          superZone: _superZone!,
          centers:   _centers,
        );
    }
  }
}

enum _NavLevel { district, superZone, zone, map }

// ══════════════════════════════════════════════════════════════════════════════
//  District list
// ══════════════════════════════════════════════════════════════════════════════
class _DistrictList extends StatelessWidget {
  final List<Map> districts;
  final void Function(String) onSelect;
  const _DistrictList({required this.districts, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    if (districts.isEmpty) return const _Empty(text: 'कोई जिला नहीं मिला');
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(14, 14, 14,
          MediaQuery.of(context).padding.bottom + 14),
      itemCount: districts.length,
      itemBuilder: (_, i) {
        final d = '${districts[i]['district']}';
        return _DrillCard(
          leading: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
                color: _kPrimary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.location_city_outlined, color: _kPrimary, size: 22)),
          title: d, subtitle: 'जिला', color: _kPrimary,
          onTap: () => onSelect(d));
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Super Zone list
// ══════════════════════════════════════════════════════════════════════════════
class _SuperZoneList extends StatelessWidget {
  final List<Map> superZones;
  final void Function(Map) onSelect;
  const _SuperZoneList({required this.superZones, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    if (superZones.isEmpty) return const _Empty(text: 'कोई सुपर जोन नहीं मिला');
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(14, 14, 14,
          MediaQuery.of(context).padding.bottom + 14),
      itemCount: superZones.length,
      itemBuilder: (_, i) {
        final sz       = superZones[i];
        final zones    = (sz['zones'] as List?)?.length ?? 0;
        final officers = (sz['officers'] as List? ?? []);
        final nm       = '${sz['name']}';
        return _DrillCard(
          leading: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF0F2B5B), Color(0xFF1E3F80)]),
                borderRadius: BorderRadius.circular(10)),
            child: Center(child: Text(nm.substring(0, math.min(2, nm.length)),
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)))),
          title: nm,
          subtitle: 'ब्लॉक: ${sz['block'] ?? '—'}  •  $zones जोन',
          badge: officers.isNotEmpty ? '${officers.length} अधिकारी' : null,
          color: _kPrimary,
          onTap: () => onSelect(sz));
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Zone list
// ══════════════════════════════════════════════════════════════════════════════
class _ZoneList extends StatelessWidget {
  final List<Map> zones;
  final Map superZone;
  final void Function(Map) onSelect;
  const _ZoneList({required this.zones, required this.superZone, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    if (zones.isEmpty) return const _Empty(text: 'कोई जोन नहीं मिला');
    final szOfficers = (superZone['officers'] as List? ?? []);

    return Column(children: [
      if (szOfficers.isNotEmpty)
        _OfficerBanner(
          label: 'सुपर जोन अधिकारी – ${superZone['name']}',
          officers: szOfficers, color: _kPrimary),
      Expanded(
        child: ListView.builder(
          padding: EdgeInsets.fromLTRB(14, 14, 14,
              MediaQuery.of(context).padding.bottom + 14),
          itemCount: zones.length,
          itemBuilder: (_, i) {
            final z       = zones[i];
            final sectors = (z['sectors'] as List?)?.length ?? 0;
            int centers   = 0;
            for (final s in (z['sectors'] as List? ?? []))
              for (final gp in (s['panchayats'] as List? ?? []))
                centers += (gp['centers'] as List?)?.length ?? 0;
            final officers = (z['officers'] as List? ?? []);

            return _DrillCard(
              leading: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                    color: _kGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kGreen.withOpacity(0.3))),
                child: const Icon(Icons.map_outlined, color: _kGreen, size: 22)),
              title: '${z['name']}',
              subtitle: '$sectors सैक्टर  •  $centers मतदान केन्द्र',
              badge: officers.isNotEmpty ? '${officers.length} अधिकारी' : null,
              extra: (z['hq_address'] ?? '').toString().isNotEmpty
                  ? 'HQ: ${z['hq_address']}' : null,
              color: _kGreen,
              trailingIcon: Icons.map_rounded,
              onTap: () => onSelect(z));
          },
        ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  MAP VIEW  — Fixed markers + Print support
// ══════════════════════════════════════════════════════════════════════════════
class _MapView extends StatefulWidget {
  final Map zone, superZone;
  final List<Map> centers;
  const _MapView({super.key, required this.zone, required this.superZone, required this.centers});

  @override
  State<_MapView> createState() => _MapViewState();
}

class _MapViewState extends State<_MapView> {
  MapplsMapController? _ctrl;

  // Separate tracking: circles for colored dots, symbols for labels
  final List<Circle>  _circles = [];
  final List<Symbol>  _symbols = [];

  Map? _selectedCenter;
  bool _markersAdded = false;

  // RepaintBoundary key for screenshot/print
  final _repaintKey = GlobalKey();

  // ── Map lifecycle ─────────────────────────────────────────────────────────
  void _onMapCreated(MapplsMapController controller) {
    _ctrl = controller;
  }

  void _onStyleLoaded() {
    if (!_markersAdded) {
      _markersAdded = true;
      _addMarkers();
    }
  }

  // ── FIX: Add markers using circles (colored) + symbols (labels) ───────────
  Future<void> _addMarkers() async {
    if (_ctrl == null || widget.centers.isEmpty) return;

    for (int i = 0; i < widget.centers.length; i++) {
      final c   = widget.centers[i];
      final lat = (c['latitude']  as num).toDouble();
      final lng = (c['longitude'] as num).toDouble();
      final type = '${c['center_type'] ?? c['centerType'] ?? 'C'}';
      final colorHex = _typeColorHex(type);

      // 1. Colored filled circle (the actual visible marker)
      final circle = await _ctrl!.addCircle(CircleOptions(
        geometry:        LatLng(lat, lng),
        circleRadius:    9.0,
        circleColor:     colorHex,
        circleOpacity:   1.0,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2.0,
      ));
      _circles.add(circle);

      // 2. Symbol for the center name label below the dot
      final sym = await _ctrl!.addSymbol(SymbolOptions(
        geometry:       LatLng(lat, lng),
        textField:      '${c['name']}',
        textSize:       10.0,
        textOffset:     const Offset(0, 2.2),
        textColor:      '#1A2332',
        textHaloColor:  '#FFFFFF',
        textHaloWidth:  1.5,
        textAnchor:     'top',
        iconImage:      '',    // no default marker icon
        iconSize:       0.0,
      ));
      _symbols.add(sym);
    }

    // Tap listener on circles
    _ctrl!.onCircleTapped.add(_onCircleTapped);

    _fitBounds();
  }

  void _onCircleTapped(Circle circle) {
    final idx = _circles.indexOf(circle);
    if (idx >= 0 && idx < widget.centers.length) {
      setState(() => _selectedCenter = widget.centers[idx]);
      _showCenterSheet(widget.centers[idx]);
    }
  }

  void _fitBounds() {
    if (_ctrl == null || widget.centers.isEmpty) return;
    double minLat =  90, maxLat = -90;
    double minLng = 180, maxLng = -180;
    for (final c in widget.centers) {
      final lat = (c['latitude']  as num).toDouble();
      final lng = (c['longitude'] as num).toDouble();
      minLat = math.min(minLat, lat);
      maxLat = math.max(maxLat, lat);
      minLng = math.min(minLng, lng);
      maxLng = math.max(maxLng, lng);
    }
    const pad = 0.005;
    _ctrl!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat - pad, minLng - pad),
        northeast: LatLng(maxLat + pad, maxLng + pad),
      ),
      top: 100, bottom: 40, left: 40, right: 40,
    ));
  }

  // ── Print: capture map via RepaintBoundary → PDF → system print ───────────
  Future<void> printMap() async {
    try {
      // Show a small snack so user knows it's working
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('नक्शा कैप्चर हो रहा है...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Capture the RepaintBoundary as PNG bytes
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final pngBytes = byteData.buffer.asUint8List();

      // Build a PDF page with the captured image + header info
      final pdf  = pw.Document();
      final pdfImg = pw.MemoryImage(pngBytes);

      final zoneName  = widget.zone['name']      ?? '';
      final szName    = widget.superZone['name'] ?? '';
      final szBlock   = widget.superZone['block'] ?? '—';
      final totalCenters = widget.centers.length;

      // Count by type
      final typeCounts = <String, int>{};
      for (final c in widget.centers) {
        final t = '${c['center_type'] ?? c['centerType'] ?? 'C'}';
        typeCounts[t] = (typeCounts[t] ?? 0) + 1;
      }

      final font = await PdfGoogleFonts.notoSansDevanagariRegular();
      final bold = await PdfGoogleFonts.notoSansDevanagariBold();

      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(16),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue900,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('चुनाव नक्शा – Election Center Map',
                      style: pw.TextStyle(font: bold, fontSize: 14, color: PdfColors.white)),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'जोन: $zoneName  •  सुपर जोन: $szName  •  ब्लॉक: $szBlock  •  कुल केन्द्र: $totalCenters',
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 9,
                      color: PdfColor.fromInt(0xB3FFFFFF), // ✅ FIXED
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            // Map image
            pw.Expanded(
              child: pw.Container(
                width: double.infinity,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.ClipRRect(
                  horizontalRadius: 4, verticalRadius: 4,
                  child: pw.Image(pdfImg, fit: pw.BoxFit.contain)),
              ),
            ),
            pw.SizedBox(height: 8),
            // Legend row
            pw.Row(children: [
              for (final e in const [
                ['A++', 'अत्यति संवेदनशील', PdfColors.purple900],
                ['A',   'अति संवेदनशील',    PdfColors.red900],
                ['B',   'संवेदनशील',         PdfColors.orange900],
                ['C',   'सामान्य',            PdfColors.green900],
              ]) ...[
                pw.Container(width: 10, height: 10,
                    decoration: pw.BoxDecoration(
                        color: e[2] as PdfColor, shape: pw.BoxShape.circle)),
                pw.SizedBox(width: 4),
                pw.Text(
                  '${e[0]}: ${typeCounts[e[0]] ?? 0}  ${e[1]}',
                  style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey800),
                ),
                pw.SizedBox(width: 16),
              ],
              pw.Spacer(),
              pw.Text(
                'मुद्रण दिनांक: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600),
              ),
            ]),
          ],
        ),
      ));

      await Printing.layoutPdf(onLayout: (_) => pdf.save());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('प्रिंट विफल: $e'), backgroundColor: _kRed),
        );
      }
    }
  }

  void _showCenterSheet(Map center) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CenterDetailSheet(center: center),
    );
  }

  void _showLegend(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('रंग संकेत',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final e in const [
            ['A++', 'अत्यति संवेदनशील'],
            ['A',   'अति संवेदनशील'],
            ['B',   'संवेदनशील'],
            ['C',   'सामान्य'],
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Container(width: 14, height: 14,
                    decoration: BoxDecoration(
                        color: _typeColor(e[0]), shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Text('${e[0]} – ${e[1]}',
                    style: const TextStyle(fontSize: 13)),
              ]),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('बंद')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.centers.isEmpty) {
      return const _Empty(
          text: 'इस जोन में कोई मतदान केन्द्र नहीं (GPS निर्देशांक उपलब्ध नहीं)');
    }

    return Stack(children: [

      // ── Mappls map wrapped in RepaintBoundary for screenshot ──────────────
      RepaintBoundary(
        key: _repaintKey,
        child: MapplsMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(
              (widget.centers.first['latitude']  as num).toDouble(),
              (widget.centers.first['longitude'] as num).toDouble(),
            ),
            zoom: 11,
          ),
          onMapCreated:          _onMapCreated,
          onStyleLoadedCallback: _onStyleLoaded,
          myLocationEnabled:     true,
          compassEnabled:        true,
          rotateGesturesEnabled: true,
          tiltGesturesEnabled:   false,
        ),
      ),

      // ── Floating info panel (top) ─────────────────────────────────────────
      Positioned(
        top: MediaQuery.of(context).padding.top + 8,
        left: 12, right: 12,
        child: _ZoneInfoBanner(
          zone:      widget.zone,
          superZone: widget.superZone,
          centers:   widget.centers,
        ),
      ),

      // ── FAB column (right) ────────────────────────────────────────────────
      Positioned(
        bottom: MediaQuery.of(context).padding.bottom + 24,
        right: 12,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Print FAB (also accessible from AppBar)
          _MapFab(
            icon:    Icons.print_outlined,
            tooltip: 'नक्शा प्रिंट करें',
            color:   _kPrimary,
            onTap:   printMap,
          ),
          const SizedBox(height: 8),
          _MapFab(
            icon:    Icons.fit_screen_rounded,
            tooltip: 'सभी केन्द्र दिखाएं',
            onTap:   _fitBounds,
          ),
          const SizedBox(height: 8),
          _MapFab(
            icon:    Icons.info_outline_rounded,
            tooltip: 'रंग संकेत',
            onTap:   () => _showLegend(context),
          ),
        ]),
      ),

      // ── Legend strip (bottom left) ────────────────────────────────────────
      Positioned(
        bottom: MediaQuery.of(context).padding.bottom + 24,
        left: 12,
        child: _LegendStrip(centers: widget.centers),
      ),

      // ── Selected center mini-card (appears above legend after tap) ─────────
      if (_selectedCenter != null)
        Positioned(
          bottom: MediaQuery.of(context).padding.bottom + 90,
          left: 12, right: 60,
          child: _SelectedCenterCard(
            center: _selectedCenter!,
            onTap:  () => _showCenterSheet(_selectedCenter!),
            onClose: () => setState(() => _selectedCenter = null),
          ),
        ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  NEW: Mini card shown at bottom when a marker is tapped
// ══════════════════════════════════════════════════════════════════════════════
class _SelectedCenterCard extends StatelessWidget {
  final Map center;
  final VoidCallback onTap, onClose;
  const _SelectedCenterCard(
      {required this.center, required this.onTap, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final type   = '${center['center_type'] ?? center['centerType'] ?? 'C'}';
    final tColor = _typeColor(type);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tColor.withOpacity(0.4), width: 1.5),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12, offset: const Offset(0, 4))],
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                color: tColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: tColor.withOpacity(0.3))),
            child: Center(child: Text(type,
                style: TextStyle(color: tColor, fontSize: type.length > 1 ? 9 : 14,
                    fontWeight: FontWeight.w900))),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${center['name']}',
                style: const TextStyle(color: _kDark, fontWeight: FontWeight.w700, fontSize: 13),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              [
                _typeLabel(type),
                if ((center['thana'] ?? '').toString().isNotEmpty)
                  'थाना: ${center['thana']}',
              ].join('  •  '),
              style: const TextStyle(color: _kSubtle, fontSize: 10),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
          ])),
          const SizedBox(width: 6),
          Column(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onTap: onClose,
              child: const Icon(Icons.close, size: 16, color: _kSubtle)),
            const SizedBox(height: 6),
            const Icon(Icons.arrow_upward_rounded, size: 14, color: _kPrimary),
          ]),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Center detail bottom sheet
// ══════════════════════════════════════════════════════════════════════════════
class _CenterDetailSheet extends StatelessWidget {
  final Map center;
  const _CenterDetailSheet({required this.center});

  @override
  Widget build(BuildContext context) {
    final type       = '${center['center_type'] ?? center['centerType'] ?? 'C'}';
    final tColor     = _typeColor(type);
    final zone       = center['_zone']      as Map?;
    final sector     = center['_sector']    as Map?;
    final gp         = center['_gp']        as Map?;
    final superZone  = center['_superZone'] as Map?;
    final kendras    = (center['kendras']       as List? ?? []);
    final duty       = (center['duty_officers'] as List? ?? []);
    final szOfficers = (superZone?['officers']  as List? ?? []);
    final zOfficers  = (zone?['officers']       as List? ?? []);
    final sOfficers  = (sector?['officers']     as List? ?? []);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize:     0.35,
      maxChildSize:     0.92,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: _kBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Center(child: Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 44, height: 4,
            decoration: BoxDecoration(color: _kBorder, borderRadius: BorderRadius.circular(2)))),

          // Header
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [tColor, tColor.withOpacity(0.7)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(type,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${center['name']}',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                Text(_typeLabel(type),
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11)),
              ])),
              if ((center['bus_no'] ?? center['busNo'] ?? '').toString().isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.directions_bus_outlined, color: Colors.white, size: 12),
                    const SizedBox(width: 4),
                    Text('${center['bus_no'] ?? center['busNo']}',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ])),
            ])),

          Expanded(child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _SheetSection(
                icon: Icons.account_tree_outlined, title: 'पदानुक्रम', color: _kPrimary,
                child: _LocationChain(
                  superZone: superZone, zone: zone, sector: sector, gp: gp,
                  thana: '${center['thana'] ?? ''}')),
              _SheetSection(
                icon: Icons.how_to_vote_outlined,
                title: 'मतदेय स्थल / मतदान केन्द्र', color: _kGreen,
                child: kendras.isEmpty
                    ? _InfoRow(icon: Icons.how_to_vote_outlined,
                        label: 'मतदान केन्द्र', value: '${center['name']}')
                    : Column(children: [
                        for (int i = 0; i < kendras.length; i++)
                          _KendraRow(no: i + 1, kendra: kendras[i], sthalName: '${center['name']}'),
                      ])),
              if (szOfficers.isNotEmpty)
                _OfficersSection(title: 'सुपर जोन अधिकारी', color: _kPrimary, officers: szOfficers),
              if (zOfficers.isNotEmpty)
                _OfficersSection(title: 'जोनल अधिकारी', color: _kGreen, officers: zOfficers),
              if (sOfficers.isNotEmpty)
                _OfficersSection(title: 'सैक्टर अधिकारी', color: _kOrange, officers: sOfficers),
              _SheetSection(
                icon: Icons.local_police_outlined,
                title: 'ड्यूटी पर तैनात स्टाफ (${duty.length})',
                color: duty.isEmpty ? _kSubtle : _kRed,
                child: duty.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('कोई स्टाफ असाइन नहीं है',
                            style: TextStyle(color: _kSubtle, fontSize: 12)))
                    : Column(children: [
                        for (final d in duty) _DutyOfficerRow(officer: d),
                      ])),
              const SizedBox(height: 20),
            ],
          )),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Reusable sheet sub-widgets  (unchanged from original)
// ══════════════════════════════════════════════════════════════════════════════

class _SheetSection extends StatelessWidget {
  final IconData icon; final String title; final Color color; final Widget child;
  const _SheetSection({required this.icon, required this.title, required this.color, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(color: _kSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _kBorder)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          border: Border(bottom: BorderSide(color: color.withOpacity(0.15)))),
        child: Row(children: [
          Icon(icon, size: 15, color: color), const SizedBox(width: 7),
          Expanded(child: Text(title, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800))),
        ])),
      Padding(padding: const EdgeInsets.all(12), child: child),
    ]));
}

class _LocationChain extends StatelessWidget {
  final Map? superZone, zone, sector, gp; final String thana;
  const _LocationChain({this.superZone, this.zone, this.sector, this.gp, required this.thana});

  @override
  Widget build(BuildContext context) => Column(children: [
    if (superZone != null) _InfoRow(icon: Icons.layers_outlined, label: 'सुपर जोन',
        value: '${superZone!['name']} (ब्लॉक: ${superZone!['block'] ?? '—'})'),
    if (zone     != null) _InfoRow(icon: Icons.map_outlined,             label: 'जोन',         value: '${zone!['name']}'),
    if (sector   != null) _InfoRow(icon: Icons.grid_view_outlined,       label: 'सैक्टर',      value: '${sector!['name']}'),
    if (gp       != null) _InfoRow(icon: Icons.account_balance_outlined, label: 'ग्राम पंचायत', value: '${gp!['name']}'),
    if (thana.isNotEmpty) _InfoRow(icon: Icons.local_police_outlined,    label: 'थाना',        value: thana),
  ]);
}

class _InfoRow extends StatelessWidget {
  final IconData icon; final String label, value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty || value == 'null') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 13, color: _kSubtle), const SizedBox(width: 7),
        SizedBox(width: 90, child: Text(label, style: const TextStyle(color: _kSubtle, fontSize: 11))),
        Expanded(child: Text(value, style: const TextStyle(color: _kDark, fontSize: 11, fontWeight: FontWeight.w600))),
      ]));
  }
}

class _KendraRow extends StatelessWidget {
  final int no; final Map kendra; final String sthalName;
  const _KendraRow({required this.no, required this.kendra, required this.sthalName});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
        color: _kGreen.withOpacity(0.05), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kGreen.withOpacity(0.2))),
    child: Row(children: [
      Container(width: 26, height: 26,
        decoration: BoxDecoration(color: _kGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
        child: Center(child: Text('$no', style: const TextStyle(color: _kGreen, fontSize: 11, fontWeight: FontWeight.w900)))),
      const SizedBox(width: 10),
      Expanded(child: Text('$sthalName कक्ष ${kendra['room_number']}',
          style: const TextStyle(color: _kDark, fontSize: 12, fontWeight: FontWeight.w600))),
    ]));
}

class _OfficersSection extends StatelessWidget {
  final String title; final Color color; final List officers;
  const _OfficersSection({required this.title, required this.color, required this.officers});

  @override
  Widget build(BuildContext context) => _SheetSection(
    icon: Icons.manage_accounts_outlined, title: title, color: color,
    child: Column(children: [for (final o in officers) _OfficerRow(officer: o, color: color)]));
}

class _OfficerRow extends StatelessWidget {
  final Map officer; final Color color;
  const _OfficerRow({required this.officer, required this.color});

  @override
  Widget build(BuildContext context) {
    final name   = '${officer['name']   ?? ''}';
    final rank   = '${officer['user_rank'] ?? officer['rank'] ?? ''}';
    final mobile = '${officer['mobile'] ?? ''}';
    final pno    = '${officer['pno']    ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
          color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.15))),
      child: Row(children: [
        Container(width: 36, height: 36,
          decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
          child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800)))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name.isNotEmpty ? name : '—',
              style: const TextStyle(color: _kDark, fontSize: 12, fontWeight: FontWeight.w700)),
          Text([if (rank.isNotEmpty) rank, if (pno.isNotEmpty) 'PNO: $pno'].join('  •  '),
              style: const TextStyle(color: _kSubtle, fontSize: 10)),
          if (mobile.isNotEmpty) Text(mobile, style: const TextStyle(color: _kSubtle, fontSize: 10)),
        ])),
      ]));
  }
}

class _DutyOfficerRow extends StatelessWidget {
  final Map officer;
  const _DutyOfficerRow({required this.officer});

  @override
  Widget build(BuildContext context) {
    final isArmed = officer['isArmed'] == true ||
        officer['is_armed'] == true || officer['is_armed'] == 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isArmed ? _kRed.withOpacity(0.25) : _kBorder)),
      child: Row(children: [
        Container(width: 34, height: 34,
          decoration: BoxDecoration(
              color: isArmed ? _kRed.withOpacity(0.1) : _kBorder.withOpacity(0.3),
              shape: BoxShape.circle),
          child: Icon(isArmed ? Icons.security : Icons.person_outline,
              size: 16, color: isArmed ? _kRed : _kSubtle)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${officer['name'] ?? '—'}',
                style: const TextStyle(color: _kDark, fontSize: 12, fontWeight: FontWeight.w700))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: (isArmed ? _kRed : _kGreen).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: (isArmed ? _kRed : _kGreen).withOpacity(0.3))),
              child: Text(isArmed ? 'सशस्त्र' : 'निःशस्त्र',
                  style: TextStyle(color: isArmed ? _kRed : _kGreen, fontSize: 9, fontWeight: FontWeight.w700))),
          ]),
          Text(
            [
              if ((officer['user_rank'] ?? '').toString().isNotEmpty) '${officer['user_rank']}',
              if ((officer['pno']       ?? '').toString().isNotEmpty) 'PNO: ${officer['pno']}',
              if ((officer['mobile']    ?? '').toString().isNotEmpty) '${officer['mobile']}',
            ].join('  •  '),
            style: const TextStyle(color: _kSubtle, fontSize: 10)),
        ])),
      ]));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Zone info banner (top of map)  — now scrollable officers row
// ══════════════════════════════════════════════════════════════════════════════
class _ZoneInfoBanner extends StatelessWidget {
  final Map zone, superZone;
  final List<Map> centers;
  const _ZoneInfoBanner({required this.zone, required this.superZone, required this.centers});

  @override
  Widget build(BuildContext context) {
    final zOfficers  = (zone['officers']      as List? ?? []);
    final szOfficers = (superZone['officers'] as List? ?? []);
    final typeCounts = <String, int>{};
    for (final c in centers) {
      final t = '${c['center_type'] ?? c['centerType'] ?? 'C'}';
      typeCounts[t] = (typeCounts[t] ?? 0) + 1;
    }

    return Container(
      decoration: BoxDecoration(
        color: _kDark.withOpacity(0.90),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('जोन: ${zone['name']}',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('सुपर जोन: ${superZone['name']}  •  ब्लॉक: ${superZone['block'] ?? '—'}',
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          const SizedBox(width: 6),
          // Type count chips
          Wrap(spacing: 4, children: [
            for (final e in typeCounts.entries)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: _typeColor(e.key).withOpacity(0.25),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: _typeColor(e.key).withOpacity(0.5))),
                child: Text('${e.key}:${e.value}',
                    style: TextStyle(color: _typeColor(e.key), fontSize: 10, fontWeight: FontWeight.w700))),
          ]),
        ]),
        if (szOfficers.isNotEmpty || zOfficers.isNotEmpty) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 26,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final o in [...szOfficers, ...zOfficers])
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      '${o['name']}  ${o['user_rank'] ?? ''}',
                      style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 10))),
              ],
            ),
          ),
        ],
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Map FAB button  — now accepts optional color
// ══════════════════════════════════════════════════════════════════════════════
class _MapFab extends StatelessWidget {
  final IconData icon; final String tooltip; final VoidCallback onTap;
  final Color? color;
  const _MapFab({required this.icon, required this.tooltip, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: _kSurface, shape: BoxShape.circle,
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8, offset: const Offset(0, 3))]),
        child: Icon(icon, color: color ?? _kPrimary, size: 20)),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  Legend strip (bottom-left of map)
// ══════════════════════════════════════════════════════════════════════════════
class _LegendStrip extends StatelessWidget {
  final List<Map> centers;
  const _LegendStrip({required this.centers});

  @override
  Widget build(BuildContext context) {
    final types   = centers.map((c) => '${c['center_type'] ?? c['centerType'] ?? 'C'}').toSet();
    final order   = ['A++', 'A', 'B', 'C'];
    final visible = order.where(types.contains).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
          color: _kDark.withOpacity(0.85), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10,
                    decoration: BoxDecoration(color: _typeColor(t), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(t, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              ])),
        ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Officer banner (zone list header)
// ══════════════════════════════════════════════════════════════════════════════
class _OfficerBanner extends StatelessWidget {
  final String label; final List officers; final Color color;
  const _OfficerBanner({required this.label, required this.officers, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
    color: color.withOpacity(0.07),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      SizedBox(height: 30, child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final o in officers)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withOpacity(0.3))),
              child: Text('${o['name']}  ${o['user_rank'] ?? ''}',
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600))),
        ])),
    ]));
}

// ══════════════════════════════════════════════════════════════════════════════
//  Drill-down card
// ══════════════════════════════════════════════════════════════════════════════
class _DrillCard extends StatelessWidget {
  final Widget leading; final String title, subtitle;
  final String? badge, extra; final Color color;
  final IconData? trailingIcon; final VoidCallback onTap;
  const _DrillCard({required this.leading, required this.title, required this.subtitle,
      required this.color, required this.onTap, this.badge, this.extra, this.trailingIcon});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kSurface, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: [BoxShadow(color: color.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3))]),
      child: Row(children: [
        leading, const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: _kDark, fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(color: _kSubtle, fontSize: 11)),
          if (extra != null) ...[const SizedBox(height: 2),
            Text(extra!, style: const TextStyle(color: _kSubtle, fontSize: 10))],
          if (badge != null) ...[const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.3))),
              child: Text(badge!, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)))],
        ])),
        Icon(trailingIcon ?? Icons.chevron_right_rounded, color: color.withOpacity(0.6), size: 24),
      ])));
}

// ══════════════════════════════════════════════════════════════════════════════
//  Empty + Error states
// ══════════════════════════════════════════════════════════════════════════════
class _Empty extends StatelessWidget {
  final String text;
  const _Empty({required this.text});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.map_outlined, size: 52, color: _kSubtle),
        const SizedBox(height: 12),
        Text(text, style: const TextStyle(color: _kSubtle, fontSize: 14), textAlign: TextAlign.center),
      ])));
}

class _ErrorView extends StatelessWidget {
  final String error; final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 48, color: _kRed),
        const SizedBox(height: 10),
        const Text('डेटा लोड करने में त्रुटि',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _kDark)),
        const SizedBox(height: 6),
        Text(error, style: const TextStyle(color: _kSubtle, fontSize: 12), textAlign: TextAlign.center),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
          label: const Text('पुनः प्रयास', style: TextStyle(color: Colors.white))),
      ])));
}