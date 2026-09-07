(module asl-web/cosmic-landscape-background
  :d "Declarative Cosmic Blueprint Background Component in pure AgentScript"
  :x [describe-cosmic-background render-cosmic-background]
  :i [(core/strings :a s)])

(df describe-cosmic-background [] -> Str
  :d "Returns blueprint grid and telemetry background specifications"
  "(background :type \"aerospace-blueprint\" :grid-size 40 :cycles 5 :perch [130 480])")

(df render-cosmic-background [] -> Str
  :d "Renders the cosmic landscape background markup"
  "<div class=\"fixed inset-0 pointer-events-none z-0 overflow-hidden opacity-30\"><svg class=\"w-full h-full\"><defs><pattern id=\"blueprintGrid\" width=\"40\" height=\"40\" patternUnits=\"userSpaceOnUse\"><path d=\"M 40 0 L 0 0 0 40\" fill=\"none\" stroke=\"#38bdf8\" stroke-width=\"0.5\" opacity=\"0.15\"/></pattern></defs><rect width=\"100%\" height=\"100%\" fill=\"url(#blueprintGrid)\"/></svg></div>")
