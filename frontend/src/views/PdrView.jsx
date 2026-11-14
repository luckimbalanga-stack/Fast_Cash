import { useState } from 'react'
import { useAppController, useAppState } from '../controllers/context'
import { exportExcel } from '../models/excel'
import { formatMoney, formatPhone } from '../models/format'
import { Modal, SearchField, StatusChip } from './ui'

const networks = [
  ['orange', 'Orange Money'],
  ['airtel', 'Airtel Money'],
  ['mpesa', 'M-Pesa'],
  ['afrimoney', 'AfriMoney'],
]

function blank(point) {
  return {
    id: point?.id || null,
    name: point?.name || '',
    managerName: point?.manager_name || '',
    phone: String(point?.phone || '').replace('+243', ''),
    password: '',
    address: point?.address || '',
    commune: point?.commune || '',
    city: point?.city || 'Kinshasa',
    hours: point?.opening_hours || '07:00 - 20:00',
    lat: point ? String(point.lat) : '-4.3038',
    lng: point ? String(point.lng) : '15.3005',
    usd: point ? String(point.usd_declared) : '0',
    cdf: point ? String(point.cdf_declared) : '0',
    networks: point?.networks?.length ? [...point.networks] : networks.map(([key]) => key),
    active: point ? point.status !== 'inactive' : true,
    open: point ? Boolean(point.is_open) : true,
    deposits: point ? Boolean(point.accepts_deposits) : true,
  }
}

export function PdrView() {
  const state = useAppState()
  const controller = useAppController()
  if (state.section === 'pdr-form') return <PdrForm draft={state.pdrDraft} />
  return <PdrList />
}

function PdrList() {
  const { pdrs, revealedPdrPassword, revealedPdrName } = useAppState()
  const controller = useAppController()
  const [query, setQuery] = useState('')
  const needle = query.trim().toLowerCase()
  const rows = pdrs.filter((point) => !needle || `${point.name} ${point.code} ${point.commune} ${point.manager_name}`.toLowerCase().includes(needle))

  return (
    <div className="stack">
      <div className="toolbar">
        <SearchField label="Nom, code ou commune" value={query} onChange={setQuery} />
        <button type="button" className="ghost" onClick={() => exportExcel({
          filename: 'fastcash-points-de-retrait.xls',
          sheet: 'Points de retrait',
          headers: ['Code', 'Nom', 'Responsable', 'Téléphone', 'Adresse', 'Commune', 'Ville', 'Horaires', 'USD disponible', 'CDF disponible', 'USD déclaré', 'CDF déclaré', 'Réseaux', 'Statut', 'Service', 'Dépôts', 'Note', 'Avis'],
          rows: rows.map((point) => [
            point.code,
            point.name,
            point.manager_name,
            formatPhone(point.phone),
            point.address,
            point.commune,
            point.city,
            point.opening_hours,
            point.usd_available,
            point.cdf_available,
            point.usd_declared,
            point.cdf_declared,
            (point.network_labels || []).join(', '),
            point.status === 'active' ? 'Actif' : 'Inactif',
            point.is_open ? 'En service' : 'Fermé',
            point.accepts_deposits ? 'Oui' : 'Non',
            point.rating_avg || 0,
            point.rating_count || 0,
          ]),
        })}
        >Exporter Excel</button>
        <button type="button" className="primary" onClick={() => controller.openPdrForm(null)}>Nouveau</button>
      </div>
      {rows.map((point) => (
        <button key={point.id} type="button" className="card row link" onClick={() => controller.openPdrForm(point)}>
          <div>
            <strong>{point.name}</strong>
            <span className="muted">{point.code} · {point.commune}</span>
            <span className="muted">{point.manager_name} · {formatPhone(point.phone)}</span>
            <b>{formatMoney(point.usd_available, 'USD')} · {formatMoney(point.cdf_available, 'CDF')}</b>
          </div>
          <div className="end">
            <StatusChip positive={point.status === 'active'}>{point.status === 'active' ? 'Actif' : 'Inactif'}</StatusChip>
            <span className={point.is_open ? 'up' : 'down'}>{point.is_open ? 'En service' : 'Fermé'}</span>
          </div>
        </button>
      ))}
      {revealedPdrPassword ? (
        <Modal
          title="Mot de passe du point"
          text={`${revealedPdrName || 'Ce point'} — conservez ce mot de passe pour la connexion mobile. L’envoi SMS sera branché plus tard.\n\n${revealedPdrPassword}`}
          confirmLabel="J’ai noté le mot de passe"
          onClose={() => controller.clearRevealedPdrPassword()}
          onConfirm={() => controller.clearRevealedPdrPassword()}
        />
      ) : null}
    </div>
  )
}

function PdrForm({ draft }) {
  const { busy, revealedPdrPassword } = useAppState()
  const controller = useAppController()
  const [form, setForm] = useState(() => blank(draft))
  const [confirm, setConfirm] = useState(false)
  const [resetConfirm, setResetConfirm] = useState(false)
  const set = (key, value) => setForm((current) => ({ ...current, [key]: value }))

  function toggleNetwork(key) {
    setForm((current) => ({
      ...current,
      networks: current.networks.includes(key) ? current.networks.filter((item) => item !== key) : [...current.networks, key],
    }))
  }

  return (
    <form className="stack card form" onSubmit={(event) => { event.preventDefault(); controller.savePdr(form) }}>
      <label>Nom du point<input value={form.name} onChange={(event) => set('name', event.target.value)} /></label>
      <label>Responsable<input value={form.managerName} onChange={(event) => set('managerName', event.target.value)} /></label>
      <label>Téléphone<input value={form.phone} inputMode="numeric" maxLength={9} onChange={(event) => set('phone', event.target.value.replace(/\D/g, '').slice(0, 9))} />
        <small>+243, 9 chiffres</small>
      </label>
      <label>
        Mot de passe de connexion
        <input
          type="text"
          value={form.password}
          autoComplete="new-password"
          onChange={(event) => set('password', event.target.value)}
          placeholder={form.id ? 'Laisser vide pour ne pas changer' : 'Au moins 8 caractères'}
        />
        <small>{form.id ? 'Optionnel en modification. Ou utilisez « Réinitialiser » ci-dessous.' : 'Requis — le PDR s’en sert pour se connecter dans l’app mobile.'}</small>
      </label>
      <label>Adresse<input value={form.address} onChange={(event) => set('address', event.target.value)} /></label>
      <div className="split">
        <label>Commune<input value={form.commune} onChange={(event) => set('commune', event.target.value)} /></label>
        <label>Ville<input value={form.city} onChange={(event) => set('city', event.target.value)} /></label>
      </div>
      <label>Horaires<input value={form.hours} onChange={(event) => set('hours', event.target.value)} /></label>
      <div className="split">
        <label>Latitude<input value={form.lat} onChange={(event) => set('lat', event.target.value)} /></label>
        <label>Longitude<input value={form.lng} onChange={(event) => set('lng', event.target.value)} /></label>
      </div>
      <div className="split">
        <label>Liquidités USD<input value={form.usd} onChange={(event) => set('usd', event.target.value)} /></label>
        <label>Liquidités CDF<input value={form.cdf} onChange={(event) => set('cdf', event.target.value)} /></label>
      </div>
      <fieldset>
        <legend>Réseaux acceptés</legend>
        <div className="chips">
          {networks.map(([key, label]) => (
            <label key={key} className={form.networks.includes(key) ? 'choice on' : 'choice'}>
              <input type="checkbox" checked={form.networks.includes(key)} onChange={() => toggleNetwork(key)} />
              {label}
            </label>
          ))}
        </div>
      </fieldset>
      <label className="check"><input type="checkbox" checked={form.active} onChange={(event) => set('active', event.target.checked)} /> Point actif</label>
      <label className="check"><input type="checkbox" checked={form.open} onChange={(event) => set('open', event.target.checked)} /> En service maintenant</label>
      <label className="check"><input type="checkbox" checked={form.deposits} onChange={(event) => set('deposits', event.target.checked)} /> Accepte les dépôts</label>
      <div className="modal-actions">
        <button type="button" className="ghost" onClick={() => controller.open('pdr')}>Retour</button>
        <button type="submit" className="primary" disabled={busy}>{busy ? 'Enregistrement…' : form.id ? 'Enregistrer' : 'Créer le point'}</button>
      </div>
      {form.id ? (
        <button type="button" className="ghost" disabled={busy} onClick={() => setResetConfirm(true)}>
          Réinitialiser le mot de passe
        </button>
      ) : null}
      {form.id && draft?.status === 'active' ? (
        <button type="button" className="ghost danger-text" disabled={busy} onClick={() => setConfirm(true)}>Désactiver ce point</button>
      ) : null}
      {confirm ? (
        <Modal
          title="Désactiver ce point ?"
          text={`${draft.name} n’apparaîtra plus dans la recherche et sera fermé.`}
          confirmLabel="Désactiver"
          onClose={() => setConfirm(false)}
          onConfirm={() => { setConfirm(false); controller.deactivatePdr(form.id) }}
        />
      ) : null}
      {resetConfirm ? (
        <Modal
          title="Réinitialiser le mot de passe ?"
          text="Un nouveau mot de passe sera généré et affiché ici (envoi SMS à brancher plus tard)."
          confirmLabel="Réinitialiser"
          onClose={() => setResetConfirm(false)}
          onConfirm={() => {
            setResetConfirm(false)
            controller.resetPdrPassword(form.id)
          }}
        />
      ) : null}
      {revealedPdrPassword ? (
        <Modal
          title="Nouveau mot de passe"
          text={`Communiquez ce mot de passe au responsable du point :\n\n${revealedPdrPassword}`}
          confirmLabel="J’ai noté le mot de passe"
          onClose={() => controller.clearRevealedPdrPassword()}
          onConfirm={() => controller.clearRevealedPdrPassword()}
        />
      ) : null}
    </form>
  )
}
