(module asl-web/api-skills
  :d "Canonical Skills Hub metadata model for AgentScript web endpoints"
  :x [skill-catalog])

(df skill-catalog [] -> (List Any)
  :d "Returns list of modular skills"
  [
    (:id "asl-core" :name "AgentScript Language Core" :category "Code Generation & Wasm"
     :description "Official AgentScript SDK, compiler, and in-memory WebAssembly execution engine."
     :token_cost 1100 :platforms ["Claude Code" "Cursor" "Antigravity" "Windsurf" "OpenDevin"] :verified true)
    (:id "asl-addie" :name "ADDIE Swarm Orchestrator" :category "Swarm & Task Allocation"
     :description "3-layer superposition triage and consultative agent router with DAG scheduler."
     :token_cost 1450 :platforms ["Claude Code" "Cursor" "Antigravity" "Windsurf"] :verified true)
    (:id "asl-voice" :name "Voice Stream Assistant" :category "Audio & Real-Time"
     :description "16kHz PCM duplex voice streaming assistant bridge connected to Layer 2 Consultative Router."
     :token_cost 950 :platforms ["Claude Code" "Cursor" "Antigravity"] :verified true)
    (:id "asl-web-search" :name "SearXNG Web Search Engine" :category "Metasearch & Retrieval"
     :description "Zero-telemetry metasearch aggregator and proxy rotation pool for autonomous agents."
     :token_cost 850 :platforms ["Claude Code" "Cursor" "Antigravity" "Windsurf" "OpenDevin"] :verified true)
    (:id "asl-mem" :name "Vector Memory & Embeddings" :category "Vector Database & Context"
     :description "In-memory cosine similarity and persistent episodic memory for multi-agent workflows."
     :token_cost 1100 :platforms ["Claude Code" "Cursor" "Antigravity"] :verified true)
  ])
