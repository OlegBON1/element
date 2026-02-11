import { describe, it, expect, beforeEach } from 'vitest'
import {
  getFiberFromElement,
  findNearestFiberWithSource,
  findOwnerFiberWithSource,
  buildComponentTree,
} from '../src/react/fiber-walker'
import type { FiberNode } from '../src/types'

function createMockFiber(overrides: Partial<FiberNode> = {}): FiberNode {
  return {
    _debugSource: undefined,
    _debugOwner: undefined,
    type: undefined,
    stateNode: null,
    return: undefined,
    child: undefined,
    sibling: undefined,
    ...overrides,
  }
}

function attachFiberToElement(element: Element, fiber: FiberNode): void {
  const key = `__reactFiber$abc123`
  ;(element as unknown as Record<string, unknown>)[key] = fiber
}

describe('getFiberFromElement', () => {
  beforeEach(() => {
    document.body.innerHTML = ''
  })

  it('returns fiber from element with __reactFiber$ key', () => {
    const el = document.createElement('div')
    const fiber = createMockFiber()
    attachFiberToElement(el, fiber)

    const result = getFiberFromElement(el)
    expect(result).toBe(fiber)
  })

  it('returns fiber from element with __reactInternalInstance$ key', () => {
    const el = document.createElement('div')
    const fiber = createMockFiber()
    const key = '__reactInternalInstance$xyz789'
    ;(el as unknown as Record<string, unknown>)[key] = fiber

    const result = getFiberFromElement(el)
    expect(result).toBe(fiber)
  })

  it('returns null for non-React element', () => {
    const el = document.createElement('div')
    expect(getFiberFromElement(el)).toBeNull()
  })
})

describe('findNearestFiberWithSource', () => {
  it('returns the fiber itself if it has source', () => {
    const fiber = createMockFiber({
      _debugSource: { fileName: '/src/Button.tsx', lineNumber: 42 },
    })

    expect(findNearestFiberWithSource(fiber)).toBe(fiber)
  })

  it('walks up return chain to find source', () => {
    const parent = createMockFiber({
      _debugSource: { fileName: '/src/App.tsx', lineNumber: 10 },
    })
    const child = createMockFiber({ return: parent })

    const result = findNearestFiberWithSource(child)
    expect(result).toBe(parent)
    expect(result?._debugSource?.fileName).toBe('/src/App.tsx')
  })

  it('returns null if no fiber in chain has source', () => {
    const fiber = createMockFiber({
      return: createMockFiber(),
    })

    expect(findNearestFiberWithSource(fiber)).toBeNull()
  })
})

describe('findOwnerFiberWithSource', () => {
  it('finds source in debug owner chain', () => {
    const owner = createMockFiber({
      _debugSource: { fileName: '/src/Layout.tsx', lineNumber: 5 },
    })
    const fiber = createMockFiber({ _debugOwner: owner })

    const result = findOwnerFiberWithSource(fiber)
    expect(result).toBe(owner)
  })

  it('returns null if no owner has source', () => {
    const fiber = createMockFiber({
      _debugOwner: createMockFiber(),
    })

    expect(findOwnerFiberWithSource(fiber)).toBeNull()
  })
})

describe('buildComponentTree', () => {
  it('builds tree from owner chain', () => {
    const root = createMockFiber({
      type: Object.assign(function App() {}, { displayName: 'App' }),
    })
    const layout = createMockFiber({
      type: Object.assign(function Layout() {}, { displayName: 'Layout' }),
      _debugOwner: root,
    })
    const button = createMockFiber({
      type: Object.assign(function Button() {}, { displayName: 'Button' }),
      _debugOwner: layout,
    })

    const tree = buildComponentTree(button)
    expect(tree).toEqual(['App', 'Layout', 'Button'])
  })

  it('skips HTML elements (string types)', () => {
    const parent = createMockFiber({
      type: Object.assign(function App() {}, { displayName: 'App' }),
    })
    const div = createMockFiber({
      type: 'div',
      _debugOwner: parent,
    })

    const tree = buildComponentTree(div)
    expect(tree).toEqual(['App'])
  })

  it('returns empty array for fiber with no named components', () => {
    const fiber = createMockFiber({ type: 'span' })
    expect(buildComponentTree(fiber)).toEqual([])
  })
})
