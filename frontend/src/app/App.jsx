import { useEffect, useMemo } from 'react'
import { AppController } from '../controllers/appController'
import { ControllerContext, useAppState } from '../controllers/context'
import { createAdminModel } from '../models/adminModel'
import { LoginView } from '../views/LoginView'
import { ShellView } from '../views/ShellView'

export function App() {
  const controller = useMemo(() => new AppController(createAdminModel()), [])
  useEffect(() => {
    controller.bootstrap()
  }, [controller])
  return (
    <ControllerContext.Provider value={controller}>
      <Root />
    </ControllerContext.Provider>
  )
}

function Root() {
  const state = useAppState()
  if (!state.ready) {
    return (
      <div className="boot">
        <img className="mark pin" src="/mark.png" alt="" />
        <p>Chargement de Fast-Cash…</p>
      </div>
    )
  }
  if (!state.session) return <LoginView />
  return <ShellView />
}
