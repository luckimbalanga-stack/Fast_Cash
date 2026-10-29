import { createContext, useContext, useSyncExternalStore } from 'react'

export const ControllerContext = createContext(null)

export function useAppController() {
  const controller = useContext(ControllerContext)
  if (!controller) throw new Error('Contrôleur indisponible.')
  return controller
}

export function useAppState() {
  const controller = useAppController()
  return useSyncExternalStore(controller.subscribe, controller.getState, controller.getState)
}
