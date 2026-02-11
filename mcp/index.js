#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const ELEMENT_API = "http://localhost:7749";

// ─── Helpers ────────────────────────────────────────────────────────────────

async function fetchElement(path) {
  const res = await fetch(`${ELEMENT_API}${path}`, {
    signal: AbortSignal.timeout(3000),
  });
  if (!res.ok) throw new Error(`Element API ${path} returned ${res.status}`);
  return res.json();
}

function textResult(content) {
  return { content: [{ type: "text", text: content }] };
}

function buildElementPrompt(data, instruction) {
  const el = data.element;
  const lines = [];

  if (el.filePath && el.lineNumber > 0) {
    lines.push(
      `Edit the ${el.componentName} component in ${el.filePath} at line ${el.lineNumber}.`
    );
    lines.push(``);
    lines.push(
      `Component tree: ${el.componentTree?.join(" → ") || el.componentName}`
    );
    if (el.codeSnippet) {
      lines.push(``, `Current code:`, "```", el.codeSnippet, "```");
    }
  } else {
    lines.push(
      `I selected a UI element in the running app via Element inspector:`
    );
    lines.push(``);
    lines.push(`- Type: ${el.tagName}`);
    lines.push(`- Component: ${el.componentName}`);
    lines.push(`- Text: ${el.textContent || "(empty)"}`);
    if (el.accessibilityIdentifier) {
      lines.push(`- Accessibility ID: ${el.accessibilityIdentifier}`);
    }
    lines.push(
      `- Frame: ${Math.round(el.frame.width)}×${Math.round(el.frame.height)} at (${Math.round(el.frame.x)}, ${Math.round(el.frame.y)})`
    );
    lines.push(
      `- Hierarchy: ${el.componentTree?.join(" → ") || el.componentName}`
    );
    if (el.childrenSummary?.length > 0) {
      lines.push(`- Children: ${el.childrenSummary.join(", ")}`);
    }
  }

  if (instruction) {
    lines.push(``, instruction);
  }

  return lines.join("\n");
}

// ─── MCP Server ─────────────────────────────────────────────────────────────

const server = new McpServer({
  name: "element",
  version: "1.1.0",
});

// ─── Prompt: element (slash command) ────────────────────────────────────────
// This appears as a slash command in Claude Code.
// Usage: /element in Claude Code to pull the selected element + instruction

server.prompt(
  "apply",
  "Pull the selected UI element and instruction from the Element inspector app. Use this when the user selects an element in Element and writes an instruction — it will fetch the element context and instruction, ready for you to act on.",
  {},
  async () => {
    try {
      const data = await fetchElement("/context");

      if (!data.hasSelectedElement) {
        return {
          messages: [
            {
              role: "user",
              content: {
                type: "text",
                text: "No element is currently selected in the Element inspector. Please select an element in Element first, then use this command again.",
              },
            },
          ],
        };
      }

      // Use the rendered prompt from Element if available, otherwise build one
      const prompt =
        data.renderedPrompt || buildElementPrompt(data, "Apply the changes.");

      return {
        messages: [
          {
            role: "user",
            content: {
              type: "text",
              text: prompt,
            },
          },
        ],
      };
    } catch (error) {
      return {
        messages: [
          {
            role: "user",
            content: {
              type: "text",
              text: `Cannot connect to Element app (localhost:7749). Make sure Element is running.\nError: ${error.message}`,
            },
          },
        ],
      };
    }
  }
);

// ─── Tool: get_selected_element ─────────────────────────────────────────────

server.tool(
  "get_selected_element",
  "Get the UI element currently selected in the Element inspector app. Returns detailed information about the element including type, text, component name, file path, line number, frame position, accessibility info, and children.",
  {},
  async () => {
    try {
      const data = await fetchElement("/selection");

      if (!data.selected) {
        return textResult(
          "No element is currently selected in Element. Select an element in the Element inspector first."
        );
      }

      const el = data.element;
      const lines = [
        `## Selected Element`,
        ``,
        `- **Type:** ${el.tagName}`,
        `- **Component:** ${el.componentName}`,
        `- **Text:** ${el.textContent || "(empty)"}`,
        `- **Platform:** ${el.platform}`,
      ];

      if (el.filePath) {
        lines.push(`- **File:** ${el.filePath}:${el.lineNumber}`);
      }
      if (el.accessibilityIdentifier) {
        lines.push(`- **Accessibility ID:** ${el.accessibilityIdentifier}`);
      }
      lines.push(
        `- **Frame:** ${Math.round(el.frame.width)}×${Math.round(el.frame.height)} at (${Math.round(el.frame.x)}, ${Math.round(el.frame.y)})`
      );

      if (el.componentTree?.length > 0) {
        lines.push(`- **Hierarchy:** ${el.componentTree.join(" → ")}`);
      }
      if (el.childrenSummary?.length > 0) {
        lines.push(`- **Children:** ${el.childrenSummary.join(", ")}`);
      }
      if (el.codeSnippet) {
        lines.push(``, `### Code`, "```", el.codeSnippet, "```");
      }

      return textResult(lines.join("\n"));
    } catch (error) {
      return textResult(
        `Cannot connect to Element app (localhost:7749). Make sure Element is running.\nError: ${error.message}`
      );
    }
  }
);

// ─── Tool: get_element_context ──────────────────────────────────────────────

server.tool(
  "get_element_context",
  "Get full context from Element app including the rendered prompt, selected project info, and selected element details. Use this to understand what the user is looking at in the Element inspector.",
  {},
  async () => {
    try {
      const data = await fetchElement("/context");

      const lines = [`## Element Context`, ``];

      if (data.projectName) {
        lines.push(`**Project:** ${data.projectName} (${data.platform})`);
        lines.push(`**Path:** ${data.projectPath}`);
      }

      lines.push(
        `**Inspector:** ${data.inspectionEnabled ? "Enabled" : "Disabled"}`
      );
      lines.push(
        `**Element Selected:** ${data.hasSelectedElement ? "Yes" : "No"}`
      );

      if (data.renderedPrompt) {
        lines.push(``, `### Rendered Prompt`, ``, data.renderedPrompt);
      }

      if (data.element) {
        const el = data.element;
        lines.push(
          ``,
          `### Element Details`,
          `- Type: ${el.tagName}`,
          `- Component: ${el.componentName}`,
          `- Text: ${el.textContent || "(empty)"}`
        );
        if (el.filePath) {
          lines.push(`- File: ${el.filePath}:${el.lineNumber}`);
        }
      }

      return textResult(lines.join("\n"));
    } catch (error) {
      return textResult(
        `Cannot connect to Element app (localhost:7749). Make sure Element is running.\nError: ${error.message}`
      );
    }
  }
);

// ─── Tool: get_projects ─────────────────────────────────────────────────────

server.tool(
  "get_projects",
  "List all projects configured in the Element inspector app.",
  {},
  async () => {
    try {
      const data = await fetchElement("/projects");

      if (!data.projects || data.projects.length === 0) {
        return textResult("No projects configured in Element.");
      }

      const lines = [`## Element Projects`, ``];
      for (const p of data.projects) {
        lines.push(`- **${p.name}** (${p.platform}) — ${p.path}`);
        if (p.url) lines.push(`  URL: ${p.url}`);
      }

      return textResult(lines.join("\n"));
    } catch (error) {
      return textResult(
        `Cannot connect to Element app (localhost:7749). Make sure Element is running.\nError: ${error.message}`
      );
    }
  }
);

// ─── Tool: apply_to_element ─────────────────────────────────────────────────

server.tool(
  "apply_to_element",
  "Get the selected element's prompt with a custom instruction. The instruction describes what change to make to the selected UI element. Returns the full rendered prompt ready to act on.",
  {
    instruction: z
      .string()
      .describe(
        "What to do with the selected element (e.g., 'change color to blue', 'make font larger', 'add a border')"
      ),
  },
  async ({ instruction }) => {
    try {
      const data = await fetchElement("/context");

      if (!data.hasSelectedElement) {
        return textResult(
          "No element selected in Element. Select an element first, then try again."
        );
      }

      return textResult(buildElementPrompt(data, instruction));
    } catch (error) {
      return textResult(
        `Cannot connect to Element app (localhost:7749). Make sure Element is running.\nError: ${error.message}`
      );
    }
  }
);

// ─── Tool: check_element_health ─────────────────────────────────────────────

server.tool(
  "check_element_health",
  "Check if the Element inspector app is running and accessible.",
  {},
  async () => {
    try {
      const data = await fetchElement("/health");
      return textResult(
        `Element app is running.\n- Status: ${data.status}\n- Version: ${data.version}`
      );
    } catch (error) {
      return textResult(
        `Element app is NOT reachable at localhost:7749.\nMake sure Element.app is running.\nError: ${error.message}`
      );
    }
  }
);

// ─── Start Server ───────────────────────────────────────────────────────────

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  process.stderr.write("[element-mcp] Server running on stdio (v1.1.0)\n");
}

main().catch((err) => {
  process.stderr.write(`[element-mcp] Fatal: ${err.message}\n`);
  process.exit(1);
});
