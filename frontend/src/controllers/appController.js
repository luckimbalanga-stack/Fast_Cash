const STORAGE_KEY = 'fastcash-admin'

const emptyData = {
  dashboard: null,
  charts: null,
  users: [],
  pdrs: [],
  operations: [],
  team: [],
  reports: null,
  settings: null,
}

function readSession() {
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY)
    return raw ? JSON.parse(raw) : null
  } catch {
    return null
  }
}

function amount(raw, label) {
  const text = String(raw ?? '').trim().replace(/\s/g, '').replace(',', '.')
  if (!text) return 0
  const value = Number(text)
  if (!Number.isFinite(value) || value < 0) throw new Error(`${label} est invalide.`)
  return value
}

/** Contrôleur d'application : orchestre la session et les actions d'administration. */
export class AppController {
  constructor(model) {
    this.model = model
    this.listeners = new Set()
    const saved = readSession()
    this.token = saved?.token || null
    this.reportFrom = null
    this.reportTo = null
    this.state = {
      ready: !this.token,
      busy: false,
      error: '',
      notice: '',
      banner: '',
      session: saved?.admin || null,
      section: 'dashboard',
      pdrDraft: null,
      ...emptyData,
    }
  }

  getState = () => this.state

  subscribe = (listener) => {
    this.listeners.add(listener)
    return () => this.listeners.delete(listener)
  }

  setState(patch) {
    this.state = { ...this.state, ...patch }
    this.listeners.forEach((listener) => listener())
  }

  async run(action) {
    this.setState({ busy: true, error: '', notice: '' })
    try {
      await action()
      this.setState({ busy: false })
    } catch (error) {
      this.setState({ busy: false, error: error.message || 'Action impossible.' })
    }
  }

  async bootstrap() {
    try {
      const settings = await this.model.settings()
      this.setState({ banner: settings.banner || '', settings })
    } catch {
      /* La connexion reste possible même si le bandeau n'est pas chargé. */
    }
    if (!this.token) {
      this.setState({ ready: true })
      return
    }
    try {
      await this.refresh()
    } catch (error) {
      this.logout(error.message || 'Session expirée. Connectez-vous à nouveau.')
    }
  }

  async enter(email, password) {
    const cleaned = email.trim().toLowerCase()
    if (!cleaned.includes('@') || password.length < 8) {
      this.setState({ error: 'Indiquez l’e-mail et un mot de passe d’au moins 8 caractères.' })
      return
    }
    this.setState({ busy: true, error: '' })
    try {
      const result = await this.model.enter(cleaned, password)
      this.token = result.token
      sessionStorage.setItem(STORAGE_KEY, JSON.stringify({ token: result.token, admin: result.admin }))
      this.setState({ session: result.admin, section: 'dashboard' })
      await this.refresh()
    } catch (error) {
      this.token = null
      sessionStorage.removeItem(STORAGE_KEY)
      this.setState({ session: null, busy: false, error: error.message })
    }
  }

  logout(message = '') {
    this.token = null
    this.reportFrom = null
    this.reportTo = null
    sessionStorage.removeItem(STORAGE_KEY)
    this.setState({
      ...emptyData,
      session: null,
      pdrDraft: null,
      section: 'dashboard',
      busy: false,
      ready: true,
      notice: '',
      error: message,
    })
  }

  open(section) {
    this.setState({ section, pdrDraft: null, error: '', notice: '' })
  }

  openPdrForm(pdr = null) {
    this.setState({ section: 'pdr-form', pdrDraft: pdr, error: '', notice: '' })
  }

  async refresh() {
    const token = this.token
    const [dashboard, charts, users, pdrs, team, settings, operations, reports] = await Promise.all([
      this.model.dashboard(token),
      this.model.charts(token),
      this.model.users(token),
      this.model.pdrs(token),
      this.model.team(token),
      this.model.settings(),
      this.model.operations(token),
      this.reportFrom ? this.model.reports(token, this.reportFrom, this.reportTo) : Promise.resolve(this.state.reports),
    ])
    this.setState({
      dashboard,
      charts,
      users,
      pdrs,
      team,
      settings,
      operations,
      reports,
      banner: settings.banner || '',
      ready: true,
      busy: false,
    })
  }

  reload() {
    return this.run(() => this.refresh())
  }

  async loadReports(from, to) {
    this.reportFrom = from
    this.reportTo = to
    await this.run(async () => {
      const reports = await this.model.reports(this.token, from, to)
      this.setState({ reports })
    })
  }

  setUserStatus(id, status) {
    return this.run(async () => {
      await this.model.setUserStatus(this.token, id, status)
      await this.refresh()
      this.setState({ notice: status === 'active' ? 'Compte réactivé.' : 'Compte suspendu.' })
    })
  }

  savePdr(input) {
    return this.run(async () => {
      const name = input.name.trim()
      const manager = input.managerName.trim()
      const address = input.address.trim()
      const commune = input.commune.trim()
      const phone = input.phone.trim()
      const latitude = Number(String(input.lat).trim().replace(',', '.'))
      const longitude = Number(String(input.lng).trim().replace(',', '.'))
      const usd = amount(input.usd, 'Le montant USD')
      const cdf = amount(input.cdf, 'Le montant CDF')
      if (name.length < 2 || manager.length < 2 || address.length < 3 || commune.length < 2) {
        throw new Error('Complétez le nom, le responsable, l’adresse et la commune.')
      }
      if (phone.length !== 9 || !Number.isFinite(latitude) || !Number.isFinite(longitude)) {
        throw new Error('Vérifiez le numéro et les coordonnées.')
      }
      if (!input.networks.length) throw new Error('Sélectionnez au moins un réseau Mobile Money.')
      const body = {
        name,
        manager_name: manager,
        phone,
        address,
        commune,
        city: input.city.trim() || 'Kinshasa',
        lat: latitude,
        lng: longitude,
        networks: input.networks,
        status: input.active ? 'active' : 'inactive',
        is_open: input.open,
        accepts_deposits: input.deposits,
        opening_hours: input.hours.trim() || '07:00 - 20:00',
        usd_declared: usd,
        cdf_declared: cdf,
      }
      if (!input.id) {
        await this.model.createPdr(this.token, body)
      } else {
        await this.model.updatePdr(this.token, input.id, body)
        await this.model.setAvailability(this.token, input.id, {
          usd_declared: usd,
          cdf_declared: cdf,
          accepts_deposits: body.accepts_deposits,
          networks: body.networks,
          is_open: body.is_open,
        })
      }
      await this.refresh()
      this.setState({ section: 'pdr', pdrDraft: null, notice: input.id ? 'Point mis à jour.' : 'Point créé.' })
    })
  }

  deactivatePdr(id) {
    return this.run(async () => {
      await this.model.deactivatePdr(this.token, id)
      await this.refresh()
      this.setState({ section: 'pdr', pdrDraft: null, notice: 'Point désactivé.' })
    })
  }

  saveSettings(input) {
    const fee = Number(String(input.fee).replace(',', '.'))
    const minutes = Number(input.minutes)
    const rate = Number(String(input.rate).replace(/\s/g, '').replace(',', '.'))
    const appVersion = String(input.appVersion || '').trim()
    const appMinVersion = String(input.appMinVersion || '').trim()
    const appDownloadUrl = String(input.appDownloadUrl || '').trim()
    const appUpdateMessage = String(input.appUpdateMessage || '').trim()
    if (!Number.isFinite(fee) || !Number.isFinite(minutes) || !Number.isFinite(rate)) {
      this.setState({ error: 'Vérifiez les trois valeurs numériques.' })
      return Promise.resolve()
    }
    if (!appVersion || !appMinVersion) {
      this.setState({ error: 'Indiquez la version publiée et la version minimale.' })
      return Promise.resolve()
    }
    return this.run(async () => {
      const settings = await this.model.saveSettings(this.token, {
        fee_percent: fee,
        token_minutes: minutes,
        usd_cdf_rate: rate,
        app_version: appVersion,
        app_min_version: appMinVersion,
        app_download_url: appDownloadUrl,
        app_update_message: appUpdateMessage,
      })
      this.setState({ settings, banner: settings.banner || '', notice: 'Paramètres enregistrés.' })
    })
  }

  createMember(input) {
    const name = input.name.trim()
    const email = input.email.trim().toLowerCase()
    const password = input.password || ''
    if (name.length < 2 || !email.includes('@') || password.length < 8) {
      this.setState({ error: 'Indiquez un nom, un e-mail et un mot de passe d’au moins 8 caractères.' })
      return Promise.resolve()
    }
    return this.run(async () => {
      await this.model.createMember(this.token, { name, email, role: input.role, password })
      await this.refresh()
      this.setState({ notice: 'Administrateur ajouté.' })
    })
  }

  updateMember(id, body) {
    if (id === this.state.session?.id && body.status === 'suspended') {
      this.setState({ error: 'Vous ne pouvez pas suspendre votre propre accès.' })
      return Promise.resolve()
    }
    return this.run(async () => {
      await this.model.updateMember(this.token, id, body)
      await this.refresh()
      this.setState({ notice: 'Équipe mise à jour.' })
    })
  }
}
