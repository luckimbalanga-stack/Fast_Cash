import { useState } from 'react'
import { useAppController, useAppState } from '../controllers/context'
import { Mark } from './ui'

export function LoginView() {
  const state = useAppState()
  const controller = useAppController()
  const [email, setEmail] = useState('admin@fastcash.cd')
  const [password, setPassword] = useState('')

  function submit(event) {
    event.preventDefault()
    controller.enter(email, password)
  }

  return (
    <main className="login">
      {state.banner ? <p className="banner">{state.banner}</p> : null}
      <form className="login-card" onSubmit={submit}>
        <Mark variant="logo" />
        <p className="muted">Administration web. Votre argent, votre monnaie, à proximité.</p>
        <label>
          Adresse e-mail
          <input type="email" value={email} autoComplete="username" onChange={(event) => setEmail(event.target.value)} />
        </label>
        <label>
          Mot de passe
          <input type="password" value={password} autoComplete="current-password" onChange={(event) => setPassword(event.target.value)} />
        </label>
        {state.error ? <p className="error">{state.error}</p> : null}
        <button className="primary" type="submit" disabled={state.busy}>{state.busy ? 'Connexion…' : 'Entrer'}</button>
      </form>
    </main>
  )
}
