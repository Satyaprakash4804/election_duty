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
};

// ── SUPER ADMIN ───────────────────────────────────────────────────────────────
export const superApi = {
  overview: () => api.get('/super/overview'),
  getAdmins: () => api.get('/super/admins'),
  createAdmin: (data) => api.post('/super/admins', data),
  updateAdmin: (id, data) => api.put(`/super/admins/${id}`, data),
  deleteAdmin: (id) => api.delete(`/super/admins/${id}`),
  getFormData: () => api.get('/super/form-data'),
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
