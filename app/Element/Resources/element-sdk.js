var ElementSDK = (function (exports) {
    'use strict';

    const DEFAULT_CONFIG = {
        highlightColor: 'rgba(104, 182, 255, 0.25)',
        highlightBorderColor: 'rgba(104, 182, 255, 0.8)',
        labelBackground: '#1a73e8',
        labelColor: '#ffffff',
    };

    const FIBER_KEY_PREFIXES = [
        '__reactFiber$',
        '__reactInternalInstance$',
    ];
    function getFiberFromElement(element) {
        const keys = Object.keys(element);
        for (const prefix of FIBER_KEY_PREFIXES) {
            const key = keys.find(k => k.startsWith(prefix));
            if (key) {
                return element[key];
            }
        }
        return null;
    }
    function findNearestFiberWithSource(fiber) {
        let current = fiber;
        while (current) {
            if (current._debugSource) {
                return current;
            }
            current = current.return;
        }
        return null;
    }
    function findOwnerFiberWithSource(fiber) {
        let current = fiber._debugOwner;
        while (current) {
            if (current._debugSource) {
                return current;
            }
            current = current._debugOwner;
        }
        return null;
    }
    function buildComponentTree(fiber) {
        const tree = [];
        let current = fiber;
        while (current) {
            const name = getComponentName(current);
            if (name && !tree.includes(name)) {
                tree.unshift(name);
            }
            current = current._debugOwner ?? current.return;
        }
        return tree;
    }
    function getComponentName(fiber) {
        const type = fiber.type;
        if (!type)
            return null;
        if (typeof type === 'string')
            return null;
        if (typeof type === 'function' || typeof type === 'object') {
            return resolveDisplayName(type);
        }
        return null;
    }
    function resolveDisplayName(type) {
        if (typeof type === 'function') {
            const fn = type;
            return fn.displayName ?? fn.name ?? null;
        }
        if (typeof type === 'object' && type !== null) {
            const obj = type;
            if (obj.displayName && typeof obj.displayName === 'string') {
                return obj.displayName;
            }
            if (obj.render && typeof obj.render === 'function') {
                const render = obj.render;
                return render.displayName ?? render.name ?? null;
            }
            if (obj.type && typeof obj.type === 'object') {
                return resolveDisplayName(obj.type);
            }
        }
        return null;
    }
    function isReactApp() {
        const rootKeys = Object.keys(document.documentElement);
        return rootKeys.some(k => FIBER_KEY_PREFIXES.some(prefix => k.startsWith(prefix))) || document.querySelector('[data-reactroot]') !== null
            || document.querySelector('#__next') !== null
            || document.querySelector('#root') !== null;
    }

    function extractSourceInfo(element) {
        const fiber = getFiberFromElement(element);
        if (!fiber) {
            return buildFallbackInfo(element);
        }
        const sourceFiber = findNearestFiberWithSource(fiber)
            ?? findOwnerFiberWithSource(fiber);
        if (!sourceFiber || !sourceFiber._debugSource) {
            return buildFallbackInfo(element);
        }
        const source = sourceFiber._debugSource;
        const componentTree = buildComponentTree(sourceFiber);
        const componentName = deriveComponentName(sourceFiber, componentTree);
        const rect = element.getBoundingClientRect();
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
        };
    }
    function deriveComponentName(fiber, tree) {
        const type = fiber.type;
        if (type && typeof type !== 'string') {
            const obj = type;
            if (obj.displayName)
                return obj.displayName;
            if (obj.name)
                return obj.name;
        }
        if (tree.length > 0) {
            return tree[tree.length - 1];
        }
        return 'Unknown';
    }
    function buildFallbackInfo(element) {
        const rect = element.getBoundingClientRect();
        const id = element.id ? `#${element.id}` : '';
        const classes = element.className && typeof element.className === 'string'
            ? `.${element.className.split(' ').filter(Boolean).join('.')}`
            : '';
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
        };
    }
    function truncateText(text, maxLen) {
        if (!text)
            return null;
        const trimmed = text.trim();
        if (trimmed.length <= maxLen)
            return trimmed;
        return `${trimmed.slice(0, maxLen)}...`;
    }

    const OVERLAY_ID = '__element_inspector_overlay';
    const LABEL_ID = '__element_inspector_label';
    let state = null;
    function createOverlay(config = DEFAULT_CONFIG) {
        if (state)
            return;
        const container = document.createElement('div');
        container.id = OVERLAY_ID;
        Object.assign(container.style, {
            position: 'fixed',
            top: '0',
            left: '0',
            width: '100vw',
            height: '100vh',
            zIndex: '2147483647',
            pointerEvents: 'none',
        });
        const highlight = document.createElement('div');
        Object.assign(highlight.style, {
            position: 'absolute',
            backgroundColor: config.highlightColor,
            border: `2px solid ${config.highlightBorderColor}`,
            borderRadius: '3px',
            transition: 'all 0.1s ease-out',
            opacity: '0',
            pointerEvents: 'none',
        });
        const label = document.createElement('div');
        label.id = LABEL_ID;
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
        });
        container.appendChild(highlight);
        container.appendChild(label);
        document.body.appendChild(container);
        state = { container, highlight, label };
    }
    function updateHighlight(rect, componentName) {
        if (!state)
            return;
        Object.assign(state.highlight.style, {
            left: `${rect.x}px`,
            top: `${rect.y}px`,
            width: `${rect.width}px`,
            height: `${rect.height}px`,
            opacity: '1',
        });
        state.label.textContent = componentName;
        const labelX = rect.x;
        const labelY = rect.y > 28 ? rect.y - 28 : rect.y + rect.height + 4;
        Object.assign(state.label.style, {
            left: `${labelX}px`,
            top: `${labelY}px`,
            opacity: '1',
        });
    }
    function hideHighlight() {
        if (!state)
            return;
        state.highlight.style.opacity = '0';
        state.label.style.opacity = '0';
    }
    function destroyOverlay() {
        if (!state)
            return;
        state.container.remove();
        state = null;
    }
    function isOverlayElement(element) {
        if (!state)
            return false;
        return state.container.contains(element)
            || element.id === OVERLAY_ID
            || element.id === LABEL_ID;
    }

    let selectorState = null;
    function startSelector(onSelect) {
        if (selectorState?.active)
            return;
        createOverlay();
        selectorState = { onSelect, active: true };
        document.addEventListener('mousemove', handleMouseMove, true);
        document.addEventListener('click', handleClick, true);
        document.addEventListener('keydown', handleKeyDown, true);
    }
    function stopSelector() {
        if (!selectorState)
            return;
        selectorState.active = false;
        document.removeEventListener('mousemove', handleMouseMove, true);
        document.removeEventListener('click', handleClick, true);
        document.removeEventListener('keydown', handleKeyDown, true);
        hideHighlight();
        destroyOverlay();
        selectorState = null;
    }
    function isActive() {
        return selectorState?.active ?? false;
    }
    function handleMouseMove(event) {
        if (!selectorState?.active)
            return;
        const target = document.elementFromPoint(event.clientX, event.clientY);
        if (!target || isOverlayElement(target))
            return;
        const info = extractSourceInfo(target);
        if (!info)
            return;
        updateHighlight(info.elementRect, info.componentName);
    }
    function handleClick(event) {
        if (!selectorState?.active)
            return;
        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation();
        const target = document.elementFromPoint(event.clientX, event.clientY);
        if (!target || isOverlayElement(target))
            return;
        const info = extractSourceInfo(target);
        if (!info)
            return;
        selectorState.onSelect(info);
    }
    function handleKeyDown(event) {
        if (!selectorState?.active)
            return;
        if (event.key === 'Escape') {
            event.preventDefault();
            stopSelector();
        }
    }

    function sendToSwift(info) {
        const message = {
            type: 'elementSelected',
            payload: info,
        };
        postMessage(message);
    }
    function notifyInspectorEnabled() {
        postMessage({
            type: 'inspectorEnabled',
            payload: { message: 'Inspector mode activated' },
        });
    }
    function notifyInspectorDisabled() {
        postMessage({
            type: 'inspectorDisabled',
            payload: { message: 'Inspector mode deactivated' },
        });
    }
    function notifyError(error) {
        postMessage({
            type: 'error',
            payload: { message: error },
        });
    }
    function isSwiftBridgeAvailable() {
        return typeof window !== 'undefined'
            && window.webkit?.messageHandlers?.elementBridge !== undefined;
    }
    function postMessage(message) {
        try {
            const handler = window.webkit?.messageHandlers?.elementBridge;
            if (handler) {
                handler.postMessage(JSON.stringify(message));
            }
        }
        catch {
            // Silently fail when not in WKWebView context
        }
    }

    let lastSelectedElement = null;
    let externalCallback = null;
    function enable(config) {
        config ? { ...DEFAULT_CONFIG, ...config } : DEFAULT_CONFIG;
        startSelector(handleElementSelected);
        notifyInspectorEnabled();
    }
    function disable() {
        stopSelector();
        notifyInspectorDisabled();
    }
    function toggle() {
        if (isActive()) {
            disable();
        }
        else {
            enable();
        }
    }
    function getLastSelected() {
        return lastSelectedElement;
    }
    function onSelect(callback) {
        externalCallback = callback;
    }
    function getStatus() {
        return {
            active: isActive(),
            reactDetected: isReactApp(),
            bridgeAvailable: isSwiftBridgeAvailable(),
        };
    }
    function handleElementSelected(info) {
        lastSelectedElement = info;
        sendToSwift(info);
        if (externalCallback) {
            externalCallback(info);
        }
        if (!info.filePath) {
            notifyError(`No source info found for ${info.componentName}. ` +
                'Ensure the app is running in development mode with React source plugin enabled.');
        }
    }

    exports.disable = disable;
    exports.enable = enable;
    exports.getLastSelected = getLastSelected;
    exports.getStatus = getStatus;
    exports.onSelect = onSelect;
    exports.toggle = toggle;

    return exports;

})({});
