import { describe, it, expect, beforeEach } from 'vitest'
import { extractSourceInfo } from '../src/react/source-extractor'
import type { FiberNode } from '../src/types'

function attachFiber(el: Element, fiber: FiberNode): void {
  const key = `__reactFiber$test123`
  ;(el as unknown as Record<string, unknown>)[key] = fiber
}

describe('extractSourceInfo', () => {
  beforeEach(() => {
    document.body.innerHTML = ''
  })

  it('extracts full source info from React fiber', () => {
    const el = document.createElement('button')
    el.textContent = 'Add to Cart'
    document.body.appendChild(el)

    const fiber: FiberNode = {
      _debugSource: {
        fileName: '/src/components/Button.tsx',
        lineNumber: 42,
        columnNumber: 5,
      },
      type: Object.assign(function Button() {}, { displayName: 'Button' }),
      _debugOwner: {
        type: Object.assign(function Header() {}, { displayName: 'Header' }),
        _debugOwner: {
          type: Object.assign(function App() {}, { displayName: 'App' }),
        },
      } as FiberNode,
    }
    attachFiber(el, fiber)

    const info = extractSourceInfo(el)

    expect(info).not.toBeNull()
    expect(info!.componentName).toBe('Button')
    expect(info!.filePath).toBe('/src/components/Button.tsx')
    expect(info!.lineNumber).toBe(42)
    expect(info!.columnNumber).toBe(5)
    expect(info!.componentTree).toEqual(['App', 'Header', 'Button'])
    expect(info!.tagName).toBe('button')
    expect(info!.textContent).toBe('Add to Cart')
  })

  it('walks up return chain when direct fiber has no source', () => {
    const el = document.createElement('span')
    document.body.appendChild(el)

    const parentFiber: FiberNode = {
      _debugSource: {
        fileName: '/src/Parent.tsx',
        lineNumber: 10,
      },
      type: Object.assign(function Parent() {}, { displayName: 'Parent' }),
    }
    const childFiber: FiberNode = {
      return: parentFiber,
      type: 'span',
    }
    attachFiber(el, childFiber)

    const info = extractSourceInfo(el)

    expect(info).not.toBeNull()
    expect(info!.filePath).toBe('/src/Parent.tsx')
    expect(info!.lineNumber).toBe(10)
  })

  it('returns fallback info for non-React elements', () => {
    const el = document.createElement('div')
    el.id = 'main'
    el.className = 'container wide'
    document.body.appendChild(el)

    const info = extractSourceInfo(el)

    expect(info).not.toBeNull()
    expect(info!.componentName).toBe('div#main.container.wide')
    expect(info!.filePath).toBe('')
    expect(info!.lineNumber).toBe(0)
    expect(info!.componentTree).toEqual([])
  })

  it('truncates long text content', () => {
    const el = document.createElement('p')
    el.textContent = 'A'.repeat(200)
    document.body.appendChild(el)

    const info = extractSourceInfo(el)

    expect(info).not.toBeNull()
    expect(info!.textContent!.length).toBeLessThanOrEqual(103) // 100 + "..."
  })

  it('handles null columnNumber gracefully', () => {
    const el = document.createElement('div')
    document.body.appendChild(el)

    const fiber: FiberNode = {
      _debugSource: {
        fileName: '/src/View.tsx',
        lineNumber: 5,
      },
      type: Object.assign(function View() {}, { displayName: 'View' }),
    }
    attachFiber(el, fiber)

    const info = extractSourceInfo(el)
    expect(info!.columnNumber).toBeNull()
  })
})
