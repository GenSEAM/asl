(module asl-web/functions/api-plugins
  :d "Canonical Plugin Registry metadata model for AgentScript web endpoints"
  :x [plugin-catalog])

(df plugin-catalog [] -> (List Any)
  :d "Returns list of ecosystem plugins"
  [
    (:name "asl-github" :repo "github.com/GenSEAM/plugin-github" :capability "vcs"
     :description "Inspect repositories, read pull requests, and review diffs via GitHub API"
     :author "GenSEAM Core" :stars 142 :version "1.0.0")
    (:name "asl-slack" :repo "github.com/GenSEAM/plugin-slack" :capability "chat"
     :description "Autonomous message dispatch, channel listener, and thread summarization"
     :author "community/alex" :stars 98 :version "1.0.0")
    (:name "asl-postgres" :repo "github.com/GenSEAM/plugin-postgres" :capability "database"
     :description "Type-safe SQL query generation, schema inspection, and migration runner"
     :author "community/database-dao" :stars 215 :version "1.0.0")
    (:name "asl-linear" :repo "github.com/GenSEAM/plugin-linear" :capability "pm"
     :description "Issue tracking, sprint planning, and automated roadmap synchronization"
     :author "community/pm-tools" :stars 86 :version "1.0.0")
    (:name "asl-searxng" :repo "github.com/GenSEAM/search" :capability "search"
     :description "Zero-telemetry SearXNG metasearch aggregator and proxy rotation pool"
     :author "GenSEAM Core" :stars 310 :version "1.0.0")
  ])
