import type { ElementSourceInfo } from '../types'
import { extractSourceInfo } from '../react/source-extractor'
import {
  createOverlay,
  updateHighlight,
  hideHighlight,
  destroyOverlay,
  isOverlayElement,
} from './overlay'

type SelectCallback = (info: ElementSourceInfo) => void

interface SelectorState {
  readonly onSelect: SelectCallback
  active: boolean
}

let selectorState: SelectorState | null = null

export function startSelector(onSelect: SelectCallback): void {
  if (selectorState?.active) return

  createOverlay()

  selectorState = { onSelect, active: true }

  document.addEventListener('mousemove', handleMouseMove, true)
  document.addEventListener('click', handleClick, true)
  document.addEventListener('keydown', handleKeyDown, true)
}

export function stopSelector(): void {
  if (!selectorState) return

  selectorState.active = false

  document.removeEventListener('mousemove', handleMouseMove, true)
  document.removeEventListener('click', handleClick, true)
  document.removeEventListener('keydown', handleKeyDown, true)

  hideHighlight()
  destroyOverlay()

  selectorState = null
}

export function isActive(): boolean {
  return selectorState?.active ?? false
}

function handleMouseMove(event: MouseEvent): void {
  if (!selectorState?.active) return

  const target = document.elementFromPoint(event.clientX, event.clientY)
  if (!target || isOverlayElement(target)) return

  const info = extractSourceInfo(target)
  if (!info) return

  updateHighlight(info.elementRect, info.componentName)
}

function handleClick(event: MouseEvent): void {
  if (!selectorState?.active) return

  event.preventDefault()
  event.stopPropagation()
  event.stopImmediatePropagation()

  const target = document.elementFromPoint(event.clientX, event.clientY)
  if (!target || isOverlayElement(target)) return

  const info = extractSourceInfo(target)
  if (!info) return

  selectorState.onSelect(info)
}

function handleKeyDown(event: KeyboardEvent): void {
  if (!selectorState?.active) return

  if (event.key === 'Escape') {
    event.preventDefault()
    stopSelector()
  }
}
