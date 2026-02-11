import { describe, it, expect, beforeEach, vi } from 'vitest'
import {
  sendToSwift,
  isSwiftBridgeAvailable,
  notifyInspectorEnabled,
} from '../src/bridge/swift-bridge'
import type { ElementSourceInfo } from '../src/types'

describe('swift-bridge', () => {
  beforeEach(() => {
    delete (window as Record<string, unknown>).webkit
  })

  it('isSwiftBridgeAvailable returns false when no webkit', () => {
    expect(isSwiftBridgeAvailable()).toBe(false)
  })

  it('isSwiftBridgeAvailable returns true when handler exists', () => {
    ;(window as Record<string, unknown>).webkit = {
      messageHandlers: {
        elementBridge: { postMessage: vi.fn() },
      },
    }
    expect(isSwiftBridgeAvailable()).toBe(true)
  })

  it('sendToSwift posts message to handler', () => {
    const postMessage = vi.fn()
    ;(window as Record<string, unknown>).webkit = {
      messageHandlers: {
        elementBridge: { postMessage },
      },
    }

    const info: ElementSourceInfo = {
      componentName: 'Button',
      filePath: '/src/Button.tsx',
      lineNumber: 42,
      columnNumber: 5,
      componentTree: ['App', 'Button'],
      elementRect: { x: 0, y: 0, width: 100, height: 40 },
      tagName: 'button',
      textContent: 'Click',
    }

    sendToSwift(info)

    expect(postMessage).toHaveBeenCalledOnce()
    const message = JSON.parse(postMessage.mock.calls[0][0])
    expect(message.type).toBe('elementSelected')
    expect(message.payload.componentName).toBe('Button')
    expect(message.payload.filePath).toBe('/src/Button.tsx')
  })

  it('sendToSwift does not throw when bridge unavailable', () => {
    const info: ElementSourceInfo = {
      componentName: 'Test',
      filePath: '',
      lineNumber: 0,
      columnNumber: null,
      componentTree: [],
      elementRect: { x: 0, y: 0, width: 0, height: 0 },
      tagName: 'div',
      textContent: null,
    }

    expect(() => sendToSwift(info)).not.toThrow()
  })

  it('notifyInspectorEnabled sends correct message type', () => {
    const postMessage = vi.fn()
    ;(window as Record<string, unknown>).webkit = {
      messageHandlers: {
        elementBridge: { postMessage },
      },
    }

    notifyInspectorEnabled()

    const message = JSON.parse(postMessage.mock.calls[0][0])
    expect(message.type).toBe('inspectorEnabled')
  })
})
