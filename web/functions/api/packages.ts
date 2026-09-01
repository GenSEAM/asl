export async function onRequestGet(context: any) {
  const packages = [
    { name: "@genseam/search", version: "1.0.0", repo: "https://github.com/GenSEAM/search", desc: "SearXNG metasearch engine" },
    { name: "@genseam/mem", version: "1.0.0", repo: "https://github.com/GenSEAM/mem", desc: "In-memory vector database and cosine similarity" },
    { name: "@genseam/fsm", version: "1.0.0", repo: "https://github.com/GenSEAM/fsm", desc: "Algebraic Finite State Machine engine" },
    { name: "@genseam/vdom", version: "1.0.0", repo: "https://github.com/GenSEAM/vdom", desc: "Declarative S-Expression Virtual DOM" },
    { name: "@genseam/harness", version: "1.0.0", repo: "https://github.com/GenSEAM/harness", desc: "Universal Multi-Modal Agent Harness" },
    { name: "@genseam/browser-plugin", version: "1.0.0", repo: "https://github.com/GenSEAM/browser-plugin", desc: "Browser Automation Controller" },
    { name: "@genseam/agent-bus", version: "1.0.0", repo: "https://github.com/GenSEAM/agent-bus", desc: "Inter-Agent Swarm Bus Protocol" },
    { name: "@genseam/eddie", version: "1.0.0", repo: "https://github.com/GenSEAM/eddie", desc: "3-Layer Superposition Swarm Orchestrator" },
    { name: "@genseam/voice", version: "1.0.0", repo: "https://github.com/GenSEAM/voice", desc: "Real-time Voice Stream Assistant" },
    { name: "@genseam/skills", version: "1.0.0", repo: "https://github.com/GenSEAM/skills", desc: "Universal Agent Skills Hub" }
  ];

  return new Response(JSON.stringify({ total: packages.length, packages }, null, 2), {
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": "public, max-age=60, s-maxage=300"
    }
  });
}
