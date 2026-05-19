// ═════════════════════════════════════════════════════════════════════════════
//  user_model.dart
//
//  Canonical model for an authenticated user / any user record returned
//  by the backend.
//
//  KEY DESIGN:
//  • Every field maps 1-to-1 with the `users` DB table + login response.
//  • Election context fields (electionId / electionName / electionDate) are
//    optional — they appear only on endpoints that join with election_configs.
//  • Immutable (all fields final). Use copyWith() for in-place updates.
//  • Helpers: roleLevel, isMaster, isAdmin, etc. — used for role-gating UI.
//  • ElectionContext is a separate lightweight model returned alongside the
//    user on finalize-status / duty-assignment APIs. Keeps UserModel clean.
// ═════════════════════════════════════════════════════════════════════════════

// ignore_for_file: constant_identifier_names

/// Canonical role strings — match backend ENUM exactly.
abstract class UserRole {
  static const master      = 'master';
  static const superAdmin  = 'super_admin';
  static const admin       = 'admin';
  static const staff       = 'staff';

  /// Ordered lowest → highest privilege.
  static const _hierarchy = [staff, admin, superAdmin, master];

  /// Returns 0 (staff) … 3 (master). Returns -1 for unknown.
  static int level(String role) => _hierarchy.indexOf(role.toLowerCase());

  static bool atLeast(String role, String minimum) =>
      level(role) >= level(minimum);
}

// ─────────────────────────────────────────────────────────────────────────────
//  ElectionContext
//  Lightweight snapshot of an election config, attached to API responses
//  wherever election_id is joined in (finalize/status, duty lists, etc.).
// ─────────────────────────────────────────────────────────────────────────────
class ElectionContext {
  final int    id;
  final String district;
  final String electionName;
  final String electionType;
  final String phase;
  final String electionDate;   // ISO date string "YYYY-MM-DD"
  final String pratahSamay;
  final String sayaSamay;
  final bool   isFinalized;
  final bool   autoFinalized;
  final String? finalizedAt;

  const ElectionContext({
    required this.id,
    required this.district,
    required this.electionName,
    required this.electionType,
    required this.phase,
    required this.electionDate,
    required this.pratahSamay,
    required this.sayaSamay,
    required this.isFinalized,
    required this.autoFinalized,
    this.finalizedAt,
  });

  factory ElectionContext.fromJson(Map<String, dynamic> j) => ElectionContext(
    id:            _int(j['id']),
    district:      _str(j['district']),
    electionName:  _str(j['electionName']),
    electionType:  _str(j['electionType']),
    phase:         _str(j['phase']),
    electionDate:  _str(j['electionDate']),
    pratahSamay:   _str(j['pratahSamay']),
    sayaSamay:     _str(j['sayaSamay']),
    isFinalized:   _bool(j['isFinalized']),
    autoFinalized: _bool(j['autoFinalized']),
    finalizedAt:   j['finalizedAt'] as String?,
  );

  /// Try to parse from a Map that may be null. Returns null if j is null.
  static ElectionContext? tryFromJson(dynamic j) {
    if (j == null || j is! Map<String, dynamic>) return null;
    return ElectionContext.fromJson(j);
  }

  Map<String, dynamic> toJson() => {
    'id':            id,
    'district':      district,
    'electionName':  electionName,
    'electionType':  electionType,
    'phase':         phase,
    'electionDate':  electionDate,
    'pratahSamay':   pratahSamay,
    'sayaSamay':     sayaSamay,
    'isFinalized':   isFinalized,
    'autoFinalized': autoFinalized,
    if (finalizedAt != null) 'finalizedAt': finalizedAt,
  };

  /// "विधान सभा निर्वाचन — द्वितीय चरण"
  String get displayLabel =>
      phase.isNotEmpty ? '$electionName — $phase' : electionName;

  /// True when election date has already passed (client-side hint only;
  /// backend is the source of truth for finalization).
  bool get isPast {
    if (electionDate.isEmpty) return false;
    final d = DateTime.tryParse(electionDate);
    if (d == null) return false;
    return DateTime.now().isAfter(d.add(const Duration(days: 1)));
  }

  @override
  String toString() => 'ElectionContext(id=$id, $electionName, '
      'finalized=$isFinalized, auto=$autoFinalized)';
}

// ─────────────────────────────────────────────────────────────────────────────
//  ActiveElectionStatus
//  Returned by GET /admin/election/finalize/status
//  and GET /master/elections/status-summary (per district entry).
// ─────────────────────────────────────────────────────────────────────────────
enum ElectionStatus {
  /// An election is active and no duty actions are blocked.
  active,
  /// Election date has passed; auto-finalization has moved duties to history.
  autoFinalized,
  /// Admin/master manually finalized before election date.
  manuallyFinalized,
  /// No election_config row exists for this district.
  notConfigured,
}

class ActiveElectionStatus {
  final ElectionStatus status;
  final ElectionContext? election;    // null when notConfigured
  final bool alreadyFinalized;       // legacy compat field from backend
  final String? message;             // optional backend message

  const ActiveElectionStatus({
    required this.status,
    this.election,
    this.alreadyFinalized = false,
    this.message,
  });

  factory ActiveElectionStatus.fromJson(Map<String, dynamic> j) {
    // Backend shape: { success, data: { isFinalized, autoFinalized,
    //   alreadyFinalized, electionId, electionName, electionDate, ... } }
    final d = j['data'] as Map<String, dynamic>? ?? j;

    final isFinalized    = _bool(d['isFinalized']) || _bool(d['alreadyFinalized']);
    final autoFinalized  = _bool(d['autoFinalized']);
    final hasElection    = d['electionId'] != null || d['id'] != null;

    ElectionStatus st;
    if (!hasElection) {
      st = ElectionStatus.notConfigured;
    } else if (isFinalized && autoFinalized) {
      st = ElectionStatus.autoFinalized;
    } else if (isFinalized) {
      st = ElectionStatus.manuallyFinalized;
    } else {
      st = ElectionStatus.active;
    }

    // Build ElectionContext from the flattened or nested data.
    ElectionContext? ctx;
    if (hasElection) {
      ctx = ElectionContext.fromJson({
        'id':            d['electionId'] ?? d['id'] ?? 0,
        'district':      d['district']   ?? '',
        'electionName':  d['electionName'] ?? '',
        'electionType':  d['electionType'] ?? '',
        'phase':         d['phase']        ?? '',
        'electionDate':  d['electionDate'] ?? '',
        'pratahSamay':   d['pratahSamay']  ?? '',
        'sayaSamay':     d['sayaSamay']    ?? '',
        'isFinalized':   isFinalized,
        'autoFinalized': autoFinalized,
        'finalizedAt':   d['finalizedAt'],
      });
    }

    return ActiveElectionStatus(
      status:          st,
      election:        ctx,
      alreadyFinalized: _bool(d['alreadyFinalized']),
      message:         d['message'] as String?,
    );
  }

  bool get isActive           => status == ElectionStatus.active;
  bool get isFinalized        => status == ElectionStatus.autoFinalized ||
                                  status == ElectionStatus.manuallyFinalized;
  bool get isAutoFinalized    => status == ElectionStatus.autoFinalized;
  bool get isNotConfigured    => status == ElectionStatus.notConfigured;

  /// True → any mutation (duty assign / manak save / officer assign) is BLOCKED.
  bool get isMutationBlocked  => isFinalized || isNotConfigured;

  int?    get electionId   => election?.id;
  String  get electionName => election?.electionName ?? '';
  String  get electionDate => election?.electionDate ?? '';
  String  get district     => election?.district     ?? '';

  @override
  String toString() =>
      'ActiveElectionStatus(status=$status, election=$election)';
}

// ─────────────────────────────────────────────────────────────────────────────
//  UserModel
//  Maps the `users` table + login response + any joined election data.
// ─────────────────────────────────────────────────────────────────────────────
class UserModel {
  // ── Identity ─────────────────────────────────────────────────────────────
  final int    id;
  final String name;
  final String username;
  final String mobile;
  final String role;          // see UserRole constants

  // ── Police-specific ───────────────────────────────────────────────────────
  final String  pno;          // badge / personnel number (unique)
  final String  userRank;     // 'SI', 'ASI', 'Head Constable', etc.
  final bool    isArmed;

  // ── Geographic scope ──────────────────────────────────────────────────────
  final String district;
  final String thana;

  // ── Account state ─────────────────────────────────────────────────────────
  final bool   isActive;

  // ── Hierarchy linkage (nullable — not always present) ─────────────────────
  final int?   createdBy;
  final int?   assignedBy;
  final int?   superAdminId;

  // ── Timestamps ────────────────────────────────────────────────────────────
  final String? createdAt;
  final String? updatedAt;

  // ── Election context (optional — present when joined with election_configs) ─
  /// The election this user's duty / action is tagged to.
  final int?    electionId;
  final String  electionName;
  /// ISO date "YYYY-MM-DD" when this duty/action's election was held.
  final String  electionDate;

  const UserModel({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
    this.mobile       = '',
    this.pno          = '',
    this.userRank     = '',
    this.isArmed      = false,
    this.district     = '',
    this.thana        = '',
    this.isActive     = true,
    this.createdBy,
    this.assignedBy,
    this.superAdminId,
    this.createdAt,
    this.updatedAt,
    // Election context
    this.electionId,
    this.electionName = '',
    this.electionDate = '',
  });

  // ── JSON deserialization ──────────────────────────────────────────────────
  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
    id:            _int(j['id']),
    name:          _str(j['name']),
    username:      _str(j['username']),
    role:          _str(j['role']).toLowerCase(),
    mobile:        _str(j['mobile']),
    pno:           _str(j['pno']),
    userRank:      _str(j['userRank'] ?? j['user_rank']),
    isArmed:       _bool(j['isArmed'] ?? j['is_armed']),
    district:      _str(j['district']),
    thana:         _str(j['thana']),
    isActive:      _bool(j['isActive'] ?? j['is_active'] ?? true),
    createdBy:     j['createdBy']    as int?,
    assignedBy:    j['assignedBy']   as int?,
    superAdminId:  j['superAdminId'] as int?,
    createdAt:     j['createdAt']    as String?,
    updatedAt:     j['updatedAt']    as String?,
    // ── Election context ──────────────────────────────────────────────────
    electionId:    j['electionId']   as int?,
    electionName:  _str(j['electionName']),
    electionDate:  _str(j['electionDate']),
  );

  // ── JSON serialization ───────────────────────────────────────────────────
  Map<String, dynamic> toJson() => {
    'id':           id,
    'name':         name,
    'username':     username,
    'role':         role,
    'mobile':       mobile,
    'pno':          pno,
    'userRank':     userRank,
    'isArmed':      isArmed,
    'district':     district,
    'thana':        thana,
    'isActive':     isActive,
    if (createdBy   != null) 'createdBy':   createdBy,
    if (assignedBy  != null) 'assignedBy':  assignedBy,
    if (superAdminId!= null) 'superAdminId':superAdminId,
    if (createdAt   != null) 'createdAt':   createdAt,
    if (updatedAt   != null) 'updatedAt':   updatedAt,
    if (electionId  != null) 'electionId':  electionId,
    if (electionName.isNotEmpty) 'electionName': electionName,
    if (electionDate.isNotEmpty) 'electionDate': electionDate,
  };

  // ── copyWith ──────────────────────────────────────────────────────────────
  UserModel copyWith({
    int?    id,
    String? name,
    String? username,
    String? role,
    String? mobile,
    String? pno,
    String? userRank,
    bool?   isArmed,
    String? district,
    String? thana,
    bool?   isActive,
    int?    createdBy,
    int?    assignedBy,
    int?    superAdminId,
    String? createdAt,
    String? updatedAt,
    int?    electionId,
    String? electionName,
    String? electionDate,
  }) => UserModel(
    id:            id            ?? this.id,
    name:          name          ?? this.name,
    username:      username      ?? this.username,
    role:          role          ?? this.role,
    mobile:        mobile        ?? this.mobile,
    pno:           pno           ?? this.pno,
    userRank:      userRank      ?? this.userRank,
    isArmed:       isArmed       ?? this.isArmed,
    district:      district      ?? this.district,
    thana:         thana         ?? this.thana,
    isActive:      isActive      ?? this.isActive,
    createdBy:     createdBy     ?? this.createdBy,
    assignedBy:    assignedBy    ?? this.assignedBy,
    superAdminId:  superAdminId  ?? this.superAdminId,
    createdAt:     createdAt     ?? this.createdAt,
    updatedAt:     updatedAt     ?? this.updatedAt,
    electionId:    electionId    ?? this.electionId,
    electionName:  electionName  ?? this.electionName,
    electionDate:  electionDate  ?? this.electionDate,
  );

  // ── Role helpers ─────────────────────────────────────────────────────────
  bool get isMaster     => role == UserRole.master;
  bool get isSuperAdmin => role == UserRole.superAdmin;
  bool get isAdmin      => role == UserRole.admin;
  bool get isStaff      => role == UserRole.staff;

  /// True for roles that have an admin panel (master / super_admin / admin).
  bool get hasAdminAccess =>
      UserRole.atLeast(role, UserRole.admin);

  /// True for roles that can manage other admins (master / super_admin).
  bool get canManageAdmins =>
      UserRole.atLeast(role, UserRole.superAdmin);

  // ── Election helpers ──────────────────────────────────────────────────────
  /// True when this user/duty record carries an election tag.
  bool get hasElectionContext => electionId != null;

  /// Checks whether this record's electionId matches the active one.
  bool isCurrentElection(int? activeElectionId) =>
      activeElectionId != null && electionId == activeElectionId;

  // ── Display helpers ───────────────────────────────────────────────────────
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  String get displayRole {
    switch (role) {
      case UserRole.master:     return 'Master Admin';
      case UserRole.superAdmin: return 'Super Admin';
      case UserRole.admin:      return 'Admin';
      case UserRole.staff:      return 'Staff';
      default:                  return role;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is UserModel && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'UserModel(id=$id, $username [$role], district=$district)';
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