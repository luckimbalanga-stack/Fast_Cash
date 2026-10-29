import { request } from './http'

/** Accès aux données d'administration. Aucune règle d'écran ici. */
export function createAdminModel() {
  return {
    settings: () => request('/api/settings'),
    enter: (email, password) => request('/api/auth/admin/enter', { method: 'POST', body: { email, password } }),
    dashboard: (token) => request('/api/admin/dashboard', { token }),
    charts: (token) => request('/api/admin/charts', { token }),
    users: (token) => request('/api/admin/users', { token }),
    pdrs: (token) => request('/api/pdr', { token }),
    team: (token) => request('/api/admin/admins', { token }),
    operations: (token) => request('/api/operations', { token }),
    reports: (token, from, to) => request(`/api/admin/reports?date_from=${from}&date_to=${to}`, { token }),
    setUserStatus: (token, id, status) => request(`/api/users/${id}`, { method: 'PATCH', token, body: { status } }),
    createPdr: (token, body) => request('/api/pdr', { method: 'POST', token, body }),
    updatePdr: (token, id, body) => request(`/api/pdr/${id}`, { method: 'PATCH', token, body }),
    setAvailability: (token, id, body) => request(`/api/pdr/${id}/availability`, { method: 'POST', token, body }),
    deactivatePdr: (token, id) => request(`/api/pdr/${id}/deactivate`, { method: 'POST', token, body: {} }),
    saveSettings: (token, body) => request('/api/settings', { method: 'PUT', token, body }),
    createMember: (token, body) => request('/api/admin/admins', { method: 'POST', token, body }),
    updateMember: (token, id, body) => request(`/api/admin/admins/${id}`, { method: 'PATCH', token, body }),
  }
}
