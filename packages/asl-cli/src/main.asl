(module asl-cli/main
  :d "Pure AgentScript CLI main dispatcher and entrypoint."
  :x [dispatch main]
  :i [(cli :a c)])

(df ! dispatch [(args (List Str))] -> (Result Unit Str)
  :d "Dispatches command-line arguments to the pure AgentScript CLI."
  (c/execute-cli args))

(df ! main [(args (List Str))] -> (Result Unit IoError)
  :d "Top-level main entrypoint for compiled pure ASL CLI."
  (c/main args))
