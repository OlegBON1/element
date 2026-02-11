import type { FiberNode } from '../types'

const FIBER_KEY_PREFIXES = [
  '__reactFiber$',
  '__reactInternalInstance$',
] as const

export function getFiberFromElement(element: Element): FiberNode | null {
  const keys = Object.keys(element)
  for (const prefix of FIBER_KEY_PREFIXES) {
    const key = keys.find(k => k.startsWith(prefix))
    if (key) {
      return (element as unknown as Record<string, unknown>)[key] as FiberNode
    }
  }
  return null
}

export function findNearestFiberWithSource(fiber: FiberNode): FiberNode | null {
  let current: FiberNode | undefined = fiber
  while (current) {
    if (current._debugSource) {
      return current
    }
    current = current.return
  }
  return null
}

export function findOwnerFiberWithSource(fiber: FiberNode): FiberNode | null {
  let current: FiberNode | undefined = fiber._debugOwner
  while (current) {
    if (current._debugSource) {
      return current
    }
    current = current._debugOwner
  }
  return null
}

export function buildComponentTree(fiber: FiberNode): readonly string[] {
  const tree: string[] = []
  let current: FiberNode | undefined = fiber

  while (current) {
    const name = getComponentName(current)
    if (name && !tree.includes(name)) {
      tree.unshift(name)
    }
    current = current._debugOwner ?? current.return
  }

  return tree
}

function getComponentName(fiber: FiberNode): string | null {
  const type = fiber.type
  if (!type) return null
  if (typeof type === 'string') return null

  if (typeof type === 'function' || typeof type === 'object') {
    return resolveDisplayName(type as unknown as Record<string, unknown>)
  }

  return null
}

function resolveDisplayName(type: Record<string, unknown>): string | null {
  if (typeof type === 'function') {
    const fn = type as { displayName?: string; name?: string }
    return fn.displayName ?? fn.name ?? null
  }

  if (typeof type === 'object' && type !== null) {
    const obj = type as Record<string, unknown>

    if (obj.displayName && typeof obj.displayName === 'string') {
      return obj.displayName
    }

    if (obj.render && typeof obj.render === 'function') {
      const render = obj.render as { displayName?: string; name?: string }
      return render.displayName ?? render.name ?? null
    }

    if (obj.type && typeof obj.type === 'object') {
      return resolveDisplayName(obj.type as Record<string, unknown>)
    }
  }

  return null
}

export function isReactApp(): boolean {
  const rootKeys = Object.keys(document.documentElement)
  return rootKeys.some(k =>
    FIBER_KEY_PREFIXES.some(prefix => k.startsWith(prefix))
  ) || document.querySelector('[data-reactroot]') !== null
    || document.querySelector('#__next') !== null
    || document.querySelector('#root') !== null
}
