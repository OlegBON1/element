import type { ElementSourceInfo, InspectorConfig } from './types'
import { DEFAULT_CONFIG } from './types'
import { startSelector, stopSelector, isActive } from './inspector/selector'
import { isReactApp } from './react/fiber-walker'
import {
  sendToSwift,
  notifyInspectorEnabled,
  notifyInspectorDisabled,
  notifyError,
  isSwiftBridgeAvailable,
} from './bridge/swift-bridge'

export type { ElementSourceInfo, InspectorConfig }

let lastSelectedElement: ElementSourceInfo | null = null
let externalCallback: ((info: ElementSourceInfo) => void) | null = null

export function enable(config?: Partial<InspectorConfig>): void {
  const _config = config ? { ...DEFAULT_CONFIG, ...config } : DEFAULT_CONFIG

  void _config // config will be passed to overlay in future

  startSelector(handleElementSelected)
  notifyInspectorEnabled()
}

export function disable(): void {
  stopSelector()
  notifyInspectorDisabled()
}

export function toggle(): void {
  if (isActive()) {
    disable()
  } else {
    enable()
  }
}

export function getLastSelected(): ElementSourceInfo | null {
  return lastSelectedElement
}

export function onSelect(callback: (info: ElementSourceInfo) => void): void {
  externalCallback = callback
}

export function getStatus(): {
  readonly active: boolean
  readonly reactDetected: boolean
  readonly bridgeAvailable: boolean
} {
  return {
    active: isActive(),
    reactDetected: isReactApp(),
    bridgeAvailable: isSwiftBridgeAvailable(),
  }
}

function handleElementSelected(info: ElementSourceInfo): void {
  lastSelectedElement = info

  sendToSwift(info)

  if (externalCallback) {
    externalCallback(info)
  }

  if (!info.filePath) {
    notifyError(
      `No source info found for ${info.componentName}. ` +
      'Ensure the app is running in development mode with React source plugin enabled.'
    )
  }
}
