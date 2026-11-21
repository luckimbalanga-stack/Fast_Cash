import { useEffect, useMemo, useState } from 'react'
import { useAppController, useAppState } from '../controllers/context'

function plain(value) {
  const number = Number(value)
  return Number.isInteger(number) ? String(number) : String(value ?? '')
}

function money(value) {
  const number = Number(value)
  if (!Number.isFinite(number)) return '—'
  return number.toLocaleString('fr-FR', { maximumFractionDigits: 2 })
}

const DEFAULT_RANGE = { min_usd: '1', max_usd: '10000', cut_usd: '0.5' }

function normalizeRanges(list) {
  const rows = (list || []).map((row) => ({
    min_usd: plain(row.min_usd ?? ''),
    max_usd: plain(row.max_usd ?? ''),
    cut_usd: plain(row.cut_usd ?? ''),
  }))
  return rows.length ? rows : [{ ...DEFAULT_RANGE }]
}

export function SettingsView() {
  const { settings, busy } = useAppState()
  const controller = useAppController()
  const [tab, setTab] = useState('general')
  const [fee, setFee] = useState(plain(settings?.fee_percent ?? 1))
  const [minutes, setMinutes] = useState(String(settings?.token_minutes ?? 30))
  const [rate, setRate] = useState(plain(settings?.usd_cdf_rate ?? 2880))
  const [searchRadius, setSearchRadius] = useState(String(settings?.search_radius_m ?? 1000))
  const [pdrOfferSeconds, setPdrOfferSeconds] = useState(String(settings?.pdr_offer_seconds ?? 30))
  const [appVersion, setAppVersion] = useState(settings?.app_version ?? '1.0.0')
  const [appMinVersion, setAppMinVersion] = useState(settings?.app_min_version ?? '1.0.0')
  const [appDownloadUrl, setAppDownloadUrl] = useState(settings?.app_download_url ?? '')
  const [appUpdateMessage, setAppUpdateMessage] = useState(
    settings?.app_update_message
      ?? 'Une nouvelle version de Fast-Cash est disponible. Téléchargez-la pour continuer.',
  )
  const [ranges, setRanges] = useState(() => normalizeRanges(settings?.commission_ranges))

  const rateNumber = useMemo(() => {
    const value = Number(String(rate).replace(/\s/g, '').replace(',', '.'))
    return Number.isFinite(value) && value > 0 ? value : 2880
  }, [rate])

  useEffect(() => {
    if (!settings) return
    setFee(plain(settings.fee_percent ?? 1))
    setMinutes(String(settings.token_minutes ?? 30))
    setRate(plain(settings.usd_cdf_rate ?? 2880))
    setSearchRadius(String(settings.search_radius_m ?? 1000))
    setPdrOfferSeconds(String(settings.pdr_offer_seconds ?? 30))
    setAppVersion(settings.app_version ?? '1.0.0')
    setAppMinVersion(settings.app_min_version ?? '1.0.0')
    setAppDownloadUrl(settings.app_download_url ?? '')
    setAppUpdateMessage(
      settings.app_update_message
        ?? 'Une nouvelle version de Fast-Cash est disponible. Téléchargez-la pour continuer.',
    )
    setRanges(normalizeRanges(settings.commission_ranges))
  }, [settings])

  function updateRange(index, key, value) {
    setRanges((current) => current.map((row, i) => (i === index ? { ...row, [key]: value } : row)))
  }

  function addRange() {
    setRanges((current) => {
      const last = current[current.length - 1]
      const nextMin = last ? String(Number(String(last.max_usd).replace(',', '.')) + 1 || '') : '1'
      return [...current, { min_usd: nextMin, max_usd: '', cut_usd: '' }]
    })
  }

  function removeRange(index) {
    setRanges((current) => {
      if (current.length <= 1) return current
      return current.filter((_, i) => i !== index)
    })
  }

  function cutPercent(row) {
    const max = Number(String(row.max_usd).replace(',', '.'))
    const cut = Number(String(row.cut_usd).replace(',', '.'))
    if (!Number.isFinite(max) || max <= 0 || !Number.isFinite(cut)) return '—'
    return `${((cut / max) * 100).toFixed(2)} %`
  }

  return (
    <div className="stack">
      <div className="chips" role="tablist" aria-label="Paramètres">
        <button type="button" role="tab" className={tab === 'general' ? 'choice on' : 'choice'} aria-selected={tab === 'general'} onClick={() => setTab('general')}>
          Général
        </button>
        <button type="button" role="tab" className={tab === 'ranges' ? 'choice on' : 'choice'} aria-selected={tab === 'ranges'} onClick={() => setTab('ranges')}>
          Plages de commission
        </button>
      </div>
      <p className="muted">
        {tab === 'general'
          ? 'Tous les paramètres d’exploitation et de mise à jour de l’app.'
          : 'Au moins une plage est obligatoire — elle définit la coupe liquidité PDR à chaque retrait réussi.'}
      </p>

      {tab === 'general' ? (
        <form
          className="card form stack"
          onSubmit={(event) => {
            event.preventDefault()
            controller.saveSettings({
              fee,
              minutes,
              rate,
              searchRadius,
              pdrOfferSeconds,
              appVersion,
              appMinVersion,
              appDownloadUrl,
              appUpdateMessage,
            })
          }}
        >
          <h3>Paramètres d’exploitation</h3>
          <p className="muted">Ces valeurs s’appliquent aux prochaines opérations. La coupe liquidité PDR se règle dans l’onglet Plages de commission.</p>
          <label>
            Frais client / couverture liquidité (%)
            <input value={fee} onChange={(event) => setFee(event.target.value)} />
            <small>Entre 0 et 10 — frais affichés au client ; aussi seuil d’ouverture PDR (couverture vs volume du jour)</small>
          </label>
          <label>Validité du jeton (minutes)<input value={minutes} onChange={(event) => setMinutes(event.target.value)} /><small>Entre 5 et 180</small></label>
          <label>Taux indicatif 1 USD en CDF<input value={rate} onChange={(event) => setRate(event.target.value)} /><small>Entre 100 et 20 000 — sert aussi à convertir les plages de commission</small></label>
          <label>
            Rayon de recherche des PDR (mètres)
            <input value={searchRadius} onChange={(event) => setSearchRadius(event.target.value)} />
            <small>Entre 100 et 20 000 — utilisé pour la recherche client et le scan de zone</small>
          </label>
          <label>
            Délai d’acceptation PDR (secondes)
            <input value={pdrOfferSeconds} onChange={(event) => setPdrOfferSeconds(event.target.value)} />
            <small>Entre 5 et 120 — temps laissé à chaque PDR pour valider ou refuser avant le suivant</small>
          </label>

          <h3>Mise à jour de l’application mobile</h3>
          <p className="muted">Quand la version publiée est supérieure à celle installée, l’app affiche une popup avec le lien de téléchargement.</p>
          <label>Version publiée<input value={appVersion} onChange={(event) => setAppVersion(event.target.value)} placeholder="1.0.1" /><small>Ex. 1.0.1 — doit correspondre au versionName du nouvel APK</small></label>
          <label>Version minimale requise<input value={appMinVersion} onChange={(event) => setAppMinVersion(event.target.value)} placeholder="1.0.0" /><small>Sous cette version, la mise à jour est obligatoire</small></label>
          <label>Lien de téléchargement<input value={appDownloadUrl} onChange={(event) => setAppDownloadUrl(event.target.value)} placeholder="https://…/fast-cash.apk" /><small>URL HTTPS de l’APK ou de la fiche Play Store</small></label>
          <label>Message affiché<textarea value={appUpdateMessage} onChange={(event) => setAppUpdateMessage(event.target.value)} rows={3} /></label>

          <button type="submit" className="primary" disabled={busy}>{busy ? 'Enregistrement…' : 'Enregistrer les paramètres'}</button>
        </form>
      ) : (
        <form
          className="card form stack"
          onSubmit={(event) => {
            event.preventDefault()
            controller.saveCommissionRanges(ranges)
          }}
        >
          <h3>Plages de commission PDR</h3>
          <p className="muted">
            Pour un retrait entre X et Y USD, la plateforme coupe Z USD (converti en CDF au taux {money(rateNumber)}) dans la liquidité du PDR.
            Les plages ne doivent pas se chevaucher (ex. 1–10 puis 11–15).
          </p>

          <div className="stack" style={{ gap: 12 }}>
            {ranges.map((row, index) => {
              const minUsd = Number(String(row.min_usd).replace(',', '.'))
              const maxUsd = Number(String(row.max_usd).replace(',', '.'))
              const cutUsd = Number(String(row.cut_usd).replace(',', '.'))
              return (
                <div key={index} className="card" style={{ padding: 14, border: '1px solid #d7e0ea' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
                    <strong>Plage {index + 1}</strong>
                    <button type="button" className="ghost" onClick={() => removeRange(index)} disabled={ranges.length <= 1}>
                      Supprimer
                    </button>
                  </div>
                  <div className="grid-3" style={{ display: 'grid', gridTemplateColumns: 'repeat(3, minmax(0, 1fr))', gap: 10 }}>
                    <label>
                      X — min (USD)
                      <input value={row.min_usd} onChange={(event) => updateRange(index, 'min_usd', event.target.value)} />
                      <small>≈ {money(Number.isFinite(minUsd) ? minUsd * rateNumber : NaN)} CDF</small>
                    </label>
                    <label>
                      Y — max (USD)
                      <input value={row.max_usd} onChange={(event) => updateRange(index, 'max_usd', event.target.value)} />
                      <small>≈ {money(Number.isFinite(maxUsd) ? maxUsd * rateNumber : NaN)} CDF</small>
                    </label>
                    <label>
                      Z — coupe (USD)
                      <input value={row.cut_usd} onChange={(event) => updateRange(index, 'cut_usd', event.target.value)} />
                      <small>≈ {money(Number.isFinite(cutUsd) ? cutUsd * rateNumber : NaN)} CDF · {cutPercent(row)} du max</small>
                    </label>
                  </div>
                </div>
              )
            })}
          </div>

          <button type="button" className="ghost" onClick={addRange}>Ajouter une plage</button>
          <button type="submit" className="primary" disabled={busy}>{busy ? 'Enregistrement…' : 'Enregistrer les plages'}</button>
        </form>
      )}
    </div>
  )
}
