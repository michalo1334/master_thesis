import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const DEFAULT_TIMEOUTS: Readonly<Record<string, number>> = {
  bash: 300,
  ctx_execute: 600_000,
  ctx_execute_file: 600_000,
  ctx_batch_execute: 600_000,
};

export function applyDefaultTimeout(toolName: string, input: unknown): void {
  if (!input || typeof input !== "object" || Array.isArray(input)) return;

  const timeout = DEFAULT_TIMEOUTS[toolName];
  if (timeout === undefined) return;

  const args = input as Record<string, unknown>;
  if (args.timeout === undefined) args.timeout = timeout;
}

export default function toolTimeoutDefaults(pi: ExtensionAPI): void {
  pi.on("tool_call", (event) => {
    applyDefaultTimeout(event.toolName, event.input);
  });
}
