# Element

**Visual UI inspector that bridges your running app to Claude Code.**

Click any UI element in your running web, React Native, or iOS app — Element finds the source code and sends it directly to Claude Code. No more copy-pasting file paths or describing components manually.

```
You click a button  -->  Element finds the source  -->  Claude Code edits it
```

## How It Works

1. **Preview your app** inside Element (web via localhost, iOS via Simulator mirror)
2. **Click any element** — Element highlights it and extracts source location
3. **Write an instruction** (e.g., "make this button blue")
4. **Send to Claude Code** — the prompt includes file path, line number, code snippet, and your instruction

For **web apps** (React, Next.js, Vue), the SDK walks the React fiber tree to find `_debugSource` — the exact file and line where the component is defined.

For **iOS apps**, Element uses macOS Accessibility APIs to inspect the Simulator window and heuristic source mapping to locate SwiftUI/UIKit views.

## Architecture

```
Element.app (SwiftUI)
  |
  |-- WKWebView ............. Web app preview (localhost)
  |-- ScreenCaptureKit ...... iOS Simulator mirror
  |-- Metro WebSocket ....... React Native connection
  |
  |-- Dev Server Manager .... Start/stop dev servers per project
  |-- Element API Server .... localhost:7749 (for MCP)
  |-- Claude Code Session ... Direct subprocess via stream-json
  |                           (supports text + image attachments)
  v
MCP Server (optional) ....... Claude Code integration via MCP protocol
```

### Two Ways to Connect to Claude Code

**1. Direct Session (built-in):** Element launches Claude Code as a subprocess using `--input-format stream-json --output-format stream-json`. Prompts are sent directly via stdin. No extra setup needed.

**2. MCP Server:** For users who prefer the MCP integration, Element exposes a local API on port 7749. The included MCP server connects Claude Code to this API, enabling `/element` slash commands and tools like `get_selected_element`.

## Installation

### Prerequisites

| Requirement | Version | Purpose |
|-------------|---------|---------|
| **macOS** | 14.0+ (Sonoma) | Required OS version |
| **Xcode Command Line Tools** | Swift 5.9+ | Building the native app |
| **Node.js** | 18+ | Building the JS SDK and MCP server |
| **Claude Code** | Latest | AI coding assistant (`~/.local/bin/claude`) |
| **Go** | 1.21+ | Go bridge only (optional, not required for normal usage) |

### Step 1: Clone the Repository

```bash
git clone https://github.com/gokbeyinac/element.git
cd element
```

### Step 2: Build the JS SDK

The SDK detects UI elements in web apps by walking the React fiber tree. It must be built first because the macOS app bundles it.

```bash
cd sdk
npm install
npm run build
```

This produces `dist/element-sdk.js` which gets copied into the app bundle during build.

### Step 3: Build and Install the macOS App

```bash
cd ../app
chmod +x build-app.sh
./build-app.sh
```

The build script will:
1. Compile the Swift app with SPM (`swift build`)
2. Create a `.app` bundle with proper directory structure
3. Copy resources (JS SDK, app icon, Info.plist)
4. Sign the bundle with entitlements (ad-hoc for local development)
5. Install to `/Applications/Element.app`

### Step 4: Grant macOS Permissions

On first launch, macOS will prompt for permissions. You can also grant them manually:

1. Open **System Settings > Privacy & Security > Accessibility**
2. Click the **+** button and add **Element**
3. For iOS Simulator inspection, also grant **Screen Recording** permission

> **Note:** After granting Accessibility permission, you may need to restart Element for changes to take effect.

### Step 5: Launch Element

```bash
open /Applications/Element.app
```

### Optional: Install the MCP Server

If you want to use Element as an MCP tool inside Claude Code:

```bash
cd mcp
npm install
```

Add to your Claude Code MCP config (`~/.claude.json` or project `.mcp.json`):

```json
{
  "mcpServers": {
    "element": {
      "command": "node",
      "args": ["/absolute/path/to/element/mcp/index.js"]
    }
  }
}
```

### Optional: Build the Go Bridge

The Go bridge wraps any terminal AI assistant in a PTY and exposes an HTTP API. Useful for integrating with tools beyond Claude Code.

```bash
cd bridge
go build -o bin/element-bridge ./cmd/element-bridge
```

---

## Usage

### Adding a Project

1. Click **Add Project** in the sidebar (bottom-left)
2. Fill in the project details:

| Field | Description |
|-------|-------------|
| **Project Name** | Display name for the sidebar |
| **Platform** | Web (React/Next.js), React Native, SwiftUI, or UIKit |
| **Project Path** | Root directory of your project (use **Browse...** to select) |
| **Preview URL** | *(Web only)* Your dev server URL, e.g. `http://localhost:3000` |
| **Metro Port** | *(React Native only)* Metro bundler port, default `8081` |

> **Tip:** If you leave the project name empty and browse for a folder, Element will use the folder name automatically.

### Inspecting Elements

1. **Select a project** from the sidebar
2. **Start your dev server** (for web/React Native projects)
3. **Toggle the inspector** using the eye icon in the toolbar or press **⌘I**
4. **Hover over elements** in the preview — they'll be highlighted
5. **Click an element** to select it — Element extracts:
   - Component name
   - Source file path and line number
   - Code snippet around the definition
   - Component tree hierarchy

### Sending to Claude Code

1. After selecting an element, write your instruction in the text field (e.g., "make this button blue")
2. Optionally attach images using the **📎 paperclip** button (screenshots, design references)
3. Click **Send to Claude Code** or press **⌘Enter**
4. Element sends a structured prompt with the file path, code snippet, images, and your instruction directly to Claude Code

### Claude Session Status

The toolbar shows a colored dot indicating the Claude Code session state:

| Color | Meaning |
|-------|---------|
| 🟢 Green | Ready — session connected |
| 🔵 Blue | Processing — Claude Code is working |
| 🟡 Yellow | Starting — session initializing |
| 🔴 Red | Error — session failed |
| ⚪ Gray | Idle — no active session |

### Dev Server Controls

For **web projects**, the toolbar shows a play/stop button to start or stop the dev server directly from Element. Element infers the correct command based on the preview URL port (e.g., `npm run dev` for port 3000/5173).

### Image Attachments

You can attach images (PNG, JPG, WebP, GIF) alongside your text instructions. Click the paperclip icon in the instruction panel to add screenshots or design references. Images are sent as base64-encoded content to Claude Code for multimodal context. Max 5 images, 5MB each.

### Platform-Specific Setup

#### Web (React, Next.js, Vue)

1. Add the project with the **Web** platform type
2. Set the **Preview URL** to your localhost address (e.g., `http://localhost:3000`)
3. Start your dev server using the **▶ play button** in the toolbar, or manually (`npm run dev`, `next dev`, etc.)
4. Element loads your app in an embedded browser and injects the inspector SDK

**Important:** Your app must run in **development mode**. Production builds strip `_debugSource` metadata which Element uses to find source locations.

#### React Native

1. Start Metro bundler (`npx react-native start`)
2. Boot an iOS Simulator and run your app
3. Add the project with the **React Native** platform type
4. Set the **Metro Port** (default: `8081`)
5. Element connects to Metro via WebSocket and inspects the JS runtime

#### iOS (SwiftUI / UIKit)

1. Run your app in the **iOS Simulator** from Xcode
2. Add the project with **SwiftUI** or **UIKit** platform type
3. Set the **Project Path** to your Xcode project root
4. Element uses Accessibility APIs to inspect the Simulator and heuristic source mapping to locate views

> **Note:** Since Swift has no `_debugSource` equivalent, Element uses heuristic matching (accessibility identifiers, text content, view types). When confidence is low, it shows the top candidates for you to choose from.

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| **⌘I** | Toggle element inspector |
| **⌘Enter** | Send prompt to Claude Code |
| **Esc** | Cancel / dismiss |

---

## Configuration

Open **Settings** from the menu bar (**Element > Settings** or **⌘,**).

### General

| Setting | Default | Description |
|---------|---------|-------------|
| Enable inspection on project open | Off | Automatically enable the inspector when selecting a project |
| Show element selection notifications | On | Show a notification when an element is selected |

### Templates

Element uses prompt templates to format the context sent to Claude Code. Choose from three built-in templates or customize them:

| Template | Best For |
|----------|----------|
| **Default** | Elements with full source info (file path, code snippet) |
| **Minimal** | Quick one-line references for simple edits |
| **Inspector** | iOS elements inspected via Accessibility (no source mapping) |

Element automatically selects the best template based on the available element data. You can override this by selecting a template manually.

**Available template variables:**

| Variable | Description |
|----------|-------------|
| `{{componentName}}` | Component or view name |
| `{{filePath}}` | Source file path |
| `{{lineNumber}}` | Line number in source |
| `{{codeSnippet}}` | Code around the element definition |
| `{{componentTree}}` | Component hierarchy breadcrumb |
| `{{tagName}}` | HTML tag or view type |
| `{{textContent}}` | Text content of the element |
| `{{instruction}}` | Your instruction text |

---

## MCP Server

The MCP (Model Context Protocol) server lets Claude Code pull element data directly using tool calls.

### Available Tools

| Tool | Description |
|------|-------------|
| `get_selected_element` | Get the currently selected element's details |
| `get_element_context` | Get full context including rendered prompt |
| `get_projects` | List configured projects |
| `apply_to_element` | Get prompt for a custom instruction on selected element |
| `check_element_health` | Check if Element app is running |

### Available Prompts

| Prompt | Description |
|--------|-------------|
| `apply` | Pull selected element + instruction, ready for Claude Code to act on |

---

## Go Bridge

The Go bridge wraps any terminal AI assistant in a PTY and exposes an HTTP API for text injection.

```bash
# Start the bridge wrapping Claude Code
./bin/element-bridge -- claude

# Inject text via HTTP
curl -X POST http://localhost:9999/inject \
  -H "Content-Type: application/json" \
  -d '{"text": "Edit the Button component in src/App.tsx at line 42"}'
```

### Bridge API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/status` | GET | Bridge status + child process state |
| `/inject` | POST | Inject text into the terminal |
| `/queue` | DELETE | Clear injection queue |

## Project Structure

```
element/
├── app/                          # macOS native app (SwiftUI)
│   ├── Package.swift             # SPM manifest (macOS 14+)
│   ├── build-app.sh              # Build + bundle + sign + install
│   ├── Element.entitlements      # App sandbox disabled (for AX API)
│   └── Element/
│       ├── App/                  # App entry point, global state
│       ├── Models/               # ElementInfo, ProjectConfig, ImageAttachment
│       ├── Services/             # Core services
│       │   ├── ClaudeCodeSession # Direct Claude Code subprocess
│       │   ├── DevServerManager  # Dev server process management
│       │   ├── ElementAPIServer  # Local HTTP API for MCP
│       │   ├── Web/              # WKWebView + JS SDK injection
│       │   ├── ReactNative/      # Metro WebSocket + RN inspector
│       │   └── iOS/              # Simulator AX inspection
│       ├── Views/                # SwiftUI views
│       └── Resources/            # Info.plist, element-sdk.js
│
├── sdk/                          # Web element detection SDK
│   ├── src/
│   │   ├── inspector/            # Overlay + element selector
│   │   ├── react/                # Fiber walker, source extractor
│   │   └── bridge/               # webkit.messageHandlers bridge
│   ├── package.json
│   └── rollup.config.mjs        # Bundles to single IIFE file
│
├── bridge/                       # Go PTY bridge (optional)
│   ├── cmd/element-bridge/       # CLI entry point (Cobra)
│   └── internal/
│       ├── pty/                  # PTY lifecycle management
│       ├── server/               # HTTP server + handlers
│       ├── queue/                # FIFO injection queue
│       └── detector/             # Idle/busy pattern detection
│
└── mcp/                          # MCP server for Claude Code
    ├── index.js                  # MCP tools + prompts
    └── package.json
```

## How Element Detects Source Code

### Web (React, Next.js, Vue)

The JS SDK (`element-sdk.js`) is injected into the WKWebView preview. It:

- Walks the React fiber tree to find `_debugSource` metadata
- Extracts component name, file path, line number, and column number
- Highlights elements on hover, captures on click
- Sends data to Swift via `webkit.messageHandlers`

**Requirement:** Your app must run in dev mode. Production builds strip `_debugSource`.

### React Native

Element connects to the Metro dev server via WebSocket and uses the Chrome DevTools Protocol to access the JS runtime. It reads `_debugSource` from the React fiber tree, same as web.

### iOS (SwiftUI / UIKit)

Since Swift has no `_debugSource` equivalent, Element uses heuristic source mapping:

1. **Accessibility identifier** — searches for `.accessibilityIdentifier("id")` in source
2. **Text content** — matches `Text("...")` or `Button("...")` patterns
3. **View type** — maps AX roles to Swift types
4. **Class name** — finds UIKit class definitions

When confidence is low, Element shows the top candidates for the user to choose from.

## Development

### Building from Source

```bash
# Build everything
cd sdk && npm install && npm run build && cd ..
cd app && chmod +x build-app.sh && ./build-app.sh && cd ..

# Optional: build the Go bridge
cd bridge && go build -o bin/element-bridge ./cmd/element-bridge && cd ..

# Optional: install MCP server deps
cd mcp && npm install && cd ..
```

### Running Tests

```bash
# SDK tests
cd sdk && npm test

# SDK type checking
cd sdk && npm run typecheck
```

### Debug Logging

In debug builds, Element writes logs to `~/Library/Logs/Element/claude-session.log`. This is disabled in release builds.

## Permissions

Element requires these macOS permissions:

| Permission | Why |
|------------|-----|
| **Accessibility** | Inspect iOS Simulator UI elements via AXUIElement API |
| **Screen Recording** | Mirror iOS Simulator display via ScreenCaptureKit |
| **Local Networking** | Connect to localhost dev servers and run the API server |

The app sandbox is disabled (`Element.entitlements`) because the Accessibility API requires direct process access.

## Troubleshooting

**"Claude Code binary not found"**
Element looks for `claude` in `~/.local/bin/claude`, `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`, and falls back to `which claude`. Make sure Claude Code is installed.

**"No booted iOS Simulator found"**
Start an iOS Simulator from Xcode before using the iOS inspector.

**Accessibility permission not working**
After granting permission in System Settings, you may need to restart Element. If using the built app, make sure `/Applications/Element.app` is the version you granted access to.

**Web element click shows no source info**
Your app must be running in development mode. Production builds strip React `_debugSource` metadata. Check that your dev server is running on the localhost URL you configured.

## Contributing

Contributions are welcome. Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run existing tests (`cd sdk && npm test`)
5. Submit a pull request

## License

MIT
