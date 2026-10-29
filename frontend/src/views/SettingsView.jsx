import { useState } from 'react'
import { useAppController, useAppState } from '../controllers/context'

function plain(value) {
  const number = Number(value)
  return Number.isInteger(number) ? String(number) : String(value ?? '')
}

export function SettingsView() {
  const { settings, busy } = useAppState()
  const controller = useAppController()
  const [fee, setFee] = useState(plain(settings?.fee_percent ?? 1))
  const [minutes, setMinutes] = useState(String(settings?.token_minutes ?? 30))
  const [rate, setRate] = useState(plain(settings?.usd_cdf_rate ?? 2880))
  const [appVersion, setAppVersion] = useState(settings?.app_version ?? '1.0.0')
  const [appMinVersion, setAppMinVersion] = useState(settings?.app_min_version ?? '1.0.0')
  const [appDownloadUrl, setAppDownloadUrl] = useState(settings?.app_download_url ?? '')
  const [appUpdateMessage, setAppUpdateMessage] = useState(
    settings?.app_update_message
      ?? 'Une nouvelle version de Fast-Cash est disponible. Téléchargez-la pour continuer.',
  )

  return (
    <form
      className="card form stack"
      onSubmit={(event) => {
        event.preventDefault()
        controller.saveSettings({
          fee,
          minutes,
          rate,
          appVersion,
          appMinVersion,
          appDownloadUrl,
          appUpdateMessage,
        })
      }}
    >
      <h3>Paramètres d’exploitation</h3>
      <p className="muted">Ces valeurs s’appliquent aux prochaines opérations.</p>
      <label>Frais de retrait (%)<input value={fee} onChange={(event) => setFee(event.target.value)} /><small>Entre 0 et 10</small></label>
      <label>Validité du jeton (minutes)<input value={minutes} onChange={(event) => setMinutes(event.target.value)} /><small>Entre 5 et 180</small></label>
      <label>Taux indicatif 1 USD en CDF<input value={rate} onChange={(event) => setRate(event.target.value)} /><small>Entre 100 et 20 000</small></label>

      <h3>Mise à jour de l’application mobile</h3>
      <p className="muted">Quand la version publiée est supérieure à celle installée, l’app affiche une popup avec le lien de téléchargement.</p>
      <label>Version publiée<input value={appVersion} onChange={(event) => setAppVersion(event.target.value)} placeholder="1.0.1" /><small>Ex. 1.0.1 — doit correspondre au versionName du nouvel APK</small></label>
      <label>Version minimale requise<input value={appMinVersion} onChange={(event) => setAppMinVersion(event.target.value)} placeholder="1.0.0" /><small>Sous cette version, la mise à jour est obligatoire</small></label>
      <label>Lien de téléchargement<input value={appDownloadUrl} onChange={(event) => setAppDownloadUrl(event.target.value)} placeholder="https://…/fast-cash.apk" /><small>URL HTTPS de l’APK ou de la fiche Play Store</small></label>
      <label>Message affiché<textarea value={appUpdateMessage} onChange={(event) => setAppUpdateMessage(event.target.value)} rows={3} /></label>

      <button type="submit" className="primary" disabled={busy}>{busy ? 'Enregistrement…' : 'Enregistrer les paramètres'}</button>
    </form>
  )
}
