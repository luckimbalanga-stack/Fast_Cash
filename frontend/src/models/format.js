const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.']

const statusLabels = {
  pending: 'En attente',
  pin_required: 'Code PIN requis',
  accepted: 'Acceptée',
  refused: 'Refusée',
  payment_pending: 'Paiement en attente',
  payment_confirmed: 'Paiement confirmé',
  cash_delivered: 'Scan effectué',
  completed: 'Terminée',
  cancelled: 'Annulée',
}

export function formatPhone(phone) {
  const digits = String(phone || '').replace('+243', '')
  if (digits.length !== 9) return phone || ''
  return `+243 ${digits.slice(0, 3)} ${digits.slice(3, 6)} ${digits.slice(6)}`
}

export function groupDigits(value) {
  const negative = Number(value) < 0
  const raw = String(Math.round(Math.abs(Number(value) || 0)))
  let out = ''
  for (let index = 0; index < raw.length; index += 1) {
    if (index > 0 && (raw.length - index) % 3 === 0) out += '\u00a0'
    out += raw[index]
  }
  return negative ? `-${out}` : out
}

export function formatMoney(amount, currency) {
  const value = Number(amount) || 0
  if (currency === 'CDF') return `${groupDigits(value)} CDF`
  const text = value % 1 === 0 ? groupDigits(value) : value.toFixed(2).replace('.', ',')
  return `${text} USD`
}

export function formatDate(iso) {
  if (!iso) return ''
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return iso
  const hour = String(date.getHours()).padStart(2, '0')
  const minute = String(date.getMinutes()).padStart(2, '0')
  return `${date.getDate()} ${months[date.getMonth()]} ${date.getFullYear()} · ${hour}:${minute}`
}

export function statusLabel(status, type) {
  if (type === 'deposit' && status === 'cash_delivered') return 'Espèces reçues'
  return statusLabels[status] || status
}

export function roleLabel(role) {
  return role === 'superadmin' ? 'Super administrateur' : 'Support'
}

export function typeLabel(type) {
  return type === 'deposit' ? 'Dépôt' : 'Retrait'
}

export function formatDelta(delta) {
  if (delta === null || delta === undefined) return ''
  const sign = delta > 0 ? '+' : ''
  return `${sign}${Number(delta).toFixed(1).replace('.', ',')} %`
}
