/** Conversions monétaires partagées (SRP). */

export function amountToCdf(amount, currency, rate = 2880) {
  const value = Number(amount) || 0
  if (currency === 'CDF') return value
  return value * (Number(rate) || 2880)
}

export function isoDay(date = new Date()) {
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${date.getFullYear()}-${month}-${day}`
}
