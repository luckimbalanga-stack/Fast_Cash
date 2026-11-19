import { request } from './http'

/** Accès aux données d'administration. Aucune règle d'écran ici. */
export function createAdminModel() {
  return {
    settings: () => request('/api/settings'),
    enter: (email, password) => request('/api/auth/admin/enter', { method: 'POST', body: { email, password } }),
    dashboard: (token) => request('/api/admin/dashboard', { token }),
    charts: (token, { from, to, network } = {}) => {
      const query = new URLSearchParams()
      if (from) query.set('date_from', from)
      if (to) query.set('date_to', to)
      if (network) query.set('network', network)
      const suffix = query.toString() ? `?${query}` : ''
      return request(`/api/admin/charts${suffix}`, { token })
    },
    users: (token) => request('/api/admin/users', { token }),
    pdrs: (token) => request('/api/pdr', { token }),
    team: (token) => request('/api/admin/admins', { token }),
    operations: (token) => request('/api/operations', { token }),
    reports: (token, from, to, network) => {
      const query = new URLSearchParams({ date_from: from, date_to: to })
      if (network) query.set('network', network)
      return request(`/api/admin/reports?${query}`, { token })
    },
    setUserStatus: (token, id, status) => request(`/api/users/${id}`, { method: 'PATCH', token, body: { status } }),
    importUsers: (token, users) => request('/api/admin/users/import', { method: 'POST', token, body: { users } }),
    createPdr: (token, body) => request('/api/pdr', { method: 'POST', token, body }),
    updatePdr: (token, id, body) => request(`/api/pdr/${id}`, { method: 'PATCH', token, body }),
    setAvailability: (token, id, body) => request(`/api/pdr/${id}/availability`, { method: 'POST', token, body }),
    deactivatePdr: (token, id) => request(`/api/pdr/${id}/deactivate`, { method: 'POST', token, body: {} }),
    resetPdrPassword: (token, id, body = {}) => request(`/api/pdr/${id}/reset-password`, { method: 'POST', token, body }),
    saveSettings: (token, body) => request('/api/settings', { method: 'PUT', token, body }),
    createMember: (token, body) => request('/api/admin/admins', { method: 'POST', token, body }),
    updateMember: (token, id, body) => request(`/api/admin/admins/${id}`, { method: 'PATCH', token, body }),
  }
}
