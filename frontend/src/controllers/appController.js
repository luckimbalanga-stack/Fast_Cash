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
    if (section !== 'reports') {
      this.reportFrom = null
      this.reportTo = null
    }
    this.setState({ section, pdrDraft: null, error: '', notice: '' })
    const key = section === 'pdr-form' ? 'pdr' : section
    return this.run(() => this.loadSection(key))
  }

  openPdrForm(pdr = null) {
    this.setState({ section: 'pdr-form', pdrDraft: pdr, error: '', notice: '' })
  }

  async loadDashboard(filters = {}) {
    const from = filters.from || this.pdrChartFrom || null
    const to = filters.to || this.pdrChartTo || null
    const network = filters.network ?? this.pdrChartNetwork ?? null
    this.pdrChartFrom = from
    this.pdrChartTo = to
    this.pdrChartNetwork = network
    const [dashboard, charts] = await Promise.all([
      this.model.dashboard(this.token),
      this.model.charts(this.token, { from, to, network }),
    ])
    this.setState({ dashboard, charts })
  }

  async loadPdrCharts(from, to, network) {
    this.pdrChartFrom = from
    this.pdrChartTo = to
    this.pdrChartNetwork = network || null
    await this.run(async () => {
      const charts = await this.model.charts(this.token, { from, to, network: this.pdrChartNetwork })
      this.setState({ charts })
    })
  }

  async loadUsers() {
    this.setState({ users: await this.model.users(this.token) })
  }

  async loadPdrs() {
    this.setState({ pdrs: await this.model.pdrs(this.token) })
  }

  async loadOperations() {
    this.setState({ operations: await this.model.operations(this.token) })
  }

  async loadTeam() {
    this.setState({ team: await this.model.team(this.token) })
  }

  async loadSettings() {
    const settings = await this.model.settings()
    this.setState({ settings, banner: settings.banner || '' })
  }

  async loadSection(section) {
    switch (section) {
      case 'dashboard':
        await this.loadDashboard()
        break
      case 'users':
        await this.loadUsers()
        break
      case 'pdr':
      case 'pdr-form':
        await this.loadPdrs()
        break
      case 'operations':
        await this.loadOperations()
        break
      case 'team':
        await this.loadTeam()
        break
      case 'settings':
        await this.loadSettings()
        break
      case 'reports':
        break
      default:
        await this.loadDashboard()
    }
  }

  async refresh() {
    const token = this.token
    const section = this.state.section === 'pdr-form' ? 'pdr' : this.state.section
    const settings = await this.model.settings()
    this.setState({ settings, banner: settings.banner || '' })
    await this.loadSection(section)
    if (section === 'reports' && this.reportFrom) {
      const reports = await this.model.reports(token, this.reportFrom, this.reportTo, this.reportNetwork)
      this.setState({ reports })
    }
    this.setState({ ready: true, busy: false })
  }

  reload() {
    return this.run(() => this.refresh())
  }

  async loadReports(from, to, network = null) {
    this.reportFrom = from
    this.reportTo = to
    this.reportNetwork = network || null
    await this.run(async () => {
      const reports = await this.model.reports(this.token, from, to, this.reportNetwork)
      this.setState({ reports })
    })
  }

  setUserStatus(id, status) {
    return this.run(async () => {
      await this.model.setUserStatus(this.token, id, status)
      await this.loadUsers()
      this.setState({ notice: status === 'active' ? 'Compte réactivé.' : 'Compte suspendu.' })
    })
  }

  importUsers(rows) {
    if (!Array.isArray(rows) || !rows.length) {
      this.setState({ error: 'Aucune ligne à importer.' })
      return Promise.resolve(null)
    }
    return this.run(async () => {
      const result = await this.model.importUsers(this.token, rows.map((row) => ({
        name: String(row.name || '').trim(),
        phone: String(row.phone || '').trim(),
        network: String(row.network || '').trim() || null,
        status: String(row.status || 'actif').trim() || 'actif',
      })))
      await this.loadUsers()
      const created = result?.created_count || 0
      const failed = result?.error_count || 0
      this.setState({
        notice: failed
          ? `${created} utilisateur${created > 1 ? 's' : ''} importé${created > 1 ? 's' : ''}, ${failed} ligne${failed > 1 ? 's' : ''} en erreur.`
          : `${created} utilisateur${created > 1 ? 's' : ''} importé${created > 1 ? 's' : ''}.`,
        userImportResult: result,
      })
      return result
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
      const password = String(input.password || '').trim()
      if (!input.id && password.length < 8) {
        throw new Error('Définissez un mot de passe d’au moins 8 caractères pour le point de retrait.')
      }
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
      let createdPassword = null
      if (!input.id) {
        body.password = password
        const created = await this.model.createPdr(this.token, body)
        createdPassword = created?.password || password
      } else {
        if (password.length >= 8) body.password = password
        await this.model.updatePdr(this.token, input.id, body)
        await this.model.setAvailability(this.token, input.id, {
          usd_declared: usd,
          cdf_declared: cdf,
          accepts_deposits: body.accepts_deposits,
          networks: body.networks,
          is_open: body.is_open,
        })
      }
      await this.loadPdrs()
      this.setState({
        section: 'pdr',
        pdrDraft: null,
        notice: input.id ? 'Point mis à jour.' : 'Point créé.',
        revealedPdrPassword: createdPassword,
      })
    })
  }

  async resetPdrPassword(id) {
    return this.run(async () => {
      const result = await this.model.resetPdrPassword(this.token, id, {})
      await this.loadPdrs()
      const nextPassword = result.password || null
      const draft = this.state.pdrDraft
      this.setState({
        notice: result.message || 'Mot de passe réinitialisé.',
        revealedPdrPassword: nextPassword,
        revealedPdrName: result.name || draft?.name || null,
        pdrDraft: draft && nextPassword ? { ...draft, password: nextPassword } : draft,
      })
      return result
    })
  }

  clearRevealedPdrPassword() {
    this.setState({ revealedPdrPassword: null, revealedPdrName: null })
  }

  deactivatePdr(id) {
    return this.run(async () => {
      await this.model.deactivatePdr(this.token, id)
      await this.loadPdrs()
      this.setState({ section: 'pdr', pdrDraft: null, notice: 'Point désactivé.' })
    })
  }

  saveSettings(input) {
    const fee = Number(String(input.fee).replace(',', '.'))
    const minutes = Number(input.minutes)
    const rate = Number(String(input.rate).replace(/\s/g, '').replace(',', '.'))
    const searchRadius = Number(String(input.searchRadius).replace(/\s/g, '').replace(',', '.'))
    const pdrOfferSeconds = Number(String(input.pdrOfferSeconds).replace(/\s/g, '').replace(',', '.'))
    const appVersion = String(input.appVersion || '').trim()
    const appMinVersion = String(input.appMinVersion || '').trim()
    const appDownloadUrl = String(input.appDownloadUrl || '').trim()
    const appUpdateMessage = String(input.appUpdateMessage || '').trim()
    if (!Number.isFinite(fee) || !Number.isFinite(minutes) || !Number.isFinite(rate) || !Number.isFinite(searchRadius) || !Number.isFinite(pdrOfferSeconds)) {
      this.setState({ error: 'Vérifiez les valeurs numériques.' })
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
        search_radius_m: Math.round(searchRadius),
        pdr_offer_seconds: Math.round(pdrOfferSeconds),
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
      await this.loadTeam()
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
      await this.loadTeam()
      this.setState({ notice: 'Équipe mise à jour.' })
    })
  }
}
