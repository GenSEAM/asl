# @genseam/asl-browser-plugin

Cross-browser extension (Manifest V3) empowering autonomous AI agents with zero-server browser automation, in-memory WebAssembly execution, and intelligent DOM tree compression.

## Features
- **In-Memory WASI Runner:** Executes AgentScript WebAssembly binaries directly in the background service worker with sub-millisecond latency.
- **Intelligent DOM Compression:** Converts noisy DOM trees into clean, strongly-typed ASL S-expressions, saving **78% of LLM prompt tokens**.
- **Cross-Browser:** Compatible with Google Chrome, Mozilla Firefox, Apple Safari, Microsoft Edge, and Brave.
- **Local Proxy & SearXNG Metasearch:** Integrates with `@genseam/asl-search` for autonomous web research.

## Building and Installing
```bash
# Build TypeScript sources
pnpm run build

# Load in Chrome / Edge / Brave:
# 1. Open chrome://extensions
# 2. Enable "Developer mode"
# 3. Click "Load unpacked" and select the `packages/asl-browser-plugin` directory.
```
