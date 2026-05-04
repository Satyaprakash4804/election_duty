import api from './client';

// ── AUTH ──────────────────────────────────────────────────────────────────────
export const authApi = {
  login: (pno, password) =>
    api.post('/auth/login', { pno, password, platform: 'web' }),
  logout: () => api.post('/auth/logout'),
  me: () => api.get('/auth/me'),
};

// ── ADMIN ─────────────────────────────────────────────────────────────────────
export const adminApi = {
  // Dashboard
  overview: () => api.get('/admin/overview'),
  getRules: (sensitivity) =>
    api.get(`/admin/rules?sensitivity=${encodeURIComponent(sensitivity)}`),
  saveRules: (sensitivity, rules) =>
    api.post('/admin/rules', { sensitivity, rules }),

  // Staff
  getStaff: (params) => api.get('/admin/staff', { params }),
  addStaff: (data) => api.post('/admin/staff', data),
  updateStaff: (id, data) => api.put(`/admin/staff/${id}`, data),
  deleteStaff: (id) => api.delete(`/admin/staff/${id}`),
  bulkUpload: (formData) =>
    api.post('/admin/staff/bulk', formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    }),

  // Super Zones (Structure)
  getSuperZones: (params) => api.get('/admin/super-zones', { params }),
  addSuperZone: (data) => api.post('/admin/super-zones', data),
  updateSuperZone: (id, data) => api.put(`/admin/super-zones/${id}`, data),
  deleteSuperZone: (id) => api.delete(`/admin/super-zones/${id}`),
  getSuperZoneOfficers: (id) => api.get(`/admin/super-zones/${id}/officers`),

  // Zones
  getZones: (superZoneId, params) =>
    api.get(`/admin/super-zones/${superZoneId}/zones`, { params }),
  addZone: (superZoneId, data) =>
    api.post(`/admin/super-zones/${superZoneId}/zones`, data),
  updateZone: (id, data) => api.put(`/admin/zones/${id}`, data),
  deleteZone: (id) => api.delete(`/admin/zones/${id}`),

  // Sectors
  getSectors: (zoneId, params) =>
    api.get(`/admin/zones/${zoneId}/sectors`, { params }),
  addSector: (zoneId, data) =>
    api.post(`/admin/zones/${zoneId}/sectors`, data),
  updateSector: (id, data) => api.put(`/admin/sectors/${id}`, data),
  deleteSector: (id) => api.delete(`/admin/sectors/${id}`),

  // Duties
  getDuties: (params) => api.get('/admin/duties', { params }),
  getDutyCard: (id) => api.get(`/admin/duties/${id}`),
  assignDuty: (data) => api.post('/admin/duties', data),
  removeAssignment: (dutyId) => api.delete(`/admin/duties/${dutyId}`),

  // Booths / Centers
  getCenters: (params) => api.get('/admin/centers/all', { params }),
  addCenter: (data) => api.post('/admin/centers', data),
  updateCenter: (id, data) => api.put(`/admin/centers/${id}`, data),
  deleteCenter: (id) => api.delete(`/admin/centers/${id}`),

  // Hierarchy
  getHierarchy: () => api.get('/admin/hierarchy/report'),

  getBoothRules: () => api.get('/admin/booth-rules'),
  getDistrictRules: () => api.get('/admin/district-rules'),
  saveBoothRules: (sensitivity, rules) =>
    api.post('/admin/booth-rules', { sensitivity, rules }),

  startAssignJob: (szId) =>
    api.post(`/admin/assign/start/${szId}`, {}),
  getAssignJobStatus: (jobId) =>
    api.get(`/admin/assign/status/${jobId}`),
  refreshDuties: (szId) =>
    api.post(`/admin/refresh/${szId}`, {}),


  lockSuperZone: (szId, reason = '') =>
    api.post(`/admin/lock/${szId}`, { reason }),
  requestUnlock: (superZoneId, reason) =>
    api.post('/admin/unlock/request', { superZoneId, reason }),

  getCenterStaff: (centerId) =>
    api.get(`/admin/center/${centerId}/staff`),

  swapStaff: (removeStaffId, addStaffId, centerId) =>
    api.post('/admin/swap', { removeStaffId, addStaffId, centerId }),

  getCenterRooms: (centerId) =>
    api.get(`/admin/centers/${centerId}/rooms`),

  addCenterRoom: (centerId, roomNumber) =>
    api.post(`/admin/centers/${centerId}/rooms`, { roomNumber }),

  deleteRoom: (roomId) =>
    api.delete(`/admin/rooms/${roomId}`),
};

// ── DISTRICT RULES ────────────────────────────────────────────────────────────
// Manages duty-type rule definitions (sankhya + rank counts per duty type)
export const districtRulesApi = {
  // GET  /admin/district-rules
  // Returns list of all duty-type rules (default + custom)
  getAll: () => api.get('/admin/district-rules'),

  // POST /admin/district-rules  { rules: [...] }
  // Bulk-save all rules (sort order preserved by array position)
  saveAll: (rules) => api.post('/admin/district-rules', { rules }),

  // POST /admin/district-rules/custom  { labelHi: string }
  // Create a new custom duty type; server returns { dutyType, dutyLabelHi, ... }
  addCustom: (labelHi) =>
    api.post('/admin/district-rules/custom', { labelHi }),

  // PUT  /admin/district-rules/custom/:dutyType  { labelHi: string }
  // Rename an existing custom duty type
  updateCustom: (dutyType, labelHi) =>
    api.put(`/admin/district-rules/custom/${dutyType}`, { labelHi }),

  // DELETE /admin/district-rules/custom/:dutyType
  // Remove a custom duty type and its rule
  deleteCustom: (dutyType) =>
    api.delete(`/admin/district-rules/custom/${dutyType}`),
};

// ── DISTRICT DUTY SUMMARY ─────────────────────────────────────────────────────
// Aggregate stats: how many staff are assigned per duty type
export const districtDutySummaryApi = {
  // GET  /admin/district-duty/summary
  // Returns { data: { [dutyType]: { totalAssigned, batchCount } } }
  getSummary: () => api.get('/admin/district-duty/summary'),
};

// ── DISTRICT DUTY ASSIGNMENTS ─────────────────────────────────────────────────
// Per-duty-type batch management
export const districtDutyApi = {
  // GET  /admin/district-duty/:dutyType/batches
  // Returns { data: [ { batchNo, staffCount, busNo, note, staff: [...] } ] }
  getBatches: (dutyType) =>
    api.get(`/admin/district-duty/${dutyType}/batches`),

  // GET  /admin/district-duty/:dutyType/available-staff
  //   ?page=1&limit=20&q=<search>&rank=<rank>
  // Returns paginated unassigned staff for a duty type
  getAvailableStaff: (dutyType, params) =>
    api.get(`/admin/district-duty/${dutyType}/available-staff`, { params }),

  // POST /admin/district-duty/:dutyType/assign
  //   { staffIds: number[], busNo?: string, note?: string }
  // Creates a new batch; returns { batchNo, assigned, skipped }
  assignStaff: (dutyType, data) =>
    api.post(`/admin/district-duty/${dutyType}/assign`, data),

  // DELETE /admin/district-duty/:dutyType/batch/:batchNo
  // Remove all assignments in a specific batch
  deleteBatch: (dutyType, batchNo) =>
    api.delete(`/admin/district-duty/${dutyType}/batch/${batchNo}`),

  // DELETE /admin/district-duty/:dutyType/clear
  // Remove ALL assignments for a duty type
  clearDutyType: (dutyType) =>
    api.delete(`/admin/district-duty/${dutyType}/clear`),

  // DELETE /admin/district-duty/assignment/:assignmentId
  // Remove a single staff member's assignment
  removeAssignment: (assignmentId) =>
    api.delete(`/admin/district-duty/assignment/${assignmentId}`),
};

// ── DISTRICT DUTY AUTO-ASSIGN ─────────────────────────────────────────────────
// Background job that auto-assigns staff to all duty types per manak rules
export const districtAutoAssignApi = {
  // GET  /admin/district-duty/auto-assign/latest
  // Returns the most recent job { jobId, status, pct, assigned, skipped }
  getLatest: () => api.get('/admin/district-duty/auto-assign/latest'),

  // POST /admin/district-duty/auto-assign/start  {}
  // Kick off a new auto-assign background job; returns { jobId }
  start: () => api.post('/admin/district-duty/auto-assign/start', {}),

  // GET  /admin/district-duty/auto-assign/status/:jobId
  // Poll job progress { status, pct, assigned, skipped, errorMsg? }
  getStatus: (jobId) =>
    api.get(`/admin/district-duty/auto-assign/status/${jobId}`),

  // DELETE /admin/district-duty/auto-assign/clear-all
  // Wipe ALL district duty assignments across every duty type
  clearAll: () => api.delete('/admin/district-duty/auto-assign/clear-all'),
};


export const manakRankApi = {
  // GET  /admin/manak-ranks?sensitivity=<val>
  // Returns { data: { siArmedCount, siUnarmedCount, hcArmedCount, hcUnarmedCount,
  //                   constArmedCount, constUnarmedCount,
  //                   auxArmedCount, auxUnarmedCount,
  //                   pacCount, sankhya } }
  get: (sensitivity) =>
    api.get('/admin/manak-ranks', {
      params: sensitivity ? { sensitivity } : undefined,
    }),

  // PUT  /admin/manak-ranks
  // Body: { sensitivity?, siArmedCount, siUnarmedCount, hcArmedCount,
  //         hcUnarmedCount, constArmedCount, constUnarmedCount,
  //         auxArmedCount, auxUnarmedCount, pacCount, sankhya? }
  // Returns saved record.
  save: (data) => api.put('/admin/manak-ranks', data),

  // GET  /admin/manak-ranks/center/:centerId
  // Returns center-specific manak override (falls back to default if none).
  getForCenter: (centerId) =>
    api.get(`/admin/manak-ranks/center/${centerId}`),

  // PUT  /admin/manak-ranks/center/:centerId
  // Save center-level override.
  saveForCenter: (centerId, data) =>
    api.put(`/admin/manak-ranks/center/${centerId}`, data),

  // DELETE /admin/manak-ranks/center/:centerId
  // Remove override (revert to district default).
  resetForCenter: (centerId) =>
    api.delete(`/admin/manak-ranks/center/${centerId}`),
};

// ── SUPER ADMIN ───────────────────────────────────────────────────────────────
export const superApi = {
  overview: () => api.get('/super/overview'),
  getAdmins: () => api.get('/super/admins'),
  createAdmin: (data) => api.post('/super/admins', data),
  updateAdmin: (id, data) => api.put(`/super/admins/${id}`, data),
  deleteAdmin: (id) => api.delete(`/super/admins/${id}`),
  getFormData: () => api.get('/super/form-data'),
  getUnlockRequests: () => api.get('/super/unlock-requests'),
  actionUnlockRequest: (id, act) =>
    api.post(`/super/unlock-requests/${id}/action`, { action: act }),
};

// ── MASTER ────────────────────────────────────────────────────────────────────
export const masterApi = {
  overview: () => api.get('/master/overview'),
  getSuperAdmins: () => api.get('/master/super-admins'),
  createSuperAdmin: (data) => api.post('/master/super-admins', data),
  updateSuperAdmin: (id, data) => api.put(`/master/super-admins/${id}`, data),
  deleteSuperAdmin: (id) => api.delete(`/master/super-admins/${id}`),
  getAdmins: () => api.get('/master/admins'),
  createAdmin: (data) => api.post('/master/admins', data),
  getLogs: (params) => api.get('/master/logs', { params }),
  getSystemStats: () => api.get('/master/system-stats'),
  getConfig: () => api.get('/master/config'),
  updateConfig: (data) => api.post('/master/config', data),
};

// ── STAFF ─────────────────────────────────────────────────────────────────────
export const staffApi = {
  profile: () => api.get('/staff/profile'),
  myDuty: () => api.get('/staff/my-duty'),
  changePassword: (data) => api.post('/staff/change-password', data),
};