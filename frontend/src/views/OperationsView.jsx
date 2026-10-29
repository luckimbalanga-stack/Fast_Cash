import { useState } from 'react'
import { useAppState } from '../controllers/context'
import { exportExcel } from '../models/excel'
import { formatDate, formatMoney, formatPhone, statusLabel, typeLabel } from '../models/format'
import { SearchField, StatusChip } from './ui'

const statuses = [null, 'pending', 'payment_confirmed', 'cash_delivered', 'completed', 'refused', 'cancelled']

export function OperationsView() {
  const { operations } = useAppState()
  const [query, setQuery] = useState('')
  const [type, setType] = useState(null)
  const [status, setStatus] = useState(null)
  const [selected, setSelected] = useState(null)
  const needle = query.trim().toLowerCase()
  const rows = operations.filter((operation) => {
    if (type && operation.type !== type) return false
    if (status && operation.status !== status) return false
    if (!needle) return true
    return `${operation.reference} ${operation.user_name} ${operation.pdr_name} ${operation.phone} ${operation.token_code || ''}`.toLowerCase().includes(needle)
  })

  return (
    <div className="stack">
      <SearchField label="Référence, client, point ou jeton" value={query} onChange={setQuery} />
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
      <div className="row">
        <p className="muted">{rows.length} opération{rows.length > 1 ? 's' : ''}</p>
        <button type="button" className="ghost" onClick={() => exportExcel({
          filename: 'fastcash-transactions.xls',
          sheet: 'Transactions',
          headers: ['Référence', 'Type', 'Statut', 'Montant', 'Devise', 'Frais', 'Client', 'Téléphone', 'Point', 'Commune', 'Opérateur', 'Date'],
          rows: rows.map((operation) => [
            operation.reference,
            typeLabel(operation.type),
            statusLabel(operation.status, operation.type),
            operation.amount,
            operation.currency,
            operation.fees,
            operation.user_name,
            formatPhone(operation.phone),
            operation.pdr_name,
            operation.pdr_commune,
            operation.network_label,
            formatDate(operation.created_at),
          ]),
        })}
        >Exporter Excel</button>
      </div>
      {rows.map((operation) => (
        <button key={operation.id} type="button" className="card row link" onClick={() => setSelected(operation)}>
          <div>
            <strong>{operation.reference}</strong>
            <span className="muted">{typeLabel(operation.type)} · {operation.user_name}</span>
            <span className="muted">{operation.pdr_name} · {formatDate(operation.created_at)}</span>
          </div>
          <div className="end">
            <b>{formatMoney(operation.amount, operation.currency)}</b>
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
            <StatusChip positive={['completed', 'cash_delivered', 'payment_confirmed', 'accepted'].includes(selected.status)}>
              {statusLabel(selected.status, selected.type)}
            </StatusChip>
            <p>{selected.pdr_name}<br />{selected.pdr_address}, {selected.pdr_commune}</p>
            <p className="muted">{selected.network_label} · {formatPhone(selected.phone)}</p>
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
