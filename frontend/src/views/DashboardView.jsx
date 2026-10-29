import { useRef, useState } from 'react'
import { useAppState } from '../controllers/context'
import { exportExcel } from '../models/excel'
import { formatDelta, formatMoney, groupDigits } from '../models/format'
import { Icon } from './ui'

const metricIcons = {
  users: 'users',
  active_pdr: 'pin',
  transactions: 'swap',
  withdrawals: 'down',
  deposits: 'up',
  pending: 'clock',
  completed: 'check',
  refused: 'close',
}

function chartPoint(days, index, value, max, box) {
  const x = box.left + (days.length <= 1 ? box.width / 2 : (index / (days.length - 1)) * box.width)
  const y = box.top + box.height - (value / max) * box.height
  return [x, y]
}

function smoothPath(points) {
  if (!points.length) return ''
  if (points.length === 1) return `M${points[0][0]},${points[0][1]}`
  let path = `M${points[0][0]},${points[0][1]}`
  for (let index = 0; index < points.length - 1; index += 1) {
    const previous = points[index - 1] || points[index]
    const current = points[index]
    const next = points[index + 1]
    const after = points[index + 2] || next
    const c1x = current[0] + (next[0] - previous[0]) / 6
    const c1y = current[1] + (next[1] - previous[1]) / 6
    const c2x = next[0] - (after[0] - current[0]) / 6
    const c2y = next[1] - (after[1] - current[1]) / 6
    path += ` C${c1x},${c1y} ${c2x},${c2y} ${next[0]},${next[1]}`
  }
  return path
}

function axisLabel(value, currency) {
  if (currency === 'USD' && value < 1000) {
    const rounded = Math.round(value * 100) / 100
    return Number.isInteger(rounded) ? groupDigits(rounded) : rounded.toFixed(2).replace('.', ',')
  }
  if (value >= 1000000) return `${(value / 1000000).toFixed(value >= 10000000 ? 0 : 1).replace('.', ',')} M`
  if (value >= 1000) return `${Math.round(value / 1000)} k`
  return groupDigits(value)
}

function dayLabel(iso) {
  const date = new Date(`${iso}T12:00:00`)
  return date.toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' })
}

function currencySeries(days, currency) {
  const key = currency.toLowerCase()
  return days.map((day) => ({
    date: day.date,
    withdrawals: Number(day[key]?.withdrawals ?? (currency === 'CDF' ? day.withdrawals : 0)) || 0,
    deposits: Number(day[key]?.deposits ?? (currency === 'CDF' ? day.deposits : 0)) || 0,
  }))
}

function exportVolume(days, currency) {
  exportExcel({
    filename: `fastcash-volume-${currency}.xls`,
    sheet: `Volume ${currency}`,
    headers: ['Date', 'Devise', 'Retraits', 'Dépôts', 'Total'],
    rows: days.map((day) => {
      const withdrawals = day.withdrawals
      const deposits = day.deposits
      return [day.date, currency, withdrawals, deposits, Math.round((withdrawals + deposits) * 100) / 100]
    }),
  })
}

function LineChart({ days, currency }) {
  const width = 640
  const height = 240
  const box = { left: 46, right: 12, top: 12, bottom: 28, width: 0, height: 0 }
  box.width = width - box.left - box.right
  box.height = height - box.top - box.bottom
  const peak = Math.max(0, ...days.flatMap((day) => [day.withdrawals, day.deposits]))
  const max = peak > 0 ? peak : 1
  const series = (key) => days.map((day, index) => chartPoint(days, index, day[key], max, box))
  const withdrawals = series('withdrawals')
  const deposits = series('deposits')
  const base = box.top + box.height
  const area = (points) => {
    const line = smoothPath(points)
    if (!line || !points.length) return ''
    return `${line} L${points[points.length - 1][0]},${base} L${points[0][0]},${base} Z`
  }
  const marks = [0, 0.25, 0.5, 0.75, 1]
  const labelCount = Math.min(5, days.length)
  const labels = days.length
    ? [...Array(labelCount)].map((_, index) => Math.round((index * (days.length - 1)) / Math.max(1, labelCount - 1)))
    : []

  return (
    <svg className="line-chart" viewBox={`0 0 ${width} ${height}`} role="img" aria-label={`Volume des opérations en ${currency} sur 30 jours`}>
      {marks.map((mark) => {
        const y = box.top + box.height - mark * box.height
        return (
          <g key={mark}>
            <line className="grid" x1={box.left} x2={width - box.right} y1={y} y2={y} />
            <text x={box.left - 8} y={y + 4} textAnchor="end">{peak > 0 || mark === 0 ? axisLabel(max * mark, currency) : ''}</text>
          </g>
        )
      })}
      <path className="area night" d={area(deposits)} />
      <path className="area brand" d={area(withdrawals)} />
      <path className="series night" d={smoothPath(deposits)} />
      <path className="series brand" d={smoothPath(withdrawals)} />
      {labels.map((index) => {
        const anchor = index === 0 ? 'start' : index === days.length - 1 ? 'end' : 'middle'
        return <text key={days[index].date} x={withdrawals[index][0]} y={height - 8} textAnchor={anchor}>{dayLabel(days[index].date)}</text>
      })}
    </svg>
  )
}

function metric(dashboard, key) {
  const raw = dashboard?.[key]
  if (!raw) return { key, label: key, value: '—', delta: null }
  const value = typeof raw.value === 'number' ? groupDigits(raw.value) : raw.value
  return { key, label: raw.label, value, delta: raw.delta }
}

function VolumeChart({ days }) {
  const scroller = useRef(null)
  const [currency, setCurrency] = useState('CDF')
  const cdf = currencySeries(days, 'CDF')
  const usd = currencySeries(days, 'USD')
  const active = currency === 'USD' ? usd : cdf
  const total = active.reduce((sum, day) => sum + day.withdrawals + day.deposits, 0)

  function reveal(next) {
    const node = scroller.current
    if (node) node.scrollTo({ left: next === 'USD' ? node.clientWidth : 0, behavior: 'smooth' })
    setCurrency(next)
  }

  function onScroll(event) {
    const node = event.currentTarget
    const next = node.scrollLeft > node.clientWidth / 2 ? 'USD' : 'CDF'
    setCurrency((current) => (current === next ? current : next))
  }

  return (
    <article className="card">
      <div className="chart-head">
        <div>
          <h3>Volume des opérations</h3>
          <p className="chart-total">{formatMoney(total, currency)}</p>
          <p className="muted">30 derniers jours, montants en {currency}. Faites défiler pour changer de devise.</p>
        </div>
        <div className="chart-tools">
          <div className="currency-switch" role="tablist" aria-label="Devise du graphique">
            <button type="button" role="tab" aria-selected={currency === 'CDF'} className={currency === 'CDF' ? 'on' : ''} onClick={() => reveal('CDF')}>CDF</button>
            <button type="button" role="tab" aria-selected={currency === 'USD'} className={currency === 'USD' ? 'on' : ''} onClick={() => reveal('USD')}>USD</button>
          </div>
          <button type="button" className="ghost" onClick={() => exportVolume(active, currency)}>Exporter Excel</button>
        </div>
      </div>
      <div className="chart-scroll" ref={scroller} onScroll={onScroll}>
        <section aria-label="Graphique CDF">
          <LineChart days={cdf} currency="CDF" />
          <p className="legend"><i className="dot night" /> Dépôts <i className="dot brand" /> Retraits</p>
        </section>
        <section aria-label="Graphique USD">
          <LineChart days={usd} currency="USD" />
          <p className="legend"><i className="dot night" /> Dépôts <i className="dot brand" /> Retraits</p>
        </section>
      </div>
    </article>
  )
}

export function DashboardView() {
  const { dashboard, charts } = useAppState()
  if (!dashboard) return <p className="muted">Chargement du tableau de bord…</p>
  const cards = ['users', 'active_pdr', 'transactions', 'withdrawals', 'deposits', 'pending', 'completed', 'refused'].map((key) => metric(dashboard, key))
  const days = charts?.daily || []
  const operators = charts?.operators || []
  const operatorMax = Math.max(1, ...operators.map((row) => row.count))
  const top = charts?.top_pdrs || []

  const today = new Date().toLocaleDateString('fr-FR', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' })

  return (
    <div className="stack">
      <header className="hello">
        <div>
          <h2>Bonjour !</h2>
          <p className="muted">Voici un aperçu des performances de Fast-Cash aujourd’hui.</p>
        </div>
        <p className="today"><Icon name="calendar" /><span><b>Aujourd’hui</b>{today}</span></p>
      </header>
      <div className="metrics">
        {cards.map((card) => (
          <article key={card.label} className="card kpi">
            <span className="kpi-icon"><Icon name={metricIcons[card.key] || 'chart'} /></span>
            <span>
              <span className="muted">{card.label}</span>
              <strong>{card.value}</strong>
              {card.delta === null || card.delta === undefined ? null : <em className={card.delta >= 0 ? 'up' : 'down'}>{formatDelta(card.delta)}</em>}
            </span>
          </article>
        ))}
        <article className="card kpi mint">
          <span className="kpi-icon"><Icon name="chart" /></span>
          <span>
            <span className="muted">Taux d’acceptation</span>
            <strong>{Number(dashboard.acceptance_rate || 0).toFixed(1).replace('.', ',')} %</strong>
          </span>
        </article>
      </div>
      <p className="muted">Les variations comparent les 15 derniers jours aux 15 jours précédents.</p>
      {days.length === 0 ? <article className="card"><h3>Volume des opérations</h3><p className="muted">Pas encore de volume</p></article> : <VolumeChart days={days} />}
      <div className="split">
        <article className="card">
          <h3>Répartition par opérateur</h3>
          {operators.length === 0 ? <p className="muted">Aucune transaction</p> : operators.map((row) => (
            <div key={row.network} className="hbar">
              <div><span>{row.label}</span><b>{row.count}</b></div>
              <i style={{ width: `${Math.max(4, (row.count / operatorMax) * 100)}%` }} />
            </div>
          ))}
        </article>
        <article className="card">
          <h3>Points les plus sollicités</h3>
          {top.length === 0 ? <p className="muted">Aucune transaction retenue</p> : top.map((row) => (
            <p key={row.pdr_id} className="line"><span>{row.name}</span><b>{row.count}</b></p>
          ))}
          <p className="muted">Acceptées {charts?.acceptance?.accepted || 0} · Refusées {charts?.acceptance?.refused || 0}</p>
        </article>
      </div>
    </div>
  )
}
