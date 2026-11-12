import { useRef, useState } from 'react'
import { useAppController, useAppState } from '../controllers/context'
import { downloadUserImportTemplate, exportExcel, parseUserImportFile } from '../models/excel'
import { formatDate, formatPhone } from '../models/format'
import { Modal, SearchField, StatusChip } from './ui'

export function UsersView() {
  const { users, busy } = useAppState()
  const controller = useAppController()
  const fileRef = useRef(null)
  const [query, setQuery] = useState('')
  const [pending, setPending] = useState(null)
  const [importPreview, setImportPreview] = useState(null)
  const [importResult, setImportResult] = useState(null)
  const [importError, setImportError] = useState('')
  const needle = query.trim().toLowerCase()
  const rows = users.filter((user) => !needle || `${user.name} ${user.phone}`.toLowerCase().includes(needle))

  async function onPickFile(event) {
    const file = event.target.files?.[0]
    event.target.value = ''
    if (!file) return
    setImportError('')
    setImportResult(null)
    try {
      const parsed = await parseUserImportFile(file)
      setImportPreview(parsed)
    } catch (error) {
      setImportPreview(null)
      setImportError(error.message || 'Lecture du fichier impossible.')
    }
  }

  return (
    <div className="stack">
      <div className="toolbar">
        <SearchField label="Nom ou numéro" value={query} onChange={setQuery} />
        <button
          type="button"
          className="ghost"
          onClick={() => exportExcel({
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
        >
          Exporter Excel
        </button>
        <button type="button" className="ghost" onClick={() => downloadUserImportTemplate()}>
          Modèle Excel
        </button>
        <button type="button" className="primary" disabled={busy} onClick={() => fileRef.current?.click()}>
          Importer Excel
        </button>
        <input
          ref={fileRef}
          type="file"
          accept=".xls,.csv,.txt,application/vnd.ms-excel,text/csv"
          hidden
          onChange={onPickFile}
        />
      </div>
      <p className="muted">
        {rows.length} compte{rows.length > 1 ? 's' : ''}. Pour un import : téléchargez le modèle, complétez Nom / Téléphone / Réseau / Statut, puis importez le fichier .xls ou CSV.
      </p>
      {importError ? <p className="error">{importError}</p> : null}
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
      {importPreview ? (
        <div className="modal-back" role="presentation" onClick={() => !busy && setImportPreview(null)}>
          <div className="modal wide" role="dialog" aria-modal="true" onClick={(event) => event.stopPropagation()}>
            <h3>Importer {importPreview.length} utilisateur{importPreview.length > 1 ? 's' : ''} ?</h3>
            <p className="muted">Vérifiez l’aperçu puis confirmez. Les numéros déjà présents seront signalés en erreur.</p>
            <div className="import-preview">
              <table>
                <thead>
                  <tr>
                    <th>Nom</th>
                    <th>Téléphone</th>
                    <th>Réseau</th>
                    <th>Statut</th>
                  </tr>
                </thead>
                <tbody>
                  {importPreview.slice(0, 12).map((row, index) => (
                    <tr key={`${row.phone}-${index}`}>
                      <td>{row.name || '—'}</td>
                      <td>{row.phone || '—'}</td>
                      <td>{row.network || 'auto'}</td>
                      <td>{row.status || 'actif'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {importPreview.length > 12 ? <p className="muted">… et {importPreview.length - 12} autre{importPreview.length - 12 > 1 ? 's' : ''}.</p> : null}
            </div>
            <div className="modal-actions">
              <button type="button" className="ghost" disabled={busy} onClick={() => setImportPreview(null)}>Annuler</button>
              <button
                type="button"
                className="primary"
                disabled={busy}
                onClick={async () => {
                  const rowsToImport = importPreview
                  setImportPreview(null)
                  const result = await controller.importUsers(rowsToImport)
                  if (result) setImportResult(result)
                }}
              >
                {busy ? 'Import…' : 'Confirmer l’import'}
              </button>
            </div>
          </div>
        </div>
      ) : null}
      {importResult ? (
        <div className="modal-back" role="presentation" onClick={() => setImportResult(null)}>
          <div className="modal wide" role="dialog" aria-modal="true" onClick={(event) => event.stopPropagation()}>
            <h3>Résultat de l’import</h3>
            <p>
              {importResult.created_count} créé{importResult.created_count > 1 ? 's' : ''}
              {importResult.error_count ? ` · ${importResult.error_count} erreur${importResult.error_count > 1 ? 's' : ''}` : ''}
            </p>
            {importResult.errors?.length ? (
              <div className="import-preview">
                <table>
                  <thead>
                    <tr>
                      <th>Ligne</th>
                      <th>Nom</th>
                      <th>Téléphone</th>
                      <th>Erreur</th>
                    </tr>
                  </thead>
                  <tbody>
                    {importResult.errors.map((item) => (
                      <tr key={`${item.row}-${item.phone}`}>
                        <td>{item.row}</td>
                        <td>{item.name || '—'}</td>
                        <td>{item.phone || '—'}</td>
                        <td>{item.error}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            ) : null}
            <div className="modal-actions">
              <button type="button" className="primary" onClick={() => setImportResult(null)}>Fermer</button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  )
}
