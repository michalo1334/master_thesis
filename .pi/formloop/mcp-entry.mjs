// Closing a Pi client must also stop its polling timers inside the shared container.
// The HTTP server is a separate process and keeps the forms in memory.
process.stdin.once("end", () => process.exit(0));
process.stdin.once("close", () => process.exit(0));
await import("./bin/mcp-server.mjs");
