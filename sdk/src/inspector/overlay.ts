import type { InspectorConfig } from '../types'
import { DEFAULT_CONFIG } from '../types'

const OVERLAY_ID = '__element_inspector_overlay'
const LABEL_ID = '__element_inspector_label'

interface OverlayState {
  readonly container: HTMLDivElement
  readonly highlight: HTMLDivElement
  readonly label: HTMLDivElement
}

let state: OverlayState | null = null

export function createOverlay(config: InspectorConfig = DEFAULT_CONFIG): void {
  if (state) return

  const container = document.createElement('div')
  container.id = OVERLAY_ID
  Object.assign(container.style, {
    position: 'fixed',
    top: '0',
    left: '0',
    width: '100vw',
    height: '100vh',
    zIndex: '2147483647',
    pointerEvents: 'none',
  })

  const highlight = document.createElement('div')
  Object.assign(highlight.style, {
    position: 'absolute',
    backgroundColor: config.highlightColor,
    border: `2px solid ${config.highlightBorderColor}`,
    borderRadius: '3px',
    transition: 'all 0.1s ease-out',
    opacity: '0',
    pointerEvents: 'none',
  })

  const label = document.createElement('div')
  label.id = LABEL_ID
  Object.assign(label.style, {
    position: 'absolute',
    backgroundColor: config.labelBackground,
    color: config.labelColor,
    padding: '2px 8px',
    borderRadius: '3px',
    fontSize: '12px',
    fontFamily: 'SF Mono, Menlo, Monaco, monospace',
    fontWeight: '600',
    whiteSpace: 'nowrap',
    opacity: '0',
    transition: 'opacity 0.1s ease-out',
    pointerEvents: 'none',
    boxShadow: '0 2px 8px rgba(0,0,0,0.15)',
  })

  container.appendChild(highlight)
  container.appendChild(label)
  document.body.appendChild(container)

  state = { container, highlight, label }
}

export function updateHighlight(
  rect: { x: number; y: number; width: number; height: number },
  componentName: string
): void {
  if (!state) return

  Object.assign(state.highlight.style, {
    left: `${rect.x}px`,
    top: `${rect.y}px`,
    width: `${rect.width}px`,
    height: `${rect.height}px`,
    opacity: '1',
  })

  state.label.textContent = componentName

  const labelX = rect.x
  const labelY = rect.y > 28 ? rect.y - 28 : rect.y + rect.height + 4

  Object.assign(state.label.style, {
    left: `${labelX}px`,
    top: `${labelY}px`,
    opacity: '1',
  })
}

export function hideHighlight(): void {
  if (!state) return

  state.highlight.style.opacity = '0'
  state.label.style.opacity = '0'
}

export function destroyOverlay(): void {
  if (!state) return

  state.container.remove()
  state = null
}

export function isOverlayElement(element: Element): boolean {
  if (!state) return false

  return state.container.contains(element)
    || element.id === OVERLAY_ID
    || element.id === LABEL_ID
}
