import { useEffect, useState } from 'react'
import { useAppController, useAppState } from '../controllers/context'
import { formatMoney, statusLabel } from '../models/format'
import { isoDay } from '../models/money'
import { OPERATORS } from '../models/operators'

function reportLabel(bucket, key) {
  if (bucket === 'by_type') return key === 'deposit' ? 'Dépôts' : 'Retraits'
  if (bucket === 'by_status') return statusLabel(key)
  return key
}

function Table({ title, bucket, rows, showCdfEquiv = false }) {
  return (
    <article className="card">
      <h3>{title}</h3>
      {!rows?.length ? <p className="muted">Aucune donnée sur cette période.</p> : (
        <table>
          <thead>
            <tr>
              <th>Libellé</th>
              <th>Nombre</th>
              <th>USD</th>
              <th>CDF</th>
              {showCdfEquiv ? <th>Équiv. CDF</th> : null}
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.key}>
                <td>{reportLabel(bucket, row.key)}</td>
                <td>{row.count}</td>
                <td>{formatMoney(row.usd, 'USD')}</td>
                <td>{formatMoney(row.cdf, 'CDF')}</td>
                {showCdfEquiv ? <td>{formatMoney(row.cdf_equiv, 'CDF')}</td> : null}
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
  const [tab, setTab] = useState('general')
  const [from, setFrom] = useState(isoDay(new Date(today.getFullYear(), today.getMonth(), today.getDate() - 29)))
  const [to, setTo] = useState(isoDay(today))
  const [network, setNetwork] = useState('')

  useEffect(() => {
    controller.loadReports(from, to, network || null)
  }, [controller, from, to, network])

  const success = reports?.pdr_success

  return (
    <div className="stack">
      <div className="chips" role="tablist" aria-label="Type de rapport">
        <button type="button" role="tab" className={tab === 'general' ? 'choice on' : 'choice'} aria-selected={tab === 'general'} onClick={() => setTab('general')}>
          Vue générale
        </button>
        <button type="button" role="tab" className={tab === 'pdr' ? 'choice on' : 'choice'} aria-selected={tab === 'pdr'} onClick={() => setTab('pdr')}>
          Transactions PDR
        </button>
      </div>
      <div className="toolbar">
        <label>Du<input type="date" value={from} max={to} onChange={(event) => setFrom(event.target.value)} /></label>
        <label>Au<input type="date" value={to} min={from} onChange={(event) => setTo(event.target.value)} /></label>
        <label>
          Opérateur
          <select value={network} onChange={(event) => setNetwork(event.target.value)}>
            {OPERATORS.map(([value, label]) => <option key={value || 'all'} value={value}>{label}</option>)}
          </select>
        </label>
        <span className="muted">{reports ? `${reports.count} opérations` : 'Chargement…'}</span>
      </div>
      {reports ? (
        tab === 'general' ? (
          <>
            <Table title="Par type" bucket="by_type" rows={reports.by_type} />
            <Table title="Par opérateur" bucket="by_network" rows={reports.by_network} />
            <Table title="Par commune" bucket="by_commune" rows={reports.by_commune} />
            <Table title="Par statut" bucket="by_status" rows={reports.by_status} />
            <Table title="Par client" bucket="by_client" rows={reports.by_client} showCdfEquiv />
          </>
        ) : (
          <>
            <article className="card">
              <h3>Synthèse liquidité PDR</h3>
              {!success ? <p className="muted">Aucune donnée.</p> : (
                <div className="split">
                  <p><span className="muted">Transactions réussies</span><br /><strong>{success.count}</strong></p>
                  <p><span className="muted">Volume réussi (CDF)</span><br /><strong>{formatMoney(success.volume_cdf, 'CDF')}</strong></p>
                  <p><span className="muted">Couverture ({success.cover_percent} %)</span><br /><strong>{formatMoney(success.cover_cdf, 'CDF')}</strong></p>
                </div>
              )}
              <p className="muted">Retraits terminés et dépôts confirmés, montants convertis en CDF.</p>
            </article>
            <Table title="Par point de retrait" bucket="by_pdr" rows={reports.by_pdr} showCdfEquiv />
            <Table title="Par opérateur" bucket="by_network" rows={reports.by_network} showCdfEquiv />
            <Table title="Par commune" bucket="by_commune" rows={reports.by_commune} showCdfEquiv />
            <Table title="Par type" bucket="by_type" rows={reports.by_type} showCdfEquiv />
          </>
        )
      ) : null}
    </div>
  )
}
