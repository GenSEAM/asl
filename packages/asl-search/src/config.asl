(module aslWebApiSearch/config :x [SearchConfig resolveSearchConfig getEngineKey makeDefaultSearchConfig isEngineConfigured?] :i [])

(schema SearchConfig (:f openFirstDefault Bool) (:f braveKey (Option Str)) (:f tavilyKey (Option Str)) (:f serperKey (Option Str)) (:f searxngUrl (Option Str)))

fn makeDefaultSearchConfig -> SearchConfig
  (SearchConfig :openFirstDefault true :braveKey (none) :tavilyKey (none) :serperKey (none) :searxngUrl (none))

fn resolveSearchConfig brave: (Option Str) tavily: (Option Str) serper: (Option Str) searxng: (Option Str) openFirst: Bool -> SearchConfig
  (SearchConfig :openFirstDefault openFirst :braveKey brave :tavilyKey tavily :serperKey serper :searxngUrl searxng)

fn getEngineKey cfg: SearchConfig engine: Str -> (Option Str)
  (let [(e (stringLower engine))] (cond ((= e "brave") cfg.braveKey) ((= e "tavily") cfg.tavilyKey) ((= e "serper") cfg.serperKey) ((= e "searxng") cfg.searxngUrl) (else (none))))

fn isEngineConfigured? cfg: SearchConfig engine: Str -> Bool
  (let [(k (getEngineKey cfg engine))] (and (some? k) (!= (optionOr k "") "")))
