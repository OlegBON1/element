import type { SwiftBridgeMessage, ElementSourceInfo } from '../types'

interface WebKitMessageHandler {
  postMessage(message: string): void
}

interface WebKitBridge {
  messageHandlers?: {
    elementBridge?: WebKitMessageHandler
  }
}

declare global {
  interface Window {
    webkit?: WebKitBridge
  }
}

export function sendToSwift(info: ElementSourceInfo): void {
  const message: SwiftBridgeMessage = {
    type: 'elementSelected',
    payload: info,
  }
  postMessage(message)
}

export function notifyInspectorEnabled(): void {
  postMessage({
    type: 'inspectorEnabled',
    payload: { message: 'Inspector mode activated' },
  })
}

export function notifyInspectorDisabled(): void {
  postMessage({
    type: 'inspectorDisabled',
    payload: { message: 'Inspector mode deactivated' },
  })
}

export function notifyError(error: string): void {
  postMessage({
    type: 'error',
    payload: { message: error },
  })
}

export function isSwiftBridgeAvailable(): boolean {
  return typeof window !== 'undefined'
    && window.webkit?.messageHandlers?.elementBridge !== undefined
}

function postMessage(message: SwiftBridgeMessage): void {
  try {
    const handler = window.webkit?.messageHandlers?.elementBridge
    if (handler) {
      handler.postMessage(JSON.stringify(message))
    }
  } catch {
    // Silently fail when not in WKWebView context
  }
}
