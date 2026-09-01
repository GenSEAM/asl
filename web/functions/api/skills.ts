export async function onRequestGet(context: any) {
  const url = new URL(context.request.url);
  const query = (url.searchParams.get("q") || "").toLowerCase();

  const skills = [
    {
      id: "asl-core",
      name: "AgentScript Language Core",
      category: "Code Generation & Wasm",
      description: "Official AgentScript SDK, compiler, and in-memory WebAssembly execution engine.",
      token_cost: 1100,
      platforms: ["Claude Code", "Cursor", "Antigravity", "Windsurf", "OpenDevin"],
      verified: true
    },
    {
      id: "asl-eddie",
      name: "EDDIE Swarm Orchestrator",
      category: "Swarm & Task Allocation",
      description: "3-layer superposition triage and consultative agent router with DAG scheduler.",
      token_cost: 1450,
      platforms: ["Claude Code", "Cursor", "Antigravity", "Windsurf"],
      verified: true
    },
    {
      id: "asl-voice",
      name: "Voice Stream Assistant",
      category: "Audio & Real-Time",
      description: "16kHz PCM duplex voice streaming assistant bridge connected to Layer 2 Consultative Router.",
      token_cost: 950,
      platforms: ["Claude Code", "Cursor", "Antigravity"],
      verified: true
    },
    {
      id: "asl-search",
      name: "SearXNG Web Search Engine",
      category: "Metasearch & Retrieval",
      description: "Zero-telemetry metasearch aggregator and proxy rotation pool for autonomous agents.",
      token_cost: 850,
      platforms: ["Claude Code", "Cursor", "Antigravity", "Windsurf", "OpenDevin"],
      verified: true
    },
    {
      id: "asl-mem",
      name: "Vector Memory & Embeddings",
      category: "Vector Database & Context",
      description: "In-memory cosine similarity and persistent episodic memory for multi-agent workflows.",
      token_cost: 1100,
      platforms: ["Claude Code", "Cursor", "Antigravity"],
      verified: true
    }
  ];

  const filtered = query
    ? skills.filter(s => s.name.toLowerCase().includes(query) || s.description.toLowerCase().includes(query) || s.category.toLowerCase().includes(query))
    : skills;

  return new Response(JSON.stringify({ total: filtered.length, skills: filtered }, null, 2), {
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": "public, max-age=60, s-maxage=300"
    }
  });
}
