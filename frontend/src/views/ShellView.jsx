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
  const state = useAppState()
  const controller = useAppController()
  const [menu, setMenu] = useState(false)
  const current = state.section === 'pdr-form' ? 'pdr' : state.section

  function choose(section) {
    controller.open(section)
    setMenu(false)
  }

  return (
    <div className="shell">
      {state.banner ? <p className="banner">{state.banner}</p> : null}
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
            <span className="sr">{titles[state.section]}</span>
            <div className="top-actions">
              <button type="button" className="icon" aria-label="Actualiser" onClick={() => controller.reload()}><Icon name="refresh" /></button>
              <div className="account">
                <span className="avatar">{initials(state.session.name)}</span>
                <span>
                  <b>{state.session.name}</b>
                  <small>{roleLabel(state.session.role)}</small>
                </span>
              </div>
            </div>
          </header>
          {state.error ? <p className="error bar">{state.error}</p> : null}
          {state.notice ? <p className="notice">{state.notice}</p> : null}
          <div className="page">
            {state.section !== 'dashboard' ? <header className="page-title"><h2>{titles[state.section]}</h2></header> : null}
            {state.section === 'dashboard' ? <DashboardView /> : null}
            {state.section === 'users' ? <UsersView /> : null}
            {state.section === 'pdr' || state.section === 'pdr-form' ? <PdrView /> : null}
            {state.section === 'operations' ? <OperationsView /> : null}
            {state.section === 'reports' ? <ReportsView /> : null}
            {state.section === 'team' ? <TeamView /> : null}
            {state.section === 'settings' ? <SettingsView /> : null}
          </div>
        </section>
      </div>
    </div>
  )
}
