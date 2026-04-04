import axios from 'axios'

const BASE_URL = import.meta.env.VITE_API_URL || 'http://127.0.0.1:5000/api'

const api = axios.create({ baseURL: BASE_URL,withCredentials:true })

// Attach token to every request
api.interceptors.request.use((config) => {
  const token = localStorage.getItem('token')
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

// Handle 401 globally
api.interceptors.response.use(
  (res) => res,
  (err) => {
    if (err.response?.status === 401) {
      localStorage.clear()
      window.location.href = '/login'
    }
    return Promise.reject(err)
  }
)

// ── Auth ──────────────────────────────────────────────
export const authAPI = {
  login: (username, password) =>
    api.post('/login', { username, password }).then((r) => r.data),
  logout: () => api.post('/logout').then((r) => r.data),
}

// ── Admin ─────────────────────────────────────────────
export const adminAPI = {
  overview:   () => api.get('/admin/overview').then((r) => r.data.data),

  // Super Zones
  getSuperZones:    () => api.get('/admin/super-zones').then((r) => r.data.data),
  addSuperZone: (body) => api.post('/admin/super-zones', body),
  deleteSuperZone:  (id) => api.delete(`/admin/super-zones/${id}`).then((r) => r.data),

  // Zones
  getZones:    (szId) => api.get(`/admin/super-zones/${szId}/zones`).then((r) => r.data.data),
  addZone:     (szId, body) => api.post(`/admin/super-zones/${szId}/zones`, body).then((r) => r.data),
  deleteZone:  (id) => api.delete(`/admin/zones/${id}`).then((r) => r.data),

  // Sectors
  getSectors:   (zId) => api.get(`/admin/zones/${zId}/sectors`).then((r) => r.data.data),
  addSector:    (zId, body) => api.post(`/admin/zones/${zId}/sectors`, body).then((r) => r.data),
  deleteSector: (id) => api.delete(`/admin/sectors/${id}`).then((r) => r.data),

  // Officers
  addOfficer:    (sId, body) => api.post(`/admin/sectors/${sId}/officers`, body).then((r) => r.data),
  deleteOfficer: (id) => api.delete(`/admin/officers/${id}`).then((r) => r.data),

  // Gram Panchayats
  getGPs:    (sId) => api.get(`/admin/sectors/${sId}/gram-panchayats`).then((r) => r.data.data),
  addGP:     (sId, body) => api.post(`/admin/sectors/${sId}/gram-panchayats`, body).then((r) => r.data),
  deleteGP:  (id) => api.delete(`/admin/gram-panchayats/${id}`).then((r) => r.data),

  // Centers (Matdan Sthal)
  getCenters:    (gpId) => api.get(`/admin/gram-panchayats/${gpId}/centers`).then((r) => r.data.data),
  addCenter:     (gpId, body) => api.post(`/admin/gram-panchayats/${gpId}/centers`, body).then((r) => r.data),
  deleteCenter:  (id) => api.delete(`/admin/centers/${id}`).then((r) => r.data),
  allCenters:    () => api.get('/admin/centers/all').then((r) => r.data.data),

  // Staff
  getStaff:      (q = '') => api.get(`/admin/staff${q ? `?q=${q}` : ''}`).then((r) => r.data.data),
  addStaff:      (body) => api.post('/admin/staff', body).then((r) => r.data),
  addStaffBulk:  (staff) => api.post('/admin/staff/bulk', { staff }).then((r) => r.data),

  // Duties
  getDuties:    (centerId) => api.get(`/admin/duties${centerId ? `?center_id=${centerId}` : ''}`).then((r) => r.data.data),
  assignDuty:   (body) => api.post('/admin/duties', body).then((r) => r.data),
  removeDuty:   (id) => api.delete(`/admin/duties/${id}`).then((r) => r.data),
}

// ── Super Admin ───────────────────────────────────────
export const superAPI = {

  overview: () =>
    api.get('/super/overview').then((r) => r.data.data),

  // ✅ FIXED (search + pagination)
  getAdmins: (params) =>
    api.get('/super/admins', { params }).then((r) => r.data.data),

  createAdmin: (body) =>
    api.post('/super/admins', body).then((r) => r.data),

  deleteAdmin: (id) =>
    api.delete(`/super/admins/${id}`).then((r) => r.data),

  // ✅ ADD THIS (UPDATE)
  updateAdmin: (id, body) =>
    api.put(`/super/admins/${id}`, body).then((r) => r.data),

  // ✅ ADD THIS (TOGGLE)
  toggleAdmin: (id) =>
    api.patch(`/super/admins/${id}/toggle`).then((r) => r.data),

  // ✅ OPTIONAL
  resetPassword: (id, password) =>
    api.patch(`/super/admins/${id}/reset-password`, { password }).then((r) => r.data),

  formData: () =>
    api.get('/super/form-data').then((r) => r.data.data),
}

// ── Master ────────────────────────────────────────────
export const masterAPI = {
  overview:         () => api.get('/master/system-stats').then((r) => r.data.data),
  getSuperAdmins:   () => api.get('/master/super-admins').then((r) => r.data.data),
  createSuperAdmin: (body) => api.post('/master/create-super-admin', body).then((r) => r.data),
  deleteSuperAdmin: (id) => api.delete(`/master/super-admin/${id}`).then((r) => r.data),
  getLogs:          () => api.get('/master/logs').then((r) => r.data.data),
}

// ── Staff ─────────────────────────────────────────────
export const staffAPI = {
  myDuty:   () => api.get('/staff/my-duty').then((r) => r.data.data),
  profile:  () => api.get('/staff/profile').then((r) => r.data.data),
  changePassword: (body) => api.post('/staff/change-password', body).then(r => r.data),
}

export default api
