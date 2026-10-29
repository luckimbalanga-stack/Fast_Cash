import { useState } from 'react'
import { useAppController, useAppState } from '../controllers/context'
import { exportExcel } from '../models/excel'
import { formatDate, formatPhone } from '../models/format'
import { Modal, SearchField, StatusChip } from './ui'

export function UsersView() {
  const { users, busy } = useAppState()
  const controller = useAppController()
  const [query, setQuery] = useState('')
  const [pending, setPending] = useState(null)
  const needle = query.trim().toLowerCase()
  const rows = users.filter((user) => !needle || `${user.name} ${user.phone}`.toLowerCase().includes(needle))

  return (
    <div className="stack">
      <div className="toolbar">
        <SearchField label="Nom ou numéro" value={query} onChange={setQuery} />
        <button type="button" className="ghost" onClick={() => exportExcel({
          filename: 'fastcash-utilisateurs.xls',
          sheet: 'Utilisateurs',
          headers: ['Nom', 'Téléphone', 'Statut', 'Transactions', 'Inscription'],
          rows: rows.map((user) => [
            user.name,
            formatPhone(user.phone),
            user.status === 'active' ? 'Actif' : 'Suspendu',
            user.transaction_count || 0,
            formatDate(user.created_at),
          ]),
        })}
        >Exporter Excel</button>
      </div>
      <p className="muted">{rows.length} compte{rows.length > 1 ? 's' : ''}</p>
      {rows.map((user) => {
        const active = user.status === 'active'
        return (
          <article key={user.id} className="card row">
            <div>
              <strong>{user.name}</strong>
              <span className="muted">{formatPhone(user.phone)}</span>
              <span className="muted">{user.transaction_count || 0} transaction{(user.transaction_count || 0) > 1 ? 's' : ''}</span>
            </div>
            <div className="end">
              <StatusChip positive={active}>{active ? 'Actif' : 'Suspendu'}</StatusChip>
              <button type="button" className="text-button" disabled={busy} onClick={() => setPending(user)}>
                {active ? 'Suspendre' : 'Réactiver'}
              </button>
            </div>
          </article>
        )
      })}
      {pending ? (
        <Modal
          title={pending.status === 'active' ? 'Suspendre ce compte ?' : 'Réactiver ce compte ?'}
          text={pending.status === 'active'
            ? `${pending.name} ne pourra plus se connecter ni lancer d’opération.`
            : `${pending.name} pourra de nouveau utiliser Fast-Cash.`}
          confirmLabel={pending.status === 'active' ? 'Suspendre' : 'Réactiver'}
          onClose={() => setPending(null)}
          onConfirm={() => {
            const next = pending.status === 'active' ? 'suspended' : 'active'
            const id = pending.id
            setPending(null)
            controller.setUserStatus(id, next)
          }}
        />
      ) : null}
    </div>
  )
}
