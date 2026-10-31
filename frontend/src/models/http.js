export class ApiError extends Error {}

/** URL de l’API Render en prod ; vide en local (proxy Vite /api → :8000). */
const API_BASE = String(import.meta.env.VITE_API_BASE || '').replace(/\/$/, '')

function detailMessage(data, status) {
  if (data && typeof data.detail === 'string') return data.detail
  if (data && Array.isArray(data.detail)) {
    return data.detail.map((item) => (item && item.msg) || String(item)).join(' ')
  }
  return `Erreur ${status}`
}

export async function request(path, { method = 'GET', body, token } = {}) {
  const headers = { 'Content-Type': 'application/json' }
  if (token) headers.Authorization = `Bearer ${token}`
  const url = path.startsWith('http') ? path : `${API_BASE}${path}`
  let response
  try {
    response = await fetch(url, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    })
  } catch {
    throw new ApiError('Impossible de joindre le serveur Fast-Cash. Vérifiez que l’API est démarrée.')
  }
  const data = response.status === 204 || response.headers.get('content-length') === '0'
    ? null
    : await response.json().catch(() => null)
  if (!response.ok) throw new ApiError(detailMessage(data, response.status))
  return data
}
