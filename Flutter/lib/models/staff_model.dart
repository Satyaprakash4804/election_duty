// ═════════════════════════════════════════════════════════════════════════════
//  staff_model.dart
//
//  Models for staff records, duty assignments, and district duty rows.
//
//  KEY DESIGN:
//  • StaffModel — mirrors `users` table for police personnel.
//  • DutyAssignment — mirrors `duty_assignments` (booth duty) with full
//    election context: electionId, electionName, electionDate.
//  • DistrictDutyAssignment — mirrors `district_duty_assignments`.
//  • OfficerAssignment — shared shape for kshetra/zonal/sector officers.
//  • DutyAssignmentHistory — read-only snapshot from *_history tables.
//  • All models have:
//      - fromJson()    – parse API response
//      - toJson()      – serialize for POST/PUT bodies
//      - copyWith()    – immutable updates
//      - election helpers (isCurrentElection, hasElectionContext)
//
//  ELECTION TAGGING:
//  Every mutable model that represents an assigned record carries:
//    • electionId   — FK to election_configs.id
//    • electionName — denormalized for display without extra API call
//    • electionDate — denormalized date string "YYYY-MM-DD"
//    • assignedBy   — user_id of who made the assignment
// ═════════════════════════════════════════════════════════════════════════════

// ignore_for_file: constant_identifier_names

// ─────────────────────────────────────────────────────────────────────────────
//  StaffModel
//  A police personnel record (role='staff').
//  Used in pickers, lists, bulk-upload previews, and duty cards.
// ─────────────────────────────────────────────────────────────────────────────
class StaffModel {
  final int    id;
  final String name;
  final String pno;
  final String mobile;
  final String userRank;   // 'SI', 'ASI', 'Head Constable', 'Constable', …
  final String district;
  final String thana;
  final bool   isArmed;
  final bool   isActive;

  // ── Election context (present when API joins duty_assignments) ────────────
  /// ID of the election this staff member's current duty is tagged to.
  final int?   electionId;
  final String electionName;
  final String electionDate;

  // ── Duty context (present when staff list endpoint joins duty_assignments) ─
  /// True when this staff has an active duty for the current election.
  final bool   hasDuty;
  final int?   dutySthalId;
  final String dutyCenterName;

  // ── Who assigned ──────────────────────────────────────────────────────────
  final int?   assignedBy;
  final String? createdAt;

  const StaffModel({
    required this.id,
    required this.name,
    required this.pno,
    this.mobile        = '',
    this.userRank      = '',
    this.district      = '',
    this.thana         = '',
    this.isArmed       = false,
    this.isActive      = true,
    // Election context
    this.electionId,
    this.electionName  = '',
    this.electionDate  = '',
    // Duty context
    this.hasDuty       = false,
    this.dutySthalId,
    this.dutyCenterName = '',
    // Meta
    this.assignedBy,
    this.createdAt,
  });

  factory StaffModel.fromJson(Map<String, dynamic> j) => StaffModel(
    id:             _int(j['id']),
    name:           _str(j['name']),
    pno:            _str(j['pno']),
    mobile:         _str(j['mobile']),
    userRank:       _str(j['userRank'] ?? j['user_rank'] ?? j['rank']),
    district:       _str(j['district']),
    thana:          _str(j['thana']),
    isArmed:        _bool(j['isArmed'] ?? j['is_armed']),
    isActive:       _bool(j['isActive'] ?? j['is_active'] ?? true),
    // Election context
    electionId:     j['electionId'] as int?,
    electionName:   _str(j['electionName']),
    electionDate:   _str(j['electionDate']),
    // Duty context
    hasDuty:        _bool(j['hasDuty'] ?? j['has_duty']),
    dutySthalId:    j['dutySthalId'] as int?,
    dutyCenterName: _str(j['dutyCenterName'] ?? j['centerName']),
    // Meta
    assignedBy:     j['assignedBy'] as int?,
    createdAt:      j['createdAt'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id':       id,
    'name':     name,
    'pno':      pno,
    'mobile':   mobile,
    'userRank': userRank,
    'district': district,
    'thana':    thana,
    'isArmed':  isArmed,
    'isActive': isActive,
    if (electionId     != null) 'electionId':     electionId,
    if (electionName.isNotEmpty) 'electionName':  electionName,
    if (electionDate.isNotEmpty) 'electionDate':  electionDate,
    if (dutySthalId    != null) 'dutySthalId':    dutySthalId,
    if (assignedBy     != null) 'assignedBy':     assignedBy,
    if (createdAt      != null) 'createdAt':      createdAt,
  };

  StaffModel copyWith({
    int?    id,
    String? name,
    String? pno,
    String? mobile,
    String? userRank,
    String? district,
    String? thana,
    bool?   isArmed,
    bool?   isActive,
    int?    electionId,
    String? electionName,
    String? electionDate,
    bool?   hasDuty,
    int?    dutySthalId,
    String? dutyCenterName,
    int?    assignedBy,
    String? createdAt,
  }) => StaffModel(
    id:             id             ?? this.id,
    name:           name           ?? this.name,
    pno:            pno            ?? this.pno,
    mobile:         mobile         ?? this.mobile,
    userRank:       userRank       ?? this.userRank,
    district:       district       ?? this.district,
    thana:          thana          ?? this.thana,
    isArmed:        isArmed        ?? this.isArmed,
    isActive:       isActive       ?? this.isActive,
    electionId:     electionId     ?? this.electionId,
    electionName:   electionName   ?? this.electionName,
    electionDate:   electionDate   ?? this.electionDate,
    hasDuty:        hasDuty        ?? this.hasDuty,
    dutySthalId:    dutySthalId    ?? this.dutySthalId,
    dutyCenterName: dutyCenterName ?? this.dutyCenterName,
    assignedBy:     assignedBy     ?? this.assignedBy,
    createdAt:      createdAt      ?? this.createdAt,
  );

  // ── Helpers ───────────────────────────────────────────────────────────────
  bool get hasElectionContext => electionId != null;

  /// Returns true when this staff's duty belongs to the currently active
  /// election (pass the activeElectionId from ActiveElectionStatus).
  bool isCurrentElection(int? activeElectionId) =>
      activeElectionId != null && electionId == activeElectionId;

  /// "पिछले चुनाव की ड्यूटी" vs "इस चुनाव की ड्यूटी"
  DutyElectionState dutyState(int? activeElectionId) {
    if (!hasDuty)                            return DutyElectionState.noDuty;
    if (!hasElectionContext)                  return DutyElectionState.noDuty;
    if (isCurrentElection(activeElectionId)) return DutyElectionState.currentElection;
    return DutyElectionState.previousElection;
  }

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is StaffModel && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'StaffModel(id=$id, $name [$userRank], electionId=$electionId)';
}

// ─────────────────────────────────────────────────────────────────────────────
//  DutyElectionState — used for duty badge coloring in the UI.
// ─────────────────────────────────────────────────────────────────────────────
enum DutyElectionState {
  /// No duty assigned at all.
  noDuty,
  /// Duty assigned in the currently active election.
  currentElection,
  /// Duty was assigned in a past election (needs attention / re-assign).
  previousElection,
}

// ─────────────────────────────────────────────────────────────────────────────
//  DutyAssignment
//  Mirrors `duty_assignments` table — one staff at one booth center.
//  Returned by GET /admin/centers/:id/duties and staff duty endpoints.
// ─────────────────────────────────────────────────────────────────────────────
class DutyAssignment {
  final int    id;
  final int    staffId;
  final int    sthalId;

  // ── Staff snapshot (denormalized for display) ─────────────────────────────
  final String staffName;
  final String staffPno;
  final String staffMobile;
  final String staffRank;
  final String staffDistrict;
  final String staffThana;
  final bool   isArmed;

  // ── Center snapshot ───────────────────────────────────────────────────────
  final String centerName;
  final String centerType;    // 'A++', 'A', 'B', 'C'

  // ── Duty metadata ─────────────────────────────────────────────────────────
  final String busNo;
  final String mode;
  final String electionDate;  // ISO string "YYYY-MM-DD"
  final bool   attended;
  final bool   cardDownloaded;

  // ── Election context ──────────────────────────────────────────────────────
  final int?   electionId;
  final String electionName;

  // ── Who assigned ──────────────────────────────────────────────────────────
  final int?   assignedBy;
  final String? createdAt;

  const DutyAssignment({
    required this.id,
    required this.staffId,
    required this.sthalId,
    this.staffName     = '',
    this.staffPno      = '',
    this.staffMobile   = '',
    this.staffRank     = '',
    this.staffDistrict = '',
    this.staffThana    = '',
    this.isArmed       = false,
    this.centerName    = '',
    this.centerType    = 'C',
    this.busNo         = '',
    this.mode          = '',
    this.electionDate  = '',
    this.attended      = false,
    this.cardDownloaded = false,
    // Election context
    this.electionId,
    this.electionName  = '',
    // Meta
    this.assignedBy,
    this.createdAt,
  });

  factory DutyAssignment.fromJson(Map<String, dynamic> j) => DutyAssignment(
    id:             _int(j['id']),
    staffId:        _int(j['staffId'] ?? j['staff_id']),
    sthalId:        _int(j['sthalId'] ?? j['sthal_id']),
    staffName:      _str(j['staffName']     ?? j['name']),
    staffPno:       _str(j['staffPno']      ?? j['pno']),
    staffMobile:    _str(j['staffMobile']   ?? j['mobile']),
    staffRank:      _str(j['staffRank']     ?? j['userRank'] ?? j['user_rank'] ?? j['rank']),
    staffDistrict:  _str(j['staffDistrict'] ?? j['district']),
    staffThana:     _str(j['staffThana']    ?? j['thana']),
    isArmed:        _bool(j['isArmed']      ?? j['is_armed']),
    centerName:     _str(j['centerName']    ?? j['center_name']),
    centerType:     _str(j['centerType']    ?? j['center_type'], 'C'),
    busNo:          _str(j['busNo']         ?? j['bus_no']),
    mode:           _str(j['mode']),
    electionDate:   _str(j['electionDate']  ?? j['election_date']),
    attended:       _bool(j['attended']),
    cardDownloaded: _bool(j['cardDownloaded'] ?? j['card_downloaded']),
    // Election context
    electionId:     j['electionId'] as int?,
    electionName:   _str(j['electionName']),
    // Meta
    assignedBy:     j['assignedBy'] as int?,
    createdAt:      j['createdAt'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id':             id,
    'staffId':        staffId,
    'sthalId':        sthalId,
    'busNo':          busNo,
    'mode':           mode,
    'electionDate':   electionDate,
    'attended':       attended,
    'cardDownloaded': cardDownloaded,
    if (electionId    != null) 'electionId':  electionId,
    if (assignedBy    != null) 'assignedBy':  assignedBy,
  };

  DutyAssignment copyWith({
    int?    id,
    int?    staffId,
    int?    sthalId,
    String? staffName,
    String? staffPno,
    String? staffMobile,
    String? staffRank,
    String? staffDistrict,
    String? staffThana,
    bool?   isArmed,
    String? centerName,
    String? centerType,
    String? busNo,
    String? mode,
    String? electionDate,
    bool?   attended,
    bool?   cardDownloaded,
    int?    electionId,
    String? electionName,
    int?    assignedBy,
    String? createdAt,
  }) => DutyAssignment(
    id:             id             ?? this.id,
    staffId:        staffId        ?? this.staffId,
    sthalId:        sthalId        ?? this.sthalId,
    staffName:      staffName      ?? this.staffName,
    staffPno:       staffPno       ?? this.staffPno,
    staffMobile:    staffMobile    ?? this.staffMobile,
    staffRank:      staffRank      ?? this.staffRank,
    staffDistrict:  staffDistrict  ?? this.staffDistrict,
    staffThana:     staffThana     ?? this.staffThana,
    isArmed:        isArmed        ?? this.isArmed,
    centerName:     centerName     ?? this.centerName,
    centerType:     centerType     ?? this.centerType,
    busNo:          busNo          ?? this.busNo,
    mode:           mode           ?? this.mode,
    electionDate:   electionDate   ?? this.electionDate,
    attended:       attended       ?? this.attended,
    cardDownloaded: cardDownloaded ?? this.cardDownloaded,
    electionId:     electionId     ?? this.electionId,
    electionName:   electionName   ?? this.electionName,
    assignedBy:     assignedBy     ?? this.assignedBy,
    createdAt:      createdAt      ?? this.createdAt,
  );

  bool get hasElectionContext => electionId != null;
  bool isCurrentElection(int? activeElectionId) =>
      activeElectionId != null && electionId == activeElectionId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is DutyAssignment && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

// ─────────────────────────────────────────────────────────────────────────────
//  DistrictDutyAssignment
//  Mirrors `district_duty_assignments` — one staff assigned to a district-level
//  duty type (cluster_mobile, thana_mobile, evm_security, etc.).
// ─────────────────────────────────────────────────────────────────────────────
class DistrictDutyAssignment {
  final int    id;
  final int    adminId;
  final int    staffId;
  final String dutyType;
  final String dutyLabelHi;
  final int    batchNo;
  final String busNo;
  final String note;

  // ── Staff snapshot ────────────────────────────────────────────────────────
  final String staffName;
  final String staffPno;
  final String staffMobile;
  final String staffRank;
  final String staffDistrict;
  final String staffThana;
  final bool   isArmed;

  // ── Election context ──────────────────────────────────────────────────────
  final int?   electionId;
  final String electionName;
  final String electionDate;

  // ── Who assigned ──────────────────────────────────────────────────────────
  final int?   assignedBy;
  final String? createdAt;

  const DistrictDutyAssignment({
    required this.id,
    required this.adminId,
    required this.staffId,
    required this.dutyType,
    this.dutyLabelHi  = '',
    this.batchNo      = 1,
    this.busNo        = '',
    this.note         = '',
    this.staffName    = '',
    this.staffPno     = '',
    this.staffMobile  = '',
    this.staffRank    = '',
    this.staffDistrict = '',
    this.staffThana   = '',
    this.isArmed      = false,
    // Election context
    this.electionId,
    this.electionName  = '',
    this.electionDate  = '',
    // Meta
    this.assignedBy,
    this.createdAt,
  });

  factory DistrictDutyAssignment.fromJson(Map<String, dynamic> j) =>
      DistrictDutyAssignment(
    id:            _int(j['id']),
    adminId:       _int(j['adminId']   ?? j['admin_id']),
    staffId:       _int(j['staffId']   ?? j['staff_id']),
    dutyType:      _str(j['dutyType']  ?? j['duty_type']),
    dutyLabelHi:   _str(j['dutyLabelHi'] ?? j['duty_label_hi']),
    batchNo:       _int(j['batchNo']   ?? j['batch_no'], 1),
    busNo:         _str(j['busNo']     ?? j['bus_no']),
    note:          _str(j['note']),
    staffName:     _str(j['staffName']    ?? j['name']),
    staffPno:      _str(j['staffPno']     ?? j['pno']),
    staffMobile:   _str(j['staffMobile']  ?? j['mobile']),
    staffRank:     _str(j['staffRank']    ?? j['userRank'] ?? j['user_rank'] ?? j['rank']),
    staffDistrict: _str(j['staffDistrict'] ?? j['district']),
    staffThana:    _str(j['staffThana']   ?? j['thana']),
    isArmed:       _bool(j['isArmed']     ?? j['is_armed']),
    // Election context
    electionId:    j['electionId'] as int?,
    electionName:  _str(j['electionName']),
    electionDate:  _str(j['electionDate']),
    // Meta
    assignedBy:    j['assignedBy'] as int?,
    createdAt:     j['createdAt'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id':         id,
    'adminId':    adminId,
    'staffId':    staffId,
    'dutyType':   dutyType,
    'dutyLabelHi':dutyLabelHi,
    'batchNo':    batchNo,
    'busNo':      busNo,
    'note':       note,
    if (electionId != null) 'electionId': electionId,
    if (assignedBy != null) 'assignedBy': assignedBy,
  };

  bool get hasElectionContext => electionId != null;
  bool isCurrentElection(int? activeElectionId) =>
      activeElectionId != null && electionId == activeElectionId;
}

// ─────────────────────────────────────────────────────────────────────────────
//  OfficerAssignment
//  Shared shape for kshetra_officers, zonal_officers, sector_officers.
//  The `level` field distinguishes which table it came from.
// ─────────────────────────────────────────────────────────────────────────────
enum OfficerLevel { kshetra, zonal, sector }

class OfficerAssignment {
  final int          id;
  final OfficerLevel level;

  // ── Hierarchy IDs ─────────────────────────────────────────────────────────
  final int?   superZoneId;
  final String superZoneName;
  final int?   zoneId;
  final String zoneName;
  final int?   sectorId;
  final String sectorName;

  // ── Officer details ───────────────────────────────────────────────────────
  final int?   userId;
  final String name;
  final String pno;
  final String mobile;
  final String userRank;

  // ── Election context ──────────────────────────────────────────────────────
  final int?   electionId;
  final String electionName;
  final String electionDate;

  // ── Who assigned ──────────────────────────────────────────────────────────
  final int?   assignedBy;
  final String? createdAt;

  const OfficerAssignment({
    required this.id,
    required this.level,
    this.superZoneId,
    this.superZoneName = '',
    this.zoneId,
    this.zoneName      = '',
    this.sectorId,
    this.sectorName    = '',
    this.userId,
    this.name          = '',
    this.pno           = '',
    this.mobile        = '',
    this.userRank      = '',
    // Election context
    this.electionId,
    this.electionName  = '',
    this.electionDate  = '',
    // Meta
    this.assignedBy,
    this.createdAt,
  });

  factory OfficerAssignment.fromJson(
      Map<String, dynamic> j, OfficerLevel level) =>
      OfficerAssignment(
    id:            _int(j['id']),
    level:         level,
    superZoneId:   j['superZoneId'] as int?,
    superZoneName: _str(j['superZoneName']),
    zoneId:        j['zoneId'] as int?,
    zoneName:      _str(j['zoneName']),
    sectorId:      j['sectorId'] as int?,
    sectorName:    _str(j['sectorName']),
    userId:        j['userId'] as int?,
    name:          _str(j['name']),
    pno:           _str(j['pno']),
    mobile:        _str(j['mobile']),
    userRank:      _str(j['userRank'] ?? j['user_rank'] ?? j['rank']),
    // Election context
    electionId:    j['electionId'] as int?,
    electionName:  _str(j['electionName']),
    electionDate:  _str(j['electionDate']),
    // Meta
    assignedBy:    j['assignedBy'] as int?,
    createdAt:     j['createdAt'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id':       id,
    'userId':   userId,
    'name':     name,
    'pno':      pno,
    'mobile':   mobile,
    'userRank': userRank,
    if (superZoneId != null) 'superZoneId': superZoneId,
    if (zoneId      != null) 'zoneId':      zoneId,
    if (sectorId    != null) 'sectorId':    sectorId,
    if (electionId  != null) 'electionId':  electionId,
    if (assignedBy  != null) 'assignedBy':  assignedBy,
  };

  bool get hasElectionContext => electionId != null;
  bool isCurrentElection(int? activeElectionId) =>
      activeElectionId != null && electionId == activeElectionId;

  String get levelLabel {
    switch (level) {
      case OfficerLevel.kshetra: return 'क्षेत्र अधिकारी';
      case OfficerLevel.zonal:   return 'जोनल अधिकारी';
      case OfficerLevel.sector:  return 'सेक्टर अधिकारी';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DutyAssignmentHistory
//  Read-only snapshot from duty_assignments_history.
//  Returned by GET /admin/election/history/:electionId/booth-duties
// ─────────────────────────────────────────────────────────────────────────────
class DutyAssignmentHistory {
  final int    id;            // history row id (BIGINT)
  final int    originalId;    // original duty_assignments.id
  final int    electionId;
  final String electionName;
  final String district;
  final int    adminId;

  // ── Staff snapshot ────────────────────────────────────────────────────────
  final int    staffId;
  final String staffName;
  final String staffPno;
  final String staffMobile;
  final String staffRank;
  final String staffDistrict;
  final String staffThana;
  final bool   isArmed;

  // ── Center snapshot ───────────────────────────────────────────────────────
  final int    sthalId;
  final String centerName;
  final String centerType;

  // ── Duty metadata ─────────────────────────────────────────────────────────
  final String busNo;
  final String electionDate;
  final bool   attended;
  final bool   cardDownloaded;

  // ── Archive metadata ──────────────────────────────────────────────────────
  final int?   assignedBy;
  final String? originalCreatedAt;
  final String? archivedAt;

  const DutyAssignmentHistory({
    required this.id,
    required this.originalId,
    required this.electionId,
    required this.electionName,
    required this.district,
    required this.adminId,
    required this.staffId,
    this.staffName      = '',
    this.staffPno       = '',
    this.staffMobile    = '',
    this.staffRank      = '',
    this.staffDistrict  = '',
    this.staffThana     = '',
    this.isArmed        = false,
    required this.sthalId,
    this.centerName     = '',
    this.centerType     = 'C',
    this.busNo          = '',
    this.electionDate   = '',
    this.attended       = false,
    this.cardDownloaded = false,
    this.assignedBy,
    this.originalCreatedAt,
    this.archivedAt,
  });

  factory DutyAssignmentHistory.fromJson(Map<String, dynamic> j) =>
      DutyAssignmentHistory(
    id:                 _int(j['id']),
    originalId:         _int(j['originalId']  ?? j['original_id']),
    electionId:         _int(j['electionId']  ?? j['election_id']),
    electionName:       _str(j['electionName']),
    district:           _str(j['district']),
    adminId:            _int(j['adminId']     ?? j['admin_id']),
    staffId:            _int(j['staffId']     ?? j['staff_id']),
    staffName:          _str(j['staffName']   ?? j['name']),
    staffPno:           _str(j['staffPno']    ?? j['pno']),
    staffMobile:        _str(j['staffMobile'] ?? j['mobile']),
    staffRank:          _str(j['staffRank']   ?? j['userRank'] ?? j['user_rank'] ?? j['rank']),
    staffDistrict:      _str(j['staffDistrict'] ?? j['district']),
    staffThana:         _str(j['staffThana']  ?? j['thana']),
    isArmed:            _bool(j['isArmed']    ?? j['is_armed']),
    sthalId:            _int(j['sthalId']     ?? j['sthal_id']),
    centerName:         _str(j['centerName']),
    centerType:         _str(j['centerType'], 'C'),
    busNo:              _str(j['busNo']       ?? j['bus_no']),
    electionDate:       _str(j['electionDate']),
    attended:           _bool(j['attended']),
    cardDownloaded:     _bool(j['cardDownloaded'] ?? j['card_downloaded']),
    assignedBy:         j['assignedBy'] as int?,
    originalCreatedAt:  j['originalCreatedAt'] as String?,
    archivedAt:         j['archivedAt'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is DutyAssignmentHistory && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

// ─────────────────────────────────────────────────────────────────────────────
//  DistrictDutyHistory
//  Read-only snapshot from district_duty_history.
// ─────────────────────────────────────────────────────────────────────────────
class DistrictDutyHistory {
  final int    id;
  final int    originalId;
  final int    electionId;
  final String electionName;
  final String district;
  final int    adminId;

  final int    staffId;
  final String staffName;
  final String staffPno;
  final String staffMobile;
  final String staffRank;
  final String staffDistrict;
  final String staffThana;
  final bool   isArmed;

  final String dutyType;
  final String dutyLabelHi;
  final int    batchNo;
  final String busNo;
  final String note;
  final String electionDate;

  final int?   assignedBy;
  final String? originalCreatedAt;
  final String? archivedAt;

  const DistrictDutyHistory({
    required this.id,
    required this.originalId,
    required this.electionId,
    required this.electionName,
    required this.district,
    required this.adminId,
    required this.staffId,
    this.staffName     = '',
    this.staffPno      = '',
    this.staffMobile   = '',
    this.staffRank     = '',
    this.staffDistrict = '',
    this.staffThana    = '',
    this.isArmed       = false,
    required this.dutyType,
    this.dutyLabelHi   = '',
    this.batchNo       = 1,
    this.busNo         = '',
    this.note          = '',
    this.electionDate  = '',
    this.assignedBy,
    this.originalCreatedAt,
    this.archivedAt,
  });

  factory DistrictDutyHistory.fromJson(Map<String, dynamic> j) =>
      DistrictDutyHistory(
    id:                _int(j['id']),
    originalId:        _int(j['originalId']  ?? j['original_id']),
    electionId:        _int(j['electionId']  ?? j['election_id']),
    electionName:      _str(j['electionName']),
    district:          _str(j['district']),
    adminId:           _int(j['adminId']     ?? j['admin_id']),
    staffId:           _int(j['staffId']     ?? j['staff_id']),
    staffName:         _str(j['staffName']   ?? j['name']),
    staffPno:          _str(j['staffPno']    ?? j['pno']),
    staffMobile:       _str(j['staffMobile'] ?? j['mobile']),
    staffRank:         _str(j['staffRank']   ?? j['userRank'] ?? j['user_rank'] ?? j['rank']),
    staffDistrict:     _str(j['staffDistrict']),
    staffThana:        _str(j['staffThana']  ?? j['thana']),
    isArmed:           _bool(j['isArmed']    ?? j['is_armed']),
    dutyType:          _str(j['dutyType']    ?? j['duty_type']),
    dutyLabelHi:       _str(j['dutyLabelHi'] ?? j['duty_label_hi']),
    batchNo:           _int(j['batchNo']     ?? j['batch_no'], 1),
    busNo:             _str(j['busNo']       ?? j['bus_no']),
    note:              _str(j['note']),
    electionDate:      _str(j['electionDate']),
    assignedBy:        j['assignedBy'] as int?,
    originalCreatedAt: j['originalCreatedAt'] as String?,
    archivedAt:        j['archivedAt'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is DistrictDutyHistory && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Private parse helpers — handle int/String/bool coercions from MySQL JSON.
// ─────────────────────────────────────────────────────────────────────────────
int _int(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}

String _str(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  return v.toString().trim();
}

bool _bool(dynamic v, [bool fallback = false]) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is int) return v == 1;
  final s = v.toString().toLowerCase().trim();
  return s == '1' || s == 'true' || s == 'yes';
}