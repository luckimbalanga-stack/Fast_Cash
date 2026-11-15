import { createContext, useContext, useRef, useSyncExternalStore } from 'react'

export const ControllerContext = createContext(null)

export function useAppController() {
  const controller = useContext(ControllerContext)
  if (!controller) throw new Error('Contrôleur indisponible.')
  return controller
}

/** Sans sélecteur : store entier. Avec sélecteur : ne re-rend que si la valeur change (Object.is). */
export function useAppState(selector) {
  const controller = useAppController()
  const select = selector || ((state) => state)
  const cached = useRef({ state: null, selected: null })
  return useSyncExternalStore(
    controller.subscribe,
    () => {
      const nextState = controller.getState()
      if (cached.current.state === nextState) return cached.current.selected
      const nextSelected = select(nextState)
      if (Object.is(cached.current.selected, nextSelected)) {
        cached.current.state = nextState
        return cached.current.selected
      }
      cached.current = { state: nextState, selected: nextSelected }
      return nextSelected
    },
    () => select(controller.getState()),
  )
}
