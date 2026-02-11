export interface ElementSourceInfo {
  readonly componentName: string
  readonly filePath: string
  readonly lineNumber: number
  readonly columnNumber: number | null
  readonly componentTree: readonly string[]
  readonly elementRect: {
    readonly x: number
    readonly y: number
    readonly width: number
    readonly height: number
  }
  readonly tagName: string
  readonly textContent: string | null
}

export interface FiberNode {
  readonly _debugSource?: {
    readonly fileName: string
    readonly lineNumber: number
    readonly columnNumber?: number
  }
  readonly _debugOwner?: FiberNode
  readonly type?: FiberComponentType
  readonly stateNode?: Element | null
  readonly return?: FiberNode
  readonly child?: FiberNode
  readonly sibling?: FiberNode
  readonly memoizedProps?: Record<string, unknown>
}

export type FiberComponentType =
  | string
  | FiberFunctionComponent
  | FiberClassComponent

interface FiberFunctionComponent {
  readonly displayName?: string
  readonly name?: string
  readonly $$typeof?: symbol
  readonly render?: FiberFunctionComponent
  readonly type?: FiberFunctionComponent
}

interface FiberClassComponent {
  readonly displayName?: string
  readonly name?: string
}

export interface InspectorConfig {
  readonly highlightColor: string
  readonly highlightBorderColor: string
  readonly labelBackground: string
  readonly labelColor: string
}

export interface SwiftBridgeMessage {
  readonly type: 'elementSelected' | 'inspectorEnabled' | 'inspectorDisabled' | 'error'
  readonly payload: ElementSourceInfo | { readonly message: string }
}

export const DEFAULT_CONFIG: InspectorConfig = {
  highlightColor: 'rgba(104, 182, 255, 0.25)',
  highlightBorderColor: 'rgba(104, 182, 255, 0.8)',
  labelBackground: '#1a73e8',
  labelColor: '#ffffff',
} as const
