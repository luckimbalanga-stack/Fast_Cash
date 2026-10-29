import { useEffect, useState } from 'react'
import { useAppController, useAppState } from '../controllers/context'
import { formatMoney, statusLabel } from '../models/format'

function iso(date) {
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${date.getFullYear()}-${month}-${day}`
}

function reportLabel(bucket, key) {
  if (bucket === 'by_type') return key === 'deposit' ? 'Dépôts' : 'Retraits'
  if (bucket === 'by_status') return statusLabel(key)
  return key
}

function Table({ title, bucket, rows }) {
  return (
    <article className="card">
      <h3>{title}</h3>
      {!rows?.length ? <p className="muted">Aucune donnée sur cette période.</p> : (
        <table>
          <thead>
            <tr><th>Libellé</th><th>Nombre</th><th>USD</th><th>CDF</th></tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.key}>
                <td>{reportLabel(bucket, row.key)}</td>
                <td>{row.count}</td>
                <td>{formatMoney(row.usd, 'USD')}</td>
                <td>{formatMoney(row.cdf, 'CDF')}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </article>
  )
}

export function ReportsView() {
  const { reports } = useAppState()
  const controller = useAppController()
  const today = new Date()
  const [from, setFrom] = useState(iso(new Date(today.getFullYear(), today.getMonth(), today.getDate() - 29)))
  const [to, setTo] = useState(iso(today))

  useEffect(() => {
    controller.loadReports(from, to)
  }, [controller, from, to])

  return (
    <div className="stack">
      <div className="toolbar">
        <label>Du<input type="date" value={from} max={to} onChange={(event) => setFrom(event.target.value)} /></label>
        <label>Au<input type="date" value={to} min={from} onChange={(event) => setTo(event.target.value)} /></label>
        <span className="muted">{reports ? `${reports.count} opérations` : 'Chargement…'}</span>
      </div>
      {reports ? (
        <>
          <Table title="Par type" bucket="by_type" rows={reports.by_type} />
          <Table title="Par opérateur" bucket="by_network" rows={reports.by_network} />
          <Table title="Par commune" bucket="by_commune" rows={reports.by_commune} />
          <Table title="Par statut" bucket="by_status" rows={reports.by_status} />
        </>
      ) : null}
    </div>
  )
}
