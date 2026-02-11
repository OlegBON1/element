import type { ElementSourceInfo, FiberNode } from '../types'
import {
  getFiberFromElement,
  findNearestFiberWithSource,
  findOwnerFiberWithSource,
  buildComponentTree,
} from './fiber-walker'

export function extractSourceInfo(element: Element): ElementSourceInfo | null {
  const fiber = getFiberFromElement(element)
  if (!fiber) {
    return buildFallbackInfo(element)
  }

  const sourceFiber = findNearestFiberWithSource(fiber)
    ?? findOwnerFiberWithSource(fiber)

  if (!sourceFiber || !sourceFiber._debugSource) {
    return buildFallbackInfo(element)
  }

  const source = sourceFiber._debugSource
  const componentTree = buildComponentTree(sourceFiber)
  const componentName = deriveComponentName(sourceFiber, componentTree)
  const rect = element.getBoundingClientRect()

  return {
    componentName,
    filePath: source.fileName,
    lineNumber: source.lineNumber,
    columnNumber: source.columnNumber ?? null,
    componentTree,
    elementRect: {
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height,
    },
    tagName: element.tagName.toLowerCase(),
    textContent: truncateText(element.textContent, 100),
  }
}

function deriveComponentName(
  fiber: FiberNode,
  tree: readonly string[]
): string {
  const type = fiber.type
  if (type && typeof type !== 'string') {
    const obj = type as { displayName?: string; name?: string }
    if (obj.displayName) return obj.displayName
    if (obj.name) return obj.name
  }

  if (tree.length > 0) {
    return tree[tree.length - 1]
  }

  return 'Unknown'
}

function buildFallbackInfo(element: Element): ElementSourceInfo | null {
  const rect = element.getBoundingClientRect()
  const id = element.id ? `#${element.id}` : ''
  const classes = element.className && typeof element.className === 'string'
    ? `.${element.className.split(' ').filter(Boolean).join('.')}`
    : ''

  return {
    componentName: `${element.tagName.toLowerCase()}${id}${classes}`,
    filePath: '',
    lineNumber: 0,
    columnNumber: null,
    componentTree: [],
    elementRect: {
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height,
    },
    tagName: element.tagName.toLowerCase(),
    textContent: truncateText(element.textContent, 100),
  }
}

function truncateText(text: string | null, maxLen: number): string | null {
  if (!text) return null
  const trimmed = text.trim()
  if (trimmed.length <= maxLen) return trimmed
  return `${trimmed.slice(0, maxLen)}...`
}
