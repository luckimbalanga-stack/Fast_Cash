const iconPaths = {
  grid: 'M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z',
  users: 'M8 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM3 19c.4-2.4 2.4-4 5-4s4.6 1.6 5 4M16 11a2.5 2.5 0 1 0 0-5M16.2 15c1.8.3 3.2 1.5 3.8 4',
  pin: 'M12 21s6-5.2 6-10a6 6 0 1 0-12 0c0 4.8 6 10 6 10zM12 11.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3z',
  swap: 'M7 7h11M15 4l3 3-3 3M17 17H6M9 14l-3 3 3 3',
  chart: 'M4 19V5M4 19h16M8 15l3-4 3 2 4-6',
  team: 'M9 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM4 19c.5-2.5 2.6-4 5-4s4.5 1.5 5 4M17 8v6M14 11h6',
  gear: 'M12 15.5a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7zM12 3.5v2M12 18.5v2M4.9 6.4l1.5 1.5M17.6 16.1l1.5 1.5M3.5 12h2M18.5 12h2M4.9 17.6l1.5-1.5M17.6 7.9l1.5-1.5',
  down: 'M12 4v12M7 11l5 5 5-5',
  up: 'M12 20V8M7 13l5-5 5 5',
  clock: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM12 7v5l3 2',
  check: 'M5 12l5 5L20 7',
  close: 'M7 7l10 10M17 7L7 17',
  calendar: 'M5 6h14v14H5zM5 10h14M8 4v4M16 4v4',
  refresh: 'M20 12a8 8 0 1 1-2.2-5.5M20 4v5h-5',
  logout: 'M10 7V5h9v14h-9v-2M13 12H4M7 9l-3 3 3 3',
}

export function Icon({ name }) {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={iconPaths[name]} />
    </svg>
  )
}

export function Mark({ variant = 'pin' }) {
  const source = variant === 'logo' ? '/logo.png' : variant === 'lockup' ? '/lockup.png' : '/mark.png'
  return <img className={`mark ${variant}`} src={source} alt="Fast-Cash" />
}

export function Modal({ title, text, confirmLabel, onConfirm, onClose }) {
  return (
    <div className="modal-back" onClick={onClose} role="presentation">
      <div className="modal" role="dialog" aria-modal="true" aria-labelledby="modal-title" onClick={(event) => event.stopPropagation()}>
        <h3 id="modal-title">{title}</h3>
        <p>{text}</p>
        <div className="modal-actions">
          <button type="button" className="ghost" onClick={onClose}>Annuler</button>
          <button type="button" className="primary" onClick={onConfirm}>{confirmLabel}</button>
        </div>
      </div>
    </div>
  )
}

export function StatusChip({ positive, children }) {
  return <span className={positive ? 'chip ok' : 'chip no'}>{children}</span>
}

export function SearchField({ label, value, onChange }) {
  return (
    <label className="search">
      <span className="sr">{label}</span>
      <input value={value} placeholder={label} onChange={(event) => onChange(event.target.value)} />
    </label>
  )
}
