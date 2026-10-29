import { useState } from 'react'
import { useAppController, useAppState } from '../controllers/context'
import { exportExcel } from '../models/excel'
import { formatDate, roleLabel } from '../models/format'
import { StatusChip } from './ui'

export function TeamView() {
  const { team, session, busy } = useAppState()
  const controller = useAppController()
  const [open, setOpen] = useState(false)
  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [role, setRole] = useState('support')
  const [password, setPassword] = useState('')

  function create(event) {
    event.preventDefault()
    controller.createMember({ name, email, role, password })
    setOpen(false)
    setName('')
    setEmail('')
    setPassword('')
    setRole('support')
  }

  return (
    <div className="stack">
      <div className="toolbar">
        <button type="button" className="primary" onClick={() => setOpen(true)}>Ajouter un administrateur</button>
        <button type="button" className="ghost" onClick={() => exportExcel({
          filename: 'fastcash-equipe.xls',
          sheet: 'Équipe',
          headers: ['Nom', 'E-mail', 'Rôle', 'Statut', 'Inscription'],
          rows: team.map((member) => [
            member.name,
            member.email,
            roleLabel(member.role),
            member.status === 'active' ? 'Actif' : 'Suspendu',
            formatDate(member.created_at),
          ]),
        })}
        >Exporter Excel</button>
      </div>
      {team.map((member) => (
        <article key={member.id} className="card row">
          <div>
            <strong>{member.name}</strong>
            <span className="muted">{member.email}</span>
            <span className="role">{roleLabel(member.role)}</span>
          </div>
          <div className="end">
            <StatusChip positive={member.status === 'active'}>{member.status === 'active' ? 'Actif' : 'Suspendu'}</StatusChip>
            {member.id !== session.id ? (
              <button
                type="button"
                className="text-button"
                disabled={busy}
                onClick={() => controller.updateMember(member.id, { status: member.status === 'active' ? 'suspended' : 'active' })}
              >
                {member.status === 'active' ? 'Suspendre' : 'Réactiver'}
              </button>
            ) : null}
            <label className="inline">
              Rôle
              <select value={member.role} onChange={(event) => controller.updateMember(member.id, { role: event.target.value })}>
                <option value="support">Support</option>
                <option value="superadmin">Super administrateur</option>
              </select>
            </label>
          </div>
        </article>
      ))}
      {open ? (
        <div className="modal-back" role="presentation" onClick={() => setOpen(false)}>
          <form className="modal" role="dialog" aria-modal="true" onClick={(event) => event.stopPropagation()} onSubmit={create}>
            <h3>Nouvel administrateur</h3>
            <label>Nom<input value={name} onChange={(event) => setName(event.target.value)} /></label>
            <label>E-mail<input type="email" value={email} onChange={(event) => setEmail(event.target.value)} /></label>
            <label>Mot de passe<input type="password" value={password} autoComplete="new-password" onChange={(event) => setPassword(event.target.value)} /></label>
            <label>Rôle
              <select value={role} onChange={(event) => setRole(event.target.value)}>
                <option value="support">Support</option>
                <option value="superadmin">Super administrateur</option>
              </select>
            </label>
            <div className="modal-actions">
              <button type="button" className="ghost" onClick={() => setOpen(false)}>Annuler</button>
              <button type="submit" className="primary">Créer</button>
            </div>
          </form>
        </div>
      ) : null}
    </div>
  )
}
