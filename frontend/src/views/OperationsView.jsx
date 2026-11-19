import { useMemo, useState } from 'react'
import { useAppState } from '../controllers/context'
import { exportExcel } from '../models/excel'
import { formatDate, formatMoney, formatPhone, statusLabel, typeLabel } from '../models/format'
import { amountToCdf } from '../models/money'
import { OPERATORS } from '../models/operators'
import { SearchField, StatusChip } from './ui'

const statuses = [null, 'pending', 'payment_confirmed', 'cash_delivered', 'completed', 'refused', 'cancelled']

export function OperationsView() {
  const { operations, settings, charts } = useAppState()
  const rate = settings?.usd_cdf_rate || charts?.usd_cdf_rate || 2880
  const [tab, setTab] = useState('client')
  const [query, setQuery] = useState('')
  const [type, setType] = useState(null)
  const [status, setStatus] = useState(null)
  const [network, setNetwork] = useState('')
  const [selected, setSelected] = useState(null)
  const needle = query.trim().toLowerCase()

  const rows = useMemo(() => operations.filter((operation) => {
    if (type && operation.type !== type) return false
    if (status && operation.status !== status) return false
    if (network && operation.network !== network) return false
    if (!needle) return true
    return `${operation.reference} ${operation.user_name} ${operation.pdr_name} ${operation.phone} ${operation.token_code || ''}`.toLowerCase().includes(needle)
  }), [operations, type, status, network, needle])

  const exportRows = rows.map((operation) => {
    const base = [
      operation.reference,
      typeLabel(operation.type),
      statusLabel(operation.status, operation.type),
      operation.amount,
      operation.currency,
      operation.fees,
      formatDate(operation.created_at),
    ]
    if (tab === 'client') {
      return [
        ...base,
        operation.user_name,
        formatPhone(operation.phone),
        operation.network_label,
        operation.pdr_name,
      ]
    }
    return [
      ...base,
      operation.pdr_name,
      operation.pdr_commune,
      operation.network_label,
      Math.round(amountToCdf(operation.amount, operation.currency, rate)),
      operation.user_name,
    ]
  })

  return (
    <div className="stack">
      <div className="chips" role="tablist" aria-label="Vue transactions">
        <button type="button" role="tab" className={tab === 'client' ? 'choice on' : 'choice'} aria-selected={tab === 'client'} onClick={() => setTab('client')}>
          Clients
        </button>
        <button type="button" role="tab" className={tab === 'pdr' ? 'choice on' : 'choice'} aria-selected={tab === 'pdr'} onClick={() => setTab('pdr')}>
          Points de retrait
        </button>
      </div>
      <SearchField
        label={tab === 'client' ? 'Référence, client, téléphone ou jeton' : 'Référence, point, commune ou opérateur'}
        value={query}
        onChange={setQuery}
      />
      <div className="chips">
        {[[null, 'Toutes'], ['withdrawal', 'Retraits'], ['deposit', 'Dépôts']].map(([value, label]) => (
          <button key={label} type="button" className={type === value ? 'choice on' : 'choice'} onClick={() => setType(value)}>{label}</button>
        ))}
      </div>
      <div className="chips">
        {statuses.map((value) => (
          <button key={value || 'all'} type="button" className={status === value ? 'choice on' : 'choice'} onClick={() => setStatus(value)}>
            {value ? statusLabel(value) : 'Tous les statuts'}
          </button>
        ))}
      </div>
      {tab === 'pdr' ? (
        <div className="chips">
          {OPERATORS.map(([value, label]) => (
            <button key={value || 'all'} type="button" className={network === value ? 'choice on' : 'choice'} onClick={() => setNetwork(value)}>
              {label}
            </button>
          ))}
        </div>
      ) : null}
      <div className="row">
        <p className="muted">{rows.length} opération{rows.length > 1 ? 's' : ''} · vue {tab === 'client' ? 'client' : 'PDR'}</p>
        <button
          type="button"
          className="ghost"
          onClick={() => exportExcel({
            filename: tab === 'client' ? 'fastcash-transactions-clients.xls' : 'fastcash-transactions-pdr.xls',
            sheet: tab === 'client' ? 'Clients' : 'PDR',
            headers: tab === 'client'
              ? ['Référence', 'Type', 'Statut', 'Montant', 'Devise', 'Frais', 'Date', 'Client', 'Téléphone', 'Opérateur', 'Point']
              : ['Référence', 'Type', 'Statut', 'Montant', 'Devise', 'Frais', 'Date', 'Point', 'Commune', 'Opérateur', 'Équiv. CDF', 'Client'],
            rows: exportRows,
          })}
        >
          Exporter Excel
        </button>
      </div>
      {rows.map((operation) => (
        <button key={operation.id} type="button" className="card row link" onClick={() => setSelected(operation)}>
          <div>
            <strong>{operation.reference}</strong>
            {tab === 'client' ? (
              <>
                <span className="muted">{typeLabel(operation.type)} · {operation.user_name}</span>
                <span className="muted">{formatPhone(operation.phone)} · {operation.network_label} · {formatDate(operation.created_at)}</span>
              </>
            ) : (
              <>
                <span className="muted">{typeLabel(operation.type)} · {operation.pdr_name}</span>
                <span className="muted">{operation.pdr_commune} · {operation.network_label} · {formatDate(operation.created_at)}</span>
              </>
            )}
          </div>
          <div className="end">
            <b>{tab === 'pdr' ? formatMoney(amountToCdf(operation.amount, operation.currency, rate), 'CDF') : formatMoney(operation.amount, operation.currency)}</b>
            {tab === 'pdr' && operation.currency !== 'CDF' ? (
              <span className="muted">{formatMoney(operation.amount, operation.currency)}</span>
            ) : null}
            <StatusChip positive={['completed', 'cash_delivered', 'payment_confirmed', 'accepted'].includes(operation.status)}>
              {statusLabel(operation.status, operation.type)}
            </StatusChip>
          </div>
        </button>
      ))}
      {selected ? (
        <div className="modal-back" onClick={() => setSelected(null)} role="presentation">
          <article className="modal wide" role="dialog" aria-modal="true" onClick={(event) => event.stopPropagation()}>
            <h3>{selected.reference}</h3>
            <p className="amount">{formatMoney(selected.amount, selected.currency)}</p>
            {selected.currency !== 'CDF' ? <p className="muted">Équivalent : {formatMoney(amountToCdf(selected.amount, selected.currency, rate), 'CDF')}</p> : null}
            <StatusChip positive={['completed', 'cash_delivered', 'payment_confirmed', 'accepted'].includes(selected.status)}>
              {statusLabel(selected.status, selected.type)}
            </StatusChip>
            <p><strong>Client</strong><br />{selected.user_name}<br />{formatPhone(selected.phone)}</p>
            <p><strong>Point de retrait</strong><br />{selected.pdr_name}<br />{selected.pdr_address}, {selected.pdr_commune}</p>
            <p className="muted">{selected.network_label}</p>
            <p className="muted">Frais : {formatMoney(selected.fees, selected.currency)}</p>
            {selected.token_code ? <p className="muted">Jeton {selected.token_code} · {selected.token_status}</p> : null}
            <h4>Chronologie</h4>
            <ul className="timeline">
              {(selected.timeline || []).map((event) => (
                <li key={`${event.status}-${event.created_at}`}>
                  <strong>{event.label}</strong>
                  <span>{formatDate(event.created_at)}</span>
                </li>
              ))}
            </ul>
            <button type="button" className="ghost" onClick={() => setSelected(null)}>Fermer</button>
          </article>
        </div>
      ) : null}
    </div>
  )
}
