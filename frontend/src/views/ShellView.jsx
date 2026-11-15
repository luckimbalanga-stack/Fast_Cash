import { useState } from 'react'
import { useAppController, useAppState } from '../controllers/context'
import { roleLabel } from '../models/format'
import { DashboardView } from './DashboardView'
import { OperationsView } from './OperationsView'
import { PdrView } from './PdrView'
import { ReportsView } from './ReportsView'
import { SettingsView } from './SettingsView'
import { TeamView } from './TeamView'
import { UsersView } from './UsersView'
import { Icon, Mark } from './ui'

const items = [
  ['dashboard', 'Tableau de bord', 'grid'],
  ['users', 'Utilisateurs', 'users'],
  ['pdr', 'Points de retrait', 'pin'],
  ['operations', 'Transactions', 'swap'],
  ['reports', 'Rapports', 'chart'],
  ['team', 'Équipe', 'team'],
  ['settings', 'Paramètres', 'gear'],
]

function initials(name) {
  const parts = (name || '').trim().split(/\s+/).filter(Boolean)
  if (!parts.length) return 'FC'
  return parts.slice(0, 2).map((part) => part[0]).join('').toUpperCase()
}

const titles = {
  dashboard: 'Tableau de bord',
  users: 'Utilisateurs',
  pdr: 'Points de retrait',
  'pdr-form': 'Point de retrait',
  operations: 'Transactions',
  reports: 'Rapports',
  team: 'Équipe',
  settings: 'Paramètres',
}

export function ShellView() {
  const banner = useAppState((state) => state.banner)
  const section = useAppState((state) => state.section)
  const session = useAppState((state) => state.session)
  const error = useAppState((state) => state.error)
  const notice = useAppState((state) => state.notice)
  const controller = useAppController()
  const [menu, setMenu] = useState(false)
  const current = section === 'pdr-form' ? 'pdr' : section

  function choose(section) {
    controller.open(section)
    setMenu(false)
  }

  return (
    <div className="shell">
      {banner ? <p className="banner">{banner}</p> : null}
      <div className="frame">
        <aside className={menu ? 'side open' : 'side'}>
          <div className="brand">
            <Mark variant="lockup" />
          </div>
          <nav>
            {items.map(([id, label, icon]) => (
              <button key={id} type="button" className={current === id ? 'nav on' : 'nav'} aria-current={current === id ? 'page' : undefined} onClick={() => choose(id)}>
                <Icon name={icon} />
                {label}
              </button>
            ))}
          </nav>
          <button type="button" className="text-button logout" onClick={() => controller.logout()}><Icon name="logout" />Se déconnecter</button>
        </aside>
        {menu ? <button type="button" className="scrim" aria-label="Fermer le menu" onClick={() => setMenu(false)} /> : null}
        <section className="content">
          <header className="top">
            <button type="button" className="icon menu-button" aria-label="Ouvrir le menu" onClick={() => setMenu(true)}>☰</button>
            <span className="sr">{titles[section]}</span>
            <div className="top-actions">
              <button type="button" className="icon" aria-label="Actualiser" onClick={() => controller.reload()}><Icon name="refresh" /></button>
              <div className="account">
                <span className="avatar">{initials(session?.name)}</span>
                <span>
                  <b>{session?.name}</b>
                  <small>{roleLabel(session?.role)}</small>
                </span>
              </div>
            </div>
          </header>
          {error ? <p className="error bar">{error}</p> : null}
          {notice ? <p className="notice">{notice}</p> : null}
          <div className="page">
            {section !== 'dashboard' ? <header className="page-title"><h2>{titles[section]}</h2></header> : null}
            {section === 'dashboard' ? <DashboardView /> : null}
            {section === 'users' ? <UsersView /> : null}
            {section === 'pdr' || section === 'pdr-form' ? <PdrView /> : null}
            {section === 'operations' ? <OperationsView /> : null}
            {section === 'reports' ? <ReportsView /> : null}
            {section === 'team' ? <TeamView /> : null}
            {section === 'settings' ? <SettingsView /> : null}
          </div>
        </section>
      </div>
    </div>
  )
}
