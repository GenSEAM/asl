(module asl-web/navbar
  :d "Declarative navigation header component in pure AgentScript."
  :x [navbar-view]
  :i [])

(df navbar-view [] -> Str
  :d "Renders responsive navigation header with ecosystem links."
  "(nav (:class \"sticky top-0 z-50 backdrop-blur-md bg-surface/80 border-b border-line px-6 py-4 flex items-center justify-between\")
    (div (:class \"flex items-center gap-3\")
      (span (:class \"w-8 h-8 rounded-xl bg-signal flex items-center justify-center font-bold text-ground\") \"ASL\")
      (span (:class \"text-xl font-bold tracking-tight text-ink\") \"AgentScript\"))
    (div (:class \"flex items-center gap-6 text-sm font-medium text-ink-muted\")
      (a (:href \"#ecosystem\" :class \"hover:text-signal transition\") \"Ecosystem\")
      (a (:href \"#capabilities\" :class \"hover:text-signal transition\") \"Capabilities\")
      (a (:href \"#docs\" :class \"hover:text-signal transition\") \"Documentation\") (a (:href \"#blog\" :class \"hover:text-signal transition\") \"Blog\") (a (:href \"#roadmap\" :class \"hover:text-signal transition\") \"Roadmap\") (a (:href \"#playground\" :class \"hover:text-signal transition\") \"Playground\") (a (:href \"#studio\" :class \"hover:text-signal transition\") \"Studio\")
      (a (:href \"https://github.com/GenSEAM/asl\" :class \"px-4 py-2 rounded-xl bg-signal text-ground font-semibold hover:opacity-90 transition\") \"GitHub\")))")
