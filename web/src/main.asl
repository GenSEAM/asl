(module asl-web/main
  :d "Web Application Entrypoint & DOM Bootstrapper in pure AgentScript"
  :x [bootstrap-web main]
  :i [(core/strings :a s)
      (App :a app)])

(df bootstrap-web [(mount-id Str)] -> Str
  :d "Bootstraps application shell into browser DOM root element"
  (app/render-app "/"))

(df main [] -> I64
  :d "Main application initialization hook"
  (let [(shell (bootstrap-web "root"))]
    0))
